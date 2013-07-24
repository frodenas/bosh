# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'
require 'fog'

describe Bosh::Deployer::Config do
  let(:config_dir) { Dir.mktmpdir('bdc_spec') }
  let(:config_rackspace) { spec_asset('test-bootstrap-config-rackspace.yml') }
  let(:config) { Psych.load_file(config_rackspace) }
  let(:compute_api) { double('compute_api') }
  let(:blockstorage_api) { double('blockstorage_api') }

  before do
    config['dir'] = config_dir
    Fog::Compute.stub(:new).and_return(compute_api)
    Fog::Rackspace::BlockStorage.stub(:new).and_return(blockstorage_api)
  end

  after do
    FileUtils.remove_entry_secure config_dir
  end

  it 'configure should fail without cloud properties' do
    expect do
      Bosh::Deployer::Config.configure({ 'dir' => config_dir })
    end.to raise_error(Bosh::Cli::CliError, 'No cloud properties defined')
  end

  it 'should default agent properties' do
    Bosh::Deployer::Config.configure(config)

    properties = Bosh::Deployer::Config.cloud_options['properties']
    expect(properties['agent']).to be_kind_of(Hash)
    expect(properties['agent']['mbus'].start_with?('https://')).to be_true
    expect(properties['agent']['blobstore']).to be_kind_of(Hash)
  end

  it 'should map network properties' do
    Bosh::Deployer::Config.configure(config)

    networks = Bosh::Deployer::Config.networks
    expect(networks).to be_kind_of(Hash)

    net = networks['bosh']
    expect(net).to be_kind_of(Hash)
    %w(cloud_properties type).each do |key|
      expect(net[key]).to_not be_nil
    end
  end

  it 'should default vm env properties' do
    env = Bosh::Deployer::Config.env

    expect(env).to be_kind_of(Hash)
    expect(env).to have_key('bosh')
    expect(env['bosh']).to be_kind_of(Hash)
    expect(env['bosh']['password']).to_not be_nil
    expect(env['bosh']['password']).to be_kind_of(String)
    expect(env['bosh']['password']).to eql('$6$salt$password')
  end

  it 'should contain default vm resource properties' do
    Bosh::Deployer::Config.configure({ 'dir' => config_dir, 'cloud' => { 'plugin' => 'rackspace' } })
    resources = Bosh::Deployer::Config.resources

    expect(resources).to be_kind_of(Hash)
    expect(resources['persistent_disk']).to be_kind_of(Integer)
    cloud_properties = resources['cloud_properties']
    expect(cloud_properties).to be_kind_of(Hash)
    %w(instance_type).each do |key|
      expect(cloud_properties[key]).to_not be_nil
    end
  end

  it 'should configure agent using mbus property' do
    Bosh::Deployer::Config.configure(config)

    agent = Bosh::Deployer::Config.agent
    expect(agent).to be_kind_of(Bosh::Agent::HTTPClient)
  end

  it 'should have rackapce and registry object access' do
    Bosh::Deployer::Config.configure(config)

    cloud = Bosh::Deployer::Config.cloud
    expect(cloud.compute_api).to eql(compute_api)
    expect(cloud.blockstorage_api).to eql(blockstorage_api)
    expect(cloud.respond_to?(:registry)).to be_true
    expect(cloud.registry).to be_kind_of(Bosh::Registry::Client)
  end
end