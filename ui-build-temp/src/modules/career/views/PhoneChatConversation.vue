<template>
  <PhoneWrapper :app-name="contactName" status-font-color="#25D366" status-blend-mode="">
    <div class="conversation-screen">
      <!-- Header -->
      <div class="conv-header">
        <button class="back-btn" @click="goBack">&lt;</button>
        <div class="contact-info">
          <div class="contact-avatar" :class="{ unlocked: contact?.isUnlocked }">
            {{ contact?.isUnlocked ? contactName.charAt(0) : '?' }}
          </div>
          <div class="contact-details">
            <div class="contact-name">{{ contactName }}</div>
            <div class="contact-status" v-if="contact?.isTyping">{{ $t('mysummer.chat.ui.typing') }}</div>
            <div class="contact-status" v-else-if="contact?.specialty">{{ contact.specialty }}</div>
          </div>
        </div>
      </div>

      <!-- Messages -->
      <div class="messages-container" ref="messagesContainer">
        <div v-if="loading" class="loading-messages">{{ $t('mysummer.chat.ui.loading') }}</div>

        <div v-else class="messages-list">
          <div
            v-for="msg in messages"
            :key="msg.id"
            class="message-wrapper"
            :class="msg.senderType"
          >
            <div class="message-bubble" :class="[msg.senderType, { system: msg.senderType === 'system' }]">
              <div class="message-content">{{ msg.content }}</div>

              <!-- Mission offer action -->
              <div v-if="msg.actionType === 'mission_offer' && !msg.actionCompleted" class="message-action">
                <button
                  class="action-btn accept"
                  @click="acceptMission(msg)"
                  :disabled="actionLoading"
                >
                  {{ actionLoading ? $t('mysummer.chat.actions.starting') : $t('mysummer.chat.actions.acceptJob') }}
                </button>
              </div>

              <!-- Surveillance quiz options -->
              <div v-if="msg.actionType === 'surveillance_quiz' && msg.actionData?.quizOptions && !msg.actionCompleted" class="message-action quiz">
                <div class="quiz-label">{{ $t('mysummer.chat.actions.whereDidTheyGo') }}</div>
                <button
                  v-for="(option, idx) in msg.actionData.quizOptions"
                  :key="idx"
                  class="action-btn quiz-option"
                  @click="answerQuiz(msg, idx)"
                  :disabled="actionLoading"
                >
                  {{ option }}
                </button>
              </div>

              <div class="message-time">{{ formatTime(msg.timestamp) }}</div>
            </div>
          </div>

          <!-- Typing indicator -->
          <div v-if="isTyping" class="message-wrapper contact">
            <div class="message-bubble contact typing">
              <span class="typing-dots">
                <span></span><span></span><span></span>
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- Choices (when dialogue has pending choices) -->
      <div v-if="pendingChoices && pendingChoices.length > 0" class="choices-container">
        <button
          v-for="choice in pendingChoices"
          :key="choice.id"
          class="choice-btn"
          @click="selectChoice(choice)"
          :disabled="sendingChoice"
        >
          {{ choice.text }}
        </button>
      </div>

      <!-- Start Dialogue Button (when no active dialogue) -->
      <div v-else-if="canStartDialogue && !hasActiveDialogue" class="start-dialogue-container">
        <button
          class="start-dialogue-btn"
          @click="startDialogue"
          :disabled="startingDialogue"
        >
          {{ startingDialogue ? $t('mysummer.chat.actions.starting') : $t('mysummer.chat.ui.startConversation') }}
        </button>
      </div>

      <!-- Input area (for future free-text, currently disabled) -->
      <div v-else class="input-container disabled">
        <span class="input-placeholder">{{ $t('mysummer.chat.ui.selectResponse') }}</span>
      </div>
    </div>
  </PhoneWrapper>
</template>

<script setup>
import PhoneWrapper from "./PhoneWrapper.vue"
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'

