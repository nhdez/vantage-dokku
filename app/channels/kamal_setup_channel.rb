class KamalSetupChannel < ApplicationCable::Channel
  def subscribed
    deployment = current_user.deployments.find_by(uuid: params[:deployment_uuid])
    return reject unless deployment&.kamal?

    stream_from "kamal_setup_#{deployment.uuid}"
    Rails.logger.info "KamalSetupChannel: subscribed to setup for #{deployment.uuid}"
  end

  def unsubscribed
    Rails.logger.info "KamalSetupChannel: unsubscribed"
  end
end
