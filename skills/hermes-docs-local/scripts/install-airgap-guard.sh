#!/usr/bin/env bash
# install-airgap-guard.sh — wire airgap-guard.sh into Hermes as a pre_tool_call shell hook.
#
# Usage:  ./install-airgap-guard.sh          # installs into $HERMES_HOME (default ~/.hermes)
#
# Safe to re-run. It never edits an existing hooks: block — if one is already present it prints
# the lines for you to merge instead.

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CFG="$HERMES_HOME/config.yaml"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$HERMES_HOME/agent-hooks"
HOOK="$HOOK_DIR/airgap-guard.sh"

mkdir -p "$HOOK_DIR"
install -m 755 "$SRC_DIR/airgap-guard.sh" "$HOOK"
echo "==> hook installed: $HOOK"

if [[ -f "$CFG" ]] && grep -q 'airgap-guard' "$CFG"; then
    echo "==> already registered in $CFG — nothing to do"
elif [[ -f "$CFG" ]] && grep -q '^hooks:' "$CFG"; then
    echo "!! $CFG already has a hooks: block. Merge this under it (do not add a second 'hooks:' key):"
    echo
    echo "hooks:"
    echo "  pre_tool_call:"
    echo "    - matcher: \"web_extract|web_fetch|web_search|browser|terminal|computer\""
    echo "      command: \"$HOOK\""
    echo "      timeout: 10"
    echo
    exit 1
else
    {
        echo
        echo "# --- air-gap guard (hermes-local-docs skill): block docs-host fetches, point at the mirror"
        echo "hooks:"
        echo "  pre_tool_call:"
        echo "    - matcher: \"web_extract|web_fetch|web_search|browser|terminal|computer\""
        echo "      command: \"$HOOK\""
        echo "      timeout: 10"
    } >> "$CFG"
    echo "==> registered in $CFG (hooks: block appended)"
fi

# --- also teach the bundled hermes-agent skill itself (the source of the links) --------------
# The hook is the enforcement layer; this is the prevention layer: a preamble inside the skill
# makes the agent prefer the mirror BEFORE it tries the network. Bundled-skill edits are tracked
# as user modifications (kept by `hermes skills update`; `hermes skills reset` undoes this).
AGENT_SKILL="$(find "$HERMES_HOME/skills" -maxdepth 4 -path '*hermes-agent/SKILL.md' 2>/dev/null | head -1)"
if [[ -z "$AGENT_SKILL" ]]; then
    echo "!! bundled hermes-agent skill not found under $HERMES_HOME/skills — preamble not applied"
elif grep -q 'HERMES-AIRGAP-PREAMBLE' "$AGENT_SKILL"; then
    echo "==> bundled hermes-agent skill already patched: $AGENT_SKILL"
else
    MIRROR_LINE="${HERMES_DOCS_MIRROR:-/opt/data/docs/hermes}"
    python3 - "$AGENT_SKILL" "$MIRROR_LINE" <<'PY'
import sys
path, mirror = sys.argv[1], sys.argv[2]
text = open(path).read()
if "HERMES-AIRGAP-PREAMBLE" in text:
    sys.exit(0)
pre = (
    "<!-- HERMES-AIRGAP-PREAMBLE: added by hermes-local-docs install-airgap-guard.sh -->\n"
    "**Air-gapped environment:** if the local docs mirror exists (`$HERMES_DOCS_MIRROR`, default "
    f"`{mirror}`), **NEVER fetch hermes-agent.nousresearch.com** — the corporate firewall 403s it. "
    "Resolve every docs link in this file against the local mirror instead (see the hermes-docs-local "
    "skill for the URL-to-local-path map). Fetching it wastes a turn and returns an HTML error page.\n\n"
)
lines = text.splitlines(keepends=True)
if lines and lines[0].strip() == "---":
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            lines.insert(i + 1, "\n" + pre)
            break
    else:
        lines.insert(0, pre)
else:
    lines.insert(0, pre)
open(path, "w").write("".join(lines))
print("==> patched bundled hermes-agent skill:", path)
PY
fi

echo
echo "Consent: Hermes prompts once per (event, command) pair on first use. For headless/gateway"
echo "use, set 'hooks_auto_accept: true' in $CFG, or accept the prompt once in a TUI session."
echo
echo "Test it:"
echo "  echo '{\"tool_name\":\"web_extract\",\"tool_input\":{\"url\":\"https://hermes-agent.nousresearch.com/docs/\"}}' | $HOOK"
echo "  -> should print a block JSON with the mirror path"
echo "  echo '{\"tool_name\":\"read_file\",\"tool_input\":{\"path\":\"/etc/hosts\"}}' | $HOOK"
echo "  -> should print nothing"
