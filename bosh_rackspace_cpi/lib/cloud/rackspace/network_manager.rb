# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # Manages the network configuration
  #
  class NetworkManager
    include Helpers

    attr_reader :logger
    attr_reader :compute_api
    attr_reader :network_spec
    attr_reader :cloud_properties

    ##
    # Creates a new network manager
    #
    # @param [[Fog::Compute::RackspaceV2] compute_api Fog RackspaceV2 Compute client
    # @param [Hash] raw_network_spec Raw network spec
    # @return [Bosh::RackspaceCloud::NetworkManager] Network Manager
    def initialize(compute_api, raw_network_spec)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api

      @network_spec = nil
      @cloud_properties = nil

      parse_network_spec(raw_network_spec)
    end

    ##
    # Applies a network configuration to a Rackspace server
    #
    # Right now it's a no-op as networks are completely managed by Rackspace
    #
    # @param [Fog::Compute::RackspaceV2::Server] server Rackspace server to configure
    # @return [void]
    # @raise [Bosh::Clouds:NotSupported] If there's a network change that requires the recreation of the VM
    def configure(server)
      # noop
    end

    ##
    # Returns the Rackspace networks ids to attach to a Rackspace server
    #
    # Rackspace servers can be attached to several networks:
    # * If you do not specify any networks, the Rackspace server will be attached to the `public Internet' and
    #   `private ServiceNet' networks
    # * If you specify one or more networks, the Rackspace server will be attached to only the networks that you
    #   specify, so if you want to attach to the `public Internet' and/or `private ServiceNet' networks,
    #   you must specify them explicitly:
    #   The UUID for the `public Internet' is 00000000-0000-0000-0000-000000000000
    #   The UUID for the`private ServiceNet' is 11111111-1111-1111-1111-111111111111
    #
    # @return [Array<String>] network ids
    # @raise [Bosh::Clouds::CloudError] if network ids set at cloud properties are not valid
    def network_ids
      network_ids = cloud_properties.fetch('network_ids', []) || []
      cloud_error("Invalid network_ids: Array expected, #{network_ids.class} provided") unless network_ids.is_a?(Array)

      unless network_ids.empty?
        rackspace_networks = wrap_rackspace_errors { compute_api.networks }
        network_ids.each do |network_id|
          network = rackspace_networks.find { |n| n.id == network_id }
          cloud_error("Network `#{network_id}' not found") if network.nil?
        end
      end

      network_ids
    end

    ##
    # Returns the DNS server list to use in a Rackspace server
    #
    # @return [Array<String>] DNS server list
    # @raise [Bosh::Clouds::CloudError] if dns set at network spec are not valid
    def dns
      dns = network_spec.fetch('dns', []) || []
      cloud_error("Invalid dns: Array expected, #{dns.class} provided") unless dns.is_a?(Array)

      dns
    end

    private

    ##
    # Parses the network spec
    #
    # @param [Hash] raw_network_spec Raw network spec
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if network spec is invalid
    def parse_network_spec(raw_network_spec)
      unless raw_network_spec.is_a?(Hash)
        cloud_error("Invalid network spec: Hash expected, #{raw_network_spec.class} provided")
      end

      raw_network_spec.each_pair do |name, spec|
        cloud_error('Must have exactly one network per instance') if network_spec

        unless spec['type'] == 'dynamic'
          cloud_error("Invalid network type `#{spec['type']}': Rackspace CPI can only handle `dynamic' network types")
        end

        @network_spec = spec
        @cloud_properties = spec.fetch('cloud_properties', {}) || {}
      end

      cloud_error('At least one dynamic network should be defined') if network_spec.nil?
    end
  end
end