<template>
  <div class="email-page">
    <!-- Email Client Header -->
    <div class="email-header">
      <div class="email-logo">
        <span class="logo-icon">[M]</span>
        <span class="logo-text">WebMail</span>
      </div>
      <div class="email-toolbar">
        <button class="toolbar-btn" @click="refreshMessages" :disabled="loading">
          {{ loading ? 'Loading...' : 'Refresh' }}
        </button>
        <button class="toolbar-btn" @click="markAllRead" :disabled="unreadCount === 0">
          Mark All Read
        </button>
      </div>
      <div class="email-stats">
        <span class="unread-badge" v-if="unreadCount > 0">{{ unreadCount }} unread</span>
        <span class="total-count">{{ messages.length }} messages</span>
      </div>
    </div>

    <!-- Email Content Area -->
    <div class="email-content">
      <!-- Message List -->
      <div class="message-list" :class="{ 'has-selection': selectedMessage }">
        <div v-if="loading" class="loading-state">
          <span class="loading-icon">[@]</span>
          <span>Loading messages...</span>
        </div>

        <div v-else-if="messages.length === 0" class="empty-state">
          <span class="empty-icon">[INBOX]</span>
          <p>No messages</p>
          <p class="empty-sub">Your inbox is empty</p>
        </div>

        <div
          v-else
          v-for="msg in messages"
          :key="msg.id"
          class="message-item"
          :class="{
            unread: !msg.read,
            selected: selectedMessage && selectedMessage.id === msg.id,
            'priority-high': msg.priority === 'high'
          }"
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

      <!-- Message View -->
      <div class="message-view" v-if="selectedMessage">
        <div class="view-header">
          <button class="back-btn" @click="selectedMessage = null">&lt; Back</button>
          <button class="delete-btn" @click="deleteMessage(selectedMessage.id)">Delete</button>
        </div>

        <div class="view-content">
          <div class="view-meta">
            <div class="view-from">
              <span class="meta-label">From:</span>
              <span class="meta-value">{{ selectedMessage.fromName }}</span>
            </div>
            <div class="view-date">
              <span class="meta-label">Date:</span>
              <span class="meta-value">{{ formatFullDate(selectedMessage.timestamp) }}</span>
            </div>
            <div class="view-subject">
              <span class="meta-label">Subject:</span>
              <span class="meta-value">{{ selectedMessage.subject }}</span>
            </div>
          </div>

          <div class="view-body">
            <pre>{{ selectedMessage.body }}</pre>
          </div>

          <!-- Quiz Actions (for surveillance missions) -->
          <div class="quiz-actions" v-if="selectedMessage.actionType === 'surveillance_quiz' && selectedMessage.quizOptions">
            <div class="quiz-prompt">Where did the target go?</div>
            <div class="quiz-options">
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
          </div>

          <!-- Mission Actions (for regular mission offers) -->
          <div class="mission-actions" v-else-if="selectedMessage.missionId && selectedMessage.actionType !== 'surveillance_quiz'">
            <button class="accept-mission-btn" @click="acceptMission(selectedMessage.missionId)" :disabled="missionLoading">
              {{ missionLoading ? 'Starting...' : 'ACCEPT JOB' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Status Bar -->
    <div class="email-status">
      <span class="status-text">Connected to mail server</span>
      <span class="status-server">mail.westcoast.local</span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue"

const messages = ref([])
const loading = ref(true)
const selectedMessage = ref(null)
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
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  })
}

const getPreview = (body) => {
  if (!body) return ""
  const lines = body.split("\n").filter(l => l.trim())
  const preview = lines.slice(0, 2).join(" ")
  return preview.length > 80 ? preview.substring(0, 80) + "..." : preview
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

const markAllRead = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerMessages.markAllAsRead()')
    messages.value.forEach(m => m.read = true)
  }
}

const acceptMission = (missionId) => {
  if (!window.bngApi || missionLoading.value) return

  missionLoading.value = true
  window.bngApi.engineLua(`career_modules_mysummerMissions.startMission("${missionId}")`, (result) => {
    missionLoading.value = false
    if (result) {
      // Mission started - delete the email and close view
      deleteMessage(selectedMessage.value.id)
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
    // Delete the message and close view
    deleteMessage(selectedMessage.value.id)
  })
}

const refreshMessages = () => {
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
  refreshMessages()
})
</script>

<style scoped lang="scss">
$email-blue: #0066cc;
$email-gray: #f5f5f5;
$email-border: #ddd;
$email-text: #333;
$email-light: #666;

.email-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: white;
  font-family: "Segoe UI", Tahoma, sans-serif;
  font-size: 12px;
  color: $email-text;
}

