<template>
  <div class="deepweb-page">
    <!-- Deep Web Header -->
    <div class="dw-header">
      <div class="dw-ascii">
        <pre>
  ____  _____ _____ ____   __        _______ ____
 |  _ \| ____| ____|  _ \  \ \      / / ____| __ )
 | | | |  _| |  _| | |_) |  \ \ /\ / /|  _| |  _ \
 | |_| | |___| |___|  __/    \ V  V / | |___| |_) |
 |____/|_____|_____|_|        \_/\_/  |_____|____/
     A C C E S S   P O I N T   [SECURE]
        </pre>
      </div>
      <div class="dw-warning">
        <span class="warning-icon">[!]</span>
        <span>Connection encrypted via TOR network</span>
      </div>
    </div>

    <!-- Sub-Menu (when no section selected) -->
    <div v-if="!currentSection" class="dw-menu">
      <div class="menu-title">// SELECT ACCESS POINT</div>
      <div class="menu-grid">
        <button class="menu-item" @click="currentSection = 'chats'">
          <div class="item-icon chats">[<span class="blink">@</span>]</div>
          <div class="item-label">CONTACTS</div>
          <div class="item-desc">Encrypted messaging with vendors</div>
          <div class="item-status" :class="{ online: onlineVendorsCount > 0 }">{{ onlineVendorsCount }} AVAILABLE</div>
        </button>
        <button class="menu-item" @click="currentSection = 'silkroad'">
          <div class="item-icon silkroad">[<span class="blink">$</span>]</div>
          <div class="item-label">SILK ROAD</div>
          <div class="item-desc">Anonymous parts marketplace</div>
          <div class="item-status">{{ leads.length }} LISTINGS</div>
        </button>
      </div>
    </div>

    <!-- Back button when in a section -->
    <div v-if="currentSection" class="dw-nav">
      <button class="back-btn" @click="currentSection = null">
        &lt; BACK TO MENU
      </button>
      <span class="nav-title">{{ currentSection === 'chats' ? 'CONTACTS' : 'SILK ROAD' }}</span>
    </div>

    <!-- CHATS Section -->
    <div v-if="currentSection === 'chats'" class="chats-section">
      <!-- Vendor List (when no conversation active) -->
      <template v-if="!conversation">
        <div class="vendors-header">
          <span>// AVAILABLE CONTACTS</span>
          <span class="vendor-count">[{{ vendors.length }}]</span>
        </div>

        <div v-if="chatLoading" class="loading-state">
          <span class="blink">LOADING CONTACTS...</span>
        </div>

        <div v-else-if="vendors.length === 0" class="empty-vendors">
          <span>NO_CONTACTS_AVAILABLE</span>
          <span class="sub">Check back later...</span>
        </div>

        <div v-else class="vendors-list">
          <div
            v-for="vendor in sortedVendors"
            :key="vendor.id"
            class="vendor-item"
            :class="{ locked: vendor.locked, 'on-cooldown': vendor.onCooldown, 'ai-pilot': vendor.isAIPilot }"
          >
            <div class="vendor-main" @click="!vendor.locked && !vendor.onCooldown && openVendorChat(vendor.id)">
              <div class="vendor-avatar" :class="getVendorStatus(vendor)">
                <span v-if="vendor.isAIPilot" class="ai-icon">[AI]</span>
                <span v-else>[{{ getVendorInitial(vendor) }}]</span>
              </div>
              <div class="vendor-info">
                <div class="vendor-name">
                  &gt; {{ vendor.name }}
                  <span v-if="vendor.isAIPilot" class="ai-badge">ORACLE</span>
                </div>
                <div v-if="vendor.specialty && vendor.specialty.toLowerCase() !== 'unknown'" class="vendor-specialty">{{ vendor.specialty }}</div>
                <div v-if="vendor.locked && vendor.unlockedBy" class="vendor-locked-hint">
                  Build trust with {{ vendor.unlockedBy }} to unlock
                </div>
                <div v-else-if="vendor.onCooldown" class="vendor-cooldown-hint">
                  Available in <span class="cooldown-time">{{ formatCooldown(vendor.cooldownRemaining) }}</span>
                </div>
                <!-- Show traits hint for contacts with traits defined -->
                <div v-if="!vendor.locked && vendor.traits && vendor.traits.values" class="vendor-traits-hint">
                  Values: {{ vendor.traits.values.slice(0, 3).join(', ') }}
                </div>
              </div>
              <div class="vendor-meta">
                <span v-if="vendor.locked" class="status-locked">[LOCKED]</span>
                <span v-else-if="vendor.onCooldown" class="status-cooldown">[BUSY]</span>
                <span v-else class="status-trust">
                  [LVL {{ vendor.trustLevel || 1 }}]
                  <span class="xp-display">{{ vendor.trustXP || 0 }} XP</span>
                </span>
              </div>
              <div class="vendor-arrow" v-if="!vendor.locked && !vendor.onCooldown">&gt;&gt;</div>
            </div>
          </div>
        </div>
      </template>

      <!-- Conversation View -->
      <template v-else>
        <div class="chat-header">
          <button class="back-btn" @click="closeChat">&lt; BACK</button>
          <span class="chat-name">[{{ getVendorInitial(conversation.vendor) }}] {{ conversation.vendor?.name }}</span>
        </div>

        <div class="chat-messages" ref="chatMessagesRef">
          <div
            v-for="(msg, idx) in displayedMessages"
            :key="idx"
            class="chat-message"
            :class="[msg.sender === 'vendor' ? 'received' : 'sent', { typing: msg.isTyping }]"
          >
            <span class="msg-prefix">{{ msg.sender === 'vendor' ? '>' : '<' }}</span>
            <span class="msg-text">{{ msg.displayText || msg.text }}<span v-if="msg.isTyping" class="typing-cursor">_</span></span>
          </div>
        </div>

        <!-- AI Free Text Input -->
        <div v-if="conversation.isAI && conversation.waitingForInput && !conversation.ended" class="ai-input-section">
          <div class="ai-input-label">// ENTER MESSAGE:</div>
          <div class="ai-input-wrapper">
            <textarea
              v-model="aiMessageInput"
              class="ai-textarea"
              placeholder="Type your message..."
              :disabled="chatLoading"
              @keydown.enter.ctrl="sendAIMessageHandler"
              rows="2"
            ></textarea>
            <button
              class="ai-send-btn"
              @click="sendAIMessageHandler"
              :disabled="chatLoading || !aiMessageInput.trim()"
            >
              <span v-if="chatLoading" class="blink">[...]</span>
              <span v-else>[SEND]</span>
            </button>
          </div>
          <div class="ai-input-hint">Ctrl+Enter to send | AI-powered conversation</div>
          <button class="end-chat-btn" @click="endAIChat">[END CONVERSATION]</button>
        </div>

        <!-- AI Not Configured Warning -->
        <div v-else-if="conversation.isAI && conversation.aiNotConfigured" class="ai-not-configured">
          <div class="warning-icon">[!]</div>
          <div class="warning-text">AI not configured</div>
          <div class="warning-hint">Set up API key in settings to enable Oracle conversations</div>
          <button class="back-btn full" @click="closeChat">RETURN TO CONTACTS</button>
        </div>

        <!-- Response Choices (for scripted conversations) -->
        <div v-else-if="conversation.choices && conversation.choices.length > 0 && !isTyping" class="chat-choices">
          <div class="choices-label">// SELECT RESPONSE:</div>
          <button
            v-for="choice in conversation.choices"
            :key="choice.id"
            class="choice-btn"
            @click="selectChatChoice(choice.id)"
            :disabled="chatLoading || isTyping"
          >
            {{ choice.text }}
          </button>
        </div>

        <div v-else-if="conversation.ended && !isTyping" class="chat-ended">
          <span>&gt; CONNECTION TERMINATED._</span>
          <button class="back-btn full" @click="closeChat">RETURN TO CONTACTS</button>
        </div>
      </template>
    </div>

    <!-- SILK ROAD Section (Parts Marketplace) -->
    <div v-if="currentSection === 'silkroad'" class="silkroad-section">
      <!-- Navigation Tabs -->
      <div class="sr-tabs">
        <button class="sr-tab" :class="{ active: activeTab === 'listings' }" @click="activeTab = 'listings'">
          > LISTINGS [{{ leads.length }}]
        </button>
        <button class="sr-tab" :class="{ active: activeTab === 'active' }" @click="activeTab = 'active'">
          > ACTIVE OP
          <span v-if="activePickup" class="blink">*</span>
        </button>
      </div>

      <!-- Listings -->
      <div v-if="activeTab === 'listings'" class="listings-content">
        <div class="section-header">
          <span class="header-text">// AVAILABLE PARTS</span>
          <span class="header-count">[{{ leads.length }} items]</span>
        </div>

        <div v-if="leads.length === 0" class="empty-message">
          <span>NO_ACTIVE_LISTINGS</span>
          <span class="sub">Check back later for new stock</span>
        </div>

        <div class="leads-list">
          <div
            v-for="lead in leads"
            :key="lead.id"
            class="lead-card"
            :class="`heat-${lead.heat}`"
          >
            <div class="lead-header">
              <span class="lead-heat">
                <span class="heat-indicator"></span>
                {{ getHeatLabel(lead.heat) }}
              </span>
              <span class="lead-expires">TTL: {{ formatTimeRemaining(lead.expiresAt) }}</span>
            </div>

            <div class="lead-body">
              <h3 class="lead-title">{{ lead.partNiceName || lead.partName }}</h3>
              <p class="lead-message">"{{ lead.message }}"</p>
            </div>

            <div class="lead-location">
              <span class="loc-label">DROP POINT:</span>
              <span class="loc-value">{{ lead.location?.name || "UNKNOWN" }}</span>
            </div>

            <div class="lead-footer">
              <span class="lead-price">
                ${{ calculatePrice(lead).toLocaleString() }}
                <span class="price-discount">(-{{ getDiscount(lead) }}% off retail)</span>
              </span>
              <button class="lead-btn" @click="acceptLead(lead)">
                [BUY NOW]
              </button>
            </div>

            <div class="lead-warning">
              <span v-if="lead.heat === 'extreme'">!! HIGH PURSUIT RISK - HOT MERCHANDISE !!</span>
              <span v-else-if="lead.heat === 'hot'">! MODERATE RISK - PROCEED WITH CAUTION !</span>
              <span v-else>LOW PROFILE - MINIMAL HEAT</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Active Operation -->
      <div v-if="activeTab === 'active'" class="active-content">
        <div class="section-header">
          <span class="header-text">// ACTIVE OPERATION</span>
        </div>

        <div v-if="!activePickup" class="empty-message">
          <span>NO_ACTIVE_OPERATION</span>
          <span class="sub">Purchase a part to begin pickup</span>
        </div>

        <div v-else class="active-card">
          <div class="active-status">
            <span class="status-indicator blink"></span>
            <span>PICKUP IN PROGRESS</span>
          </div>

          <div class="active-details">
            <div class="detail-row">
              <span class="detail-key">TARGET:</span>
              <span class="detail-val">{{ activePickup.partNiceName || activePickup.partName }}</span>
            </div>
            <div class="detail-row">
              <span class="detail-key">LOCATION:</span>
              <span class="detail-val">{{ activePickup.location?.name || "UNKNOWN" }}</span>
            </div>
            <div class="detail-row">
              <span class="detail-key">DISTANCE:</span>
              <span class="detail-val">{{ formatDistance(activePickup.distance) }}</span>
            </div>
          </div>

          <div v-if="activePickup.isIllegal" class="pursuit-warning">
            <span class="blink">[!]</span>
            EXPECT POLICE PURSUIT AFTER PICKUP
            <span class="blink">[!]</span>
          </div>

          <button class="abort-btn" @click="cancelPickup">
            [ABORT_OPERATION]
          </button>
        </div>
      </div>
    </div>

    <!-- Heat Indicator Bar (only show if heat > 0) -->
    <div v-if="heatInfo.heat > 0" class="heat-bar" :class="heatBarClass">
      <div class="heat-label">
        <span class="heat-icon">[!]</span>
        <span>HEAT LEVEL:</span>
      </div>
      <div class="heat-meter">
        <div class="heat-fill" :style="{ width: heatPercent + '%' }"></div>
      </div>
      <div class="heat-value">{{ heatInfo.heat }}/{{ heatInfo.maxHeat }}</div>
      <button
        v-if="showClearHeatButton"
        class="clear-heat-btn"
        @click="clearHeat"
        :disabled="chatLoading"
      >
        [CLEAN: ${{ heatInfo.clearPrice }}]
      </button>
    </div>

    <!-- Footer -->
    <div class="dw-footer">
      <span>Connection: ENCRYPTED</span>
      <span>|</span>
      <span>Identity: ANONYMOUS</span>
      <span>|</span>
      <span class="blink">*</span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from "vue"
