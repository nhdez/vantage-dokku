class UpdateDomainsChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]
    stream_from "update_domains_#{deployment_uuid}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end