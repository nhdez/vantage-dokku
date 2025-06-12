import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.initializeMDB()
  }

  initializeMDB() {
    // Initialize all MDB inputs in this container
    const inputs = this.element.querySelectorAll('.form-outline')
    
    inputs.forEach(inputContainer => {
      // Initialize the MDB Input
      if (window.mdb && window.mdb.Input) {
        const input = inputContainer.querySelector('input, textarea')
        if (input) {
          // Create new MDB Input instance
          new mdb.Input(input)
          
          // Handle pre-filled inputs
          if (input.value && input.value.trim() !== '') {
            this.activateLabel(inputContainer)
          }
        }
      }
    })

    // Initialize other MDB components
    this.initializeOtherMDBComponents()
  }

  activateLabel(inputContainer) {
    const label = inputContainer.querySelector('.form-label')
    if (label) {
      label.classList.add('active')
    }
  }

  initializeOtherMDBComponents() {
    // Initialize selects
    const selects = this.element.querySelectorAll('.form-select')
    selects.forEach(select => {
      if (window.mdb && window.mdb.Select) {
        new mdb.Select(select)
      }
    })

    // Initialize switches
    const switches = this.element.querySelectorAll('.form-check-input')
    switches.forEach(switchEl => {
      if (window.mdb && window.mdb.Switch) {
        new mdb.Switch(switchEl)
      }
    })

    // Initialize tooltips
    const tooltips = this.element.querySelectorAll('[data-mdb-tooltip-init]')
    tooltips.forEach(tooltip => {
      if (window.mdb && window.mdb.Tooltip) {
        new mdb.Tooltip(tooltip)
      }
    })
  }

  // Method to reinitialize when content changes
  reinitialize() {
    this.initializeMDB()
  }
}