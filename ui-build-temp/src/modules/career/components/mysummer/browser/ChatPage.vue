<template>
  <div class="chat-browser-page">
    <!-- Two-pane layout -->
    <div class="chat-layout">
      <!-- Left: Conversation List -->
      <div class="conversations-pane">
        <div class="pane-header">
          <span class="header-title">{{ $t('mysummer.chat.ui.messages') }}</span>
          <span class="unread-badge" v-if="totalUnread > 0">{{ totalUnread }}</span>
        </div>

        <div class="conversations-list">
          <div v-if="loading && conversations.length === 0" class="loading-state">
            {{ $t('mysummer.chat.ui.loading') }}
          </div>

          <div v-else-if="conversations.length === 0" class="empty-state">
            {{ $t('mysummer.chat.ui.noMessages') }}
          </div>

          <div
            v-for="conv in conversations"
            :key="conv.contactId"
            class="conv-item"
            :class="{
              selected: selectedContact === conv.contactId,
              unread: conv.unreadCount > 0
            }"
            @click="selectConversation(conv.contactId)"
          >
            <div class="conv-avatar" :class="{ unlocked: conv.isUnlocked }">
              {{ conv.isUnlocked ? conv.displayName.charAt(0) : '?' }}
            </div>
            <div class="conv-info">
              <div class="conv-name">{{ conv.isUnlocked ? conv.displayName : '???' }}</div>
              <div class="conv-preview">{{ getPreview(conv.lastMessage) }}</div>
            </div>
            <div class="conv-meta">
              <span class="conv-time">{{ formatTime(conv.lastActivity) }}</span>
              <span class="conv-unread" v-if="conv.unreadCount > 0">{{ conv.unreadCount }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Right: Chat View -->
      <div class="chat-pane">
        <template v-if="selectedContact && currentConversation">
          <!-- Chat Header -->
          <div class="chat-header">
            <div class="contact-avatar" :class="{ unlocked: currentContact?.isUnlocked }">
              {{ currentContact?.isUnlocked ? currentContact.displayName.charAt(0) : '?' }}
            </div>
            <div class="contact-info">
              <div class="contact-name">
                {{ currentContact?.isUnlocked ? currentContact.displayName : '???' }}
              </div>
              <div class="contact-specialty" v-if="currentContact?.specialty">
                {{ currentContact.specialty }}
              </div>
            </div>
          </div>

          <!-- Messages -->
          <div class="messages-container" ref="messagesContainer">
            <div
              v-for="msg in currentConversation.messages"
              :key="msg.id"
              class="message"
              :class="msg.senderType"
            >
              <div class="message-bubble" :class="msg.senderType">
                <div class="message-text">{{ msg.content }}</div>

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

                <div class="message-time">{{ formatMessageTime(msg.timestamp) }}</div>
              </div>
            </div>

            <!-- Typing indicator -->
            <div v-if="isTyping" class="message contact">
              <div class="message-bubble contact typing">
                <span class="typing-text">{{ $t('mysummer.chat.ui.typing') }}</span>
              </div>
            </div>
          </div>

          <!-- Choices -->
          <div v-if="pendingChoices.length > 0" class="choices-pane">
            <div class="choices-label">{{ $t('mysummer.chat.ui.yourResponse') }}</div>
            <div class="choices-list">
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
          </div>

          <!-- Start Dialogue -->
          <div v-else-if="canStartDialogue && !hasActiveDialogue" class="start-pane">
            <button
              class="start-btn"
              @click="startDialogue"
              :disabled="startingDialogue"
            >
              {{ startingDialogue ? $t('mysummer.chat.actions.starting') : $t('mysummer.chat.ui.startConversation') }}
            </button>
          </div>

          <!-- No interaction available -->
          <div v-else class="input-pane disabled">
            <span>{{ $t('mysummer.chat.ui.noResponseOptions') }}</span>
          </div>
        </template>

        <!-- No conversation selected -->
        <div v-else class="no-selection">
          <div class="no-selection-icon">[M]</div>
          <div class="no-selection-text">{{ $t('mysummer.chat.ui.selectConversation') }}</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { useI18n } from 'petite-vue-i18n'

const { t } = useI18n()
const emit = defineEmits(['navigate'])

const conversations = ref([])
const currentConversation = ref(null)
const currentContact = ref(null)
const selectedContact = ref(null)
const pendingChoices = ref([])
const loading = ref(true)
const totalUnread = ref(0)
const isTyping = ref(false)
const sendingChoice = ref(false)
const startingDialogue = ref(false)
const hasActiveDialogue = ref(false)
const canStartDialogue = ref(false)
const actionLoading = ref(false)

const messagesContainer = ref(null)

const formatTime = (timestamp) => {
  if (!timestamp) return ""
  const date = new Date(timestamp * 1000)
  const now = new Date()
  const diff = now - date

  if (diff < 24 * 60 * 60 * 1000 && date.getDate() === now.getDate()) {
    return date.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })
  }
  if (diff < 7 * 24 * 60 * 60 * 1000) {
    return date.toLocaleDateString("en-US", { weekday: "short" })
  }
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

