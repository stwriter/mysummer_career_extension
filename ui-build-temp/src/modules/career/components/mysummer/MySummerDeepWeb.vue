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
          <span class="blink">{{ hackingStatus }}</span>
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
            <span class="address-text">darknet://underground.parts/vendors</span>
          </div>
        </div>
      </div>

      <!-- Vendor List View -->
      <template v-if="!conversation">
        <div class="deepweb-header">
          <h2>:: UNDERGROUND PARTS NETWORK ::</h2>
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
            :class="{ locked: vendor.locked }"
            @click="!vendor.locked && openVendor(vendor.id)"
          >
            <div class="vendor-icon">[{{ vendorInitial(vendor) }}]</div>
            <div class="vendor-info">
              <div class="vendor-name">&gt; {{ vendor.name }}</div>
              <div class="vendor-specialty">{{ vendor.specialty }}</div>
              <div class="vendor-status">
                <span v-if="vendor.locked" class="status-locked">[LOCKED]</span>
                <span v-else-if="vendor.trustLevel" class="status-trust">[TRUST: {{ vendor.trustLevel }} pts]</span>
              </div>
            </div>
            <div class="vendor-arrow" v-if="!vendor.locked">&gt;&gt;</div>
          </div>
        </div>
      </template>

      <!-- Conversation View -->
      <template v-else>
        <div class="conversation-header">
          <button class="win95-btn" @click="closeConversation">&lt; Back</button>
          <div class="conversation-vendor">
            <span class="vendor-icon small">[{{ vendorInitial(conversation.vendor) }}]</span>
            <span>Chat with: {{ conversation.vendor?.name || "Unknown" }}</span>
          </div>
        </div>

        <div class="messages-container">
          <div
            v-for="(msg, idx) in conversation.messages"
            :key="idx"
            class="message"
            :class="[msg.sender, { 'system-message': msg.isSystemMessage, 'pause-message': msg.isPause, 'positive': msg.pointsChange > 0, 'negative': msg.pointsChange < 0 }]"
          >
            <template v-if="msg.isPause">
              <span class="pause-dots">...</span>
            </template>
            <template v-else-if="msg.isSystemMessage">
              <span class="system-text">{{ msg.text }}</span>
            </template>
            <template v-else>
              <span class="message-prefix">{{ msg.sender === 'vendor' ? '&gt;' : '&lt;' }}</span>
              <span class="message-content">{{ msg.text }}</span>
            </template>
          </div>
        </div>

        <!-- Session Stats -->
        <div class="session-stats" v-if="conversation.sessionPoints !== undefined">
          <span class="stat-item" :class="{ positive: conversation.sessionPoints > 0, negative: conversation.sessionPoints < 0 }">
            Session: {{ conversation.sessionPoints > 0 ? '+' : '' }}{{ conversation.sessionPoints }} pts
          </span>
          <span class="stat-item" v-if="conversation.strikes > 0">
            Strikes: {{ conversation.strikes }}/{{ conversation.maxStrikes }}
          </span>
        </div>

        <div class="choices-container" v-if="conversation.choices && conversation.choices.length > 0">
          <div class="choices-label">Select response:</div>
          <button
            v-for="choice in conversation.choices"
            :key="choice.id"
            class="win95-btn choice-btn"
            @click="selectChoice(choice.id)"
            :disabled="store.loading"
          >
            {{ choice.text }}
          </button>
        </div>

        <div class="conversation-end" v-else-if="conversation.ended">
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
import { ref, computed, onMounted, onUnmounted } from "vue"
import { useMySummerDeepWebStore } from "../../stores/mysummerDeepWebStore"

const props = defineProps({
  compact: {
    type: Boolean,
    default: false,
  },
})

const store = useMySummerDeepWebStore()

// Hacking animation state
const showHackingAnimation = ref(true)
const hackingLines = ref([])
const hackingStatus = ref("INITIALIZING SECURE TUNNEL...")
const codeContainer = ref(null)
let hackingInterval = null
let lineId = 0

