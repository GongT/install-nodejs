#!/bin/bash

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
