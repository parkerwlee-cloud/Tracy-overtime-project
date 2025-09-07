#!/usr/bin/env bash
# scripts/setup-touchscreen.sh
# Calibrate touchscreen to HDMI-2 geometry using xinput.

set -euo pipefail

HDMI2_GEOM=$(xrandr | awk '/HDMI-2 connected/{print $3}')
HDMI2_W=$(echo "$HDMI2_GEOM" | cut -dx -f1)
HDMI2_H=$(echo "$HDMI2_GEOM" | cut -dx -f2 | cut -d+ -f1)
HDMI2_X=$(echo "$HDMI2_GEOM" | cut -d+ -f2)
HDMI2_Y=$(echo "$HDMI2_GEOM" | cut -d+ -f3)

if [[ -z "$HDMI2_GEOM" ]]; then
  echo "ERROR: Could not detect HDMI-2 geometry."
  exit 1
fi

TOUCH_ID=$(xinput list | awk -F'id=' '/Touchscreen/{print $2}' | cut -f1)
if [[ -z "$TOUCH_ID" ]]; then
  echo "ERROR: Could not detect touchscreen device."
  xinput list
  exit 1
fi

echo "Touchscreen ID: $TOUCH_ID"
echo "Mapping to HDMI-2: ${HDMI2_W}x${HDMI2_H}+${HDMI2_X}+${HDMI2_Y}"

xinput map-to-output "$TOUCH_ID" HDMI-2

# Persist mapping by creating ~/.xsessionrc
XSESSIONRC="${HOME}/.xsessionrc"
grep -q "xinput map-to-output" "$XSESSIONRC" 2>/dev/null || {
  echo "xinput map-to-output $TOUCH_ID HDMI-2" >> "$XSESSIONRC"
}
echo "✅ Touchscreen mapping persisted in $XSESSIONRC"
