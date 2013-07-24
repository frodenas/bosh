# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::RackspaceCloud::Helpers do
  include Bosh::RackspaceCloud::Helpers

  let(:task_checkpoint_delegator) { double('task_checkpoint_delegator') }

  before do
    Kernel.stub(:sleep)
    Bosh::Clouds::Config.stub(:task_checkpoint).and_return(task_checkpoint_delegator)
  end

  describe :cloud_error do
    let(:logger) { double('logger') }
    let(:error_message) { 'error message' }
    let(:error_exception) { 'error exception' }

    context 'when there is a logger' do
      before do
        @logger = logger
      end

      it 'should raise a CloudError exception and log the error and exception message' do
        logger.should_receive(:error).with(error_message)
        logger.should_receive(:error).with(error_exception)

        expect do
          cloud_error(error_message, error_exception)
        end.to raise_error(Bosh::Clouds::CloudError, error_message)
      end
    end

    context 'when there is no logger' do
      before do
        @logger = nil
      end

      it 'should raise a CloudError exception' do
        logger.should_not_receive(:error)

        expect do
          cloud_error(error_message, error_exception)
        end.to raise_error(Bosh::Clouds::CloudError, error_message)
      end
    end
  end

  describe :generate_unique_name do
    let(:unique_name) { SecureRandom.uuid }

    it 'should generate a unique name' do
      SecureRandom.stub(:uuid).and_return(unique_name)

      expect(generate_unique_name).to eql(unique_name)
    end
  end

  describe :task_checkpoint do
    it 'should return the delegator' do
      expect(task_checkpoint).to eql(task_checkpoint_delegator)
    end
  end

  describe :wrap_rackspace_errors do
    let(:code_block_return) { 'code-block-return' }
    let(:proc) { Proc.new { code_block_return } }

    it 'should yield the block' do
      expect(wrap_rackspace_errors { proc.call }).to eql(code_block_return)
    end

    it 'should raise the exception if it is not a rescued exception' do
      proc.should_receive(:call).and_raise(Bosh::Clouds::CloudError)

      expect do
        wrap_rackspace_errors { proc.call  }
      end.to raise_error(Bosh::Clouds::CloudError)
    end

    context 'when there is a RequestEntityTooLarge exception' do
      let(:retry_after) { '3' }
      let(:overlimit_message) do
        {
          'code' => 413,
          'retryAfter' => retry_after,
          'message' => 'This request was rate-limited.',
          'details' => 'Only 10 POST request(s) can be made to * every minute.'
        }
      end
      let(:body) { { 'overLimit' => overlimit_message } }
      let(:response) { Excon::Response.new(body: JSON.dump(body)) }
      let(:exception) { Excon::Errors::RequestEntityTooLarge.new('', '', response) }

      context 'when there is no overLimit message' do
        let(:body) { { 'unknown' => 'error' } }

        it 'should raise a CloudError exception' do
          proc.should_receive(:call).and_raise(exception)

          expect do
            wrap_rackspace_errors { proc.call  }
          end.to raise_error(Bosh::Clouds::CloudError, 'Rackspace API Over Limit. Check task debug log for details.')
        end
      end

      context 'when there is an overLimit message' do
        it 'should retry the maximum number of retries' do
          proc.should_receive(:call).exactly(10).times.and_raise(exception)

          expect do
            wrap_rackspace_errors { proc.call  }
          end.to raise_error(Bosh::Clouds::CloudError, 'Rackspace API Over Limit. Check task debug log for details.')
        end

        context 'and response contains retry after' do
          it 'should retry the amount of seconds received at the response message' do
            proc.should_receive(:call).and_raise(exception)
            Kernel.should_receive(:sleep).with(retry_after.to_i)
            proc.should_receive(:call)

            wrap_rackspace_errors { proc.call }
          end
        end

        context 'and response does not contain retry after' do
          let(:overlimit_message) { {} }

          it 'should retry the default amount of seconds' do
            proc.should_receive(:call).and_raise(exception)
            Kernel.should_receive(:sleep).with(5)
            proc.should_receive(:call)

            wrap_rackspace_errors { proc.call }
          end
        end
      end
    end
  end
end