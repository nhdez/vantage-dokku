import { Controller } from "@hotwired/stimulus"

// Generic confirmation modal controller.
//
// Usage: call window.appConfirm({ title, bodyHtml, confirmLabel, danger }) which
// returns a Promise<boolean>. bodyHtml is developer-controlled HTML (never user input).
// The modal element is injected once and reused across calls.
export default class extends Controller {
  connect() {
    this._ensureModal()
    window.appConfirm = this.show.bind(this)
  }

  disconnect() {
    delete window.appConfirm
  }

  show({ title = "Are you sure?", bodyHtml = "", confirmLabel = "Confirm", danger = false } = {}) {
    return new Promise((resolve) => {
      const modal = document.getElementById("app-confirm-modal")
      modal.querySelector(".app-confirm-title").textContent = title
      const bodyEl = modal.querySelector(".app-confirm-body")
      bodyEl.replaceChildren()
      bodyEl.insertAdjacentHTML("beforeend", bodyHtml)

      const confirmBtn = modal.querySelector(".app-confirm-ok")
      confirmBtn.textContent = confirmLabel
      confirmBtn.className = `btn ${danger ? "btn-danger" : "btn-primary"} app-confirm-ok`

      const instance = new mdb.Modal(modal, { backdrop: true, keyboard: true })

      const onConfirm = () => {
        cleanup()
        resolve(true)
      }
      const onCancel = () => {
        cleanup()
        resolve(false)
      }

      const cleanup = () => {
        confirmBtn.removeEventListener("click", onConfirm)
        modal.removeEventListener("hide.mdb.modal", onCancel)
        instance.hide()
      }

      confirmBtn.addEventListener("click", onConfirm, { once: true })
      modal.addEventListener("hide.mdb.modal", onCancel, { once: true })

      instance.show()
    })
  }

  _ensureModal() {
    if (document.getElementById("app-confirm-modal")) return

    const html = `
      <div id="app-confirm-modal" class="modal fade" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title app-confirm-title"></h5>
              <button type="button" class="btn-close" data-mdb-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
              <p class="app-confirm-body mb-0"></p>
            </div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" data-mdb-dismiss="modal">Cancel</button>
              <button type="button" class="btn btn-primary app-confirm-ok">Confirm</button>
            </div>
          </div>
        </div>
      </div>`

    document.body.insertAdjacentHTML("beforeend", html)
  }
}
