"""numctx-verify: validate Ollama serves the context length Hermes config claims.

Hermes' own startup check looks at config.yaml's `context_length` and refuses
to start if it's below the 64K Hermes Agent minimum. But that check is on the
*config* value — it does NOT verify that Ollama is actually serving at that
length. Ollama defaults to ~2k-4k num_ctx when no PARAMETER num_ctx is set in
the modelfile, silently truncating inputs.

7 eval rounds (2026-04-30) were lost debugging "model capability ceiling"
symptoms (hallucinated paths, fabricated attestations, empty-command loops)
that all reduced to: the model literally couldn't see most of its prompt.
The fix is one PARAMETER num_ctx line in each Ollama modelfile. The bug is
hard to spot because everything LOOKS configured — Hermes config says 65536,
Pi config says 32768, but the served value is 4096.

This plugin queries each configured Ollama provider's modelfile via the
Ollama-native /api/show endpoint at session start, parses PARAMETER num_ctx,
and refuses to start if it's missing or below what the Hermes config claims.

Hard-fails via sys.exit(1) — SystemExit propagates past the broad-catch in
run_agent.py:9395 (which catches Exception, not BaseException).

See: ~/.claude/projects/-home-bob-ai-rig/memory/feedback_check_ollama_numctx.md
"""

import json
import logging
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# Hermes Agent's hardcoded minimum, used as the floor when a config's
# context_length isn't set or is below this value. Mirrors the check
# inside hermes-agent's startup.
_HERMES_MIN_NUM_CTX = 65536

# Probe timeout — Ollama /api/show is fast on a warm container; 5s is
# generous. On a cold container the first probe may take longer, but
# we'd rather fail than hang.
_PROBE_TIMEOUT_SEC = 5.0

_NUM_CTX_RE = re.compile(r"^PARAMETER\s+num_ctx\s+(\d+)\s*$", re.MULTILINE)


def _ollama_api_base(openai_base_url: str) -> str:
    """Translate an OpenAI-compat base_url (.../v1) to an Ollama-native
    base (no /v1). Returns the base for /api/show calls."""
    return openai_base_url.rstrip("/").removesuffix("/v1").rstrip("/")


def _query_modelfile(openai_base_url: str, model: str) -> Optional[str]:
    """Fetch the modelfile from Ollama's /api/show. Returns the raw modelfile
    string, or None on any failure (probe error, parse fail, non-Ollama
    endpoint). Failing open on probe errors avoids blocking startup on
    transient infrastructure issues, but a HARD config error (missing or
    too-low num_ctx) is caught at the parse step downstream."""
    api_base = _ollama_api_base(openai_base_url)
    url = f"{api_base}/api/show"
    body = json.dumps({"model": model}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=_PROBE_TIMEOUT_SEC) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            mf = data.get("modelfile", "")
            return mf if isinstance(mf, str) else ""
    except urllib.error.HTTPError as exc:
        # 404 likely means non-Ollama endpoint (no /api/show). Fail open.
        logger.debug("numctx-verify: %s returned HTTP %s — not an Ollama endpoint?",
                     url, exc.code)
        return None
    except Exception as exc:
        logger.debug("numctx-verify: probe %s failed: %s", url, exc)
        return None


def _parse_num_ctx(modelfile: str) -> Optional[int]:
    """Extract the PARAMETER num_ctx value from a modelfile. Returns None if
    no num_ctx line found (which is the bug we're catching — Ollama defaults
    to ~2k-4k when this is missing)."""
    if not modelfile:
        return None
    m = _NUM_CTX_RE.search(modelfile)
    if not m:
        return None
    try:
        return int(m.group(1))
    except (ValueError, TypeError):
        return None


