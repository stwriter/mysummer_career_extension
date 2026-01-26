<template>
  <div class="deepweb-root" :class="{ compact }">
    <!-- Hacking Animation Overlay -->
    <div v-if="showHackingAnimation" class="hacking-overlay">
      <div class="hacking-content">
        <div class="code-lines" ref="codeContainer">
          <div v-for="line in hackingLines" :key="line.id" class="code-line">
            {{ line.text }}
          </div>
        </div>
        <div class="hacking-status">
          <span>{{ hackingStatus }}</span>
        </div>
      </div>
    </div>

    <!-- Main Content (Windows 95 Style) -->
    <template v-else>
      <!-- Browser Window Frame -->
      <div class="browser-frame">
        <div class="browser-titlebar">
          <span class="titlebar-icon">@</span>
          <span class="titlebar-text">DarkNet Browser v0.9.5 - Secure Connection</span>
          <div class="titlebar-buttons">
            <span class="btn-minimize">_</span>
            <span class="btn-maximize">[]</span>
            <span class="btn-close">X</span>
          </div>
        </div>
        <div class="browser-menubar">
          <span class="menu-item">File</span>
          <span class="menu-item">Edit</span>
          <span class="menu-item">View</span>
          <span class="menu-item">Bookmarks</span>
          <span class="menu-item">Help</span>
        </div>
        <div class="browser-addressbar">
          <span class="address-label">Location:</span>
          <div class="address-input">
            <span class="address-text">darknet://silkroad.parts/vendors</span>
          </div>
        </div>
      </div>

      <!-- Vendor List View -->
      <template v-if="!conversation">
        <div class="deepweb-header">
          <h2>:: SILKROAD PARTS NETWORK ::</h2>
          <p>[ Secure connection established - Anonymous mode active ]</p>
        </div>

        <div class="vendors-list">
          <div v-if="vendors.length === 0" class="empty-state">
            &gt; No vendors available yet._
          </div>
          <div
            v-for="vendor in vendors"
            :key="vendor.id"
            class="vendor-card"
            :class="{ locked: vendor.locked, 'on-cooldown': vendor.onCooldown }"
            @click="handleVendorClick(vendor)"
          >
            <div class="vendor-icon">[{{ vendorInitial(vendor) }}]</div>
            <div class="vendor-info">
              <div class="vendor-name">&gt; {{ vendor.name }}</div>
              <div class="vendor-specialty">{{ vendor.specialty }}</div>
              <div class="vendor-status">
                <span v-if="vendor.locked" class="status-locked">[LOCKED]</span>
                <span v-else-if="vendor.onCooldown" class="status-cooldown">[BUSY - {{ formatCooldown(vendor.cooldownRemaining) }}]</span>
                <span v-else class="status-trust">[LEVEL {{ vendor.trustLevel || 1 }}]</span>
              </div>
            </div>
            <div class="vendor-arrow" v-if="!vendor.locked && !vendor.onCooldown">&gt;&gt;</div>
          </div>
        </div>
      </template>

      <!-- Conversation View -->
      <template v-else>
        <div class="conversation-header">
          <button class="win95-btn" @click="closeConversation">&lt; Back</button>
          <div class="conversation-vendor">
            <span class="vendor-icon small">[{{ vendorInitial(conversation.vendor) }}]</span>
            <span>{{ conversation.vendor?.name || "Unknown" }}</span>
            <span class="vendor-level">[Lv.{{ conversation.trustLevel || 1 }}]</span>
          </div>
        </div>

        <div class="messages-container" ref="messagesContainer">
          <div
            v-for="(msg, idx) in displayedMessages"
            :key="idx"
            class="message"
            :class="[msg.sender, { 'typing': msg.isTyping }]"
          >
            <template v-if="msg.sender === 'vendor'">
              <span class="message-prefix">&gt;</span>
              <span class="message-content">{{ msg.displayText }}<span v-if="msg.isTyping" class="typing-cursor">_</span></span>
            </template>
            <template v-else-if="msg.sender === 'player'">
              <span class="message-prefix">&lt;</span>
              <span class="message-content">{{ msg.text }}</span>
            </template>
            <template v-else-if="msg.sender === 'system'">
              <span class="system-text">{{ msg.text }}</span>
            </template>
          </div>
        </div>

        <!-- Strike Warning -->
        <div class="strike-warning" v-if="conversation.strikes > 0">
          ! WARNING: {{ conversation.strikes }}/{{ conversation.maxStrikes }} strikes
        </div>

        <div class="choices-container" v-if="canShowChoices">
          <div class="choices-label">&gt; Select response:</div>
          <button
            v-for="choice in conversation.choices"
            :key="choice.id"
            class="win95-btn choice-btn"
            @click="selectChoice(choice.id)"
            :disabled="store.loading || isTyping"
          >
            {{ choice.text }}
          </button>
        </div>

        <div class="conversation-end" v-else-if="conversation.ended && !isTyping">
          <p>&gt; Connection terminated._</p>
          <button class="win95-btn full" @click="closeConversation">Return to Vendors</button>
        </div>
      </template>

      <!-- Status Bar -->
      <div class="browser-statusbar">
        <span class="status-text">{{ statusText }}</span>
        <span class="status-secure">[ENCRYPTED]</span>
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from "vue"
import { useMySummerDeepWebStore } from "../../stores/mysummerDeepWebStore"

