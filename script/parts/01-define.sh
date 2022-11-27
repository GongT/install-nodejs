#!/usr/bin/env bash

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
