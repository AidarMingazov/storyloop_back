// Plays recorded audio when we have it (TTS files arrive in waves 5–6); until then the browser's
// speech synthesis reads the text.
const VOICES = { en: "en-US", ko: "ko-KR", ru: "ru-RU", ja: "ja-JP", pt: "pt-BR" }
let player = null

export function canSpeak() {
  return "speechSynthesis" in window
}

export function speak(text, lang, audioUrl = null) {
  stopSpeaking()
  if (audioUrl) {
    player = new Audio(audioUrl)
    player.play().catch(() => {})
    return
  }
  if (!canSpeak()) return
  const utterance = new SpeechSynthesisUtterance(text)
  utterance.lang = VOICES[lang] || lang
  utterance.rate = 0.9
  window.speechSynthesis.speak(utterance)
}

export function stopSpeaking() {
  player?.pause()
  player = null
  if (canSpeak()) window.speechSynthesis.cancel()
}
