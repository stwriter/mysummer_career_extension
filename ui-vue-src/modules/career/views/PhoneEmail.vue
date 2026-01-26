<template>
  <PhoneWrapper app-name="Email" status-font-color="#0066cc" status-blend-mode="">
    <div class="email-screen">
      <!-- Header -->
      <div class="email-header">
        <div class="email-title">[M] WebMail</div>
        <div class="email-stats" v-if="unreadCount > 0">
          {{ unreadCount }} unread
        </div>
      </div>

      <!-- Message List -->
      <div class="messages-section" v-if="!selectedMessage">
        <div v-if="loading" class="loading-state">
          <span class="loading-icon">[@]</span>
          <span>Loading...</span>
        </div>

        <div v-else-if="messages.length === 0" class="empty-state">
          <span class="empty-icon">[INBOX]</span>
          <span>No messages</span>
        </div>

        <div v-else class="messages-list">
          <div
            v-for="msg in messages"
            :key="msg.id"
            class="message-item"
            :class="{ unread: !msg.read, 'priority-high': msg.priority === 'high' }"
            @click="selectMessage(msg)"
          >
            <div class="msg-icon">{{ msg.icon || '[*]' }}</div>
            <div class="msg-content">
              <div class="msg-header">
                <span class="msg-from">{{ msg.fromName }}</span>
                <span class="msg-date">{{ formatDate(msg.timestamp) }}</span>
              </div>
              <div class="msg-subject">{{ msg.subject }}</div>
              <div class="msg-preview">{{ getPreview(msg.body) }}</div>
            </div>
            <div class="msg-status">
              <span v-if="!msg.read" class="unread-dot"></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Message View -->
      <div class="message-view" v-if="selectedMessage">
        <button class="back-btn" @click="selectedMessage = null">
          &lt; Back
        </button>

        <div class="view-content">
          <div class="view-meta">
            <div class="view-row">
              <span class="meta-label">From:</span>
              <span class="meta-value">{{ selectedMessage.fromName }}</span>
            </div>
            <div class="view-row">
              <span class="meta-label">Date:</span>
              <span class="meta-value">{{ formatFullDate(selectedMessage.timestamp) }}</span>
            </div>
            <div class="view-row subject">
              <span class="meta-label">Subject:</span>
              <span class="meta-value">{{ selectedMessage.subject }}</span>
            </div>
          </div>

          <div class="view-body">
            <pre>{{ selectedMessage.body }}</pre>
          </div>

          <!-- Quiz Actions (for surveillance missions) -->
          <div v-if="selectedMessage.actionType === 'surveillance_quiz' && selectedMessage.quizOptions" class="quiz-actions">
            <div class="quiz-prompt">Where did the target go?</div>
            <button
              v-for="(option, index) in selectedMessage.quizOptions"
              :key="index"
              class="quiz-option-btn"
              @click="answerQuiz(index)"
              :disabled="quizLoading"
            >
              {{ option }}
            </button>
          </div>

          <!-- Mission Actions (for regular mission offers) -->
          <button
            v-else-if="selectedMessage.missionId && selectedMessage.actionType !== 'surveillance_quiz'"
            class="accept-mission-btn"
            @click="acceptMission(selectedMessage.missionId)"
            :disabled="missionLoading"
          >
            {{ missionLoading ? 'Starting...' : 'ACCEPT JOB' }}
          </button>

          <button class="delete-btn" @click="deleteMessage(selectedMessage.id)">
            Delete Message
          </button>
        </div>
      </div>

      <!-- Footer -->
      <div class="email-footer">
        <span>mail.westcoast.local</span>
      </div>
    </div>
  </PhoneWrapper>
</template>

<script setup>
import PhoneWrapper from "./PhoneWrapper.vue"
import { ref, computed, onMounted } from 'vue'

const messages = ref([])
const selectedMessage = ref(null)
const loading = ref(true)
const missionLoading = ref(false)
const quizLoading = ref(false)

const unreadCount = computed(() => messages.value.filter(m => !m.read).length)

