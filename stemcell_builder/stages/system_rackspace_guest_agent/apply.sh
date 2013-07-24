#!/usr/bin/env bash
#
# Copyright (c) 2013 GoPivotal, Inc.

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

# Install dependencies
debs="autoconf automake build-essential python-cjson libxen3-dev \
python-anyjson python-pip python-crypto libtool python-dev"
apt_get install $debs

# Copy assets
mkdir -p $chroot/tmp $chroot/tmp
cp $assets_dir/install_nova_agent.sh $chroot/tmp
cp $assets_dir/patchelf_0.7pre169-eea5b99-1_amd64.deb $chroot/tmp
cp $assets_dir/openstack-guest-agents-unix-0.0.1.37.tar.gz $chroot/tmp

# Install Patchelf
run_in_chroot $chroot "
dpkg -i /tmp/patchelf_0.7pre169-eea5b99-1_amd64.deb
rm -f /tmp/patchelf_0.7pre169-eea5b99-1_amd64.deb
"

# Install Rackspace Guest Agent
run_in_chroot $chroot "
tar xvzf /tmp/openstack-guest-agents-unix-0.0.1.37.tar.gz -C /tmp
/tmp/install_nova_agent.sh
rm -fr /tmp/openstack-guest-agents-unix
rm -f /tmp/openstack-guest-agents-unix-0.0.1.37.tar.gz
rm -f /tmp/install_nova_agent.sh
"