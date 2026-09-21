#!/usr/bin/env bash
# b3-403-diagnose.sh — one-shot evidence capture for the skill_view 403.
# Run it on the machine where Hermes 403s, paste the output back.
set -uo pipefail
H="${HERMES_HOME:-$HOME/.hermes}"

echo "================ 1. hook state (is the guard actually registered & accepted?) ================"
hermes hooks list 2>&1 | head -20 || true
grep -n 'hooks_auto_accept' "$H/config.yaml" || echo "hooks_auto_accept: NOT SET (headless sessions skip unaccepted hooks!)"
grep -n -A5 'pre_tool_call' "$H/config.yaml" | head -12

echo
echo "================ 2. hook fires? (simulated payload through the REGISTERED script) ================"
HOOK=$(grep -A5 'pre_tool_call' "$H/config.yaml" 2>/dev/null | grep -o '[^ "]*airgap-guard\.sh' | head -1)
echo "registered hook path: ${HOOK:-NONE FOUND}"
if [[ -n "${HOOK:-}" && -x "$HOOK" ]]; then
  echo '{"tool_name":"web_extract","tool_input":{"url":"https://hermes-agent.nousresearch.com/docs/"}}' | "$HOOK" | head -c 200; echo
else
  echo "!! hook missing or not executable at the registered path"
fi

echo
echo "================ 3. what does errors.log say around the failure? ================"
L="$H/logs/errors.log"
grep -n 'Streaming failed before delivery\|403\|nousresearch' "$L" 2>/dev/null | tail -8 || echo "(no matches)"
echo "---- last 15 lines of errors.log ----"
tail -15 "$L" 2>/dev/null

echo
echo "================ 4. DLP test: does B3GPT 403 on PROMPT CONTENT containing the domain? ================"
echo "(reads provider/base_url/key from the environment the way Hermes does; prints only HTTP codes)"
python3 - <<'PY'
import os, json, urllib.request, urllib.error
base = os.environ.get("B3GPT_BASE_URL") or os.environ.get("OPENAI_BASE_URL") or ""
key  = os.environ.get("B3GPT_API_KEY") or os.environ.get("OPENAI_API_KEY") or ""
model = os.environ.get("B3GPT_MODEL") or ""
if not (base and key and model):
    print("skip: set B3GPT_BASE_URL / B3GPT_API_KEY / B3GPT_MODEL (or fill them inline) to run the DLP probe")
else:
    for label, content in [
        ("clean prompt        ", "Say hi."),
        ("prompt w/ docs URL ", "Summarize the docs at https://hermes-agent.nousresearch.com/docs/user-guide/configuration"),
    ]:
        req = urllib.request.Request(
            base.rstrip("/") + "/chat/completions",
            data=json.dumps({"model": model, "max_tokens": 5,
                             "messages": [{"role": "user", "content": content}]}).encode(),
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            r = urllib.request.urlopen(req, timeout=30)
            print(f"{label} -> HTTP {r.status}")
        except urllib.error.HTTPError as e:
            print(f"{label} -> HTTP {e.code}   <-- 403 here means the egress DLP blocks the CONTENT, not the provider")
        except Exception as e:
            print(f"{label} -> {type(e).__name__}: {e}")
PY
echo
echo "================ 5. gateway/agent log around the failure ================"
grep -n '403\|nousresearch' "$H/logs/gateway.log" 2>/dev/null | tail -5 || true
