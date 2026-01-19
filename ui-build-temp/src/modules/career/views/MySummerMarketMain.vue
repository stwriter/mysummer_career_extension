<template>
  <ComputerWrapper :title="'Internet Browser'" :path="['Garage', 'Internet']" back @back="close">
    <MySummerBrowser />
  </ComputerWrapper>
</template>

<script setup>
import { lua } from "@/bridge"
import ComputerWrapper from "./ComputerWrapper.vue"
import MySummerBrowser from "../components/mysummer/MySummerBrowser.vue"

const close = () => {
  if (window.vueGlobalStore) {
    window.vueGlobalStore.__uiAppsShown = true
  }
  lua.career_modules_mysummerParts.closeMenu()
}
</script>

<style scoped lang="scss">
</style>
