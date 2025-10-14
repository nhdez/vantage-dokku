# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  layout :resolve_layout

  private

  def resolve_layout
    case action_name
    when "new", "create"
      "devise"
    else
      "application"
    end
  end
end