import { useMySummerPartsStore } from "../../../stores/mysummerPartsStore"
import { useMySummerDeepWebStore } from "../../../stores/mysummerDeepWebStore"

const emit = defineEmits(["navigate"])
const partsStore = useMySummerPartsStore()
const deepWebStore = useMySummerDeepWebStore()

const currentSection = ref(null) // null = menu, 'chats', 'silkroad'
const activeTab = ref("listings")

// Typing effect state
const displayedMessages = ref([])
const isTyping = ref(false)
let typingTimeout = null
let messageQueue = []
const chatMessagesRef = ref(null)

// Vendor/Chat data from store
const vendors = computed(() => deepWebStore.vendors || [])
const conversation = computed(() => deepWebStore.conversation)
const chatLoading = computed(() => deepWebStore.loading || isTyping.value)

// Parts/leads data
const leads = computed(() => partsStore.marketData.leads || [])
const activePickup = computed(() => {
  const pickup = partsStore.marketData.activePickup
  return pickup?.isIllegal ? pickup : null
})

// Online vendors count
const onlineVendorsCount = computed(() => {
  return vendors.value.filter(v => !v.locked).length
})

// Heat system
const heatInfo = computed(() => deepWebStore.heatInfo || { heat: 0, maxHeat: 100, canClear: false, clearPrice: 5000 })

