# Copyright (c) 2009-2013 GoPivotal, Inc.

require 'spec_helper'

describe Bosh::Director::Api::ReleaseManager do

  let(:tmpdir) { Dir.tmpdir }
  let(:user) { Bosh::Director::Models::User.make }
  let(:task_id) { 1 }
  let(:task) { double('task', :id => task_id) }
  let(:release) { 'release_location' }
  let(:release_manager) { described_class.new }

  describe 'create_release' do
    before do
      release_manager.stub(:create_task).and_return(task)
      Dir.stub(:mktmpdir).and_return(tmpdir)
    end   

    context 'local release' do
      it 'enqueues a task to upload a local stemcell' do                
        release_manager.should_receive(:check_available_disk_space).and_return(true)
        release_manager.should_receive(:write_file)
        Resque.should_receive(:enqueue).with(BD::Jobs::UpdateRelease, task_id, tmpdir, {})
        
        expect(release_manager.create_release(user, release)).to eql(task)
      end      
    end
    
    context 'remote release' do
      it 'enqueues a task to upload a remote release' do
        Resque.should_receive(:enqueue).with(BD::Jobs::UpdateRelease, task_id, tmpdir, {'remote' => true,
                                                                                        'location' => release})
        
        expect(release_manager.create_release(user, release, {'remote' => true})).to eql(task)
      end
    end
  end  
end