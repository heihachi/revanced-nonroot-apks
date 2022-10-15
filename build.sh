#!/usr/bin/env bash

set -eu -o pipefail

source build.conf
source utils.sh

print_usage() {
	echo -e "Usage:\n${0} build|clean|reset-template"
}

if [ -z ${1+x} ]; then
	print_usage
	exit 0
elif [ "$1" = "clean" ]; then
	rm -rf revanced-cache build.md build
	reset_template
	exit 0
elif [ "$1" = "reset-template" ]; then
	reset_template
	exit 0
elif [ "$1" = "build" ]; then
	:
else
	print_usage
	exit 1
fi

: >build.md
mkdir -p "$BUILD_DIR" "$TEMP_DIR"

if [ "$UPDATE_PREBUILTS" = true ]; then get_prebuilts; else set_prebuilts; fi
reset_template
get_cmpr

if [ "$BUILD_TWITTER" = true ]; then build_twitter; fi
if [ "$BUILD_REDDIT" = true ]; then build_reddit; fi
if [ "$BUILD_TIKTOK" = true ]; then build_tiktok; fi
if [ "$BUILD_SPOTIFY" = true ]; then build_spotify; fi
if [ "$BUILD_YT" = true ]; then build_yt; fi
if [ "$BUILD_MUSIC_ARM64_V8A" = true ]; then build_music $ARM64_V8A; fi
if [ "$BUILD_MUSIC_ARM_V7A" = true ]; then build_music $ARM_V7A; fi
if [ "$BUILD_MINDETACH_MODULE" = true ]; then
	echo "Building mindetach module"
	cd mindetach-magisk/mindetach/
	: >detach.txt
	if [[ ${YT_PATCHER_ARGS} = *-e\ ?(music-)microg-support* ]]; then
		echo "com.google.android.youtube" >>detach.txt
	fi
	if [[ ${MUSIC_PATCHER_ARGS} = *-e\ ?(music-)microg-support* ]]; then
		echo "com.google.android.apps.youtube.music" >>detach.txt
	fi
	if [ "$TWITTER_MODULE" = true ]; then
		echo "com.twitter.android" >>detach.txt
	fi
	if [ "$REDDIT_MODULE" = true ]; then
		echo "com.reddit.frontpage" >>detach.txt
	fi
	if [ "$TIKTOK_MODULE" = true ]; then
		echo "com.zhiliaoapp.musically" >>detach.txt
	fi	
	if [ "$SPOTIFY_MODULE" = true ]; then
		echo "com.spotify.music" >>detach.txt
	fi
	zip -r ../../build/mindetach.zip .
	cd ../../
fi
log "\n[revanced-magisk-module-repo](https://github.com/E85Addict/revanced-magisk-module)"

reset_template
echo "Done"
