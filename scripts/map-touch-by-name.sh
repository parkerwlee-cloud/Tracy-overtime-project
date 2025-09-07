#!/bin/bash
# Map the touchscreen input to the correct HDMI display on Raspberry Pi (X11)

set -euo pipefail

TOUCH_NAME="Yldzkj USB2IIC_CTP_CONTROL"

# Give X time to enumerate devices after login
sleep 2

# Resolve device ID by exact name (fallback to partial match)
TOUCH_ID="$(xinput list --id-only "$TOUCH_NAME" 2>/dev/null || true)"
if [ -z "${TOUCH_ID:-}" ]; then
  TOUCH_ID="$(xinput list | awk -F'id=' '/USB2IIC|CTP|Touch/ && /pointer/ {sub(/].*/,"",$2); print $2; exit}')"
fi

# Pick the connected output that offers 1024x600 (typical for this panel)
OUTPUT="$(xrandr | awk '
  / connected/ {out=$1}
  /1024x600/  {print out; exit}
')"

# Fallbacks if mode probing failed
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-2"
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-1"

if [ -n "${TOUCH_ID:-}" ]; then
  xinput map-to-output "$TOUCH_ID" "$OUTPUT"
fi
