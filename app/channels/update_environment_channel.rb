class UpdateEnvironmentChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]
    stream_from "update_environment_#{deployment_uuid}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end