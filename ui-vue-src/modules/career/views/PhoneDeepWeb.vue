<template>
  <PhoneWrapper app-name="Deep Web" status-font-color="#00ff41" status-blend-mode="">
    <div class="deepweb-screen">
      <!-- Header -->
      <div class="dw-header">
        <div class="dw-title">[DEEP WEB]</div>
        <div class="dw-status">
          <span class="blink">*</span> ENCRYPTED CONNECTION
        </div>
      </div>

      <!-- Contacts List -->
      <div class="contacts-section" v-if="!selectedContact">
        <div class="section-title">// CONTACTS</div>

        <div v-if="loading" class="loading-state">
          <span class="blink">CONNECTING...</span>
        </div>

        <div v-else-if="contacts.length === 0" class="empty-state">
          <span>NO_CONTACTS_AVAILABLE</span>
        </div>

        <div v-else class="contacts-list">
          <div
            v-for="contact in contacts"
            :key="contact.id"
            class="contact-item"
            :class="{ locked: contact.locked, 'can-race': contact.canRace }"
            @click="!contact.locked && selectContact(contact)"
          >
            <div class="contact-avatar">[{{ getInitial(contact) }}]</div>
            <div class="contact-info">
              <div class="contact-name">{{ contact.name }}</div>
              <div class="contact-specialty">{{ contact.specialty }}</div>
              <div v-if="contact.locked" class="contact-locked">
                [LOCKED]
              </div>
              <div v-else-if="contact.canRace" class="contact-race-ready">
                [RACE AVAILABLE]
              </div>
              <div v-else-if="contact.raceReason" class="contact-race-reason">
                {{ contact.raceReason }}
              </div>
            </div>
            <div class="contact-level" v-if="!contact.locked">
              LVL {{ contact.trustLevel || 1 }}
            </div>
          </div>
        </div>
      </div>

      <!-- Selected Contact Actions -->
      <div class="contact-actions" v-if="selectedContact">
        <button class="back-btn" @click="selectedContact = null">
          &lt; BACK
        </button>

        <div class="selected-contact-info">
          <div class="contact-avatar large">[{{ getInitial(selectedContact) }}]</div>
          <div class="contact-name">{{ selectedContact.name }}</div>
          <div class="contact-specialty">{{ selectedContact.specialty }}</div>
        </div>

        <div class="action-buttons">
          <button
            v-if="selectedContact.canRace"
            class="action-btn race"
            @click="challengeToRace"
            :disabled="loading"
          >
            [CHALLENGE TO RACE]
          </button>
          <div v-else-if="selectedContact.raceReason" class="race-unavailable">
            {{ selectedContact.raceReason }}
          </div>
        </div>
      </div>

      <!-- Footer -->
      <div class="dw-footer">
        <span>TOR: ACTIVE</span>
        <span>|</span>
        <span>ID: ANON</span>
      </div>
    </div>
  </PhoneWrapper>
</template>

<script setup>
import PhoneWrapper from "./PhoneWrapper.vue"
import { ref, onMounted, onUnmounted } from 'vue'
import { useMySummerDeepWebStore } from "../stores/mysummerDeepWebStore"

const deepWebStore = useMySummerDeepWebStore()

const contacts = ref([])
const selectedContact = ref(null)
const loading = ref(false)

const getInitial = (contact) => {
  if (!contact || !contact.name) return "?"
  return contact.name.charAt(0).toUpperCase()
}

const selectContact = (contact) => {
  selectedContact.value = contact
}

const challengeToRace = async () => {
  if (!selectedContact.value || loading.value) return

  loading.value = true
  try {
    const result = await deepWebStore.challengeToRace(selectedContact.value.id)
    if (result && result.success) {
      // Close the phone to start the race
      if (window.bngApi) {
        window.bngApi.engineLua("guihooks.trigger('closePhone')")
      }
    }
  } catch (e) {
    console.error("[PhoneDeepWeb] Race challenge error:", e)
  } finally {
    loading.value = false
  }
}

