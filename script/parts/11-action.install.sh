#!/bin/bash

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
