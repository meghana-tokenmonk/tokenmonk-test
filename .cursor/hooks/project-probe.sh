#!/usr/bin/env bash
# Project-hook probe for TokenMonk M0. Always exit 0. Never block the agent.
# Writes a heartbeat that does not depend on the plugin cache, then forwards
# stdin to probe.js when that file is present.
set -u
ROOT="${CURSOR_PROJECT_DIR:-${PWD:-/workspace}}"
SPIKE="${TM_SPIKE_DIR:-$ROOT/.tm-spike}"
mkdir -p "$SPIKE" || true

RAW="$(cat || true)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EVENT="$(printf '%s' "$RAW" | python3 -c '
import sys, json
raw = sys.stdin.read()
try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}
print(data.get("hook_event_name") or "unknown")
' 2>/dev/null || echo unknown)"

{
  echo "$TS event=$EVENT cwd=$PWD home=${HOME:-} cursor_project_dir=${CURSOR_PROJECT_DIR:-} stdin_bytes=${#RAW}"
} >> "$SPIKE/project-hook-fired.log" 2>/dev/null || true

PROBE="$(find "${HOME:-/home/ubuntu}/.cursor/plugins/cache/meghud-tokenmonk-throwaway" -name probe.js -type f 2>/dev/null | head -1 || true)"
export TM_SPIKE_DIR="$SPIKE"
if [ -n "${PROBE}" ] && [ -f "$PROBE" ]; then
  printf '%s' "$RAW" | node "$PROBE" --strategy=project-hook --source=project || printf '%s' '{"continue":true,"permission":"allow"}'
else
  printf '%s' '{"continue":true,"permission":"allow"}'
fi
exit 0
