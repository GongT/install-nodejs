#!/usr/bin/env bash

function timing_registry() {
	local REG="$1"
	local http_proxy='' https_proxy='' all_proxy='' HTTP_PROXY='' HTTPS_PROXY='' ALL_PROXY=''
	local ts tt

	nslookup "$REG" &>/dev/null

	ts=$(date +%s%N)
	curl "https://$REG/" &>/dev/null || true
	curl "https://$REG/debug/package.json" &>/dev/null || true
	tt=$(($(date +%s%N) - ts))

	echo "Timing: [$tt] $REG" >&2
	echo "$tt"
}

function update_config() {
	mkdir -p "$PREFIX/etc" || true
	[[ -e "$PREFIX/etc/yarnrc" ]] || touch "$PREFIX/etc/yarnrc" || true
	[[ -e "$PREFIX/etc/npmrc" ]] || touch "$PREFIX/etc/npmrc" || true

	replace_line "$PREFIX/etc/yarnrc" 'global-folder' 'global-folder "/usr/nodejs/lib"'
	replace_line "$PREFIX/etc/npmrc" 'prefix' "prefix=$PREFIX"
	replace_line "$PREFIX/etc/npmrc" 'global-dir' "global-dir=$PREFIX/lib/pnpm-global"
	replace_line "$PREFIX/etc/npmrc" 'global-bin-dir' "global-bin-dir=$PREFIX/bin"
	replace_line "$PREFIX/etc/npmrc" 'access' "access=public"
	replace_line "$PREFIX/etc/npmrc" 'always-auth' 'always-auth=false'
	replace_line "$PREFIX/etc/npmrc" 'fetch-retries' 'fetch-retries=1000'
	replace_line "$PREFIX/etc/npmrc" 'network-concurrency' 'network-concurrency=3'
	replace_line "$PREFIX/etc/npmrc" 'prefer-offline' 'prefer-offline=true'

	set_registy
	set_cache_path
}

function set_registy() {
	export npm_config_registry='https://registry.npmjs.org'
	if ! grep -qE '\bregistry\s*=' "$PREFIX/etc/npmrc"; then
		CHINA=$(timing_registry registry.npmmirror.com)
		ORIGINAL=$(timing_registry registry.npmjs.org)

		if [[ $CHINA -le $ORIGINAL ]]; then
			echo "Using TaoBao npm mirror: npmmirror.com"
			replace_line "$PREFIX/etc/npmrc" 'registry' "registry=https://registry.npmmirror.com"
			export npm_config_registry='https://registry.npmmirror.com'
		else
			replace_line "$PREFIX/etc/npmrc" 'registry' "registry=https://registry.npmjs.org"
		fi
		replace_line "$PREFIX/etc/npmrc" 'noproxy' "noproxy=registry.npmmirror.com,cdn.npmmirror.com,npmmirror.com"
	else
		reg=$(grep -E '^registry\s*=' "$PREFIX/etc/npmrc" | tr '=' ' ' | awk '{print $2}')
		if [[ $reg == http* ]]; then
			echo "Using Config npm registry: $reg"
			export npm_config_registry="${reg%/}"

		fi
	fi
}

function set_cache_path() {
	if [[ ${SYSTEM_COMMON_CACHE+found} == found ]]; then
		echo "Reset cache folder(s) to $SYSTEM_COMMON_CACHE"
		replace_line "$PREFIX/etc/npmrc" 'cache' "cache=$SYSTEM_COMMON_CACHE/npm"
		replace_line "$PREFIX/etc/yarnrc" 'cache-folder' "cache-folder \"$SYSTEM_COMMON_CACHE/yarn\""

		echo "export JSPM_GLOBAL_PATH='$SYSTEM_COMMON_CACHE/jspm'" >>/etc/profile.d/nodejs.sh
	fi
}
