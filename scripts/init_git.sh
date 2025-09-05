#!/usr/bin/env bash
set -euo pipefail
if [ ! -d ".git" ]; then git init; fi
git checkout -B main
git add -A
if git diff --cached --quiet; then echo "Nothing to commit."; else git commit -m "Initial commit: Overtime Kiosk"; fi
echo
echo "Create a new empty repo on GitHub."
read -p "Paste GitHub repo URL: " GH_URL
[ -z "$GH_URL" ] && { echo "No URL provided."; exit 1; }
git remote remove origin 2>/dev/null || true
git remote add origin "$GH_URL"
git push -u origin main
echo "✅ Done. Pushed to $GH_URL"