const props = defineProps({
  compact: {
    type: Boolean,
    default: false,
  },
})

const store = useMySummerDeepWebStore()

// Refs
const messagesContainer = ref(null)
const codeContainer = ref(null)

// Hacking animation state
const showHackingAnimation = ref(true)
const hackingLines = ref([])
const hackingStatus = ref("INITIALIZING SECURE TUNNEL...")
let hackingInterval = null
let lineId = 0

// Typing effect state
const displayedMessages = ref([])
const isTyping = ref(false)
let typingTimeout = null
let messageQueue = []

const vendors = computed(() => store.vendors || [])
const conversation = computed(() => store.conversation)

const canShowChoices = computed(() => {
  return conversation.value?.choices?.length > 0 && !isTyping.value
})

const statusText = computed(() => {
  if (store.loading) return "Loading..."
  if (isTyping.value) return "Receiving data..."
  if (conversation.value) return `Connected to: ${conversation.value.vendor?.name || 'Unknown'}`
  return "Ready"
})

const vendorInitial = (vendor) => {
  if (!vendor || !vendor.name) return "?"
  return vendor.name.charAt(0).toUpperCase()
}

const formatCooldown = (seconds) => {
  if (!seconds || seconds <= 0) return "now"
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  if (mins > 0) {
    return `${mins}m ${secs}s`
  }
  return `${secs}s`
}

const handleVendorClick = async (vendor) => {
  if (vendor.locked || vendor.onCooldown) return
  await store.startConversation(vendor.id)
}

const selectChoice = async (choiceId) => {
  if (isTyping.value) return
  try {
    await store.respondToVendor(choiceId)
  } catch (err) {
    console.error("[MySummerDeepWeb] respondToVendor error:", err)
  }
}

const closeConversation = () => {
  isTyping.value = false
  if (typingTimeout) clearTimeout(typingTimeout)
  messageQueue = []
  displayedMessages.value = []
  store.closeConversation()
}

// Typing effect - type out vendor messages character by character
const typeMessage = (message, index) => {
  return new Promise((resolve) => {
    if (message.sender !== 'vendor') {
      displayedMessages.value[index] = { ...message, displayText: message.text }
      scrollToBottom()
      resolve()
      return
    }

    const text = message.text || ""
    let charIndex = 0
    displayedMessages.value[index] = { ...message, displayText: "", isTyping: true }

    const typeChar = () => {
      if (charIndex < text.length) {
        displayedMessages.value[index].displayText = text.substring(0, charIndex + 1)
        charIndex++
        scrollToBottom()
        const delay = 25 + Math.random() * 35
        typingTimeout = setTimeout(typeChar, delay)
      } else {
        displayedMessages.value[index].isTyping = false
        resolve()
      }
    }

    typeChar()
  })
}

const processMessageQueue = async () => {
  isTyping.value = true

  while (messageQueue.length > 0) {
    const message = messageQueue.shift()
    const index = displayedMessages.value.length
    displayedMessages.value.push({ ...message, displayText: "" })

    await typeMessage(message, index)

    if (messageQueue.length > 0 && message.sender === 'vendor') {
      await new Promise(r => setTimeout(r, 400))
    }
  }

  isTyping.value = false
}

const scrollToBottom = () => {
  nextTick(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
    }
  })
}

// Watch for new messages from conversation
watch(() => conversation.value?.messages, (newMessages) => {
  if (!newMessages) {
    displayedMessages.value = []
    return
  }

  const currentCount = displayedMessages.value.length
  const newMsgs = newMessages.slice(currentCount)

  if (newMsgs.length > 0) {
    messageQueue.push(...newMsgs)
    if (!isTyping.value) {
      processMessageQueue()
    }
  }
}, { deep: true, immediate: true })

