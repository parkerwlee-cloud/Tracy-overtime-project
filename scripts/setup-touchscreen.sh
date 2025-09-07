#!/usr/bin/env bash
# Calibrate touchscreen to HDMI-2 using an exact Coordinate Transformation Matrix (CTM).
# Works on X11 sessions. Requires: xinput, xrandr, python3
# Usage: ./scripts/setup-touchscreen.sh
# Optional: TOUCH_NAME="Your Touch Name" ./scripts/setup-touchscreen.sh

set -euo pipefail

# --- sanity ---
if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  echo "⚠ Detected session type: ${XDG_SESSION_TYPE:-unknown}. Precise touch mapping requires X11."
  echo "  If placement is wrong under Wayland, run: sudo ./scripts/force-x11.sh"
fi

command -v xrandr >/dev/null || { echo "ERROR: xrandr not found"; exit 1; }
command -v xinput  >/dev/null || { echo "ERROR: xinput not found. Try: sudo apt install -y xinput"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not found"; exit 1; }

# --- choose touchscreen device ---
if [[ -n "${TOUCH_NAME:-}" ]]; then
  TOUCH_LINE="$(xinput list | grep -i "$TOUCH_NAME" || true)"
else
  # pick the first "Touch" pointer device
  TOUCH_LINE="$(xinput list | grep -i 'Touch' | head -n1 || true)"
fi
if [[ -z "$TOUCH_LINE" ]]; then
  echo "ERROR: No touchscreen device found in xinput list."
  xinput list
  exit 1
fi
TOUCH_ID="$(echo "$TOUCH_LINE" | sed -n 's/.*id=\([0-9]\+\).*/\1/p' | head -n1)"
if [[ -z "$TOUCH_ID" ]]; then
  echo "ERROR: Could not parse touchscreen id."
  echo "$TOUCH_LINE"
  exit 1
fi

# --- read outputs from xrandr ---
XR="$(xrandr | awk '/ connected/{print $1,$3}')"
echo "XR outputs:"
echo "$XR"

# require HDMI-2 for target (touchscreen)
HDMI2_LINE="$(echo "$XR" | awk '$1=="HDMI-2"{print $0}')"
if [[ -z "$HDMI2_LINE" ]]; then
  echo "ERROR: HDMI-2 not detected as connected. Current outputs:"
  echo "$XR"
  exit 1
fi

# compute CTM via python for accurate floats
read -r CTM <<<"$(python3 - "$XR" <<'PY'
import sys,re
# read lines "NAME GEOM"
lines=sys.stdin.read().strip().splitlines()
outs=[]
maxW=maxH=0
for ln in lines:
    name,geom=ln.split()
    m=re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', geom)
    if not m: 
        continue
    w,h,x,y = map(int,m.groups())
    outs.append((name,w,h,x,y))
    maxW=max(maxW, x+w)
    maxH=max(maxH, y+h)

# find HDMI-2
hdmi2 = next((o for o in outs if o[0]=="HDMI-2"), None)
if not hdmi2:
    print("", end=""); sys.exit(0)
_, w2,h2,x2,y2 = hdmi2

# normalized CTM for this output region within the full screen (0..1)
sx = w2/float(maxW)
sy = h2/float(maxH)
tx = x2/float(maxW)
ty = y2/float(maxH)

# print 9 numbers row-major (3x3)
print(f"{sx} 0 {tx}  0 {sy} {ty}  0 0 1")
PY
)" || true)"

if [[ -z "$CTM" ]]; then
  echo "ERROR: Could not compute CTM."
  exit 1
fi

echo "Touch ID: ${TOUCH_ID}"
echo "CTM: ${CTM}"

# apply transformation matrix
xinput set-prop "${TOUCH_ID}" "Coordinate Transformation Matrix" ${CTM}

# also map to output as a safety (some stacks use it)
xinput map-to-output "${TOUCH_ID}" HDMI-2 || true

# persist in ~/.xsessionrc (re-applies at login)
XSESSIONRC="${HOME}/.xsessionrc"
LINE1="xinput set-prop ${TOUCH_ID} 'Coordinate Transformation Matrix' ${CTM}"
LINE2="xinput map-to-output ${TOUCH_ID} HDMI-2"
mkdir -p "$(dirname "$XSESSIONRC")"
grep -Fqx "$LINE1" "$XSESSIONRC" 2>/dev/null || echo "$LINE1" >> "$XSESSIONRC"
grep -Fqx "$LINE2" "$XSESSIONRC" 2>/dev/null || echo "$LINE2" >> "$XSESSIONRC"

echo "✅ Touchscreen calibrated and persisted in ${XSESSIONRC}"
echo "   If the wrong device was chosen, set TOUCH_NAME='Exact Device Name' and re-run."
