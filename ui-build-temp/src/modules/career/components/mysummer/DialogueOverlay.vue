<template>
  <Teleport to="body">
    <Transition name="dialogue-slide">
      <div v-if="visible && currentMessage" class="dialogue-overlay">
        <div class="dialogue-box">
          <!-- Character portrait area (left side) -->
          <div class="portrait-area" :class="[currentMessage.contactId, { 'unknown': !currentMessage.isUnlocked }]">
            <div class="portrait-frame">
              <div class="portrait-image" v-if="currentMessage.isUnlocked">
                <!-- Future: actual character images -->
                <span class="portrait-letter">{{ getInitial(currentMessage.contactName) }}</span>
              </div>
              <div class="portrait-image unknown" v-else>
                <span class="portrait-letter">?</span>
              </div>
            </div>
            <div class="portrait-name">{{ currentMessage.isUnlocked ? currentMessage.contactName : '???' }}</div>
          </div>

          <!-- Message content area -->
          <div class="message-area">
            <div class="message-text" ref="messageText">
              <span class="typed-text">{{ displayedText }}</span>
              <span class="cursor" v-if="isTyping">|</span>
            </div>

            <!-- Progress dots (subtle) -->
            <div class="progress-dots" v-if="queueLength > 1">
              <span
                v-for="i in queueLength"
                :key="i"
                class="dot"
                :class="{ active: i - 1 === currentIndex, done: i - 1 < currentIndex }"
              ></span>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useEvents } from '@/services/events'

const events = useEvents()

// State
const visible = ref(false)
const messageQueue = ref([])
const currentIndex = ref(0)
const displayedText = ref('')
const isTyping = ref(false)
const typingSpeed = 25 // ms per character
const autoAdvanceDelay = 3000 // ms to wait after typing completes before auto-advancing
let autoAdvanceTimer = null

// Computed
const currentMessage = computed(() => messageQueue.value[currentIndex.value] || null)
const queueLength = computed(() => messageQueue.value.length)

// Methods
const getInitial = (name) => {
  return name ? name.charAt(0).toUpperCase() : '?'
}

let typingInterval = null

const typeText = (text) => {
  isTyping.value = true
  displayedText.value = ''
  let charIndex = 0

  if (typingInterval) clearInterval(typingInterval)
  if (autoAdvanceTimer) clearTimeout(autoAdvanceTimer)

  typingInterval = setInterval(() => {
    if (charIndex < text.length) {
      displayedText.value += text.charAt(charIndex)
      charIndex++
    } else {
      clearInterval(typingInterval)
      typingInterval = null
      isTyping.value = false

      // Auto-advance after delay
      autoAdvanceTimer = setTimeout(() => {
        advanceDialogue()
      }, autoAdvanceDelay)
    }
  }, typingSpeed)
}

const skipTyping = () => {
  if (typingInterval) {
    clearInterval(typingInterval)
    typingInterval = null
  }
  if (autoAdvanceTimer) {
    clearTimeout(autoAdvanceTimer)
    autoAdvanceTimer = null
  }
  if (currentMessage.value) {
    displayedText.value = currentMessage.value.content
  }
  isTyping.value = false

  // Start auto-advance timer after skipping
  autoAdvanceTimer = setTimeout(() => {
    advanceDialogue()
  }, autoAdvanceDelay)
}

const advanceDialogue = () => {
  // If still typing, skip to end
  if (isTyping.value) {
    skipTyping()
    return
  }

  // Move to next message
  if (currentIndex.value < messageQueue.value.length - 1) {
    currentIndex.value++
    typeText(currentMessage.value.content)
  } else {
    // End of queue
    closeDialogue()
  }
}

const closeDialogue = () => {
  visible.value = false
  if (typingInterval) {
    clearInterval(typingInterval)
    typingInterval = null
  }
  if (autoAdvanceTimer) {
    clearTimeout(autoAdvanceTimer)
    autoAdvanceTimer = null
  }
  // Clear after animation
  setTimeout(() => {
    messageQueue.value = []
    currentIndex.value = 0
    displayedText.value = ''
  }, 300)
}

const showMessage = (message) => {
  messageQueue.value.push(message)

  if (!visible.value) {
    visible.value = true
    currentIndex.value = messageQueue.value.length - 1
    typeText(message.content)
  }
}

const showMessages = (messages) => {
  if (!messages || messages.length === 0) return

  messageQueue.value = messages
  currentIndex.value = 0
  visible.value = true
  typeText(messages[0].content)
}

// Event handlers for Lua integration
const handleShowDialogue = (data) => {
  if (data.messages && data.messages.length > 0) {
    showMessages(data.messages)
  } else if (data.message) {
    showMessage(data.message)
  }
}

const handleHideDialogue = () => {
  closeDialogue()
}

// Keyboard support (only Escape to dismiss)
const handleKeydown = (e) => {
  if (!visible.value) return

  if (e.key === 'Escape') {
    e.preventDefault()
    closeDialogue()
  }
}

// Lifecycle
onMounted(() => {
  // Register event listeners for Lua guihooks
  events.on('mysummerDialogueShow', handleShowDialogue)
  events.on('mysummerDialogueHide', handleHideDialogue)

  // Keyboard support
  document.addEventListener('keydown', handleKeydown)
})

