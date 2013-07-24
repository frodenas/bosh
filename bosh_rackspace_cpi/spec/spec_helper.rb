# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'cloud/rackspace'

Dir[File.expand_path('./support/*', File.dirname(__FILE__))].each do |support_file|
  require support_file
end

def asset(filename)
  File.join(File.dirname(__FILE__), 'assets', filename)
end

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.order = 'random'

  config.before(:each) do
    Bosh::Clouds::Config.stub(:logger).and_return(double.as_null_object)
  end
end