const formatMessageTime = (timestamp) => {
  if (!timestamp) return ""
  return new Date(timestamp * 1000).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit"
  })
}

const getPreview = (lastMessage) => {
  if (!lastMessage) return t('mysummer.chat.ui.noMessages')
  const content = lastMessage.content || ""
  if (lastMessage.senderType === "player") {
    return t('mysummer.chat.ui.you') + ": " + (content.length > 25 ? content.substring(0, 25) + "..." : content)
  }
  return content.length > 30 ? content.substring(0, 30) + "..." : content
}

const scrollToBottom = () => {
  nextTick(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
    }
  })
}

const loadConversations = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerChat.getConversations()', (result) => {
      conversations.value = result || []
      loading.value = false
    })
    window.bngApi.engineLua('career_modules_mysummerChat.getUnreadCounts()', (result) => {
      if (result) {
        totalUnread.value = result.total || 0
      }
    })
  } else {
    loading.value = false
  }
}

const selectConversation = (contactId) => {
  selectedContact.value = contactId
  loadConversation(contactId)
}

const loadConversation = (contactId) => {
  if (!window.bngApi) return

  window.bngApi.engineLua(`career_modules_mysummerChat.getConversation("${contactId}")`, (result) => {
    if (result) {
      currentConversation.value = result.conversation
      currentContact.value = result.contact
      pendingChoices.value = result.pendingChoices || []
      scrollToBottom()
    }
  })

  window.bngApi.engineLua(`career_modules_mysummerChat.hasAvailableDialogue("${contactId}")`, (result) => {
    canStartDialogue.value = result === true
  })

  window.bngApi.engineLua(`career_modules_mysummerChat.getDialogueState("${contactId}")`, (result) => {
    if (result) {
      hasActiveDialogue.value = result.isActive
      if (result.pendingChoices) {
        pendingChoices.value = result.pendingChoices
      }
    }
  })

  // Mark as read
  window.bngApi.engineLua(`career_modules_mysummerChat.markAsRead("${contactId}")`)
}

const startDialogue = () => {
  if (!window.bngApi || startingDialogue.value || !selectedContact.value) return

  startingDialogue.value = true
  window.bngApi.engineLua(`career_modules_mysummerChat.startDialogue("${selectedContact.value}")`, (result) => {
    startingDialogue.value = false
    if (result && result.success) {
      hasActiveDialogue.value = true
      if (result.choices) {
        pendingChoices.value = result.choices
      }
      loadConversation(selectedContact.value)
    }
  })
}

