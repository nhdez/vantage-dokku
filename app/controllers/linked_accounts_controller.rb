class LinkedAccountsController < ApplicationController
  include ActivityTrackable
  
  before_action :set_linked_account, only: [:show, :edit, :update, :destroy, :test_connection]
  before_action :authorize_linked_account, only: [:show, :edit, :update, :destroy, :test_connection]
  
  def index
    @linked_accounts = current_user.linked_accounts.includes(:user).order(:provider, :created_at)
    log_activity('linked_accounts_viewed', details: "Viewed linked accounts list (#{@linked_accounts.count} accounts)")
  end

  def show
    log_activity('linked_account_viewed', details: "Viewed linked account: #{@linked_account.display_name}")
  end

  def new
    @linked_account = current_user.linked_accounts.build
    @available_providers = LinkedAccount::SUPPORTED_PROVIDERS
    authorize @linked_account
  end

  def create
    @linked_account = current_user.linked_accounts.build(linked_account_params)
    @available_providers = LinkedAccount::SUPPORTED_PROVIDERS
    authorize @linked_account
    
    if @linked_account.save
      # Test the connection immediately after creation
      result = @linked_account.test_connection
      
      if result[:success]
        # Update account info from the API
        update_account_info_from_api(result)
        @linked_account.update_last_connected!
        
        log_activity('linked_account_created', details: "Created and verified linked account: #{@linked_account.display_name}")
        toast_success("#{@linked_account.provider.capitalize} account linked successfully!", title: "Account Linked")
        redirect_to @linked_account
      else
        log_activity('linked_account_creation_failed', details: "Failed to verify linked account: #{@linked_account.provider} - #{result[:error]}")
        toast_error("Account created but connection failed: #{result[:error]}", title: "Connection Error")
        redirect_to @linked_account
      end
    else
      toast_error("Failed to link account. Please check the form for errors.", title: "Link Failed")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Account set by before_action
  end

  def update
    if @linked_account.update(linked_account_params)
      log_activity('linked_account_updated', details: "Updated linked account: #{@linked_account.display_name}")
      toast_success("#{@linked_account.provider.capitalize} account updated successfully!", title: "Account Updated")
      redirect_to @linked_account
    else
      toast_error("Failed to update account. Please check the form for errors.", title: "Update Failed")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    provider = @linked_account.provider
    display_name = @linked_account.display_name
    @linked_account.destroy
    log_activity('linked_account_deleted', details: "Deleted linked account: #{display_name}")
    toast_success("#{provider.capitalize} account unlinked successfully!", title: "Account Unlinked")
    redirect_to linked_accounts_path
  end

  def test_connection
    begin
      result = @linked_account.test_connection
      
      if result[:success]
        # Update account info from the API
        update_account_info_from_api(result)
        @linked_account.update_last_connected!
        
        log_activity('linked_account_tested', details: "Successfully tested connection for: #{@linked_account.display_name}")
        render json: {
          success: true,
          message: "Connection successful! Account information updated.",
          account_info: result[:account_info],
          connection_status: @linked_account.reload.connection_status
        }
      else
        log_activity('linked_account_test_failed', details: "Connection test failed for: #{@linked_account.display_name} - #{result[:error]}")
        render json: {
          success: false,
          message: result[:error],
          connection_status: @linked_account.reload.connection_status
        }
      end
    rescue StandardError => e
      Rails.logger.error "Connection test failed: #{e.message}"
      render json: {
        success: false,
        message: "An unexpected error occurred: #{e.message}",
        connection_status: 'error'
      }
    end
  end

  private

  def set_linked_account
    @linked_account = current_user.linked_accounts.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    toast_error("Linked account not found.", title: "Not Found")
    redirect_to linked_accounts_path
  end
  
  def authorize_linked_account
    authorize @linked_account
  end

  def linked_account_params
    params.require(:linked_account).permit(:provider, :access_token, :account_username, :account_email, :active)
  end
  
  def update_account_info_from_api(result)
    return unless result[:account_info]
    
    info = result[:account_info]
    updates = {}
    
    case @linked_account.provider
    when 'github'
      updates[:account_username] = info[:login] if info[:login]
      updates[:account_email] = info[:email] if info[:email]
      
      # Store additional metadata
      metadata = @linked_account.metadata || {}
      metadata.merge!({
        'name' => info[:name],
        'company' => info[:company],
        'blog' => info[:blog],
        'location' => info[:location],
        'bio' => info[:bio],
        'public_repos' => info[:public_repos],
        'public_gists' => info[:public_gists],
        'followers' => info[:followers],
        'following' => info[:following],
        'avatar_url' => info[:avatar_url],
        'html_url' => info[:html_url]
      }.compact)
      updates[:metadata] = metadata
    end
    
    @linked_account.update!(updates) if updates.any?
  end
end
