class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index, :maintenance ]

  def index
    # Redirect authenticated users to dashboard
    redirect_to dashboard_path if user_signed_in?
  end

  def maintenance
    # Renders app/views/home/maintenance.html.erb
  end
end
