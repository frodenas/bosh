# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::Cloud do
  let(:subject) { described_class }
  let(:cloud) { subject.new(cloud_options) }

  let(:compute_api) { double('compute_api') }
  let(:stemcell_manager) { double(Bosh::RackspaceCloud::StemcellManager) }
  let(:server_manager) { double(Bosh::RackspaceCloud::ServerManager) }
  let(:blockstorage_api) { double('blockstorage_api') }
  let(:volume_manager) { double(Bosh::RackspaceCloud::VolumeManager) }
  let(:volume_snapshot_manager) { double(Bosh::RackspaceCloud::VolumeSnapshotManager) }
  let(:network_manager) { double(Bosh::RackspaceCloud::NetworkManager) }

  let(:registry) { double('registry') }
  let(:rackspace_username) { 'rackspace_username' }
  let(:rackspace_api_key) { 'rackspace_api_key' }
  let(:rackspace_options) do
    {
      'username' => rackspace_username,
      'api_key'  => rackspace_api_key
    }
  end
  let(:registry_endpoint) { 'registry_endpoint' }
  let(:registry_user) { 'registry_user' }
  let(:registry_password) { 'registry_password' }
  let(:registry_options) do
    {
      'endpoint' => registry_endpoint,
      'user'     => registry_user,
      'password' => registry_password
    }
  end
  let(:cloud_options) do
    {
      'rackspace' => rackspace_options,
      'registry' => registry_options
    }
  end

  let(:stemcell_id) { 'stemcell-id' }
  let(:image) { double('image', id: stemcell_id) }
  let(:server_id) { 'server-id' }
  let(:server_name) { 'server-name' }
  let(:server) { double('server', id: server_id, name: server_name) }
  let(:volume_id) { 'volume-id' }
  let(:volume) { double('volume', id: volume_id) }
  let(:device_name) { '/dev/xvdb' }
  let(:attachment) { double('attachment', volume_id: volume_id, device: device_name) }
  let(:volume_snapshot_id) { 'volume-snapshot-id' }
  let(:volume_snapshot) { double('volume-snapshot', id: volume_snapshot_id) }

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

  let(:resource_pool) { {} }

  let(:agent_id) { 'agent-id' }
  let(:environment) { { 'bosh' => { 'password' => 'bosh-password' } } }
  let(:agent_settings) do
    {
      'vm' => { 'name' => server_name },
      'agent_id' => agent_id,
      'networks' => network_spec,
      'disks' => { 'system' => '/dev/xvda', 'persistent' => {} },
      'env' => environment
    }
  end
  let(:agent_settings_with_network) do
    settings = agent_settings
    settings['networks'] = network_spec
    settings
  end
  let(:persistent_disk) { { volume_id => device_name } }
  let(:agent_settings_with_disk) do
    settings = agent_settings
    settings['disks']['persistent'] = persistent_disk
    settings
  end

  before do
    Fog::Compute.stub(:new).and_return(compute_api)
    Bosh::RackspaceCloud::StemcellManager.stub(:new).with(compute_api).and_return(stemcell_manager)
    Bosh::RackspaceCloud::ServerManager.stub(:new).with(compute_api).and_return(server_manager)
    Bosh::RackspaceCloud::NetworkManager.stub(:new).with(compute_api, network_spec).and_return(network_manager)
    Fog::Rackspace::BlockStorage.stub(:new).and_return(blockstorage_api)
    Bosh::RackspaceCloud::VolumeManager.stub(:new).with(blockstorage_api).and_return(volume_manager)
    Bosh::RackspaceCloud::VolumeSnapshotManager.stub(:new).with(blockstorage_api).and_return(volume_snapshot_manager)
    Bosh::Registry::Client.stub(:new).and_return(registry)
  end

  describe :new do
    it 'should set attribute readers' do
      manager = subject.new(cloud_options)
      expect(manager.compute_api).to eql(compute_api)
      expect(manager.blockstorage_api).to eql(blockstorage_api)
      expect(manager.registry).to eql(registry)
    end

    it 'should initialize Compute api' do
      Fog::Compute.should_receive(:new).with(provider: 'Rackspace',
                                             version: :v2,
                                             rackspace_username: rackspace_username,
                                             rackspace_api_key: rackspace_api_key,
                                             rackspace_region: nil,
                                             rackspace_auth_url: nil,
                                             connection_options: nil)

      subject.new(cloud_options)
    end

    it 'should raise a CloudError exception if cannot connect to Compute api' do
      Fog::Compute.should_receive(:new).and_raise(Fog::Errors::Error)

      expect do
        subject.new(cloud_options)
      end.to raise_error(Bosh::Clouds::CloudError,
                         'Unable to connect to the Rackspace Compute API. Check task debug log for details.')
    end

    it 'should initialize Block Storage api' do
      Fog::Rackspace::BlockStorage.should_receive(:new).with(rackspace_username: rackspace_username,
                                                             rackspace_api_key: rackspace_api_key,
                                                             rackspace_region: nil,
                                                             rackspace_auth_url: nil,
                                                             connection_options: nil)

      subject.new(cloud_options)
    end

    it 'should raise a CloudError exception if cannot connect to Block Storage api' do
      Fog::Rackspace::BlockStorage.should_receive(:new).and_raise(Fog::Errors::Error)

      expect do
        subject.new(cloud_options)
      end.to raise_error(Bosh::Clouds::CloudError,
                         'Unable to connect to the Rackspace Block Storage API. Check task debug log for details.')
    end

    it 'should initialize Bosh Registry client' do
      Bosh::Registry::Client.should_receive(:new).with(registry_endpoint, registry_user, registry_password)

      subject.new(cloud_options)
    end

    context 'validates rackspace options' do
      let(:rackspace_options) { { } }

      it 'should raise a CloudError exception if there is a missing parameter' do
        expect do
          subject.new(cloud_options)
        end.to raise_error(Bosh::Clouds::CloudError,
                           'Missing configuration parameters: rackspace:username, rackspace:api_key')
      end
    end

    context 'validates registry options' do
      let(:registry_options) { { } }

      it 'should raise a CloudError exception if there is a missing parameter' do
        expect do
          subject.new(cloud_options)
        end.to raise_error(Bosh::Clouds::CloudError,
                           'Missing configuration parameters: registry:endpoint, registry:user, registry:password')
      end
    end
  end

  describe :create_stemcell do
    it 'should create a stemcell' do
      stemcell_manager.should_receive(:create).with({ 'infraestructure' => 'rackspace' }).and_return(image)

      expect(cloud.create_stemcell('path', { 'infraestructure' => 'rackspace' })).to eql(stemcell_id)
    end
  end

  describe :delete_stemcell do
    it 'should delete a stemcell' do
      stemcell_manager.should_receive(:delete).with(stemcell_id)

      cloud.delete_stemcell(stemcell_id)
    end
  end

  describe :create_vm do
    it 'should create a vm' do
      server_manager.should_receive(:create)
        .with(stemcell_id, resource_pool, network_manager, registry_endpoint).and_return(server)
      network_manager.should_receive(:configure).with(server)
      registry.should_receive(:endpoint).and_return(registry_endpoint)
      registry.should_receive(:update_settings).with(server_name, agent_settings)

      expect(cloud.create_vm(agent_id, stemcell_id, resource_pool, network_spec, nil, environment)).to eql(server_id)
    end
  end

  describe :delete_vm do
    it 'should delete a vm' do
      server_manager.should_receive(:get).with(server_id).and_return(server)
      server_manager.should_receive(:terminate).with(server_id)
      registry.should_receive(:delete_settings).with(server_name)

      cloud.delete_vm(server_id)
    end
  end

  describe :reboot_vm do
    it 'should reboot a vm' do
      server_manager.should_receive(:reboot).with(server_id)

      cloud.reboot_vm(server_id)
    end
  end

  describe :has_vm? do
    it 'should return true if vm exist' do
      server_manager.should_receive(:exists?).with(server_id).and_return(true)

      expect(cloud.has_vm?(server_id)).to be_true
    end

    it 'should return false if vm does not exist' do
      server_manager.should_receive(:exists?).with(server_id).and_return(false)

      expect(cloud.has_vm?(server_id)).to be_false
    end
  end

  describe :set_vm_metadata do
    it 'should set metadata for a vm' do
      server_manager.should_receive(:set_metadata).with(server_id, { job: 'job', index: 'index' })

      cloud.set_vm_metadata(server_id, { job: 'job', index: 'index' })
    end
  end

  describe :configure_networks do
    it 'should configure networks for a vm' do
      server_manager.should_receive(:get).with(server_id).and_return(server)
      network_manager.should_receive(:configure).with(server)
      registry.should_receive(:read_settings).with(server_name).and_return(agent_settings)
      registry.should_receive(:update_settings).with(server_name, agent_settings_with_network)

      cloud.configure_networks(server_id, network_spec)
    end
  end

  describe :create_disk do
    it 'should create a disk' do
      volume_manager.should_receive(:create).with(1024).and_return(volume)

      expect(cloud.create_disk(1024)).to eql(volume_id)
    end
  end

  describe :delete_disk do
    it 'should delete a disk' do
      volume_manager.should_receive(:delete).with(volume_id)

      cloud.delete_disk(volume_id)
    end
  end

  describe :attach_disk do
    it 'should attach a disk' do
      server_manager.should_receive(:get).with(server_id).and_return(server)
      volume_manager.should_receive(:get).with(volume_id).and_return(volume)
      server_manager.should_receive(:attach_volume).with(server, volume).and_return(attachment)
      registry.should_receive(:read_settings).with(server_name).and_return(agent_settings)
      registry.should_receive(:update_settings).with(server_name, agent_settings_with_disk)

      cloud.attach_disk(server_id, volume_id)
    end
  end

  describe :detach_disk do
    it 'should detach a disk' do
      server_manager.should_receive(:get).with(server_id).and_return(server)
      volume_manager.should_receive(:get).with(volume_id).and_return(volume)
      server_manager.should_receive(:detach_volume).with(server, volume)
      registry.should_receive(:read_settings).with(server_name).and_return(agent_settings_with_disk)
      registry.should_receive(:update_settings).with(server_name, agent_settings)

      cloud.detach_disk(server_id, volume_id)
    end
  end

  describe :get_disks do
    it 'should return the list of attached disks of a server' do
      server_manager.should_receive(:get_attached_volumes).with(server_id).and_return([volume_id])

      expect(cloud.get_disks(server_id)).to eql([volume_id])
    end
  end

  describe :snapshot_disk do
    it 'should take a snapshot of a disk' do
      volume_snapshot_manager.should_receive(:create).with(volume_id, {}).and_return(volume_snapshot)

      expect(cloud.snapshot_disk(volume_id, {})).to eql(volume_snapshot_id)
    end
  end

  describe :delete_snapshot do
    it 'should delete a volume snapshot' do
      volume_snapshot_manager.should_receive(:delete).with(volume_snapshot_id)

      cloud.delete_snapshot(volume_snapshot_id)
    end
  end

  describe :validate_deployment do
    it 'should raise a NotImplemented exception' do
      expect do
        cloud.validate_deployment({}, {})
      end.to raise_error(Bosh::Clouds::NotImplemented)
    end
  end
end