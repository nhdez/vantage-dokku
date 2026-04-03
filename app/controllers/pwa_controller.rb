class PwaController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :service_worker, :manifest ]

  def service_worker
    render file: "pwa/service-worker", layout: false, content_type: "application/javascript"
  end

  def manifest
    render file: "pwa/manifest", layout: false, content_type: "application/json"
  end
end
