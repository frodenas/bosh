# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'
require 'tempfile'
require 'cloud'
require 'cloud/rackspace'

##
# BOSH Rackspace CPI Integration tests
#
describe Bosh::RackspaceCloud::Cloud do
  let(:cpi_options) do
    {
      'rackspace' => {
        'username'           => ENV['BOSH_RACKSPACE_USERNAME'],
        'api_key'            => ENV['BOSH_RACKSPACE_API_KEY'],
        'region'             => ENV['BOSH_RACKSPACE_REGION'],
        'auth_url'           => ENV['BOSH_RACKSPACE_AUTH_URL'],
        'connection_options' => ENV['BOSH_RACKSPACE_CONNECTION_OPTIONS'],
      },
      'registry'   => {
        'endpoint' => 'fake',
        'user'     => 'fake',
        'password' => 'fake'
      }
    }
  end

  let(:cpi) { described_class.new(cpi_options) }
  let(:image_id) { '5ae0db04-dadd-4de3-8e94-2f0669e279bf' } # Ubuntu 10.04 LTS (Lucid Lynx)

  before :all do
    unless ENV['BOSH_RACKSPACE_USERNAME'] && ENV['BOSH_RACKSPACE_API_KEY']
      raise "Mising env var. You need 'BOSH_RACKSPACE_USERNAME' and 'BOSH_RACKSPACE_API_KEY' set."
    end
  end

  before(:each) do
    delegate = double('delegate', logger: Logger.new(STDOUT))
    delegate.stub(:task_checkpoint)
    Bosh::Clouds::Config.configure(delegate)
    Bosh::Registry::Client.stub(:new).and_return(double('registry').as_null_object)

    @server_id = nil
    @volume_id = nil
  end

  after(:each) do
    if @server_id
      cpi.delete_vm(@server_id)
      expect(cpi.has_vm?(@server_id)).to be_false
    end
    cpi.delete_disk(@volume_id) if @volume_id
  end

  def vm_lifecycle(stemcell_id, network_spec, disk_locality)
    @server_id = cpi.create_vm('agent-007', stemcell_id, { 'instance_type' => '1GB Standard Instance' },
                               network_spec, disk_locality, { 'key' => 'value' })

    @server_id.should_not be_nil

    expect(cpi.has_vm?(@server_id)).to be_true

    metadata = { deployment: 'deployment', job: 'cpi_spec', index: '0' }
    cpi.set_vm_metadata(@server_id, metadata)

    @volume_id = cpi.create_disk(102_400, @server_id)
    expect(@volume_id).to_not be_nil

    cpi.attach_disk(@server_id, @volume_id)

    expect(cpi.get_disks(@server_id)).to eql([@volume_id])

    metadata[:director_name] = 'Director'
    metadata[:director_uuid] = '6d06b0cc-2c08-43c5-95be-f1b2dd247e18'
    metadata[:agent_id] = 'agent-007'
    metadata[:instance_id] = 'instance'
    snapshot_id = cpi.snapshot_disk(@volume_id, metadata)
    expect(snapshot_id).to_not be_nil

    cpi.delete_snapshot(snapshot_id)

    cpi.detach_disk(@server_id, @volume_id)
  end

  describe 'dynamic network' do
    let(:network_spec) do
      {
        'default' => {
          'type' => 'dynamic',
          'cloud_properties' => {}
        }
      }
    end

    context 'without existing disks' do
      it 'should exercise the vm lifecycle' do
        vm_lifecycle(image_id, network_spec, [])
      end
    end

    context 'with existing disks' do
      before do
        @existing_volume_id = cpi.create_disk(102_400)
      end

      after do
        cpi.delete_disk(@existing_volume_id) if @existing_volume_id
      end

      it 'should exercise the vm lifecycle' do
        vm_lifecycle(image_id, network_spec, [@existing_volume_id])
      end
    end
  end
end