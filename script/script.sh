#!/usr/bin/env bash

do_system_check
install_nodejs
create_nodejs_profile
update_config

install_pnpm
install_other_packages
