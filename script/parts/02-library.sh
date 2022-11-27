#!/bin/bash

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

function do_system_check() {
	command_exists wget || die "command 'wget' not found, please install it"
	command_exists dirname || die "command 'dirname' not found, please install coreutils"
	command_exists tar || die "command 'tar' not found, please install it"
	command_exists gzip || die "command 'gzip' not found, please install it"

	if command_exists node && [[ "$(command -v node)" != "$BIN" ]]; then
		msg "\e[38;5;9mAnother node.js installed at $(command -v node)!\e[0m"
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
