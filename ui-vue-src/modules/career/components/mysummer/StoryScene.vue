<template>
  <div class="story-scene" @click.self="handleContinue">
    <div class="scene-frame">
      <div class="scene-portrait">
        <div class="portrait-mask">
          <img
            :src="avatarSrc"
            :alt="`${contactName} - ${emotion}`"
            class="portrait-img"
          />
        </div>
        <div class="portrait-name">{{ contactName }}</div>
      </div>

      <div class="scene-copy">
        <div v-if="title" class="scene-title">{{ title }}</div>

        <div class="scene-text" @click="handleContinue">
          <span class="typed-text">{{ displayedText }}</span>
          <span v-if="isTyping" class="cursor">|</span>
        </div>

        <div class="scene-progress" v-if="messages.length > 1 && !showChoices">
          <span
            v-for="(item, index) in messages"
            :key="index"
            class="dot"
            :class="{ active: index === messageIndex, done: index < messageIndex }"
          ></span>
        </div>

        <div class="scene-actions" v-if="showActions">
          <button
            v-for="choice in visibleChoices"
            :key="choice.value"
            class="scene-button"
            type="button"
            @click="handleChoice(choice)"
          >
            {{ choice.label }}
          </button>

          <button
            v-if="showContinue"
            class="scene-button continue"
            type="button"
            @click="handleContinue"
          >
            {{ continueButtonLabel }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from "vue"
import { getContactImage, EMOTIONS } from "../../utils/contactImages"

const props = defineProps({
  sceneId: { type: String, default: "" },
  contactId: { type: String, required: true },
  contactName: { type: String, required: true },
  emotion: { type: String, default: EMOTIONS.STANDARD },
  title: { type: String, default: "" },
  text: { type: String, required: true },
  texts: { type: Array, default: null },
  choices: { type: Array, default: null },
  continueLabel: { type: String, default: "" },
  language: { type: String, default: "" }
})

const emit = defineEmits(["return"])

const displayedText = ref("")
const isTyping = ref(false)
const typingSpeed = 24
let typingInterval = null
const messageIndex = ref(0)

const normalizedMessages = computed(() => {
  const source = Array.isArray(props.texts) && props.texts.length > 0 ? props.texts : [props.text]
  return source.map((entry) => {
    if (entry && typeof entry === "object" && entry.text) {
      return { text: entry.text, emotion: entry.emotion || null }
    }
    return { text: String(entry ?? ""), emotion: null }
  })
})

const currentMessage = computed(() => normalizedMessages.value[messageIndex.value] || { text: "", emotion: null })
const currentEmotion = computed(() => currentMessage.value.emotion || props.emotion)
const avatarSrc = computed(() => getContactImage(props.contactId, currentEmotion.value))

const isSpanish = computed(() => {
  if (props.language) return props.language.startsWith("es")
  const sample = currentMessage.value.text || ""
  return sample.includes(" el ") || sample.includes(" la ") || sample.includes(" que ")
})

const resolvedContinueLabel = computed(() => {
  if (props.continueLabel) return props.continueLabel
  return isSpanish.value ? "Continuar" : "Continue"
})

const messages = computed(() => normalizedMessages.value)
const isLastMessage = computed(() => messageIndex.value >= normalizedMessages.value.length - 1)
const hasChoices = computed(() => Array.isArray(props.choices) && props.choices.length > 0)
const showActions = computed(() => !isTyping.value)
const showChoices = computed(() => !isTyping.value && hasChoices.value && isLastMessage.value)
const showContinue = computed(() => !isTyping.value && (!hasChoices.value || !isLastMessage.value))
const visibleChoices = computed(() => (showChoices.value ? props.choices : []))
const continueButtonLabel = computed(() => {
  if (!isLastMessage.value) return isSpanish.value ? "Siguiente" : "Next"
  return resolvedContinueLabel.value
})

const typeText = (text) => {
  if (typingInterval) clearInterval(typingInterval)
  displayedText.value = ""
  isTyping.value = true
  let index = 0

  typingInterval = setInterval(() => {
    if (index < text.length) {
      displayedText.value += text.charAt(index)
      index += 1
    } else {
      clearInterval(typingInterval)
      typingInterval = null
      isTyping.value = false
    }
  }, typingSpeed)
}

const skipTyping = () => {
  if (typingInterval) {
    clearInterval(typingInterval)
    typingInterval = null
  }
  displayedText.value = currentMessage.value.text || ""
  isTyping.value = false
}

const handleContinue = () => {
  if (isTyping.value) {
    skipTyping()
    return
  }

  if (!isLastMessage.value) {
    messageIndex.value += 1
    typeText(currentMessage.value.text || "")
    return
  }

  if (hasChoices.value) {
    return
  }

  emit("return", { sceneId: props.sceneId })
}

const handleChoice = (choice) => {
  emit("return", { sceneId: props.sceneId, choice: choice.value })
}

const handleKeydown = (event) => {
  if (event.key === "Escape") {
    event.preventDefault()
    handleContinue()
    return
  }

  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault()
    handleContinue()
  }
}

