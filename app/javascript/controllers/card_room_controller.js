import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Visual positions for 6-max oval table. Index 0 = bottom-center (rotated to hero).
const SEAT_POSITIONS_6 = [
  'bottom:2%;left:50%;transform:translateX(-50%)',
  'bottom:10%;left:4%',
  'top:50%;left:0%;transform:translateY(-50%)',
  'top:5%;left:4%',
  'top:5%;right:4%',
  'top:50%;right:0%;transform:translateY(-50%)',
]

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
          } else if (data.type === "error") {
            console.error('[CardRoom] server error:', data.detail, '-', data.message)
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
    const seat = this.state.seats.find(s => s.position === position)
    if (seat && seat.status !== "empty") return
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

  reset() { this.channel.send({ type: "reset" }) }

  // ── Actions ─────────────────────────────────────────────────────────────────

  fold()  {
    console.log('[CardRoom] fold, pos:', this.myPosition())
    this.actionInfoTarget.textContent = 'Sending fold...'
    this._sendAction({ type: "action", move: "fold", position: this.myPosition() })
  }
  call()  {
    console.log('[CardRoom] call/check, pos:', this.myPosition())
    this.actionInfoTarget.textContent = 'Sending...'
    this._sendAction({ type: "action", move: "call", position: this.myPosition() })
  }
  raise() {
    const amount = parseInt(this.raiseInputTarget.value)
    console.log('[CardRoom] raise, pos:', this.myPosition(), 'amount:', amount)
    this.actionInfoTarget.textContent = 'Sending raise...'
    this._sendAction({ type: "action", move: "raise", amount, position: this.myPosition() })
  }

  _sendAction(data) {
    const sent = this.channel.send(data)
    const ws   = this.channel.consumer?.connection?.webSocket
    console.log('[CardRoom] send returned:', sent,
      '| WS readyState:', ws?.readyState,
      '| subscription:', this.channel.consumer?.subscriptions?.subscriptions?.length)
    if (!sent) {
      console.error('[CardRoom] send FAILED — WebSocket not open, readyState:', ws?.readyState)
      this.actionInfoTarget.textContent = 'Connection lost — please reload'
    }
  }

  // ── Rendering ───────────────────────────────────────────────────────────────

  render() {
    if (!this.state) return
    console.log('[CardRoom] state:', this.state.status, this.state.street,
      '| current_pos:', this.state.current_position,
      '| my_pos:', this.myPosition(),
      '| my_session:', this.sessionId)
    this.renderTable()
    this.renderActionBar()
  }

  renderTable() {
    const s = this.state
    const myPos = this.myPosition()
    const maxSeats = this.maxSeatsValue
    const offset = myPos !== null ? myPos : 0

    const seatMap = {}
    s.seats.forEach(seat => { seatMap[seat.position] = seat })

    // Rotate so hero always appears at visual position 0 (bottom-center)
    const visualSlots = Array.from({ length: maxSeats }, (_, vp) => {
      const ap = (vp + offset) % maxSeats
      return seatMap[ap] || { position: ap, status: 'empty', name: null, stack: 0, bet: 0, hole_cards: [] }
    })

    const statusText = s.status === 'playing'
      ? (s.street || '').replace(/_/g, ' ')
      : 'Waiting for players'

    this.tableTarget.innerHTML = `
      <div class="bg-gray-900 border border-gray-800 rounded-2xl p-4">
        <div class="flex justify-between items-center mb-3">
          <span class="text-sm text-gray-400">Hand #${s.hand_number || 0}</span>
          <span class="text-sm ${s.status === 'playing' ? 'text-green-400' : 'text-gray-500'}">${statusText}</span>
        </div>
        <div class="relative" style="height:380px">
          ${this.renderFelt(s)}
          ${visualSlots.map((seat, vp) => this.renderSeat(seat, s, myPos, vp)).join('')}
        </div>
      </div>
    `
  }

  renderFelt(s) {
    const cards = s.community_cards || []
    const placeholders = Array(5 - cards.length).fill(null)
    return `
      <div class="absolute flex flex-col items-center justify-center gap-2"
           style="top:22%;left:18%;right:18%;bottom:22%;background:#14532d;border:3px solid #166534;border-radius:50%">
        <div class="flex gap-1 flex-wrap justify-center">
          ${cards.map(c => this.cardHtml(c)).join('')}
          ${placeholders.map(() => `<div class="w-8 h-11 rounded" style="background:rgba(22,101,52,0.5);border:1px dashed #15803d"></div>`).join('')}
        </div>
        <div class="text-sm font-medium" style="color:#86efac">Pot: $${s.pot || 0}</div>
        ${s.last_action ? `<div class="text-xs" style="color:#9ca3af">${s.last_action.player} ${s.last_action.action}${s.last_action.amount ? ' $' + s.last_action.amount : ''}</div>` : ''}
      </div>
    `
  }

  renderSeat(seat, state, myPos, visualPos = 0) {
    const posStyle   = SEAT_POSITIONS_6[visualPos] || SEAT_POSITIONS_6[0]
    const isMe       = seat.position === myPos
    const isActive   = state.current_position === seat.position
    const borderColor = isMe ? '#3b82f6' : isActive ? '#4ade80' : '#374151'

    if (seat.status === 'empty') {
      return `
        <div class="absolute w-24 rounded-lg p-2 text-center cursor-pointer"
             style="${posStyle};border:1px dashed ${borderColor};background:#111827"
             data-action="click->card-room#clickSeat" data-position="${seat.position}">
          <div class="text-xs mb-1" style="color:#4b5563">Seat ${seat.position + 1}</div>
          <div class="text-xs" style="color:#6b7280">+ Sit</div>
          <div class="mt-1">
            <button class="text-xs" style="color:#4b5563;text-decoration:underline"
                    data-action="click->card-room#addBot" data-position="${seat.position}"
                    onclick="event.stopPropagation()">Add Bot</button>
          </div>
        </div>
      `
    }

    // True showdown = hand_over with multiple active/all-in players (vs. a fold win with one survivor)
    const activeSeatCount = state.seats.filter(s => s.status === 'active' || s.status === 'all_in').length
    const isTrueShowdown  = state.street === 'hand_over' && activeSeatCount > 1
    const cards = isMe ? (seat.hole_cards || []) :
                  (isTrueShowdown && (seat.status === 'active' || seat.status === 'all_in')) ? (seat.hole_cards || []) : []
    const folded = seat.status === 'folded'

    return `
      <div class="absolute w-24 rounded-lg p-2 text-center${folded ? ' opacity-40' : ''}"
           style="${posStyle};border:1px solid ${borderColor};background:#111827">
        <div class="text-xs mb-1 truncate" style="color:#9ca3af">${seat.name}${seat.is_bot ? ' 🤖' : ''}${isMe ? ' (you)' : ''}</div>
        <div class="text-sm font-bold">$${seat.stack}</div>
        <div class="flex gap-1 justify-center mt-1">
          ${cards.length
            ? cards.map(c => this.cardHtml(c)).join('')
            : `<div class="text-xs" style="color:#4b5563">—</div>`}
        </div>
        ${seat.bet > 0 ? `<div class="text-xs mt-1" style="color:#eab308">bet $${seat.bet}</div>` : ''}
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

  potBet() {
    const s        = this.state
    const myPos    = this.myPosition()
    const mySeat   = s.seats.find(seat => seat.position === myPos)
    const allIn    = (mySeat?.stack || 0) + (mySeat?.bet || 0)
    const minRaise = (s.current_bet || 0) + (s.min_raise || 20)
    this.raiseInputTarget.value = Math.min(Math.max(s.pot || 0, minRaise), allIn)
  }

  allIn() {
    const myPos  = this.myPosition()
    const mySeat = this.state.seats.find(seat => seat.position === myPos)
    this.raiseInputTarget.value = (mySeat?.stack || 0) + (mySeat?.bet || 0)
  }

  renderActionBar() {
    const s     = this.state
    const myPos = this.myPosition()
    const isMyTurn = s.current_position === myPos && s.status === 'playing'

    this.actionBarTarget.style.visibility = isMyTurn ? 'visible' : 'hidden'
    if (!isMyTurn) return

    const mySeat   = s.seats.find(seat => seat.position === myPos)
    const toCall   = (s.current_bet || 0) - (mySeat?.bet || 0)
    const minRaise = (s.current_bet || 0) + (s.min_raise || 20)
    const allIn    = (mySeat?.stack || 0) + (mySeat?.bet || 0)

    this.actionInfoTarget.textContent = toCall > 0 ? `To call: $${toCall}` : 'Your action'
    this.callButtonTarget.textContent = toCall > 0 ? `Call $${toCall}` : 'Check'
    this.raiseInputTarget.value       = minRaise
    this.raiseInputTarget.min         = minRaise
    this.raiseInputTarget.max         = allIn
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
