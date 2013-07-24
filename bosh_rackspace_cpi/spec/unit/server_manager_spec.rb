# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::ServerManager do
  let(:compute_api) { double('compute_api') }
  let(:subject) { described_class.new(compute_api) }
  let(:stemcell_manager) { double(Bosh::RackspaceCloud::StemcellManager) }
  let(:network_manager) { double(Bosh::RackspaceCloud::NetworkManager) }

  let(:servers) { double('servers') }
  let(:server_id) { 'server-id' }
  let(:server_name) { 'server_name' }
  let(:server_state) { :available }
  let(:server) { double('server', id: server_id, name: server_name, state: server_state) }

  let(:stemcell_id) { 'stemcell-id' }
  let(:stemcell_name) { 'stemcell_name' }
  let(:image) { double('image', id: stemcell_id, name: stemcell_name) }
  let(:flavor_id) { 'flavor-id' }
  let(:flavor_name) { 'flavor-name' }
  let(:flavor) { double('flavor', id: flavor_id, name: flavor_name) }

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
  let(:registry_endpoint) { 'registry_endpoint' }

  let(:volume_id) { 'volume-id' }
  let(:volume) { double('volume', id: volume_id) }
  let(:attachment) { double('attachment', volume_id: volume_id, device: '/dev/xvdb') }

  let(:server_wait_manager) { double(Bosh::RackspaceCloud::ResourceWaitManager) }
  let(:volume_wait_manager) { double(Bosh::RackspaceCloud::ResourceWaitManager) }

  before do
    compute_api.stub(:servers).and_return(servers)
    Bosh::RackspaceCloud::NetworkManager.stub(:new).with(compute_api, network_spec).and_return(network_manager)
    Bosh::RackspaceCloud::ResourceWaitManager.stub(:new).with(server).and_return(server_wait_manager)
    Bosh::RackspaceCloud::ResourceWaitManager.stub(:new).with(volume).and_return(volume_wait_manager)
  end

  describe :get do
    it 'should return a server' do
      servers.should_receive(:get).with(server_id).and_return(server)

      expect(subject.get(server_id)).to eql(server)
    end

    it 'should raise a CloudError exception if server is not found' do
      servers.should_receive(:get).with(server_id).and_return(nil)

      expect do
        subject.get(server_id)
      end.to raise_error(Bosh::Clouds::CloudError, "Server `#{server_id}' not found")
    end
  end

  describe :create do
    let(:unique_name) { SecureRandom.uuid }
    let(:public_key) { 'openssh-public-key' }
    let(:resource_pool) { { 'instance_type' => flavor_name, 'public_key' => public_key } }
    let(:user_data_file) { '/var/vcap/bosh/user_data.json' }
    let(:user_data) do
      {
        'registry' => { 'endpoint' => registry_endpoint },
        'server' => { 'name' => "server-#{unique_name}" },
        'dns' => { 'nameserver' => network_dns },
        'openssh' => { 'public_key' => public_key }
      }
    end
    let(:server_params) do
      {
        name: "server-#{unique_name}",
        image_id: stemcell_id,
        flavor_id: flavor_id,
        personality: [{ path: user_data_file, contents: Base64.encode64(Yajl::Encoder.encode(user_data)) }],
        networks: [{ id: network_id }]
      }
    end

    before do
      subject.stub(:generate_unique_name).and_return(unique_name)
      Bosh::RackspaceCloud::StemcellManager.stub(:new).with(compute_api).and_return(stemcell_manager)
    end

    it 'should create a server' do
      stemcell_manager.should_receive(:get).with(stemcell_id).and_return(image)
      compute_api.should_receive(:flavors).and_return([flavor])
      network_manager.should_receive(:dns).and_return(network_dns)
      network_manager.should_receive(:network_ids).and_return(network_ids)
      servers.should_receive(:create).with(server_params).and_return(server)
      server_wait_manager.should_receive(:wait_for).with(:active)
      server.should_receive(:reload).and_return(server)

      expect(subject.create(stemcell_id, resource_pool, network_manager, registry_endpoint)).to eql(server)
    end

    it 'should raise a VMCreationFailed exception when unable to create a vm' do
      subject.should_receive(:server_params).and_return({})
      servers.should_receive(:create).and_return(server)
      server_wait_manager.should_receive(:wait_for).with(:active).and_raise(Bosh::Clouds::CloudError)

      expect do
        subject.create(stemcell_id, resource_pool, network_manager, registry_endpoint)
      end.to raise_error(Bosh::Clouds::VMCreationFailed)
    end

    context 'when flavor does not exist' do
      let(:resource_pool) { { 'instance_type' => 'unknown' } }

      it 'should raise a CloudError exception' do
        stemcell_manager.should_receive(:get).with(stemcell_id).and_return(image)
        compute_api.should_receive(:flavors).and_return([flavor])

        expect do
          subject.create(stemcell_id, resource_pool, network_manager, registry_endpoint)
        end.to raise_error(Bosh::Clouds::CloudError, "Flavor `unknown' not found")
      end
    end
  end

  describe :terminate do
    it 'should terminate a server' do
      servers.should_receive(:get).with(server_id).and_return(server)
      server.should_receive(:destroy)
      server_wait_manager.should_receive(:wait_for).with([:terminated, :deleted], allow_notfound: true)

      subject.terminate(server_id)
    end
  end

  describe :reboot do
    it 'should reboot a server' do
      servers.should_receive(:get).with(server_id).and_return(server)
      server.should_receive(:reboot)
      server_wait_manager.should_receive(:wait_for).with(:active)

      subject.reboot(server_id)
    end
  end

  describe :exists? do
    context 'when server exist' do
      before(:each) do
        servers.should_receive(:get).with(server_id).and_return(server)
      end

      it 'should return true' do
        expect(subject.exists?(server_id)).to be_true
      end

      context 'and state is terminated' do
        let(:server_state) { :terminated }

        it 'should return false' do
          expect(subject.exists?(server_id)).to be_false
        end
      end

      context 'and state is deleted' do
        let(:server_state) { :deleted }

        it 'should return false' do
          expect(subject.exists?(server_id)).to be_false
        end
      end
    end

    context 'when server does not exist' do
      before(:each) do
        servers.should_receive(:get).with(server_id).and_return(nil)
      end

      it 'should return false' do
        expect(subject.exists?(server_id)).to be_false
      end
    end
  end

  describe :set_metadata do
    let(:metadata) { { job: 'job', index: 'index' } }
    let(:metadata_manager) { Bosh::RackspaceCloud::TagManager }

    it 'should set metadata' do
      servers.should_receive(:get).with(server_id).and_return(server)
      metadata_manager.should_receive(:tag).with(server, :job, 'job')
      metadata_manager.should_receive(:tag).with(server, :index, 'index')

      subject.set_metadata(server_id, metadata)
    end
  end

  describe :attach_volume do
    it 'should attach a volume to a server' do
      server.should_receive(:attach_volume).with(volume)
      volume_wait_manager.should_receive(:wait_for).with('in-use'.to_sym)

      subject.attach_volume(server, volume)
    end
  end

  describe :detach_volume do
    it 'should detach a volume from a server' do
      server.should_receive(:attachments).and_return([attachment])
      attachment.should_receive(:detach)
      volume_wait_manager.should_receive(:wait_for).with(:available)

      subject.detach_volume(server, volume)
    end

    it 'should raise a CloudError exception when volume is not attached to the server' do
      server.should_receive(:attachments).and_return([])

      expect do
        subject.detach_volume(server, volume)
      end.to raise_error(Bosh::Clouds::CloudError, "Volume `#{volume_id}' is not attached to server `#{server_id}'")
    end
  end

  describe :get_attached_volumes do
    it 'should return the list of attached volumes' do
      servers.should_receive(:get).with(server_id).and_return(server)
      server.should_receive(:attachments).and_return([attachment])

      expect(subject.get_attached_volumes(server_id)).to eql([volume_id])
    end

    it 'should return an empty array if no volumes are attached' do
      servers.should_receive(:get).with(server_id).and_return(server)
      server.should_receive(:attachments).and_return([])

      expect(subject.get_attached_volumes(server_id)).to eql([])
    end
  end
end