#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
build_dir="$project_dir/.build/$configuration"
app_dir="$project_dir/dist/Servo.app"

cd "$project_dir"
sdk_arguments=()
if [[ -n "${SERVO_SDK_PATH:-}" ]]; then
    sdk_arguments=(--sdk "$SERVO_SDK_PATH")
fi
CLANG_MODULE_CACHE_PATH="$project_dir/.swift-cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.swift-cache/clang" \
swift build --disable-sandbox -c "$configuration" "${sdk_arguments[@]}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/Servo" "$app_dir/Contents/MacOS/Servo.new"
mv -f "$app_dir/Contents/MacOS/Servo.new" "$app_dir/Contents/MacOS/Servo"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/servo.icns" "$app_dir/Contents/Resources/servo.icns"
cp "$project_dir/Resources/Assets.car" "$app_dir/Contents/Resources/Assets.car"
cp "$project_dir/Resources/servo-https-prepend.php" "$app_dir/Contents/Resources/servo-https-prepend.php"
python3 - "$app_dir/Contents/Info.plist" <<'PYVERSION'
import pathlib, plistlib, re, sys
version = pathlib.Path("VERSION").read_text().strip()
build = pathlib.Path("BUILD_NUMBER").read_text().strip()
repository = pathlib.Path("UPDATE_REPOSITORY").read_text().strip()
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
assert build.isdigit()
assert re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository)
with open(sys.argv[1], "rb") as f: info = plistlib.load(f)
info.update(CFBundleShortVersionString=version, CFBundleVersion=build, ServoUpdateRepository=repository)
with open(sys.argv[1], "wb") as f: plistlib.dump(info, f)
PYVERSION
codesign --force --deep --options runtime --timestamp=none --sign - "$app_dir"
echo "$app_dir"
