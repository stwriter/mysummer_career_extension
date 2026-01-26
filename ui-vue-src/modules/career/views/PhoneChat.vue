<template>
  <PhoneWrapper :app-name="$t('mysummer.chat.ui.messages')" status-font-color="#25D366" status-blend-mode="">
    <div class="chat-screen">
      <!-- Header -->
      <div class="chat-header">
        <div class="chat-title">{{ $t('mysummer.chat.ui.messages') }}</div>
        <div class="unread-badge" v-if="totalUnread > 0">
          {{ totalUnread }}
        </div>
      </div>

      <!-- Conversation List -->
      <div class="conversations-section" v-if="!loading">
        <div v-if="conversations.length === 0" class="empty-state">
          <span class="empty-icon">[ ]</span>
          <span>{{ $t('mysummer.chat.ui.noMessages') }}</span>
        </div>

        <div v-else class="conversations-list">
          <div
            v-for="conv in conversations"
            :key="conv.contactId"
            class="conversation-item"
            :class="{
              unread: conv.unreadCount > 0,
              'is-system': conv.isSystem
            }"
            @click="openConversation(conv.contactId)"
          >
            <!-- Avatar -->
            <div class="conv-avatar" :class="{ unlocked: conv.isUnlocked }">
              <span v-if="conv.isSystem" class="avatar-icon system">S</span>
              <span v-else-if="conv.isUnlocked" class="avatar-icon">{{ conv.displayName.charAt(0) }}</span>
              <span v-else class="avatar-icon unknown">?</span>
            </div>

            <!-- Content -->
            <div class="conv-content">
              <div class="conv-header">
                <span class="conv-name" :class="{ unknown: !conv.isUnlocked }">
                  {{ conv.isUnlocked ? conv.displayName : '???' }}
                </span>
                <span class="conv-time">{{ formatTime(conv.lastActivity) }}</span>
              </div>
              <div class="conv-preview">
                <span v-if="conv.isTyping" class="typing-indicator">{{ $t('mysummer.chat.ui.typing') }}</span>
                <span v-else>{{ getPreview(conv.lastMessage) }}</span>
              </div>
            </div>

            <!-- Unread badge -->
            <div class="conv-unread" v-if="conv.unreadCount > 0">
              {{ conv.unreadCount }}
            </div>
          </div>
        </div>
      </div>

      <div v-else class="loading-state">
        <span>{{ $t('mysummer.chat.ui.loading') }}</span>
      </div>

      <!-- Footer -->
      <div class="chat-footer">
        <span>encrypted</span>
      </div>
    </div>
  </PhoneWrapper>
</template>

<script setup>
import PhoneWrapper from "./PhoneWrapper.vue"
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'

const router = useRouter()

const conversations = ref([])
const loading = ref(true)
const totalUnread = ref(0)

const formatTime = (timestamp) => {
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

  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

const getPreview = (lastMessage) => {
  if (!lastMessage) return "No messages"
  const content = lastMessage.content || ""
  if (lastMessage.senderType === "player") {
    return "You: " + (content.length > 30 ? content.substring(0, 30) + "..." : content)
  }
  return content.length > 40 ? content.substring(0, 40) + "..." : content
}

const openConversation = (contactId) => {
  router.push(`/career/phone-chat/${contactId}`)
}

const loadConversations = () => {
  loading.value = true
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

// Listen for updates
const handleChatUpdated = (data) => {
  loadConversations()
}

const handleNewMessage = (data) => {
  loadConversations()
}

const handleTyping = (data) => {
  const conv = conversations.value.find(c => c.contactId === data.contactId)
  if (conv) {
    conv.isTyping = data.isTyping
  }
}

onMounted(() => {
  loadConversations()

  if (window.bngApi) {
    window.bngApi.on("mysummerChatUpdated", handleChatUpdated)
    window.bngApi.on("mysummerChatNewMessage", handleNewMessage)
    window.bngApi.on("mysummerChatTyping", handleTyping)
  }
})

onUnmounted(() => {
  if (window.bngApi) {
    window.bngApi.off("mysummerChatUpdated", handleChatUpdated)
    window.bngApi.off("mysummerChatNewMessage", handleNewMessage)
    window.bngApi.off("mysummerChatTyping", handleTyping)
  }
})
</script>

<style scoped lang="scss">
$chat-green: #25D366;
$chat-dark: #0d1418;
$chat-gray: #8696a0;
$chat-light: #e9edef;
$chat-bubble-out: #005c4b;
$chat-border: #222d34;

.chat-screen {
  padding: 16px;
  padding-top: 72px;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  overflow-y: auto;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  color: $chat-light;
}

.chat-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid $chat-border;
}

.chat-title {
  font-size: 1.3rem;
  font-weight: bold;
  color: $chat-light;
}

.unread-badge {
  font-size: 0.75rem;
  background: $chat-green;
  color: white;
  padding: 3px 10px;
  border-radius: 12px;
  font-weight: bold;
}

.loading-state, .empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 40px 20px;
  color: $chat-gray;
  gap: 8px;
}

.empty-icon {
  font-size: 2rem;
}

.conversations-list {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.conversation-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 8px;
  cursor: pointer;
  transition: background 0.2s;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);

  &:hover {
    background: rgba(255, 255, 255, 0.05);
  }

  &.unread {
    background: rgba(37, 211, 102, 0.08);

    .conv-name, .conv-preview {
      font-weight: 600;
    }
  }

  &.is-system {
    .conv-avatar .avatar-icon {
      background: #5865f2;
    }
  }
}

.conv-avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  background: $chat-border;

  .avatar-icon {
    font-size: 1.2rem;
    font-weight: bold;
    color: white;

    &.unknown {
      color: $chat-gray;
    }

    &.system {
      background: #5865f2;
      width: 100%;
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
      border-radius: 50%;
    }
  }

  &.unlocked {
    background: $chat-green;
  }
}

.conv-content {
  flex: 1;
  min-width: 0;
}

.conv-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 4px;
}

.conv-name {
  font-size: 0.95rem;
  color: $chat-light;

  &.unknown {
    font-style: italic;
    color: $chat-gray;
  }
}

.conv-time {
  font-size: 0.7rem;
  color: $chat-gray;
}

.conv-preview {
  font-size: 0.8rem;
  color: $chat-gray;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.typing-indicator {
  color: $chat-green;
  font-style: italic;
}

.conv-unread {
  background: $chat-green;
  color: white;
  font-size: 0.7rem;
  font-weight: bold;
  padding: 2px 7px;
  border-radius: 10px;
  min-width: 18px;
  text-align: center;
}

.chat-footer {
  display: flex;
  justify-content: center;
  padding-top: 12px;
  margin-top: auto;
  border-top: 1px solid $chat-border;
  font-size: 0.65rem;
  color: $chat-gray;
}

:deep(.phone-content) {
  background: $chat-dark;
}
</style>
