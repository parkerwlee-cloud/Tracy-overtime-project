#!/usr/bin/env bash
# scripts/detect-chromium.sh
# Print the correct Chromium command and ready-to-paste autostart lines.
# Usage:
#   ./scripts/detect-chromium.sh [--mode display|kiosk] [--url URL] [--no-sandbox]
#
# Examples:
#   ./scripts/detect-chromium.sh
#   ./scripts/detect-chromium.sh --mode kiosk
#   ./scripts/detect-chromium.sh --url http://192.168.1.50:5000/display
#   ./scripts/detect-chromium.sh --mode display --no-sandbox

set -euo pipefail

MODE="display"   # default: wallboard
URL_DEFAULT_DISPLAY="http://localhost:5000/display"
URL_DEFAULT_KIOSK="http://localhost:5000/"
URL=""
NO_SANDBOX=0

while (( "$#" )); do
  case "$1" in
    --mode)
      MODE="${2:-}"; shift 2;;
    --url)
      URL="${2:-}"; shift 2;;
    --no-sandbox)
      NO_SANDBOX=1; shift 1;;
    -h|--help)
      echo "Usage: $0 [--mode display|kiosk] [--url URL] [--no-sandbox]"
      exit 0;;
    *)
      echo "Unknown option: $1" >&2; exit 1;;
  esac
done

# Decide URL
if [[ -z "${URL}" ]]; then
  if [[ "${MODE}" == "kiosk" ]]; then
    URL="${URL_DEFAULT_KIOSK}"
  else
    URL="${URL_DEFAULT_DISPLAY}"
  fi
fi

# Find chromium command
CMD=""
if command -v chromium-browser >/dev/null 2>&1; then
  CMD="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CMD="chromium"
else
  echo "ERROR: Chromium is not installed. Try: sudo apt install -y chromium-browser || sudo apt install -y chromium" >&2
  exit 2
fi

EXTRA_FLAGS="--kiosk --incognito --noerrdialogs --disable-translate"
if [[ "${NO_SANDBOX}" -eq 1 ]]; then
  EXTRA_FLAGS="${EXTRA_FLAGS} --no-sandbox"
fi

echo "Detected Chromium command: ${CMD}"
echo "Mode: ${MODE}"
echo "URL:  ${URL}"
echo

echo "▶ LXDE autostart line (paste into ~/.config/lxsession/LXDE-pi/autostart):"
echo "@${CMD} ${EXTRA_FLAGS} ${URL}"
echo
echo "▶ .desktop Exec line (paste into ~/.config/autostart/kiosk.desktop):"
echo "Exec=${CMD} ${EXTRA_FLAGS} ${URL}"
echo
echo "Tip: If you see 'bash: @chromium-browser: command not found' you tried to run the LXDE line in a shell."
echo "     The '@' prefix is only for the LXDE autostart file."
