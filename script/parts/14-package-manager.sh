#!/usr/bin/env bash

### curl https://get.pnpm.io/install.sh

_fetch() {
	curl -fsSL "$1"
}

download_using_pnpm() {
	local http_proxy='' https_proxy='' all_proxy='' HTTP_PROXY='' HTTPS_PROXY='' ALL_PROXY=''
	msg "  metadata: $npm_config_registry/pnpm"
	version_json="$(_fetch "$npm_config_registry/pnpm")" || die "Download Error!"
	version="$(printf '%s' "${version_json}" | jq -r '."dist-tags".latest')"
	msg "  version: $version"

	archive_url="$(printf '%s' "${version_json}" | jq --arg version "$version" -r '.versions[$version].dist.tarball')"
	msg "  tarball: $archive_url"

	curl -fL "$archive_url" >"pnpm.tgz.download"
	mv "pnpm.tgz.download" "pnpm.tgz"
	tar xf "pnpm.tgz"

	"$BIN" ./package/bin/pnpm.cjs -g add pnpm@latest npm@latest yarn@latest || die "failed execute temp file"
}

function install_package_managers() {
	TMPD=$(mktemp -d)
	pushd "$TMPD" >/dev/null || die "temp dir not found!"
	msg "Installing package managers..."

	rm -rf "$PREFIX/bin/npm" "$PREFIX/bin/npx" "$PREFIX/lib/node_modules"
	download_using_pnpm

	echo -n "    - pnpm: "
	"$PNPM" --version
	echo -n "    - npm: "
	"$NPM" --version
	echo -n "    - yarn: "
	"$YARN" --version

	popd >/dev/null || die "???"
	rm -rf "$TMPD"
}

function install_other_packages() {
	msg "Installing other package managers..."
	"$PNPM" -g add unipm @microsoft/rush
}