const selectChoice = (choice) => {
  if (!window.bngApi || sendingChoice.value || !selectedContact.value) return

  sendingChoice.value = true
  window.bngApi.engineLua(`career_modules_mysummerChat.continueDialogue("${selectedContact.value}", "${choice.id}")`, (result) => {
    sendingChoice.value = false
    if (result && result.success) {
      pendingChoices.value = result.choices || []
      if (result.ended) {
        hasActiveDialogue.value = false
        window.bngApi.engineLua(`career_modules_mysummerChat.hasAvailableDialogue("${selectedContact.value}")`, (available) => {
          canStartDialogue.value = available === true
        })
      }
      loadConversation(selectedContact.value)
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
      msg.actionCompleted = true
      // Close browser menu
      window.bngApi.engineLua("guihooks.trigger('MenuHide')")
    }
  })
}

const answerQuiz = (msg, answerIndex) => {
  if (!window.bngApi || actionLoading.value) return

  actionLoading.value = true
  const luaIndex = answerIndex + 1
  window.bngApi.engineLua(`career_modules_mysummerMissions.answerSurveillanceQuiz(${luaIndex})`, (result) => {
    actionLoading.value = false
    msg.actionCompleted = true
    window.bngApi.engineLua("guihooks.trigger('MenuHide')")
  })
}

// Event handlers
const handleConversationUpdated = (data) => {
  loadConversations()
  if (selectedContact.value && data.contactId === selectedContact.value) {
    loadConversation(selectedContact.value)
  }
}

const handleNewMessage = (data) => {
  loadConversations()
  if (selectedContact.value && data.contactId === selectedContact.value) {
    loadConversation(selectedContact.value)
  }
}

const handleTyping = (data) => {
  if (selectedContact.value && data.contactId === selectedContact.value) {
    isTyping.value = data.isTyping
    if (data.isTyping) scrollToBottom()
  }
}

const handleChoices = (data) => {
  if (selectedContact.value && data.contactId === selectedContact.value) {
    pendingChoices.value = data.choices || []
  }
}

onMounted(() => {
  loadConversations()

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

watch(() => currentConversation.value?.messages, () => {
  scrollToBottom()
})
</script>

<style scoped lang="scss">
$bg-dark: #1a1a2e;
$bg-darker: #0f0f1a;
$border-color: #333355;
$text-primary: #e0e0ff;
$text-secondary: #8888aa;
$accent-green: #25D366;
$bubble-out: #005c4b;
$bubble-in: #2a2a4a;

.chat-browser-page {
  height: 100%;
  background: $bg-dark;
  color: $text-primary;
  font-family: "Segoe UI", Tahoma, sans-serif;
}

.chat-layout {
  display: flex;
  height: 100%;
}

// Left Pane - Conversations List
.conversations-pane {
  width: 280px;
  border-right: 1px solid $border-color;
  display: flex;
  flex-direction: column;
  background: $bg-darker;
}

.pane-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 16px;
  border-bottom: 1px solid $border-color;
  background: rgba(0,0,0,0.2);
}

.header-title {
  font-weight: bold;
  font-size: 1rem;
}

.unread-badge {
  background: $accent-green;
  color: white;
  font-size: 0.7rem;
  padding: 2px 8px;
  border-radius: 10px;
}

.conversations-list {
  flex: 1;
  overflow-y: auto;
}

.loading-state, .empty-state {
  padding: 20px;
  text-align: center;
  color: $text-secondary;
}

.conv-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  cursor: pointer;
  border-bottom: 1px solid rgba(255,255,255,0.05);
  transition: background 0.2s;

  &:hover {
    background: rgba(255,255,255,0.05);
  }

  &.selected {
    background: rgba(37, 211, 102, 0.15);
    border-left: 3px solid $accent-green;
  }

  &.unread {
    .conv-name { font-weight: bold; }
  }
}

.conv-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: $border-color;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: bold;
  color: $text-secondary;
  flex-shrink: 0;

  &.unlocked {
    background: $accent-green;
    color: white;
  }
}

.conv-info {
  flex: 1;
  min-width: 0;
}

