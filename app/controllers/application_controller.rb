require 'socket'

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  include Pundit::Authorization
  include Pagy::Backend
  include Toastable
  
  # Require authentication for most actions
  before_action :authenticate_user!
  
  # Configure Devise permitted parameters
  before_action :configure_permitted_parameters, if: :devise_controller?
  
  # Handle Pundit authorization errors
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def generate_ssh_key
    begin
      Rails.logger.info "[SSH Key Generation] Starting SSH key generation"
      Rails.logger.info "[SSH Key Generation] Current user: #{ENV['USER']}"
      Rails.logger.info "[SSH Key Generation] Current HOME: #{ENV['HOME']}"
      
      # Check if SSH key already exists
      if ENV['DOKKU_SSH_KEY_PATH'].present? && File.exist?(ENV['DOKKU_SSH_KEY_PATH'])
        render json: {
          success: false,
          message: "SSH key already exists at #{ENV['DOKKU_SSH_KEY_PATH']}"
        }
        return
      end

      # Determine the appropriate SSH directory
      # Try multiple approaches to find a writable directory
      possible_homes = [
        ENV['HOME'],
        (Dir.home rescue nil),
        ENV['USERPROFILE'], # Windows
        "/home/#{ENV['USER']}",
        "/Users/#{ENV['USER']}", # macOS
        Dir.pwd # Current working directory as last resort
      ].compact
      
      ssh_dir = nil
      
      # Try each possible home directory
      possible_homes.each do |home_dir|
        next unless home_dir && Dir.exist?(home_dir)
        
        test_ssh_dir = File.join(home_dir, '.ssh')
        Rails.logger.info "[SSH Key Generation] Testing SSH directory: #{test_ssh_dir}"
        
        begin
          # Test if we can create the directory or if it's writable
          if Dir.exist?(test_ssh_dir)
            # Check if directory is writable
            if File.writable?(test_ssh_dir)
              ssh_dir = test_ssh_dir
              Rails.logger.info "[SSH Key Generation] Using existing writable SSH directory: #{ssh_dir}"
              break
            end
          else
            # Try to create the directory
            Dir.mkdir(test_ssh_dir, 0700)
            ssh_dir = test_ssh_dir
            Rails.logger.info "[SSH Key Generation] Created new SSH directory: #{ssh_dir}"
            break
          end
        rescue => e
          Rails.logger.warn "[SSH Key Generation] Cannot use #{test_ssh_dir}: #{e.message}"
          next
        end
      end
      
      # If no home directory worked, use /tmp as fallback
      if ssh_dir.nil?
        ssh_dir = '/tmp/vantage_ssh'
        Rails.logger.info "[SSH Key Generation] Using fallback directory: #{ssh_dir}"
        
        unless Dir.exist?(ssh_dir)
          Dir.mkdir(ssh_dir, 0700)
        end
      end

      # Set paths for the key files
      private_key_path = File.join(ssh_dir, 'id_ed25519')
      public_key_path = "#{private_key_path}.pub"

      # Generate the SSH key using system command
      command = "ssh-keygen -t ed25519 -f #{private_key_path} -N '' -C 'vantage-dokku@#{Socket.gethostname}'"
      
      if system(command)
        # Read the generated public key
        if File.exist?(public_key_path)
          public_key_content = File.read(public_key_path).strip

          # Set file permissions
          File.chmod(0600, private_key_path) if File.exist?(private_key_path)
          File.chmod(0644, public_key_path)

          # Set environment variables in a persistent way
          # You might want to update your .env file or use a different method
          # depending on how you manage environment variables
          
          # For now, we'll write to a temporary env file that can be sourced
          env_updates = <<~ENV
            # Vantage Dokku SSH Key Configuration (Generated #{Time.current})
            export DOKKU_SSH_KEY_PATH=#{private_key_path}
            export DOKKU_SSH_PUBLIC_KEY='#{public_key_content}'
          ENV
          
          # Write to a file that can be sourced
          env_file_path = '/tmp/vantage_ssh_env.sh'
          File.write(env_file_path, env_updates)
          
          # Also try to update the current process environment
          ENV['DOKKU_SSH_KEY_PATH'] = private_key_path
          ENV['DOKKU_SSH_PUBLIC_KEY'] = public_key_content

          Rails.logger.info "[SSH Key Generation] Generated new SSH key at #{private_key_path}"
          Rails.logger.info "[SSH Key Generation] Environment file created at #{env_file_path}"

          render json: {
            success: true,
            message: "SSH key generated successfully",
            private_key_path: private_key_path,
            public_key_path: public_key_path,
            public_key: public_key_content,
            env_file: env_file_path
          }
        else
          render json: {
            success: false,
            message: "SSH key generation completed but public key file not found"
          }
        end
      else
        render json: {
          success: false,
          message: "Failed to generate SSH key using ssh-keygen command"
        }
      end

    rescue StandardError => e
      Rails.logger.error "[SSH Key Generation] Failed: #{e.message}"
      render json: {
        success: false,
        message: "SSH key generation failed: #{e.message}"
      }
    end
  end

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back_or_to(root_path)
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :date_of_birth, :profile_picture])
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :date_of_birth, :profile_picture, :theme])
  end
end
