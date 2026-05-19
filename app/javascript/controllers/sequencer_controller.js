import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const STEPS   = 16
const NOTES   = ['B4','A#4','A4','G#4','G4','F#4','F4','E4','D#4','D4','C#4','C4']
const ROWS    = NOTES.length
const NATURAL = new Set(['C4','D4','E4','F4','G4','A4','B4'])

export default class extends Controller {
  static values = { slug: String, state: Object }

  static targets = [
    'grid', 'kickGrid', 'noteLabels', 'beatMarkers', 'percSection',
    'playBtn', 'addKickBtn',
    'bpmInput', 'bpmVal',
    'waveformSelect',
    'decayInput', 'decayVal',
    'reverbInput', 'reverbVal',
    'volumeInput', 'volVal',
    'collabIndicator', 'collabStatus', 'shareLink'
  ]

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  connect() {
    this.clientId       = crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36)
    this.channel        = null
    this.channelReady   = false
    this.pendingMessages = []
    this.pendingCreate  = false

    // Sequencer state
    this.grid      = Array.from({ length: ROWS }, () => new Array(STEPS).fill(false))
    this.kick      = new Array(STEPS).fill(false)
    this.kickActive = false
    this.cells     = []         // cells[row][step]
    this.kickCells = []
    this.head      = -1
    this.playing   = false

    this.buildNoteLabels()
    this.buildBeatMarkers()
    this.buildMelodyGrid()
    this.setupAudio()

    // iOS requires audio context to be resumed inside a synchronous user gesture.
    // Unlock it on the very first touch so it's ready before play is pressed.
    this._unlockAudio = () => Tone.start()
    document.addEventListener('touchstart', this._unlockAudio, { once: true, passive: true })

