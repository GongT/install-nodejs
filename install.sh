#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	echo "not privileged user."
	exec sudo bash
fi

OLD_EXISTS="0"
if [ -e /usr/nodejs/bin/node ]; then
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
	if echo "${NODE_PACKAGE}" | grep -q "$(/usr/nodejs/bin/node -v)"; then
		unlink latest-nodejs.txt
		echo "official node.js not updated:"
		echo "  current version: $(/usr/nodejs/bin/node -v)"
		exit 0
	fi
fi

echo "installing..."
echo "	downloading file: https://nodejs.org/dist/latest/${NODE_PACKAGE}"
wget --continue https://nodejs.org/dist/latest/${NODE_PACKAGE} --progress=bar:force -O nodejs.tar.xz

unlink latest-nodejs.txt || true

if [ -e "nodejs-install-temp-dir" ]; then
	rm -rf nodejs-install-temp-dir
fi
mkdir nodejs-install-temp-dir

echo "	extracting file: nodejs.tar.xz"
tar xf nodejs.tar.xz -C nodejs-install-temp-dir && unlink nodejs.tar.xz

cd nodejs-install-temp-dir/*

echo "	copy nodejs to /usr/nodejs ..."
rm -f /usr/nodejs/bin/node
cp -r . /usr/nodejs
echo "complete."

cd /tmp

rm -rf nodejs-install-temp-dir

echo ""

if [ -e /usr/nodejs/bin/node ]; then
	echo -n "  node.js: "
	/usr/nodejs/bin/node -v
else
	echo "error... something wrong... no /usr/nodejs/bin/node after extract."
	exit 1
fi

echo 'export PATH="$PATH:/usr/nodejs/bin:/usr/nodejs/yarn/bin:./node_modules/.bin"' > /etc/profile.d/nodejs.sh
source /etc/profile.d/nodejs.sh

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
	
	/usr/nodejs/bin/npm rebuild "${ITEMS[@]}"
}
if [ "${OLD_EXISTS}" ]; then
	echo "rebuild global node_modules folder..."
	PREFIX=$(/usr/nodejs/bin/npm config --global get prefix)
	cd "${PREFIX}/lib/node_modules"
	
	install || die "nodejs install success. But can not rebuild some global packages. This may or may not cause error."
fi

wget https://yarnpkg.com/latest-rc.tar.gz -O /tmp/install-yarn.tar.gz --progress=bar:force --continue
rm -rf /usr/nodejs/yarn
mkdir -p /usr/nodejs/yarn
tar -zvxf /tmp/install-yarn.tar.gz -C /usr/nodejs/yarn --strip-components=1

echo -n "  yarn: "
/usr/nodejs/yarn/bin/yarn -v

mkdir -p /usr/nodejs/etc || true
[[ -e /usr/nodejs/etc/yarnrc ]] || touch /usr/nodejs/etc/yarnrc || true
[[ -e /usr/nodejs/etc/npmrc ]] || touch /usr/nodejs/etc/npmrc || true

if ! grep 'global-folder' /usr/nodejs/etc/yarnrc -q ; then
	echo '' >> /usr/nodejs/etc/yarnrc
	echo 'global-folder "/usr/nodejs/lib"' >> /usr/nodejs/etc/yarnrc
fi

if command -v unpm &>/dev/null ; then
	echo "Installing package manager: unpm"
	yarn global add @idlebox/package-manager || echo "Failed to install @idlebox/package-manager. that is not fatal."
fi
if command -v pnpm &>/dev/null ; then
	echo "Installing package manager: pnpm"
	yarn global add pnpm || echo "Failed to install pnpm. that is not fatal."
fi

echo "nodejs install success."
echo 'You should run "source /etc/profile.d/nodejs.sh" or restart current session to take effect.'