const formatDate = (timestamp) => {
  if (!timestamp) return ""
  const date = new Date(timestamp * 1000)
  const now = new Date()
  const diff = now - date

  // Today
  if (diff < 24 * 60 * 60 * 1000 && date.getDate() === now.getDate()) {
    return date.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })
  }

  // This week
  if (diff < 7 * 24 * 60 * 60 * 1000) {
    return date.toLocaleDateString("en-US", { weekday: "short" })
  }

  // Older
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

const formatFullDate = (timestamp) => {
  if (!timestamp) return ""
  const date = new Date(timestamp * 1000)
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  })
}

const getPreview = (body) => {
  if (!body) return ""
  const lines = body.split("\n").filter(l => l.trim())
  const preview = lines.slice(0, 1).join(" ")
  return preview.length > 40 ? preview.substring(0, 40) + "..." : preview
}

const selectMessage = (msg) => {
  selectedMessage.value = msg

  // Mark as read
  if (!msg.read && window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerMessages.markAsRead(${msg.id})`)
    msg.read = true
  }
}

const deleteMessage = (msgId) => {
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerMessages.deleteMessage(${msgId})`)
    messages.value = messages.value.filter(m => m.id !== msgId)
    selectedMessage.value = null
  }
}

const acceptMission = (missionId) => {
  if (!window.bngApi || missionLoading.value) return

  missionLoading.value = true
  window.bngApi.engineLua(`career_modules_mysummerMissions.startMission("${missionId}")`, (result) => {
    missionLoading.value = false
    if (result) {
      // Mission started - delete the email, close view, close phone
      deleteMessage(selectedMessage.value.id)
      window.bngApi.engineLua("guihooks.trigger('closePhone')")
    }
  })
}

const answerQuiz = (answerIndex) => {
  if (!window.bngApi || quizLoading.value) return

  quizLoading.value = true
  // Call the quiz callback with the answer (1-indexed for Lua)
  const luaIndex = answerIndex + 1
  window.bngApi.engineLua(`career_modules_mysummerMissions.answerSurveillanceQuiz(${luaIndex})`, (result) => {
    quizLoading.value = false
    // Delete the message and close phone regardless of result
    deleteMessage(selectedMessage.value.id)
    window.bngApi.engineLua("guihooks.trigger('closePhone')")
  })
}

const loadMessages = () => {
  loading.value = true
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerMessages.getMessages()', (result) => {
      messages.value = result || []
      loading.value = false
    })
  } else {
    loading.value = false
  }
}

onMounted(() => {
  loadMessages()
})
</script>

<style scoped lang="scss">
$email-blue: #0066cc;
$email-light-blue: #4d94ff;
$email-white: #ffffff;
$email-gray: #888;
$email-dark: #1a1a1a;
$email-border: #333;

.email-screen {
  padding: 16px;
  padding-top: 72px;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  overflow-y: auto;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  color: $email-white;
}

.email-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid $email-border;
}

.email-title {
  font-size: 1.1rem;
  font-weight: bold;
  color: $email-light-blue;
}

.email-stats {
  font-size: 0.75rem;
  background: $email-blue;
  color: white;
  padding: 3px 8px;
  border-radius: 10px;
}

.loading-state, .empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 40px 20px;
  color: $email-gray;
  gap: 8px;
}

.loading-icon, .empty-icon {
  font-size: 1.5rem;
}

.messages-list {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.message-item {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 12px 10px;
  background: rgba(255, 255, 255, 0.03);
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
  cursor: pointer;
  transition: background 0.2s;

  &:hover {
    background: rgba(255, 255, 255, 0.08);
  }

  &.unread {
    background: rgba(0, 102, 204, 0.1);
    border-left: 3px solid $email-blue;

    .msg-from, .msg-subject {
      font-weight: bold;
    }
  }

  &.priority-high {
    border-left: 3px solid #ff6600;
  }
}

.msg-icon {
  font-size: 0.9rem;
  color: $email-light-blue;
  flex-shrink: 0;
  width: 24px;
  text-align: center;
}

.msg-content {
  flex: 1;
  min-width: 0;
}

.msg-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 2px;
}

