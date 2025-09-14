#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit extglob nullglob globstar lastpipe shift_verbose

if command_exists id && [[ "$(id -u)" -ne 0 ]]; then
	msg "not privileged user."
	if command_exists sudo; then
		msg "re-invoke with sudo... (will fail if password is required from commandline)"
		exec sudo bash
	fi
fi

if [[ -e "/data/DevelopmentRoot" ]]; then
	declare -x PNPM_HOME=/data/DevelopmentRoot/pnpm
else
	declare -x PNPM_HOME=/usr/local/share/pnpm
fi
declare -r PNPM_BIN="$PNPM_HOME/pnpm"

if ! [[ "${TMPDIR:-}" ]]; then
	export TMPDIR="/tmp"
fi
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP

function msg() {
	echo -e "$*" >&2
}
function die() {
	msg "$@"
	exit 1
}

function _wget() {
	if wget --help 2>&1 | grep -q -- '--show-progress'; then
		wget --continue --quiet --show-progress --progress=bar:force:noscroll "$1" -O "$2"
	else
		wget -c -q "$1" -O "$2"
	fi
}

function timing_registry() {
	local REG="$1" TIMEOUT="${2-5}"
	local http_proxy='' https_proxy='' all_proxy='' HTTP_PROXY='' HTTPS_PROXY='' ALL_PROXY=''
	local ts te tt

	nslookup "$REG" &>/dev/null

	ts=$(date '+%s.%N')
	curl --connect-timeout "$TIMEOUT" "https://$REG/" &>/dev/null || true
	curl --connect-timeout "$TIMEOUT" "https://$REG/debug/package.json" &>/dev/null || true
	te=$(date '+%s.%N')

	tt=$(echo "$te" "$ts" | awk '{printf "%f", $1 - $2}')

	echo "Timing: [$tt] $REG" >&2
	printf "%s" "$tt"
}

function set_registry() {
	local CHINA ORIGINAL CHINA_FASTER
	CHINA=$(timing_registry registry.npmmirror.com)
	ORIGINAL=$(timing_registry registry.npmjs.org)
	CHINA_FASTER=$(printf "%f < %f\n" "${CHINA}" "${ORIGINAL}" | bc)

	if [[ $CHINA_FASTER -eq 1 ]]; then
		echo "Using TaoBao npm mirror: npmmirror.com"
		export npm_config_registry='https://registry.npmmirror.com'
	else
		echo "Using Global npm mirror: registry.npmjs.org"
		export npm_config_registry='https://registry.npmjs.org'
	fi
}

is_glibc_compatible() {
	getconf GNU_LIBC_VERSION >/dev/null 2>&1 || ldd --version >/dev/null 2>&1 || return 1
}

detect_platform() {
	local platform
	platform="$(uname -s | tr '[:upper:]' '[:lower:]')"

	case "${platform}" in
	linux)
		if is_glibc_compatible; then
			platform="linux"
		else
			platform="linuxstatic"
		fi
		;;
	darwin) platform="macos" ;;
	windows) platform="win" ;;
	mingw*) platform="win" ;;
	esac

	printf '%s' "${platform}"
}

detect_arch() {
	local arch
	arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

	case "${arch}" in
	x86_64 | amd64) arch="x64" ;;
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

_pnpm_download_and_install() {
	local platform arch version_json version archive_url temp_bin
	platform="$(detect_platform)"

	if [ "${platform}" = "win" ]; then
		die "this script does not support Windows, please use pwsh script (install.ps1)"
	fi

	arch="$(detect_arch)" || die "Sorry! pnpm currently only provides pre-built binaries for x86_64/arm64 architectures."
	version_json="$(wget -qO- "${npm_config_registry}/@pnpm/exe")" || die "Download Error!"
	version="$(echo "$version_json" | grep -o '"latest":[[:space:]]*"[0-9.]*"' | grep -o '[0-9.]*')"

	archive_url="https://github.com/pnpm/pnpm/releases/download/v${version}/pnpm-${platform}-${arch}"
	temp_bin="$tmp_dir/pnpm-${version}-${platform}-${arch}"

	msg "Downloading pnpm binaries ${version}"
	# download the binary to the specified directory
	_wget "$archive_url" "$temp_bin"
	chmod +x "$temp_bin"

	mkdir -p "$PNPM_HOME"

	if [[ -e ${PNPM_BIN} ]]; then
		rm -f "${PNPM_BIN}.old"
		mv "${PNPM_BIN}" "${PNPM_BIN}.old"
		rm -f "${PNPM_BIN}.old" || true
	fi

	cp -f "$temp_bin" "${PNPM_BIN}"
}

