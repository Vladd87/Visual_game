#!/usr/bin/env bash
# Run one capture round as three parallel capture.js processes and merge them.
#
# The browser's software GL (SwiftShader) renders on about one core here, so
# three processes on a 4-core machine finish a 16-shot round in about a third
# of the time. Each process gets its own output folder; the merged folder has
# the usual layout (inner/, cover/, report.txt in shot order).
#
# Usage: tools/capture/capture_par.sh <outDir> [capture.js options...]
#   e.g. tools/capture/capture_par.sh captures/round-41 --root /tmp/web-r41 \
#          --scale 0.64 --extra '&rscale=1&glitter=0'
set -euo pipefail
out=${1:?output folder}
shift
here=$(cd "$(dirname "$0")" && pwd)
tmp="$out.parts"
rm -rf "$tmp"
mkdir -p "$tmp" "$out/inner" "$out/cover"
node "$here/capture.js" "$tmp/a" --shots 1,2,3,4 --aspects inner "$@" > "$tmp/a.log" 2>&1 &
pa=$!
node "$here/capture.js" "$tmp/b" --shots 5,6,7,8 --aspects inner "$@" > "$tmp/b.log" 2>&1 &
pb=$!
node "$here/capture.js" "$tmp/c" --shots 1,2,3,4,5,6,7,8 --aspects cover "$@" > "$tmp/c.log" 2>&1 &
pc=$!
status=0
wait $pa || status=1
wait $pb || status=1
wait $pc || status=1
for p in a b c; do
  for asp in inner cover; do
    [[ -d "$tmp/$p/$asp" ]] && cp "$tmp/$p/$asp"/* "$out/$asp/" 2>/dev/null || true
  done
done
# Report lines in the usual order: inner 1-8, then cover 1-8.
cat "$tmp"/a/report.txt "$tmp"/b/report.txt "$tmp"/c/report.txt 2>/dev/null |
  sort -t' ' -k1,1r -k2,2V > "$out/report.txt" || true
n=$(ls "$out"/inner/*.png "$out"/cover/*.png 2>/dev/null | wc -l)
echo "captured $n/16 shots into $out"
cat "$out/report.txt"
if [[ $status -ne 0 || $n -ne 16 ]]; then
  echo "capture incomplete; logs in $tmp" >&2
  exit 1
fi
rm -rf "$tmp"