// Hacking animation
const generateRandomCode = () => {
  const types = [
    () => `0x${Math.random().toString(16).substr(2, 8).toUpperCase()} RECV ${Math.floor(Math.random() * 9999)}`,
    () => `[${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}] CONNECT`,
    () => `TCP/IP HANDSHAKE ${Math.random() > 0.5 ? 'OK' : 'ACK'} SEQ=${Math.floor(Math.random() * 99999)}`,
    () => `ENCRYPT: AES-256 KEY=${Math.random().toString(36).substr(2, 16).toUpperCase()}`,
    () => `PROXY: NODE_${Math.floor(Math.random() * 99)} -> ${Math.random() > 0.5 ? 'FORWARD' : 'TUNNEL'}`,
  ]
  return types[Math.floor(Math.random() * types.length)]()
}

const startHackingAnimation = () => {
  const statusMessages = [
    "INITIALIZING SECURE TUNNEL...",
    "ROUTING THROUGH PROXY NODES...",
    "ESTABLISHING ENCRYPTED CHANNEL...",
    "CONNECTING TO SILKROAD...",
    "CONNECTION ESTABLISHED"
  ]
  let statusIndex = 0

  hackingInterval = setInterval(() => {
    hackingLines.value.push({
      id: lineId++,
      text: generateRandomCode()
    })
    if (hackingLines.value.length > 25) {
      hackingLines.value.shift()
    }
  }, 80)

  const statusInterval = setInterval(() => {
    statusIndex++
    if (statusIndex < statusMessages.length) {
      hackingStatus.value = statusMessages[statusIndex]
    }
  }, 600)

  setTimeout(() => {
    clearInterval(hackingInterval)
    clearInterval(statusInterval)
    showHackingAnimation.value = false
    store.requestData()
  }, 3000)
}

onMounted(() => {
  startHackingAnimation()
})

onUnmounted(() => {
  if (hackingInterval) clearInterval(hackingInterval)
  if (typingTimeout) clearTimeout(typingTimeout)
  store.dispose()
})
</script>

<style scoped lang="scss">
// Windows 95 Color Palette
$win-gray: #c0c0c0;
$win-dark-gray: #808080;
$win-light-gray: #dfdfdf;
$win-white: #ffffff;
$win-black: #000000;
$win-blue: #000080;
$win-cyan: #008080;

// 3D Border Mixin
@mixin win-raised {
  border: 2px solid;
  border-color: $win-white $win-dark-gray $win-dark-gray $win-white;
}

@mixin win-sunken {
  border: 2px solid;
  border-color: $win-dark-gray $win-white $win-white $win-dark-gray;
}

.deepweb-root {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
  background: $win-gray;
  font-family: 'Courier New', 'Lucida Console', monospace;
  font-size: 14px;
  color: $win-black;
}

.deepweb-root.compact {
  padding-top: 3rem;
}

// Hacking Animation
.hacking-overlay {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: #000;
  z-index: 100;
  display: flex;
  flex-direction: column;
}

.hacking-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  padding: 1rem;
  overflow: hidden;
}

.code-lines {
  flex: 1;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}

.code-line {
  color: #00ff00;
  font-family: 'Courier New', monospace;
  font-size: 13px;
  line-height: 1.4;
  opacity: 0.8;
  white-space: nowrap;
}

.hacking-status {
  margin-top: 1rem;
  padding: 0.5rem;
  text-align: center;
  color: #00ff00;
  font-weight: bold;
  font-size: 16px;
}

// Browser Frame
.browser-frame {
  @include win-raised;
  background: $win-gray;
}

.browser-titlebar {
  background: linear-gradient(to right, $win-blue, $win-cyan);
  color: $win-white;
  padding: 3px 6px;
  display: flex;
  align-items: center;
  font-weight: bold;
  font-size: 14px;
}

.titlebar-icon {
  margin-right: 8px;
}

.titlebar-text {
  flex: 1;
}

.titlebar-buttons {
  display: flex;
  gap: 2px;

  span {
    @include win-raised;
    background: $win-gray;
    color: $win-black;
    width: 18px;
    height: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    cursor: pointer;

    &:active {
      @include win-sunken;
    }
  }
}

.browser-menubar {
  background: $win-gray;
  padding: 3px 6px;
  border-bottom: 1px solid $win-dark-gray;
  font-size: 14px;
}

.menu-item {
  padding: 2px 10px;
  cursor: pointer;

  &:hover {
    background: $win-blue;
    color: $win-white;
  }
}

.browser-addressbar {
  @include win-sunken;
  background: $win-white;
  margin: 4px;
  padding: 4px 8px;
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 14px;
}

.address-label {
  color: $win-black;
}

.address-input {
  flex: 1;
}

.address-text {
  color: $win-blue;
}

// Header
.deepweb-header {
  padding: 12px;
  text-align: center;
  border-bottom: 1px solid $win-dark-gray;

  h2 {
    margin: 0;
    font-size: 18px;
    color: $win-blue;
    font-weight: bold;
  }

  p {
    margin: 6px 0 0;
    font-size: 13px;
    color: $win-dark-gray;
  }
}

