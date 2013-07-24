# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # Manages Servers
  #
  class ServerManager
    include Helpers

    BOSH_APP_DIR = '/var/vcap/bosh' # BOSH Agent directory to store user data file

    attr_reader :logger
    attr_reader :compute_api

    ##
    # Creates a new server manager
    #
    # @param [Fog::Compute::RackspaceV2] compute_api Fog RackspaceV2 Compute client
    # @return [Bosh::RackspaceCloud::ServerManager] Server Manager
    def initialize(compute_api)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api
    end

    ##
    # Returns an existing Rackspace server
    #
    # @param [String] server_id Rackspace server id
    # @return [Fog::Compute::RackspaceV2::Server] Rackspace server
    # @raise [Bosh::Clouds::CloudError] if server is not found
    def get(server_id)
      server = wrap_rackspace_errors { compute_api.servers.get(server_id) }
      cloud_error("Server `#{server_id}' not found") unless server

      server
    end

    ##
    # Creates a new Rackspace server and waits until it reports as active
    #
    # @param [String] stemcell_id BOSH stemcell id
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this server
    # @param [Bosh::RackspaceCloud::NetworkManager] network_manager Network manager
    # @return [Fog::Compute::RackspaceV2::Server] Rackspace server
    # @param [String] registry_endpoint Registry endpoint URI
    # @raise [Bosh::Clouds::VMCreationFailed] if failed to create the server
    def create(stemcell_id, resource_pool, network_manager, registry_endpoint)
      server_params = server_params("server-#{generate_unique_name}", stemcell_id, resource_pool,
                                    network_manager, registry_endpoint)
      logger.debug("Using boot params: `#{server_params.inspect}'")

      server = wrap_rackspace_errors { compute_api.servers.create(server_params) }
      logger.info("Creating new server `#{server.id}'...")
      begin
        ResourceWaitManager.new(server).wait_for(:active)
      rescue Bosh::Clouds::CloudError
        raise Bosh::Clouds::VMCreationFailed.new(true)
      end

      wrap_rackspace_errors { server.reload }
    end

    ##
    # Terminates an existing Rackspace server and waits until it reports as terminated
    #
    # @param [String] server_id Rackspace server id
    # @return [void]
    def terminate(server_id)
      server = get(server_id)

      wrap_rackspace_errors { server.destroy }
      ResourceWaitManager.new(server).wait_for([:terminated, :deleted], allow_notfound: true)
    end

    ##
    # Reboots an existing Rackspace server and waits until it reports as active
    #
    # @param [String] server_id Rackspace server id
    # @return [void]
    def reboot(server_id)
      server = get(server_id)

      wrap_rackspace_errors { server.reboot }
      ResourceWaitManager.new(server).wait_for(:active)
    end

    ##
    # Checks if a Rackspace server exists
    #
    # @param [String] server_id Rackspace server id
    # @return [Boolean] True if the server exists, false otherwise
    def exists?(server_id)
      server = wrap_rackspace_errors { compute_api.servers.get(server_id) }
      !server.nil? && ![:terminated, :deleted].include?(server.state.downcase.to_sym)
    end

    ##
    # Set metadata for an existing Rackspace server
    #
    # @param [String] server_id Rackspace server id
    # @param [Hash] metadata Metadata key/value pairs to add to the server
    # @return [void]
    def set_metadata(server_id, metadata)
      server = get(server_id)

      wrap_rackspace_errors do
        metadata.each do |name, value|
          TagManager.tag(server, name, value)
        end
      end
    end

    ##
    # Attaches an existing Rackspace volume to an existing Rackspace server
    #
    # @param [Fog::Compute::RackspaceV2::Server] server Rackspace server
    # @param [Fog::Rackspace::BlockStorage::Volume] volume Rackspace volume
    # @return [Fog::Compute::RackspaceV2::Attachment] Rackspace volume attachment
    def attach_volume(server, volume)
      attachment = wrap_rackspace_errors { server.attach_volume(volume) }
      ResourceWaitManager.new(volume).wait_for('in-use'.to_sym)

      attachment
    end

    ##
    # Detaches an existing Rackspace volume from an existing Rackspace server
    #
    # @param [Fog::Compute::RackspaceV2::Server] server Rackspace server
    # @param [Fog::Rackspace::BlockStorage::Volume] volume Rackspace volume
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if volume is not attached to the server
    def detach_volume(server, volume)
      attachment = wrap_rackspace_errors { server.attachments.find { |a| a.volume_id == volume.id } }
      cloud_error("Volume `#{volume.id}' is not attached to server `#{server.id}'") unless attachment

      wrap_rackspace_errors { attachment.detach }
      ResourceWaitManager.new(volume).wait_for(:available)
    end

    ##
    # List the attached Rackspace volumes of an existing Rackspace server
    #
    # @param [String] server_id Rackspace server id
    # @return [Array<String>] List of volume ids attached to the server
    def get_attached_volumes(server_id)
      server = get(server_id)

      wrap_rackspace_errors { server.attachments.map { |a| a.volume_id } }
    end

    private

    ##
    # Returns the params to be used to boot a new Rackspace server
    #
    # @param [String] server_name Server name
    # @param [String] stemcell_id BOSH stemcell id
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this server
    # @param [Bosh::RackspaceCloud::NetworkManager] network_manager Network manager
    # @param [String] registry_endpoint Registry endpoint URI
    # @return [Hash] Server boot params
    def server_params(server_name, stemcell_id, resource_pool, network_manager, registry_endpoint)
      server_params = {
        name: server_name,
        image_id: server_image_id(stemcell_id),
        flavor_id: server_flavor_id(resource_pool['instance_type']),
        personality: server_personality(server_name, resource_pool, network_manager, registry_endpoint)
      }

      network_ids = server_network_ids(network_manager)
      server_params[:networks] = network_ids if network_ids.any?

      server_params
    end

    ##
    # Returns the Rackspace image id to be used to boot a new Rackspace server
    #
    # @param [String] stemcell_id Bosh stemcell id
    # @return [String] Rackspace image id
    def server_image_id(stemcell_id)
      image = StemcellManager.new(compute_api).get(stemcell_id)

      logger.debug("Using image: `#{image.name} (#{image.id})'")
      image.id.to_s
    end

    ##
    # Returns the Rackspace flavor id to be used to boot a new Rackspace server
    #
    # @param [String] flavor_name Rackspace flavor name
    # @return [String] Rackspace flavor id
    # @raise [Bosh::Clouds::CloudError] if flavor is not found
    def server_flavor_id(flavor_name)
      flavor = wrap_rackspace_errors { compute_api.flavors.find { |f| f.name == flavor_name } }
      cloud_error("Flavor `#{flavor_name}' not found") if flavor.nil?

      logger.debug("Using flavor: `#{flavor.name} (#{flavor.id})'")
      flavor.id.to_s
    end

    ##
    # Returns the Array of files to be injected onto the Rackspace server
    #
    # @param [String] server_name Server name
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this server
    # @param [Bosh::RackspaceCloud::NetworkManager] network_manager Network manager
    # @param [String] registry_endpoint Registry endpoint URI
    # @return [Array<Hash>] Server personality files
    def server_personality(server_name, resource_pool, network_manager, registry_endpoint)
      user_data = server_user_data(server_name, resource_pool, network_manager, registry_endpoint)
      logger.debug("Setting user data: `#{user_data}'")

      [{
        path: "#{BOSH_APP_DIR}/user_data.json",
        contents: Base64.encode64(Yajl::Encoder.encode(user_data))
      }]
    end

    ##
    # Returns the user data to be injected onto the Rackspace server
    #
    # @param [String] server_name Server name
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this server
    # @param [Bosh::RackspaceCloud::NetworkManager] network_manager Network manager
    # @param [String] registry_endpoint Registry endpoint URI
    # @return [Hash] Server user data
    def server_user_data(server_name, resource_pool, network_manager, registry_endpoint)
      user_data = {
        'registry' => { 'endpoint' => registry_endpoint },
        'server' => { 'name' => server_name }
      }

      dns_list = network_manager.dns
      user_data['dns'] = { 'nameserver' => dns_list } if dns_list.any?

      public_key = server_public_key(resource_pool)
      user_data['openssh'] = { 'public_key' => public_key } if public_key

      user_data
    end

    ##
    # Returns the OpenSSH public key to use in a Rackspace server
    #
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this server
    # @return [String] OpenSSH public key
    # @raise [Bosh::Clouds::CloudError] if public key set at resource pool is not valid
    def server_public_key(resource_pool)
      public_key = resource_pool.fetch('public_key', nil)
      if public_key && !public_key.is_a?(String)
        cloud_error("Invalid public key: String expected, #{public_key.class} provided")
      end

      public_key
    end

    ##
    # Returns the Rackspace network ids to be used to boot a new Rackspace server
    #
    # @param [Bosh::RackspaceCloud::NetworkManager] network_manager Network manager
    # @return [Array<Hash>] Rackspace network ids
    def server_network_ids(network_manager)
      network_ids = network_manager.network_ids

      logger.debug("Using networks: `#{network_ids.join(', ')}'") unless network_ids.empty?
      network_ids.map { |network_id| { id: network_id.to_s } }
    end
  end
end