def _verify_provider(
    label: str,
    base_url: str,
    model: str,
    expected_min: int,
) -> Optional[str]:
    """Verify one provider's served num_ctx meets the expected minimum.
    Returns an error message string on failure, or None on success/probe-skip."""
    modelfile = _query_modelfile(base_url, model)
    if modelfile is None:
        # Probe failure — fail open (don't block start on transient issues
        # or non-Ollama providers like anthropic/openai).
        logger.debug("numctx-verify: skipping %s — not Ollama or probe failed", label)
        return None
    num_ctx = _parse_num_ctx(modelfile)
    if num_ctx is None:
        return (
            f"Provider '{label}' (model={model} at {base_url}) has NO 'PARAMETER num_ctx' "
            f"in its modelfile. Ollama defaults to ~2k-4k context, will silently truncate "
            f"inputs. Fix: re-create the model with PARAMETER num_ctx >= {expected_min}.\n"
            f"   ollama create {model} -f - <<EOF\n"
            f"FROM {model}\n"
            f"PARAMETER num_ctx {expected_min}\n"
            f"EOF"
        )
    if num_ctx < expected_min:
        return (
            f"Provider '{label}' (model={model}) num_ctx={num_ctx} is BELOW required "
            f"{expected_min} (Hermes config / Hermes Agent minimum). Re-create the model "
            f"with PARAMETER num_ctx >= {expected_min}."
        )
    logger.info(
        "numctx-verify: %s/%s num_ctx=%d (>= %d) OK",
        label, model, num_ctx, expected_min,
    )
    return None


def _on_session_start(
    session_id: Optional[str] = None,
    model: Any = None,
    platform: str = "",
    **kwargs,
) -> None:
    """Validate every Ollama-backed provider before Hermes starts using them."""
    try:
        from hermes_cli.config import load_config
    except Exception as exc:
        logger.warning("numctx-verify: could not load config (%s); skipping check", exc)
        return

    try:
        cfg = load_config()
    except Exception as exc:
        logger.warning("numctx-verify: load_config() failed (%s); skipping check", exc)
        return

    if not isinstance(cfg, dict):
        return

    errors: List[str] = []

    # Primary model section: model.{default,model} + model.base_url + model.context_length
    model_cfg = cfg.get("model")
    if isinstance(model_cfg, dict):
        primary_model = (model_cfg.get("default") or model_cfg.get("model") or "")
        primary_url = (model_cfg.get("base_url") or "")
        # Use config's context_length if set, else Hermes minimum.
        try:
            primary_ctx = int(model_cfg.get("context_length") or _HERMES_MIN_NUM_CTX)
        except (TypeError, ValueError):
            primary_ctx = _HERMES_MIN_NUM_CTX
        primary_ctx = max(primary_ctx, _HERMES_MIN_NUM_CTX)
        if (isinstance(primary_model, str) and primary_model.strip()
                and isinstance(primary_url, str) and primary_url.strip()):
            err = _verify_provider(
                "model.default",
                primary_url.strip(),
                primary_model.strip(),
                primary_ctx,
            )
            if err:
                errors.append(err)

    # Named providers: providers.<name>.{base_url, model, context_length}
    providers = cfg.get("providers")
    if isinstance(providers, dict):
        for pname, pcfg in providers.items():
            if not isinstance(pcfg, dict):
                continue
            base_url = (pcfg.get("base_url") or "")
            model_id = (pcfg.get("model") or "")
            try:
                expected = int(pcfg.get("context_length") or _HERMES_MIN_NUM_CTX)
            except (TypeError, ValueError):
                expected = _HERMES_MIN_NUM_CTX
            expected = max(expected, _HERMES_MIN_NUM_CTX)
            if (not isinstance(base_url, str) or not base_url.strip()
                    or not isinstance(model_id, str) or not model_id.strip()):
                continue
            err = _verify_provider(
                f"providers.{pname}",
                base_url.strip(),
                model_id.strip(),
                expected,
            )
            if err:
                errors.append(err)

    if errors:
        sys.stderr.write("\n=== numctx-verify: REFUSING TO START ===\n")
        for e in errors:
            sys.stderr.write(f"\n  [X] {e}\n")
        sys.stderr.write(
            "\n"
            "Why this matters: Ollama silently truncates inputs to its modelfile's\n"
            "num_ctx. Hermes config's context_length is aspirational; only the\n"
            "modelfile counts. Past evals burned 7 rounds debugging the symptoms.\n"
            "See ~/.claude/projects/-home-bob-ai-rig/memory/feedback_check_ollama_numctx.md\n\n"
        )
        sys.exit(1)


def register(ctx) -> None:
    """Plugin entry point — wires the on_session_start verification."""
    ctx.register_hook("on_session_start", _on_session_start)
    logger.info("numctx-verify: on_session_start hook registered")
