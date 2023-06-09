#!/usr/bin/env bash

set -Eeuo pipefail

declare -r PREFIX=/usr/nodejs
UNAME=$(uname -a) || die "uname -a failed."

declare -r BIN=${PREFIX}/bin/node
declare -r NPM=${PREFIX}/bin/npm
declare -r PNPM=${PREFIX}/bin/pnpm
declare -r YARN=$PREFIX/yarn/bin/yarn

INSTALL_VERSION="${1-latest}"

if ! [[ "${TMPDIR:-}" ]]; then
	export TMPDIR="/tmp"
fi

declare -r TMP_VERSION="$TMPDIR/nodejs-version-$INSTALL_VERSION.txt"
declare -r TMP_INDEX="$TMPDIR/nodejs-versions-list.txt"

function msg() {
	echo -e "$*" >&2
}
function die() {
	msg "$@"
	exit 1
}

function check_system() {
	echo "$UNAME" | grep -iq "${1}" 2>/dev/null
}

function command_exists() {
	local -r PATH="$PATH:$PREFIX/bin"
	command -v "$1" &>/dev/null
}

function find_command() {
	local -r PATH="$PATH:$PREFIX/bin"
	command -v "$1"
}

function do_system_check() {
	command_exists wget || die "command 'wget' not found, please install it"
	command_exists dirname || die "command 'dirname' not found, please install coreutils"
	command_exists tar || die "command 'tar' not found, please install it"
	command_exists gzip || die "command 'gzip' not found, please install it"

	if command_exists node && [[ "$(find_command node)" != "$BIN" ]]; then
		msg "\e[38;5;9mAnother node.js installed at $(find_command node)!\e[0m"
		msg "    this will cause error!"
		exit 1
	fi
}

function _wget() {
	if wget --help 2>&1 | grep -q -- '--show-progress'; then
		wget --continue --quiet --show-progress --progress=bar:force:noscroll "$1" -O "$2"
	else
		wget -c -q "$1" -O "$2"
	fi
}

function download_file() {
	local url="$1" temp
	temp="$DOWNLOAD/$(basename "${url}")"
	local save_at=${2-"$temp"}

	msg "Download file from $url:"
	msg "    to: $save_at"
	if [[ -e $save_at ]]; then
		msg "    use cached file."
	else
		_wget "$url" "${save_at}.downloading" || die "Cannot download."
		mv "${save_at}.downloading" "${save_at}"
		msg "    saved at ${save_at}"
	fi
	if [[ -z ${2-""} ]]; then
		echo "$save_at"
	fi
}

function replace_line() {
	local FILE="$1" KEY="$2" RESULT="$3" OLD MID
	OLD=$(<"$FILE")
	MID=$(echo "$OLD" | sed -E "s#^${KEY}[ =].+\$#__REPLACE_LINE__#g")
	if [[ $MID == "$OLD" ]]; then
		local NEW="$OLD
$RESULT
"
	else
		local NEW=${MID/__REPLACE_LINE__/"$RESULT"}
	fi

	if [[ $OLD != "$NEW" ]]; then
		msg "modify file '$FILE'\n    \e[2m$RESULT\e[0m"
		echo "$NEW" >"$FILE"
	fi
}

