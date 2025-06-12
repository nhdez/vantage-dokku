module ThemeHelper
  def current_user_theme
    return 'auto' unless user_signed_in?
    current_user.effective_theme
  end

  def theme_data_attribute
    current_user_theme
  end

  def theme_toggle_button(classes: 'theme-toggle', show_label: true)
    content_tag(:div, 
      class: "d-flex align-items-center #{show_label ? 'gap-2' : ''}",
      data: { 
        controller: 'theme',
        theme_current_value: current_user_theme,
        theme_endpoint_value: user_signed_in? ? update_theme_path : nil
      }
    ) do
      toggle_html = content_tag(:button,
        content_tag(:div, theme_icon(current_user_theme), class: 'toggle-slider'),
        class: "#{classes} #{current_user_theme == 'dark' ? 'dark' : ''}",
        data: { action: 'click->theme#toggle', theme_target: 'toggle' },
        title: theme_tooltip(current_user_theme),
        type: 'button'
      )
      
      if show_label
        label_html = content_tag(:span, 'Theme', class: 'text-muted small')
        safe_join([toggle_html, label_html])
      else
        toggle_html
      end
    end
  end

  def theme_selection_dropdown(classes: 'dropdown')
    content_tag(:div, class: classes) do
      button = content_tag(:button,
        safe_join([
          content_tag(:i, '', class: 'fas fa-palette me-2'),
          'Theme ',
          content_tag(:i, '', class: 'fas fa-chevron-down ms-1')
        ]),
        class: 'btn btn-outline-secondary dropdown-toggle',
        type: 'button',
        data: { 
          'mdb-toggle': 'dropdown',
          'mdb-auto-close': 'true'
        }
      )
      
      menu_items = [
        { theme: 'light', icon: 'fa-sun', label: 'Light Mode', desc: 'Always use light theme' },
        { theme: 'dark', icon: 'fa-moon', label: 'Dark Mode', desc: 'Always use dark theme' },
        { theme: 'auto', icon: 'fa-adjust', label: 'Auto Mode', desc: 'Match system preference' }
      ]
      
      menu = content_tag(:ul, class: 'dropdown-menu') do
        menu_items.map do |item|
          content_tag(:li) do
            link_to('#',
              class: "dropdown-item #{'active' if current_user_theme == item[:theme]}",
              data: { action: 'click->theme#setTheme', theme: item[:theme] }
            ) do
              safe_join([
                content_tag(:i, '', class: "fas #{item[:icon]} me-3 text-#{theme_color(item[:theme])}"),
                content_tag(:div, class: 'd-flex flex-column') do
                  safe_join([
                    content_tag(:span, item[:label], class: 'fw-bold'),
                    content_tag(:small, item[:desc], class: 'text-muted')
                  ])
                end
              ])
            end
          end
        end.join.html_safe
      end
      
      safe_join([button, menu])
    end
  end

  def body_theme_classes
    theme = current_user_theme
    effective = theme == 'auto' ? 'auto' : theme
    "theme-#{effective}"
  end

  def theme_meta_tags
    effective_theme = current_user_theme == 'auto' ? 'auto' : current_user_theme
    
    content_for :head do
      safe_join([
        tag(:meta, name: 'theme-color', content: theme_color_hex(effective_theme)),
        tag(:meta, name: 'color-scheme', content: effective_theme == 'dark' ? 'dark' : 'light'),
        tag(:meta, name: 'msapplication-navbutton-color', content: theme_color_hex(effective_theme))
      ])
    end
  end

  private

  def theme_icon(theme)
    case theme
    when 'light'
      '☀️'
    when 'dark' 
      '🌙'
    when 'auto'
      '🔄'
    else
      '☀️'
    end
  end

  def theme_tooltip(theme)
    case theme
    when 'light'
      'Switch to Dark Mode'
    when 'dark'
      'Switch to Auto Mode'  
    when 'auto'
      'Switch to Light Mode'
    else
      'Change Theme'
    end
  end

  def theme_color(theme)
    case theme
    when 'light'
      'warning'
    when 'dark'
      'primary'
    when 'auto'
      'info'
    else
      'secondary'
    end
  end

  def theme_color_hex(theme)
    case theme
    when 'dark'
      '#0d1117'
    else
      '#ffffff'
    end
  end
end