const vendors = computed(() => store.vendors || [])
const conversation = computed(() => store.conversation)
const statusText = computed(() => {
  if (store.loading) return "Loading..."
  if (conversation.value) return `Connected to: ${conversation.value.vendor?.name || 'Unknown'}`
  return "Ready"
})

const vendorInitial = (vendor) => {
  if (!vendor || !vendor.name) return "?"
  return vendor.name.charAt(0).toUpperCase()
}

const openVendor = async (vendorId) => {
  await store.startConversation(vendorId)
}

const selectChoice = async (choiceId) => {
  try {
    await store.respondToVendor(choiceId)
  } catch (err) {
    console.error("[MySummerDeepWeb] respondToVendor error:", err)
  }
}

const closeConversation = () => {
  store.closeConversation()
}

// Generate random hex/code strings
const generateRandomCode = () => {
  const types = [
    () => `0x${Math.random().toString(16).substr(2, 8).toUpperCase()} RECV ${Math.floor(Math.random() * 9999)}`,
    () => `[${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}.${Math.floor(Math.random() * 255)}] CONNECT`,
    () => `TCP/IP HANDSHAKE ${Math.random() > 0.5 ? 'OK' : 'ACK'} SEQ=${Math.floor(Math.random() * 99999)}`,
    () => `ENCRYPT: AES-256 KEY=${Math.random().toString(36).substr(2, 16).toUpperCase()}`,
    () => `PROXY: NODE_${Math.floor(Math.random() * 99)} -> ${Math.random() > 0.5 ? 'FORWARD' : 'TUNNEL'}`,
    () => `AUTH: ${Math.random() > 0.7 ? 'VERIFIED' : 'PENDING'} HASH=${Math.random().toString(16).substr(2, 12)}`,
  ]
  return types[Math.floor(Math.random() * types.length)]()
}

const startHackingAnimation = () => {
  const statusMessages = [
    "INITIALIZING SECURE TUNNEL...",
    "ROUTING THROUGH PROXY NODES...",
    "ESTABLISHING ENCRYPTED CHANNEL...",
    "BYPASSING SECURITY PROTOCOLS...",
    "CONNECTING TO DARKNET...",
    "CONNECTION ESTABLISHED"
  ]
  let statusIndex = 0

  // Add new code lines rapidly
  hackingInterval = setInterval(() => {
    hackingLines.value.push({
      id: lineId++,
      text: generateRandomCode()
    })

    // Keep only last 30 lines
    if (hackingLines.value.length > 30) {
      hackingLines.value.shift()
    }
  }, 100)

  // Update status messages
  const statusInterval = setInterval(() => {
    statusIndex++
    if (statusIndex < statusMessages.length) {
      hackingStatus.value = statusMessages[statusIndex]
    }
  }, 800)

  // End animation after 5 seconds
  setTimeout(() => {
    clearInterval(hackingInterval)
    clearInterval(statusInterval)
    showHackingAnimation.value = false
    store.requestData()
  }, 5000)
}

onMounted(() => {
  startHackingAnimation()
})

onUnmounted(() => {
  if (hackingInterval) {
    clearInterval(hackingInterval)
  }
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
  font-size: 12px;
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
  font-size: 11px;
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
  font-size: 14px;
}

.blink {
  animation: blink-animation 1s infinite;
}

@keyframes blink-animation {
  0%, 49% { opacity: 1; }
  50%, 100% { opacity: 0; }
}

// Browser Frame
.browser-frame {
  @include win-raised;
  background: $win-gray;
}

.browser-titlebar {
  background: linear-gradient(to right, $win-blue, $win-cyan);
  color: $win-white;
  padding: 2px 4px;
  display: flex;
  align-items: center;
  font-weight: bold;
}

.titlebar-icon {
  margin-right: 6px;
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
    width: 16px;
    height: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 10px;
    cursor: pointer;

    &:active {
      @include win-sunken;
    }
  }
}

.browser-menubar {
  background: $win-gray;
  padding: 2px 4px;
  border-bottom: 1px solid $win-dark-gray;
}

