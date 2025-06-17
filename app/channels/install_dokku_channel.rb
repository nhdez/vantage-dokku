class InstallDokkuChannel < ApplicationCable::Channel
  def subscribed
    server_uuid = params[:server_uuid]
    stream_from "install_dokku_#{server_uuid}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end