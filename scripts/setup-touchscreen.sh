#!/usr/bin/env bash
# Map touchscreen → HDMI-2 with a proper CTM (rotation/inversion supported)
set -euo pipefail

command -v xrandr >/dev/null || { echo "xrandr not found"; exit 1; }
command -v xinput  >/dev/null || { echo "xinput not found (sudo apt install -y xinput)"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found"; exit 1; }

if ! xrandr | grep -q "^HDMI-2 connected"; then
  echo "ERROR: HDMI-2 not detected"; exit 1
fi

if [[ -n "${TOUCH_NAME:-}" ]]; then
  TOUCH_LINE="$(xinput list | grep -i "$TOUCH_NAME" | head -n1 || true)"
else
  TOUCH_LINE="$(xinput list | grep -Ei 'Touch|Goodix|FT5406|ELAN|eGalax|HID|capacitive' | grep -i pointer | head -n1 || true)"
fi
[[ -n "$TOUCH_LINE" ]] || { echo "No touchscreen found"; xinput list; exit 1; }
TOUCH_ID="$(sed -n 's/.*id=\([0-9]\+\).*/\1/p' <<<"$TOUCH_LINE" | head -n1)"

XR="$(xrandr | awk '/ connected/{print $1,$3}')"
ROT="${TOUCH_ROTATION:-0}"; INVX="${TOUCH_INVERT_X:-0}"; INVY="${TOUCH_INVERT_Y:-0}"

read -r CTM <<<"$(python3 - <<PY
import re,sys
lines='''$XR'''.strip().splitlines()
outs=[]; maxW=maxH=0
for ln in lines:
    name,geom=ln.split()
    m=re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', geom)
    if not m: continue
    w,h,x,y=map(int,m.groups())
    outs.append((name,w,h,x,y)); maxW=max(maxW,x+w); maxH=max(maxH,y+h)
hdmi2=next((o for o in outs if o[0]=="HDMI-2"),None)
if not hdmi2: print('',end='') or sys.exit(0)
_,w2,h2,x2,y2=hdmi2
sx=w2/float(maxW); sy=h2/float(maxH); tx=x2/float(maxW); ty=y2/float(maxH)
M=[[sx,0,tx],[0,sy,ty],[0,0,1]]

def mul(A,B): return [[sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def rotM(d):
    if d==0: return [[1,0,0],[0,1,0],[0,0,1]]
    if d==90: return [[0,1,0],[-1,0,1],[0,0,1]]
    if d==180: return [[-1,0,1],[0,-1,1],[0,0,1]]
    if d==270: return [[0,-1,1],[1,0,0],[0,0,1]]

rot=int("$ROT") if "$ROT".isdigit() else 0
InvX=[[ -1,0,1],[0,1,0],[0,0,1]] if "$INVX"=="1" else [[1,0,0],[0,1,0],[0,0,1]]
InvY=[[ 1,0,0],[0,-1,1],[0,0,1]] if "$INVY"=="1" else [[1,0,0],[0,1,0],[0,0,1]]

Pre = mul(InvY, mul(InvX, rotM(rot)))
Final = mul(M, Pre)
print(f"{Final[0][0]} {Final[0][1]} {Final[0][2]}  {Final[1][0]} {Final[1][1]} {Final[1][2]}  0 0 1")
PY
)" || true)"

[[ -n "$CTM" ]] || { echo "Failed to compute CTM"; exit 1; }

xinput set-prop "${TOUCH_ID}" "Coordinate Transformation Matrix" ${CTM} || \
xinput set-prop "${TOUCH_ID}" "libinput Calibration Matrix" ${CTM}
xinput map-to-output "${TOUCH_ID}" HDMI-2 || true

XSESSIONRC="${HOME}/.xsessionrc"
LINE1="xinput set-prop ${TOUCH_ID} 'Coordinate Transformation Matrix' ${CTM}"
LINE2="xinput map-to-output ${TOUCH_ID} HDMI-2"
grep -Fqx "$LINE1" "$XSESSIONRC" 2>/dev/null || echo "$LINE1" >> "$XSESSIONRC"
grep -Fqx "$LINE2" "$XSESSIONRC" 2>/dev/null || echo "$LINE2" >> "$XSESSIONRC"
echo "✅ Touchscreen calibrated and persisted"
