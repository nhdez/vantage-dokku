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
    // Find and initialize MDB inputs in the container
    const inputs = this.containerTarget.querySelectorAll('.form-outline')
    
    inputs.forEach(inputContainer => {
      if (window.mdb && window.mdb.Input) {
        const input = inputContainer.querySelector('input, textarea')
        if (input) {
          // Initialize MDB Input
          new mdb.Input(input)
          
          // Handle pre-filled inputs - activate label if input has value
          if (input.value && input.value.trim() !== '') {
            const label = inputContainer.querySelector('.form-label')
            if (label) {
              label.classList.add('active')
            }
          }
        }
      }
    })

    // Initialize selects
    const selects = this.containerTarget.querySelectorAll('.form-select')
    selects.forEach(select => {
      if (window.mdb && window.mdb.Select) {
        new mdb.Select(select)
      }
    })
  }
}