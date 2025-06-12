module ToastHelper
  def render_flash_toasts
    content = []
    
    flash.each do |type, message|
      next if message.blank?
      
      # Handle arrays of messages
      messages = message.is_a?(Array) ? message : [message]
      
      messages.each do |msg|
        content << content_tag(:div, '',
          data: {
            controller: 'toast',
            toast_type_value: normalize_flash_type(type),
            toast_message_value: msg,
            toast_title_value: flash_title(type),
            toast_autohide_value: true,
            toast_delay_value: flash_delay(type)
          },
          class: 'toast-trigger d-none'
        )
      end
    end
    
    safe_join(content)
  end

  def toast_container
    content_tag(:div, '', 
      id: 'toast-container',
      class: 'toast-container position-fixed top-0 end-0 p-3',
      style: 'z-index: 9999;',
      data: { controller: 'toast', toast_target: 'container' }
    )
  end

  # Create a toast programmatically 
  def create_toast(type, message, title: nil, autohide: true, delay: 5000)
    content_tag(:div, '',
      data: {
        controller: 'toast',
        toast_type_value: type.to_s,
        toast_message_value: message,
        toast_title_value: title,
        toast_autohide_value: autohide,
        toast_delay_value: delay
      },
      class: 'toast-trigger d-none'
    )
  end

  private

  def normalize_flash_type(type)
    case type.to_s
    when 'notice'
      'success'
    when 'alert'
      'error' 
    when 'error'
      'error'
    when 'warning'
      'warning'
    when 'info'
      'info'
    when 'success'
      'success'
    else
      'info'
    end
  end

  def flash_title(type)
    case normalize_flash_type(type)
    when 'success'
      'Success!'
    when 'error'
      'Error!'
    when 'warning'
      'Warning!'
    when 'info'
      'Information'
    else
      'Notification'
    end
  end

  def flash_delay(type)
    case normalize_flash_type(type)
    when 'error'
      8000  # Errors stay longer
    when 'warning'
      6000  # Warnings stay a bit longer
    else
      5000  # Default
    end
  end
end