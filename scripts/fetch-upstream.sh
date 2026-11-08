#!/usr/bin/env sh
set -eu
# Default is the current verified snapshot; override with a commit or tag:
#   PI_UPSTREAM_REF=v1.6.0 scripts/fetch-upstream.sh
UPSTREAM_REF=${PI_UPSTREAM_REF:-06aa6563e4d51d6df5de6c9664c3a868f3f5bb2a}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/.upstream"
if [ -f "$ROOT/.upstream/packages/ai/package.json" ]; then
  echo "upstream snapshot already present; remove $ROOT/.upstream to refetch $UPSTREAM_REF"
  exit 0
fi
echo "fetching upstream pi at $UPSTREAM_REF"
curl -L "https://codeload.github.com/earendil-works/pi/tar.gz/$UPSTREAM_REF" \
  | tar -xz -C "$ROOT/.upstream" --strip-components=1
