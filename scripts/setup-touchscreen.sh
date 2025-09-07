#!/usr/bin/env bash
# Calibrate touchscreen to HDMI-2 using an exact Coordinate Transformation Matrix (CTM).
# Handles rotation/inversion via env vars.
#
# Usage:
#   ./scripts/setup-touchscreen.sh
#
# Optional environment overrides:
#   TOUCH_NAME="Exact device name from xinput list"
#   TOUCH_ROTATION=0|90|180|270         # rotate touch coords
#   TOUCH_INVERT_X=0|1                  # invert X axis
#   TOUCH_INVERT_Y=0|1                  # invert Y axis
#
# Requires: xinput, xrandr, python3 (X11 session recommended)

set -euo pipefail

# Sanity
command -v xrandr >/dev/null || { echo "ERROR: xrandr not found"; exit 1; }
command -v xinput  >/dev/null || { echo "ERROR: xinput not found (sudo apt install -y xinput)"; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not found"; exit 1; }

# Pick touchscreen
if [[ -n "${TOUCH_NAME:-}" ]]; then
  TOUCH_LINE="$(xinput list | grep -i "$TOUCH_NAME" | head -n1 || true)"
else
  TOUCH_LINE="$(xinput list | grep -Ei 'Touch|Goodix|FT5406|ELAN|eGalax|HID|capacitive' | grep -i pointer | head -n1 || true)"
fi
[[ -n "$TOUCH_LINE" ]] || { echo "ERROR: No touchscreen device found in xinput list."; xinput list; exit 1; }
TOUCH_ID="$(sed -n 's/.*id=\([0-9]\+\).*/\1/p' <<<"$TOUCH_LINE" | head -n1)"
[[ -n "$TOUCH_ID" ]] || { echo "ERROR: Could not parse touchscreen id."; echo "$TOUCH_LINE"; exit 1; }

# HDMI-2 geometry
XR="$(xrandr | awk '/ connected/{print $1,$3}')"
HDMI2_LINE="$(awk '$1=="HDMI-2"{print $0}' <<<"$XR")"
[[ -n "$HDMI2_LINE" ]] || { echo "ERROR: HDMI-2 not detected as connected."; echo "$XR"; exit 1; }

# Params
ROT="${TOUCH_ROTATION:-0}"
INVX="${TOUCH_INVERT_X:-0}"
INVY="${TOUCH_INVERT_Y:-0}"

# Compute CTM in Python (float precision)
read -r CTM <<<"$(python3 - <<PY
import re,sys,math
lines='''$XR'''.strip().splitlines()
outs=[]
maxW=maxH=0
for ln in lines:
    name,geom=ln.split()
    m=re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', geom)
    if not m: continue
    w,h,x,y=map(int,m.groups())
    outs.append((name,w,h,x,y))
    maxW=max(maxW,x+w); maxH=max(maxH,y+h)

hdmi2 = next((o for o in outs if o[0]=="HDMI-2"), None)
if not hdmi2:
    print('',end=''); sys.exit(0)
_,w2,h2,x2,y2 = hdmi2

sx = w2/float(maxW)
sy = h2/float(maxH)
tx = x2/float(maxW)
ty = y2/float(maxH)

# Base matrix (scale+translate)
M = [[sx,0,tx],
     [0,sy,ty],
     [0,0,1]]

def matmul(A,B):
    return [[sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

# Optional rotations about full-screen unit square (0..1)
rot = int("$ROT")
if rot not in (0,90,180,270):
    rot=0

def rotM(deg):
    if deg==0:   return [[1,0,0],[0,1,0],[0,0,1]]
    if deg==90:  return [[0,1,0],[-1,0,1],[0,0,1]]      # rotate +90 around origin then translate to keep in [0,1]
    if deg==180: return [[-1,0,1],[0,-1,1],[0,0,1]]
    if deg==270: return [[0,-1,1],[1,0,0],[0,0,1]]

# Optional axis inversions in unit space
invx = int("$INVX"); invy = int("$INVY")
InvX = [[-1,0,1],[0,1,0],[0,0,1]] if invx==1 else [[1,0,0],[0,1,0],[0,0,1]]
InvY = [[1,0,0],[0,-1,1],[0,0,1]] if invy==1 else [[1,0,0],[0,1,0],[0,0,1]]

# Final: first apply rotation/inversion in unit space, then scale+translate to HDMI-2 region
R = rotM(rot)
Pre = matmul(InvY, matmul(InvX, R))
Final = matmul(M, Pre)

print(f"{Final[0][0]} {Final[0][1]} {Final[0][2]}  {Final[1][0]} {Final[1][1]} {Final[1][2]}  0 0 1")
PY
)" || true)"

[[ -n "$CTM" ]] || { echo "ERROR: Could not compute CTM."; exit 1; }

echo "Touch ID: ${TOUCH_ID}"
echo "CTM: ${CTM}"
echo "Rotation=${ROT} InvertX=${INVX} InvertY=${INVY}"

# Apply matrix
xinput set-prop "${TOUCH_ID}" "Coordinate Transformation Matrix" ${CTM} || {
  # Some stacks name it differently (libinput)
  xinput set-prop "${TOUCH_ID}" "libinput Calibration Matrix" ${CTM}
}

# Also map-to-output as a fallback hint
xinput map-to-output "${TOUCH_ID}" HDMI-2 || true

# Persist in ~/.xsessionrc
XSESSIONRC="${HOME}/.xsessionrc"
LINE1="xinput set-prop ${TOUCH_ID} 'Coordinate Transformation Matrix' ${CTM}"
LINE1b="xinput set-prop ${TOUCH_ID} 'libinput Calibration Matrix' ${CTM}"
LINE2="xinput map-to-output ${TOUCH_ID} HDMI-2"
mkdir -p "$(dirname "$XSESSIONRC")"
grep -Fqx "$LINE1"  "$XSESSIONRC" 2>/dev/null || grep -Fqx "$LINE1b" "$XSESSIONRC" 2>/dev/null || echo "$LINE1" >> "$XSESSIONRC"
grep -Fqx "$LINE2"  "$XSESSIONRC" 2>/dev/null || echo "$LINE2" >> "$XSESSIONRC"

echo "✅ Touchscreen calibrated and persisted in ${XSESSIONRC}"
echo "   Tip: if the cursor is mirrored or rotated, re-run with TOUCH_ROTATION / TOUCH_INVERT_X / TOUCH_INVERT_Y."