const heatPercent = computed(() => {
  if (!heatInfo.value.maxHeat) return 0
  return Math.round((heatInfo.value.heat / heatInfo.value.maxHeat) * 100)
})

const heatBarClass = computed(() => {
  const heat = heatInfo.value.heat
  if (heat >= 75) return 'heat-critical'
  if (heat >= 50) return 'heat-high'
  if (heat >= 25) return 'heat-medium'
  return 'heat-low'
})

// Check if Shadow is available and can clear heat
const showClearHeatButton = computed(() => {
  // Shadow must be unlocked (check vendors)
  const shadow = vendors.value.find(v => v.id === 'shadow')
  return shadow && !shadow.locked && heatInfo.value.canClear
})

const clearHeat = async () => {
  const result = await deepWebStore.clearHeatWithShadow()
  if (result && !result.success) {
    console.log("[DeepWebPage] Failed to clear heat:", result.message)
  }
}

// Define the unlock chain order for sorting
const unlockOrder = ['ghost', 'techie', 'muscle', 'import', 'shadow', 'oracle']

// Sort vendors: available first in chain order, then locked in chain order
// Oracle (AI pilot) is always shown at the end of available contacts
const sortedVendors = computed(() => {
  return [...vendors.value].sort((a, b) => {
    // Available contacts first
    if (!a.locked && b.locked) return -1
    if (a.locked && !b.locked) return 1

    // Oracle always last among available contacts
    if (a.isAIPilot && !b.isAIPilot) return 1
    if (!a.isAIPilot && b.isAIPilot) return -1

    // Within same lock status, sort by unlock chain order
    const orderA = unlockOrder.indexOf(a.id)
    const orderB = unlockOrder.indexOf(b.id)
    return orderA - orderB
  })
})

