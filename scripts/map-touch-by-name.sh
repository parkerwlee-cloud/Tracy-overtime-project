#!/bin/bash
# Map the touchscreen input to the correct HDMI display on Raspberry Pi (X11)
set -euo pipefail
TOUCH_NAME="Yldzkj USB2IIC_CTP_CONTROL"
sleep 2
TOUCH_ID="$(xinput list --id-only "$TOUCH_NAME" 2>/dev/null || true)"
if [ -z "${TOUCH_ID:-}" ]; then
  TOUCH_ID="$(xinput list | awk -F'id=' '/USB2IIC|CTP|Touch/ && /pointer/ {sub(/].*/,"",$2); print $2; exit}')"
fi
OUTPUT="$(xrandr | awk '/ connected/{out=$1} /1024x600/{print out; exit}')"
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-2"
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-1"
if [ -n "${TOUCH_ID:-}" ]; then
  xinput map-to-output "$TOUCH_ID" "$OUTPUT"
fi
