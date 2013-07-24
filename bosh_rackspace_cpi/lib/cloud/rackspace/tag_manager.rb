# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::RackspaceCloud
  ##
  # Manages Resource's Tags
  #
  class TagManager

    MAX_TAG_KEY_LENGTH = 255
    MAX_TAG_VALUE_LENGTH = 255

    ##
    # Tags a Rackspace resource
    #
    # @param [Fog::Model] taggable Rackspace resource to tag
    # @param [String] key Tag key
    # @param [String] value Tag value
    # @return [void]
    def self.tag(taggable, key, value)
      return if key.nil? || value.nil?
      trimmed_key = key[0..(MAX_TAG_KEY_LENGTH - 1)]
      trimmed_value = value[0..(MAX_TAG_VALUE_LENGTH - 1)]
      taggable.metadata[trimmed_key] = trimmed_value
      taggable.metadata.save
    end
  end
end