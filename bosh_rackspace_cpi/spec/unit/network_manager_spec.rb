# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::NetworkManager do
  let(:compute_api) { double('compute_api') }
  let(:subject) { described_class }
  let(:manager) { subject.new(compute_api, network_spec) }

  let(:network_type) { 'dynamic' }
  let(:network_dns) { ['8.8.8.8'] }
  let(:network_id) { '00000000-0000-0000-0000-000000000000' }
  let(:network_ids) { [network_id] }
  let(:cloud_properties) { { 'network_ids' => network_ids } }
  let(:dynamic_network) do
    {
      'type' => network_type,
      'dns' => network_dns,
      'cloud_properties' => cloud_properties
    }
  end
  let(:network_spec) { { 'default' => dynamic_network } }

  let(:network) { double('network', id: network_id) }
  let(:networks) { [network] }

  describe :new do
    it 'should set attribute readers' do
      manager = subject.new(compute_api, network_spec)
      expect(manager.network_spec).to eql(dynamic_network)
      expect(manager.cloud_properties).to eql(cloud_properties)
    end

    it 'validates network spec is a Hash' do
      expect do
        subject.new(compute_api, 'network_spec')
      end.to raise_error(Bosh::Clouds::CloudError, 'Invalid network spec: Hash expected, String provided')
    end

    it 'validates there is only one network' do
      expect do
        subject.new(compute_api, { 'net_1' => dynamic_network, 'net_2' => dynamic_network })
      end.to raise_error(Bosh::Clouds::CloudError, 'Must have exactly one network per instance')
    end

    it 'validates network type is dynamic' do
      expect do
        subject.new(compute_api, { 'default' => { 'type' => 'unknown' } })
      end.to raise_error(Bosh::Clouds::CloudError,
                         "Invalid network type `unknown': Rackspace CPI can only handle `dynamic' network types")
    end

    it 'validates at least one dynamic network is defined' do
      expect do
        subject.new(compute_api, {})
      end.to raise_error(Bosh::Clouds::CloudError, 'At least one dynamic network should be defined')
    end
  end

  describe :configure do
    it 'should do nothing' do
      manager.configure(network_spec)
    end
  end

  describe :network_ids do
    it 'should return the network ids' do
      compute_api.should_receive(:networks).and_return(networks)

      expect(manager.network_ids).to eql(network_ids)
    end

    it 'should raise a CloudError exception when a network id set at cloud properties is not found' do
      compute_api.should_receive(:networks).and_return([])

      expect do
        manager.network_ids
      end.to raise_error(Bosh::Clouds::CloudError, "Network `#{network_id}' not found")
    end

    context 'when network ids list is not set at cloud properties' do
      let(:dynamic_network) { { 'type' => network_type } }

      it 'should return an empty array' do
        expect(manager.network_ids).to eql([])
      end
    end

    context 'when network ids list set at cloud properties is not an Array' do
      let(:network_ids) { network_id }

      it 'should raise a CloudError exception' do
        expect do
          manager.network_ids
        end.to raise_error(Bosh::Clouds::CloudError, 'Invalid network_ids: Array expected, String provided')
      end
    end
  end

  describe :dns do
    it 'should return the dns list' do
      expect(manager.dns).to eql(network_dns)
    end

    context 'when dns list is not set at network spec' do
      let(:dynamic_network) { { 'type' => network_type } }

      it 'should return an empty array' do
        expect(manager.dns).to eql([])
      end
    end

    context 'when dns list set at network spec is not an Array' do
      let(:network_dns) { '8.8.8.8' }

      it 'should raise a CloudError exception' do
        expect do
          manager.dns
        end.to raise_error(Bosh::Clouds::CloudError, 'Invalid dns: Array expected, String provided')
      end
    end
  end
end