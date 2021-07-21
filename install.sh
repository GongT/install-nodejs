#!/bin/bash

set -Eeuo pipefail

function msg() {
	echo -e "$*" >&2
}
function die() {
	msg "$@"
	exit 1
}
declare -r PREFIX=/usr/nodejs
UNAME=$(uname -a) || die "uname -a failed."
function check_system() {
	echo "$UNAME" | grep -iq "${1}" 2>/dev/null
}
function command_exists() {
	local -r PATH="$PATH:$PREFIX/bin"
	command -v "$1" &>/dev/null
}
function do_system_check() {
	command_exists wget || die "command 'wget' not found, please install it"
	command_exists dirname || die "command 'dirname' not found, please install coreutils"
	command_exists tar || die "command 'tar' not found, please install it"
	command_exists gzip || die "command 'gzip' not found, please install it"
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
	MID=$(echo "$OLD" | sed -E "s#^$KEY\b.+\$#__REPLACE_LINE__#g")
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

if command_exists id && [[ "$(id -u)" -ne 0 ]]; then
	msg "not privileged user."
	if command_exists sudo; then
		msg "re-invoke with sudo... (will fail if password is required from commandline)"
		exec sudo bash
	fi
fi

if ! [[ "${TMPDIR:-}" ]]; then
	export TMPDIR="/tmp"
fi
if [[ ${SYSTEM_COMMON_CACHE+found} == found ]]; then
	DOWNLOAD="${SYSTEM_COMMON_CACHE}/Download"
	msg "download dir is $DOWNLOAD"
else
	DOWNLOAD="${TMPDIR-"/tmp"}"
	msg "temp download dir is $DOWNLOAD"
fi
(
	mkdir -p "$DOWNLOAD"
	cd "$DOWNLOAD"
	touch .test && rm .test
) || die "System temp direcotry '$DOWNLOAD' is not writable."

do_system_check

mkdir -p "$PREFIX" || die "Can not create directory at '$PREFIX'"

BIN=${PREFIX}/bin/node
NPM=${PREFIX}/bin/npm
YARN=$PREFIX/yarn/bin/yarn

INSTALL_VERSION="${1-latest}"
TMP_VERSION="$TMPDIR/nodejs-version-$INSTALL_VERSION.txt"
TMP_INDEX="$TMPDIR/nodejs-versions-list.txt"

OLD_EXISTS="0"
if [[ -e $BIN ]]; then
	msg "old nodejs exists."
	OLD_EXISTS="1"
fi

if command_exists node && [[ "$(command -v node)" != "$BIN" ]]; then
	msg "\e[38;5;9mAnother node.js installed at $(command -v node)!\e[0m"
	msg "    this will cause error!"
fi

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

if [[ ${OLD_EXISTS} -eq 1 ]]; then
	if echo "${NODE_PACKAGE}" | grep -q "$($BIN -v)"; then
		rm "$TMP_VERSION" || true
		msg "official node.js not updated:"
		msg "    current version: $($BIN -v)"
		if [[ ${FORCE+found} != found ]] || [[ ${FORCE} != yes ]] && command_exists yarn; then
			exit 0
		fi
		msg "FORCE UPDATE"
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
	msg "  * npm: $($NPM -v || true)"
else
	die "error... something wrong... no '$BIN' after extract."
fi

msg "Creating profile..."
{
	echo "_NODE_JS_INSTALL_PREFIX='$PREFIX'"
	cat <<-'DATA'
		if ! echo ":$PATH:" | grep -q "$_NODE_JS_INSTALL_PREFIX/bin" ; then
			export PATH="$PATH:./node_modules/.bin:$_NODE_JS_INSTALL_PREFIX/bin"
		fi
		unset _NODE_JS_INSTALL_PREFIX
	DATA
	echo
} >/etc/profile.d/nodejs.sh
source /etc/profile.d/nodejs.sh

mkdir -p "$PREFIX/etc" || true
[[ -e "$PREFIX/etc/yarnrc" ]] || touch "$PREFIX/etc/yarnrc" || true
[[ -e "$PREFIX/etc/npmrc" ]] || touch "$PREFIX/etc/npmrc" || true

replace_line "$PREFIX/etc/yarnrc" 'global-folder' 'global-folder "/usr/nodejs/lib"'
replace_line "$PREFIX/etc/npmrc" 'prefix' "prefix = \"$PREFIX\""

if [[ ${SYSTEM_COMMON_CACHE+found} == found ]]; then
	echo "Reset cache folder(s) to $SYSTEM_COMMON_CACHE"
	if [[ "$("$NPM" -g config get cache)" != "$SYSTEM_COMMON_CACHE/npm" ]]; then
		"$NPM" -g config set cache "$SYSTEM_COMMON_CACHE/npm"
	fi
	replace_line "$PREFIX/etc/yarnrc" 'cache-folder' "cache-folder \"$SYSTEM_COMMON_CACHE/yarn\""

	echo "export JSPM_GLOBAL_PATH='$SYSTEM_COMMON_CACHE/jspm'" >>/etc/profile.d/nodejs.sh
fi
"$NPM" -g config delete store-path

declare -a GLOBAL_PACKAGE_TO_INSTALL=()
if ! yarn -v &>/dev/null; then
	GLOBAL_PACKAGE_TO_INSTALL+=(yarn)
fi
if ! unipm -v 2>/dev/null | grep -q -- npm; then
	GLOBAL_PACKAGE_TO_INSTALL+=(unipm)
fi
if ! pnpm -v &>/dev/null; then
	GLOBAL_PACKAGE_TO_INSTALL+=(pnpm)
fi

if [[ ${#GLOBAL_PACKAGE_TO_INSTALL[@]} -gt 0 ]]; then
	msg "Installing ${GLOBAL_PACKAGE_TO_INSTALL[*]}..."
	$NPM -g --unsafe-perm install "${GLOBAL_PACKAGE_TO_INSTALL[@]}" || msg "Failed to install some package manager."
fi

msg "Node.JS install success."
msg 'You should run "source /etc/profile.d/nodejs.sh" or restart current session to take effect.'
