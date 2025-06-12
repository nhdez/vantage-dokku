import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "toggle"]
  
  connect() {
    this.updateVisibility()
  }

  toggleSettings() {
    this.updateVisibility()
  }

  updateVisibility() {
    const isEnabled = this.hasToggleTarget && this.toggleTarget.checked
    
    if (this.hasContainerTarget) {
      if (isEnabled) {
        this.containerTarget.style.display = 'block'
        // Add smooth transition
        this.containerTarget.style.opacity = '0'
        setTimeout(() => {
          this.containerTarget.style.transition = 'opacity 0.3s ease-in-out'
          this.containerTarget.style.opacity = '1'
          // Reinitialize MDB components when shown
          this.initializeMDBComponents()
        }, 10)
      } else {
        this.containerTarget.style.transition = 'opacity 0.3s ease-in-out'
        this.containerTarget.style.opacity = '0'
        setTimeout(() => {
          this.containerTarget.style.display = 'none'
        }, 300)
      }
    }
  }

  initializeMDBComponents() {
    // Initialize any MDB components that might be in the container
    // (Currently not needed since we're using standard Bootstrap forms, 
    // but keeping for future extensibility)
    
    // Initialize selects if any exist
    const selects = this.containerTarget.querySelectorAll('[data-mdb-select-init]')
    selects.forEach(select => {
      if (window.mdb && window.mdb.Select) {
        new mdb.Select(select)
      }
    })

    // Initialize tooltips if any exist
    const tooltips = this.containerTarget.querySelectorAll('[data-mdb-tooltip-init]')
    tooltips.forEach(tooltip => {
      if (window.mdb && window.mdb.Tooltip) {
        new mdb.Tooltip(tooltip)
      }
    })
  }
}