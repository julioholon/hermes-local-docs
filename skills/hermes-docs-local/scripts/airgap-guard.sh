#!/usr/bin/env bash
# airgap-guard.sh — Hermes pre_tool_call shell hook.
#
# Blocks any tool call that would fetch hermes-agent.nousresearch.com (firewall-403'd on networks
# that block AI hosts by domain category) and returns a message pointing the agent at the local
# docs mirror. This makes the air-gap rule hold even when the hermes-docs-local skill is not in
# context — e.g. when the agent follows a link inside the bundled hermes-agent skill.
#
# Install with: install-airgap-guard.sh
# Disable for a session: export HERMES_AIRGAP_GUARD=0

[[ "${HERMES_AIRGAP_GUARD:-1}" == "1" ]] || exit 0

input=$(cat)
# fast path: nothing to do unless the docs host is mentioned anywhere in the payload
echo "$input" | grep -q 'hermes-agent\.nousresearch\.com' || exit 0

MIRROR="${HERMES_DOCS_MIRROR:-/opt/data/docs/hermes}"
python3 - "$MIRROR" <<'PY'
import json, sys
mirror = sys.argv[1]
msg = (
    "Blocked by the air-gap guard: hermes-agent.nousresearch.com is unreachable from this network "
    "(corporate firewall returns 403). Do NOT retry the network call and do not try mirrors of it.\n"
    f"The Hermes docs are mirrored locally at {mirror} — use search_files / read_file there "
    "(see the hermes-docs-local skill: URL -> local path equivalents, section map).\n"
    f"If {mirror} is empty, tell the user to build it with hermes-docs-mirror.sh."
)
print(json.dumps({"action": "block", "message": msg}))
PY
