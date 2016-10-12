#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
	exec sudo bash
fi

set -e
cd /tmp

if [ ! -f latest-nodejs.txt ]; then
	curl https://nodejs.org/dist/latest/ > latest-nodejs.txt
fi


NODE_PACKAGE=$(grep -Eo 'href="node-v[0-9.]+-linux-x64.tar.xz"' latest-nodejs.txt | sed 's/^href="//; s/"$//')

echo "nodejs file: ${NODE_PACKAGE}"

if [ ! -f nodejs.tar.xz ]; then
	wget --continue -O nodejs.tar.xz https://nodejs.org/dist/latest/${NODE_PACKAGE}
fi

if [ -e "nodejs-install-temp-dir" ]; then
	rm -rf nodejs-install-temp-dir
fi
mkdir nodejs-install-temp-dir

tar xvf nodejs.tar.xz -C nodejs-install-temp-dir

cd nodejs-install-temp-dir/*

cp -vr */ /usr/local

cd /tmp

rm -rf nodejs-install-temp-dir

echo ""

if [ -e /usr/local/bin/node ]; then
	echo "install complete !"
	echo -n "Node.js: version "
	/usr/local/bin/node -v
else
	echo "error... something wrong..."
	exit 1
fi


if [ -e /usr/bin/which ]; then
	NODE=$(which node)
	if [ -z "${NODE}" ]; then
		echo "you must add /usr/local/bin to your \$PATH"
	fi
else
	echo "you may need add /usr/local/bin to your \$PATH."
fi
