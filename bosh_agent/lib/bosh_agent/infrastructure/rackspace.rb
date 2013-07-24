# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::Agent
  ##
  # BOSH Agent Rackspace Infrastructure
  #
  class Infrastructure::Rackspace
    require 'bosh_agent/infrastructure/rackspace/settings'
    require 'bosh_agent/infrastructure/rackspace/registry'

    def load_settings
      Settings.new.load_settings
    end

    def get_network_settings(network_name, properties)
      Settings.new.get_network_settings(network_name, properties)
    end
  end
end