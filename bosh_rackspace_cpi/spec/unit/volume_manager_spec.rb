# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::VolumeManager do
  let(:blockstorage_api) { double('blockstorage_api') }
  let(:subject) { described_class.new(blockstorage_api) }

  let(:volumes) { double('volumes') }
  let(:volume_id) { 'volume-id' }
  let(:volume_state) { :available }
  let(:volume) { double('volume', id: volume_id, state: volume_state) }

  let(:volume_wait_manager) { double(Bosh::RackspaceCloud::ResourceWaitManager) }

  before do
    blockstorage_api.stub(:volumes).and_return(volumes)
    Bosh::RackspaceCloud::ResourceWaitManager.stub(:new).with(volume).and_return(volume_wait_manager)
  end

  describe :get do
    it 'should return a volume' do
      volumes.should_receive(:get).with(volume_id).and_return(volume)

      expect(subject.get(volume_id)).to eql(volume)
    end

    it 'should raise a CloudError exception if volume is not found' do
      volumes.should_receive(:get).with(volume_id).and_return(nil)

      expect do
        subject.get(volume_id)
      end.to raise_error(Bosh::Clouds::CloudError, "Volume `#{volume_id}' not found")
    end
  end

  describe :create do
    let(:unique_name) { SecureRandom.uuid }
    let(:disk_size) { 100 }
    let(:volume_params) do
      {
        display_name: "volume-#{unique_name}",
        size: disk_size
      }
    end

    before do
      subject.stub(:generate_unique_name).and_return(unique_name)
    end

    it 'should create a volume' do
      volumes.should_receive(:create).with(volume_params).and_return(volume)
      volume_wait_manager.should_receive(:wait_for).with(:available)
      volume.should_receive(:reload).and_return(volume)

      expect(subject.create(disk_size * 1024)).to eql(volume)
    end

    it 'should raise a CloudError exception if disk size is not an Integer' do
      expect do
        subject.create('size')
      end.to raise_error(Bosh::Clouds::CloudError, 'Volume size needs to be an Integer')
    end

    it 'should raise a CloudError exception if disk size is less than 100GiB' do
      expect do
        subject.create(disk_size)
      end.to raise_error(Bosh::Clouds::CloudError, 'Minimum volume size is 100 GiB, set only 1 GiB')
    end
  end

  describe :delete do
    before do
      volumes.should_receive(:get).with(volume_id).and_return(volume)
    end

    it 'should delete a volume' do
      volume.should_receive(:ready?).and_return(true)
      volume.should_receive(:destroy)
      volume_wait_manager.should_receive(:wait_for).with(:deleted, allow_notfound: true)

      subject.delete(volume_id)
    end

    it 'should raise a CloudError exception if volume is not in a ready state' do
      volume.should_receive(:ready?).and_return(false)

      expect do
        subject.delete(volume_id)
      end.to raise_error(Bosh::Clouds::CloudError,
                         "Cannot delete volume `#{volume_id}', state is `#{volume_state}'")
    end
  end
end