#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	echo "not privileged user."
	exec sudo bash
fi

OLD_EXISTS="0"
if [ -e /usr/local/bin/node ]; then
	echo "old nodejs exists."
	OLD_EXISTS="1"
fi

function die {
	echo "$@" >&2
	exit 1
}
set -e
cd /tmp

if [ ! -f latest-nodejs.txt ]; then
	echo "fetch current version: "
	curl -s https://nodejs.org/dist/latest/ > latest-nodejs.txt || die "can not get https://nodejs.org/dist/latest/"
	echo "  ok."
else
	echo "  latest-nodejs.txt exists"
fi

UNAME="$(uname -a)"
function check_system {
	echo "${UNAME}" | grep -iq "${1}" 2>/dev/null
}

if check_system darwin ; then
	PACKAGE_TAG="darwin"
elif check_system cygwin ; then
	PACKAGE_TAG="win"
elif check_system linux ; then
	PACKAGE_TAG="linux"
else
	echo "only support: Darwin(Mac OS), Cygwin, Linux (RHEL & WSL)" >&2
	exit 1
fi
echo "system name: ${PACKAGE_TAG}"

NODE_PACKAGE=$(grep -Eo "href=\"node-v[0-9.]+-${PACKAGE_TAG}-x64.tar.xz\"" latest-nodejs.txt | sed 's/^href="//; s/"$//')
echo "  package name: ${NODE_PACKAGE}"

if [ ${OLD_EXISTS} -eq 1 ]; then
	if echo "${NODE_PACKAGE}" | grep -q "$(/usr/local/bin/node -v)"; then
		unlink latest-nodejs.txt
		echo "official node.js not updated:"
		echo "  current version: $(/usr/local/bin/node -v)"
		exit 0
	fi
fi

echo "installing..."
echo "	downloading file: https://nodejs.org/dist/latest/${NODE_PACKAGE}"
wget --continue https://nodejs.org/dist/latest/${NODE_PACKAGE} --progress=bar:force -O nodejs.tar.xz

unlink latest-nodejs.txt

if [ -e "nodejs-install-temp-dir" ]; then
	rm -rf nodejs-install-temp-dir
fi
mkdir nodejs-install-temp-dir

echo "	extracting file: nodejs.tar.xz"
tar xf nodejs.tar.xz -C nodejs-install-temp-dir && unlink nodejs.tar.xz

cd nodejs-install-temp-dir/*

echo "	copy nodejs to /usr/local ..."
rm -f /usr/local/bin/node
cp -r */ /usr/local
echo "complete."

cd /tmp

rm -rf nodejs-install-temp-dir

echo ""

if [ -e /usr/local/bin/node ]; then
	echo -n "  node.js: "
	/usr/local/bin/node -v
else
	echo "error... something wrong... no /usr/local/bin/node after extract."
	exit 1
fi

function install {
	local ITEMS=()
	local i
	local j
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
	
	npm rebuild "${ITEMS[@]}"
}
if [ "${OLD_EXISTS}" ]; then
	PREFIX=$(/usr/local/bin/npm config --global get prefix)
	cd "${PREFIX}/lib/node_modules"
	
	install || die "nodejs install success. But can not rebuild some global packages. This may or may not cause error."
fi

echo "nodejs install success."

if ! command -v node &>/dev/null; then
	echo "you must add /usr/local/bin to your \$PATH"
fi
