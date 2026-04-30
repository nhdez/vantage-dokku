import { Controller } from "@hotwired/stimulus"

// Handles Github-style deletion confirmation where user must type the object name
export default class extends Controller {
  static targets = ["input", "button"]
  static values = {
    expectedName: String
  }

  connect() {
    if (this.hasInputTarget) {
      this.validate()
    }
  }

  validate() {
    if (!this.hasInputTarget || !this.hasButtonTarget) return
    
    const isMatch = this.inputTarget.value === this.expectedNameValue
    this.buttonTarget.disabled = !isMatch
  }

  reset() {
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
      this.validate()
    }
  }
}