.msg-from {
  font-size: 0.85rem;
  color: $email-white;
}

.msg-date {
  font-size: 0.65rem;
  color: $email-gray;
}

.msg-subject {
  font-size: 0.8rem;
  color: rgba(255, 255, 255, 0.9);
  margin-bottom: 2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.msg-preview {
  font-size: 0.7rem;
  color: $email-gray;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.msg-status {
  flex-shrink: 0;
  width: 10px;
}

.unread-dot {
  display: block;
  width: 8px;
  height: 8px;
  background: $email-blue;
  border-radius: 50%;
}

// Message View
.message-view {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.back-btn {
  align-self: flex-start;
  padding: 8px 14px;
  background: transparent;
  border: 1px solid $email-border;
  color: $email-gray;
  font-size: 0.8rem;
  cursor: pointer;
  margin-bottom: 16px;
  border-radius: 4px;

  &:hover {
    border-color: $email-light-blue;
    color: $email-light-blue;
  }
}

.view-content {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.view-meta {
  padding-bottom: 12px;
  border-bottom: 1px solid $email-border;
  margin-bottom: 12px;
}

.view-row {
  display: flex;
  margin-bottom: 4px;
  font-size: 0.8rem;

  &.subject {
    margin-top: 8px;

    .meta-value {
      font-weight: bold;
      font-size: 0.95rem;
    }
  }
}

.meta-label {
  width: 50px;
  color: $email-gray;
  flex-shrink: 0;
}

.meta-value {
  flex: 1;
  color: $email-white;
}

.view-body {
  flex: 1;
  overflow-y: auto;

  pre {
    margin: 0;
    font-family: inherit;
    white-space: pre-wrap;
    word-wrap: break-word;
    line-height: 1.5;
    font-size: 0.8rem;
    color: rgba(255, 255, 255, 0.9);
  }
}

.accept-mission-btn {
  margin-top: 16px;
  padding: 14px;
  background: linear-gradient(180deg, rgba(255, 136, 0, 0.3) 0%, rgba(255, 102, 0, 0.3) 100%);
  border: 2px solid #ff6600;
  color: #ff9933;
  font-size: 0.9rem;
  font-weight: bold;
  cursor: pointer;
  border-radius: 4px;
  text-transform: uppercase;
  letter-spacing: 1px;

  &:hover:not(:disabled) {
    background: rgba(255, 102, 0, 0.5);
    color: #ffbb66;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.delete-btn {
  margin-top: 12px;
  padding: 10px;
  background: rgba(204, 0, 0, 0.2);
  border: 1px solid #cc3333;
  color: #ff4444;
  font-size: 0.8rem;
  cursor: pointer;
  border-radius: 4px;

  &:hover {
    background: rgba(204, 0, 0, 0.4);
  }
}

// Quiz Actions
.quiz-actions {
  margin-top: 16px;
  padding-top: 12px;
  border-top: 2px solid $email-blue;
}

.quiz-prompt {
  font-size: 0.9rem;
  font-weight: bold;
  color: $email-light-blue;
  margin-bottom: 12px;
  text-align: center;
}

.quiz-option-btn {
  display: block;
  width: 100%;
  margin-bottom: 8px;
  padding: 12px 14px;
  background: rgba(0, 102, 204, 0.15);
  border: 1px solid $email-blue;
  color: $email-white;
  font-size: 0.85rem;
  cursor: pointer;
  border-radius: 4px;
  text-align: left;
  transition: all 0.2s;

  &:hover:not(:disabled) {
    background: rgba(0, 102, 204, 0.35);
    border-color: $email-light-blue;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.email-footer {
  display: flex;
  justify-content: center;
  padding-top: 12px;
  margin-top: auto;
  border-top: 1px solid $email-border;
  font-size: 0.65rem;
  color: $email-gray;
}

:deep(.phone-content) {
  background: linear-gradient(to bottom, #0a0a0a, #1a1a2a);
}
</style>