onMounted(() => {
  messageIndex.value = 0
  typeText(currentMessage.value.text || "")
  document.addEventListener("keydown", handleKeydown)
})

onUnmounted(() => {
  if (typingInterval) clearInterval(typingInterval)
  document.removeEventListener("keydown", handleKeydown)
})

watch(() => messages.value, (newMessages) => {
  if (!newMessages || newMessages.length === 0) return
  messageIndex.value = 0
  typeText(currentMessage.value.text || "")
})
</script>

<style scoped lang="scss">
$bg: rgba(0, 0, 0, 0.96);
$panel: rgba(12, 12, 16, 0.85);
$text-main: #f2f2f2;
$text-dim: rgba(255, 255, 255, 0.6);
$accent: #e91e63;

.story-scene {
  position: fixed;
  inset: 0;
  background: $bg;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 12000;
  padding: 32px;
}

.scene-frame {
  width: min(1100px, 92vw);
  min-height: 460px;
  display: grid;
  grid-template-columns: 360px 1fr;
  gap: 36px;
  padding: 32px;
  background: $panel;
  border: 1px solid rgba(255, 255, 255, 0.06);
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.5);
  animation: sceneFadeIn 0.6s ease-out;

  @media (max-width: 900px) {
    grid-template-columns: 1fr;
    gap: 20px;
  }
}

.scene-portrait {
  display: flex;
  flex-direction: column;
  gap: 16px;
  align-items: flex-start;
}

.portrait-mask {
  width: 100%;
  aspect-ratio: 4 / 5;
  overflow: hidden;
  clip-path: polygon(0 0, 100% 0, 85% 100%, 0 100%);
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: #111;
}

.portrait-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: center;
  filter: saturate(0.9) contrast(1.05);
}

.portrait-name {
  font-family: "Bebas Neue", "Oswald", "Arial Narrow", sans-serif;
  font-size: 22px;
  letter-spacing: 3px;
  text-transform: uppercase;
  color: $text-dim;
}

.scene-copy {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  gap: 28px;
}

.scene-title {
  font-family: "Bebas Neue", "Oswald", "Arial Narrow", sans-serif;
  font-size: 28px;
  letter-spacing: 4px;
  color: $text-dim;
  text-transform: uppercase;
}

.scene-text {
  font-family: "Georgia", "Times New Roman", serif;
  font-size: 20px;
  line-height: 1.7;
  color: $text-main;
  min-height: 180px;
  cursor: pointer;
}

.typed-text {
  white-space: pre-wrap;
}

.cursor {
  display: inline-block;
  margin-left: 4px;
  color: $accent;
  animation: blink 0.7s infinite;
}

.scene-actions {
  display: flex;
  flex-direction: column;
  gap: 10px;
  align-items: flex-start;
  pointer-events: auto;
}

.scene-progress {
  display: flex;
  gap: 8px;
  align-items: center;
}

.scene-progress .dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.2);
  transition: all 0.25s ease;
}

.scene-progress .dot.active {
  background: $accent;
  box-shadow: 0 0 8px rgba(233, 30, 99, 0.4);
}

.scene-progress .dot.done {
  background: rgba(233, 30, 99, 0.35);
}

.scene-button {
  min-width: 220px;
  justify-content: flex-start;
  padding: 12px 18px;
  font-size: 14px;
  letter-spacing: 1px;
  text-transform: uppercase;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.3);
  color: $text-main;
  cursor: pointer;
  transition: all 0.2s ease;

  &.continue {
    border-color: rgba(255, 255, 255, 0.6);
  }

  &:hover {
    background: rgba(255, 255, 255, 0.12);
    border-color: rgba(255, 255, 255, 0.6);
  }
}

@keyframes sceneFadeIn {
  from {
    opacity: 0;
    transform: translateY(24px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes blink {
  0%, 50% { opacity: 1; }
  51%, 100% { opacity: 0; }
}
</style>
