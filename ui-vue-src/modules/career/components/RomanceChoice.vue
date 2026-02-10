<template>
  <Teleport to="body">
    <div class="romance-choice-overlay" v-if="showChoice">
      <div class="romance-choice-container">
        <!-- Title -->
        <div class="choice-header">
          <h1 class="choice-title">{{ $t.value('title') }}</h1>
          <p class="choice-subtitle">{{ $t.value('subtitle') }}</p>
        </div>

        <!-- Split Screen: Rook (Left) and Nova (Right) -->
        <div class="choice-split">
          <!-- ROOK - Left Side -->
          <div class="choice-side rook-side" :class="{ hovered: hoveredChoice === 'rook' }" @mouseenter="hoveredChoice = 'rook'" @mouseleave="hoveredChoice = null">
            <div class="portrait-container">
              <svg class="portrait rook-portrait" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
                <circle cx="50" cy="50" r="45" fill="#2c5aa0" />
                <circle cx="50" cy="40" r="15" fill="#fff" />
                <path d="M30 65 Q50 75 70 65" stroke="#fff" stroke-width="8" fill="none" stroke-linecap="round" />
              </svg>
            </div>
            <div class="character-info">
              <h2 class="character-name">ROOK</h2>
              <p class="character-philosophy">{{ $t.value('rook.philosophy') }}</p>
              <div class="character-quote">
                <p>"{{ $t.value('rook.quote') }}"</p>
              </div>
              <div class="final-words">
                <p>{{ $t.value('rook.finalWords') }}</p>
              </div>
            </div>
            <button class="choice-button rook-button" @click="makeChoice('rook')">
              {{ $t.value('rook.button') }}
            </button>
          </div>

          <!-- NOVA - Right Side -->
          <div class="choice-side nova-side" :class="{ hovered: hoveredChoice === 'nova' }" @mouseenter="hoveredChoice = 'nova'" @mouseleave="hoveredChoice = null">
            <div class="portrait-container">
              <svg class="portrait nova-portrait" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
                <circle cx="50" cy="50" r="45" fill="#d63031" />
                <circle cx="50" cy="40" r="15" fill="#fff" />
                <path d="M30 65 Q50 80 70 65" stroke="#fff" stroke-width="8" fill="none" stroke-linecap="round" />
              </svg>
            </div>
            <div class="character-info">
              <h2 class="character-name">NOVA</h2>
              <p class="character-philosophy">{{ $t.value('nova.philosophy') }}</p>
              <div class="character-quote">
                <p>"{{ $t.value('nova.quote') }}"</p>
              </div>
              <div class="final-words">
                <p>{{ $t.value('nova.finalWords') }}</p>
              </div>
            </div>
            <button class="choice-button nova-button" @click="makeChoice('nova')">
              {{ $t.value('nova.button') }}
            </button>
          </div>
        </div>

        <!-- Warning -->
        <div class="choice-warning">
          <svg class="warning-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
            <path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/>
          </svg>
          <p>{{ $t.value('warning') }}</p>
        </div>

        <!-- ETK-I in the Middle (background decoration) -->
        <div class="etki-backdrop">
          <p class="etki-text">ETK-I</p>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useEvents } from '@/services/events'
import { useBridge } from '@/bridge'

const events = useEvents()
const { lua } = useBridge()

// State
const showChoice = ref(false)
const hoveredChoice = ref(null)
const currentLang = ref('en') // TODO: Get from game settings

