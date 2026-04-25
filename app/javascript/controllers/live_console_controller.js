import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["console", "output", "tabs", "toggleBtn"]

  connect() {
    this.ops = {}      // { id: { label, subscription, lines, status, onComplete } }
    this.activeId = null
    this.expanded = false
    this._onStart = this.handleStart.bind(this)
    window.addEventListener("live-console:start", this._onStart)
  }

  disconnect() {
    window.removeEventListener("live-console:start", this._onStart)
    Object.values(this.ops).forEach(op => op.subscription?.unsubscribe())
  }

  handleStart({ detail: { id, label, channelName, channelParams, onComplete } }) {
    if (this.ops[id]) return

    const subscription = window.actionCableConsumer.subscriptions.create(
      { channel: channelName, ...channelParams },
      { received: (data) => this.receive(id, data) }
    )

    this.ops[id] = { label, subscription, lines: [], status: "running", onComplete }
    if (!this.activeId) this.activeId = id
    this.element.classList.remove("d-none")
    this.renderTabs()
  }

  receive(id, data) {
    const op = this.ops[id]
    if (!op) return

    if (data.type === "started") {
      op.lines.push(data.message)
    } else if (data.type === "output") {
      if (data.message?.trim()) op.lines.push(data.message)
    } else if (data.type === "completed") {
      op.status = data.success ? "success" : "failed"
      op.lines.push(`\n--- ${data.message} ---`)
      op.subscription.unsubscribe()
      op.onComplete?.()
      setTimeout(() => this.remove(id), 5000)
    }

    this.renderTabs()
    if (this.activeId === id && this.expanded) this.renderOutput()
  }

  remove(id) {
    delete this.ops[id]
    const ids = Object.keys(this.ops)
    if (ids.length === 0) {
      this.element.classList.add("d-none")
      this.expanded = false
      this.consoleTarget.classList.add("d-none")
      this.toggleBtnTarget.replaceChildren(this._icon("fas fa-chevron-up"))
    } else {
      if (this.activeId === id) this.activeId = ids[0]
      this.render()
    }
  }

  toggle() {
    this.expanded = !this.expanded
    if (this.expanded) {
      this.consoleTarget.classList.remove("d-none")
      this.renderOutput()
      this.toggleBtnTarget.replaceChildren(this._icon("fas fa-chevron-down"))
    } else {
      this.consoleTarget.classList.add("d-none")
      this.toggleBtnTarget.replaceChildren(this._icon("fas fa-chevron-up"))
    }
  }

  switchTo(event) {
    this.activeId = event.currentTarget.dataset.opId
    this.renderTabs()
    if (this.expanded) this.renderOutput()
  }

  renderTabs() {
    const buttons = Object.entries(this.ops).map(([id, op]) => {
      const btn = document.createElement("button")
      btn.className = "live-console-tab" + (id === this.activeId ? " active" : "")
      btn.dataset.action = "click->live-console#switchTo"
      btn.dataset.opId = id

      if (op.status === "running") {
        const spinner = document.createElement("span")
        spinner.className = "live-console-spinner me-1"
        btn.appendChild(spinner)
      } else {
        btn.appendChild(this._icon(
          op.status === "success"
            ? "fas fa-check-circle text-success me-1"
            : "fas fa-times-circle text-danger me-1"
        ))
      }

      btn.appendChild(document.createTextNode(op.label))
      return btn
    })

    this.tabsTarget.replaceChildren(...buttons)
  }

  renderOutput() {
    const op = this.ops[this.activeId]
    if (!op) return
    this.outputTarget.textContent = op.lines.join("\n")
    this.consoleTarget.scrollTop = this.consoleTarget.scrollHeight
  }

  render() {
    this.renderTabs()
    if (this.expanded) this.renderOutput()
  }

  _icon(classes) {
    const i = document.createElement("i")
    i.className = classes
    return i
  }
}
