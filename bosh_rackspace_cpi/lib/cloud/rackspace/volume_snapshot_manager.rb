# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # Manages Volume Snapshots
  #
  class VolumeSnapshotManager
    include Helpers

    attr_reader :logger
    attr_reader :blockstorage_api

    ##
    # Creates a new volume snapshot manager
    #
    # @param [Fog::Rackspace::BlockStorage] blockstorage_api Fog Rackspace Block Storage client
    # @return [Bosh::RackspaceCloud::VolumeSnapshotManager] Volume Snapshot Manager
    def initialize(blockstorage_api)
      @logger = Bosh::Clouds::Config.logger
      @blockstorage_api = blockstorage_api
    end

    ##
    # Returns an existing Rackspace volume snapshot
    #
    # @param [String] volume_snapshot_id Rackspace volume snapshot id
    # @return [Fog::Rackspace::BlockStorage::Snapshot] Rackspace volume snapshot
    # @raise [Bosh::Clouds::CloudError] if volume snapshot is not found
    def get(volume_snapshot_id)
      volume_snapshot = wrap_rackspace_errors { blockstorage_api.snapshots.get(volume_snapshot_id) }
      cloud_error("Volume snapshot `#{volume_snapshot_id}' not found") unless volume_snapshot

      volume_snapshot
    end

    ##
    # Creates a snapshot of an existing Rackspace volume and waits until it reports as available
    #
    # @param [String] volume_id Rackspace volume id
    # @param [Hash] metadata Metadata key/value pairs to add to the volume snapshot
    # @return [Fog::Rackspace::BlockStorage::Snapshot] Rackspace volume snapshot
    def create(volume_id, metadata)
      volume = VolumeManager.new(blockstorage_api).get(volume_id)

      volume_snapshot_params = volume_snapshot_params("snapshot-#{generate_unique_name}", metadata, volume)
      logger.debug("Using volume snapshot params: `#{volume_snapshot_params.inspect}'")

      # There's a bug in fog that prevents to call volume.create_snapshot method with 'force' option,
      # so instead, we're creating a 'snapshot' model and then saving it with 'force' option.
      volume_snapshot = blockstorage_api.snapshots.new(volume_snapshot_params)
      wrap_rackspace_errors { volume_snapshot.save(true) }

      logger.info("Creating new volume snapshot `#{volume_snapshot.id}'...")
      ResourceWaitManager.new(volume_snapshot).wait_for(:available)

      wrap_rackspace_errors { volume_snapshot.reload }
    end

    ##
    # Deletes an existing Rackspace volume snapshot and waits until it reports as deleted
    #
    # @param [String] volume_snapshot_id Rackspace volume snapshot id
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if volume snapshot is not in a ready state
    def delete(volume_snapshot_id)
      volume_snapshot = get(volume_snapshot_id)
      unless volume_snapshot.ready?
        cloud_error("Cannot delete volume snapshot `#{volume_snapshot.id}', state is `#{volume_snapshot.state}'")
      end

      wrap_rackspace_errors { volume_snapshot.destroy }
      ResourceWaitManager.new(volume_snapshot).wait_for(:deleted, allow_notfound: true)
    end

    private

    ##
    # Returns the params to be used to create a new Rackspace volume snapshot
    #
    # @param [String] volume_snapshot_name Volume snapshot name
    # @param [Hash] metadata Metadata key/value pairs to add to the volume snapshot
    # @param [[Fog::Rackspace::BlockStorage::Volume] volume Rackspace volume
    # @return [Hash] Volume snapshot creation params
    def volume_snapshot_params(volume_snapshot_name, metadata, volume)
      description = [:deployment, :job, :index].map { |key| metadata[key] }

      devices = []
      wrap_rackspace_errors do
        volume.attachments.each { |attachment| devices << attachment['device'] unless attachment.empty? }
      end
      description << devices.first.split('/').last if devices.any?

      {
        force: true,
        volume_id: volume.id,
        display_name: volume_snapshot_name,
        display_description: description.join('/')
      }
    end
  end
end