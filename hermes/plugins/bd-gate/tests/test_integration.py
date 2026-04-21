"""Integration test — drive the gate through Hermes's real plugin manager.

Uses get_pre_tool_call_block_message() (the exact enforcement path
model_tools.py:454-472 calls at tool-dispatch time). A live Hermes session
would take the same code path, so a PASS here means the plugin will fire.
"""
import os
import subprocess
import sys
from pathlib import Path

# Run each probe against /tmp/bd-gate-smoketest so the git state is known.
REPO = "/tmp/bd-gate-smoketest"
os.chdir(REPO)

sys.path.insert(0, str(Path.home() / ".hermes" / "hermes-agent"))

from hermes_cli.plugins import (  # type: ignore
    discover_plugins,
    get_pre_tool_call_block_message,
    get_plugin_manager,
)

discover_plugins()

mgr = get_plugin_manager()
loaded = getattr(mgr, "_loaded", getattr(mgr, "plugins", None))
if isinstance(loaded, dict):
    print("Loaded plugins:", list(loaded.keys()))
elif isinstance(loaded, list):
    print("Loaded plugins:", [getattr(p, "name", p) for p in loaded])
else:
    print("Loaded plugins: (introspecting manager fields)",
          [k for k in vars(mgr) if "plugin" in k.lower() or "hook" in k.lower()])

def case(label, tool, args, *, expect_block: bool, contains: str | None = None):
    msg = get_pre_tool_call_block_message(tool, args)
    blocked = msg is not None
    ok = blocked == expect_block
    if ok and contains is not None:
        ok = contains in (msg or "")
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}")
    if not ok:
        print(f"    expect_block={expect_block} got_msg={msg!r}")
    return ok

all_ok = True

# Reset repo to clean state between stages.
def git(*argv):
    return subprocess.run(["git", *argv], cwd=REPO, capture_output=True, text=True)

# Stage 1: no commit references "Core-9fhd" yet.
git("reset", "--hard", "HEAD")
all_ok &= case(
    "bd close Core-9fhd with no matching commit → BLOCK",
    "terminal", {"command": "bd close Core-9fhd"},
    expect_block=True, contains="Core-9fhd",
)
all_ok &= case(
    "bd update Core-9fhd --status=closed (no commit) → BLOCK",
    "terminal", {"command": "bd update Core-9fhd --status=closed"},
    expect_block=True, contains="Core-9fhd",
)
all_ok &= case(
    "bd close --reason=done Core-9fhd (flag before id) → BLOCK",
    "terminal", {"command": "bd close --reason=done Core-9fhd"},
    expect_block=True, contains="Core-9fhd",
)

# Stage 2: add a commit that mentions Core-9fhd.
Path(REPO, "fix.txt").write_text("fix\n")
git("add", "fix.txt")
git("commit", "-m", "fix: resolve Core-9fhd typo in config")

all_ok &= case(
    "bd close Core-9fhd with matching commit → allow",
    "terminal", {"command": "bd close Core-9fhd"},
    expect_block=False,
)
all_ok &= case(
    "bd close Core-other (no such commit) still BLOCK",
    "terminal", {"command": "bd close Core-other"},
    expect_block=True, contains="Core-other",
)

# Stage 3: empty-diff commit gate.
# With nothing staged, `git commit` should be blocked.
all_ok &= case(
    "git commit with no staged diff → BLOCK",
    "terminal", {"command": 'git commit -m "no changes"'},
    expect_block=True, contains="no staged",
)

# Stage with an actual change.
Path(REPO, "another.txt").write_text("x\n")
git("add", "another.txt")
all_ok &= case(
    "git commit with staged diff → allow",
    "terminal", {"command": 'git commit -m "fix: real change"'},
    expect_block=False,
)

# --allow-empty bypasses the gate.
git("reset")  # unstage
all_ok &= case(
    "git commit --allow-empty → allow",
    "terminal", {"command": 'git commit --allow-empty -m "marker"'},
    expect_block=False,
)

# Non-terminal tool untouched.
all_ok &= case(
    "file_read tool → allow",
    "file_read", {"path": "/tmp/foo"},
    expect_block=False,
)

# bd update --claim is not a close.
all_ok &= case(
    "bd update Core-avqg --claim → allow",
    "terminal", {"command": "bd update Core-avqg --claim"},
    expect_block=False,
)

print("\nRESULT:", "ALL PASS" if all_ok else "FAILURES ABOVE")
sys.exit(0 if all_ok else 1)
