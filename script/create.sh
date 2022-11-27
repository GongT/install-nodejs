#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

DATA="#!/usr/bin/env bash
"

for I in parts/*.sh; do

	DATA+=$(tail -n+2 "$I")
	DATA+=$'\n'

done

DATA+=$(tail -n+2 "script.sh" | grep -vP '^\s*source ')
DATA+=$'\n'

cd ..
if [[ "$(<install.sh)" != "$(echo -n "$DATA")" ]]; then
	echo "file updated."
	echo -n "$DATA" >install.sh
else
	echo "no change."
fi
