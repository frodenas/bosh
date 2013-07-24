# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::TagManager do
  let(:subject) { described_class }

  let(:taggable) { double('taggable') }
  let(:metadata) { double('metadata') }

  before do
    taggable.stub(:metadata).and_return(metadata)
  end

  describe :tag do
    it 'should trim key and value length' do
      metadata.should_receive(:[]=) do |key, value|
        expect(key.size).to eql(255)
        expect(value.size).to eql(255)
      end
      metadata.should_receive(:save)

      subject.tag(taggable, 'x' * 256, 'y' * 256)
    end

    it 'should do nothing if key is nil' do
      taggable.should_not_receive(:metadata)

      subject.tag(taggable, nil, 'value')
    end

    it 'should do nothing if value is nil' do
      taggable.should_not_receive(:metadata)

      subject.tag(taggable, 'key', nil)
    end
  end
end