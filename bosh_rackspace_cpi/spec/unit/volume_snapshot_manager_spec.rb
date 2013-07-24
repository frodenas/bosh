# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::VolumeSnapshotManager do
  let(:blockstorage_api) { double('blockstorage_api') }
  let(:subject) { described_class.new(blockstorage_api) }

  let(:volume_id) { 'volume-id' }
  let(:volume) { double('volume', id: volume_id) }

  let(:snapshots) { double('snapshots') }
  let(:volume_snapshot_id) { 'volume-snapshot-id' }
  let(:volume_snapshot_state) { :available }
  let(:volume_snapshot) { double('volume-snapshot', id: volume_snapshot_id, state: volume_snapshot_state) }

  let(:snapshot_wait_manager) { double(Bosh::RackspaceCloud::ResourceWaitManager) }

  before do
    blockstorage_api.stub(:snapshots).and_return(snapshots)
    Bosh::RackspaceCloud::ResourceWaitManager.stub(:new).with(volume_snapshot).and_return(snapshot_wait_manager)
  end

  describe :get do
    it 'should return a volume snapshot' do
      snapshots.should_receive(:get).with(volume_snapshot_id).and_return(volume_snapshot)

      expect(subject.get(volume_snapshot_id)).to eql(volume_snapshot)
    end

    it 'should raise a CloudError exception if volume snapshot is not found' do
      snapshots.should_receive(:get).with(volume_snapshot_id).and_return(nil)

      expect do
        subject.get(volume_snapshot_id)
      end.to raise_error(Bosh::Clouds::CloudError, "Volume snapshot `#{volume_snapshot_id}' not found")
    end
  end

  describe :create do
    let(:volume_manager) { double(Bosh::RackspaceCloud::VolumeManager) }
    let(:unique_name) { SecureRandom.uuid }
    let(:deployment) { 'deployment' }
    let(:job) { 'job' }
    let(:index) { 'index' }
    let(:metadata) do
      {
        deployment: deployment,
        job: job,
        index: index
      }
    end
    let(:volume_snapshot_params) do
      {
        force: true,
        volume_id: volume_id,
        display_name: "snapshot-#{unique_name}",
        display_description: volume_snapshot_description
      }
    end

    before do
      Bosh::RackspaceCloud::VolumeManager.stub(:new).with(blockstorage_api).and_return(volume_manager)
      subject.stub(:generate_unique_name).and_return(unique_name)
    end

    context 'when volume has attachments' do
      let(:device_name) { 'xvdb'  }
      let(:attachments) { [{ 'device' => "/dev/#{device_name}" }] }
      let(:volume_snapshot_description) { "#{deployment}/#{job}/#{index}/#{device_name}" }

      it 'should create a volume snapshot' do
        volume_manager.should_receive(:get).with(volume_id).and_return(volume)
        volume.should_receive(:attachments).and_return(attachments)

        snapshots.should_receive(:new).with(volume_snapshot_params).and_return(volume_snapshot)
        volume_snapshot.should_receive(:save).with(true)
        snapshot_wait_manager.should_receive(:wait_for).with(:available)
        volume_snapshot.should_receive(:reload).and_return(volume_snapshot)

        expect(subject.create(volume_id, metadata)).to eql(volume_snapshot)
      end
    end

    context 'when volume has no attachments' do
      let(:attachments) { [] }
      let(:volume_snapshot_description) { "#{deployment}/#{job}/#{index}" }

      it 'should create a volume snapshot' do
        volume_manager.should_receive(:get).with(volume_id).and_return(volume)
        volume.should_receive(:attachments).and_return(attachments)

        snapshots.should_receive(:new).with(volume_snapshot_params).and_return(volume_snapshot)
        volume_snapshot.should_receive(:save).with(true)
        snapshot_wait_manager.should_receive(:wait_for).with(:available)
        volume_snapshot.should_receive(:reload).and_return(volume_snapshot)

        expect(subject.create(volume_id, metadata)).to eql(volume_snapshot)
      end
    end
  end

  describe :delete do
    before do
      snapshots.should_receive(:get).with(volume_snapshot_id).and_return(volume_snapshot)
    end

    it 'should delete a volume snapshot' do
      volume_snapshot.should_receive(:ready?).and_return(true)
      volume_snapshot.should_receive(:destroy)
      snapshot_wait_manager.should_receive(:wait_for).with(:deleted, allow_notfound: true)

      subject.delete(volume_snapshot_id)
    end

    it 'should raise a CloudError exception if volume snapshot is not in a ready state' do
      volume_snapshot.should_receive(:ready?).and_return(false)

      expect do
        subject.delete(volume_snapshot_id)
      end.to raise_error(Bosh::Clouds::CloudError,
                         "Cannot delete volume snapshot `#{volume_snapshot_id}', state is `#{volume_snapshot_state}'")
    end
  end
end