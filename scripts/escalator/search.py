"""Web search via DuckDuckGo HTML scrape.

No API key needed — DDG's HTML interface is plain HTTP. Per work-loop
SKILL.md:388-397 we want titles + snippets from top results, then feed
them into the next devstral nudge or the Advisor's diagnostic context.
"""

from __future__ import annotations

import re
import subprocess
import urllib.parse
from dataclasses import dataclass


DDG_HTML_URL = "https://html.duckduckgo.com/html/"
# Minimal UA. Empirically: full Chrome UA strings get DDG's anti-bot empty
# homepage (14k bytes, 0 results), but bare "Mozilla/5.0" returns the real
# result list (~28k bytes, 10 results). Counter-intuitive but consistent.
USER_AGENT = "Mozilla/5.0"


@dataclass
class SearchResult:
    title: str
    url: str
    snippet: str


_RESULT_BLOCK_RE = re.compile(
    r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>'
    r'.*?<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
    re.DOTALL,
)
_TAG_STRIP_RE = re.compile(r"<[^>]+>")


def _strip_html(text: str) -> str:
    return _TAG_STRIP_RE.sub("", text).strip()


def search(query: str, *, max_results: int = 5, timeout_sec: int = 30) -> list[SearchResult]:
    """Return up to `max_results` from DuckDuckGo HTML.

    Uses POST (DDG's GET on html.duckduckgo.com returns just the homepage
    shell, no results — only POST returns the result list). Failures
    (network, parse, timeout) return an empty list — the chain falls
    through to the next tier rather than aborting.
    """
    body = urllib.parse.urlencode({"q": query, "kl": "us-en"})
    try:
        proc = subprocess.run(
            [
                "curl",
                "--silent",
                "--show-error",
                "--max-time",
                str(timeout_sec),
                "-A",
                USER_AGENT,
                "-X",
                "POST",
                "-d",
                body,
                DDG_HTML_URL,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return []
    if proc.returncode != 0 or not proc.stdout:
        return []

    out: list[SearchResult] = []
    for match in _RESULT_BLOCK_RE.finditer(proc.stdout):
        href = match.group(1)
        title_html = match.group(2)
        snippet_html = match.group(3)
        title = _strip_html(title_html)
        snippet = _strip_html(snippet_html)
        # DDG sometimes wraps real URLs in a redirector. Extract uddg= param.
        if "uddg=" in href:
            try:
                href = urllib.parse.unquote(href.split("uddg=", 1)[1].split("&", 1)[0])
            except Exception:
                pass
        if title and snippet:
            out.append(SearchResult(title=title, url=href, snippet=snippet))
        if len(out) >= max_results:
            break
    return out


def format_results_for_prompt(results: list[SearchResult]) -> str:
    """Render results as a compact block suitable for embedding in a Pi
    prompt. Keeps each result short to preserve context budget."""
    if not results:
        return "(no web results found)"
    lines: list[str] = []
    for i, r in enumerate(results, 1):
        lines.append(f"{i}. {r.title}")
        lines.append(f"   {r.url}")
        # Truncate snippet to keep prompt budget tight.
        snippet = r.snippet[:300]
        lines.append(f"   {snippet}")
    return "\n".join(lines)
