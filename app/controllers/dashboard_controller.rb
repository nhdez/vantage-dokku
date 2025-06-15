class DashboardController < ApplicationController
  def index
  end

  def settings
    # Settings will be handled by Devise user registration controller
    redirect_to edit_user_registration_path
  end

  private

end
