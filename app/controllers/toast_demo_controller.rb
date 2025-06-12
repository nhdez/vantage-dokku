class ToastDemoController < ApplicationController
  def index
    # This is just for demo purposes
  end

  def show_success
    toast_success("This is a beautiful success message! Your action completed perfectly.", title: "Awesome!")
    redirect_to toast_demo_index_path
  end

  def show_error
    toast_error("Something went wrong! Please check your input and try again.", title: "Oops!")
    redirect_to toast_demo_index_path
  end

  def show_warning
    toast_warning("This is a warning message. Please be careful with this action.", title: "Heads Up!")
    redirect_to toast_demo_index_path
  end

  def show_info
    toast_info("Here's some useful information about this feature. Pretty cool, right?", title: "Did You Know?")
    redirect_to toast_demo_index_path
  end

  def show_login
    toast_login_success("John Doe")
    redirect_to toast_demo_index_path
  end

  def show_role_assigned
    toast_role_assigned("admin", "Jane Smith")
    redirect_to toast_demo_index_path
  end

  def show_settings_updated
    toast_settings_updated
    redirect_to toast_demo_index_path
  end

  def show_multiple
    toast_success("First success message!")
    toast_warning("Then a warning!")
    toast_info("And some info!")
    redirect_to toast_demo_index_path
  end
end