function install_pnpm() {
	if [[ -e ${PNPM_BIN} ]]; then
		CURRENT_VERSION=$("${PNPM_BIN}" --version)

		"${PNPM_BIN}" self-update
		NEW_VERSION=$("${PNPM_BIN}" --version)
	else
		_pnpm_download_and_install
	fi
}

function remove_section_from_bashrc() {
	local FILE="$HOME/.bashrc"
	local START="# pnpm" END="# pnpm end"
	if grep -q "$START" "$FILE"; then
		sed -i "/$START/,/$END/d" "$FILE"
		msg "Removed pnpm section from $FILE"
	fi
}

function create_nodejs_profile() {
	msg "Creating profile..."
	{
		echo "### Generated file, DO NOT MODIFY"
		printf 'export npm_config_registry=%q\n' "$npm_config_registry"
		printf 'export PNPM_HOME=%q\n' "$PNPM_HOME"
		cat <<-'DATA'
			if ! echo ":$PATH:" | grep -q ":$PNPM_HOME/bin:" ; then
				export PATH="$PATH:./node_modules/.bin:./common/temp/bin:$PNPM_HOME:$PNPM_HOME/bin:$PNPM_HOME/nodejs_current/bin/"
			fi
		DATA
		echo
	} >/etc/profile.d/nodejs.sh
	msg "Loading profile..."
	source /etc/profile.d/nodejs.sh
}

function install_latest_nodejs() {
	local PNPM_ETC="${PNPM_HOME}/etc"

	if [[ -L ~/.config/pnpm ]]; then
		if [[ $(readlink ~/.config/pnpm) != "${PNPM_ETC}" ]]; then
			unlink ~/.config/pnpm
		fi
	elif [[ -e ~/.config/pnpm ]]; then
		if [[ ! -e ${PNPM_ETC} ]]; then
			mv ~/.config/pnpm "${PNPM_ETC}"
		else
			die "$HOME/.config/pnpm folder is exists, need remove it."
		fi
	fi

	if ! [[ -e ~/.config/pnpm ]]; then
		ln -s -T "${PNPM_ETC}" ~/.config/pnpm
	fi

	mkdir -p "${PNPM_ETC}"

	mkdir -p "${PNPM_HOME}/nodejs"
	"${PNPM_BIN}" env use --global latest
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

function update_config() {
	npm config --location=global set \
		"access=public" \
		"fetch-retries=1000" \
		"registry=$npm_config_registry"

	pnpm config --location=global set "global-dir" "${PNPM_HOME}/lib/pnpm-global"
	pnpm config --location=global set 'network-concurrency' '3'
	pnpm config --location=global set 'always-auth' 'false'
	pnpm config --location=global set "global-bin-dir" "${PNPM_HOME}/bin"

	if [[ ${SYSTEM_COMMON_CACHE+found} == found ]]; then
		echo "Reset cache folder(s) to $SYSTEM_COMMON_CACHE"
		npm config --location=global set "cache=$SYSTEM_COMMON_CACHE/npm"
		# replace_line "$PREFIX/etc/yarnrc" 'cache-folder' "cache-folder \"$SYSTEM_COMMON_CACHE/yarn\""

		echo "export JSPM_GLOBAL_PATH='$SYSTEM_COMMON_CACHE/jspm'" >>/etc/profile.d/nodejs.sh
	fi
}

function install_other_packages() {
	msg "Installing other package managers..."
	"${PNPM_BIN}" -g add unipm @microsoft/rush
}

set_registry
install_pnpm

remove_section_from_bashrc
create_nodejs_profile

install_latest_nodejs
update_config
install_other_packages
