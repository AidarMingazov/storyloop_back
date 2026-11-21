import { Controller } from "@hotwired/stimulus"

// "Story by voice" (7.12): records the microphone as 16 kHz mono WAV right in the browser (every speech model takes
// WAV; MediaRecorder's webm/mp4 would need converting on the server), sends it to the transcription endpoint and
// appends the text to the field — the learner can fix it before creating the story. Up to MAX_SECONDS.
const RATE = 16000
const MAX_SECONDS = 90

export default class extends Controller {
  static targets = [ "button", "field", "status" ]
  static values = { url: String, start: String, stop: String, busy: String, failed: String, denied: String }

  connect() {
    if (!navigator.mediaDevices?.getUserMedia || !(window.AudioContext || window.webkitAudioContext)) {
      this.buttonTarget.hidden = true
    }
  }

  disconnect() { this.cleanup() }

  async toggle() {
    if (this.recording) return this.finish()
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } })
    } catch {
      return this.say(this.deniedValue)
    }
    const AudioContext = window.AudioContext || window.webkitAudioContext
    this.audio = new AudioContext()
    await this.audio.resume()
    this.chunks = []
    this.source = this.audio.createMediaStreamSource(this.stream)
    // ScriptProcessor is old but works everywhere without a separate worklet file; 4096 frames per callback.
    this.processor = this.audio.createScriptProcessor(4096, 1, 1)
    this.processor.onaudioprocess = (event) => this.chunks.push(new Float32Array(event.inputBuffer.getChannelData(0)))
    this.source.connect(this.processor)
    this.processor.connect(this.audio.destination)
    this.recording = true
    this.started = Date.now()
    this.buttonTarget.setAttribute("aria-pressed", "true")
    this.tick()
    this.timer = setInterval(() => this.tick(), 500)
  }

  tick() {
    const seconds = Math.floor((Date.now() - this.started) / 1000)
    this.buttonTarget.textContent = `⏹ ${this.stopValue} · ${seconds}s`
    if (seconds >= MAX_SECONDS) this.finish()
  }

  async finish() {
    const rate = this.audio.sampleRate
    const samples = this.merge(this.chunks)
    this.cleanup()
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = this.busyValue
    try {
      const body = new FormData()
      body.append("audio", new Blob([ this.wav(this.downsample(samples, rate)) ], { type: "audio/wav" }), "voice.wav")
      const response = await fetch(this.urlValue, {
        method: "POST", body, headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content, Accept: "application/json" }
      })
      const data = await response.json()
      if (!response.ok || !data.text) throw new Error(data.error || "empty")
      const field = this.fieldTarget
      field.value = [ field.value.trim(), data.text ].filter(Boolean).join(" ").slice(0, field.maxLength > 0 ? field.maxLength : undefined)
      field.dispatchEvent(new Event("input", { bubbles: true }))
      field.focus()
      this.say("")
    } catch {
      this.say(this.failedValue)
    } finally {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = `🎙 ${this.startValue}`
    }
  }

  cleanup() {
    clearInterval(this.timer)
    this.recording = false
    this.buttonTarget?.setAttribute("aria-pressed", "false")
    this.processor?.disconnect()
    this.source?.disconnect()
    this.stream?.getTracks().forEach(track => track.stop())
    this.audio?.close()
    this.processor = this.source = this.stream = this.audio = null
  }

  say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  merge(chunks) {
    const out = new Float32Array(chunks.reduce((sum, chunk) => sum + chunk.length, 0))
    let offset = 0
    for (const chunk of chunks) { out.set(chunk, offset); offset += chunk.length }
    return out
  }

  // Averages the samples that fall into each 16 kHz slot (enough for speech).
  downsample(samples, rate) {
    if (rate === RATE) return samples
    const ratio = rate / RATE
    const out = new Float32Array(Math.floor(samples.length / ratio))
    for (let i = 0; i < out.length; i++) {
      const start = Math.floor(i * ratio), end = Math.min(Math.floor((i + 1) * ratio), samples.length)
      let sum = 0
      for (let j = start; j < end; j++) sum += samples[j]
      out[i] = sum / Math.max(end - start, 1)
    }
    return out
  }

  // 16-bit PCM WAV.
  wav(samples) {
    const buffer = new ArrayBuffer(44 + samples.length * 2)
    const view = new DataView(buffer)
    const text = (offset, string) => [ ...string ].forEach((char, i) => view.setUint8(offset + i, char.charCodeAt(0)))
    text(0, "RIFF"); view.setUint32(4, 36 + samples.length * 2, true); text(8, "WAVE")
    text(12, "fmt "); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true)
    view.setUint32(24, RATE, true); view.setUint32(28, RATE * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true)
    text(36, "data"); view.setUint32(40, samples.length * 2, true)
    samples.forEach((sample, i) => view.setInt16(44 + i * 2, Math.max(-1, Math.min(1, sample)) * 0x7fff, true))
    return buffer
  }
}
