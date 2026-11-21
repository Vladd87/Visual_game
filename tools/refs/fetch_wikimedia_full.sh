#!/usr/bin/env bash
# Download Wikimedia Commons candidates at >=1600 px with curl, one at a time.
# curl --retry honours the server's Retry-After on 429; requests are spaced out.
# Input lines: <name> <original-url> <original-width>
# Usage: fetch_wikimedia_full.sh <list.txt> <outdir>
set -u
list=$1
out=$2
mkdir -p "$out"
UA='LanternRefFetcher/0.1 (game art reference research)'
while read -r name url width; do
  [ -s "$out/$name.jpg" ] && continue
  url=${url%%\?*}
  if [ "$width" -gt 1920 ]; then
    # Standard 1920 px thumbnail step (smaller transfer than the original).
    tail=${url#*/wikipedia/commons/}
    file=${tail##*/}
    get="https://upload.wikimedia.org/wikipedia/commons/thumb/$tail/1920px-$file"
  else
    get=$url
  fi
  if curl -sSf --retry 10 --retry-max-time 5400 -A "$UA" -o "$out/$name.jpg" "$get"; then
    echo "ok $name"
  else
    echo "FAIL $name $get"
    rm -f "$out/$name.jpg"
  fi
  sleep 20
done < "$list"
