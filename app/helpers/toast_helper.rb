module ToastHelper
  def render_flash_toasts
    content = []
    seen_messages = {}

    # Define flash type priority (higher number = higher priority)
    # When duplicate messages exist, show the one with highest priority
    priority_map = {
      "error" => 5,
      "alert" => 5,  # Same as error
      "warning" => 4,
      "success" => 3,
      "notice" => 2,  # Lower priority than success
      "info" => 1
    }

    # First pass: collect all messages and track highest priority for each
    flash.each do |type, message|
      next if type.to_s.end_with?("_title")  # title overrides are not messages
      next if message.blank?

      # Handle arrays of messages
      messages = message.is_a?(Array) ? message : [ message ]

      messages.each do |msg|
        normalized_type = normalize_flash_type(type)
        current_priority = priority_map[normalized_type] || 0

        # Track this message and its priority
        if seen_messages[msg]
          # If we've seen this message before, keep the higher priority type
          if current_priority > seen_messages[msg][:priority]
            seen_messages[msg] = {
              type: type,
              normalized_type: normalized_type,
              priority: current_priority
            }
          end
        else
          # First time seeing this message
          seen_messages[msg] = {
            type: type,
            normalized_type: normalized_type,
            priority: current_priority
          }
        end
      end
    end

    # Second pass: render toasts for unique messages only
    seen_messages.each do |msg, info|
      content << content_tag(:div, "",
        data: {
          controller: "toast",
          toast_type_value: info[:normalized_type],
          toast_message_value: msg,
          toast_title_value: flash_title(info[:type]),
          toast_autohide_value: true,
          toast_delay_value: flash_delay(info[:type])
        },
        class: "toast-trigger d-none"
      )
    end

    safe_join(content)
  end

  def toast_container
    content_tag(:div, "",
      id: "toast-container",
      class: "toast-container position-fixed top-0 end-0 p-3",
      style: "z-index: 9999;",
      data: { controller: "toast", toast_target: "container" }
    )
  end

  # Create a toast programmatically
  def create_toast(type, message, title: nil, autohide: true, delay: 5000)
    content_tag(:div, "",
      data: {
        controller: "toast",
        toast_type_value: type.to_s,
        toast_message_value: message,
        toast_title_value: title,
        toast_autohide_value: autohide,
        toast_delay_value: delay
      },
      class: "toast-trigger d-none"
    )
  end

  private

  def normalize_flash_type(type)
    case type.to_s
    when "notice"
      "success"
    when "alert"
      "error"
    when "error"
      "error"
    when "warning"
      "warning"
    when "info"
      "info"
    when "success"
      "success"
    else
      "info"
    end
  end

  def flash_title(type)
    flash["#{type}_title"].presence || case normalize_flash_type(type)
    when "success" then "Success!"
    when "error"   then "Error!"
    when "warning" then "Warning!"
    when "info"    then "Information"
    else                "Notification"
    end
  end

  def flash_delay(type)
    case normalize_flash_type(type)
    when "error"
      8000  # Errors stay longer
    when "warning"
      6000  # Warnings stay a bit longer
    else
      5000  # Default
    end
  end
end
