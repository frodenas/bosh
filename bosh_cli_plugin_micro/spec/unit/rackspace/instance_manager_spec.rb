# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::Deployer::InstanceManager do
  let(:subject)  { described_class }
  let(:config_dir) { Dir.mktmpdir('bdim_spec') }
  let(:config_rackspace) { spec_asset('test-bootstrap-config-rackspace.yml') }
  let(:config) { Psych.load_file(config_rackspace) }
  let(:deployer) { subject.create(config) }
  let(:spec_rackspace) { spec_asset('apply_spec_rackspace.yml') }
  let(:spec) { Psych.load_file(spec_rackspace) }
  let(:cloud) { double('cloud') }
  let(:compute_api) { double('compute_api') }
  let(:server) { double('server', ipv4_address: '10.0.0.1') }
  let(:servers) { double('servers') }
  let(:blockstorage_api) { double('blockstorage_api') }
  let(:disk_size) { 100 }
  let(:volume) { double('volume', size: disk_size) }
  let(:volumes) { double('volumes') }
  let(:agent) { double('agent') }
  let(:stemcell_file) { 'bosh-instance-1.0.tgz' }
  let(:stemcell_cid) { 'SC-CID' }
  let(:stemcell_cid_new) { 'SC-CID-NEW' }
  let(:vm_cid) { 'VM-CID' }
  let(:vm_cid_new) { 'VM-CID-NEW' }
  let(:disk_cid) { 'DISK-CID' }
  let(:disk_cid_new) { 'DISK-CID-NEW' }

  before(:each) do
    config['dir'] = config_dir
    config['name'] = "spec-#{SecureRandom.uuid}"
    config['logging'] = { 'file' => "#{config_dir}/bmim.log" }
    deployer.stub!(:agent).and_return(agent)
    Bosh::Deployer::Specification.stub!(:load_apply_spec).and_return(spec)
    cloud.stub(:compute_api).and_return(compute_api)
    cloud.stub(:blockstorage_api).and_return(blockstorage_api)
    Bosh::Deployer::Config.stub!(:cloud).and_return(cloud)
  end

  after do
    deployer.state.destroy
    FileUtils.remove_entry_secure config_dir
  end

  describe :create do
    it 'should create an instance' do
      deployer.should_receive(:run_command)
      deployer.stub!(:load_stemcell_manifest).and_return({ 'cloud_properties' => {} })
      cloud.should_receive(:create_stemcell).and_return(stemcell_cid)
      cloud.should_receive(:create_vm).and_return(vm_cid)
      compute_api.should_receive(:servers).twice.and_return(servers)
      servers.should_receive(:get).twice.with(vm_cid).and_return(server)
      deployer.should_receive(:remote_tunnel)
      deployer.should_receive(:wait_until_ready).with('agent')
      cloud.should_receive(:create_disk).and_return(disk_cid)
      cloud.should_receive(:attach_disk).with(vm_cid, disk_cid)
      agent.should_receive(:run_task).with(:mount_disk, disk_cid)
      agent.should_receive(:run_task).with(:stop)
      agent.should_receive(:run_task).with(:apply, spec)
      agent.should_receive(:run_task).with(:start)
      deployer.should_receive(:wait_until_ready).with('director', 1, 600)

      deployer.create(stemcell_file)

      expect(deployer.state.stemcell_cid).to eql(stemcell_cid)
      expect(deployer.state.vm_cid).to eql(vm_cid)
      expect(deployer.state.disk_cid).to eql(disk_cid)
    end

    it 'should fail if VM CID exists' do
      deployer.state.vm_cid = vm_cid

      expect do
        deployer.create(stemcell_file)
      end.to raise_error(Bosh::Cli::CliError, "VM #{vm_cid} already exists")
    end

    it 'should fail if stemcell CID exists' do
      deployer.state.stemcell_cid = stemcell_cid

      expect do
        deployer.create(stemcell_file)
      end.to raise_error(Bosh::Cli::CliError, "stemcell #{stemcell_cid} already exists")
    end
  end

  describe :destroy do
    before do
      deployer.state.disk_cid = disk_cid
      deployer.state.stemcell_cid = stemcell_cid
      deployer.state.vm_cid = vm_cid
    end

    it 'should destroy an instance with disk' do
      agent.should_receive(:run_task).with(:stop)
      agent.should_receive(:list_disk).and_return([disk_cid])
      agent.should_receive(:run_task).with(:unmount_disk, disk_cid)
      cloud.should_receive(:detach_disk).with(vm_cid, disk_cid)
      cloud.should_receive(:delete_disk).with(disk_cid)
      cloud.should_receive(:delete_vm).with(vm_cid)
      cloud.should_receive(:delete_stemcell).with(stemcell_cid)

      deployer.destroy

      expect(deployer.state.stemcell_cid).to be_nil
      expect(deployer.state.vm_cid).to be_nil
      expect(deployer.state.disk_cid).to be_nil
    end

    it 'should destroy an instance without disk' do
      deployer.state.disk_cid = nil
      agent.should_receive(:run_task).with(:stop)
      cloud.should_receive(:delete_vm).with(vm_cid)
      cloud.should_receive(:delete_stemcell).with(stemcell_cid)

      deployer.destroy

      expect(deployer.state.stemcell_cid).to be_nil
      expect(deployer.state.vm_cid).to be_nil
      expect(deployer.state.disk_cid).to be_nil
    end

    it 'should fail unless VM CID exists' do
      deployer.state.disk_cid = nil
      deployer.state.vm_cid = nil
      agent.should_receive(:run_task).with(:stop)

      expect do
        deployer.destroy
      end.to raise_error(Bosh::Cli::CliError, 'Cannot find existing VM')
    end

    it 'should fail unless stemcell CID exists' do
      deployer.state.disk_cid = nil
      deployer.state.stemcell_cid = nil
      agent.should_receive(:run_task).with(:stop)
      cloud.should_receive(:delete_vm).with(vm_cid)

      expect do
        deployer.destroy
      end.to raise_error(Bosh::Cli::CliError, 'Cannot find existing stemcell')
    end
  end

  describe :update do
    before do
      deployer.state.disk_cid = disk_cid
      deployer.state.stemcell_cid = stemcell_cid
      deployer.state.vm_cid = vm_cid
    end

    it 'should update an instance' do
      agent.should_receive(:run_task).with(:stop)
      agent.should_receive(:list_disk).and_return([disk_cid])
      agent.should_receive(:run_task).with(:unmount_disk, disk_cid)
      cloud.should_receive(:detach_disk).with(vm_cid, disk_cid)
      cloud.should_receive(:delete_vm).with(vm_cid)
      cloud.should_receive(:delete_stemcell).with(stemcell_cid)
      deployer.should_receive(:run_command)
      deployer.stub!(:load_stemcell_manifest).and_return({ 'cloud_properties' => {} })
      cloud.should_receive(:create_stemcell).and_return(stemcell_cid_new)
      cloud.should_receive(:create_vm).and_return(vm_cid_new)
      compute_api.should_receive(:servers).twice.and_return(servers)
      servers.should_receive(:get).twice.with(vm_cid_new).and_return(server)
      deployer.should_receive(:remote_tunnel)
      deployer.should_receive(:wait_until_ready).with('agent')
      cloud.should_receive(:attach_disk).with(vm_cid_new, disk_cid)
      agent.should_receive(:run_task).with(:mount_disk, disk_cid)
      blockstorage_api.should_receive(:volumes).and_return(volumes)
      volumes.should_receive(:get).and_return(volume)
      agent.should_receive(:run_task).with(:stop)
      agent.should_receive(:run_task).with(:apply, spec)
      agent.should_receive(:run_task).with(:start)
      deployer.should_receive(:wait_until_ready).with('director', 1, 600)

      deployer.update(stemcell_file)

      expect(deployer.state.stemcell_cid).to eql(stemcell_cid_new)
      expect(deployer.state.vm_cid).to eql(vm_cid_new)
      expect(deployer.state.disk_cid).to eql(disk_cid)
    end

    context 'when persistent disk size changed' do
      let(:disk_size) { 200 }

      it 'should update an instance and migrate the disk' do
        agent.should_receive(:run_task).with(:stop)
        agent.should_receive(:list_disk).and_return([disk_cid])
        agent.should_receive(:run_task).with(:unmount_disk, disk_cid)
        cloud.should_receive(:detach_disk).with(vm_cid, disk_cid)
        cloud.should_receive(:delete_vm).with(vm_cid)
        cloud.should_receive(:delete_stemcell).with(stemcell_cid)
        deployer.should_receive(:run_command)
        deployer.stub!(:load_stemcell_manifest).and_return({ 'cloud_properties' => {} })
        cloud.should_receive(:create_stemcell).and_return(stemcell_cid_new)
        cloud.should_receive(:create_vm).and_return(vm_cid_new)
        compute_api.should_receive(:servers).twice.and_return(servers)
        servers.should_receive(:get).twice.with(vm_cid_new).and_return(server)
        deployer.should_receive(:remote_tunnel)
        deployer.should_receive(:wait_until_ready).with('agent')
        cloud.should_receive(:attach_disk).with(vm_cid_new, disk_cid)
        agent.should_receive(:run_task).with(:mount_disk, disk_cid)
        blockstorage_api.should_receive(:volumes).and_return(volumes)
        volumes.should_receive(:get).and_return(volume)
        cloud.should_receive(:create_disk).and_return(disk_cid_new)
        cloud.should_receive(:attach_disk).with(vm_cid_new, disk_cid_new)
        agent.should_receive(:run_task).with(:mount_disk, disk_cid_new)
        agent.should_receive(:run_task).with(:migrate_disk, disk_cid, disk_cid_new)
        agent.should_receive(:run_task).with(:unmount_disk, disk_cid)
        cloud.should_receive(:detach_disk).with(vm_cid_new, disk_cid)
        cloud.should_receive(:delete_disk).with(disk_cid)
        agent.should_receive(:run_task).with(:stop)
        agent.should_receive(:run_task).with(:apply, spec)
        agent.should_receive(:run_task).with(:start)
        deployer.should_receive(:wait_until_ready).with('director', 1, 600)

        deployer.update(stemcell_file)

        expect(deployer.state.stemcell_cid).to eql(stemcell_cid_new)
        expect(deployer.state.vm_cid).to eql(vm_cid_new)
        expect(deployer.state.disk_cid).to eql(disk_cid_new)
      end
    end
  end
end