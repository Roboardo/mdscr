#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly BUILD_MODE="${1:-debug}"
readonly FLUTTER_IMAGE="${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"
readonly CACHE_DIR="$PROJECT_DIR/.docker-cache"

case "$BUILD_MODE" in
  debug|release)
    ;;
  *)
    printf 'Usage: %s [debug|release]\n' "$0" >&2
    exit 2
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required to build the APK.\n' >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  printf 'Docker is installed but its daemon is unavailable.\n' >&2
  exit 1
fi

mkdir -p \
  "$CACHE_DIR/home" \
  "$CACHE_DIR/pub" \
  "$CACHE_DIR/gradle" \
  "$CACHE_DIR/android" \
  "$CACHE_DIR/android-sdk/ndk" \
  "$CACHE_DIR/android-sdk/cmake"

docker run --rm \
  --env HOST_UID="$(id -u)" \
  --env HOST_GID="$(id -g)" \
  --env HOME=/workspace/.docker-cache/home \
  --env PUB_CACHE=/workspace/.docker-cache/pub \
  --env GRADLE_USER_HOME=/workspace/.docker-cache/gradle \
  --volume "$PROJECT_DIR:/workspace" \
  --volume "$CACHE_DIR/android-sdk/ndk:/opt/android-sdk-linux/ndk" \
  --volume "$CACHE_DIR/android-sdk/cmake:/opt/android-sdk-linux/cmake" \
  --workdir /workspace \
  "$FLUTTER_IMAGE" \
  bash -lc "set -e
    created_android=0
    cleanup() {
      for path in /workspace/build /workspace/.dart_tool; do
        [[ -e \"\$path\" ]] && chown -R \"\$HOST_UID:\$HOST_GID\" \"\$path\"
      done
      [[ \"\$created_android\" -eq 0 ]] || chown -R \"\$HOST_UID:\$HOST_GID\" /workspace/android
    }
    trap cleanup EXIT
    git config --global --add safe.directory /sdks/flutter
    if [[ ! -f android/gradlew ]]; then
      flutter create --platforms=android .
      created_android=1
    fi
    flutter pub get
    if [[ ! -f .docker-cache/android/debug.keystore ]]; then
      keytool -genkeypair -keystore .docker-cache/android/debug.keystore \
        -storepass android -keypass android -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname 'CN=Android Debug,O=Android,C=US'
    fi
    flutter build apk --$BUILD_MODE"
