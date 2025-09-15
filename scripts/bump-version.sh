#!/usr/bin/env bash
set -euo pipefail
new_ver="${1:-}"
if [ -z "$new_ver" ]; then echo "Usage: scripts/bump-version.sh X.Y.Z"; exit 1; fi
echo "$new_ver" > VERSION
perl -0777 -pe "s/(v)\d+\.\d+\.\d+/$1$new_ver/g" -i README.md 2>/dev/null || true
perl -0777 -pe "s/(\[)\d+\.\d+\.\d+(\])/([$new_ver])/g" -i CHANGELOG.md 2>/dev/null || true
echo "Version bumped to $new_ver"
