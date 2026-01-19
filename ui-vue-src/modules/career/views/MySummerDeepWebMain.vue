<template>
  <ComputerWrapper :title="'Garage Panel - Deep Web'" :path="['Garage', 'Deep Web']" back @back="close">
    <MySummerDeepWeb />
  </ComputerWrapper>
</template>

<script setup>
import { lua } from "@/bridge"
import ComputerWrapper from "./ComputerWrapper.vue"
import MySummerDeepWeb from "../components/mysummer/MySummerDeepWeb.vue"

const close = () => {
  // Restore UI apps visibility flag (minimap depends on this)
  if (window.vueGlobalStore) {
    window.vueGlobalStore.__uiAppsShown = true
  }
  lua.career_career.closeAllMenus()
}
</script>
