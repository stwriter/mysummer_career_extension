<template>
  <LayoutSingle class="internet-layout">
    <MySummerInternet />
  </LayoutSingle>
</template>

<script setup>
import { LayoutSingle } from '@/common/layouts'
import MySummerInternet from "../components/mysummer/MySummerInternet.vue"
</script>

<style scoped lang="scss">
.internet-layout {
  height: 100%;
}
</style>
