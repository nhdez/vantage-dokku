class Deployments::BaseController < ApplicationController
  include ActivityTrackable

  before_action :set_deployment
  before_action :authorize_deployment

  private

  def set_deployment
    @deployment = current_user.deployments.find_by!(uuid: params[:uuid])
  rescue ActiveRecord::RecordNotFound
    toast_error("Deployment not found.", title: "Not Found")
    redirect_to deployments_path
  end

  def authorize_deployment
    authorize @deployment
  end
end
