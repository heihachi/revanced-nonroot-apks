#!/usr/bin/env bash

source semver

MODULE_TEMPLATE_DIR="revanced-magisk"
MODULE_SCRIPTS_DIR="scripts"
TEMP_DIR="temp"
BUILD_DIR="build"

ARM64_V8A="arm64-v8a"
ARM_V7A="arm-v7a"
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-$"E85Addict/revanced-magisk-module"}
NEXT_VER_CODE=${NEXT_VER_CODE:-$(date +'%Y%m%d')}
WGET_HEADER="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:104.0) Gecko/20100101 Firefox/104.0"

SERVICE_SH=$(cat $MODULE_SCRIPTS_DIR/service.sh)
POSTFSDATA_SH=$(cat $MODULE_SCRIPTS_DIR/post-fs-data.sh)
CUSTOMIZE_SH=$(cat $MODULE_SCRIPTS_DIR/customize.sh)
UNINSTALL_SH=$(cat $MODULE_SCRIPTS_DIR/uninstall.sh)

get_prebuilts() {
	echo "Getting prebuilts"
	RV_CLI_URL=$(req https://api.github.com/repos/E85Addict/revanced-cli/releases/latest - | tr -d ' ' | sed -n 's/.*"browser_download_url":"\(.*jar\)".*/\1/p')
	RV_CLI_JAR="${TEMP_DIR}/${RV_CLI_URL##*/}"
	log "CLI: ${RV_CLI_JAR#"$TEMP_DIR/"}"

	RV_INTEGRATIONS_URL=$(req https://api.github.com/repos/revanced/revanced-integrations/releases/latest - | tr -d ' ' | sed -n 's/.*"browser_download_url":"\(.*apk\)".*/\1/p')
	RV_INTEGRATIONS_APK=${RV_INTEGRATIONS_URL##*/}
	RV_INTEGRATIONS_APK="${TEMP_DIR}/${RV_INTEGRATIONS_APK%.apk}-$(cut -d/ -f8 <<<"$RV_INTEGRATIONS_URL").apk"
	log "Integrations: ${RV_INTEGRATIONS_APK#"$TEMP_DIR/"}"

	RV_PATCHES_URL=$(req https://api.github.com/repos/E85Addict/revanced-patches/releases/latest - | tr -d ' ' | sed -n 's/.*"browser_download_url":"\(.*jar\)".*/\1/p')
	RV_PATCHES_JAR="${TEMP_DIR}/${RV_PATCHES_URL##*/}"
	local rv_patches_filename=${RV_PATCHES_JAR#"$TEMP_DIR/"}
	local rv_patches_ver=${rv_patches_filename##*'-'}
	log "Patches: $rv_patches_filename"
	log "[Patches Changelog](https://github.com/E85Addict/revanced-patches/releases/tag/v${rv_patches_ver%%'.jar'*})"

	dl_if_dne "$RV_CLI_JAR" "$RV_CLI_URL"
	dl_if_dne "$RV_INTEGRATIONS_APK" "$RV_INTEGRATIONS_URL"
	dl_if_dne "$RV_PATCHES_JAR" "$RV_PATCHES_URL"
}

get_cmpr() {
	dl_if_dne "${MODULE_TEMPLATE_DIR}/bin/arm64/cmpr" "https://github.com/j-hc/cmpr/releases/download/20220811/cmpr-arm64-v8a"
	dl_if_dne "${MODULE_TEMPLATE_DIR}/bin/arm/cmpr" "https://github.com/j-hc/cmpr/releases/download/20220811/cmpr-armeabi-v7a"
}

abort() { echo "abort: $1" && exit 1; }

set_prebuilts() {
	[ -d "$TEMP_DIR" ] || abort "${TEMP_DIR} directory could not be found"
	RV_CLI_JAR=$(find "$TEMP_DIR" -maxdepth 1 -name "revanced-cli-*" | tail -n1)
	[ -z "$RV_CLI_JAR" ] && abort "revanced cli not found"
	log "CLI: ${RV_CLI_JAR#"$TEMP_DIR/"}"
	RV_INTEGRATIONS_APK=$(find "$TEMP_DIR" -maxdepth 1 -name "app-release-unsigned-*" | tail -n1)
	[ -z "$RV_CLI_JAR" ] && abort "revanced integrations not found"
	log "Integrations: ${RV_INTEGRATIONS_APK#"$TEMP_DIR/"}"
	RV_PATCHES_JAR=$(find "$TEMP_DIR" -maxdepth 1 -name "revanced-patches-*" | tail -n1)
	[ -z "$RV_CLI_JAR" ] && abort "revanced patches not found"
	log "Patches: ${RV_PATCHES_JAR#"$TEMP_DIR/"}"
}

reset_template() {
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/service.sh"
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/post-fs-data.sh"
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/customize.sh"
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/uninstall.sh"
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/module.prop"
	rm -rf ${MODULE_TEMPLATE_DIR}/*.apk
	mkdir -p ${MODULE_TEMPLATE_DIR}/bin/arm ${MODULE_TEMPLATE_DIR}/bin/arm64
}

req() { wget -nv -O "$2" --header="$WGET_HEADER" "$1"; }
log() { echo -e "$1  " >>build.log; }
get_apk_vers() { req "https://www.apkmirror.com/uploads/?appcategory=${1}" - | sed -n 's;.*Version:</span><span class="infoSlide-value">\(.*\) </span>.*;\1;p'; }
get_largest_ver() {
	local max=0
	while read -r v || [ -n "$v" ]; do
		if [ "$(command_compare "$v" "$max")" = 1 ]; then max=$v; fi
	done
	if [[ $max = 0 ]]; then echo ""; else echo "$max"; fi
}
get_patch_last_supported_ver() {
	unzip -p "$RV_PATCHES_JAR" | strings -s , | sed -rn "s/.*${1},versions,(([0-9.]*,*)*),Lk.*/\1/p" | tr ',' '\n' | get_largest_ver
}

dl_if_dne() {
	if [ ! -f "$1" ]; then
		echo -e "\nGetting '$1' from '$2'"
		req "$2" "$1"
	fi
}

# if you are here to copy paste this piece of code, acknowledge it:)
dl_apk() {
	local url=$1 regexp=$2 output=$3
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n "s/href=\"/@/g; s;.*${regexp}.*;\1;p")"
	echo "$url"
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
	req "$url" "$output"
}

# used for UpToDown
get_apk_download_url() {
    # Usage: get_apk_download_url <repo_name> <artifact_name> <file_type> 
    version_url=$(curl -s "$1" | jq ".data[] | select(.version | contains(\"$2\")) | .versionURL")
    dl_url=$(curl -s "${version_url:1:-1}" | grep -oE "https:\/\/dw\.uptodown\.com.+\/")
    echo "$dl_url"
}

get_apk_latest_version_uptodown() {
    version_latest=$(curl -s "$1" | jq ".data[0] | select( 0 )| .version" | tr -d '"')
    echo "$version_latest"
}

patch_apk() {
	local stock_input=$1 patched_output=$2 patcher_args=$3
	if [ -f "$patched_output" ]; then return; fi
	# shellcheck disable=SC2086
	# --rip-lib is only available in my own revanced-cli builds
	java -jar "$RV_CLI_JAR" --rip-lib x86 --rip-lib x86_64 -a "$stock_input" -o "$patched_output" -b "$RV_PATCHES_JAR" --keystore=ks.keystore $patcher_args
}

zip_module() {
	local patched_apk=$1 module_name=$2 stock_apk=$3 pkg_name=$4
	cp -f "$patched_apk" "${MODULE_TEMPLATE_DIR}/base.apk"
	cp -f "$stock_apk" "${MODULE_TEMPLATE_DIR}/${pkg_name}.apk"
	cd "$MODULE_TEMPLATE_DIR" || abort "Module template dir not found"
	zip -9 -FSr "../${BUILD_DIR}/${module_name}" .
	cd ..
}

select_ver() {
	local last_ver pkg_name=$1 apkmirror_category=$2 select_ver_experimental=$3
	last_ver=$(get_patch_last_supported_ver "$pkg_name")
	if [ "$select_ver_experimental" = true ] || [ -z "$last_ver" ]; then
		if [ "$pkg_name" = "com.twitter.android" ]; then
			last_ver=$(get_apk_vers "$apkmirror_category" | grep "release" | get_largest_ver)
		elif [ "$pkg_name" = "com.google.android.youtube" ]; then
			if [[ ${args[patcher_args]} == *"--experimental"* ]]; then
				last_ver=$EXPERIMENTAL_YTVER
			else
				last_ver=$(get_apk_vers "$apkmirror_category" | get_largest_ver)
			fi
		elif [ "$pkg_name" = "com.google.android.apps.youtube.music" ]; then
			if [[ ${args[patcher_args]} == *"--experimental"* ]]; then
				last_ver=$EXPERIMENTAL_YTMVER
			else
				last_ver=$(get_apk_vers "$apkmirror_category" | get_largest_ver)
			fi
		elif [ "$pkg_name" = "com.zhiliaoapp.musically" ]; then
			if [[ ${args[patcher_args]} == *"--experimental"* ]]; then
				last_ver=$EXPERIMENTAL_TTVER
			else
				last_ver=$(get_apk_vers "$apkmirror_category" | get_largest_ver)
			fi
		elif [ "$pkg_name" = "com.spotify.music" ]; then
			if [[ ${args[patcher_args]} == *"--experimental"* ]]; then
				last_ver=$EXPERIMENTAL_SPVER
			else
				last_ver=$(get_apk_latest_version_uptodown $2)
			fi
		else
			last_ver=$(get_apk_vers "$apkmirror_category" | get_largest_ver)
		fi
	fi
	echo "$last_ver"
}

build_rv() {
	local -n args=$1
	local version
	reset_template

	echo "Building ${args[app_name]} ${args[arch]}"

	if [ "${args[is_module]}" = true ]; then
		if [[ ${args[patcher_args]} == *"--experimental"* ]]; then
			local select_ver_experimental=true
		else
			local select_ver_experimental=false
		fi
		if [ "${args[custom_module]}" = true ]; then
			local select_ver_experimental=true
			local is_root=true
		elif [[ ${args[patcher_args]} != *-e\ ?(music-)microg-support* ]] &&
			[[ ${args[patcher_args]} != *"--exclusive"* ]] ||
			[[ ${args[patcher_args]} == *-i\ ?(music-)microg-support* ]]; then
			local is_root=false
		else
			local is_root=true
		fi
	else
		local select_ver_experimental=true
		local is_root=false
	fi
	if [ $is_root = true ]; then
		local output_dir="$TEMP_DIR"
		# --unsigned is only available in my revanced-cli builds
		if [ "${args[rip_all_libs]}" = true ]; then
			# native libraries are already extracted. remove them all to keep apks smol
			args[patcher_args]="${args[patcher_args]} --unsigned --rip-lib arm64-v8a --rip-lib armeabi-v7a"
		else
			args[patcher_args]="${args[patcher_args]} --unsigned"
		fi
	else
		local output_dir="$BUILD_DIR"
	fi

	if [[ ${args[dl_provider]} == *"uptodown"* ]]; then
		version=$(select_ver "${args[pkg_name]}" "${args[uptodown_dlurl]}" $select_ver_experimental)
		echo "Choosing version '${version}'"
		local stock_apk="${TEMP_DIR}/${args[app_name],,}-stock-${version}-${args[arch]}.apk"
		local patched_apk="${output_dir}/${args[app_name],,}-revanced-${version}-${args[arch]}.apk"
		if [ ! -f "$stock_apk" ]; then
			echo "Downloading ${args[app_name]}"
			curl --progress-bar -Lo $stock_apk "$(get_apk_download_url ${args[uptodown_dlurl]} "$version")"
			log "\n${args[app_name]} version: ${version}"
			log "downloaded from: [UpToDown - ${args[app_name]}]($(curl -s ${args[uptodown_dlurl]} | jq ".data[] | select(.version | contains(\"$version\")) | .versionURL" | tr -d '"'))"
		fi
	elif [[ ${args[dl_provider]} == *"apkmirror"* ]]; then
		version=$(select_ver "${args[pkg_name]}" "${args[apkmirror_dlurl]##*/}" $select_ver_experimental)
		echo "Choosing version '${version}'"
		local stock_apk="${TEMP_DIR}/${args[app_name],,}-stock-v${version}-${args[arch]}.apk"
		local patched_apk="${output_dir}/${args[app_name],,}-revanced-v${version}-${args[arch]}.apk"
		if [ ! -f "$stock_apk" ]; then
			declare -r dl_url=$(dl_apk "https://www.apkmirror.com/apk/${args[apkmirror_dlurl]}-${version//./-}-release/" \
				"${args[regexp]}" \
				"$stock_apk")
			if [ "${args[arch]}" = "all" ]; then
				log "\n${args[app_name]} version: ${version}"
				log "downloaded from: [APKMirror - ${args[app_name]}]($dl_url)"
			else
				log "\n${args[app_name]} (${args[arch]}) version: ${version}"
				log "downloaded from: [APKMirror - ${args[app_name]} (${args[arch]})]($dl_url)"
			fi
		fi
	fi

	patch_apk "$stock_apk" "$patched_apk" "${args[patcher_args]}"

	if [ $is_root = false ]; then
		echo "Built ${args[app_name]} (${args[arch]}) (non-root)"
		return
	fi

	uninstall_sh "${args[pkg_name]}"
	service_sh "${args[pkg_name]}"
	postfsdata_sh "${args[pkg_name]}"
	customize_sh "${args[pkg_name]}" "${version}"
	module_prop "${args[module_prop_name]}" \
		"${args[app_name]} ReVanced" \
		"${version}" \
		"${args[app_name]} ReVanced Magisk module" \
		"https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/update/${args[module_update_json]}"

	local module_output="${args[app_name],,}-revanced-magisk-v${version}-${args[arch]}.zip"
	zip_module "$patched_apk" "$module_output" "$stock_apk" "${args[pkg_name]}"

	echo "Built ${args[app_name]}: '${BUILD_DIR}/${module_output}'"
}

build_yt() {
	declare -A yt_args
	yt_args[app_name]="YouTube"
	yt_args[is_module]=true
	yt_args[custom_module]=false
	yt_args[patcher_args]="${YT_PATCHER_ARGS} -m ${RV_INTEGRATIONS_APK}"
	yt_args[arch]="all"
	yt_args[rip_all_libs]=true
	yt_args[pkg_name]="com.google.android.youtube"
	yt_args[apkmirror_dlurl]="google-inc/youtube/youtube"
	yt_args[dl_provider]="apkmirror"
	yt_args[regexp]="APK</span>[^@]*@\([^#]*\)"
	yt_args[module_prop_name]="ytrv-magisk"
	#shellcheck disable=SC2034
	yt_args[module_update_json]="yt-update.json"

	build_rv yt_args
}

build_music() {
	declare -A ytmusic_args
	local arch=$1
	ytmusic_args[app_name]="Music"
	ytmusic_args[is_module]=true
	ytmusic_args[custom_module]=false
	ytmusic_args[patcher_args]="${MUSIC_PATCHER_ARGS}"
	ytmusic_args[arch]=$arch
	ytmusic_args[rip_all_libs]=false
	ytmusic_args[pkg_name]="com.google.android.apps.youtube.music"
	ytmusic_args[apkmirror_dlurl]="google-inc/youtube-music/youtube-music"
	ytmusic_args[dl_provider]="apkmirror"
	if [ "$arch" = "$ARM64_V8A" ]; then
		ytmusic_args[regexp]='arm64-v8a</div>[^@]*@\([^"]*\)'
		ytmusic_args[module_prop_name]="ytmusicrv-magisk"
	elif [ "$arch" = "$ARM_V7A" ]; then
		ytmusic_args[regexp]='armeabi-v7a</div>[^@]*@\([^"]*\)'
		ytmusic_args[module_prop_name]="ytmusicrv-arm-magisk"
	fi
	#shellcheck disable=SC2034
	ytmusic_args[module_update_json]="music-update-${arch}.json"

	build_rv ytmusic_args
}

build_twitter() {
	declare -A tw_args
	tw_args[app_name]="Twitter"
	tw_args[is_module]="$TWITTER_MODULE"
	tw_args[custom_module]="$TWITTER_MODULE"
	tw_args[rip_all_libs]="$TWITTER_MODULE"
	tw_args[patcher_args]="${TWITTER_PATCHER_ARGS}"
	tw_args[arch]="all"
	tw_args[pkg_name]="com.twitter.android"
	tw_args[apkmirror_dlurl]="twitter-inc/twitter/twitter"
	tw_args[dl_provider]="apkmirror"
	#shellcheck disable=SC2034
	tw_args[regexp]="APK</span>[^@]*@\([^#]*\)"
	if [ "$TWITTER_MODULE" = true ]; then
		tw_args[module_prop_name]="twrv-magisk"
		tw_args[module_update_json]="tw-update.json"
	fi

	build_rv tw_args
}

build_reddit() {
	declare -A reddit_args
	reddit_args[app_name]="Reddit"
	reddit_args[is_module]="$REDDIT_MODULE"
	reddit_args[custom_module]="$REDDIT_MODULE"
	reddit_args[rip_all_libs]="$REDDIT_MODULE"
	reddit_args[patcher_args]="${REDDIT_PATCHER_ARGS}"
	reddit_args[arch]="all"
	reddit_args[pkg_name]="com.reddit.frontpage"
	reddit_args[apkmirror_dlurl]="redditinc/reddit/reddit"
	reddit_args[dl_provider]="apkmirror"
	#shellcheck disable=SC2034
	reddit_args[regexp]="APK</span>[^@]*@\([^#]*\)"
	if [ "$REDDIT_MODULE" = true ]; then
		reddit_args[module_prop_name]="rdtrv-magisk"
		reddit_args[module_update_json]="rdt-update.json"
	fi

	build_rv reddit_args
}

build_tiktok() {
	declare -A tiktok_args
	tiktok_args[app_name]="TikTok"
	tiktok_args[is_module]="$TIKTOK_MODULE"
	tiktok_args[patcher_args]="${TIKTOK_PATCHER_ARGS} -m ${RV_INTEGRATIONS_APK}"
	tiktok_args[arch]="all"
	tiktok_args[custom_module]="$TIKTOK_MODULE"
	tiktok_args[rip_all_libs]="$TIKTOK_MODULE"
	tiktok_args[pkg_name]="com.zhiliaoapp.musically"
	tiktok_args[apkmirror_dlurl]="tiktok-pte-ltd/tik-tok-including-musical-ly/tik-tok-including-musical-ly"
	tiktok_args[dl_provider]="apkmirror"
	#shellcheck disable=SC2034
	tiktok_args[regexp]="APK</span>[^@]*@\([^#]*\)"
	if [ "$TIKTOK_MODULE" = true ]; then
	tiktok_args[module_prop_name]="ttrv-magisk"
	tiktok_args[module_update_json]="tt-update.json"
	fi

	build_rv tiktok_args
}

build_spotify() {
	declare -A spotify_args
	spotify_args[app_name]="Spotify"
	spotify_args[is_module]="$SPOTIFY_MODULE"
	spotify_args[patcher_args]="${SPOTIFY_PATCHER_ARGS} -m ${RV_INTEGRATIONS_APK}"
	spotify_args[arch]="all"
	spotify_args[custom_module]="$SPOTIFY_MODULE"
	spotify_args[rip_all_libs]="$SPOTIFY_MODULE"
	spotify_args[pkg_name]="com.spotify.music"
	spotify_args[uptodown_dlurl]="https://spotify.en.uptodown.com/android/apps/16806/versions"
	spotify_args[dl_provider]="uptodown"
	#shellcheck disable=SC2034
	spotify_args[regexp]="APK</span>[^@]*@\([^#]*\)"
	if [ "$SPOTIFY_MODULE" = true ]; then
	spotify_args[module_prop_name]="sprv-magisk"
	spotify_args[module_update_json]="sp-update.json"
	fi

	build_rv spotify_args
}

postfsdata_sh() { echo "${POSTFSDATA_SH//__PKGNAME/$1}" >"${MODULE_TEMPLATE_DIR}/post-fs-data.sh"; }
uninstall_sh() { echo "${UNINSTALL_SH//__PKGNAME/$1}" >"${MODULE_TEMPLATE_DIR}/uninstall.sh"; }
service_sh() {
	s="${SERVICE_SH//__MNTDLY/$MOUNT_DELAY}"
	echo "${s//__PKGNAME/$1}" >"${MODULE_TEMPLATE_DIR}/service.sh"
}
customize_sh() {
	s="${CUSTOMIZE_SH//__PKGNAME/$1}"
	echo "${s//__MDVRSN/$2}" >"${MODULE_TEMPLATE_DIR}/customize.sh"
}

module_prop() {
	echo "id=${1}
name=${2}
version=v${3}
versionCode=${NEXT_VER_CODE}
author=E85 Addict
description=${4}" >"${MODULE_TEMPLATE_DIR}/module.prop"

	if [ "$ENABLE_MAGISK_UPDATE" = true ]; then
		echo "updateJson=${5}" >>"${MODULE_TEMPLATE_DIR}/module.prop"
	fi
}
