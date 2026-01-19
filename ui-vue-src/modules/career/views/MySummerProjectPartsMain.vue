<template>
  <ComputerWrapper :title="'Garage Panel - Project Parts'" :path="['Garage', 'Project Parts']" back @back="close">
    <MySummerProjectParts />
  </ComputerWrapper>
</template>

<script setup>
import { lua } from "@/bridge"
import ComputerWrapper from "./ComputerWrapper.vue"
import MySummerProjectParts from "../components/mysummer/MySummerProjectParts.vue"

const close = () => {
  // Restore UI apps visibility flag (minimap depends on this)
  if (window.vueGlobalStore) {
    window.vueGlobalStore.__uiAppsShown = true
  }
  lua.career_modules_mysummerParts.closeProjectPartsMenu()
}
</script>
