<template>
  <StoryScene
    v-if="isActive"
    :sceneId="sceneId"
    :contactId="contactId"
    :contactName="contactName"
    :emotion="emotion"
    :title="title"
    :texts="messages"
    :choices="choices"
    :continueLabel="continueLabel"
    :language="language"
    @return="handleReturn"
  />
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useEvents } from '@/services/events'
import StoryScene from './StoryScene.vue'

const events = useEvents()

// State
const isActive = ref(false)
const sceneId = ref('')
const contactId = ref('unknown')
const contactName = ref('Unknown')
const emotion = ref('standard')
const title = ref('')
const rawMessages = ref([])
const choices = ref(null)
const continueLabel = ref('')
const language = ref('en')

// Transform raw messages from Lua format to StoryScene format
const messages = computed(() => {
  return rawMessages.value.map(msg => ({
    text: msg.text,
    emotion: msg.emotion || 'standard'
  }))
})

// Handle incoming call event from Lua
const handleIncomingCall = (data) => {
  if (!data.caller || !data.callerName) return

  console.log('[CallSceneWrapper] Incoming call from:', data.caller)

  // Reset state for new call
  sceneId.value = data.callId || `call_${Date.now()}`
  contactId.value = data.caller
  contactName.value = data.callerName
  emotion.value = 'standard'
  title.value = '' // Calls don't have titles
  rawMessages.value = []
  choices.value = null
  continueLabel.value = data.continueLabel || ''
  language.value = data.language || 'en'

  // Don't show yet - wait for first line
}

// Handle call dialogue line from Lua
const handleShowCallLine = (data) => {
  if (!data.speaker || !data.text) return

  console.log('[CallSceneWrapper] Received call line:', data)

  // Add message to list
  rawMessages.value.push({
    text: data.text,
    emotion: data.emotion || 'standard'
  })

  // If this is a choice line, set choices
  if (data.isChoice && data.choices) {
    choices.value = data.choices.map(choice => ({
      label: choice.text,
      value: choice.id
    }))
  }

  // Show scene on first message
  if (!isActive.value) {
    isActive.value = true
  }
}

// Handle scene close/return
const handleReturn = (data) => {
  console.log('[CallSceneWrapper] Scene returned with:', data)

  // If user made a choice, notify Lua
  if (data.choice) {
    // TODO: Send choice to Lua backend
    // events.emit('mysummerCallChoice', { choiceId: data.choice })
  }

  // Close scene
  isActive.value = false

  // Reset state after animation
  setTimeout(() => {
    sceneId.value = ''
    contactId.value = 'unknown'
    contactName.value = 'Unknown'
    rawMessages.value = []
    choices.value = null
  }, 300)
}

// Lifecycle
onMounted(() => {
  console.log('[CallSceneWrapper] Mounted, listening for call events')
  events.on('mysummerIncomingCall', handleIncomingCall)
  events.on('mysummerShowCallLine', handleShowCallLine)
})

onUnmounted(() => {
  events.off('mysummerIncomingCall', handleIncomingCall)
  events.off('mysummerShowCallLine', handleShowCallLine)
})
</script>
