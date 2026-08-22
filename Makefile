FLUTTER_IMAGE ?= ghcr.io/cirruslabs/flutter:stable

.PHONY: apk apk-debug apk-release

apk: apk-debug

apk-debug:
	FLUTTER_IMAGE="$(FLUTTER_IMAGE)" ./scripts/build-apk-docker.sh debug

apk-release:
	FLUTTER_IMAGE="$(FLUTTER_IMAGE)" ./scripts/build-apk-docker.sh release
