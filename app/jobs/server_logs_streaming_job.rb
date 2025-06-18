require 'net/ssh'

class ServerLogsStreamingJob < ApplicationJob
  queue_as :default

  def perform(deployment, user)
    @deployment = deployment
    @user = user
    @server = deployment.server
    @connection_details = @server.connection_details
    @streaming = true
    
    Rails.logger.info "[ServerLogsStreamingJob] Starting server logs streaming for deployment #{@deployment.uuid}"
    
    begin
      # Broadcast that streaming is starting
      broadcast_message("Starting server logs streaming...")
      
      Net::SSH.start(
        @connection_details[:host],
        @connection_details[:username],
        ssh_options
      ) do |ssh|
        stream_dokku_logs(ssh)
      end
      
    rescue Net::SSH::AuthenticationFailed => e
      error_msg = "Authentication failed. Please check your SSH key or password."
      Rails.logger.error "[ServerLogsStreamingJob] #{error_msg}"
      broadcast_error(error_msg)
    rescue Net::SSH::ConnectionTimeout => e
      error_msg = "Connection timeout. Server may be unreachable."
      Rails.logger.error "[ServerLogsStreamingJob] #{error_msg}"
      broadcast_error(error_msg)
    rescue StandardError => e
      Rails.logger.error "[ServerLogsStreamingJob] Server logs streaming failed: #{e.message}"
      broadcast_error(e.message)
    ensure
      Rails.logger.info "[ServerLogsStreamingJob] Server logs streaming ended for deployment #{@deployment.uuid}"
      broadcast_message("Server logs streaming ended.")
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

  def stream_dokku_logs(ssh)
    app_name = @deployment.dokku_app_name
    command = "sudo dokku logs #{app_name} -t"
    
    Rails.logger.info "[ServerLogsStreamingJob] Starting log streaming with command: #{command}"
    broadcast_message("Executing: #{command}")
    broadcast_message("─" * 80)
    
    # Set up a channel for the streaming command
    channel = ssh.open_channel do |ch|
      ch.exec command do |ch, success|
        unless success
          broadcast_error("Failed to execute dokku logs command")
          return
        end
        
        # Handle stdout (log output)
        ch.on_data do |ch, data|
          # Check if we should stop streaming
          unless @streaming
            Rails.logger.info "[ServerLogsStreamingJob] Stopping log streaming as requested"
            ch.close
            return
          end
          
          # Split data into lines and broadcast each line
          data.split("\n").each do |line|
            next if line.strip.empty?
            broadcast_log_output(line.strip)
          end
        end
        
        # Handle stderr (error output)
        ch.on_extended_data do |ch, type, data|
          if type == 1 # stderr
            data.split("\n").each do |line|
              next if line.strip.empty?
              broadcast_log_output("STDERR: #{line.strip}")
            end
          end
        end
        
        # Handle channel close
        ch.on_close do |ch|
          Rails.logger.info "[ServerLogsStreamingJob] SSH channel closed"
        end
      end
    end
    
    # Set up a listener for stop streaming signals
    setup_stop_listener
    
    # Keep the connection alive and process the stream
    ssh.loop do
      @streaming && channel.active?
    end
    
  rescue Net::SSH::Exception => e
    Rails.logger.error "[ServerLogsStreamingJob] SSH error during log streaming: #{e.message}"
    broadcast_error("SSH error: #{e.message}")
  rescue StandardError => e
    Rails.logger.error "[ServerLogsStreamingJob] Unexpected error during log streaming: #{e.message}"
    broadcast_error("Unexpected error: #{e.message}")
  end

  def setup_stop_listener
    # Subscribe to the stop streaming channel to listen for stop signals
    # This is a simplified approach - in a more robust implementation,
    # you might use Redis or a database flag to signal stopping
    
    # For now, we'll rely on a timeout mechanism
    @start_time = Time.current
    @max_streaming_duration = 30.minutes # Stop after 30 minutes max
  end

  def check_should_stop_streaming
    # Check various conditions to stop streaming
    
    # Stop if we've been streaming too long
    if Time.current - @start_time > @max_streaming_duration
      Rails.logger.info "[ServerLogsStreamingJob] Stopping due to max duration reached"
      @streaming = false
      return true
    end
    
    # Check for stop signal (this would be more sophisticated in production)
    # For now, we'll just continue streaming until the connection is closed
    
    false
  end

  def broadcast_message(message)
    ActionCable.server.broadcast("server_logs_#{@deployment.uuid}", {
      type: 'log_message',
      message: message,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_log_output(output)
    # Check if we should stop before broadcasting
    if check_should_stop_streaming
      return
    end
    
    ActionCable.server.broadcast("server_logs_#{@deployment.uuid}", {
      type: 'log_message',
      message: output,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_error(error_message)
    ActionCable.server.broadcast("server_logs_#{@deployment.uuid}", {
      type: 'error',
      message: error_message,
      timestamp: Time.current.iso8601
    })
  end
end