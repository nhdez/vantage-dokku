class Servers::BaseController < ApplicationController
  include ActivityTrackable

  before_action :set_server
  before_action :authorize_server

  private

  def set_server
    @server = current_user.servers.find_by!(uuid: params[:uuid])
  rescue ActiveRecord::RecordNotFound
    toast_error("Server not found.", title: "Not Found")
    redirect_to servers_path
  end

  def authorize_server
    authorize @server
  end
end
