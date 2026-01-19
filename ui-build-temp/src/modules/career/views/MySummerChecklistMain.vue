<template>
  <ComputerWrapper :title="'Garage Panel - Build Checklist'" :path="['Garage', 'Build Checklist']" back @back="close">
    <MySummerChecklist />
  </ComputerWrapper>
</template>

<script setup>
import { lua } from "@/bridge"
import ComputerWrapper from "./ComputerWrapper.vue"
import MySummerChecklist from "../components/mysummer/MySummerChecklist.vue"

const close = () => {
  // Restore UI apps visibility flag (minimap depends on this)
  if (window.vueGlobalStore) {
    window.vueGlobalStore.__uiAppsShown = true
  }
  lua.career_career.closeAllMenus()
}
</script>
