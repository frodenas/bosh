# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::Registry
  ##
  # BOSH Registry Instance Manager
  #
  class InstanceManager
    ##
    # BOSH Rackspace Instance Manager
    #
    class Rackspace < InstanceManager

      attr_reader   :options
      attr_accessor :logger

      ##
      # Creates a new BOSH Registry Instance Manager
      #
      # @param [Hash] options Rackspace options (options are defined in the {file:README.md})
      # @return [Bosh::Registry::InstanceManager::Rackspace] Rackspace Instance Manager
      def initialize(options)
        @options = options.dup
        validate_options

        @logger = Bosh::Registry.logger
      end

      ##
      # Get the list of IPs belonging to a Rackspace server
      #
      # @param [String] server_name Rackspace server name
      # @return [Array<String>] List of server IPs
      # @raise [Bosh::Registry::InstanceNotFound] if server is not found
      def instance_ips(server_name)
        server = rackspace_compute_api.servers.find { |s| s.name == server_name }
        raise InstanceNotFound, "Server `#{server_name}' not found" unless server

        addresses = server.addresses
        return [] if addresses.nil? || addresses.empty?
        addresses.values.flatten.map { |a| a['addr'] }
      end

      private

      ##
      # Checks if options passed to BOSH Rackspace Instance Manager are valid and can actually be used to create all
      # required data structures
      #
      # @return [void]
      # @raise [Bosh::Registry::ConfigError] if options are not valid
      def validate_options
        required_keys = { 'rackspace' => %w(username api_key) }

        missing_keys = []

        required_keys.each_pair do |key, values|
          values.each do |value|
            missing_keys << "#{key}:#{value}" unless options.has_key?(key) && options[key].has_key?(value)
          end
        end

        raise ConfigError, "Missing configuration parameters: #{missing_keys.join(', ')}" unless missing_keys.empty?
      end

      ##
      # Returns the Rackspace API connection params
      #
      # @return [Hash] Rackspace API connection params
      def rackspace_api_params
        rackspace_properties = options.fetch('rackspace')
        {
          provider:           'Rackspace',
          version:            :v2,
          rackspace_username: rackspace_properties['username'],
          rackspace_api_key:  rackspace_properties['api_key'],
          rackspace_region:   rackspace_properties['region'],
          rackspace_auth_url: rackspace_properties['auth_url'],
          connection_options: rackspace_properties['connection_options'],
        }
      end

      ##
      # Returns the Fog RackspaceV2 Compute client
      #
      # @return [Fog::Compute::RackspaceV2] Fog RackspaceV2 Compute client
      # @raise [Bosh::Registry::ConnectionError] if unable to connect to the Rackspace compute API
      def rackspace_compute_api
        begin
          @compute_api ||= Fog::Compute.new(rackspace_api_params)
        rescue Fog::Errors::Error => e
          logger.error(e)
          raise ConnectionError, 'Unable to connect to the Rackspace Compute API'
        end
      end
    end
  end
end