const loadContacts = async () => {
  loading.value = true
  try {
    await deepWebStore.requestData()
    contacts.value = deepWebStore.vendors || []
  } catch (e) {
    console.error("[PhoneDeepWeb] Failed to load contacts:", e)
    contacts.value = []
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  loadContacts()
})

onUnmounted(() => {
  deepWebStore.dispose()
})
</script>

<style scoped lang="scss">
$terminal-green: #00ff41;
$terminal-amber: #ffb000;
$terminal-red: #ff3333;
$terminal-cyan: #00ffff;
$bg-dark: #0a0a0a;

.deepweb-screen {
  padding: 16px;
  padding-top: 72px;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  overflow-y: auto;
  font-family: "Courier New", Courier, monospace;
  color: $terminal-green;
}

.dw-header {
  text-align: center;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px dashed #333;
}

.dw-title {
  font-size: 1.2rem;
  font-weight: bold;
  text-shadow: 0 0 10px rgba(0, 255, 65, 0.5);
}

.dw-status {
  font-size: 0.7rem;
  color: #666;
  margin-top: 4px;
}

.section-title {
  font-size: 0.8rem;
  color: #555;
  margin-bottom: 12px;
}

.loading-state, .empty-state {
  text-align: center;
  padding: 40px 20px;
  color: #555;
}

.contacts-list {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.contact-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px;
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid #333;
  cursor: pointer;
  transition: all 0.2s;

  &:hover:not(.locked) {
    border-color: $terminal-green;
    background: rgba(0, 255, 65, 0.05);
  }

  &.locked {
    opacity: 0.4;
    cursor: not-allowed;
  }

  &.can-race {
    border-color: $terminal-amber;
  }
}

.contact-avatar {
  font-size: 1.2rem;
  font-weight: bold;
  color: $terminal-cyan;

  &.large {
    font-size: 2rem;
    margin-bottom: 8px;
  }
}

.contact-info {
  flex: 1;
}

.contact-name {
  font-size: 0.9rem;
  color: #ddd;
  margin-bottom: 2px;
}

.contact-specialty {
  font-size: 0.7rem;
  color: #666;
}

.contact-locked {
  font-size: 0.65rem;
  color: $terminal-red;
  margin-top: 4px;
}

.contact-race-ready {
  font-size: 0.65rem;
  color: $terminal-amber;
  margin-top: 4px;
}

.contact-race-reason {
  font-size: 0.6rem;
  color: #555;
  margin-top: 4px;
}

.contact-level {
  font-size: 0.7rem;
  color: $terminal-cyan;
}

// Selected contact view
.contact-actions {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.back-btn {
  align-self: flex-start;
  padding: 6px 12px;
  background: transparent;
  border: 1px solid #444;
  color: #888;
  font-family: inherit;
  font-size: 0.75rem;
  cursor: pointer;
  margin-bottom: 20px;

  &:hover {
    border-color: $terminal-green;
    color: $terminal-green;
  }
}

.selected-contact-info {
  text-align: center;
  padding: 20px;
  margin-bottom: 20px;
}

.action-buttons {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.action-btn {
  width: 100%;
  padding: 14px;
  font-family: inherit;
  font-size: 0.9rem;
  font-weight: bold;
  border: none;
  cursor: pointer;
  text-transform: uppercase;
  letter-spacing: 1px;
  transition: all 0.2s;

  &.race {
    background: rgba(255, 176, 0, 0.2);
    border: 2px solid $terminal-amber;
    color: $terminal-amber;

    &:hover:not(:disabled) {
      background: $terminal-amber;
      color: #000;
    }

    &:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }
  }
}

.race-unavailable {
  text-align: center;
  padding: 14px;
  color: #555;
  font-size: 0.8rem;
  border: 1px dashed #333;
}

.dw-footer {
  display: flex;
  justify-content: center;
  gap: 8px;
  padding-top: 12px;
  margin-top: auto;
  border-top: 1px dashed #333;
  font-size: 0.65rem;
  color: #444;
}

.blink {
  animation: blink 1s infinite;
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

:deep(.phone-content) {
  background: linear-gradient(to bottom, #000000, #0a1a0a);
}
</style>