.menu-item {
  padding: 2px 8px;
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
  padding: 2px 4px;
  display: flex;
  align-items: center;
  gap: 8px;
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
  padding: 0.5rem;
  text-align: center;
  border-bottom: 1px solid $win-dark-gray;

  h2 {
    margin: 0;
    font-size: 14px;
    color: $win-blue;
    font-weight: bold;
  }

  p {
    margin: 4px 0 0;
    font-size: 11px;
    color: $win-dark-gray;
  }
}

// Vendor List
.vendors-list {
  flex: 1;
  overflow: auto;
  padding: 0.5rem;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.vendor-card {
  @include win-raised;
  background: $win-gray;
  padding: 8px;
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;

  &:hover:not(.locked) {
    background: $win-light-gray;
  }

  &:active:not(.locked) {
    @include win-sunken;
  }

  &.locked {
    opacity: 0.6;
    cursor: not-allowed;
  }
}

.vendor-icon {
  font-weight: bold;
  color: $win-blue;
  font-size: 14px;

  &.small {
    font-size: 12px;
  }
}

.vendor-info {
  flex: 1;
}

.vendor-name {
  font-weight: bold;
  color: $win-black;
}

.vendor-specialty {
  font-size: 11px;
  color: $win-dark-gray;
}

.vendor-status {
  margin-top: 2px;
}

.status-locked {
  color: #800000;
  font-size: 10px;
}

.status-trust {
  color: $win-cyan;
  font-size: 10px;
}

.vendor-arrow {
  color: $win-dark-gray;
}

// Conversation
.conversation-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px;
  border-bottom: 1px solid $win-dark-gray;
}

.conversation-vendor {
  display: flex;
  align-items: center;
  gap: 4px;
  font-weight: bold;
}

.messages-container {
  flex: 1;
  overflow: auto;
  padding: 8px;
  @include win-sunken;
  background: $win-white;
  margin: 4px;
}

.message {
  margin-bottom: 8px;
  display: flex;
  gap: 4px;
}

.message-prefix {
  color: $win-dark-gray;
  font-weight: bold;
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

// System messages (feedback, strikes, etc)
.message.system-message {
  justify-content: center;
  margin: 4px 0;

  .system-text {
    font-size: 10px;
    padding: 2px 8px;
    background: $win-gray;
    border: 1px solid $win-dark-gray;
  }

  &.positive .system-text {
    color: #008000;
    background: #e0ffe0;
    border-color: #008000;
  }

  &.negative .system-text {
    color: #800000;
    background: #ffe0e0;
    border-color: #800000;
  }
}

// Pause messages (...)
.message.pause-message {
  justify-content: center;
  margin: 12px 0;

  .pause-dots {
    color: $win-dark-gray;
    font-size: 16px;
    letter-spacing: 4px;
    animation: pulse 1.5s ease-in-out infinite;
  }
}

@keyframes pulse {
  0%, 100% { opacity: 0.3; }
  50% { opacity: 1; }
}

// Session stats bar
.session-stats {
  display: flex;
  justify-content: space-between;
  padding: 4px 8px;
  background: $win-gray;
  border-top: 1px solid $win-dark-gray;
  font-size: 10px;

  .stat-item {
    &.positive { color: #008000; }
    &.negative { color: #800000; }
  }
}

// Choices
.choices-container {
  padding: 8px;
  border-top: 1px solid $win-dark-gray;
}

.choices-label {
  margin-bottom: 4px;
  color: $win-dark-gray;
  font-size: 11px;
}

// Windows 95 Button
.win95-btn {
  @include win-raised;
  background: $win-gray;
  color: $win-black;
  padding: 4px 12px;
  font-family: 'Courier New', monospace;
  font-size: 12px;
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
    margin-top: 8px;
  }
}

.choice-btn {
  display: block;
  width: 100%;
  text-align: left;
  margin-bottom: 4px;
}

.conversation-end {
  text-align: center;
  padding: 1rem;

  p {
    margin: 0 0 8px;
    color: $win-dark-gray;
  }
}

.empty-state {
  padding: 2rem;
  text-align: center;
  color: $win-dark-gray;
}

// Status Bar
.browser-statusbar {
  @include win-sunken;
  background: $win-gray;
  padding: 2px 8px;
  display: flex;
  justify-content: space-between;
  font-size: 11px;
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