    // If the server gave us a song, load its state and connect immediately
    if (this.slugValue) {
      const initialState = this.stateValue
      if (initialState && initialState.grid) this.applyState(initialState)
      this.connectChannel(this.slugValue)
      this.showShareLink(this.slugValue)
    }
  }

  disconnect() {
    this.channel?.unsubscribe()
    if (this.playing) this._stopPlayback()
    document.removeEventListener('touchstart', this._unlockAudio)
  }

  // ── Audio setup ────────────────────────────────────────────────────────────

  setupAudio() {
    this.reverbFx  = new Tone.Reverb({ decay: 2.5, wet: 0.2 }).toDestination()
    this.volNode   = new Tone.Volume(-6).connect(this.reverbFx)
    this.kickSynth = new Tone.MembraneSynth({
      pitchDecay: 0.08, octaves: 6,
      envelope: { attack: 0.001, decay: 0.35, sustain: 0, release: 0.1 }
    }).toDestination()
    this.synth = new Tone.PolySynth(Tone.Synth, {
      oscillator: { type: 'sine' },
      envelope:   { attack: 0.005, decay: 0.4, sustain: 0, release: 0.1 }
    }).connect(this.volNode)

    this.seq = new Tone.Sequence((time, step) => {
      NOTES.forEach((note, row) => {
        if (this.grid[row][step]) {
          this.synth.triggerAttackRelease(note, '32n', time)
        }
      })
      if (this.kickActive && this.kick[step]) {
        this.kickSynth.triggerAttackRelease('C1', '8n', time)
      }
      Tone.Draw.schedule(() => {
        this._setHead(step)
        if (this.kickActive) {
          this.kickCells.forEach((c, i) => c.classList.toggle('head', i === step))
        }
      }, time)
    }, [...Array(STEPS).keys()], '16n')
  }

  // ── DOM building ───────────────────────────────────────────────────────────

  buildNoteLabels() {
    NOTES.forEach(n => {
      const d = document.createElement('div')
      d.className = 'note-label' + (NATURAL.has(n) ? ' natural' : '')
      d.textContent = n
      this.noteLabelsTarget.appendChild(d)
    })
  }

  buildBeatMarkers() {
    for (let s = 0; s < STEPS; s++) {
      const d = document.createElement('div')
      d.className = 'beat-marker' + (s % 4 === 0 ? ' bar-start' : '')
      d.textContent = s % 4 === 0 ? (s / 4 + 1) : '·'
      this.beatMarkersTarget.appendChild(d)
    }
  }

  buildMelodyGrid() {
    for (let row = 0; row < ROWS; row++) {
      this.cells[row] = []
      for (let step = 0; step < STEPS; step++) {
        const cell = document.createElement('div')
        cell.className = 'cell'
        cell.dataset.row  = row
        cell.dataset.step = step
        cell.addEventListener('click', () => this.toggle(row, step))
        this.gridTarget.appendChild(cell)
        this.cells[row][step] = cell
      }
    }
  }

  buildKickGrid() {
    for (let step = 0; step < STEPS; step++) {
      const cell = document.createElement('div')
      cell.className = 'cell'
      cell.dataset.step = step
      cell.addEventListener('click', () => this.kickToggle(step))
      this.kickGridTarget.appendChild(cell)
      this.kickCells[step] = cell
    }
  }

  // ── Playback actions ───────────────────────────────────────────────────────

  async togglePlay() {
    const btn = this.playBtnTarget
    btn.disabled = true
    setTimeout(() => { btn.disabled = false }, 500)

    if (!this.playing) {
      await Tone.start()
      this.seq.stop()
      Tone.Transport.stop()
      Tone.Transport.cancel()
      this.seq.start(0)
      Tone.Transport.start()
      this.playing = true
      btn.textContent = 'STOP'
      btn.classList.add('playing')
    } else {
      this._stopPlayback()
    }
  }

  _stopPlayback() {
    this.seq.stop()
    Tone.Transport.stop()
    Tone.Transport.cancel()
    this.playing = false
    this._clearHead()
    this.playBtnTarget.textContent = 'PLAY'
    this.playBtnTarget.classList.remove('playing')
  }

  // ── Grid actions ───────────────────────────────────────────────────────────

  toggle(row, step, remote = false) {
    this.grid[row][step] = !this.grid[row][step]
    this.cells[row][step].classList.toggle('on', this.grid[row][step])
    if (!remote) this.broadcastChange({ type: 'toggle', row, step, value: this.grid[row][step] })
  }

  kickToggle(step, remote = false) {
    this.kick[step] = !this.kick[step]
    this.kickCells[step]?.classList.toggle('on', this.kick[step])
    if (!remote) this.broadcastChange({ type: 'kick_toggle', step, value: this.kick[step] })
  }

  clear() {
    for (let r = 0; r < ROWS; r++)
      for (let s = 0; s < STEPS; s++) {
        this.grid[r][s] = false
        this.cells[r][s].classList.remove('on')
      }
    for (let s = 0; s < STEPS; s++) {
      this.kick[s] = false
      if (this.kickCells[s]) this.kickCells[s].classList.remove('on')
    }
    this.broadcastChange({ type: 'clear' })
  }

  addKick(broadcast = true) {
    if (this.kickActive) return
    this.kickActive = true
    this.buildKickGrid()
    this.percSectionTarget.style.display = ''
    this.addKickBtnTarget.textContent = 'KICK ON'
    this.addKickBtnTarget.classList.add('active')
    if (broadcast) this.broadcastChange({ type: 'kick_active', value: true })
  }

  // ── Control actions ────────────────────────────────────────────────────────

  changeBpm(event) {
    const v = +event.target.value
    Tone.Transport.bpm.value = v
    this.bpmValTarget.textContent = v
    this.broadcastChange({ type: 'bpm', value: v })
  }

  changeWaveform(event) {
    const v = event.target.value
    this.synth.set({ oscillator: { type: v } })
    this.broadcastChange({ type: 'waveform', value: v })
  }

  changeDecay(event) {
    const v = parseFloat(event.target.value)
    this.synth.set({ envelope: { decay: v } })
    this.decayValTarget.textContent = v.toFixed(2) + 's'
    this.broadcastChange({ type: 'decay', value: v })
  }

  changeReverb(event) {
    const v = +event.target.value
    this.reverbFx.wet.value = v / 100
    this.reverbValTarget.textContent = v + '%'
    this.broadcastChange({ type: 'reverb', value: v })
  }

  changeVolume(event) {
    const v = +event.target.value
    this.volNode.volume.value = v
    this.volValTarget.textContent = v
    this.broadcastChange({ type: 'volume', value: v })
  }

  // ── State loading ──────────────────────────────────────────────────────────

  applyState(s) {
    if (!s || !s.grid) return

    for (let row = 0; row < ROWS; row++)
      for (let step = 0; step < STEPS; step++) {
        this.grid[row][step] = s.grid[row]?.[step] ?? false
        this.cells[row]?.[step]?.classList.toggle('on', this.grid[row][step])
      }

    if (s.kick_active && !this.kickActive) {
      this.addKick(false)
      for (let step = 0; step < STEPS; step++) {
        this.kick[step] = s.kick?.[step] ?? false
        this.kickCells[step]?.classList.toggle('on', this.kick[step])
      }
    }

    if (s.bpm) {
      Tone.Transport.bpm.value = s.bpm
      this.bpmInputTarget.value = s.bpm
      this.bpmValTarget.textContent = s.bpm
    }
    if (s.waveform) {
      this.synth.set({ oscillator: { type: s.waveform } })
      this.waveformSelectTarget.value = s.waveform
    }
    if (s.decay != null) {
      this.synth.set({ envelope: { decay: s.decay } })
      this.decayInputTarget.value = s.decay
      this.decayValTarget.textContent = parseFloat(s.decay).toFixed(2) + 's'
    }
    if (s.reverb != null) {
      this.reverbFx.wet.value = s.reverb / 100
      this.reverbInputTarget.value = s.reverb
      this.reverbValTarget.textContent = s.reverb + '%'
    }
    if (s.volume != null) {
      this.volNode.volume.value = s.volume
      this.volumeInputTarget.value = s.volume
      this.volValTarget.textContent = s.volume
    }
  }

  applyDiff(data) {
    switch (data.type) {
      case 'toggle':
        this.grid[data.row][data.step] = data.value
        this.cells[data.row]?.[data.step]?.classList.toggle('on', data.value)
        break
      case 'kick_toggle':
        this.kick[data.step] = data.value
        this.kickCells[data.step]?.classList.toggle('on', data.value)
        break
      case 'kick_active':
        if (data.value && !this.kickActive) this.addKick(false)
        break
      case 'bpm':
        Tone.Transport.bpm.value = data.value
        this.bpmInputTarget.value = data.value
        this.bpmValTarget.textContent = data.value
        break
      case 'waveform':
        this.synth.set({ oscillator: { type: data.value } })
        this.waveformSelectTarget.value = data.value
        break
      case 'decay':
        this.synth.set({ envelope: { decay: data.value } })
        this.decayInputTarget.value = data.value
        this.decayValTarget.textContent = parseFloat(data.value).toFixed(2) + 's'
        break
      case 'reverb':
        this.reverbFx.wet.value = data.value / 100
        this.reverbInputTarget.value = data.value
        this.reverbValTarget.textContent = data.value + '%'
        break
      case 'volume':
        this.volNode.volume.value = data.value
        this.volumeInputTarget.value = data.value
        this.volValTarget.textContent = data.value
        break
      case 'clear':
        for (let r = 0; r < ROWS; r++)
          for (let s = 0; s < STEPS; s++) {
            this.grid[r][s] = false
            this.cells[r][s].classList.remove('on')
          }
        for (let s = 0; s < STEPS; s++) {
          this.kick[s] = false
          if (this.kickCells[s]) this.kickCells[s].classList.remove('on')
        }
        break
      case 'full_sync':
        if (data.grid) {
          for (let row = 0; row < ROWS; row++)
            for (let step = 0; step < STEPS; step++) {
              this.grid[row][step] = data.grid[row]?.[step] ?? false
              this.cells[row]?.[step]?.classList.toggle('on', this.grid[row][step])
            }
        }
        if (data.kick) {
          for (let step = 0; step < STEPS; step++) {
            this.kick[step] = data.kick[step] ?? false
            this.kickCells[step]?.classList.toggle('on', this.kick[step])
          }
        }
        if (data.kick_active && !this.kickActive) this.addKick(false)
        break
    }
  }

  // ── ActionCable ────────────────────────────────────────────────────────────

  connectChannel(slug) {
    this._setCollabStatus('connecting')
    const consumer = createConsumer()
    this.channel = consumer.subscriptions.create(
      { channel: 'SequencerChannel', slug },
      {
        connected: () => {
          this.channelReady = true
          this._setCollabStatus('connected')
          // Flush any messages that queued up before the socket was open
          while (this.pendingMessages.length) {
            this.channel.send(this.pendingMessages.shift())
          }
          // Sync our full state so the server is up-to-date
          this.channel.send({
            type: 'full_sync',
            client_id: this.clientId,
            grid: this.grid,
            kick: this.kick,
            kick_active: this.kickActive
          })
        },
        disconnected: () => {
          this.channelReady = false
          this._setCollabStatus('disconnected')
        },
        received: (data) => {
          if (data.client_id === this.clientId) return  // ignore own echo
          this.applyDiff(data)
        }
      }
    )
  }

  async ensureSession() {
    if (this.slugValue || this.pendingCreate) return
    this.pendingCreate = true
    try {
      const res = await fetch('/audio/songs', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })
      const { slug } = await res.json()
      this.slugValue = slug
      history.replaceState(null, '', `/audio/songs/${slug}`)
      this.showShareLink(slug)
      this.connectChannel(slug)
    } finally {
      this.pendingCreate = false
    }
  }

  broadcastChange(data) {
    const message = { ...data, client_id: this.clientId }
    this.ensureSession().then(() => {
      if (!this.channel) return
      if (this.channelReady) {
        this.channel.send(message)
      } else {
        this.pendingMessages.push(message)
      }
    })
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  showShareLink(slug) {
    const url  = `${location.origin}/audio/songs/${slug}`
    const link = document.createElement('a')
    link.href        = url
    link.textContent = url
    link.target      = '_blank'
    this.shareLinkTarget.innerHTML = ''
    this.shareLinkTarget.appendChild(link)
  }

  _setCollabStatus(status) {
    const el  = this.collabIndicatorTarget
    const txt = this.collabStatusTarget
    el.className = `collab-indicator ${status}`
    txt.textContent = status
  }

  _setHead(step) {
    if (this.head >= 0)
      for (let r = 0; r < ROWS; r++) this.cells[r][this.head].classList.remove('head')
    this.head = step
    for (let r = 0; r < ROWS; r++) this.cells[r][this.head].classList.add('head')
  }

  _clearHead() {
    if (this.head >= 0) {
      for (let r = 0; r < ROWS; r++) this.cells[r][this.head].classList.remove('head')
      this.head = -1
    }
    this.kickCells.forEach(c => c.classList.remove('head'))
  }
}
