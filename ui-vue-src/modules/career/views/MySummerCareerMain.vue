<template>
  <ComputerWrapper :title="'Garage Panel - Career Progress'" :path="['Garage', 'Career Progress']" back @back="close">
    <MySummerCareer />
  </ComputerWrapper>
</template>

<script setup>
import { lua } from "@/bridge"
import ComputerWrapper from "./ComputerWrapper.vue"
import MySummerCareer from "../components/mysummer/MySummerCareer.vue"

const close = () => {
  // Restore UI apps visibility flag (minimap depends on this)
  if (window.vueGlobalStore) {
    window.vueGlobalStore.__uiAppsShown = true
  }
  lua.career_career.closeAllMenus()
}
</script>