// Translations
const translations = {
  en: {
    title: "Choose Your Path",
    subtitle: "This decision will shape your journey",
    warning: "This choice is permanent and will affect the story",
    rook: {
      philosophy: "Technique • Precision • Loyalty",
      quote: "The machine speaks if you know how to listen. Respect its limits and it will take you further than reckless speed ever could.",
      finalWords: "Miller, stay with me. We'll finish the ETK-I with the craftsmanship it deserves. Together, with honor. No shortcuts, no regrets.",
      button: "Choose Rook"
    },
    nova: {
      philosophy: "Ambition • Speed • Freedom",
      quote: "Limits are for those who fear greatness. The only way forward is to push harder, faster, until the world has no choice but to notice.",
      finalWords: "Miller, come with me. We're going to leave this town behind and chase real glory. Rook will never understand what we're capable of.",
      button: "Choose Nova"
    }
  },
  es: {
    title: "Elige Tu Camino",
    subtitle: "Esta decisión dará forma a tu viaje",
    warning: "Esta elección es permanente y afectará la historia",
    rook: {
      philosophy: "Técnica • Precisión • Lealtad",
      quote: "La máquina habla si sabes escuchar. Respeta sus límites y te llevará más lejos de lo que la velocidad imprudente jamás podría.",
      finalWords: "Miller, quédate conmigo. Terminaremos el ETK-I con la artesanía que merece. Juntos, con honor. Sin atajos, sin arrepentimientos.",
      button: "Elegir a Rook"
    },
    nova: {
      philosophy: "Ambición • Velocidad • Libertad",
      quote: "Los límites son para quienes temen la grandeza. La única forma de avanzar es empujar más fuerte, más rápido, hasta que el mundo no tenga más opción que darse cuenta.",
      finalWords: "Miller, ven conmigo. Vamos a dejar este pueblo atrás y perseguir gloria real. Rook nunca entenderá de qué somos capaces.",
      button: "Elegir a Nova"
    }
  }
}

// Computed translation helper
const $t = computed(() => {
  return (key) => {
    const keys = key.split('.')
    let value = translations[currentLang.value]
    for (const k of keys) {
      if (value && value[k] !== undefined) {
        value = value[k]
      } else {
        return key // Return key if translation not found
      }
    }
    return value
  }
})

// Methods
function makeChoice(choice) {
  // Call Lua callback with choice
  lua.career_modules_mysummerNarrative.onRomanceChoice(choice)

  // Close modal
  showChoice.value = false
  hoveredChoice.value = null
}

// Events
function onShowRomanceChoice(data) {
  showChoice.value = true
}

onMounted(() => {
  events.on('mysummerShowRomanceChoice', onShowRomanceChoice)

  // Disable ESC key
  window.addEventListener('keydown', preventEscape)
})

onUnmounted(() => {
  events.off('mysummerShowRomanceChoice', onShowRomanceChoice)
  window.removeEventListener('keydown', preventEscape)
})

function preventEscape(e) {
  if (showChoice.value && e.key === 'Escape') {
    e.preventDefault()
    e.stopPropagation()
  }
}
</script>

<style scoped>
.romance-choice-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: linear-gradient(135deg, rgba(0, 0, 0, 0.95) 0%, rgba(20, 20, 30, 0.98) 100%);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10000;
  backdrop-filter: blur(10px);
  animation: fadeIn 0.5s ease-in-out;
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

.romance-choice-container {
  width: 90vw;
  max-width: 1400px;
  height: 85vh;
  display: flex;
  flex-direction: column;
  position: relative;
}

.choice-header {
  text-align: center;
  margin-bottom: 2rem;
  z-index: 2;
}

.choice-title {
  font-size: 3rem;
  font-weight: 900;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  background: linear-gradient(90deg, #ff6b6b 0%, #4ecdc4 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin: 0 0 0.5rem 0;
}

.choice-subtitle {
  font-size: 1.2rem;
  color: rgba(255, 255, 255, 0.7);
  margin: 0;
  letter-spacing: 0.05em;
}

.choice-split {
  display: flex;
  gap: 2rem;
  flex: 1;
  z-index: 2;
}

.choice-side {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 2rem;
  border-radius: 20px;
  background: rgba(255, 255, 255, 0.03);
  backdrop-filter: blur(5px);
  border: 2px solid rgba(255, 255, 255, 0.1);
  transition: all 0.3s ease;
  position: relative;
  overflow: hidden;
}

.choice-side::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  opacity: 0;
  transition: opacity 0.3s ease;
  pointer-events: none;
}

.rook-side::before {
  background: radial-gradient(circle at center, rgba(78, 205, 196, 0.15) 0%, transparent 70%);
}

.nova-side::before {
  background: radial-gradient(circle at center, rgba(255, 107, 107, 0.15) 0%, transparent 70%);
}

