#!/usr/bin/env bash
# Publish the Android build of Mushroom (see scripts/updater.gd for how phones pick it up).
#
#   tools/android_release.sh apk "notes"      new APK: bump BUILD in updater.gd and version/code in
#                                              export_presets.cfg first. Players download ~35 MB.
#   tools/android_release.sh patch "notes"    only the changed files since that APK (a few hundred
#                                              KB), installed from the main menu's update button.
#
# A patch can't change project.godot (autoloads, settings), permissions or the engine: ship an APK.
# Needs: godot/engine/godot.exe with Android templates, JAVA_HOME (JDK 17), gh logged in.
set -euo pipefail
cd "$(dirname "$0")/../../.."  # repo root
MODE=${1:?apk or patch}
NOTES=${2:-}
GODOT=./godot/engine/godot.exe
PROJ=godot/Mushroom
OUT=builds/Mushroom-android
REPO=Mild-Solvent/vibes-game
BUILD=$(sed -n 's/^const BUILD := \([0-9]*\).*/\1/p' $PROJ/scripts/updater.gd)
CODE=$(sed -n 's/^version\/code=\([0-9]*\)/\1/p' $PROJ/export_presets.cfg)
[ "$BUILD" = "$CODE" ] || { echo "BUILD ($BUILD) in updater.gd != version/code ($CODE)"; exit 1; }
mkdir -p $OUT
BASE=$OUT/base-$BUILD.pck
APK_URL=https://github.com/$REPO/releases/download/android-build-$BUILD/Mushroom-build-$BUILD.apk

manifest() {  # build patch pck_url pck_kb
  local mb=$(( $(stat -c %s "$OUT/Mushroom-build-$BUILD.apk" 2>/dev/null || echo 35000000) / 1000000 ))
  printf '{"build": %s, "apk_url": "%s", "apk_mb": %s, "patch": %s, "pck_url": "%s", "pck_kb": %s, "notes": %s}\n' \
    "$1" "$APK_URL" "$mb" "$2" "$3" "$4" "$(printf '%s' "$NOTES" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" > $OUT/update.json
  gh release view android-latest -R $REPO >/dev/null 2>&1 || \
    gh release create android-latest -R $REPO --prerelease --title "Android updates (read by the game)" \
      --notes "The game's updater reads update.json here. Don't delete."
  gh release upload android-latest -R $REPO $OUT/update.json --clobber
}

if [ "$MODE" = apk ]; then
  $GODOT --headless --path $PROJ --export-debug Android "$(pwd)/$OUT/Mushroom-build-$BUILD.apk"
  $GODOT --headless --path $PROJ --export-pack Android "$(pwd)/$BASE"  # what patches diff against
  gh release create android-build-$BUILD -R $REPO --prerelease --title "Android build $BUILD" \
    --notes "${NOTES:-Android APK build $BUILD.} Install over the old one; after this, updates come through the game's main menu." \
    $OUT/Mushroom-build-$BUILD.apk $BASE
  manifest "$BUILD" 0 "" 0
elif [ "$MODE" = patch ]; then
  [ -f $BASE ] || gh release download android-build-$BUILD -R $REPO -p "base-$BUILD.pck" -D $OUT
  LAST=$(curl -sL https://github.com/$REPO/releases/download/android-latest/update.json \
    | python -c "import json,sys; d=json.load(sys.stdin); print(d['patch'] if d['build']==$BUILD else 0)" 2>/dev/null || echo 0)
  N=$((LAST + 1))
  PCK=$OUT/patch-$BUILD-$N.pck
  $GODOT --headless --path $PROJ --export-patch Android "$(pwd)/$PCK" --patches "$(pwd)/$BASE"
  gh release upload android-latest -R $REPO $PCK --clobber
  manifest "$BUILD" "$N" "https://github.com/$REPO/releases/download/android-latest/patch-$BUILD-$N.pck" \
    $(( $(stat -c %s $PCK) / 1000 ))
else
  echo "usage: $0 apk|patch \"notes\""; exit 1
fi
cat $OUT/update.json