// Cooldown timer update (every second)
const cooldownInterval = ref(null)

const startCooldownTimer = () => {
  if (cooldownInterval.value) return
  cooldownInterval.value = setInterval(() => {
    // Force reactivity update for cooldown displays
    deepWebStore.requestData()
  }, 5000) // Update every 5 seconds to reduce API calls
}

const stopCooldownTimer = () => {
  if (cooldownInterval.value) {
    clearInterval(cooldownInterval.value)
    cooldownInterval.value = null
  }
}

// Format cooldown time remaining
const formatCooldown = (seconds) => {
  if (!seconds || seconds <= 0) return ""
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  if (mins > 0) {
    return `${mins}m ${secs}s`
  }
  return `${secs}s`
}

// Vendor helpers
const getVendorInitial = (vendor) => {
  if (!vendor || !vendor.name) return "?"
  return vendor.name.charAt(0).toUpperCase()
}

const getVendorStatus = (vendor) => {
  if (vendor.locked) return "locked"
  if (vendor.trustLevel && vendor.trustLevel >= 50) return "online"
  if (vendor.trustLevel && vendor.trustLevel >= 20) return "away"
  return "offline"
}

const openVendorChat = async (vendorId) => {
  await deepWebStore.startConversation(vendorId)
}

const selectChatChoice = async (choiceId) => {
  await deepWebStore.respondToVendor(choiceId)
}

const closeChat = () => {
  isTyping.value = false
  if (typingTimeout) clearTimeout(typingTimeout)
  messageQueue = []
  displayedMessages.value = []
  deepWebStore.closeConversation()
}

// Typing effect - type out vendor messages character by character
const scrollToBottom = () => {
  nextTick(() => {
    if (chatMessagesRef.value) {
      chatMessagesRef.value.scrollTop = chatMessagesRef.value.scrollHeight
    }
  })
}

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

    // Small pause before vendor starts typing
    typingTimeout = setTimeout(() => {
      const typeChar = () => {
      if (charIndex < text.length) {
        displayedMessages.value[index].displayText = text.substring(0, charIndex + 1)
        charIndex++
        scrollToBottom()
        const delay = 20 + Math.random() * 30
        typingTimeout = setTimeout(typeChar, delay)
      } else {
        displayedMessages.value[index].isTyping = false
        resolve()
      }
    }

      typeChar()
    }, 600 + Math.random() * 400) // 600-1000ms pause before typing
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
      await new Promise(r => setTimeout(r, 300))
    }
  }

  isTyping.value = false
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

// AI Conversation
const aiMessageInput = ref("")

const sendAIMessageHandler = async () => {
  if (!aiMessageInput.value.trim() || chatLoading.value) return

  const message = aiMessageInput.value.trim()
  aiMessageInput.value = ""

  try {
    await deepWebStore.sendAIMessage(message)
  } catch (err) {
    console.error("[DeepWebPage] Error sending AI message:", err)
  }
}

const endAIChat = async () => {
  await deepWebStore.endAIConversation()
  closeChat()
}

