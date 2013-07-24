#!/usr/bin/env bash
#
# Copyright (c) 2013 GoPivotal, Inc.

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

# Copy assets
mkdir -p $chroot/tmp
cp $assets_dir/xe-guest-utilities_6.2.0-1120_amd64.deb $chroot/tmp

# Install Xen guest utilities
run_in_chroot $chroot "
dpkg -i /tmp/xe-guest-utilities_6.2.0-1120_amd64.deb
rm -f /tmp/xe-guest-utilities_6.2.0-1120_amd64.deb
"