#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SphereView360"
BUNDLE_ID="dev.local.SphereView360"
PHOTOS_EXTENSION_ID="dev.local.SphereView360.PhotosExtension"
PHOTOS_EXTENSION_NAME="SphereView360PhotosExtension.appex"
SHARE_EXTENSION_ID="dev.local.SphereView360.ShareExtension"
SHARE_EXTENSION_NAME="SphereView360ShareExtension.appex"
CONFIGURATION="${CONFIGURATION:-Debug}"
PLUGIN_DISCOVERY_DELAY="${PLUGIN_DISCOVERY_DELAY:-3}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
USER_APPS_DIR="$HOME/Applications"
INSTALLED_APP_BUNDLE="$USER_APPS_DIR/$APP_NAME.app"
XCODE_PROJECT="$ROOT_DIR/$APP_NAME.xcodeproj"
XCODE_SCHEME="$APP_NAME"
IOS_TARGET="SphereView360iOS"
XCODE_ARCH="$(/usr/bin/uname -m)"
XCODE_DESTINATION="platform=macOS,arch=$XCODE_ARCH"

TEMP_PARENT="${TMPDIR:-/tmp}"
TEMP_PARENT="${TEMP_PARENT%/}"
TEMP_BUILD_ROOT="$TEMP_PARENT/$APP_NAME-buildsrc"
DERIVED_DATA="$TEMP_PARENT/$APP_NAME-XcodeDerivedData"
IOS_SIM_BUILD_ROOT="$TEMP_PARENT/$APP_NAME-iOSSimulatorBuild"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PLUGINKIT="/usr/bin/pluginkit"

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

extension_path_for_app() {
  printf '%s/Contents/PlugIns/%s\n' "$1" "$2"
}

clear_bundle_extended_attributes() {
  local bundle_path="$1"

  if [[ -d "$bundle_path" ]]; then
    /usr/bin/xattr -cr "$bundle_path" >/dev/null 2>&1 || true
  fi
}

unregister_noninstalled_extension() {
  local extension_id="$1"
  local installed_plugin="$2"

  if [[ ! -x "$PLUGINKIT" ]]; then
    return
  fi

  while IFS= read -r plugin_path; do
    [[ "$plugin_path" == *.appex ]] || continue
    [[ "$plugin_path" == "$installed_plugin" ]] && continue
    "$PLUGINKIT" -r "$plugin_path" >/dev/null 2>&1 || true
  done < <("$PLUGINKIT" -m -A -D -i "$extension_id" -v | /usr/bin/awk -F '\t' '{print $NF}')
}

unregister_noninstalled_extensions() {
  unregister_noninstalled_extension \
    "$PHOTOS_EXTENSION_ID" \
    "$(extension_path_for_app "$INSTALLED_APP_BUNDLE" "$PHOTOS_EXTENSION_NAME")"

  unregister_noninstalled_extension \
    "$SHARE_EXTENSION_ID" \
    "$(extension_path_for_app "$INSTALLED_APP_BUNDLE" "$SHARE_EXTENSION_NAME")"
}

unregister_noninstalled_extensions_with_retries() {
  local pass

  for pass in 1 2 3; do
    unregister_noninstalled_extensions
    sleep 1
  done

  unregister_noninstalled_extensions
}

build_app() {
  if [[ ! -d "$XCODE_PROJECT" ]]; then
    echo "missing Xcode project: $XCODE_PROJECT" >&2
    exit 1
  fi

  stop_running_app

  rm -rf "$TEMP_BUILD_ROOT" "$DERIVED_DATA"
  mkdir -p "$TEMP_BUILD_ROOT" "$DIST_DIR"

  # Building from a temporary copy avoids local NSFileCoordinator stalls in this workspace.
  /usr/bin/rsync -a \
    --exclude ".git" \
    --exclude ".build" \
    --exclude "build" \
    --exclude "dist" \
    "$ROOT_DIR"/ "$TEMP_BUILD_ROOT"/

  /usr/bin/xcodebuild \
    -project "$TEMP_BUILD_ROOT/$APP_NAME.xcodeproj" \
    -scheme "$XCODE_SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "$XCODE_DESTINATION" \
    -quiet \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    build

  if [[ ! -d "$BUILT_APP" ]]; then
    echo "xcodebuild did not produce $BUILT_APP" >&2
    exit 1
  fi

  rm -rf "$APP_BUNDLE"
  /usr/bin/ditto "$BUILT_APP" "$APP_BUNDLE"
  clear_bundle_extended_attributes "$APP_BUNDLE"
  unregister_noninstalled_extensions
  rm -rf "$TEMP_BUILD_ROOT" "$DERIVED_DATA"
}

