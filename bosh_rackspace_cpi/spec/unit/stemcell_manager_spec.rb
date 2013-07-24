# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::StemcellManager do
  let(:compute_api) { double('compute_api') }
  let(:subject) { described_class.new(compute_api) }

  let(:images) { double('images') }
  let(:stemcell_id) { 'stemcell-id' }
  let(:stemcell_name) { 'stemcell_name' }
  let(:image) { double('image', id: stemcell_id, name: stemcell_name) }

  before do
    compute_api.stub(:images).and_return(images)
  end

  describe :get do
    it 'should return an image' do
      images.should_receive(:get).with(stemcell_id).and_return(image)

      expect(subject.get(stemcell_id)).to eql(image)
    end

    it 'should raise a CloudError exception if stemcell is not found' do
      images.should_receive(:get).with(stemcell_id).and_return(nil)

      expect do
        subject.get(stemcell_id)
      end.to raise_error(Bosh::Clouds::CloudError, "Stemcell `#{stemcell_id}' not found in Rackspace")
    end
  end

  describe :create do
    let(:infrastructure) { 'rackspace' }
    let(:image_id) { 'image-id' }
    let(:stemcell_properties) do
      {
        'infrastructure' => infrastructure,
        'image_id' => stemcell_id
      }
    end

    it 'should return the image set at stemcell properties' do
      images.should_receive(:get).with(stemcell_id).and_return(image)

      expect(subject.create(stemcell_properties)).to eql(image)
    end

    context 'when infrastructure is not Rackspace' do
      let(:infrastructure) { 'unknown' }

      it 'should raise a CloudError exception' do
        expect do
          subject.create(stemcell_properties)
        end.to raise_error(Bosh::Clouds::CloudError,
                           "This is not a Rackspace stemcell, infrastructure is `#{infrastructure}'")
      end
    end

    context 'when stemcell properties does not contain a image id' do
      let(:stemcell_id) { nil }

      it 'should raise a CloudError exception' do
        expect do
          subject.create(stemcell_properties)
        end.to raise_error(Bosh::Clouds::CloudError, 'Stemcell properties does not contain image id')
      end
    end
  end

  describe :delete do
    it 'should do nothing' do
      subject.delete(stemcell_id)
    end
  end
end