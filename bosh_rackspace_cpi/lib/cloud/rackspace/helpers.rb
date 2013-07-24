# -*- encoding: utf-8 -*-
# Copyright (c) 2009-2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # BOSH Rackspace CPI Helpers
  #
  module Helpers

    DEFAULT_MAX_RETRIES      =  9 # Default maximum number of retries
    DEFAULT_RETRY_WAIT_TIME  =  5 # Default wait time before retrying a call (in seconds)

    ##
    # Raises a CloudError exception
    #
    # @param [String] message Message about what went wrong
    # @param [optional, Exception] exception Exception to be logged
    # @raise [Bosh::Clouds::CloudError]
    def cloud_error(message, exception = nil)
      @logger.error(message) if @logger
      @logger.error(exception) if @logger && exception
      raise Bosh::Clouds::CloudError, message
    end

    ##
    # Generates an unique name
    #
    # @return [String] Unique name
    def generate_unique_name
      SecureRandom.uuid
    end

    ##
    # Checks if the invoker's task has been cancelled
    #
    # @note This method uses a delegator defined at Bosh::Clouds::Config
    def task_checkpoint
      Bosh::Clouds::Config.task_checkpoint
    end

    ##
    # Wraps and retries on some Rackspace API errors:
    #   - Rate limit threshold exceeded
    #
    # @param [optional, Integer] max_retries Maximum number of retries
    # @raise [Bosh::Clouds::CloudError] When unable to deal with the exception
    # @yields Block
    def wrap_rackspace_errors(max_retries = DEFAULT_MAX_RETRIES)
      retries = 0
      begin
        yield
      rescue Excon::Errors::RequestEntityTooLarge => e
        overlimit = parse_rackspace_response(e.response, 'overLimit', 'overLimitFault')
        unless overlimit.nil? || retries >= max_retries
          wait_for_overlimit(overlimit)
          retries += 1
          retry
        end
        cloud_error('Rackspace API Over Limit. Check task debug log for details.', e)
      end
    end

    private

    ##
    # Waits the amount of seconds returned by the Rackspace API
    #
    # @param [Hash] overlimit Rackspace Overlimit response
    # @return [void]
    def wait_for_overlimit(overlimit)
      task_checkpoint

      wait_time = overlimit['retryAfter'] || overlimit['Retry-After'] || DEFAULT_RETRY_WAIT_TIME
      details = "#{overlimit["message"]} - #{overlimit["details"]}"

      @logger.debug("Rackspace API Rate Limit (#{details}), waiting #{wait_time} seconds before retrying") if @logger
      Kernel.sleep(wait_time.to_i)
    end

    ##
    # Parses and look ups for keys in a Rackspace API response
    #
    # @param [Excon::Response] response Response from Rackspace API
    # @param [Array<String>] keys Keys to look up in the response
    # @return [Hash] Contents at the first key found, or nil if not found
    def parse_rackspace_response(response, *keys)
      return nil if response.body.empty?

      begin
        body = JSON.parse(response.body)
        key = keys.find { |k| body.has_key?(k) }
        return body[key] if key
      rescue JSON::ParserError
        return nil
      end

      nil
    end
  end
end