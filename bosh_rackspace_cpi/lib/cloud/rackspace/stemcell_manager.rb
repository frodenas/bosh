# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # Manages Stemcells
  #
  class StemcellManager
    include Helpers

    attr_reader :logger
    attr_reader :compute_api

    ##
    # Creates a new volume manager
    #
    # @param [[Fog::Compute::RackspaceV2] compute_api Fog RackspaceV2 Compute client
    # @return [Bosh::RackspaceCloud::StemcellManager] Stemcell Manager
    def initialize(compute_api)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api
    end

    ##
    # Returns an existing stemcell
    #
    # @param [String] stemcell_id BOSH stemcell id
    # @return [Fog::Compute::RackspaceV2::Image] Rackspace image
    # @raise [Bosh::Clouds::CloudError] if stemcell is not found
    def get(stemcell_id)
      stemcell = wrap_rackspace_errors { compute_api.images.get(stemcell_id) }
      cloud_error("Stemcell `#{stemcell_id}' not found in Rackspace") if stemcell.nil?

      stemcell
    end

    ##
    # Creates a new Rackspace image
    #
    # Right now BOSH stemcells are completely managed by Rackspace, so this method will only look up at the
    # the stemcell properties for the Rackspace image id
    #
    # @param [Hash] stemcell_properties Stemcell properties
    # @option stemcell_properties [String] infrastructure Stemcell target infrastructure
    # @option stemcell_properties [String] image_id Rackspace image id
    # @return [Fog::Compute::RackspaceV2::Image] Rackspace image
    # @raise [Bosh::Clouds::CloudError] if stemcell properties are not valid
    def create(stemcell_properties)
      infrastructure = stemcell_properties['infrastructure']
      unless infrastructure && infrastructure == 'rackspace'
        cloud_error("This is not a Rackspace stemcell, infrastructure is `#{infrastructure}'")
      end

      image_id = stemcell_properties['image_id']
      cloud_error('Stemcell properties does not contain image id') unless image_id

      stemcell = get(image_id)
      logger.debug("Using existing Rackspace image `#{stemcell.name} (#{stemcell.id})'")

      stemcell
    end

    ##
    # Deletes an existing stemcell
    #
    # Right now it's a no-op as BOSH stemcells are completely managed by Rackspace
    #
    # @param [String] stemcell_id Bosh stemcell id to delete
    # @return [void]
    def delete(stemcell_id)
      # noop
      logger.debug('BOSH stemcells are managed by Rackspace, skipping')
    end
  end
end