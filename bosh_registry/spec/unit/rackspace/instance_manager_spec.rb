# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'
require 'bosh_registry/instance_manager/rackspace'

describe Bosh::Registry::InstanceManager::Rackspace do
  let(:subject) { described_class }
  let(:config) { valid_config }

  before(:each) do
    config['cloud'] = {
      'plugin' => 'rackspace',
      'rackspace' => {
        'username' => 'foo',
        'api_key'  => 'bar',
      }
    }
  end

  describe :new do
    it 'validates presence of cloud option' do
      config['cloud'].delete('rackspace')

      expect do
        subject.new(config['cloud'])
      end.to raise_error(Bosh::Registry::ConfigError, /Missing configuration parameters: rackspace/)
    end

    it 'validates presence of rackspace username' do
      config['cloud']['rackspace'].delete('username')

      expect do
        subject.new(config['cloud'])
      end.to raise_error(Bosh::Registry::ConfigError, /Missing configuration parameters: rackspace:username/)
    end

    it 'validates presence of rackspace api key' do
      config['cloud']['rackspace'].delete('api_key')

      expect do
        subject.new(config['cloud'])
      end.to raise_error(Bosh::Registry::ConfigError, /Missing configuration parameters: rackspace:api_key/)
    end
  end

  describe :instance_ips do
    let(:manager) { subject.new(config['cloud']) }
    let(:compute_api) { double('compute-api') }
    let(:server_name) { 'server-name' }
    let(:server) { mock('server', name: server_name) }
    let(:address1) { '166.78.105.63' }
    let(:address2) { '2001:4801:7817:0072:0fe1:75e8:ff10:61a9' }
    let(:address3) { '10.177.18.209' }
    let(:addresses) do
      {
        'public' => [
          { 'version' => 4, 'addr' => address1 },
          { 'version' => 6, 'addr' => address2 }
        ],
        'private' => [
          { 'version' => 4, 'addr' => address3 }
        ]
      }
    end

    before do
      Fog::Compute.stub(:new).and_return(compute_api)
    end

    it 'should return the list of server ips' do
      compute_api.should_receive(:servers).and_return([server])
      server.should_receive(:addresses).and_return(addresses)

      ips = manager.instance_ips(server_name)
      expect(ips).to include address1
      expect(ips).to include address2
      expect(ips).to include address3
    end

    it 'should return an empty array if server has no ips' do
      compute_api.should_receive(:servers).and_return([server])
      server.should_receive(:addresses).and_return([])

      expect(manager.instance_ips(server_name)).to eql([])
    end

    it 'should raise a InstanceNotFound if server name is not found' do
      compute_api.should_receive(:servers).and_return([])
      server.should_not_receive(:addresses)

      expect do
        manager.instance_ips(server_name)
      end.to raise_error(Bosh::Registry::InstanceNotFound, "Server `#{server_name}' not found")
    end

    it 'should use rackspace optional parms if set' do
      config['cloud']['rackspace']['region'] = :ord
      config['cloud']['rackspace']['auth_url'] = Fog::Compute::RackspaceV2::ORD_ENDPOINT
      config['cloud']['rackspace']['connection_options'] = { connect_timeout: 30 }
      Fog::Compute.should_receive(:new).with(provider: 'Rackspace',
                                             version: :v2,
                                             rackspace_username: 'foo',
                                             rackspace_api_key: 'bar',
                                             rackspace_region: :ord,
                                             rackspace_auth_url: Fog::Compute::RackspaceV2::ORD_ENDPOINT,
                                             connection_options: { connect_timeout: 30 }
      )

      compute_api.should_receive(:servers).and_return([server])
      server.should_receive(:addresses).and_return([])

      manager.instance_ips(server_name)
    end

    it 'should raise a ConnectionError if unable to connect to the Rackspace API' do
      Fog::Compute.should_receive(:new).and_raise(Fog::Errors::Error)

      expect do
        manager.instance_ips(server_name)
      end.to raise_error(Bosh::Registry::ConnectionError, 'Unable to connect to the Rackspace Compute API')
    end
  end
end