import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["table", "nameModal", "nameInput", "actionBar",
                    "actionInfo", "callButton", "raiseInput"]
  static values  = { slug: String, maxSeats: Number }

  connect() {
    this.sessionId = this.getOrCreateSessionId()
    this.pendingSeatPosition = null
    this.state = null
    const consumer = createConsumer()

    this.channel = consumer.subscriptions.create(
      { channel: "CardRoomChannel", slug: this.slugValue, session_id: this.sessionId },
      {
        received: (data) => {
          if (data.type === "state_update") {
            this.state = data.state
            this.render()
          }
        }
      }
    )
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  // ── Seat interaction ────────────────────────────────────────────────────────

  clickSeat(event) {
    const position = parseInt(event.currentTarget.dataset.position)
    const seat = this.state.seats[position]
    if (seat.status !== "empty") return
    this.pendingSeatPosition = position
    this.nameModalTarget.classList.remove("hidden")
    this.nameInputTarget.focus()
  }

  confirmJoin() {
    const name = this.nameInputTarget.value.trim()
    if (!name) return
    this.channel.send({ type: "join_seat", position: this.pendingSeatPosition, name })
    this.nameModalTarget.classList.add("hidden")
    this.nameInputTarget.value = ""
    this.pendingSeatPosition = null
  }

  cancelJoin() {
    this.nameModalTarget.classList.add("hidden")
    this.pendingSeatPosition = null
  }

  addBot(event) {
    const position = parseInt(event.currentTarget.dataset.position)
    this.channel.send({ type: "add_bot", position })
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  fold()  { this.channel.send({ type: "action", action: "fold",  position: this.myPosition() }) }
  call()  { this.channel.send({ type: "action", action: "call",  position: this.myPosition() }) }
  raise() {
    const amount = parseInt(this.raiseInputTarget.value)
    this.channel.send({ type: "action", action: "raise", amount, position: this.myPosition() })
  }

  // ── Rendering ───────────────────────────────────────────────────────────────

  render() {
    if (!this.state) return
    this.renderTable()
    this.renderActionBar()
  }

  renderTable() {
    const s = this.state
    const myPos = this.myPosition()
    const seats = Array.from({ length: this.maxSeatsValue }, (_, i) =>
      s.seats.find(seat => seat.position === i) ||
      { position: i, status: "empty", name: null, stack: 0, bet: 0, hole_cards: [] }
    )

    this.tableTarget.innerHTML = `
      <div class="bg-gray-900 border border-gray-800 rounded-2xl p-4">
        <div class="flex justify-between items-center mb-3">
          <span class="text-sm text-gray-400">Hand #${s.hand_number || 0}</span>
          <span class="text-sm ${s.status === 'playing' ? 'text-green-400' : 'text-gray-500'}">
            ${s.status === 'playing' ? (s.street || '').replace('_', ' ') : 'Waiting for players'}
          </span>
        </div>
        ${this.renderFelt(s)}
        <div class="grid grid-cols-3 gap-2 mt-4">
          ${seats.map(seat => this.renderSeat(seat, s, myPos)).join('')}
        </div>
        ${s.last_action ? `
          <div class="text-center text-xs text-gray-500 mt-2">
            ${s.last_action.player} ${s.last_action.action}
            ${s.last_action.amount ? '$' + s.last_action.amount : ''}
          </div>` : ''}
      </div>
    `
  }

  renderFelt(s) {
    const cards = s.community_cards || []
    const placeholders = Array(5 - cards.length).fill(null)
    return `
      <div class="bg-green-900 border-2 border-green-800 rounded-xl py-4 px-6 text-center">
        <div class="flex justify-center gap-2 mb-2">
          ${cards.map(c => this.cardHtml(c)).join('')}
          ${placeholders.map(() => `<div class="w-8 h-11 bg-green-800/50 rounded border border-dashed border-green-700"></div>`).join('')}
        </div>
        <div class="text-sm text-green-300">Pot: $${s.pot || 0}</div>
      </div>
    `
  }

  renderSeat(seat, state, myPos) {
    const isMe     = seat.position === myPos
    const isActive = state.current_position === seat.position
    const borderClass = isMe ? 'border-blue-500' : isActive ? 'border-green-400' : 'border-gray-700'
    const atShowdown  = state.street === 'showdown' || state.street === 'hand_over'

    if (seat.status === 'empty') {
      return `
        <div class="border ${borderClass} border-dashed rounded-lg p-2 text-center cursor-pointer hover:border-blue-400 transition-colors"
             data-action="click->card-room#clickSeat" data-position="${seat.position}">
          <div class="text-xs text-gray-600 mb-1">Seat ${seat.position + 1}</div>
          <div class="text-xs text-gray-500">+ Sit Down</div>
          <div class="mt-1">
            <button class="text-xs text-gray-600 hover:text-gray-400 underline"
                    data-action="click->card-room#addBot" data-position="${seat.position}"
                    onclick="event.stopPropagation()">Add Bot</button>
          </div>
        </div>
      `
    }

    // Only show hole cards for own seat, or at showdown for surviving players
    const cards  = isMe ? (seat.hole_cards || []) :
                   (atShowdown && seat.status === 'active') ? (seat.hole_cards || []) : []
    const folded = seat.status === 'folded'

    return `
      <div class="border ${borderClass} rounded-lg p-2 text-center ${folded ? 'opacity-40' : ''}">
        <div class="text-xs text-gray-400 mb-1">${seat.name}${seat.is_bot ? ' 🤖' : ''}${isMe ? ' (you)' : ''}</div>
        <div class="text-sm font-bold">$${seat.stack}</div>
        <div class="flex gap-1 justify-center mt-1">
          ${cards.length
            ? cards.map(c => this.cardHtml(c)).join('')
            : '<div class="text-xs text-gray-600">—</div>'}
        </div>
        ${seat.bet > 0 ? `<div class="text-xs text-yellow-500 mt-1">bet $${seat.bet}</div>` : ''}
      </div>
    `
  }

  cardHtml(card) {
    if (!card || card === '??') {
      return `<div class="w-8 h-11 bg-red-800 rounded text-white text-xs flex items-center justify-center border border-red-700">?</div>`
    }
    const rank = card[0]
    const suit = card[1]
    const red  = suit === 'h' || suit === 'd'
    const sym  = { h: '♥', d: '♦', s: '♠', c: '♣' }[suit] || suit
    return `
      <div class="w-8 h-11 bg-white rounded flex flex-col items-center justify-center border border-gray-300">
        <span class="text-xs font-bold leading-none ${red ? 'text-red-600' : 'text-gray-900'}">${rank}</span>
        <span class="text-xs leading-none ${red ? 'text-red-600' : 'text-gray-900'}">${sym}</span>
      </div>
    `
  }

  renderActionBar() {
    const s     = this.state
    const myPos = this.myPosition()
    const isMyTurn = s.current_position === myPos && s.status === 'playing'

    if (!isMyTurn) {
      this.actionBarTarget.classList.add("hidden")
      return
    }

    const mySeat   = s.seats.find(seat => seat.position === myPos)
    const toCall   = (s.current_bet || 0) - (mySeat?.bet || 0)
    const minRaise = (s.current_bet || 0) + (s.min_raise || 20)

    this.actionBarTarget.classList.remove("hidden")
    this.actionInfoTarget.textContent = toCall > 0 ? `To call: $${toCall}` : 'Your action'
    this.callButtonTarget.textContent = toCall > 0 ? `Call $${toCall}` : 'Check'
    this.raiseInputTarget.value       = minRaise
    this.raiseInputTarget.min         = minRaise
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  myPosition() {
    if (!this.state) return null
    const seat = this.state.seats.find(s => s.session_id === this.sessionId)
    return seat ? seat.position : null
  }

  getOrCreateSessionId() {
    let sid = sessionStorage.getItem("card_room_session_id")
    if (!sid) {
      sid = Math.random().toString(36).substring(2, 10)
      sessionStorage.setItem("card_room_session_id", sid)
    }
    return sid
  }
}