const acceptLead = async (lead) => {
  const result = await partsStore.acceptLead(lead.id)
  if (result && result.success !== false) {
    activeTab.value = "active"
  }
}

const cancelPickup = async () => {
  await partsStore.cancelPickup()
}

onMounted(async () => {
  // Load vendor data when entering chats section
  // Heat info is sent via event from Lua when getVendorData is called
  await deepWebStore.requestData()
  startCooldownTimer()
})

onUnmounted(() => {
  stopCooldownTimer()
  if (typingTimeout) clearTimeout(typingTimeout)
  deepWebStore.dispose()
})

// Calculate price based on heat level (not free anymore!)
const calculatePrice = (lead) => {
  const basePrice = lead.value || 500
  // Discounted from retail but still costs money
  // Higher heat = bigger discount (more risky = cheaper)
  switch (lead.heat) {
    case 'extreme': return Math.round(basePrice * 0.25) // 75% off - very risky
    case 'hot': return Math.round(basePrice * 0.40) // 60% off - risky
    default: return Math.round(basePrice * 0.55) // 45% off - low risk
  }
}

const getDiscount = (lead) => {
  switch (lead.heat) {
    case 'extreme': return 75
    case 'hot': return 60
    default: return 45
  }
}

const getHeatLabel = (heat) => {
  switch (heat) {
    case 'extreme': return 'EXTREME HEAT'
    case 'hot': return 'HOT'
    default: return 'LOW PROFILE'
  }
}

