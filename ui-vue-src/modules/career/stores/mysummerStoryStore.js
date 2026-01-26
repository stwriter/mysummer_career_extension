import { ref, markRaw } from "vue"
import { defineStore } from "pinia"
import { useBridge } from "@/bridge"
import { addPopup } from "@/services/popup"
import GrandfatherLetter from "../components/mysummer/GrandfatherLetter.vue"
import PhaseTransition from "../components/mysummer/PhaseTransition.vue"

export const useMySummerStoryStore = defineStore("mysummerStory", () => {
  const { events } = useBridge()

  const introData = ref(null)
  const showingIntro = ref(false)
  const transitionData = ref(null)
  const showingTransition = ref(false)

  // Handle intro event from Lua (grandfather's letter on first login)
  const handleShowIntro = async (data) => {
    console.log("[mysummerStoryStore] Received mysummerShowIntro event:", data)
    introData.value = data
    showingIntro.value = true

    // Use addPopup to show the GrandfatherLetter component
    const popup = addPopup(markRaw(GrandfatherLetter), {
      storyText: data.storyText,
      signText: data.signText,
      signName: data.signName,
      postscript: data.postscript
    })

    // Wait for the popup to close
    await popup.promise

    // Mark intro as seen in Lua
    console.log("[mysummerStoryStore] Intro dismissed, marking as seen")
    if (window.bngApi) {
      window.bngApi.engineLua("career_modules_mysummerCareer.markIntroSeen()")
    }
    showingIntro.value = false

    // Now show Chapter I transition
    console.log("[mysummerStoryStore] Showing Chapter I after letter")
    if (data.chapter1Data) {
      // Small delay for dramatic effect
      await new Promise(resolve => setTimeout(resolve, 800))

      const chapterPopup = addPopup(markRaw(PhaseTransition), {
        completedLevel: 0,
        completionText: '',
        newLevel: 1,
        newLevelName: data.chapter1Data.name,
        newLevelIntro: data.chapter1Data.intro,
        isFinalLevel: false
      })
      await chapterPopup.promise
    }
  }

  // Handle phase/level transition event from Lua (when player levels up)
  const handlePhaseTransition = async (data) => {
    console.log("[mysummerStoryStore] Phase transition:", data)
    transitionData.value = data
    showingTransition.value = true

    // Use addPopup to show the PhaseTransition component
    const popup = addPopup(markRaw(PhaseTransition), {
      completedLevel: data.completedLevel || 0,
      completionText: data.completionText || '',
      newLevel: data.newLevel || 1,
      newLevelName: data.newLevelName || '',
      newLevelIntro: data.newLevelIntro || '',
      isFinalLevel: data.isFinalLevel || false
    })

    // Wait for the popup to close
    await popup.promise

    console.log("[mysummerStoryStore] Phase transition dismissed")
    showingTransition.value = false
  }

  const dispose = () => {
    events.off("mysummerShowIntro", handleShowIntro)
    events.off("mysummerPhaseTransition", handlePhaseTransition)
  }

  // Register event listeners
  events.on("mysummerShowIntro", handleShowIntro)
  events.on("mysummerPhaseTransition", handlePhaseTransition)

  return {
    introData,
    showingIntro,
    transitionData,
    showingTransition,
    dispose,
  }
})
