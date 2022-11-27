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

	platform="$(detect_platform)" || die "Not supported platform"
	arch="$(detect_arch)" || die "Not supported architectures."

	TMP_JSON=$(mktemp --dry-run)
	download_file "https://registry.npmjs.org/@pnpm/exe" "$TMP_JSON"
	version=$(tr '{' '\n' <"$TMP_JSON" | awk -F '"' '/latest/ { print $4 }')

	PNPM_ARCHIVE=$(download_file "https://registry.npmjs.org/@pnpm/${platform}-${arch}/-/${platform}-${arch}-${version}.tgz")

	msg "    extracting file:"
	tar xf "$PNPM_ARCHIVE" --strip-components=1 -C "$TMPDIR" || die "     -> \e[38;5;9mfailed\e[0m."
	msg "     -> ok."

	chmod a+x "$TMPDIR/pnpm"
	msg "    * $("$TMPDIR/pnpm" --version)"
	rm -f "$TMP_JSON"

	export PNPM_HOME="$PREFIX/pnpm-global"
	export npm_config_global_bin_dir="$PREFIX/bin"
	"$TMPDIR/pnpm" -g add pnpm @gongt/pnpm-instead-npm
}

function install_other_packages() {
	msg "Installing other package managers..."
	"$PNPM" -g add yarn unipm @microsoft/rush
	# pnpm -g add @gongt/pnpm-instead-npm
}