.conv-name {
  font-size: 0.85rem;
  color: $text-primary;
  margin-bottom: 2px;
}

.conv-preview {
  font-size: 0.75rem;
  color: $text-secondary;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.conv-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}

.conv-time {
  font-size: 0.65rem;
  color: $text-secondary;
}

.conv-unread {
  background: $accent-green;
  color: white;
  font-size: 0.6rem;
  padding: 1px 6px;
  border-radius: 8px;
}

// Right Pane - Chat View
.chat-pane {
  flex: 1;
  display: flex;
  flex-direction: column;
  background: $bg-dark;
}

.no-selection {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: $text-secondary;
}

.no-selection-icon {
  font-size: 3rem;
  margin-bottom: 16px;
  opacity: 0.5;
}

.no-selection-text {
  font-size: 0.9rem;
}

.chat-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-bottom: 1px solid $border-color;
  background: $bg-darker;
}

.contact-avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: $border-color;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: bold;
  font-size: 1.1rem;

  &.unlocked {
    background: $accent-green;
    color: white;
  }
}

.contact-name {
  font-weight: 600;
  font-size: 0.95rem;
}

.contact-specialty {
  font-size: 0.75rem;
  color: $text-secondary;
}

.messages-container {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.message {
  display: flex;

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
  max-width: 70%;
  padding: 8px 12px;
  border-radius: 8px;

  &.player {
    background: $bubble-out;
    border-bottom-right-radius: 2px;
  }

  &.contact {
    background: $bubble-in;
    border-bottom-left-radius: 2px;
  }

  &.system {
    background: rgba(100,100,100,0.3);
    font-size: 0.75rem;
    color: $text-secondary;
    padding: 6px 16px;
    border-radius: 16px;
  }
}

.message-text {
  font-size: 0.85rem;
  line-height: 1.4;
}

.message-time {
  font-size: 0.6rem;
  color: rgba(255,255,255,0.5);
  text-align: right;
  margin-top: 4px;
}

.message-action {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid rgba(255,255,255,0.1);

  &.quiz {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
}

.quiz-label {
  font-size: 0.75rem;
  color: $text-secondary;
  margin-bottom: 6px;
}

.action-btn {
  padding: 10px 16px;
  border: none;
  border-radius: 6px;
  font-size: 0.8rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;

  &.accept {
    background: $accent-green;
    color: white;

    &:hover:not(:disabled) {
      background: darken(#25D366, 10%);
    }
  }

  &.quiz-option {
    background: rgba(100,149,237,0.2);
    border: 1px solid rgba(100,149,237,0.5);
    color: $text-primary;
    text-align: left;

    &:hover:not(:disabled) {
      background: rgba(100,149,237,0.35);
    }
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.typing-text {
  font-style: italic;
  color: $text-secondary;
}

// Choices Pane
.choices-pane {
  padding: 12px 16px;
  border-top: 1px solid $border-color;
  background: $bg-darker;
}

.choices-label {
  font-size: 0.75rem;
  color: $text-secondary;
  margin-bottom: 8px;
}

.choices-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.choice-btn {
  padding: 10px 14px;
  background: rgba(37, 211, 102, 0.1);
  border: 1px solid $accent-green;
  color: $text-primary;
  font-size: 0.8rem;
  cursor: pointer;
  border-radius: 6px;
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

// Start Dialogue Pane
.start-pane {
  padding: 16px;
  border-top: 1px solid $border-color;
  background: $bg-darker;
  text-align: center;
}

.start-btn {
  padding: 12px 24px;
  background: $accent-green;
  border: none;
  color: white;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  border-radius: 6px;
  transition: all 0.2s;

  &:hover:not(:disabled) {
    background: darken(#25D366, 10%);
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

// Disabled Input Pane
.input-pane {
  padding: 16px;
  border-top: 1px solid $border-color;
  background: $bg-darker;
  text-align: center;

  &.disabled {
    color: $text-secondary;
    font-size: 0.8rem;
  }
}
</style>