.choice-side.hovered {
  transform: scale(1.02);
  border-color: rgba(255, 255, 255, 0.3);
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
}

.choice-side.hovered::before {
  opacity: 1;
}

.rook-side.hovered {
  border-color: rgba(78, 205, 196, 0.6);
}

.nova-side.hovered {
  border-color: rgba(255, 107, 107, 0.6);
}

.portrait-container {
  width: 200px;
  height: 200px;
  border-radius: 50%;
  overflow: hidden;
  margin-bottom: 1.5rem;
  border: 4px solid rgba(255, 255, 255, 0.2);
  transition: all 0.3s ease;
}

.rook-side.hovered .portrait-container {
  border-color: rgba(78, 205, 196, 0.8);
  box-shadow: 0 0 30px rgba(78, 205, 196, 0.4);
}

.nova-side.hovered .portrait-container {
  border-color: rgba(255, 107, 107, 0.8);
  box-shadow: 0 0 30px rgba(255, 107, 107, 0.4);
}

.portrait {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.character-info {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 1rem;
}

.character-name {
  font-size: 2.5rem;
  font-weight: 900;
  letter-spacing: 0.2em;
  margin: 0;
}

.rook-side .character-name {
  color: #4ecdc4;
}

.nova-side .character-name {
  color: #ff6b6b;
}

.character-philosophy {
  font-size: 1rem;
  color: rgba(255, 255, 255, 0.6);
  text-transform: uppercase;
  letter-spacing: 0.15em;
  margin: 0;
}

.character-quote {
  font-style: italic;
  font-size: 1.1rem;
  color: rgba(255, 255, 255, 0.8);
  padding: 1rem;
  border-left: 3px solid rgba(255, 255, 255, 0.3);
  margin: 0.5rem 0;
}

.rook-side .character-quote {
  border-color: rgba(78, 205, 196, 0.5);
}

.nova-side .character-quote {
  border-color: rgba(255, 107, 107, 0.5);
}

.final-words {
  font-size: 0.95rem;
  color: rgba(255, 255, 255, 0.7);
  line-height: 1.6;
  padding: 0 1rem;
}

.choice-button {
  margin-top: 1.5rem;
  padding: 1rem 3rem;
  font-size: 1.3rem;
  font-weight: 700;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  border: none;
  border-radius: 50px;
  cursor: pointer;
  transition: all 0.3s ease;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
}

.rook-button {
  background: linear-gradient(135deg, #4ecdc4 0%, #2a9d8f 100%);
  color: #ffffff;
}

.rook-button:hover {
  background: linear-gradient(135deg, #5eddd4 0%, #3aaead 100%);
  box-shadow: 0 15px 40px rgba(78, 205, 196, 0.4);
  transform: translateY(-3px);
}

.nova-button {
  background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%);
  color: #ffffff;
}

.nova-button:hover {
  background: linear-gradient(135deg, #ff7b7b 0%, #ff6a62 100%);
  box-shadow: 0 15px 40px rgba(255, 107, 107, 0.4);
  transform: translateY(-3px);
}

.choice-warning {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  margin-top: 2rem;
  padding: 1.5rem;
  background: rgba(255, 193, 7, 0.1);
  border: 2px solid rgba(255, 193, 7, 0.4);
  border-radius: 15px;
  z-index: 2;
}

.warning-icon {
  width: 32px;
  height: 32px;
  color: #ffc107;
}

.choice-warning p {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 600;
  color: #ffc107;
  letter-spacing: 0.05em;
}

.etki-backdrop {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  z-index: 1;
  opacity: 0.03;
  pointer-events: none;
}

.etki-text {
  font-size: 20rem;
  font-weight: 900;
  letter-spacing: 0.2em;
  color: #ffffff;
  margin: 0;
  white-space: nowrap;
}

/* Responsive */
@media (max-width: 1200px) {
  .choice-split {
    flex-direction: column;
  }

  .choice-title {
    font-size: 2.5rem;
  }

  .character-name {
    font-size: 2rem;
  }

  .etki-text {
    font-size: 10rem;
  }
}
</style>
