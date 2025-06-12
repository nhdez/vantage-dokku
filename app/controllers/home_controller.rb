class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]
  
  def index
    # Redirect authenticated users to dashboard
    redirect_to dashboard_path if user_signed_in?
  end
end
