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
      Rails.logger.info "[SSH Key Generation] Starting SSH key generation for Vantage Dokku"
      
      # Check if SSH key already exists
      if ENV['DOKKU_SSH_KEY_PATH'].present?
        render json: {
          success: false,
          message: "SSH key already configured at #{ENV['DOKKU_SSH_KEY_PATH']}"
        }
        return
      end

      # Generate SSH key pair for Vantage Dokku to use when connecting to servers
      # This key will be used by the Rails application to connect to Dokku servers
      
      # Use a dedicated directory for Vantage SSH keys
      ssh_dir = '/tmp/vantage_dokku_keys'
      
      # Ensure directory exists
      unless Dir.exist?(ssh_dir)
        Dir.mkdir(ssh_dir, 0700)
      end

      # Set paths for the key files
      private_key_path = File.join(ssh_dir, 'vantage_dokku_key')
      public_key_path = "#{private_key_path}.pub"

      Rails.logger.info "[SSH Key Generation] Generating key pair at #{private_key_path}"

      # Generate the SSH key using system command
      command = "ssh-keygen -t ed25519 -f #{private_key_path} -N '' -C 'vantage-dokku-client@#{Socket.gethostname}'"
      
      if system(command)
        # Read the generated public key
        if File.exist?(public_key_path)
          public_key_content = File.read(public_key_path).strip

          # Set file permissions
          File.chmod(0600, private_key_path) if File.exist?(private_key_path)
          File.chmod(0644, public_key_path)

          # Set environment variables for the current process
          ENV['DOKKU_SSH_KEY_PATH'] = private_key_path
          ENV['DOKKU_SSH_PUBLIC_KEY'] = public_key_content

          Rails.logger.info "[SSH Key Generation] Generated SSH key pair successfully"
          Rails.logger.info "[SSH Key Generation] Private key: #{private_key_path}"
          Rails.logger.info "[SSH Key Generation] Public key: #{public_key_content[0..50]}..."

          render json: {
            success: true,
            message: "SSH key generated successfully for Vantage Dokku client",
            private_key_path: private_key_path,
            public_key_path: public_key_path,
            public_key: public_key_content,
            note: "This key will be used by Vantage to connect to your Dokku servers. You may need to add the public key to your servers' authorized_keys."
          }
        else
          render json: {
            success: false,
            message: "SSH key generation completed but public key file not found"
          }
        end
      else
        # Check if ssh-keygen is available
        unless system('which ssh-keygen > /dev/null 2>&1')
          render json: {
            success: false,
            message: "ssh-keygen command not found. Please install OpenSSH client tools."
          }
          return
        end
        
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
