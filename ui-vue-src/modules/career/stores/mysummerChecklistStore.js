import { ref } from "vue"
import { defineStore } from "pinia"
import { lua, useBridge } from "@/bridge"

export const useMySummerChecklistStore = defineStore("mysummerChecklist", () => {
  const { events } = useBridge()

  const checklistData = ref({
    checklist: {},
    stats: {
      totalSlots: 0,
      perfectMatches: 0,
      compatibleParts: 0,
      missingParts: 0,
      mandatoryMissing: 0,
      completionPercent: 0,
    },
    missingReasons: [],
    projectInventoryId: null,
  })
  const loading = ref(false)
  const error = ref(null)

  const setChecklistData = (data) => {
    checklistData.value = data || {
      checklist: {},
      stats: {
        totalSlots: 0,
        perfectMatches: 0,
        compatibleParts: 0,
        missingParts: 0,
        mandatoryMissing: 0,
        completionPercent: 0,
      },
      missingReasons: [],
      projectInventoryId: null,
    }
  }

  const requestData = async () => {
    loading.value = true
    error.value = null
    console.log("[mysummerChecklistStore] Calling getChecklistData...")
    try {
      const data = await lua.career_modules_mysummerChecklist.getChecklistData()
      console.log("[mysummerChecklistStore] Response:", data)
      setChecklistData(data)
    } catch (err) {
      console.error("[mysummerChecklistStore] Error:", err)
      error.value = err
    } finally {
      loading.value = false
    }
  }

  const refresh = async () => {
    loading.value = true
    error.value = null
    try {
      await lua.career_modules_mysummerChecklist.refresh()
      const data = await lua.career_modules_mysummerChecklist.getChecklistData()
      setChecklistData(data)
      return data
    } catch (err) {
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const handleChecklistUpdate = (data) => {
    setChecklistData(data)
  }

  const dispose = () => {
    events.off("mysummerChecklistUpdated", handleChecklistUpdate)
  }

  events.on("mysummerChecklistUpdated", handleChecklistUpdate)

  return {
    checklistData,
    loading,
    error,
    requestData,
    refresh,
    dispose,
  }
})
