#!/bin/bash

set -Eeuo pipefail

function msg() {
    echo "$@" >&2
}
function die() {
    msg "$@"
    exit 1
}
UNAME=$(uname -a) || die "uname -a failed."
function check_system() {
    echo "$UNAME" | grep -iq "${1}" 2>/dev/null
}
function command_exists() {
    command -v "$1" &>/dev/null
}
function do_system_check() {
    command_exists wget || die "command 'wget' not found, please install it"
    command_exists dirname || die "command 'dirname' not found, please install coreutils"
    command_exists tar || die "command 'tar' not found, please install it"
    command_exists gzip || die "command 'gzip' not found, please install it"
}
function download_file() {
    local url="$1"
    local temp="$TMP/$(basename "${url}")"
    
    msg "Download file from $url:"
    if [[ -e "$temp" ]] ; then
        msg "    use cached file."
    else
        wget "$url" -O "${temp}.downloading" \
        	--continue --show-progress --progress=bar:force:noscroll || die "Cannot download."
        mv "${temp}.downloading" "${temp}"
        msg "    saved at ${temp}"
    fi
    echo "$temp"
}
function replace_line() {
	local FILE="$1" KEY="$2" RESULT="$3"
	local OLD=$(< "$FILE")
	local MID=$(echo "$OLD" | sed -E "s#^$KEY\b.+\$#__REPLACE_LINE__#g")
	if [[ "$MID" == "$OLD" ]] ; then
		local NEW="$OLD
$RESULT
"
	else
		local NEW=${MID/__REPLACE_LINE__/"$RESULT"}
	fi

	if [[ "$OLD" != "$NEW" ]] ; then
		msg -e "modify file '$FILE'\n    \e[2m$RESULT\e[0m"
		echo "$NEW" > "$FILE"
	fi
}
function rebuild_global_packages() {
    local ITEMS=()
    local i
    local j
    cd "$1"
    for i in */ ; do
        i=${i%/}
        if echo "$i" | grep -qE '^@' &>/dev/null ; then
            for j in "$i"/*/ ; do
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
    if command_exists sudo ; then
        msg "re-invoke with sudo... (will fail if password is required from commandline)"
        exec sudo bash
    fi
fi

TMP="${TMPDIR-"/tmp"}"
msg "system temp dir is $TMP"
cd "$TMP"
{ touch .test && unlink .test ; } || die "System temp direcotry '$TMP' is not writable."

do_system_check

PREFIX=/usr/nodejs
BIN=${PREFIX}/bin/node
NPM=${PREFIX}/bin/npm
TMP_VERSION="$TMP/latest-nodejs.txt"

OLD_EXISTS="0"
if [[ -e "$BIN" ]]; then
    msg "old nodejs exists."
    OLD_EXISTS="1"
fi

if command_exists node && [[ "$(command -v node)" != "$BIN" ]] ; then
    msg -e "\e[38;5;9mAnother node.js installed at $(command -v node)!\e[0m"
    msg "    this will cause error!"
fi

if [ ! -f "$TMP_VERSION" ]; then
    msg "fetch current version: "
    wget --quiet https://nodejs.org/dist/latest/ -O "$TMP_VERSION" --quiet || die "can not get https://nodejs.org/dist/latest/"
    msg " -> ok."
else
    msg " -> $(basename "$TMP_VERSION") exists"
fi

if check_system darwin ; then
    PACKAGE_TAG="darwin"
    elif check_system cygwin ; then
    PACKAGE_TAG="win"
    elif check_system linux ; then
    PACKAGE_TAG="linux"
else
    die "only support: Darwin(Mac OS), Cygwin, Linux (RHEL & WSL)"
fi
msg " * system name: ${PACKAGE_TAG}"

NODE_PACKAGE=$(grep -Eo 'href="node-v[0-9.]+-'${PACKAGE_TAG}'-x64.tar.xz"' "$TMP_VERSION" | sed 's/^href="//; s/"$//') \
	|| die "failed to detect nodejs version from downloaded html. (file has saved at '$TMP_VERSION')"
msg " * package name: ${NODE_PACKAGE}"

if [[ ${OLD_EXISTS} -eq 1 ]]; then
    if echo "${NODE_PACKAGE}" | grep -q "$($BIN -v)"; then
        unlink "$TMP_VERSION" || true
        msg "official node.js not updated:"
        msg "    current version: $($BIN -v)"
        exit 0
    fi
fi

msg "Installing NodeJS..."
NODEJS_ZIP_FILE=$(download_file "https://nodejs.org/dist/latest/${NODE_PACKAGE}")
YARN_ZIP_FILE=$(download_file "https://yarnpkg.com/latest-rc.tar.gz")

mkdir -p "$PREFIX" || die "Can not create directory at '$PREFIX'"

msg "    extracting file:"
tar xf "$NODEJS_ZIP_FILE" --strip-components=1 -C "$PREFIX" || die "     -> \e[38;5;9mfailed\e[0m."
msg "     -> ok."

if [[ -e $BIN ]]; then
    V=$($BIN -v 2>&1) || die "emmmmmm... binary file '$BIN' is not executable. that's weird."
    msg "  * node.js: $V"
else
    die "error... something wrong... no '$BIN' after extract."
fi

echo "_NODE_JS_INSTALL_PREFIX='$PREFIX'" > /etc/profile.d/nodejs.sh
echo '
if ! echo ":$PATH:" | grep -q "$_NODE_JS_INSTALL_PREFIX/bin" ; then
	export PATH="$PATH:$_NODE_JS_INSTALL_PREFIX/bin:$_NODE_JS_INSTALL_PREFIX/yarn/bin:./node_modules/.bin"
fi
unset _NODE_JS_INSTALL_PREFIX
' >> /etc/profile.d/nodejs.sh
source /etc/profile.d/nodejs.sh

msg "Installing yarn package manager..."
rm -rf "$PREFIX/yarn"
mkdir -p "$PREFIX/yarn"
tar -zxf "$YARN_ZIP_FILE" -C "$PREFIX/yarn" --strip-components=1 || die "     -> \e[38;5;9mfailed\e[0m."
    V=$("$PREFIX/yarn/bin/yarn" -v -v 2>&1) || die "emmmmmm... binary file '$PREFIX/yarn/bin/yarn' is not executable. that's weird."
msg "  * yarn: $V"

mkdir -p "$PREFIX/etc" || true
[[ -e "$PREFIX/etc/yarnrc" ]] || touch "$PREFIX/etc/yarnrc" || true
[[ -e "$PREFIX/etc/npmrc" ]] || touch "$PREFIX/etc/npmrc" || true

replace_line "$PREFIX/etc/yarnrc" 'global-folder' "global-folder \"/usr/nodejs/lib\""
replace_line "$PREFIX/etc/npmrc" 'prefix' "prefix = \"$PREFIX\""

if ! command_exists unpm ; then
    msg "Installing unpm package manager..."
    yarn global add --silent --progress @idlebox/package-manager || msg "Failed to install @idlebox/package-manager. that is not fatal."
    msg " -> ok."
fi
if ! command_exists pnpm ; then
    msg "Installing pnpm package manager..."
    yarn global add --silent --progress pnpm || msg "Failed to install pnpm. that is not fatal."
    msg " -> ok."
fi

if [ "${OLD_EXISTS}" ]; then
    msg "rebuild global node_modules folder..."
    CONFIG_PREFIX=$(/usr/nodejs/bin/npm config --global get prefix)
    rebuild_global_packages "$CONFIG_PREFIX"
fi
msg "nodejs install success."
msg 'You should run "source /etc/profile.d/nodejs.sh" or restart current session to take effect.'