onUnmounted(() => {
  events.off('mysummerDialogueShow', handleShowDialogue)
  events.off('mysummerDialogueHide', handleHideDialogue)
  document.removeEventListener('keydown', handleKeydown)

  if (typingInterval) clearInterval(typingInterval)
  if (autoAdvanceTimer) clearTimeout(autoAdvanceTimer)
})

// Watch for message changes
watch(currentMessage, (newMsg) => {
  if (newMsg && visible.value) {
    typeText(newMsg.content)
  }
})

// Expose for external use
defineExpose({
  showMessage,
  showMessages,
  closeDialogue,
  visible
})
</script>

<style scoped lang="scss">
// Variables
$bg-dark: rgba(0, 0, 0, 0.75);
$bg-darker: rgba(0, 0, 0, 0.85);
$text-primary: #ffffff;
$text-secondary: rgba(255, 255, 255, 0.6);
$accent-green: #25D366;
$border-glow: rgba(37, 211, 102, 0.2);

// Contact colors
$ghost-color: #9b59b6;
$techie-color: #3498db;
$muscle-color: #e74c3c;
$import-color: #f39c12;
$shadow-color: #2c3e50;
$system-color: #7f8c8d;
$unknown-color: #555;

.dialogue-overlay {
  position: fixed;
  bottom: 30px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 9998;
  width: 85%;
  max-width: 750px;
  pointer-events: none; // Allow clicking through
}

.dialogue-box {
  display: flex;
  align-items: stretch;
  background: $bg-dark;
  border: 1px solid $border-glow;
  border-radius: 10px;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
  overflow: hidden;
  min-height: 90px;
  pointer-events: auto; // But the box itself is clickable
}

// Portrait area
.portrait-area {
  width: 100px;
  min-width: 100px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 12px;
  background: $bg-darker;
  border-right: 1px solid rgba(255, 255, 255, 0.08);

  // Contact-specific colors
  &.ghost {
    background: linear-gradient(135deg, rgba($ghost-color, 0.2) 0%, $bg-darker 100%);
    .portrait-frame { border-color: rgba($ghost-color, 0.7); }
  }
  &.techie {
    background: linear-gradient(135deg, rgba($techie-color, 0.2) 0%, $bg-darker 100%);
    .portrait-frame { border-color: rgba($techie-color, 0.7); }
  }
  &.muscle {
    background: linear-gradient(135deg, rgba($muscle-color, 0.2) 0%, $bg-darker 100%);
    .portrait-frame { border-color: rgba($muscle-color, 0.7); }
  }
  &.import {
    background: linear-gradient(135deg, rgba($import-color, 0.2) 0%, $bg-darker 100%);
    .portrait-frame { border-color: rgba($import-color, 0.7); }
  }
  &.shadow {
    background: linear-gradient(135deg, rgba($shadow-color, 0.3) 0%, $bg-darker 100%);
    .portrait-frame { border-color: rgba($shadow-color, 0.7); }
  }
  &.system {
    background: linear-gradient(135deg, rgba($system-color, 0.2) 0%, $bg-darker 100%);
    .portrait-frame { border-color: rgba($system-color, 0.7); }
  }
  &.unknown {
    .portrait-frame { border-color: rgba($unknown-color, 0.7); }
    .portrait-image { background: $unknown-color; }
  }
}

.portrait-frame {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: 2px solid $accent-green;
  overflow: hidden;
  margin-bottom: 6px;
}

.portrait-image {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #2a2a2a 0%, #1a1a1a 100%);

  &.unknown {
    background: linear-gradient(135deg, #333 0%, #222 100%);
  }
}

.portrait-letter {
  font-size: 1.6rem;
  font-weight: 700;
  color: $text-primary;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.5);
}

.portrait-name {
  font-size: 0.7rem;
  font-weight: 600;
  color: $text-secondary;
  text-align: center;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

// Message area
.message-area {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 14px 18px;
}

.message-text {
  font-size: 0.95rem;
  line-height: 1.5;
  color: $text-primary;

  .typed-text {
    white-space: pre-wrap;
  }

  .cursor {
    display: inline-block;
    animation: blink 0.6s infinite;
    color: $accent-green;
    font-weight: bold;
    margin-left: 2px;
  }
}

// Progress dots
.progress-dots {
  display: flex;
  gap: 6px;
  margin-top: 10px;

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.2);
    transition: all 0.3s;

    &.active {
      background: $accent-green;
      box-shadow: 0 0 6px $accent-green;
    }

    &.done {
      background: rgba($accent-green, 0.4);
    }
  }
}

// Animations
@keyframes blink {
  0%, 50% { opacity: 1; }
  51%, 100% { opacity: 0; }
}

@keyframes pulse {
  0%, 100% { opacity: 0.7; }
  50% { opacity: 1; }
}

// Transition
.dialogue-slide-enter-active,
.dialogue-slide-leave-active {
  transition: all 0.3s ease;
}

.dialogue-slide-enter-from {
  opacity: 0;
  transform: translateX(-50%) translateY(30px);
}

.dialogue-slide-leave-to {
  opacity: 0;
  transform: translateX(-50%) translateY(30px);
}
</style>
