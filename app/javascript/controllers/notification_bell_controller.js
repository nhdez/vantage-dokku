import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "vantage_notifications_v2"
const MAX_ITEMS   = 50

export default class extends Controller {
  static targets = ["badge", "dropdown", "list", "empty"]

  connect() {
    this.notifications = this._load()
    this._observer     = null

    this._onCompleted = this.handleLiveConsoleCompleted.bind(this)
    this._onPush      = this.handlePush.bind(this)
    this._onClickOut  = this.handleClickOutside.bind(this)

    window.addEventListener("live-console:completed", this._onCompleted)
    window.addEventListener("notify:push",            this._onPush)
    document.addEventListener("click",                this._onClickOut)

    this._updateBadge()
    this.render()
  }

  disconnect() {
    window.removeEventListener("live-console:completed", this._onCompleted)
    window.removeEventListener("notify:push",            this._onPush)
    document.removeEventListener("click",               this._onClickOut)
    this._observer?.disconnect()
  }

  // ---- event sources ----

  handleLiveConsoleCompleted({ detail: { label, success, message, lines } }) {
    // Skip if an identical notification was pushed via notify:push within the last 3s
    // (some onComplete callbacks also call showToast which would double-notify)
    const preview = lines
      .filter(l => l.trim() && !l.startsWith("\n---"))
      .slice(-5)
      .join("\n")
      .trim()

    this._push({
      source:  "operation",
      type:    success ? "success" : "error",
      title:   label,
      message: message || (success ? "Completed successfully" : "Failed"),
      preview,
    })
  }

  handlePush({ detail: { type, title, message } }) {
    // Deduplicate: skip if an identical operation notification exists for this title within 5s
    const recent = this.notifications.find(
      n => n.source === "operation" && n.title === title && Date.now() - n.ts < 5000
    )
    if (recent) return

    this._push({ source: "toast", type, title, message, preview: null })
  }

  // ---- user actions ----

  toggle(event) {
    event.stopPropagation()
    if (this.dropdownTarget.classList.contains("d-none")) {
      this._open()
    } else {
      this._close()
    }
  }

  markAllRead(event) {
    event?.stopPropagation()
    this.notifications.forEach(n => { n.read = true })
    this._save()
    this._updateBadge()
    this.render()
  }

  clearAll(event) {
    event?.stopPropagation()
    this.notifications = []
    this._save()
    this._updateBadge()
    this.render()
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) this._close()
  }

  // ---- render ----

  render() {
    const list = this.listTarget
    list.replaceChildren()
    this._observer?.disconnect()
    this._observer = null

    if (this.notifications.length === 0) {
      this.emptyTarget.classList.remove("d-none")
      return
    }

    this.emptyTarget.classList.add("d-none")

    this._observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return
        const id = Number(entry.target.dataset.notifId)
        const n  = this.notifications.find(x => x.id === id)
        if (n && !n.read) {
          // Mark read after 1.5s of being visible
          setTimeout(() => {
            const still = this.notifications.find(x => x.id === id)
            if (still && !still.read) {
              still.read = true
              this._save()
              this._updateBadge()
              entry.target.classList.remove("notif-item--unread")
              entry.target.querySelector(".notif-unread-dot")?.remove()
            }
          }, 1500)
        }
        this._observer?.unobserve(entry.target)
      })
    }, { root: list, threshold: 0.8 })

    this.notifications.forEach(n => {
      const item = this._buildItem(n)
      list.appendChild(item)
      if (!n.read) this._observer.observe(item)
    })
  }

  // ---- private ----

  _push(attrs) {
    const n = {
      id:      Date.now() + Math.random(),
      ts:      Date.now(),
      read:    false,
      source:  attrs.source,
      type:    attrs.type,
      title:   attrs.title,
      message: attrs.message,
      preview: attrs.preview || null,
    }

    this.notifications.unshift(n)
    if (this.notifications.length > MAX_ITEMS) this.notifications.length = MAX_ITEMS
    this._save()
    this._updateBadge()

    // If dropdown is open, re-render and observe the new item
    if (!this.dropdownTarget.classList.contains("d-none")) {
      this.render()
    }
  }

  _open() {
    this.dropdownTarget.classList.remove("d-none")
    this.render()
  }

  _close() {
    this.dropdownTarget.classList.add("d-none")
    this._observer?.disconnect()
    this._observer = null
  }

  _updateBadge() {
    const unread = this.notifications.filter(n => !n.read).length
    if (unread > 0) {
      this.badgeTarget.textContent = unread > 99 ? "99+" : String(unread)
      this.badgeTarget.classList.remove("d-none")
    } else {
      this.badgeTarget.classList.add("d-none")
    }
  }

  _buildItem(n) {
    const iconClass = {
      success: "fas fa-check-circle text-success",
      error:   "fas fa-times-circle text-danger",
      warning: "fas fa-exclamation-triangle text-warning",
      notice:  "fas fa-check-circle text-success",
    }[n.type] || "fas fa-info-circle text-primary"

    const time = new Date(n.ts).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })

    const item = document.createElement("div")
    item.className = "notif-item" + (n.read ? "" : " notif-item--unread")
    item.dataset.notifId = n.id

    // Unread dot
    if (!n.read) {
      const dot = document.createElement("span")
      dot.className = "notif-unread-dot"
      item.appendChild(dot)
    }

    const iconEl = document.createElement("i")
    iconEl.className = iconClass + " notif-icon"
    item.appendChild(iconEl)

    const body = document.createElement("div")
    body.className = "notif-body"

    const labelEl = document.createElement("div")
    labelEl.className = "notif-label"
    labelEl.textContent = n.title
    body.appendChild(labelEl)

    const msgEl = document.createElement("div")
    msgEl.className = "notif-message"
    msgEl.textContent = n.message
    body.appendChild(msgEl)

    if (n.preview) {
      const pre = document.createElement("pre")
      pre.className = "notif-preview"
      pre.textContent = n.preview
      body.appendChild(pre)
    }

    const timeEl = document.createElement("div")
    timeEl.className = "notif-time"
    timeEl.textContent = time
    body.appendChild(timeEl)

    item.appendChild(body)
    return item
  }

  _load() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]")
    } catch {
      return []
    }
  }

  _save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.notifications))
    } catch { /* storage full */ }
  }
}
