import { ref } from "vue"
import { defineStore } from "pinia"
import { lua, useBridge } from "@/bridge"

export const useMySummerDeepWebStore = defineStore("mysummerDeepWeb", () => {
  const { events } = useBridge()

  const vendors = ref([])
  const conversation = ref(null)
  const loading = ref(false)
  const error = ref(null)

  const setVendors = (data) => {
    vendors.value = data || []
  }

  const setConversation = (data) => {
    conversation.value = data || null
  }

  const requestData = async () => {
    loading.value = true
    error.value = null
    console.log("[mysummerDeepWebStore] Calling getVendorData...")
    try {
      const data = await lua.career_modules_mysummerDeepWeb.getVendorData()
      console.log("[mysummerDeepWebStore] Response:", data)
      setVendors(data)
    } catch (err) {
      console.error("[mysummerDeepWebStore] Error:", err)
      error.value = err
    } finally {
      loading.value = false
    }
  }

  const startConversation = async (vendorId) => {
    loading.value = true
    error.value = null
    console.log("[mysummerDeepWebStore] Starting conversation with vendor:", vendorId)
    try {
      const data = await lua.career_modules_mysummerDeepWeb.startConversation(vendorId)
      console.log("[mysummerDeepWebStore] Conversation started:", data)
      setConversation(data)
      return data
    } catch (err) {
      console.error("[mysummerDeepWebStore] startConversation error:", err)
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const respondToVendor = async (choiceId) => {
    loading.value = true
    error.value = null
    console.log("[mysummerDeepWebStore] Responding with choice:", choiceId)
    try {
      const data = await lua.career_modules_mysummerDeepWeb.respondToVendor(choiceId)
      console.log("[mysummerDeepWebStore] Response received:", data)

      if (data && conversation.value) {
        const existingMessages = conversation.value.messages || []
        const newMessages = data.messages || []
        data.messages = [...existingMessages, ...newMessages]
      }

      setConversation(data)
      return data
    } catch (err) {
      console.error("[mysummerDeepWebStore] respondToVendor error:", err)
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const closeConversation = () => {
    conversation.value = null
  }

  const activeRace = ref(null)
  const heatInfo = ref({ heat: 0, maxHeat: 100, canClear: false, clearPrice: 5000 })

  const challengeToRace = async (vendorId) => {
    loading.value = true
    error.value = null
    console.log("[mysummerDeepWebStore] Challenging to race:", vendorId)
    try {
      if (window.bngApi) {
        const escaped = vendorId.replace(/"/g, '\\"')
        return new Promise((resolve, reject) => {
          window.bngApi.engineLua(`career_modules_mysummerDeepWeb.startContactRace("${escaped}")`, (data) => {
            console.log("[mysummerDeepWebStore] Race started:", data)
            if (data && data.success) {
              activeRace.value = data
            }
            loading.value = false
            resolve(data)
          })
        })
      }
      loading.value = false
      return { success: false, message: "bngApi not available" }
    } catch (err) {
      console.error("[mysummerDeepWebStore] challengeToRace error:", err)
      error.value = err
      loading.value = false
      throw err
    }
  }

  const cancelRace = async () => {
    try {
      if (window.bngApi) {
        window.bngApi.engineLua('career_modules_mysummerDeepWeb.cancelContactRace("Cancelled by player")')
        activeRace.value = null
      }
    } catch (err) {
      console.error("[mysummerDeepWebStore] cancelRace error:", err)
    }
  }

  const getRaceState = async () => {
    try {
      if (window.bngApi) {
        return new Promise((resolve) => {
          window.bngApi.engineLua('career_modules_mysummerDeepWeb.getActiveRaceState()', (data) => {
            activeRace.value = data
            resolve(data)
          })
        })
      }
      return null
    } catch (err) {
      console.error("[mysummerDeepWebStore] getRaceState error:", err)
      return null
    }
  }

  const handleVendorUpdate = (data) => setVendors(data)
  const handleConversationUpdate = (data) => setConversation(data)
  const handleRaceFinished = (data) => {
    console.log("[mysummerDeepWebStore] Race finished:", data)
    activeRace.value = null
    requestData()
  }
  const handleRaceCancelled = (data) => {
    console.log("[mysummerDeepWebStore] Race cancelled:", data)
    activeRace.value = null
  }
  const handleHeatUpdate = (data) => {
    console.log("[mysummerDeepWebStore] Heat updated:", data)
    heatInfo.value = { ...heatInfo.value, ...data }
  }

  const getHeatInfo = async () => {
    try {
      if (window.bngApi) {
        return new Promise((resolve) => {
          window.bngApi.engineLua('career_modules_mysummerDeepWeb.getPlayerHeatInfo()', (data) => {
            if (data) heatInfo.value = data
            resolve(data)
          })
        })
      }
      return null
    } catch (err) {
      console.error("[mysummerDeepWebStore] getHeatInfo error:", err)
      return null
    }
  }

  const clearHeatWithShadow = async () => {
    loading.value = true
    error.value = null
    try {
      if (window.bngApi) {
        return new Promise((resolve) => {
          window.bngApi.engineLua('career_modules_mysummerDeepWeb.clearHeatWithShadow()', (result) => {
            if (result && result.success) getHeatInfo()
            loading.value = false
            resolve(result)
          })
        })
      }
      loading.value = false
      return { success: false, message: "bngApi not available" }
    } catch (err) {
      console.error("[mysummerDeepWebStore] clearHeatWithShadow error:", err)
      error.value = err
      loading.value = false
      throw err
    }
  }

  const dispose = () => {
    events.off("mysummerVendorsUpdated", handleVendorUpdate)
    events.off("mysummerConversationUpdated", handleConversationUpdate)
    events.off("mysummerContactRaceFinished", handleRaceFinished)
    events.off("mysummerContactRaceCancelled", handleRaceCancelled)
    events.off("mysummerHeatUpdated", handleHeatUpdate)
  }

  events.on("mysummerVendorsUpdated", handleVendorUpdate)
  events.on("mysummerConversationUpdated", handleConversationUpdate)
  events.on("mysummerContactRaceFinished", handleRaceFinished)
  events.on("mysummerContactRaceCancelled", handleRaceCancelled)
  events.on("mysummerHeatUpdated", handleHeatUpdate)

  return {
    vendors, conversation, loading, error, activeRace, heatInfo,
    requestData, startConversation, respondToVendor, closeConversation,
    challengeToRace, cancelRace, getRaceState, getHeatInfo, clearHeatWithShadow, dispose,
  }
})
