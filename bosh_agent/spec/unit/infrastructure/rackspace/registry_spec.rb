# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

require 'spec_helper'
require 'bosh_agent/infrastructure/rackspace'

describe Bosh::Agent::Infrastructure::Rackspace::Registry do
  let(:subject) { described_class }
  let(:registry_schema) { 'http' }
  let(:registry_hostname) { 'registry_endpoint' }
  let(:registry_port) { '25777' }
  let(:registry_endpoint) { "#{registry_schema}://#{registry_hostname}:#{registry_port}" }
  let(:server_name) { 'server-name' }
  let(:nameservers) { nil }
  let(:openssh_public_key) { 'openssh-public-key' }
  let(:user_data) do
    {
      registry: { endpoint: registry_endpoint },
      server: { name: server_name },
      dns: { nameserver: nameservers },
      openssh: { public_key: openssh_public_key }
    }
  end

  describe :get_openssh_key do
    it 'should get openssh public key' do
      File.should_receive(:read).and_return(Yajl::Encoder.encode(user_data))

      expect(subject.get_openssh_key).to eql(openssh_public_key)
    end

    it 'should return nil if user data does not contain an openssh public key' do
      new_user_data = user_data
      new_user_data.delete(:openssh)
      File.should_receive(:read).and_return(Yajl::Encoder.encode(new_user_data))

      expect(subject.get_openssh_key).to eql(nil)
    end

    it 'should raise a LoadSettingsError exception if user data file is not found' do
      File.should_receive(:read).and_raise(Errno::ENOENT)

      expect do
        subject.get_openssh_key
      end.to raise_error(Bosh::Agent::LoadSettingsError, /Failed to get user data from injected user data file/)
    end

    it 'should raise a LoadSettingsError exception if user data can not be parsed' do
      File.should_receive(:read).and_return(user_data)

      expect do
        subject.get_openssh_key
      end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot parse data/)
    end
  end

  describe :get_settings do
    let(:settings) do
      {
        'vm' => { 'name' => server_name },
        'agent_id' => 'agent-id',
        'networks' => { 'default' => { 'type' => 'dynamic' } },
        'disks' => { 'system' => '/dev/xvda', 'persistent' => {} }
      }
    end
    let(:httpclient) { double('httpclient') }
    let(:status) { 200 }
    let(:body) { Yajl::Encoder.encode({ settings: Yajl::Encoder.encode(settings) }) }
    let(:response) { double('response', status: status, body: body) }
    let(:uri) { "#{registry_endpoint}/instances/#{server_name}/settings" }

    before do
      HTTPClient.stub(:new).and_return(httpclient)
      httpclient.stub(:send_timeout=)
      httpclient.stub(:receive_timeout=)
      httpclient.stub(:connect_timeout=)
    end

    it 'should get agent settings' do
      File.should_receive(:read).twice.and_return(Yajl::Encoder.encode(user_data))
      httpclient.should_receive(:get).with(uri, {}, { 'Accept' => 'application/json' }).and_return(response)

      expect(subject.get_settings).to eql(settings)
    end

    it 'should raise a LoadSettingsError exception if user data does not contain registry endpoint' do
      new_user_data = user_data
      new_user_data.delete(:registry)
      File.should_receive(:read).and_return(Yajl::Encoder.encode(new_user_data))

      expect do
        subject.get_settings
      end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot get BOSH registry endpoint from user data/)
    end

    it 'should raise a LoadSettingsError exception if user data does not contain the server name' do
      new_user_data = user_data
      new_user_data.delete(:server)
      File.should_receive(:read).twice.and_return(Yajl::Encoder.encode(new_user_data))

      expect do
        subject.get_settings
      end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot get server name from user data/)
    end

    it 'should raise a LoadSettingsError exception if user data file is not found' do
      File.should_receive(:read).and_raise(Errno::ENOENT)

      expect do
        subject.get_settings
      end.to raise_error(Bosh::Agent::LoadSettingsError, /Failed to get user data from injected user data file/)
    end

    it 'should raise a LoadSettingsError exception if user data can not be parsed' do
      File.should_receive(:read).and_return(user_data)

      expect do
        subject.get_settings
      end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot parse data/)
    end

    context 'with invalid settings' do
      let(:body) { Yajl::Encoder.encode({ settings: settings }) }

      it 'should raise a LoadSettingsError exception if settings can not be parsed' do
        File.should_receive(:read).twice.and_return(Yajl::Encoder.encode(user_data))
        httpclient.should_receive(:get).with(uri, {}, { 'Accept' => 'application/json' }).and_return(response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot parse data/)
      end
    end

    context 'without settings Hash' do
      let(:body) { Yajl::Encoder.encode({ sezzings: Yajl::Encoder.encode(settings) }) }

      it 'should raise a LoadSettingsError exception if settings Hash not found' do
        File.should_receive(:read).twice.and_return(Yajl::Encoder.encode(user_data))
        httpclient.should_receive(:get).with(uri, {}, { 'Accept' => 'application/json' }).and_return(response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, /Invalid response received from BOSH registry/)
      end
    end

    context 'with dns' do
      let(:nameservers) { ['8.8.8.8'] }
      let(:resolver) { double('resolver') }
      let(:registry_ipaddress) { '1.2.3.4' }

      before do
        Resolv::DNS.stub(:new).with(nameserver: nameservers).and_return(resolver)
      end

      context 'when registry endpoint is a hostname' do
        let(:uri) { "#{registry_schema}://#{registry_ipaddress}:#{registry_port}/instances/#{server_name}/settings" }

        it 'should get agent settings' do
          File.should_receive(:read).twice.and_return(Yajl::Encoder.encode(user_data))
          httpclient.should_receive(:get).with(uri, {}, { 'Accept' => 'application/json' }).and_return(response)
          resolver.should_receive(:getaddress).with(registry_hostname).and_return(registry_ipaddress)

          expect(subject.get_settings).to eql(settings)
        end

        it 'should raise a LoadSettingsError exception if can not resolve the hostname' do
          File.should_receive(:read).and_return(Yajl::Encoder.encode(user_data))
          resolver.should_receive(:getaddress).with(registry_hostname).and_raise(Resolv::ResolvError)

          expect do
            subject.get_settings
          end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot lookup registry_endpoint using/)
        end
      end

      context 'when registry endpoint is an IP address' do
        let(:registry_hostname) { '1.2.3.4' }

        it 'should get agent settings' do
          File.should_receive(:read).twice.and_return(Yajl::Encoder.encode(user_data))
          httpclient.should_receive(:get).with(uri, {}, { 'Accept' => 'application/json' }).and_return(response)
          resolver.should_not_receive(:getaddress)

          expect(subject.get_settings).to eql(settings)
        end
      end
    end
  end
end