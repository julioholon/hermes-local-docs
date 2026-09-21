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

echo
echo "Consent: Hermes prompts once per (event, command) pair on first use. For headless/gateway"
echo "use, set 'hooks_auto_accept: true' in $CFG, or accept the prompt once in a TUI session."
echo
echo "Test it:"
echo "  echo '{\"tool_name\":\"web_extract\",\"tool_input\":{\"url\":\"https://hermes-agent.nousresearch.com/docs/\"}}' | $HOOK"
echo "  -> should print a block JSON with the mirror path"
echo "  echo '{\"tool_name\":\"read_file\",\"tool_input\":{\"path\":\"/etc/hosts\"}}' | $HOOK"
echo "  -> should print nothing"
