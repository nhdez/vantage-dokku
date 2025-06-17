class UpdateServerChannel < ApplicationCable::Channel
  def subscribed
    server_uuid = params[:server_uuid]
    stream_from "update_server_#{server_uuid}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end