const formatTimeRemaining = (expiresAt) => {
  if (!expiresAt) return "--:--"
  const now = Math.floor(Date.now() / 1000)
  const diff = expiresAt - now
  if (diff <= 0) return "EXPIRED"
  const mins = Math.floor(diff / 60)
  const secs = diff % 60
  return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`
}

const formatDistance = (distance) => {
  if (!distance && distance !== 0) return "--"
  if (distance >= 1000) return `${(distance / 1000).toFixed(1)} km`
  return `${Math.round(distance)} m`
}
</script>

<style scoped lang="scss">
$terminal-green: #00ff41;
$terminal-amber: #ffb000;
$terminal-red: #ff3333;
$terminal-cyan: #00ffff;
$terminal-purple: #bf00ff;
$bg-dark: #0a0a0a;
$bg-panel: #111;

.deepweb-page {
  min-height: 100%;
  background: $bg-dark;
  color: $terminal-green;
  font-family: "Courier New", Courier, monospace;
  font-size: 14px;
  display: flex;
  flex-direction: column;

  // Scanline effect
  background-image: repeating-linear-gradient(
    0deg,
    rgba(0, 0, 0, 0.15) 0px,
    rgba(0, 0, 0, 0.15) 1px,
    transparent 1px,
    transparent 2px
  );
}

// Header
.dw-header {
  padding: 10px 15px;
  border-bottom: 1px solid #333;
  text-align: center;
}

.dw-ascii {
  pre {
    margin: 0;
    font-size: 8px;
    line-height: 1.1;
    color: $terminal-green;
    text-shadow: 0 0 10px rgba(0, 255, 65, 0.5);
  }
}

.dw-warning {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  margin-top: 8px;
  padding: 4px 8px;
  background: rgba(0, 255, 65, 0.1);
  border: 1px dashed $terminal-green;
  font-size: 10px;

  .warning-icon {
    color: $terminal-amber;
  }
}

// Sub-Menu
.dw-menu {
  flex: 1;
  padding: 20px;
}

.menu-title {
  margin-bottom: 20px;
  font-size: 11px;
  color: #666;
  text-align: center;
}

.menu-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 15px;
  max-width: 500px;
  margin: 0 auto;
}

.menu-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 20px 15px;
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid #333;
  cursor: pointer;
  transition: all 0.2s;

  &:hover {
    border-color: $terminal-green;
    background: rgba(0, 255, 65, 0.05);
    box-shadow: 0 0 15px rgba(0, 255, 65, 0.2);
  }
}

.item-icon {
  font-size: 28px;
  font-weight: bold;
  margin-bottom: 10px;

  &.chats { color: $terminal-cyan; }
  &.silkroad { color: $terminal-green; }
}

.item-label {
  font-size: 14px;
  font-weight: bold;
  color: #ddd;
  margin-bottom: 6px;
}

.item-desc {
  font-size: 10px;
  color: #666;
  text-align: center;
  margin-bottom: 8px;
}

.item-status {
  font-size: 9px;
  padding: 2px 8px;
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid #333;
  color: #888;

  &.online {
    color: $terminal-green;
    border-color: $terminal-green;
  }
}

// Navigation
.dw-nav {
  display: flex;
  align-items: center;
  padding: 8px 15px;
  border-bottom: 1px solid #333;
  background: rgba(0, 0, 0, 0.3);
}

.back-btn {
  padding: 4px 10px;
  background: transparent;
  border: 1px solid #555;
  color: #888;
  font-family: inherit;
  font-size: 10px;
  cursor: pointer;

  &:hover {
    border-color: $terminal-green;
    color: $terminal-green;
  }
}

.nav-title {
  margin-left: 15px;
  font-size: 11px;
  color: $terminal-green;
}

// Chats Section
.chats-section {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 300px;
  padding: 10px 15px;
}

.vendors-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 12px;
  padding-bottom: 4px;
  border-bottom: 1px dashed #333;
  font-size: 10px;
  color: #666;
}

.loading-state, .empty-vendors {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 40px 20px;
  color: #555;
  text-align: center;

  .sub {
    margin-top: 4px;
    font-size: 10px;
    color: #444;
  }
}

.vendors-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.vendor-item {
  display: flex;
  flex-direction: column;
  padding: 10px 12px;
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid #333;

  &:hover:not(.locked):not(.on-cooldown) {
    border-color: $terminal-cyan;
    background: rgba(0, 255, 255, 0.05);
  }

  &.locked {
    opacity: 0.5;
  }

  &.on-cooldown {
    opacity: 0.7;
    border-color: #444;
  }

  &.ai-pilot {
    border-color: $terminal-purple;
    background: rgba(191, 0, 255, 0.05);

    &:hover:not(.on-cooldown) {
      border-color: $terminal-purple;
      background: rgba(191, 0, 255, 0.15);
      box-shadow: 0 0 15px rgba(191, 0, 255, 0.3);
    }
  }
}

.vendor-main {
  display: flex;
  align-items: center;
  gap: 10px;
  cursor: pointer;

  .locked & {
    cursor: not-allowed;
  }
}

.vendor-avatar {
  font-weight: bold;
  font-size: 18px;

  &.online { color: $terminal-green; }
  &.away { color: $terminal-amber; }
  &.offline { color: #555; }
  &.locked { color: #444; }
}

.vendor-info {
  flex: 1;
}

.vendor-name {
  font-size: 16px;
  color: #ddd;
  margin-bottom: 4px;
}

.vendor-specialty {
  font-size: 14px;
  color: #888;
}

.vendor-locked-hint {
  font-size: 12px;
  color: $terminal-amber;
  font-style: italic;
  margin-top: 4px;
}

.vendor-cooldown-hint {
  font-size: 14px;
  color: $terminal-amber;
  margin-top: 4px;
  display: flex;
  align-items: center;
  gap: 4px;

  .cooldown-time {
    color: #fff;
    font-weight: bold;
  }
}

.vendor-traits-hint {
  font-size: 11px;
  color: #555;
  margin-top: 3px;
  font-style: italic;
}

.ai-icon {
  color: $terminal-purple;
  text-shadow: 0 0 8px rgba(191, 0, 255, 0.5);
}

.ai-badge {
  font-size: 8px;
  padding: 1px 4px;
  margin-left: 6px;
  background: rgba(191, 0, 255, 0.2);
  border: 1px solid $terminal-purple;
  color: $terminal-purple;
  vertical-align: middle;
}

.status-cooldown {
  color: #888;
}

.vendor-meta {
  font-size: 12px;
  text-align: right;
}

.status-locked {
  color: $terminal-red;
}

.status-trust {
  color: $terminal-cyan;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
}

.xp-display {
  font-size: 10px;
  color: #666;
}

.vendor-arrow {
  color: $terminal-green;
}

// Chat Window
.chat-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 0;
  margin-bottom: 10px;
  border-bottom: 1px solid #333;
}

.chat-name {
  font-size: 12px;
  color: $terminal-cyan;
}

.chat-messages {
  flex: 1;
  padding: 10px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 8px;
  background: rgba(0, 0, 0, 0.3);
  border: 1px solid #333;
  min-height: 200px;
}

.chat-message {
  display: flex;
  gap: 8px;
  font-size: 14px;
  line-height: 1.4;

  &.received {
    color: $terminal-cyan;
    .msg-prefix { color: $terminal-cyan; }
  }

  &.sent {
    color: $terminal-green;
    .msg-prefix { color: $terminal-green; }
  }
}

.msg-prefix {
  font-weight: bold;
}

.msg-text {
  flex: 1;
}

.typing-cursor {
  color: $terminal-cyan;
  animation: cursor-blink 0.5s infinite;
}

@keyframes cursor-blink {
  0%, 50% { opacity: 1; }
  51%, 100% { opacity: 0; }
}

.chat-choices {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px dashed #333;
}

.choices-label {
  font-size: 12px;
  color: #888;
  margin-bottom: 10px;
}

.choice-btn {
  display: block;
  width: 100%;
  padding: 10px 14px;
  margin-bottom: 8px;
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid #444;
  color: $terminal-green;
  font-family: inherit;
  font-size: 13px;
  text-align: left;
  cursor: pointer;

  &:hover:not(:disabled) {
    border-color: $terminal-green;
    background: rgba(0, 255, 65, 0.1);
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.chat-ended {
  margin-top: 10px;
  padding: 15px;
  text-align: center;
  color: #666;
  background: rgba(0, 0, 0, 0.3);
  border: 1px dashed #333;

  span {
    display: block;
    margin-bottom: 10px;
  }
}

// AI Input Section
.ai-input-section {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px dashed $terminal-purple;
}

.ai-input-label {
  font-size: 10px;
  color: $terminal-purple;
  margin-bottom: 8px;
}

.ai-input-wrapper {
  display: flex;
  gap: 8px;
  margin-bottom: 6px;
}

.ai-textarea {
  flex: 1;
  padding: 8px 10px;
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid $terminal-purple;
  color: $terminal-green;
  font-family: inherit;
  font-size: 11px;
  resize: none;
  min-height: 40px;

  &::placeholder {
    color: #555;
  }

  &:focus {
    outline: none;
    border-color: lighten($terminal-purple, 20%);
    box-shadow: 0 0 10px rgba(191, 0, 255, 0.3);
  }

  &:disabled {
    opacity: 0.5;
  }
}

.ai-send-btn {
  padding: 8px 16px;
  background: rgba(191, 0, 255, 0.1);
  border: 1px solid $terminal-purple;
  color: $terminal-purple;
  font-family: inherit;
  font-size: 11px;
  cursor: pointer;
  white-space: nowrap;

  &:hover:not(:disabled) {
    background: $terminal-purple;
    color: #000;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.ai-input-hint {
  font-size: 9px;
  color: #555;
  margin-bottom: 10px;
}

.end-chat-btn {
  width: 100%;
  padding: 6px;
  background: transparent;
  border: 1px solid #444;
  color: #666;
  font-family: inherit;
  font-size: 10px;
  cursor: pointer;

  &:hover {
    border-color: #888;
    color: #888;
  }
}

.ai-not-configured {
  margin-top: 15px;
  padding: 20px;
  text-align: center;
  background: rgba(191, 0, 255, 0.05);
  border: 1px dashed $terminal-purple;

  .warning-icon {
    font-size: 24px;
    color: $terminal-amber;
    margin-bottom: 10px;
  }

  .warning-text {
    font-size: 14px;
    color: $terminal-purple;
    margin-bottom: 6px;
  }

  .warning-hint {
    font-size: 10px;
    color: #666;
    margin-bottom: 15px;
  }
}

// Silk Road Section
.silkroad-section {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.sr-tabs {
  display: flex;
  border-bottom: 1px solid #333;
}

.sr-tab {
  flex: 1;
  padding: 8px 12px;
  background: transparent;
  border: none;
  border-right: 1px solid #333;
  color: #666;
  font-family: inherit;
  font-size: 11px;
  cursor: pointer;
  text-align: left;

  &:last-child { border-right: none; }

  &:hover {
    color: #888;
    background: rgba(255, 255, 255, 0.02);
  }

  &.active {
    color: $terminal-green;
    background: rgba(0, 255, 65, 0.05);
    text-shadow: 0 0 8px rgba(0, 255, 65, 0.3);
  }
}

.listings-content, .active-content {
  flex: 1;
  padding: 10px 15px;
  overflow-y: auto;
}

.section-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 12px;
  padding-bottom: 4px;
  border-bottom: 1px dashed #333;
  font-size: 10px;
  color: #666;
}

.empty-message {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 40px 20px;
  color: #555;
  text-align: center;

  .sub {
    margin-top: 4px;
    font-size: 10px;
    color: #444;
  }
}

// Leads/Listings
.leads-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.lead-card {
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid #333;
  border-left: 3px solid;
  padding: 10px 12px;

  &.heat-normal { border-left-color: $terminal-green; }
  &.heat-hot { border-left-color: $terminal-amber; }
  &.heat-extreme {
    border-left-color: $terminal-red;
    animation: danger-pulse 2s infinite;
  }
}

@keyframes danger-pulse {
  0%, 100% { background: rgba(255, 0, 0, 0.05); }
  50% { background: rgba(255, 0, 0, 0.15); }
}

.lead-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 8px;
  font-size: 10px;
}

.lead-heat {
  display: flex;
  align-items: center;
  gap: 4px;
  font-weight: bold;

  .heat-normal & { color: $terminal-green; }
  .heat-hot & { color: $terminal-amber; }
  .heat-extreme & { color: $terminal-red; }
}

.heat-indicator {
  width: 6px;
  height: 6px;
  background: currentColor;
  animation: blink 1s infinite;
}

.lead-expires { color: #666; }

.lead-body { margin-bottom: 8px; }

.lead-title {
  margin: 0 0 4px;
  font-size: 13px;
  font-weight: normal;
  color: #ddd;
}

.lead-message {
  margin: 0;
  font-size: 11px;
  color: #888;
  font-style: italic;

  &::before {
    content: "> ";
    color: #555;
  }
}

.lead-location {
  margin-bottom: 8px;
  padding: 4px 6px;
  background: rgba(0, 0, 0, 0.3);
  font-size: 10px;
}

.loc-label {
  color: #666;
  margin-right: 6px;
}

.loc-value {
  color: $terminal-cyan;
}

.lead-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-top: 8px;
  border-top: 1px dashed #333;
}

.lead-price {
  font-size: 14px;
  font-weight: bold;
  color: $terminal-green;
  text-shadow: 0 0 8px rgba(0, 255, 65, 0.5);
}

.price-discount {
  font-size: 9px;
  color: $terminal-amber;
  font-weight: normal;
}

.lead-btn {
  padding: 6px 12px;
  background: rgba(0, 255, 65, 0.1);
  border: 1px solid $terminal-green;
  color: $terminal-green;
  font-family: inherit;
  font-size: 10px;
  cursor: pointer;

  &:hover {
    background: $terminal-green;
    color: #000;
  }
}

.lead-warning {
  margin-top: 8px;
  padding: 4px 6px;
  font-size: 9px;
  text-align: center;

  .heat-normal & {
    color: $terminal-green;
    background: rgba(0, 255, 65, 0.1);
  }
  .heat-hot & {
    color: $terminal-amber;
    background: rgba(255, 176, 0, 0.1);
  }
  .heat-extreme & {
    color: $terminal-red;
    background: rgba(255, 51, 51, 0.1);
    animation: blink 1.5s infinite;
  }
}

// Active Operation
.active-card {
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid $terminal-green;
  padding: 15px;
}

.active-status {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 15px;
  font-size: 11px;
  font-weight: bold;
  color: $terminal-green;
}

.status-indicator {
  width: 8px;
  height: 8px;
  background: $terminal-green;
}

.active-details {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 15px;
}

.detail-row {
  display: flex;
}

.detail-key {
  min-width: 80px;
  color: #666;
}

.detail-val {
  color: $terminal-cyan;
}

.pursuit-warning {
  padding: 8px 12px;
  margin-bottom: 15px;
  background: rgba(255, 51, 51, 0.1);
  border: 1px dashed $terminal-red;
  color: $terminal-red;
  font-size: 11px;
  text-align: center;
}

.abort-btn {
  width: 100%;
  padding: 8px;
  background: transparent;
  border: 1px solid #555;
  color: #888;
  font-family: inherit;
  font-size: 11px;
  cursor: pointer;

  &:hover {
    border-color: $terminal-red;
    color: $terminal-red;
  }
}

// Heat Bar
.heat-bar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 15px;
  border-top: 1px solid #333;
  background: rgba(0, 0, 0, 0.5);
  font-size: 10px;

  &.heat-low {
    .heat-icon, .heat-fill { background: $terminal-green; color: $terminal-green; }
  }
  &.heat-medium {
    .heat-icon { color: $terminal-amber; }
    .heat-fill { background: $terminal-amber; }
  }
  &.heat-high {
    .heat-icon { color: #ff8800; }
    .heat-fill { background: #ff8800; }
  }
  &.heat-critical {
    .heat-icon { color: $terminal-red; animation: blink 0.5s infinite; }
    .heat-fill { background: $terminal-red; animation: heat-pulse 1s infinite; }
  }
}

@keyframes heat-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.6; }
}

.heat-label {
  display: flex;
  align-items: center;
  gap: 4px;
  color: #888;
  white-space: nowrap;
}

.heat-icon {
  font-weight: bold;
}

.heat-meter {
  flex: 1;
  height: 8px;
  background: #222;
  border: 1px solid #444;
  min-width: 100px;
  max-width: 200px;
}

.heat-fill {
  height: 100%;
  transition: width 0.3s ease;
}

.heat-value {
  color: #888;
  min-width: 50px;
  text-align: right;
  font-family: monospace;
}

.clear-heat-btn {
  padding: 4px 10px;
  background: rgba(191, 0, 255, 0.1);
  border: 1px solid $terminal-purple;
  color: $terminal-purple;
  font-family: inherit;
  font-size: 9px;
  cursor: pointer;
  white-space: nowrap;

  &:hover:not(:disabled) {
    background: $terminal-purple;
    color: #000;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

// Footer
.dw-footer {
  display: flex;
  justify-content: center;
  gap: 8px;
  padding: 8px 15px;
  border-top: 1px solid #333;
  font-size: 9px;
  color: #555;
}

// Animations
.blink {
  animation: blink 1s infinite;
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}
</style>