.email-header {
  display: flex;
  align-items: center;
  gap: 15px;
  padding: 8px 12px;
  background: linear-gradient(180deg, #f8f8f8 0%, #e8e8e8 100%);
  border-bottom: 1px solid $email-border;
}

.email-logo {
  display: flex;
  align-items: center;
  gap: 6px;

  .logo-icon {
    font-size: 16px;
    color: $email-blue;
    font-weight: bold;
  }

  .logo-text {
    font-size: 14px;
    font-weight: bold;
    color: $email-blue;
  }
}

.email-toolbar {
  display: flex;
  gap: 5px;
}

.toolbar-btn {
  padding: 4px 10px;
  background: white;
  border: 1px solid #bbb;
  font-size: 11px;
  cursor: pointer;

  &:hover:not(:disabled) {
    background: #f0f0f0;
  }

  &:disabled {
    opacity: 0.5;
    cursor: default;
  }
}

.email-stats {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 11px;
  color: $email-light;
}

.unread-badge {
  background: $email-blue;
  color: white;
  padding: 2px 6px;
  border-radius: 10px;
  font-size: 10px;
}

.email-content {
  flex: 1;
  display: flex;
  overflow: hidden;
}

.message-list {
  flex: 1;
  overflow-y: auto;
  border-right: 1px solid $email-border;

  &.has-selection {
    flex: 0 0 300px;
  }
}

.message-item {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 10px 12px;
  border-bottom: 1px solid #eee;
  cursor: pointer;

  &:hover {
    background: #f8f8f8;
  }

  &.selected {
    background: #e8f0ff;
  }

  &.unread {
    background: #fffef0;

    .msg-from, .msg-subject {
      font-weight: bold;
    }
  }

  &.priority-high {
    border-left: 3px solid #ff6600;
  }
}

.msg-icon {
  font-size: 14px;
  color: $email-blue;
  flex-shrink: 0;
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
  font-size: 12px;
  color: $email-text;
}

.msg-date {
  font-size: 10px;
  color: $email-light;
}

.msg-subject {
  font-size: 11px;
  color: $email-text;
  margin-bottom: 2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.msg-preview {
  font-size: 10px;
  color: $email-light;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.msg-status {
  flex-shrink: 0;
}

.unread-dot {
  display: block;
  width: 8px;
  height: 8px;
  background: $email-blue;
  border-radius: 50%;
}

.message-view {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.view-header {
  display: flex;
  gap: 10px;
  padding: 8px 12px;
  background: $email-gray;
  border-bottom: 1px solid $email-border;
}

.back-btn, .delete-btn {
  padding: 4px 10px;
  background: white;
  border: 1px solid #bbb;
  font-size: 11px;
  cursor: pointer;

  &:hover {
    background: #f0f0f0;
  }
}

.delete-btn {
  margin-left: auto;
  color: #cc0000;
}

.view-content {
  flex: 1;
  overflow-y: auto;
  padding: 15px;
}

.view-meta {
  padding-bottom: 15px;
  border-bottom: 1px solid $email-border;
  margin-bottom: 15px;
}

.view-from, .view-date, .view-subject {
  display: flex;
  margin-bottom: 5px;
}

.meta-label {
  width: 60px;
  font-weight: bold;
  color: $email-light;
}

.meta-value {
  flex: 1;
}

.view-subject .meta-value {
  font-weight: bold;
  font-size: 14px;
}

.view-body {
  pre {
    margin: 0;
    font-family: inherit;
    white-space: pre-wrap;
    word-wrap: break-word;
    line-height: 1.6;
  }
}

.mission-actions {
  margin-top: 20px;
  padding-top: 15px;
  border-top: 2px solid #ff6600;
}

.accept-mission-btn {
  width: 100%;
  padding: 12px 20px;
  background: linear-gradient(180deg, #ff8800 0%, #ff6600 100%);
  border: none;
  color: white;
  font-size: 14px;
  font-weight: bold;
  cursor: pointer;
  text-transform: uppercase;
  letter-spacing: 1px;

  &:hover:not(:disabled) {
    background: linear-gradient(180deg, #ff9922 0%, #ff7711 100%);
  }

  &:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
}

// Quiz Actions
.quiz-actions {
  margin-top: 20px;
  padding-top: 15px;
  border-top: 2px solid $email-blue;
}

.quiz-prompt {
  font-size: 14px;
  font-weight: bold;
  color: $email-blue;
  margin-bottom: 12px;
  text-align: center;
}

.quiz-options {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.quiz-option-btn {
  width: 100%;
  padding: 12px 15px;
  background: #f8f8ff;
  border: 1px solid $email-blue;
  color: $email-text;
  font-size: 13px;
  cursor: pointer;
  text-align: left;
  transition: all 0.2s;

  &:hover:not(:disabled) {
    background: #e8f0ff;
    border-color: darken($email-blue, 10%);
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.loading-state, .empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 200px;
  color: $email-light;
}

.loading-icon, .empty-icon {
  font-size: 24px;
  margin-bottom: 10px;
}

.empty-sub {
  font-size: 11px;
  margin-top: 5px;
}

.email-status {
  display: flex;
  justify-content: space-between;
  padding: 4px 12px;
  background: $email-gray;
  border-top: 1px solid $email-border;
  font-size: 10px;
  color: $email-light;
}
</style>
