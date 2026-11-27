#!/usr/bin/env bash
# Build LANTERN APKs (arm64) and copy them into releases/.
# Clears app/build/app first: with Flutter 3.50 + Gradle 9.5, Gradle's strict
# task validation fails on stale Android outputs inside the Flutter project dir.
# Usage: tools/build_apk.sh <tag> [release|debug|both]
set -euo pipefail
tag=${1:?tag, e.g. m2}
kind=${2:-release}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/app"
mkdir -p "$root/releases"
# flutter_scene's material hook keeps the previous shaders when a .fmat
# fails to compile and the Flutter build still succeeds, so a broken
# material ships stale shaders silently. Fail the build instead.
check_materials() {
  local latest
  latest=$(ls -t .dart_tool/hooks_runner/lantern/*/stdout.txt 2>/dev/null | head -1)
  if [[ -n $latest ]] && grep -q "building .fmat materials failed" "$latest"; then
    echo "MATERIAL BUILD FAILED (stale shaders would ship):" >&2
    grep -A3 "materials failed" "$latest" >&2
    exit 1
  fi
}

build() {
  local mode=$1
  rm -rf build/app
  for i in 1 2 3; do
    # LANTERN_BUILD_ARGS: extra flutter args, e.g. the GLES diagnostic variant:
    #   LANTERN_BUILD_ARGS=--android-project-arg=lanternGles=1
    # Each tag is its own app ("Lantern <tag>", package
    # dev.lantern.lantern.<tag>) so builds install side by side.
    # LANTERN_NO_TAG=1 builds the plain "Lantern" (final release).
    local tagarg=--android-project-arg=lanternTag=$tag
    [[ ${LANTERN_NO_TAG:-0} == 1 ]] && tagarg=
    if flutter build apk --"$mode" --target-platform android-arm64 $tagarg ${LANTERN_BUILD_ARGS:-}; then return 0; fi
    echo "build failed (try $i); retrying in 60 s in case of a registry rate limit" >&2
    sleep 60
    rm -rf build/app
  done
  return 1
}
if [[ $kind == release || $kind == both ]]; then
  build release
  check_materials
  cp build/app/outputs/flutter-apk/app-release.apk "$root/releases/lantern-$tag-release.apk"
fi
if [[ $kind == debug || $kind == both ]]; then
  build debug
  check_materials
  rm -f "$root/releases/lantern-$tag-debug.apk.part-"*
  split -b 90M -d -a 2 build/app/outputs/flutter-apk/app-debug.apk "$root/releases/lantern-$tag-debug.apk.part-"
fi
cd "$root/releases"
{ for f in lantern-*-release.apk; do sha256sum "$f"; done
  for t in $(ls lantern-*-debug.apk.part-00 2>/dev/null | sed 's/-debug.apk.part-00//'); do
    echo "$(cat "$t"-debug.apk.part-* | sha256sum | cut -d' ' -f1)  $t-debug.apk (reassembled)"
  done; } > SHA256SUMS
cat SHA256SUMS
