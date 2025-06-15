class SshKeysController < ApplicationController
  include ActivityTrackable
  
  before_action :set_ssh_key, only: [:show, :edit, :update, :destroy]
  before_action :authorize_ssh_key, only: [:show, :edit, :update, :destroy]
  
  def index
    @pagy, @ssh_keys = pagy(current_user.ssh_keys.order(:name), limit: 15)
    log_activity('ssh_keys_list_viewed', details: "Viewed SSH keys list (#{@ssh_keys.count} keys)")
  end

  def show
    log_activity('ssh_key_viewed', details: "Viewed SSH key: #{@ssh_key.display_name}")
  end

  def new
    @ssh_key = current_user.ssh_keys.build
    authorize @ssh_key
  end

  def create
    @ssh_key = current_user.ssh_keys.build(ssh_key_params)
    authorize @ssh_key
    
    if @ssh_key.save
      log_activity('ssh_key_created', details: "Created SSH key: #{@ssh_key.display_name}")
      toast_success("SSH key '#{@ssh_key.name}' created successfully!", title: "SSH Key Created")
      redirect_to @ssh_key
    else
      toast_error("Failed to create SSH key. Please check the form for errors.", title: "Creation Failed")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # SSH key set by before_action
  end

  def update
    if @ssh_key.update(ssh_key_params)
      log_activity('ssh_key_updated', details: "Updated SSH key: #{@ssh_key.display_name}")
      toast_success("SSH key '#{@ssh_key.name}' updated successfully!", title: "SSH Key Updated")
      redirect_to @ssh_key
    else
      toast_error("Failed to update SSH key. Please check the form for errors.", title: "Update Failed")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    key_name = @ssh_key.name
    @ssh_key.destroy
    log_activity('ssh_key_deleted', details: "Deleted SSH key: #{key_name}")
    toast_success("SSH key '#{key_name}' deleted successfully!", title: "SSH Key Deleted")
    redirect_to ssh_keys_path
  end

  private

  def set_ssh_key
    @ssh_key = current_user.ssh_keys.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    toast_error("SSH key not found.", title: "Not Found")
    redirect_to ssh_keys_path
  end
  
  def authorize_ssh_key
    authorize @ssh_key
  end

  def ssh_key_params
    params.require(:ssh_key).permit(:name, :public_key, :expires_at)
  end
end
