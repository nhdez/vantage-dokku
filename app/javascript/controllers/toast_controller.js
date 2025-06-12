import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]
  static values = { 
    type: String, 
    message: String, 
    title: String,
    autohide: { type: Boolean, default: true },
    delay: { type: Number, default: 5000 }
  }

  connect() {
    if (this.hasMessageValue) {
      this.showToast(this.typeValue, this.messageValue, this.titleValue)
    }
  }

  showToast(type, message, title = null) {
    const toastId = `toast-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
    const iconMap = {
      success: 'fas fa-check-circle',
      error: 'fas fa-exclamation-circle', 
      warning: 'fas fa-exclamation-triangle',
      info: 'fas fa-info-circle',
      notice: 'fas fa-check-circle'
    }

    const colorMap = {
      success: 'success',
      error: 'danger',
      warning: 'warning', 
      info: 'info',
      notice: 'success'
    }

    const defaultTitles = {
      success: 'Success!',
      error: 'Error!',
      warning: 'Warning!',
      info: 'Information',
      notice: 'Success!'
    }

    const toastType = type === 'alert' ? 'error' : type
    const toastTitle = title || defaultTitles[toastType] || 'Notification'
    const toastColor = colorMap[toastType] || 'info'
    const toastIcon = iconMap[toastType] || 'fas fa-info-circle'

    const toastHTML = `
      <div id="${toastId}" class="toast fade show" role="alert" aria-live="assertive" aria-atomic="true" 
           data-mdb-autohide="${this.autohideValue}" data-mdb-delay="${this.delayValue}">
        <div class="toast-header bg-${toastColor} text-white">
          <i class="${toastIcon} me-2"></i>
          <strong class="me-auto">${toastTitle}</strong>
          <small class="text-white-50">${this.getTimeString()}</small>
          <button type="button" class="btn-close btn-close-white ms-2" data-mdb-dismiss="toast" aria-label="Close"></button>
        </div>
        <div class="toast-body bg-${toastColor} bg-opacity-10 border-${toastColor} border-start border-4">
          <div class="d-flex align-items-start">
            <i class="${toastIcon} text-${toastColor} me-3 mt-1"></i>
            <div class="flex-grow-1">
              ${message}
            </div>
          </div>
        </div>
      </div>
    `

    // Create container if it doesn't exist
    let container = this.hasContainerTarget ? this.containerTarget : document.getElementById('toast-container')
    if (!container) {
      container = document.createElement('div')
      container.id = 'toast-container'
      container.className = 'toast-container position-fixed top-0 end-0 p-3'
      container.style.zIndex = '9999'
      document.body.appendChild(container)
    }

    // Add toast to container
    container.insertAdjacentHTML('afterbegin', toastHTML)
    
    // Initialize MDB toast
    const toastElement = document.getElementById(toastId)
    const toast = new mdb.Toast(toastElement)
    
    // Auto-remove from DOM after hiding
    toastElement.addEventListener('hidden.mdb.toast', () => {
      toastElement.remove()
    })

    // Add entrance animation
    toastElement.style.transform = 'translateX(100%)'
    toastElement.style.transition = 'transform 0.3s ease-in-out'
    
    setTimeout(() => {
      toastElement.style.transform = 'translateX(0)'
    }, 10)

    return toast
  }

  // Static method to show toasts from anywhere
  static show(type, message, title = null, options = {}) {
    const event = new CustomEvent('toast:show', {
      detail: { type, message, title, ...options }
    })
    document.dispatchEvent(event)
  }

  getTimeString() {
    return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  }

  // Handle custom toast events
  handleToastEvent(event) {
    const { type, message, title, ...options } = event.detail
    this.showToast(type, message, title)
  }
}

// Global toast methods
window.Toast = {
  success: (message, title = null) => {
    const controller = new ToastController()
    controller.showToast('success', message, title)
  },
  error: (message, title = null) => {
    const controller = new ToastController()
    controller.showToast('error', message, title)
  },
  warning: (message, title = null) => {
    const controller = new ToastController()
    controller.showToast('warning', message, title)
  },
  info: (message, title = null) => {
    const controller = new ToastController()
    controller.showToast('info', message, title)
  },
  notice: (message, title = null) => {
    const controller = new ToastController()
    controller.showToast('notice', message, title)
  }
}

// Listen for custom toast events
document.addEventListener('toast:show', (event) => {
  const controller = new ToastController()
  controller.handleToastEvent(event)
})