function rebuild_global_packages() {
	local ITEMS=()
	local i
	local j
	cd "$1"
	for i in */; do
		i=${i%/}
		if echo "$i" | grep -qE '^@' &>/dev/null; then
			for j in "$i"/*/; do
				j=${j%/}
				if [ ! -L "$j" ]; then
					ITEMS+=("$j")
				fi
			done
		elif [ ! -L "$i" ]; then
			ITEMS+=("$i")
		fi
	done

	$NPM rebuild "${ITEMS[@]}" || {
		msg -e "\e[38;5;11mGlobal packages not rebuilt. This may or may not cause error.\e[0m"
		msg "    the command is: $NPM rebuild ${ITEMS[*]}"
	}
}

function install_nodejs() {
	msg "fetch version '$INSTALL_VERSION': "
	if [[ $INSTALL_VERSION == "latest" ]]; then
		download_file "https://nodejs.org/dist/latest/" "${TMP_VERSION}"
	elif [[ $INSTALL_VERSION -gt 0 ]]; then
		download_file "https://nodejs.org/dist/" "${TMP_INDEX}"

		LATEST_SUB_VERSION=$(grep -Eo ">v${INSTALL_VERSION}\.[0-9]+\.[0-9]+/<" "${TMP_INDEX}" | grep -Eo "v${INSTALL_VERSION}\.[0-9]+\.[0-9]+" | sort --version-sort | tail -n1) \
			|| die "not found version $INSTALL_VERSION. (file has saved at '$TMP_INDEX')"
		msg "latest version of v$INSTALL_VERSION is $LATEST_SUB_VERSION"
		download_file "https://nodejs.org/dist/$LATEST_SUB_VERSION/" "${TMP_VERSION}"
		INSTALL_VERSION="$LATEST_SUB_VERSION"
	else
		die "requested install version ($INSTALL_VERSION) is not valid."
	fi
	msg " -> ok."

	if check_system darwin; then
		PACKAGE_TAG="darwin"
	elif check_system cygwin; then
		PACKAGE_TAG="win"
	elif check_system linux; then
		PACKAGE_TAG="linux"
	else
		die "only support: Darwin(Mac OS), Cygwin, Linux (RHEL & WSL)\n  * windows use install.ps1"
	fi
	msg " * system name: ${PACKAGE_TAG}"

	NODE_PACKAGE=$(grep -Eo 'href="node-v[0-9.]+-'${PACKAGE_TAG}'-x64.tar.xz"' "$TMP_VERSION" | sed 's/^href="//; s/"$//') \
		|| die "failed to detect nodejs version from downloaded html. (file has saved at '$TMP_VERSION')"
	msg " * package name: ${NODE_PACKAGE}"

	if [[ -e $BIN ]]; then
		msg "old nodejs exists."
		if echo "${NODE_PACKAGE}" | grep -q "$($BIN -v)"; then
			rm "$TMP_VERSION" || true
			msg "official node.js not updated:"
			msg "    current version: $($BIN -v)"
			if [[ ${FORCE+found} != found ]] || [[ ${FORCE} != yes ]]; then
				msg "set environment 'FORCE=yes' to reinstall"
				return
			fi
			msg "    FORCE UPDATE!"
		else
			msg "official node.js updated:"
			msg "    current version: $($BIN -v)"
		fi
	fi

	msg "Installing NodeJS..."
	NODEJS_ZIP_FILE=$(download_file "https://nodejs.org/dist/$INSTALL_VERSION/${NODE_PACKAGE}")

	msg "    extracting file:"
	tar xf "$NODEJS_ZIP_FILE" --strip-components=1 -C "$PREFIX" || die "     -> \e[38;5;9mfailed\e[0m."
	msg "     -> ok."

	if [[ -e $BIN ]]; then
		V=$($BIN -v 2>&1) || die "emmmmmm... binary file '$BIN' is not executable. that's weird."
		msg "  * node.js: $V"
	else
		die "error... something wrong... no '$BIN' after extract."
	fi
}

function create_nodejs_profile() {
	msg "Creating profile..."
	{
		echo "### Generated file, DO NOT MODIFY"
		echo "_NODE_JS_INSTALL_PREFIX='$PREFIX'"
		cat <<-'DATA'
			if ! echo ":$PATH:" | grep -q "$_NODE_JS_INSTALL_PREFIX/bin" ; then
				export PATH="$PATH:./node_modules/.bin:./common/temp/bin:$_NODE_JS_INSTALL_PREFIX/bin"
			fi
			unset _NODE_JS_INSTALL_PREFIX
		DATA
		echo
	} >/etc/profile.d/nodejs.sh
	msg "Loading profile..."
	source /etc/profile.d/nodejs.sh
}

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
	if ! grep -qE '\bregistry\s*=' "$PREFIX/etc/npmrc"; then
		CHINA=$(timing_registry registry.npmmirror.com)
		ORIGINAL=$(timing_registry registry.npmjs.org)

		if [[ $CHINA -le $ORIGINAL ]]; then
			echo "Using TaoBao npm mirror: npmmirror.com"
			replace_line "$PREFIX/etc/npmrc" 'registry' "registry=https://registry.npmmirror.com/"
		else
			replace_line "$PREFIX/etc/npmrc" 'registry' "registry=https://registry.npmjs.org/"
		fi
		replace_line "$PREFIX/etc/npmrc" 'noproxy' "noproxy=registry.npmmirror.com,cdn.npmmirror.com,npmmirror.com"
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

### curl https://get.pnpm.io/install.sh

detect_platform() {
	local platform
	platform="$(uname -s | tr '[:upper:]' '[:lower:]')"

	case "${platform}" in
	linux) platform="linux" ;;
	darwin) platform="macos" ;;
	windows) platform="win" ;;
	esac

	printf '%s' "${platform}"
}

detect_arch() {
	local arch
	arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

	case "${arch}" in
	x86_64) arch="x64" ;;
	amd64) arch="x64" ;;
	armv*) arch="arm" ;;
	arm64 | aarch64) arch="arm64" ;;
	esac

	# `uname -m` in some cases mis-reports 32-bit OS as 64-bit, so double check
	if [ "${arch}" = "x64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
		arch=i686
	elif [ "${arch}" = "arm64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
		arch=arm
	fi

	case "$arch" in
	x64*) ;;
	arm64*) ;;
	*) return 1 ;;
	esac
	printf '%s' "${arch}"
}

function install_pm() {
	msg "Installing package managers..."

	corepack enable pnpm yarn
	echo -n "    - npm: "
	npm --version
	echo -n "    - pnpm: "
	pnpm --version
	echo -n "    - yarn: "
	yarn --version
}

function install_other_packages() {
	msg "Installing other package managers..."
	"$PNPM" -g add unipm @microsoft/rush @gongt/pnpm-instead-npm
}

if command_exists id && [[ "$(id -u)" -ne 0 ]]; then
	msg "not privileged user."
	if command_exists sudo; then
		msg "re-invoke with sudo... (will fail if password is required from commandline)"
		exec sudo bash
	fi
fi

mkdir -p "$PREFIX" || die "Can not create directory at '$PREFIX'"

if [[ ${SYSTEM_COMMON_CACHE+found} == found ]]; then
	declare -r DOWNLOAD="${SYSTEM_COMMON_CACHE}/Download"
	msg "download dir is $DOWNLOAD"
else
	declare -r DOWNLOAD="${TMPDIR-"/tmp"}"
	msg "temp download dir is $DOWNLOAD"
fi
(
	mkdir -p "$DOWNLOAD"
	cd "$DOWNLOAD"
	touch .test && rm .test
) || die "System temp direcotry '$DOWNLOAD' is not writable."

do_system_check
install_nodejs
create_nodejs_profile
update_config

install_pm
install_other_packages
