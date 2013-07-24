# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # BOSH Rackspace CPI
  #
  class Cloud < Bosh::Cloud
    include Helpers

    attr_reader   :compute_api
    attr_reader   :blockstorage_api
    attr_reader   :registry
    attr_reader   :options
    attr_accessor :logger

    ##
    # Creates a new BOSH Rackspace CPI
    #
    # @param [Hash] options CPI options (the contents of sub-hashes are defined in the {file:README.md})
    # @option options [Hash] rackspace Rackspace options
    # @option options [Hash] agent BOSH Agent options
    # @option options [Hash] registry BOSH Registry options
    # @return [Bosh::RackspaceCloud::Cloud] Rackspace CPI
    def initialize(options)
      @options = options.dup
      validate_options

      @logger = Bosh::Clouds::Config.logger

      initialize_compute_api
      initialize_blockstorage_api
      initialize_registry
    end

    ##
    # Creates a new stemcell
    #
    # @param [String] image_path Local filesystem path to a stemcell image
    # @param [Hash] stemcell_properties Stemcell properties
    # @return [String] Rackspace image id
    def create_stemcell(image_path, stemcell_properties)
      with_thread_name("create_stemcell(#{image_path}, ...)") do
        logger.info('Creating new stemcell...')
        image = StemcellManager.new(compute_api).create(stemcell_properties)

        image.id.to_s
      end
    end

    ##
    # Deletes an existing stemcell
    #
    # @param [String] stemcell_id BOSH stemcell id to delete
    # @return [void]
    def delete_stemcell(stemcell_id)
      with_thread_name("delete_stemcell(#{stemcell_id})") do
        logger.info("Deleting stemcell `#{stemcell_id}'...")
        StemcellManager.new(compute_api).delete(stemcell_id)
      end
    end

    ##
    # Creates a new vm
    #
    # @param [String] agent_id BOSH agent id (will be picked up by agent to assume its identity)
    # @param [String] stemcell_id BOSH stemcell id
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this vm
    # @param [Hash] networks List of networks and their settings needed for this vm
    # @param [optional, Array] disk_locality Not used in this CPI
    # @param [optional, Hash] environment Data to be merged into agent settings
    # @return [String] Rackspace server id
    def create_vm(agent_id, stemcell_id, resource_pool, network_spec, disk_locality = nil, environment = nil)
      with_thread_name("create_vm(#{agent_id}, ...)") do
        network_manager = NetworkManager.new(compute_api, network_spec)

        logger.info('Creating new server...')
        server = ServerManager.new(compute_api).create(stemcell_id, resource_pool, network_manager, registry.endpoint)

        logger.info("Configuring network for server `#{server.id}'...")
        network_manager.configure(server)

        logger.info("Updating agent settings for server `#{server.id}'...")
        registry.update_settings(server.name, initial_agent_settings(server.name, agent_id, network_spec, environment))

        server.id.to_s
      end
    end

    ##
    # Deletes an existing vm
    #
    # @param [String] server_id Rackspace server id
    # @return [void]
    def delete_vm(server_id)
      with_thread_name("delete_vm(#{server_id})") do
        server = ServerManager.new(compute_api).get(server_id)

        logger.info("Deleting server `#{server_id}'...")
        ServerManager.new(compute_api).terminate(server_id)

        logger.info("Deleting agent settings for server `#{server.id}'...")
        registry.delete_settings(server.name)
      end
    end

    ##
    # Reboots an existing vm
    #
    # @param [String] server_id Rackspace server id
    # @return [void]
    def reboot_vm(server_id)
      with_thread_name("reboot_vm(#{server_id})") do
        logger.info("Rebooting server `#{server_id}'...")
        ServerManager.new(compute_api).reboot(server_id)
      end
    end

    ##
    # Checks if a vm exists
    #
    # @param [String] server_id Rackspace server id
    # @return [Boolean] True if the vm exists, false otherwise
    def has_vm?(server_id)
      with_thread_name("has_vm?(#{server_id})") do
        logger.info("Checking if server `#{server_id}' exists")
        ServerManager.new(compute_api).exists?(server_id)
      end
    end

    ##
    # Set metadata for an existing vm
    #
    # @param [String] server_id Rackspace server id
    # @param [Hash] metadata Metadata key/value pairs to add to the server
    # @return [void]
    def set_vm_metadata(server_id, metadata)
      with_thread_name("set_vm_metadata(#{server_id}, ...)") do
        logger.info("Setting metadata for server `#{server_id}'")
        ServerManager.new(compute_api).set_metadata(server_id, metadata)
      end
    end

    ##
    # Configures networking on existing vm
    #
    # @param [String] server_id Rackspace server id
    # @param [Hash] network_spec Raw network spec
    # @return [void]
    def configure_networks(server_id, network_spec)
      with_thread_name("configure_networks(#{server_id}, ...)") do
        server = ServerManager.new(compute_api).get(server_id)

        logger.info("Configuring network for server `#{server.id}'...")
        network_manager = NetworkManager.new(compute_api, network_spec)
        network_manager.configure(server)

        logger.info("Updating agent settings for server `#{server.id}'...")
        update_network_settings(server.name, network_spec)
      end
    end

    ##
    # Creates a new volume
    #
    # @param [Integer] volume_size Disk size in MiB
    # @param [optional, String] server_id Not used in this CPI
    # @return [String] Rackspace volume id
    def create_disk(volume_size, server_id = nil)
      with_thread_name("create_disk(#{volume_size}, #{server_id})") do
        logger.info('Creating new volume...')
        volume = VolumeManager.new(blockstorage_api).create(volume_size)

        volume.id.to_s
      end
    end

    ##
    # Deletes an existing volume
    #
    # @param [String] volume_id Rackspace volume id
    # @return [void]
    def delete_disk(volume_id)
      with_thread_name("delete_disk(#{volume_id})") do
        logger.info("Deleting volume `#{volume_id}'...")
        VolumeManager.new(blockstorage_api).delete(volume_id)
      end
    end

    ##
    # Attaches an existing volume to an existing server
    #
    # @param [String] server_id Rackspace server id
    # @param [String] volume_id Rackspace volume id
    # @return [void]
    def attach_disk(server_id, volume_id)
      with_thread_name("attach_disk(#{server_id}, #{volume_id})") do
        server = ServerManager.new(compute_api).get(server_id)
        volume = VolumeManager.new(blockstorage_api).get(volume_id)

        logger.info("Attaching volume `#{volume.id}' to server `#{server.id}'...")
        attachment = ServerManager.new(compute_api).attach_volume(server, volume)

        logger.info("Updating agent settings for server `#{server.id}'...")
        update_disk_settings(server.name, volume_id, attachment.device.to_s)
      end
    end

    ##
    # Detaches an existing volume from an existing server
    #
    # @param [String] server_id Rackspace server id
    # @param [String] volume_id Rackspace volume id
    # @return [void]
    def detach_disk(server_id, volume_id)
      with_thread_name("detach_disk(#{server_id}, #{volume_id})") do
        server = ServerManager.new(compute_api).get(server_id)
        volume = VolumeManager.new(blockstorage_api).get(volume_id)

        logger.info("Detaching volume `#{volume.id}' from `#{server.id}'...")
        ServerManager.new(compute_api).detach_volume(server, volume)

        logger.info("Updating agent settings for server `#{server.id}'...")
        update_disk_settings(server.name, volume_id)
      end
    end

    ##
    # List the attached disks of an existing server
    #
    # @param [String] server_id Rackspace server id
    # @return [Array<String>] List of disk ids attached to an existing server
    def get_disks(server_id)
      with_thread_name("get_disks(#{server_id})") do
        ServerManager.new(compute_api).get_attached_volumes(server_id)
      end
    end

    ##
    # Takes a snapshot of an existing volume
    #
    # @param [String] volume_id Rackspace volume id
    # @param [Hash] metadata Metadata key/value pairs to add to the volume snapshot
    # @return [String] Rackspace volume snapshot id
    def snapshot_disk(volume_id, metadata)
      with_thread_name("snapshot_disk(#{volume_id}, ...)") do
        logger.info("Creating new snapshot for volume `#{volume_id}'...")
        volume_snapshot = VolumeSnapshotManager.new(blockstorage_api).create(volume_id, metadata)

        volume_snapshot.id.to_s
      end
    end

    ##
    # Deletes an existing volume snapshot
    #
    # @param [String] volume_snapshot_id Rackspace volume snapshot id
    # @return [void]
    def delete_snapshot(volume_snapshot_id)
      with_thread_name("delete_snapshot(#{volume_snapshot_id})") do
        logger.info("Deleting volume snapshot `#{volume_snapshot_id}'...")
        VolumeSnapshotManager.new(blockstorage_api).delete(volume_snapshot_id)
      end
    end

    ##
    # Validates the deployment
    #
    # @note Not implemented in this CPI
    def validate_deployment(old_manifest, new_manifest)
      not_implemented(:validate_deployment)
    end

    private

    ##
    # Checks if options passed to CPI are valid and can actually be used to create all required data structures
    #
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if options are not valid
    def validate_options
      required_keys = {
        'rackspace' => %w(username api_key),
        'registry' => %w(endpoint user password),
      }

      missing_keys = []

      required_keys.each_pair do |key, values|
        values.each do |value|
          missing_keys << "#{key}:#{value}" unless options.has_key?(key) && options[key].has_key?(value)
        end
      end

      cloud_error("Missing configuration parameters: #{missing_keys.join(', ')}") unless missing_keys.empty?
    end

    ##
    # Returns the Rackspace connection params
    #
    # @return [Hash] Rackspace connection params
    def rackspace_params
      rackspace_properties = options.fetch('rackspace')
      {
        rackspace_username: rackspace_properties['username'],
        rackspace_api_key:  rackspace_properties['api_key'],
        rackspace_region:   rackspace_properties['region'],
        rackspace_auth_url: rackspace_properties['auth_url'],
        connection_options: rackspace_properties['connection_options'],
      }
    end

    ##
    # Initialize the Fog RackspaceV2 Compute client
    #
    # @return [Fog::Compute::RackspaceV2] Fog RackspaceV2 Compute client
    # @raise [Bosh::Clouds::CloudError] if unable to connect to the Rackspace compute API
    def initialize_compute_api
      extra_params = { provider: 'Rackspace', version: :v2 }
      @compute_api = Fog::Compute.new(rackspace_params.merge(extra_params))
    rescue Fog::Errors::Error => e
      logger.error(e)
      cloud_error('Unable to connect to the Rackspace Compute API. Check task debug log for details.')
    end

    ##
    # Initialize the Fog Rackspace Block Storage client
    #
    # @return [Fog::Rackspace::BlockStorage] Fog Rackspace Block Storage client
    # @raise [Bosh::Clouds::CloudError] if unable to connect to the Rackspace block storage API
    def initialize_blockstorage_api
      @blockstorage_api ||= Fog::Rackspace::BlockStorage.new(rackspace_params)
    rescue Fog::Errors::Error => e
      logger.error(e)
      cloud_error('Unable to connect to the Rackspace Block Storage API. Check task debug log for details.')
    end

    ##
    # Initialize the Bosh Registry client
    #
    # @return [Bosh::Registry::Client] Bosh Registry client
    def initialize_registry
      registry_properties = options.fetch('registry', {})
      registry_endpoint   = registry_properties.fetch('endpoint')
      registry_user       = registry_properties.fetch('user')
      registry_password   = registry_properties.fetch('password')

      @registry = Bosh::Registry::Client.new(registry_endpoint,
                                             registry_user,
                                             registry_password)
    end

    ##
    # Generates initial agent settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] server_name Name of the Rackspace server (will be picked up by agent to fetch registry settings)
    # @param [String] agent_id BOSH Agent ID (will be picked up by agent to assume its identity)
    # @param [Hash] network_spec Raw network spec
    # @param [Hash] environment Environment settings
    # @return [Hash] Agent settings
    def initial_agent_settings(server_name, agent_id, network_spec, environment)
      settings = {
        'vm' => { 'name' => server_name },
        'agent_id' => agent_id,
        'networks' => network_spec,
        'disks' => { 'system' => '/dev/xvda', 'persistent' => {} }
      }

      settings['env'] = environment if environment

      settings.merge(options.fetch('agent', {}))
    end

    ##
    # Updates the agent settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] server_name Name of the Rackspace server (will be picked up by agent to fetch registry settings)
    # @raise [ArgumentError] if bloc is not provided
    def update_agent_settings(server_name)
      raise ArgumentError, 'Block is not provided' unless block_given?

      settings = registry.read_settings(server_name)
      yield settings
      registry.update_settings(server_name, settings)
    end

    ##
    # Update the agent disk settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] server_name Name of the Rackspace server (will be picked up by agent to fetch registry settings)
    # @param [String] volume_id Rackspace volume id
    # @param [String] device_name Device name
    # @return [void]
    def update_disk_settings(server_name, volume_id, device_name = nil)
      update_agent_settings(server_name) do |settings|
        settings['disks'] ||= {}
        settings['disks']['persistent'] ||= {}
        if device_name
          settings['disks']['persistent'][volume_id] = device_name
        else
          settings['disks']['persistent'].delete(volume_id)
        end
      end
    end

    ##
    # Update the agent network settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] server_name Name of the Rackspace server (will be picked up by agent to fetch registry settings)
    # @param [Hash] network_spec Raw network spec
    # @return [void]
    def update_network_settings(server_name, network_spec)
      update_agent_settings(server_name) do |settings|
        settings['networks'] = network_spec
      end
    end
  end
end