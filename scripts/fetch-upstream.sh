#!/usr/bin/env sh
set -eu
PIN=06aa6563e4d51d6df5de6c9664c3a868f3f5bb2a
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/.upstream"
if [ -f "$ROOT/.upstream/packages/ai/package.json" ]; then
  echo "upstream snapshot already present"
  exit 0
fi
curl -L "https://codeload.github.com/earendil-works/pi/tar.gz/$PIN" \
  | tar -xz -C "$ROOT/.upstream" --strip-components=1
