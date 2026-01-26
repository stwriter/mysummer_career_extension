<template>
  <div class="phase-overlay" @click.self="closeTransition">
    <div class="phase-container" :class="{ 'final': isFinalLevel }">
      <!-- Chapter header -->
      <div class="chapter-header">
        <div class="chapter-line"></div>
        <span class="chapter-label">{{ chapterLabel }}</span>
        <div class="chapter-line"></div>
      </div>

      <!-- Chapter number and title -->
      <div class="chapter-title-section">
        <h2 class="chapter-number">{{ chapterNumber }}</h2>
        <h1 class="chapter-name" :class="{ 'golden': isFinalLevel }">{{ newLevelName }}</h1>
      </div>

      <!-- Narrative text -->
      <div class="narrative-section">
        <p class="narrative-text">{{ newLevelIntro }}</p>
      </div>

      <!-- Completion message from previous chapter (if any) -->
      <div v-if="completionText" class="completion-section">
        <div class="completion-divider"></div>
        <p class="completion-text">"{{ completionText }}"</p>
      </div>

      <!-- Final level special message -->
      <div v-if="isFinalLevel" class="final-message">
        <div class="trophy-icon">🏆</div>
        <p class="grandpa-message">{{ grandpaMessage }}</p>
      </div>

      <!-- Continue button -->
      <button class="continue-button" :class="{ 'golden-btn': isFinalLevel }" @click="closeTransition">
        {{ buttonText }}
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  completedLevel: { type: Number, default: 0 },
  completionText: { type: String, default: '' },
  newLevel: { type: Number, default: 1 },
  newLevelName: { type: String, default: '' },
  newLevelIntro: { type: String, default: '' },
  isFinalLevel: { type: Boolean, default: false }
})

const emit = defineEmits(['return'])

// Detect language from the intro text (simple heuristic)
const isSpanish = computed(() => {
  return props.newLevelIntro && (
    props.newLevelIntro.includes('El ') ||
    props.newLevelIntro.includes('es ') ||
    props.newLevelIntro.includes('tu ') ||
    props.newLevelIntro.includes('abuelo') ||
    props.newLevelIntro.includes('eres ') ||
    props.newLevelIntro.includes('hora ')
  )
})

const chapterLabel = computed(() => isSpanish.value ? 'CAPITULO' : 'CHAPTER')
const chapterNumber = computed(() => {
  const romanNumerals = ['I', 'II', 'III', 'IV', 'V']
  return romanNumerals[props.newLevel - 1] || props.newLevel.toString()
})
const buttonText = computed(() => isSpanish.value ? 'Continuar' : 'Continue')
const grandpaMessage = computed(() =>
  isSpanish.value
    ? '"Sabía que lo conseguirías, chaval. Ahora ve y gana The Big One."'
    : '"I knew you could do it, kid. Now go win The Big One."'
)

function closeTransition() {
  emit('return', true)
}
</script>

<style scoped lang="scss">
$handwritten-font: 'Segoe Script', 'Bradley Hand', 'Comic Sans MS', cursive, sans-serif;
$cinematic-font: 'Georgia', 'Times New Roman', serif;

.phase-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.95);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 99999;
  padding: 20px;
  pointer-events: all;
}

.phase-container {
  max-width: 700px;
  width: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 30px;
  animation: fadeInUp 1s ease-out;
  padding: 50px 60px;

  &.final {
    .chapter-label {
      color: #ffd700;
    }
    .chapter-line {
      background: linear-gradient(90deg, transparent, #ffd700, transparent);
    }
  }
}

@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(40px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

// Chapter header with decorative lines
.chapter-header {
  display: flex;
  align-items: center;
  gap: 20px;
  width: 100%;
  animation: fadeIn 1.2s ease-out 0.3s both;
}

.chapter-line {
  flex: 1;
  height: 1px;
  background: linear-gradient(90deg, transparent, #666, transparent);
}

.chapter-label {
  font-family: $cinematic-font;
  font-size: 14px;
  color: #888;
  letter-spacing: 8px;
  text-transform: uppercase;
}

// Chapter title section
.chapter-title-section {
  text-align: center;
  animation: fadeIn 1.2s ease-out 0.5s both;
}

.chapter-number {
  font-family: $cinematic-font;
  font-size: 48px;
  font-weight: normal;
  color: #666;
  margin: 0 0 10px 0;
  letter-spacing: 6px;
}

.chapter-name {
  font-family: $cinematic-font;
  font-size: 36px;
  font-weight: normal;
  color: #fff;
  margin: 0;
  letter-spacing: 4px;
  text-transform: uppercase;

  &.golden {
    color: #ffd700;
    text-shadow: 0 0 30px rgba(255, 215, 0, 0.4);
  }
}

// Narrative text
.narrative-section {
  max-width: 550px;
  animation: fadeIn 1.2s ease-out 0.8s both;
}

.narrative-text {
  font-family: $cinematic-font;
  font-size: 20px;
  color: #bbb;
  text-align: center;
  line-height: 1.8;
  font-style: italic;
  margin: 0;
}

// Completion section (quote from previous chapter)
.completion-section {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 15px;
  margin-top: 10px;
  animation: fadeIn 1.2s ease-out 1s both;
}

.completion-divider {
  width: 60px;
  height: 1px;
  background: #444;
}

.completion-text {
  font-family: $handwritten-font;
  font-size: 18px;
  color: #777;
  text-align: center;
  font-style: italic;
  max-width: 450px;
}

// Final level special section
.final-message {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 15px;
  margin-top: 20px;
  padding: 25px 40px;
  background: rgba(255, 215, 0, 0.08);
  border-radius: 4px;
  border: 1px solid rgba(255, 215, 0, 0.2);
  animation: fadeIn 1.2s ease-out 1.2s both;
}

.trophy-icon {
  font-size: 56px;
  animation: pulse 2s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.1); }
}

.grandpa-message {
  font-family: $handwritten-font;
  font-size: 22px;
  color: #ffd700;
  text-align: center;
  font-style: italic;
}

// Continue button
.continue-button {
  margin-top: 30px;
  padding: 16px 50px;
  font-family: $cinematic-font;
  font-size: 16px;
  font-weight: normal;
  background: transparent;
  color: #888;
  border: 1px solid #444;
  border-radius: 0;
  cursor: pointer;
  transition: all 0.3s ease;
  text-transform: uppercase;
  letter-spacing: 4px;
  animation: fadeIn 1.2s ease-out 1.4s both;

  &:hover {
    color: #fff;
    border-color: #888;
    background: rgba(255, 255, 255, 0.05);
  }

  &.golden-btn {
    color: #ffd700;
    border-color: #ffd700;

    &:hover {
      background: rgba(255, 215, 0, 0.1);
      box-shadow: 0 0 20px rgba(255, 215, 0, 0.2);
    }
  }
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
</style>
