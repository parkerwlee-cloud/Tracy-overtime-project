#!/usr/bin/env bash
# Calibrate touchscreen to HDMI-2 geometry using xinput and persist via ~/.xsessionrc

set -euo pipefail

if ! command -v xinput >/dev/null 2>&1; then
  echo "ERROR: xinput not found. Install with: sudo apt install -y xinput"
  exit 1
fi

if ! xrandr | grep -q "^HDMI-2 connected"; then
  echo "ERROR: HDMI-2 is not connected."
  exit 1
fi

# Pick the first device containing "Touch" in its name
TOUCH_ID="$(xinput list | awk -F'id=' '/[Tt]ouch/{print $2}' | cut -f1 | head -n1)"
if [[ -z "${TOUCH_ID}" ]]; then
  echo "ERROR: Could not detect a touchscreen device via xinput."
  xinput list
  exit 1
fi

echo "Touchscreen device ID: ${TOUCH_ID}"
echo "Mapping to output: HDMI-2"
xinput map-to-output "${TOUCH_ID}" HDMI-2

# Persist the mapping in the user's session startup
XSESSIONRC="${HOME}/.xsessionrc"
LINE="xinput map-to-output ${TOUCH_ID} HDMI-2"
if ! grep -qF "$LINE" "$XSESSIONRC" 2>/dev/null; then
  echo "$LINE" >> "$XSESSIONRC"
  echo "✅ Persisted to ${XSESSIONRC}"
else
  echo "ℹ Mapping already present in ${XSESSIONRC}"
fi
