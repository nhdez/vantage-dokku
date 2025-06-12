import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "icon"]
  static values = { 
    current: String,
    endpoint: String
  }

  connect() {
    this.initializeTheme()
    this.updateToggleAppearance()
  }

  initializeTheme() {
    const savedTheme = this.currentValue || this.getStoredTheme() || 'auto'
    this.applyTheme(savedTheme)
  }

  toggle() {
    const currentTheme = this.getCurrentTheme()
    let newTheme
    
    switch (currentTheme) {
      case 'light':
        newTheme = 'dark'
        break
      case 'dark':
        newTheme = 'auto'
        break
      case 'auto':
      default:
        newTheme = 'light'
        break
    }
    
    this.setTheme(newTheme)
  }

  setTheme(theme) {
    this.applyTheme(theme)
    this.storeTheme(theme)
    this.updateUserPreference(theme)
    this.updateToggleAppearance()
    this.showThemeToast(theme)
  }

  applyTheme(theme) {
    const root = document.documentElement
    
    if (theme === 'auto') {
      // Use system preference
      const systemPreference = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
      root.setAttribute('data-theme', systemPreference)
    } else {
      root.setAttribute('data-theme', theme)
    }
    
    // Update theme-color meta tag for mobile browsers
    this.updateThemeColorMeta(this.getEffectiveTheme(theme))
  }

  getEffectiveTheme(theme) {
    if (theme === 'auto') {
      return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
    }
    return theme
  }

  getCurrentTheme() {
    return this.getStoredTheme() || 'auto'
  }

  storeTheme(theme) {
    localStorage.setItem('vantage-theme', theme)
    this.currentValue = theme
  }

  getStoredTheme() {
    return localStorage.getItem('vantage-theme')
  }

  updateUserPreference(theme) {
    if (this.endpointValue) {
      fetch(this.endpointValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ user: { theme: theme } })
      }).catch(error => {
        console.log('Theme preference not saved:', error)
      })
    }
  }

  updateToggleAppearance() {
    const theme = this.getCurrentTheme()
    const effectiveTheme = this.getEffectiveTheme(theme)
    
    if (this.hasToggleTarget) {
      const toggle = this.toggleTarget
      toggle.classList.toggle('dark', effectiveTheme === 'dark')
      
      // Update icon
      const slider = toggle.querySelector('.toggle-slider')
      if (slider) {
        let icon = ''
        switch (theme) {
          case 'light':
            icon = '☀️'
            break
          case 'dark':
            icon = '🌙'
            break
          case 'auto':
            icon = '🔄'
            break
        }
        slider.innerHTML = icon
      }
    }

    // Update any theme icons in the UI
    this.iconTargets.forEach(icon => {
      const theme = this.getCurrentTheme()
      const effectiveTheme = this.getEffectiveTheme(theme)
      
      icon.className = 'fas ' + (effectiveTheme === 'dark' ? 'fa-moon' : 'fa-sun')
    })
  }

  updateThemeColorMeta(theme) {
    let metaThemeColor = document.querySelector('meta[name="theme-color"]')
    if (!metaThemeColor) {
      metaThemeColor = document.createElement('meta')
      metaThemeColor.name = 'theme-color'
      document.head.appendChild(metaThemeColor)
    }
    
    metaThemeColor.content = theme === 'dark' ? '#0d1117' : '#ffffff'
  }

  showThemeToast(theme) {
    const messages = {
      light: 'Switched to Light Mode ☀️',
      dark: 'Switched to Dark Mode 🌙',
      auto: 'Using System Theme 🔄'
    }
    
    const titles = {
      light: 'Light Mode',
      dark: 'Dark Mode', 
      auto: 'Auto Mode'
    }

    if (window.Toast) {
      window.Toast.success(messages[theme], titles[theme])
    }
  }

  // Listen for system theme changes when in auto mode
  handleSystemThemeChange() {
    if (this.getCurrentTheme() === 'auto') {
      this.applyTheme('auto')
      this.updateToggleAppearance()
    }
  }

  // Initialize system theme listener
  currentValueChanged() {
    // Set up system theme change listener
    if (window.matchMedia) {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
      mediaQuery.addEventListener('change', () => this.handleSystemThemeChange())
    }
  }

  // Handle form select changes
  handleFormChange(event) {
    const theme = event.target.value
    this.setTheme(theme)
  }
}

// Global theme utilities
window.ThemeManager = {
  setTheme: (theme) => {
    const controller = document.querySelector('[data-controller*="theme"]')?.controller
    if (controller) {
      controller.setTheme(theme)
    }
  },
  
  getCurrentTheme: () => {
    return localStorage.getItem('vantage-theme') || 'auto'
  },
  
  getEffectiveTheme: () => {
    const theme = window.ThemeManager.getCurrentTheme()
    if (theme === 'auto') {
      return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
    }
    return theme
  }
}