#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
APP_NAME="Zelda's Storytelling Game"
BUNDLE_ID="com.zelda-built-this.zeldas-storytelling-game"
VERSION="${VERSION:-1.0.0}"
APP_PATH="${APP_PATH:-$BUILD_DIR/$APP_NAME.app}"
EXECUTABLE="$BUILD_DIR/chicago"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS packaging must run on macOS" >&2
  exit 1
fi
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  make -C "$ROOT_DIR" build
fi
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "missing executable: $EXECUTABLE" >&2
  exit 1
fi
if [[ "$APP_PATH" != "$BUILD_DIR/"*.app ]]; then
  echo "APP_PATH must name an .app directly inside $BUILD_DIR" >&2
  exit 1
fi

rm -rf "$APP_PATH"
MACOS_DIR="$APP_PATH/Contents/MacOS"
RESOURCES_DIR="$APP_PATH/Contents/Resources"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/build" "$FRAMEWORKS_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/zeldas-storytelling-game-bin"
cp -R "$ROOT_DIR/assets" "$RESOURCES_DIR/assets"
cp -R "$BUILD_DIR/shaders" "$RESOURCES_DIR/build/shaders"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>zeldas-storytelling-game</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

cat > "$MACOS_DIR/zeldas-storytelling-game" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
CONTENTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SDL_VULKAN_LIBRARY="$CONTENTS_DIR/Frameworks/libvulkan.1.dylib"
export VK_ICD_FILENAMES="$CONTENTS_DIR/Resources/vulkan/icd.d/MoltenVK_icd.json"
cd "$CONTENTS_DIR/Resources"
exec "$CONTENTS_DIR/MacOS/zeldas-storytelling-game-bin" "$@"
LAUNCHER
chmod +x "$MACOS_DIR/zeldas-storytelling-game" "$MACOS_DIR/zeldas-storytelling-game-bin"

VULKAN_PREFIX="${VULKAN_PREFIX:-$(brew --prefix vulkan-loader 2>/dev/null || true)}"
MOLTENVK_PREFIX="${MOLTENVK_PREFIX:-$(brew --prefix molten-vk 2>/dev/null || true)}"
if [[ ! -f "$VULKAN_PREFIX/lib/libvulkan.1.dylib" || ! -f "$MOLTENVK_PREFIX/lib/libMoltenVK.dylib" ]]; then
  echo "vulkan-loader and molten-vk are required (install with: brew install vulkan-loader molten-vk)" >&2
  exit 1
fi
cp "$VULKAN_PREFIX/lib/libvulkan.1.dylib" "$FRAMEWORKS_DIR/libvulkan.1.dylib"
cp "$MOLTENVK_PREFIX/lib/libMoltenVK.dylib" "$FRAMEWORKS_DIR/libMoltenVK.dylib"
chmod u+w "$FRAMEWORKS_DIR/libvulkan.1.dylib" "$FRAMEWORKS_DIR/libMoltenVK.dylib"
install_name_tool -id "@executable_path/../Frameworks/libvulkan.1.dylib" "$FRAMEWORKS_DIR/libvulkan.1.dylib"
install_name_tool -id "@executable_path/../Frameworks/libMoltenVK.dylib" "$FRAMEWORKS_DIR/libMoltenVK.dylib"
mkdir -p "$RESOURCES_DIR/vulkan/icd.d"
cat > "$RESOURCES_DIR/vulkan/icd.d/MoltenVK_icd.json" <<'JSON'
{"file_format_version":"1.0.0","ICD":{"library_path":"../../../Frameworks/libMoltenVK.dylib","api_version":"1.4.0","is_portability_driver":true}}
JSON

# Vendor non-system dylibs recursively and rewrite Homebrew paths.
queue=("$MACOS_DIR/zeldas-storytelling-game-bin" "$FRAMEWORKS_DIR/libvulkan.1.dylib" "$FRAMEWORKS_DIR/libMoltenVK.dylib")
index=0
while (( index < ${#queue[@]} )); do
  target="${queue[$index]}"
  ((index += 1))
  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    case "$dependency" in
      /System/*|/usr/lib/*|@executable_path/*|@loader_path/*|@rpath/*) continue ;;
    esac
    name="$(basename "$dependency")"
    bundled="$FRAMEWORKS_DIR/$name"
    if [[ ! -f "$bundled" ]]; then
      cp "$dependency" "$bundled"
      chmod u+w "$bundled"
      install_name_tool -id "@executable_path/../Frameworks/$name" "$bundled"
      queue+=("$bundled")
    fi
    install_name_tool -change "$dependency" "@executable_path/../Frameworks/$name" "$target"
  done < <(otool -L "$target" | tail -n +2 | awk '{print $1}')
done

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
if [[ "${SIGN_IDENTITY:-}" != "none" ]]; then
  identity="${SIGN_IDENTITY:--}"
  for dylib in "$FRAMEWORKS_DIR"/*.dylib; do codesign --force --sign "$identity" --timestamp=none "$dylib"; done
  codesign --force --sign "$identity" --timestamp=none "$MACOS_DIR/zeldas-storytelling-game-bin"
  codesign --force --sign "$identity" --timestamp=none "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
fi
echo "Packaged $APP_PATH"
