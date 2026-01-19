import { ref } from "vue"
import { defineStore } from "pinia"
import { lua, useBridge } from "@/bridge"

export const useMySummerCareerStore = defineStore("mysummerCareer", () => {
  const { events } = useBridge()

  const careerData = ref({
    nativeProgress: {
      level: 1,
      levelName: "Rookie Racer",
      currentXP: 0,
      minXP: 0,
      maxXP: 250,
      totalXP: 0,
      isMaxLevel: false,
    },
    reputation: {
      total: 0,
      tier: "unknown",
      breakdown: {},
    },
    currentPhase: null,
    phases: [],
    projectVehicle: null,
    availableRaces: [],
  })
  const loading = ref(false)
  const error = ref(null)

  const setCareerData = (data) => {
    careerData.value = data || {
      nativeProgress: {
        level: 1,
        levelName: "Rookie Racer",
        currentXP: 0,
        minXP: 0,
        maxXP: 250,
        totalXP: 0,
        isMaxLevel: false,
      },
      reputation: { total: 0, tier: "unknown", breakdown: {} },
      currentPhase: null,
      phases: [],
      projectVehicle: null,
      availableRaces: [],
    }
  }

  const requestData = async () => {
    loading.value = true
    error.value = null
    console.log("[mysummerCareerStore] Calling getCareerData...")
    try {
      const data = await lua.career_modules_mysummerCareer.getCareerData()
      console.log("[mysummerCareerStore] Response:", data)
      setCareerData(data)
    } catch (err) {
      console.error("[mysummerCareerStore] Error:", err)
      error.value = err
    } finally {
      loading.value = false
    }
  }

  const startPhase = async (phaseId) => {
    loading.value = true
    error.value = null
    try {
      const result = await lua.career_modules_mysummerCareer.startPhase(phaseId)
      if (result && result.success) {
        await requestData()
      }
      return result
    } catch (err) {
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const navigateToRace = async (raceId) => {
    loading.value = true
    error.value = null
    try {
      // Use bngApi.engineLua directly since lua bridge may not expose this function
      if (window.bngApi) {
        const escaped = raceId.replace(/"/g, '\\"')
        window.bngApi.engineLua(`career_modules_mysummerCareer.navigateToRace("${escaped}")`)
        return { success: true }
      }
      return { success: false, message: "bngApi not available" }
    } catch (err) {
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const handleCareerUpdate = (data) => {
    setCareerData(data)
  }

  const dispose = () => {
    events.off("mysummerCareerUpdated", handleCareerUpdate)
  }

  events.on("mysummerCareerUpdated", handleCareerUpdate)

  return {
    careerData,
    loading,
    error,
    requestData,
    startPhase,
    navigateToRace,
    dispose,
  }
})
