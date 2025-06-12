import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="mdb"
export default class extends Controller {
  connect() {
    this.initializeMDB()
  }

  initializeMDB() {
    // Initialize MDB components when they become available
    if (typeof mdb !== 'undefined') {
      // Initialize dropdowns
      const dropdownElements = document.querySelectorAll('[data-mdb-toggle="dropdown"]')
      dropdownElements.forEach(element => {
        if (!element._mdbDropdown) {
          element._mdbDropdown = new mdb.Dropdown(element)
        }
      })

      // Initialize collapse/navbar toggles
      const collapseElements = document.querySelectorAll('[data-mdb-toggle="collapse"]')
      collapseElements.forEach(element => {
        if (!element._mdbCollapse) {
          element._mdbCollapse = new mdb.Collapse(element)
        }
      })

      // Initialize alerts
      const alertElements = document.querySelectorAll('[data-mdb-dismiss="alert"]')
      alertElements.forEach(element => {
        if (!element._mdbAlert) {
          element.addEventListener('click', (e) => {
            e.preventDefault()
            const alert = element.closest('.alert')
            if (alert) {
              alert.classList.add('fade')
              setTimeout(() => {
                alert.remove()
              }, 150)
            }
          })
          element._mdbAlert = true
        }
      })
    } else {
      // If MDB is not loaded yet, try again in a moment
      setTimeout(() => this.initializeMDB(), 100)
    }
  }
}