build_ios_simulator() {
  if [[ ! -d "$XCODE_PROJECT" ]]; then
    echo "missing Xcode project: $XCODE_PROJECT" >&2
    exit 1
  fi

  rm -rf "$IOS_SIM_BUILD_ROOT"

  /usr/bin/xcodebuild \
    -project "$XCODE_PROJECT" \
    -target "$IOS_TARGET" \
    -configuration "$CONFIGURATION" \
    -sdk iphonesimulator \
    SYMROOT="$IOS_SIM_BUILD_ROOT" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    -quiet \
    build

  echo "Built iOS simulator app: $IOS_SIM_BUILD_ROOT/$CONFIGURATION-iphonesimulator/$IOS_TARGET.app"
}

open_app() {
  build_app
  /usr/bin/open -n "$APP_BUNDLE"
  sleep "$PLUGIN_DISCOVERY_DELAY"
  unregister_noninstalled_extensions
}

register_launch_services() {
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
    "$LSREGISTER" -f "$INSTALLED_APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

register_plugin_extension() {
  local extension_id="$1"
  local plugin_path="$2"

  if [[ -d "$plugin_path" && -x "$PLUGINKIT" ]]; then
    "$PLUGINKIT" -a "$plugin_path" >/dev/null 2>&1 || true
    "$PLUGINKIT" -e use -i "$extension_id" >/dev/null 2>&1 || true
  fi
}

install_integrations() {
  build_app

  mkdir -p "$USER_APPS_DIR"
  rm -rf "$INSTALLED_APP_BUNDLE"
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  clear_bundle_extended_attributes "$INSTALLED_APP_BUNDLE"

  register_launch_services
  register_plugin_extension \
    "$PHOTOS_EXTENSION_ID" \
    "$(extension_path_for_app "$INSTALLED_APP_BUNDLE" "$PHOTOS_EXTENSION_NAME")"
  register_plugin_extension \
    "$SHARE_EXTENSION_ID" \
    "$(extension_path_for_app "$INSTALLED_APP_BUNDLE" "$SHARE_EXTENSION_NAME")"
  unregister_noninstalled_extensions

  echo "Installed: $INSTALLED_APP_BUNDLE"
  echo "Finder Open With is registered as an alternate handler for compatible videos and images."
  echo "Photos extension is registered with PluginKit as $PHOTOS_EXTENSION_ID."
  echo "Share extension is registered with PluginKit as $SHARE_EXTENSION_ID."
  echo "If Photos was already open, quit and reopen Photos before checking Edit > Extensions or Share."
}

restore_video_defaults() {
  swift - <<'SWIFT'
import CoreServices
import Darwin
import Foundation

let handlers = [
  ("public.mpeg-4", "com.apple.QuickTimePlayerX"),
  ("com.apple.quicktime-movie", "com.apple.QuickTimePlayerX"),
  ("com.apple.m4v-video", "com.apple.TV")
]

var failed = false
for (contentType, bundleIdentifier) in handlers {
  let status = LSSetDefaultRoleHandlerForContentType(
    contentType as NSString,
    .viewer,
    bundleIdentifier as NSString
  )

  if status == noErr {
    print("\(contentType): \(bundleIdentifier)")
  } else {
    fputs("failed to restore \(contentType): \(status)\n", stderr)
    failed = true
  }
}

exit(failed ? 1 : 0)
SWIFT
}

verify_installation() {
  build_app

  local photos_extension_path
  local share_extension_path
  photos_extension_path="$(extension_path_for_app "$APP_BUNDLE" "$PHOTOS_EXTENSION_NAME")"
  share_extension_path="$(extension_path_for_app "$APP_BUNDLE" "$SHARE_EXTENSION_NAME")"
  if [[ ! -d "$photos_extension_path" ]]; then
    echo "missing embedded Photos extension: $photos_extension_path" >&2
    exit 1
  fi

  if [[ ! -d "$share_extension_path" ]]; then
    echo "missing embedded Share extension: $share_extension_path" >&2
    exit 1
  fi

  /usr/bin/open -n "$APP_BUNDLE"
  sleep "$PLUGIN_DISCOVERY_DELAY"
  pgrep -x "$APP_NAME" >/dev/null
  stop_running_app
  sleep 1
  unregister_noninstalled_extensions_with_retries
  echo "Verified app launch and embedded Photos/Share extensions."
}

case "$MODE" in
  run)
    open_app
    ;;
  --install-open-with|install-open-with|--install-integrations|install-integrations)
    install_integrations
    ;;
  --restore-video-defaults|restore-video-defaults)
    restore_video_defaults
    ;;
  --build-ios-simulator|build-ios-simulator)
    build_ios_simulator
    ;;
  --debug|debug)
    build_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    verify_installation
    ;;
  *)
    echo "usage: $0 [run|--install-open-with|--install-integrations|--restore-video-defaults|--build-ios-simulator|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
