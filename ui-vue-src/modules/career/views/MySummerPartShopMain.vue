<template>
  <LayoutSingle class="part-shop-layout">
    <MySummerPartShop />
  </LayoutSingle>
</template>

<script setup>
import { LayoutSingle } from '@/common/layouts'
import MySummerPartShop from "../components/mysummer/MySummerPartShop.vue"
</script>

<style scoped lang="scss">
.part-shop-layout {
  height: 100%;
}
</style>
