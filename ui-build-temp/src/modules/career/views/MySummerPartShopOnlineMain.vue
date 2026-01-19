<template>
  <LayoutSingle class="online-shop-layout">
    <MySummerPartShopOnline />
  </LayoutSingle>
</template>

<script setup>
import { LayoutSingle } from '@/common/layouts'
import MySummerPartShopOnline from "../components/mysummer/MySummerPartShopOnline.vue"
</script>

<style scoped lang="scss">
.online-shop-layout {
  height: 100%;
}
</style>
