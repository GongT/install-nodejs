#!/usr/bin/env bash

function create_nodejs_profile() {
	msg "Creating profile..."
	{
		echo "### Generated file, DO NOT MODIFY"
		echo "_NODE_JS_INSTALL_PREFIX='$PREFIX'"
		cat <<-'DATA'
			if ! echo ":$PATH:" | grep -q "$_NODE_JS_INSTALL_PREFIX/bin" ; then
				export PATH="$PATH:./node_modules/.bin:$_NODE_JS_INSTALL_PREFIX/bin"
			fi
			unset _NODE_JS_INSTALL_PREFIX
		DATA
		echo
	} >/etc/profile.d/nodejs.sh
	msg "Loading profile..."
	source /etc/profile.d/nodejs.sh
}
