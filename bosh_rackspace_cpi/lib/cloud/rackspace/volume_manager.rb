# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # Manages Volumes
  #
  class VolumeManager
    include Helpers

    attr_reader :logger
    attr_reader :blockstorage_api

    ##
    # Creates a new volume manager
    #
    # @param [Fog::Rackspace::BlockStorage] blockstorage_api Fog Rackspace Block Storage client
    # @return [Bosh::RackspaceCloud::VolumeManager] Volume Manager
    def initialize(blockstorage_api)
      @logger = Bosh::Clouds::Config.logger
      @blockstorage_api = blockstorage_api
    end

    ##
    # Returns an existing Rackspace volume
    #
    # @param [String] volume_id Rackspace volume id
    # @return [Fog::Rackspace::BlockStorage::Volume] Rackspace volume
    # @raise [Bosh::Clouds::CloudError] if volume is not found
    def get(volume_id)
      volume = wrap_rackspace_errors { blockstorage_api.volumes.get(volume_id) }
      cloud_error("Volume `#{volume_id}' not found") unless volume

      volume
    end

    ##
    # Creates a new Rackspace volume and waits until it reports as available
    #
    # @param [Integer] volume_size Volume size in MiB
    # @return [Fog::Rackspace::BlockStorage::Volume] Rackspace volume
    # @raise [Bosh::Clouds::CloudError] if volume size is not valid
    def create(volume_size)
      cloud_error('Volume size needs to be an Integer') unless volume_size.kind_of?(Integer)
      if volume_size < 1024 * 100
        cloud_error("Minimum volume size is 100 GiB, set only #{convert_to_gib(volume_size)} GiB")
      end

      volume_params = volume_params("volume-#{generate_unique_name}", volume_size)
      logger.debug("Using volume params: `#{volume_params.inspect}'")

      volume = wrap_rackspace_errors { blockstorage_api.volumes.create(volume_params) }
      logger.info("Creating new volume `#{volume.id}'...")
      ResourceWaitManager.new(volume).wait_for(:available)

      wrap_rackspace_errors { volume.reload }
    end

    ##
    # Deletes an existing Rackspace volume and waits until it reports as deleted
    #
    # @param [String] volume_id Rackspace volume id
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if volume is not in a ready state
    def delete(volume_id)
      volume = get(volume_id)
      unless volume.ready?
        cloud_error("Cannot delete volume `#{volume.id}', state is `#{volume.state}'")
      end

      wrap_rackspace_errors { volume.destroy }
      ResourceWaitManager.new(volume).wait_for(:deleted, allow_notfound: true)
    end

    private

    ##
    # Returns the params to be used to create a new Rackspace volume
    #
    # @param [String] volume_name Volume name
    # @param [Integer] volume_size Volume size in MiB
    # @return [Hash] Volume creation params
    def volume_params(volume_name, volume_size)
      {
        display_name: volume_name,
        size: convert_to_gib(volume_size)
      }
    end

    ##
    # Converts volume size from MiB to GiB
    #
    # @param [Integer] volume_size Volume size in MiB
    # @return [Integer] Volume size in GiB
    def convert_to_gib(volume_size)
      (volume_size / 1024.0).ceil
    end
  end
end