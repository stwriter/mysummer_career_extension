import { ref, markRaw } from "vue"
import { defineStore } from "pinia"
import { useBridge } from "@/bridge"
import { addPopup } from "@/services/popup"
import GrandfatherLetter from "../components/mysummer/GrandfatherLetter.vue"
import PhaseTransition from "../components/mysummer/PhaseTransition.vue"
import WelcomeTutorial from "../components/mysummer/WelcomeTutorial.vue"
import StoryScene from "../components/mysummer/StoryScene.vue"

export const useMySummerStoryStore = defineStore("mysummerStory", () => {
  const { events } = useBridge()

  const introData = ref(null)
  const showingIntro = ref(false)
  const transitionData = ref(null)
  const showingTransition = ref(false)

  const escapeLuaString = (value) => {
    return String(value ?? "")
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
  }

  // Handle intro event from Lua (grandfather's letter on first login)
  const handleShowIntro = async (data) => {
    console.log("[mysummerStoryStore] Received mysummerShowIntro event:", data)
    introData.value = data
    showingIntro.value = true

    // Pause the game during intro sequence
    pauseGame()

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

      // Show welcome tutorial after chapter intro
      console.log("[mysummerStoryStore] Showing welcome tutorial")
      await new Promise(resolve => setTimeout(resolve, 500))
      const tutorialPopup = addPopup(markRaw(WelcomeTutorial), {
        projectCarName: 'ETK-I',
        projectCarFullName: 'ETK I-Series',
        language: data.language || 'en'
      })
      await tutorialPopup.promise
      console.log("[mysummerStoryStore] Tutorial dismissed")
    }

    // Resume game after intro sequence
    resumeGame()
  }

  // Handle phase/level transition event from Lua (when player levels up)
  const handlePhaseTransition = async (data) => {
    console.log("[mysummerStoryStore] Phase transition:", data)
    transitionData.value = data
    showingTransition.value = true

    // Pause the game during phase transition
    pauseGame()

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

    // Resume game after phase transition
    resumeGame()
  }

  // Pause/resume game simulation for fullscreen scenes
  const pauseGame = () => {
    if (window.bngApi) {
      window.bngApi.engineLua('simTimeAuthority.pause(true)')
      console.log("[mysummerStoryStore] Game PAUSED for scene")
    }
  }

  const resumeGame = () => {
    if (window.bngApi) {
      window.bngApi.engineLua('simTimeAuthority.pause(false)')
      console.log("[mysummerStoryStore] Game RESUMED after scene")
    }
  }

  const handleShowSceneSequence = async (data) => {
    if (!data || !data.scenes || data.scenes.length === 0) return

    const sequenceId = data.sequenceId || "scene_sequence"
    console.log("[mysummerStoryStore] Scene sequence:", sequenceId, data.scenes.length)

    // Pause the game while showing fullscreen scenes
    pauseGame()

    try {
      for (const scene of data.scenes) {
        const popup = addPopup(markRaw(StoryScene), {
          sceneId: scene.id,
          contactId: scene.contactId,
          contactName: scene.contactName,
          emotion: scene.emotion || "standard",
          title: scene.title || "",
          text: scene.text || "",
          texts: scene.texts || null,
          choices: scene.choices || null,
          continueLabel: scene.continueLabel || "",
          language: data.language || ""
        })

        const result = await popup.promise
        if (result && result.choice && window.bngApi) {
          const choiceValue = escapeLuaString(result.choice)
          const sceneId = escapeLuaString(scene.id)
          const seqId = escapeLuaString(sequenceId)
          window.bngApi.engineLua(
            `career_modules_mysummerCareer.handleSceneChoice("${seqId}", "${sceneId}", "${choiceValue}")`
          )
        }
      }
    } finally {
      // Always resume game, even if an error occurs
      resumeGame()
    }
  }

  const handleShowScene = async (data) => {
    if (!data) return
    await handleShowSceneSequence({
      sequenceId: data.sequenceId || "scene_single",
      scenes: [data],
      language: data.language || ""
    })
  }

  const dispose = () => {
    events.off("mysummerShowIntro", handleShowIntro)
    events.off("mysummerPhaseTransition", handlePhaseTransition)
    events.off("mysummerShowSceneSequence", handleShowSceneSequence)
    events.off("mysummerShowScene", handleShowScene)
  }

  // Register event listeners
  events.on("mysummerShowIntro", handleShowIntro)
  events.on("mysummerPhaseTransition", handlePhaseTransition)
  events.on("mysummerShowSceneSequence", handleShowSceneSequence)
  events.on("mysummerShowScene", handleShowScene)

  return {
    introData,
    showingIntro,
    transitionData,
    showingTransition,
    dispose,
  }
})
