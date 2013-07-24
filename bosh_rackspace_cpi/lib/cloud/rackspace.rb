# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh
  ##
  # BOSH Rackspace CPI
  #
  module RackspaceCloud
  end
end

require 'fog'
require 'json'
require 'securerandom'
require 'yajl'

require 'common/common'
require 'common/exec'
require 'common/thread_pool'
require 'common/thread_formatter'

require 'bosh_registry/client'

require 'cloud'
require 'cloud/rackspace/version'
require 'cloud/rackspace/helpers'
require 'cloud/rackspace/cloud'

require 'cloud/rackspace/network_manager'
require 'cloud/rackspace/resource_wait_manager'
require 'cloud/rackspace/server_manager'
require 'cloud/rackspace/stemcell_manager'
require 'cloud/rackspace/tag_manager'
require 'cloud/rackspace/volume_manager'
require 'cloud/rackspace/volume_snapshot_manager'

module Bosh
  ##
  # BOSH Cloud CPI
  #
  module Clouds
    Rackspace = Bosh::RackspaceCloud::Cloud
  end
end
