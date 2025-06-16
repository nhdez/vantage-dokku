require 'net/ssh'

class ExecuteCommandJob < ApplicationJob
  queue_as :default

  def perform(deployment, user, command)
    @deployment = deployment
    @user = user
    @command = command
    @server = deployment.server
    @connection_details = @server.connection_details
    
    Rails.logger.info "[ExecuteCommandJob] Starting command execution: '#{@command}' for deployment #{@deployment.uuid}"
    
    begin
      # Broadcast that command execution is starting
      broadcast_message("Starting command execution...")
      
      Net::SSH.start(
        @connection_details[:host],
        @connection_details[:username],
        ssh_options
      ) do |ssh|
        execute_dokku_command(ssh)
      end
      
    rescue Net::SSH::AuthenticationFailed => e
      error_msg = "Authentication failed. Please check your SSH key or password."
      Rails.logger.error "[ExecuteCommandJob] #{error_msg}"
      broadcast_error(error_msg)
    rescue Net::SSH::ConnectionTimeout => e
      error_msg = "Connection timeout. Server may be unreachable."
      Rails.logger.error "[ExecuteCommandJob] #{error_msg}"
      broadcast_error(error_msg)
    rescue StandardError => e
      Rails.logger.error "[ExecuteCommandJob] Command execution failed: #{e.message}"
      broadcast_error(e.message)
    end
  end

  private

  def ssh_options
    options = {
      port: @connection_details[:port],
      timeout: 30,
      verify_host_key: :never,
      non_interactive: true
    }
    
    # Try SSH key first if available
    if @connection_details[:keys].present?
      options[:keys] = @connection_details[:keys]
      options[:auth_methods] = ['publickey']
      
      # Add password as fallback if available
      if @connection_details[:password].present?
        options[:password] = @connection_details[:password]
        options[:auth_methods] << 'password'
      end
    elsif @connection_details[:password].present?
      # Only password authentication
      options[:password] = @connection_details[:password]
      options[:auth_methods] = ['password']
    else
      raise StandardError, "No authentication method available"
    end
    
    options
  end

  def execute_dokku_command(ssh)
    app_name = @deployment.dokku_app_name
    
    # Prepare the command with proper formatting
    prepared_command = prepare_command(@command)
    full_command = "sudo dokku run #{app_name} #{prepared_command}"
    
    Rails.logger.info "[ExecuteCommandJob] Executing: #{full_command}"
    broadcast_message("Executing: #{full_command}")
    
    exit_code = 0
    output_buffer = ""
    
    # Execute the command with real-time output streaming
    ssh.exec!(full_command) do |channel, stream, data|
      output_buffer += data
      
      # Split output into lines and broadcast each line
      data.split("\n").each do |line|
        next if line.strip.empty?
        broadcast_output(line)
      end
      
      # Capture exit status
      channel.on_request("exit-status") do |ch, data|
        exit_code = data.read_long
      end
    end
    
    Rails.logger.info "[ExecuteCommandJob] Command completed with exit code: #{exit_code}"
    broadcast_completion(exit_code)
    
  rescue Net::SSH::Exception => e
    Rails.logger.error "[ExecuteCommandJob] SSH error during command execution: #{e.message}"
    broadcast_error("SSH error: #{e.message}")
  rescue StandardError => e
    Rails.logger.error "[ExecuteCommandJob] Unexpected error during command execution: #{e.message}"
    broadcast_error("Unexpected error: #{e.message}")
  end

  def prepare_command(command)
    # Handle different types of commands appropriately
    cmd = command.strip
    
    # Rails commands need bundle exec prefix
    rails_commands = [
      'rails', 'rake', 'rspec', 'rubocop', 'brakeman',
      'sidekiq', 'whenever', 'cap', 'capistrano'
    ]
    
    # Check if this is a Rails/Ruby command that needs bundle exec
    first_word = cmd.split(' ').first
    
    if rails_commands.include?(first_word)
      # Add bundle exec prefix for Rails commands
      return "bundle exec #{cmd}"
    elsif cmd.start_with?('bundle exec')
      # Already has bundle exec, use as-is
      return cmd
    else
      # System commands (ps, ls, cat, etc.) - use as-is
      return cmd
    end
  end

  def broadcast_message(message)
    ActionCable.server.broadcast("command_execution_#{@deployment.uuid}", {
      type: 'output',
      message: message,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_output(output)
    ActionCable.server.broadcast("command_execution_#{@deployment.uuid}", {
      type: 'output',
      message: output,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_completion(exit_code)
    ActionCable.server.broadcast("command_execution_#{@deployment.uuid}", {
      type: 'completed',
      exit_code: exit_code,
      command: @command,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_error(error_message)
    ActionCable.server.broadcast("command_execution_#{@deployment.uuid}", {
      type: 'error',
      message: error_message,
      command: @command,
      timestamp: Time.current.iso8601
    })
  end
end