// Vendor List
.vendors-list {
  flex: 1;
  overflow: auto;
  padding: 8px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.vendor-card {
  @include win-raised;
  background: $win-gray;
  padding: 12px;
  display: flex;
  align-items: center;
  gap: 12px;
  cursor: pointer;

  &:hover:not(.locked):not(.on-cooldown) {
    background: $win-light-gray;
  }

  &:active:not(.locked):not(.on-cooldown) {
    @include win-sunken;
  }

  &.locked, &.on-cooldown {
    opacity: 0.6;
    cursor: not-allowed;
  }
}

.vendor-icon {
  font-weight: bold;
  color: $win-blue;
  font-size: 18px;

  &.small {
    font-size: 14px;
  }
}

.vendor-info {
  flex: 1;
}

.vendor-name {
  font-weight: bold;
  color: $win-black;
  font-size: 16px;
}

.vendor-specialty {
  font-size: 13px;
  color: $win-dark-gray;
  margin-top: 2px;
}

.vendor-status {
  margin-top: 4px;
  font-size: 12px;
}

.status-locked {
  color: #800000;
}

.status-cooldown {
  color: #806000;
}

.status-trust {
  color: $win-cyan;
}

.vendor-arrow {
  color: $win-dark-gray;
  font-size: 16px;
}

// Conversation
.conversation-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px;
  border-bottom: 1px solid $win-dark-gray;
}

.conversation-vendor {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: bold;
  font-size: 15px;
}

.vendor-level {
  color: $win-cyan;
  font-size: 13px;
}

.messages-container {
  flex: 1;
  overflow: auto;
  padding: 12px;
  @include win-sunken;
  background: $win-white;
  margin: 6px;
  min-height: 200px;
}

.message {
  margin-bottom: 10px;
  display: flex;
  gap: 8px;
  line-height: 1.5;
  font-size: 14px;
}

.message-prefix {
  color: $win-dark-gray;
  font-weight: bold;
  flex-shrink: 0;
}

.message.vendor .message-prefix {
  color: $win-blue;
}

.message.player .message-prefix {
  color: $win-cyan;
}

.message-content {
  flex: 1;
}

.typing-cursor {
  animation: cursor-blink 0.6s infinite;
  color: $win-blue;
}

@keyframes cursor-blink {
  0%, 50% { opacity: 1; }
  51%, 100% { opacity: 0; }
}

.system-text {
  color: $win-dark-gray;
  font-style: italic;
  font-size: 13px;
  width: 100%;
  text-align: center;
}

// Strike Warning
.strike-warning {
  padding: 6px 12px;
  background: #ffe0e0;
  border-top: 2px solid #800000;
  color: #800000;
  font-size: 13px;
  font-weight: bold;
  text-align: center;
}

// Choices
.choices-container {
  padding: 12px;
  border-top: 1px solid $win-dark-gray;
}

.choices-label {
  margin-bottom: 8px;
  color: $win-dark-gray;
  font-size: 13px;
}

// Windows 95 Button
.win95-btn {
  @include win-raised;
  background: $win-gray;
  color: $win-black;
  padding: 8px 16px;
  font-family: 'Courier New', monospace;
  font-size: 14px;
  cursor: pointer;
  border-radius: 0;

  &:hover {
    background: $win-light-gray;
  }

  &:active {
    @include win-sunken;
  }

  &:disabled {
    color: $win-dark-gray;
    cursor: not-allowed;
  }

  &.full {
    width: 100%;
    margin-top: 10px;
  }
}

.choice-btn {
  display: block;
  width: 100%;
  text-align: left;
  margin-bottom: 6px;
  padding: 10px 14px;
}

.conversation-end {
  text-align: center;
  padding: 1.5rem;

  p {
    margin: 0 0 12px;
    color: $win-dark-gray;
    font-size: 14px;
  }
}

.empty-state {
  padding: 2rem;
  text-align: center;
  color: $win-dark-gray;
  font-size: 14px;
}

// Status Bar
.browser-statusbar {
  @include win-sunken;
  background: $win-gray;
  padding: 4px 10px;
  display: flex;
  justify-content: space-between;
  font-size: 13px;
}

.status-text {
  color: $win-black;
}

.status-secure {
  color: $win-cyan;
}

// Scrollbar styling (Windows 95 look)
.vendors-list::-webkit-scrollbar,
.messages-container::-webkit-scrollbar {
  width: 16px;
}

.vendors-list::-webkit-scrollbar-track,
.messages-container::-webkit-scrollbar-track {
  background: $win-gray;
  border: 1px solid $win-dark-gray;
}

.vendors-list::-webkit-scrollbar-thumb,
.messages-container::-webkit-scrollbar-thumb {
  @include win-raised;
  background: $win-gray;
}
</style>
