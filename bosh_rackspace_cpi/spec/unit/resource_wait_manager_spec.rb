# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'
require 'fog/compute/models/server'

describe Bosh::RackspaceCloud::ResourceWaitManager do
  let(:subject) { described_class.new(resource) }
  let(:task_checkpoint_delegator) { double('task_checkpoint_delegator') }

  let(:server_id) { 'server-id' }
  let(:resource) { double(Fog::Compute::Server, identity: server_id) }
  let(:description) { "mock `#{server_id}'" }

  before do
    Kernel.stub(:sleep)
    Bosh::Clouds::Config.stub(:task_checkpoint).and_return(task_checkpoint_delegator)
  end

  describe :new do
    it 'should set attribute readers' do
      expect(subject.resource).to eql(resource)
      expect(subject.description).to eql(description)
    end
  end

  describe :wait_for do
    let(:max_tries) { 2 }
    let(:state_method) { :status }
    let(:allow_notfound) { true }
    let(:target_state) { :available }
    let(:retry_options) do
      {
        max_tries: max_tries,
        state_method: state_method,
        allow_notfound: allow_notfound
      }
    end

    it 'should set attribute readers' do
      Bosh::Common.stub(:retryable)

      subject.wait_for(target_state, retry_options)
      expect(subject.max_tries).to eql(max_tries)
      expect(subject.state_method).to eql(state_method)
      expect(subject.allow_notfound).to eql(allow_notfound)
      expect(subject.target_states).to eql([target_state])
    end

    it 'should return when reached target state' do
      resource.should_receive(:reload).and_return(resource)
      resource.should_receive(state_method).and_return(target_state)

      subject.wait_for(target_state, retry_options)
    end

    it 'should raise a CloudError when timeouts reaching target state' do
      resource.should_receive(:reload).twice.and_return(resource)
      resource.should_receive(state_method).twice.and_return(:unknown)

      expect do
        subject.wait_for(target_state, retry_options)
      end.to raise_error(Bosh::Clouds::CloudError, /Timed out waiting for #{description}/)
    end

    context 'when waiting for a resource' do
      let(:max_tries) { 10 }

      it 'should wait exponentially and raise a CloudError if timeouts' do
        resource.should_receive(:reload).exactly(max_tries).times.and_return(resource)
        resource.should_receive(state_method).exactly(max_tries).times.and_return(:unknown)
        Kernel.should_receive(:sleep).with(2).ordered
        Kernel.should_receive(:sleep).with(4).ordered
        Kernel.should_receive(:sleep).with(8).ordered
        Kernel.should_receive(:sleep).with(16).ordered
        Kernel.should_receive(:sleep).exactly(max_tries - 5).with(32).ordered

        expect do
          subject.wait_for(target_state, retry_options)
        end.to raise_error(Bosh::Clouds::CloudError, /Timed out waiting for #{description}/)
      end
    end

    context 'when resource is not found' do
      before(:each) do
        resource.should_receive(:reload).and_return(nil)
      end

      context 'and not founds are allowed' do
        let(:allow_notfound) { true }

        it 'should return' do
          subject.wait_for(target_state, retry_options)
        end
      end

      context 'and not founds are not allowed' do
        let(:allow_notfound) { false }

        it 'should raise a CloudError exception' do
          expect do
            subject.wait_for(target_state, retry_options)
          end.to raise_error(Bosh::Clouds::CloudError, "#{description} not found")
        end
      end
    end

    context 'when state is error' do
      it 'should raise a CloudError exception' do
        resource.should_receive(:reload).and_return(resource)
        resource.should_receive(state_method).and_return(:error)

        expect do
          subject.wait_for(target_state, retry_options)
        end.to raise_error(Bosh::Clouds::CloudError, /#{description} state is error/)
      end
    end

    context 'when state is error_deleting' do
      it 'should raise a CloudError exception' do
        resource.should_receive(:reload).and_return(resource)
        resource.should_receive(state_method).and_return(:error_deleting)

        expect do
          subject.wait_for(target_state, retry_options)
        end.to raise_error(Bosh::Clouds::CloudError, /#{description} state is error/)
      end
    end
  end
end