const router = useRouter()
const route = useRoute()

const props = defineProps({
  contactId: {
    type: String,
    required: true
  }
})

const messagesContainer = ref(null)
const messages = ref([])
const contact = ref(null)
const pendingChoices = ref([])
const loading = ref(true)
const isTyping = ref(false)
const sendingChoice = ref(false)
const startingDialogue = ref(false)
const hasActiveDialogue = ref(false)
const canStartDialogue = ref(false)
const actionLoading = ref(false)

const contactName = computed(() => {
  if (!contact.value) return 'Loading...'
  return contact.value.isUnlocked ? contact.value.displayName : '???'
})

const formatTime = (timestamp) => {
  if (!timestamp) return ""
  const date = new Date(timestamp * 1000)
  return date.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })
}

const scrollToBottom = () => {
  nextTick(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
    }
  })
}

const goBack = () => {
  router.push('/career/phone-chat')
}

const loadConversation = () => {
  loading.value = true
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerChat.getConversation("${props.contactId}")`, (result) => {
      if (result) {
        messages.value = result.conversation?.messages || []
        contact.value = result.contact
        pendingChoices.value = result.pendingChoices || []
      }
      loading.value = false
      scrollToBottom()
    })

    // Check if dialogue is available
    window.bngApi.engineLua(`career_modules_mysummerChat.hasAvailableDialogue("${props.contactId}")`, (result) => {
      canStartDialogue.value = result === true
    })

    // Check dialogue state
    window.bngApi.engineLua(`career_modules_mysummerChat.getDialogueState("${props.contactId}")`, (result) => {
      if (result) {
        hasActiveDialogue.value = result.isActive
        if (result.pendingChoices) {
          pendingChoices.value = result.pendingChoices
        }
      }
    })

    // Mark as read
    window.bngApi.engineLua(`career_modules_mysummerChat.markAsRead("${props.contactId}")`)
  } else {
    loading.value = false
  }
}

const startDialogue = () => {
  if (!window.bngApi || startingDialogue.value) return

  startingDialogue.value = true
  window.bngApi.engineLua(`career_modules_mysummerChat.startDialogue("${props.contactId}")`, (result) => {
    startingDialogue.value = false
    if (result && result.success) {
      hasActiveDialogue.value = true
      if (result.choices) {
        pendingChoices.value = result.choices
      }
      // Reload conversation to get new messages
      loadConversation()
    } else if (result && result.error === 'cooldown') {
      // Show cooldown message
      console.log('Conversation on cooldown:', result.remainingTime)
    }
  })
}

const selectChoice = (choice) => {
  if (!window.bngApi || sendingChoice.value) return

  sendingChoice.value = true
  window.bngApi.engineLua(`career_modules_mysummerChat.continueDialogue("${props.contactId}", "${choice.id}")`, (result) => {
    sendingChoice.value = false
    if (result && result.success) {
      if (result.choices) {
        pendingChoices.value = result.choices
      } else {
        pendingChoices.value = []
      }
      if (result.ended) {
        hasActiveDialogue.value = false
        canStartDialogue.value = false // Refresh this
        window.bngApi.engineLua(`career_modules_mysummerChat.hasAvailableDialogue("${props.contactId}")`, (available) => {
          canStartDialogue.value = available === true
        })
      }
      // Reload to get updated messages
      loadConversation()
    }
  })
}

// Mission actions
const acceptMission = (msg) => {
  if (!window.bngApi || actionLoading.value) return

  const missionId = msg.actionData?.missionId
  if (!missionId) {
    console.error('No mission ID in message')
    return
  }

  actionLoading.value = true
  window.bngApi.engineLua(`career_modules_mysummerMissions.startMission("${missionId}")`, (result) => {
    actionLoading.value = false
    if (result) {
      // Mark message action as completed locally
      msg.actionCompleted = true
      // Close phone and start mission
      window.bngApi.engineLua("guihooks.trigger('closePhone')")
    }
  })
}

const answerQuiz = (msg, answerIndex) => {
  if (!window.bngApi || actionLoading.value) return

  actionLoading.value = true
  // Quiz answer is 1-indexed for Lua
  const luaIndex = answerIndex + 1
  window.bngApi.engineLua(`career_modules_mysummerMissions.answerSurveillanceQuiz(${luaIndex})`, (result) => {
    actionLoading.value = false
    // Mark as completed
    msg.actionCompleted = true
    // Close phone
    window.bngApi.engineLua("guihooks.trigger('closePhone')")
  })
}

// Event handlers
const handleConversationUpdated = (data) => {
  if (data.contactId === props.contactId) {
    loadConversation()
  }
}

const handleNewMessage = (data) => {
  if (data.contactId === props.contactId) {
    loadConversation()
  }
}

const handleTyping = (data) => {
  if (data.contactId === props.contactId) {
    isTyping.value = data.isTyping
    if (data.isTyping) {
      scrollToBottom()
    }
  }
}

const handleChoices = (data) => {
  if (data.contactId === props.contactId) {
    pendingChoices.value = data.choices || []
  }
}

onMounted(() => {
  loadConversation()

  if (window.bngApi) {
    window.bngApi.on("mysummerChatConversationUpdated", handleConversationUpdated)
    window.bngApi.on("mysummerChatNewMessage", handleNewMessage)
    window.bngApi.on("mysummerChatTyping", handleTyping)
    window.bngApi.on("mysummerChatChoices", handleChoices)
  }
})

onUnmounted(() => {
  if (window.bngApi) {
    window.bngApi.off("mysummerChatConversationUpdated", handleConversationUpdated)
    window.bngApi.off("mysummerChatNewMessage", handleNewMessage)
    window.bngApi.off("mysummerChatTyping", handleTyping)
    window.bngApi.off("mysummerChatChoices", handleChoices)
  }
})

// Watch for messages changes to scroll
watch(messages, () => {
  scrollToBottom()
})
</script>

<style scoped lang="scss">
$chat-green: #25D366;
$chat-dark: #0d1418;
$chat-darker: #0b141a;
$chat-gray: #8696a0;
$chat-light: #e9edef;
$chat-bubble-out: #005c4b;
$chat-bubble-in: #202c33;
$chat-border: #222d34;

.conversation-screen {
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  color: $chat-light;
}

.conv-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 60px 12px 12px;
  background: $chat-darker;
  border-bottom: 1px solid $chat-border;
}

.back-btn {
  background: transparent;
  border: none;
  color: $chat-gray;
  font-size: 1.5rem;
  cursor: pointer;
  padding: 4px 8px;

  &:hover {
    color: $chat-light;
  }
}

.contact-info {
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 1;
}

.contact-avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: $chat-border;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.1rem;
  font-weight: bold;
  color: $chat-gray;

  &.unlocked {
    background: $chat-green;
    color: white;
  }
}

.contact-details {
  flex: 1;
}

.contact-name {
  font-size: 1rem;
  font-weight: 600;
  color: $chat-light;
}

.contact-status {
  font-size: 0.75rem;
  color: $chat-gray;
}

.messages-container {
  flex: 1;
  overflow-y: auto;
  padding: 12px;
  background: $chat-dark;
  display: flex;
  flex-direction: column;
}

.loading-messages {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: $chat-gray;
}

.messages-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.message-wrapper {
  display: flex;
  margin-bottom: 2px;

  &.player {
    justify-content: flex-end;
  }

  &.contact {
    justify-content: flex-start;
  }

  &.system {
    justify-content: center;
  }
}

.message-bubble {
  max-width: 80%;
  padding: 8px 12px;
  border-radius: 8px;
  position: relative;

  &.player {
    background: $chat-bubble-out;
    border-bottom-right-radius: 2px;
  }

  &.contact {
    background: $chat-bubble-in;
    border-bottom-left-radius: 2px;
  }

  &.system {
    background: rgba(100, 100, 100, 0.3);
    font-size: 0.75rem;
    color: $chat-gray;
    padding: 6px 16px;
    border-radius: 16px;
  }

  &.typing {
    padding: 12px 16px;
  }
}

.message-content {
  font-size: 0.85rem;
  line-height: 1.4;
  word-wrap: break-word;
}

.message-time {
  font-size: 0.6rem;
  color: rgba(255, 255, 255, 0.5);
  text-align: right;
  margin-top: 4px;
}

// Message actions (mission offers, quiz)
.message-action {
  margin-top: 10px;
  padding-top: 8px;
  border-top: 1px solid rgba(255, 255, 255, 0.1);

  &.quiz {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
}

.quiz-label {
  font-size: 0.75rem;
  color: $chat-green;
  font-weight: 600;
  margin-bottom: 4px;
}

.action-btn {
  padding: 10px 16px;
  border-radius: 6px;
  font-size: 0.8rem;
  cursor: pointer;
  transition: all 0.2s;
  border: none;

  &.accept {
    background: linear-gradient(180deg, rgba(255, 136, 0, 0.3) 0%, rgba(255, 102, 0, 0.3) 100%);
    border: 2px solid #ff6600;
    color: #ff9933;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 1px;

    &:hover:not(:disabled) {
      background: rgba(255, 102, 0, 0.5);
      color: #ffbb66;
    }
  }

  &.quiz-option {
    background: rgba(37, 211, 102, 0.1);
    border: 1px solid $chat-green;
    color: $chat-light;
    text-align: left;

    &:hover:not(:disabled) {
      background: rgba(37, 211, 102, 0.25);
    }
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

// Typing indicator animation
.typing-dots {
  display: flex;
  gap: 4px;

  span {
    width: 8px;
    height: 8px;
    background: $chat-gray;
    border-radius: 50%;
    animation: typing-bounce 1.4s infinite ease-in-out;

    &:nth-child(1) { animation-delay: 0s; }
    &:nth-child(2) { animation-delay: 0.2s; }
    &:nth-child(3) { animation-delay: 0.4s; }
  }
}

@keyframes typing-bounce {
  0%, 80%, 100% {
    transform: scale(0.6);
    opacity: 0.5;
  }
  40% {
    transform: scale(1);
    opacity: 1;
  }
}

// Choices
.choices-container {
  padding: 12px;
  background: $chat-darker;
  border-top: 1px solid $chat-border;
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-height: 200px;
  overflow-y: auto;
}

.choice-btn {
  width: 100%;
  padding: 12px 16px;
  background: rgba(37, 211, 102, 0.1);
  border: 1px solid $chat-green;
  color: $chat-light;
  font-size: 0.85rem;
  cursor: pointer;
  border-radius: 8px;
  text-align: left;
  transition: all 0.2s;

  &:hover:not(:disabled) {
    background: rgba(37, 211, 102, 0.25);
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

// Start dialogue
.start-dialogue-container {
  padding: 12px;
  background: $chat-darker;
  border-top: 1px solid $chat-border;
}

.start-dialogue-btn {
  width: 100%;
  padding: 14px;
  background: $chat-green;
  border: none;
  color: white;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  border-radius: 8px;
  transition: all 0.2s;

  &:hover:not(:disabled) {
    background: darken(#25D366, 10%);
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

// Disabled input
.input-container {
  padding: 12px;
  background: $chat-darker;
  border-top: 1px solid $chat-border;

  &.disabled {
    opacity: 0.5;
  }
}

.input-placeholder {
  display: block;
  text-align: center;
  color: $chat-gray;
  font-size: 0.8rem;
  padding: 10px;
}

:deep(.phone-content) {
  background: $chat-dark;
}
</style>
