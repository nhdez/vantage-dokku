// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import * as ActionCable from "@rails/actioncable"

// Make ActionCable available globally
window.ActionCable = ActionCable

// Initialize ActionCable consumer globally
window.actionCableConsumer = ActionCable.createConsumer()

// Initialize MDB on page load and Turbo navigation
document.addEventListener('DOMContentLoaded', initializeMDB)
document.addEventListener('turbo:load', initializeMDB)

function initializeMDB() {
  // Wait for MDB to be available
  const checkMDB = () => {
    if (typeof mdb !== 'undefined') {
      // Initialize dropdowns
      const dropdownElements = document.querySelectorAll('[data-mdb-toggle="dropdown"]')
      dropdownElements.forEach(element => {
        if (!element._mdbDropdown) {
          try {
            element._mdbDropdown = new mdb.Dropdown(element)
          } catch (e) {
            console.log('Dropdown init error:', e)
          }
        }
      })

      // Initialize collapse/navbar toggles
      const collapseElements = document.querySelectorAll('[data-mdb-toggle="collapse"]')
      collapseElements.forEach(element => {
        if (!element._mdbCollapse) {
          try {
            element._mdbCollapse = new mdb.Collapse(element)
          } catch (e) {
            console.log('Collapse init error:', e)
          }
        }
      })

      // Initialize alert dismissal
      const alertElements = document.querySelectorAll('[data-mdb-dismiss="alert"]')
      alertElements.forEach(element => {
        if (!element._mdbAlertHandler) {
          element.addEventListener('click', (e) => {
            e.preventDefault()
            const alert = element.closest('.alert')
            if (alert) {
              alert.classList.remove('show')
              alert.classList.add('fade')
              setTimeout(() => {
                alert.remove()
              }, 150)
            }
          })
          element._mdbAlertHandler = true
        }
      })
    } else {
      // MDB not loaded yet, try again
      setTimeout(checkMDB, 100)
    }
  }
  
  checkMDB()
}
