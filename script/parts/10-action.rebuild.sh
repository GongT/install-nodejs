#!/bin/bash

function rebuild_global_packages() {
	local ITEMS=()
	local i
	local j
	cd "$1"
	for i in */; do
		i=${i%/}
		if echo "$i" | grep -qE '^@' &>/dev/null; then
			for j in "$i"/*/; do
				j=${j%/}
				if [ ! -L "$j" ]; then
					ITEMS+=("$j")
				fi
			done
		elif [ ! -L "$i" ]; then
			ITEMS+=("$i")
		fi
	done

	$NPM rebuild "${ITEMS[@]}" || {
		msg -e "\e[38;5;11mGlobal packages not rebuilt. This may or may not cause error.\e[0m"
		msg "    the command is: $NPM rebuild ${ITEMS[*]}"
	}
}
