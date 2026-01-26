import { ref } from "vue"
import { defineStore } from "pinia"
import { lua, useBridge } from "@/bridge"

export const useMySummerChatStore = defineStore("mysummerChat", () => {
  const { events } = useBridge()

  // State
  const conversations = ref([])
  const currentConversation = ref(null)
  const currentContact = ref(null)
  const pendingChoices = ref([])
  const loading = ref(false)
  const error = ref(null)
  const totalUnread = ref(0)
  const typingContacts = ref({})

  // Getters
  const getConversationByContact = (contactId) => {
    return conversations.value.find(c => c.contactId === contactId)
  }

  // Actions
  const loadConversations = async () => {
    loading.value = true
    error.value = null
    try {
      const data = await lua.career_modules_mysummerChat.getConversations()
      conversations.value = data || []

      const unreadData = await lua.career_modules_mysummerChat.getUnreadCounts()
      totalUnread.value = unreadData?.total || 0
    } catch (err) {
      console.error("[mysummerChatStore] Error loading conversations:", err)
      error.value = err
    } finally {
      loading.value = false
    }
  }

  const loadConversation = async (contactId) => {
    loading.value = true
    error.value = null
    try {
      const data = await lua.career_modules_mysummerChat.getConversation(contactId)
      if (data) {
        currentConversation.value = data.conversation
        currentContact.value = data.contact
        pendingChoices.value = data.pendingChoices || []
      }
      return data
    } catch (err) {
      console.error("[mysummerChatStore] Error loading conversation:", err)
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const startDialogue = async (contactId) => {
    loading.value = true
    error.value = null
    try {
      const data = await lua.career_modules_mysummerChat.startDialogue(contactId)
      if (data && data.success) {
        pendingChoices.value = data.choices || []
        // Reload conversation to get messages
        await loadConversation(contactId)
      }
      return data
    } catch (err) {
      console.error("[mysummerChatStore] Error starting dialogue:", err)
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const continueDialogue = async (contactId, choiceId) => {
    loading.value = true
    error.value = null
    try {
      const data = await lua.career_modules_mysummerChat.continueDialogue(contactId, choiceId)
      if (data && data.success) {
        pendingChoices.value = data.choices || []
        // Reload conversation
        await loadConversation(contactId)
      }
      return data
    } catch (err) {
      console.error("[mysummerChatStore] Error continuing dialogue:", err)
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const markAsRead = async (contactId) => {
    try {
      await lua.career_modules_mysummerChat.markAsRead(contactId)
      // Update local unread counts
      const unreadData = await lua.career_modules_mysummerChat.getUnreadCounts()
      totalUnread.value = unreadData?.total || 0
    } catch (err) {
      console.error("[mysummerChatStore] Error marking as read:", err)
    }
  }

  const hasAvailableDialogue = async (contactId) => {
    try {
      return await lua.career_modules_mysummerChat.hasAvailableDialogue(contactId)
    } catch (err) {
      console.error("[mysummerChatStore] Error checking dialogue availability:", err)
      return false
    }
  }

  // Event handlers
  const handleChatUpdated = (data) => {
    loadConversations()
  }

  const handleNewMessage = (data) => {
    loadConversations()
    if (currentConversation.value && data.contactId === currentContact.value?.id) {
      loadConversation(data.contactId)
    }
  }

  const handleTyping = (data) => {
    typingContacts.value = {
      ...typingContacts.value,
      [data.contactId]: data.isTyping
    }
  }

  const handleChoices = (data) => {
    if (currentContact.value && data.contactId === currentContact.value.id) {
      pendingChoices.value = data.choices || []
    }
  }

  const handleReadStatus = (data) => {
    totalUnread.value = data.totalUnread || 0
  }

  // Setup event listeners
  const setupListeners = () => {
    if (events) {
      events.on("mysummerChatUpdated", handleChatUpdated)
      events.on("mysummerChatNewMessage", handleNewMessage)
      events.on("mysummerChatTyping", handleTyping)
      events.on("mysummerChatChoices", handleChoices)
      events.on("mysummerChatReadStatusUpdated", handleReadStatus)
    }
  }

  const cleanupListeners = () => {
    if (events) {
      events.off("mysummerChatUpdated", handleChatUpdated)
      events.off("mysummerChatNewMessage", handleNewMessage)
      events.off("mysummerChatTyping", handleTyping)
      events.off("mysummerChatChoices", handleChoices)
      events.off("mysummerChatReadStatusUpdated", handleReadStatus)
    }
  }

  // Clear state
  const clearCurrentConversation = () => {
    currentConversation.value = null
    currentContact.value = null
    pendingChoices.value = []
  }

  return {
    // State
    conversations,
    currentConversation,
    currentContact,
    pendingChoices,
    loading,
    error,
    totalUnread,
    typingContacts,

    // Getters
    getConversationByContact,

    // Actions
    loadConversations,
    loadConversation,
    startDialogue,
    continueDialogue,
    markAsRead,
    hasAvailableDialogue,
    clearCurrentConversation,

    // Lifecycle
    setupListeners,
    cleanupListeners,
  }
})
