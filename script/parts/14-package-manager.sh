#!/usr/bin/env bash

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

function install_pnpm() {
	msg "Installing pnpm..."

	rm -rf "$PREFIX/bin/npm" "$PREFIX/bin/npx" "$PREFIX/lib/node_modules/npm"

	corepack enable npm pnpm yarn
	echo -n "    - pnpm: "
	pnpm --version
	echo -n "    - npm: "
	npm --version
}

function install_other_packages() {
	msg "Installing other package managers..."
	"$PNPM" -g add unipm @microsoft/rush @gongt/pnpm-instead-npm
}
