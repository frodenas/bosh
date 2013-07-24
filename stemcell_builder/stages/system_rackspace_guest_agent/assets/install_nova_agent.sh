#!/usr/bin/env bash

set -e
set -x

cd /tmp/openstack-guest-agents-unix
pip install pyxenstore
sh autogen.sh
./configure
make
make install