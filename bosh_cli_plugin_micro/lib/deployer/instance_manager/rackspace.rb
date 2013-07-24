# -*- encoding: utf-8 -*-
# Copyright (c) 2013 GoPivotal, Inc.

module Bosh::Deployer
  ##
  # Instance Manager
  #
  class InstanceManager
    ##
    # Rackspace Instance Manager
    #
    class Rackspace < InstanceManager

      attr_reader :registry_db
      attr_reader :registry_user
      attr_reader :registry_password
      attr_reader :registry_port
      attr_reader :registry_config
      attr_reader :registry_pid

      ##
      # Starts the Instance Manager for Rackspace
      #
      # @return [void]
      def start
        configure_ssh
        setup_registry
        migrate_registry_db
        start_registry_process
      ensure
        registry_config.unlink if registry_config
      end

      ##
      # Stops the Instance Manager for Rackspace
      #
      # @return [void]
      def stop
        stop_registry_process

        if registry_db
          Sequel.connect(registry_connection_settings) do |db|
            @deployments['registry_instances'] = db[:registry_instances].map { |row| row }
          end
        end

        save_state
      ensure
        registry_db.unlink if registry_db
      end

      ##
      # Discovers the server public IP and stores it at Config
      #
      # @return [void]
      def discover_bosh_ip
        if exists?
          ip = service_ip

          if ip != Config.bosh_ip
            Config.bosh_ip = ip
            logger.info("discovered bosh ip=#{Config.bosh_ip}")
          end
        end

        super
      end

      ##
      # Gets the server public IP address
      #
      # @return [String] Server public IP address
      def service_ip
        cloud.compute_api.servers.get(state.vm_cid).ipv4_address
      end

      ##
      # Updates the apply_spec received from microBOSH director with the new settings
      #
      # @return [void]
      def update_spec(spec)
        properties = spec.properties

        # Cloud settings for microBosh deployment vms can be different from microBosh vm cloud options
        properties['rackspace'] = Config.spec_properties['rackspace'] ||
                                  Config.cloud_options['properties']['rackspace'].dup
        properties['rackspace']['registry'] = Config.cloud_options['properties']['registry']

        spec.delete('networks')
      end

      ##
      # Checks if the persistent disk size changed
      #
      # @return [Boolean] True if the persistent disk size changed; False otherwise
      def persistent_disk_changed?
        # since Rackspace stores disk size in GiB and we use MiB there is a risk of conversion errors which lead to
        # an unnecessary disk migration, so we need to do a double conversion here to avoid that
        requested = (Config.resources['persistent_disk'] / 1024.0).ceil * 1024
        requested != disk_size(state.disk_cid)
      end

      private

      ##
      # Set ups Bosh Registry DB and config file
      #
      # @return [void]
      def setup_registry
        @registry_db = Tempfile.new('bosh_registry_db')

        properties = Config.cloud_options['properties']
        uri = URI.parse(properties['registry']['endpoint'])
        @registry_user, @registry_password = uri.userinfo.split(':', 2)
        @registry_port = uri.port

        @registry_config = Tempfile.new('bosh_registry_yml')
        registry_config.write(Psych.dump(registry_config_params))
        registry_config.close
      end

      ##
      # Returns the Bosh Registry config params
      #
      # @return [Hash] Registry config params
      def registry_config_params
        {
          'logfile' => './bosh_registry.log',
          'http' => { 'user' => registry_user, 'password' => registry_password, 'port' => registry_port },
          'db' => registry_connection_settings,
          'cloud' => { 'plugin' => 'rackspace', 'rackspace' => Config.cloud_options['properties']['rackspace'] }
        }
      end

      ##
      # Returns the Bosh Registry DB connection settings
      #
      # @return [Hash] Connections settings
      def registry_connection_settings
        {
          'adapter' => 'sqlite',
          'database' => registry_db.path
        }
      end

      ##
      # Creates the Bosh registry database and imports any existing instance
      #
      # @return [void]
      def migrate_registry_db
        Sequel.connect(registry_connection_settings) do |db|
          db.create_table :registry_instances do
            primary_key :id
            column :instance_id, :text, unique: true, null: false
            column :settings, :text, null: false
          end

          instances = @deployments['registry_instances']
          db[:registry_instances].insert_multiple(instances) if instances
        end
      end

      ##
      # Start a Bosh Registry process
      #
      # @return [void]
      # @raise [Bosh::Cli::CliError] if bosh_registry command is not found
      def start_registry_process
        err("bosh_registry command not found - run 'gem install bosh_registry'") unless has_bosh_registry?
        spawn_registry_process
        test_registry_endpoint
        logger.info("Bosh Registry is ready on port #{registry_port}")
      end

      ##
      # Checks if Bosh Registry command exists anywhere in PATH
      #
      # @return [Boolean] True if command exist; False otherwise
      def has_bosh_registry?(path = ENV['PATH'])
        path.split(':').each do |dir|
          return true if File.exist?(File.join(dir, 'bosh_registry'))
        end
        false
      end

      ##
      # Spawns a Bosh Registry process
      #
      # @return [void]
      # @raise [Bosh::Cli::CliError] If unable to spawn a Bosh Registry process
      def spawn_registry_process
        cmd = "bosh_registry -c #{registry_config.path}"
        @registry_pid = spawn(cmd)

        5.times do
          sleep 1
          if Process.waitpid(registry_pid, Process::WNOHANG)
            err("`#{cmd}` failed, exit status=#{$CHILD_STATUS.exitstatus}")
          end
        end
      end

      ##
      # Tests if Bosh Registry endpoint is ready
      #
      # @return [void]
      # @raise [Bosh::Cli::CliError] If unable to connect to Bosh Registry
      def test_registry_endpoint
        timeout_time = Time.now.to_f + (60 * 5)
        http_client = HTTPClient.new
        begin
          http_client.head("http://127.0.0.1:#{registry_port}")
        rescue URI::Error, SocketError, Errno::ECONNREFUSED, HTTPClient::ReceiveTimeoutError => e
          sleep 1
          retry if timeout_time - Time.now.to_f > 0
          err("Cannot connect to Bosh Registry: #{e.message}")
        end
      end

      ##
      # Stop the Bosh Registry process
      #
      # @return [void]
      def stop_registry_process
        if registry_pid && process_exists?(registry_pid)
          Process.kill('INT', registry_pid)
          Process.waitpid(registry_pid)
        end
      end

      ##
      # Returns the disk size of a Rackspace volume
      #
      # @return [Integer] Disk size in MiB
      def disk_size(cid)
        # Rackspace stores disk size in GiB but we work with MiB
        cloud.blockstorage_api.volumes.get(cid).size * 1024
      end

      ##
      # Configures SSH options
      #
      # @return [void]
      def configure_ssh
        properties = Config.cloud_options['properties']
        @ssh_user = properties['rackspace']['ssh_user']
        @ssh_port = properties['rackspace']['ssh_port'] || 22
        @ssh_wait = properties['rackspace']['ssh_wait'] || 60

        setup_private_ssh_key(properties['rackspace']['private_key'])
        setup_public_ssh_key(properties['rackspace']['public_key'])
      end

      ##
      # Set ups the server private key
      #
      # @param [String] private_key Private key file
      # @return [void]
      def setup_private_ssh_key(private_key)
        err('Missing property rackspace.private_key') unless private_key
        @ssh_key = File.expand_path(private_key)
        err("Private key '#{private_key}' does not exist") unless File.exists?(@ssh_key)
      end

      ##
      # Set ups the server public key
      #
      # @param [String] public_key Public key file
      # @return [void]
      def setup_public_ssh_key(public_key)
        err('Missing property rackspace.public_key') unless public_key
        ssh_key_file = File.expand_path(public_key)
        err("Public key '#{public_key}' does not exist") unless File.exists?(ssh_key_file)

        resources = Config.resources
        resources['cloud_properties'] ||= {}
        resources['cloud_properties']['public_key'] = File.read(ssh_key_file)
      end
    end
  end
end