# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # Manages Resources Waits
  #
  class ResourceWaitManager
    include Helpers

    DEFAULT_MAX_TRIES  = 50 # Default maximum number of retries
    MAX_SLEEP_EXPONENT =  5 # Maxim sleep exponent before retrying a call

    attr_reader :logger
    attr_reader :resource
    attr_reader :description

    attr_reader :max_tries
    attr_reader :state_method
    attr_reader :allow_notfound
    attr_reader :target_states
    attr_reader :started_at

    ##
    # Creates a new resource wait manager
    #
    # @param [Fog::Model] resource Fog Model resource
    # @param [Hash] options Resource wait options
    # @option options [String] description Resource description
    # @return [Bosh::RackspaceCloud::ResourceWaitManager] Resource Wait Manager
    def initialize(resource, options = {})
      @logger = Bosh::Clouds::Config.logger
      @resource = resource
      @description = options.fetch(:description, "#{resource_name} `#{resource_identity}'")
    end

    ##
    # Waits for a resource
    #
    # @param [Array<Symbol>] target_state Resource's state desired
    # @param [Hash] options Wait options
    # @raise [Bosh::Clouds::CloudError] When resource not found if not founds are not allowed
    # @raise [Bosh::Clouds::CloudError] When resource state is error
    def wait_for(target_state, options = {})
      @target_states = Array(target_state)
      initialize_retry_options(options)

      Bosh::Common.retryable(tries: max_tries, sleep: sleep_callback, ensure: ensure_callback) do
        task_checkpoint

        if wrap_rackspace_errors { resource.reload.nil? }
          return true if allow_notfound
          cloud_error("#{description} not found")
        end

        state = wrap_rackspace_errors { resource.send(state_method).downcase.to_sym }

        if [:error, :error_deleting].include?(state)
          cloud_error("#{description} state is #{state}, expected #{target_states.join(', ')}, took #{time_passed}s")
        end

        target_states.include?(state)
      end
    end

    private

    ##
    # Initializes the wait_for options
    #
    # @param [Hash] options wait_for options
    # @option options [Integer] max_tries Maximun number of tries to reach the target states
    # @option options [Symbol] state_method Resource's method to fetch state
    # @option options [Boolean] allow_notfound Assume we reached the target state if resource is not found
    # @return [void]
    def initialize_retry_options(options = {})
      @max_tries = options.fetch(:max_tries, DEFAULT_MAX_TRIES).to_i
      @state_method = options[:state_method] || :state
      @allow_notfound = options[:allow_notfound] || false
      @started_at = Time.now
    end

    ##
    # Callback method called when we must wait before retrying again
    #
    # @return [void]
    def sleep_callback
      lambda do |num_tries, error|
        sleep_time = 2**[num_tries, MAX_SLEEP_EXPONENT].min # Exp backoff: 2, 4, 8, 16, 32 ...
        logger.debug("#{error.class}: `#{error.message}'") if error
        logger.debug("Waiting for #{description} to be #{target_states.join(', ')}, " +
                     "retrying in #{sleep_time} seconds (#{num_tries}/#{max_tries})")
        sleep_time
      end
    end

    ##
    # Callback method called when the retryable block finishes
    #
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] When resource wait timeouts
    def ensure_callback
      lambda do |retries|
        if retries == max_tries
          cloud_error("Timed out waiting for #{description} to be #{target_states.join(', ')}, took #{time_passed}s")
        end

        logger.info("#{description} is now #{target_states.join(', ')}, took #{time_passed}s")
      end
    end

    ##
    # Returns the Resource name
    #
    # @return [String] Resource name
    def resource_name
      resource.class.name.split('::').last.to_s.downcase
    end

    ##
    # Returns the Resource identity
    #
    # @return [String] Resource identity
    def resource_identity
      resource.identity.to_s
    end

    ##
    # Returns the time passed between a start time and now
    #
    # @return [Integer] Time passed in seconds
    def time_passed
      Time.now - started_at
    end
  end
end