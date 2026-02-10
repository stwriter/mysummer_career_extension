<template>
  <PhoneWrapper app-name="Home" status-font-color="#FFFFFF" status-blend-mode="">
    <div class="home-screen">
      <div
        v-for="app in apps"
        :key="app.name"
        class="app-item"
      >
        <button
          class="app-container"
          @click="navigateTo(app.route)"
          :style="{ backgroundColor: app.color }"
        >
          <BngIcon
            class="app-icon"
            :type="app.icon"
            :style="{ color: app.iconColor }"
          />
          <!-- Notification badges -->
          <div
            v-if="getAppBadge(app) > 0"
            class="notification-badge"
          >
            {{ getAppBadge(app) }}
          </div>
        </button>
        <span class="app-name">{{ app.name }}</span>
      </div>
    </div>
  </PhoneWrapper>
</template>

<script setup>
import PhoneWrapper from "./PhoneWrapper.vue"
import { BngIcon, icons } from "@/common/components/base"
import { useRouter } from 'vue-router'
import { ref, onMounted, onUnmounted } from 'vue'
import { lua } from "@/bridge"

const router = useRouter()
const unreadCount = ref(0)
const chatUnreadCount = ref(0)
const pickupCount = ref(0)

const apps = ref([
  { name: 'Messages', icon: icons.documentText, route: '/career/phone-chat', color: '#25D366', iconColor: '#ffffff' },
  { name: 'Loans', icon: icons.beamCurrency, route: '/career/phone-loans', color: '#5a8dee', iconColor: '#ffffff' },
  { name: 'Bank', icon: icons.beamCurrency, route: '/career/phone-bank', color: '#10b981', iconColor: '#ffffff' },
  { name: 'Marketplace', icon: icons.shoppingCart, route: '/career/phone-marketplace', color: '#228B22', iconColor: '#ffffff' },
  { name: 'Parts Market', icon: icons.engine, route: '/career/phone-parts-market', color: '#f54900', iconColor: '#ffffff' },
  { name: 'Parts Bay', icon: icons.shoppingCart, route: '/career/phone-parts-bay', color: '#0654ba', iconColor: '#ffffff' },
  { name: 'Races', icon: icons.racingFlag, route: '/career/phone-races', color: '#ff3333', iconColor: '#ffffff' },
  { name: 'Deep Web', icon: icons.wifi, route: '/career/phone-deepweb', color: '#0a0a0a', iconColor: '#00ff41' },
  { name: 'Car Meet', icon: icons.cars, route: '/career/car-meets-phone', color: '#696969', iconColor: '#ffffff' },
  { name: 'Repo', icon: icons.tow, route: '/career/phone-repo', color: '#1E90FF', iconColor: '#ffffff' },
  { name: 'Taxi', icon: icons.taxiCar3, route: '/career/phone-taxi', color: '#ffd700', iconColor: '#000000' },
  { name: 'Quarry', icon: icons.cogs, route: '/career/phone-quarry', color: '#8B4513', iconColor: '#ffffff' }
])

const getAppBadge = (app) => {
  if (app.name === 'Messages') return unreadCount.value
  if (app.name === 'Deep Web') return chatUnreadCount.value
  if (app.name === 'Parts Bay') return pickupCount.value
  return 0
}

const navigateTo = (route) => {
  router.push(route)
}

const updateUnreadCount = async () => {
  try {
    const isCareerActive = await lua.career_career.isActive()
    if (!isCareerActive) return

    // Get unread message count
    const count = await lua.career_modules_mysummerMessages.getUnreadCount()
    unreadCount.value = count || 0

    // Get unread chat count (for Deep Web contacts)
    const chatCounts = await lua.career_modules_mysummerChat.getUnreadCounts()
    chatUnreadCount.value = chatCounts?.total || 0

    // Get pending pickup count (for Parts Bay)
    const marketData = await lua.career_modules_mysummerParts.getMarketData()
    const active = marketData?.activePickup && !marketData.activePickup.isIllegal ? 1 : 0
    const pending = marketData?.pendingCount || 0
    pickupCount.value = active + pending
  } catch (e) {
    console.error("Failed to get unread count", e)
  }
}

let unreadUpdateInterval = null

onMounted(async () => {
  try {
    // Check if career is active before calling business manager
    const isCareerActive = await lua.career_career.isActive()
    if (!isCareerActive) return

    // Get initial unread count
    await updateUnreadCount()

    // Update unread count every 5 seconds
    unreadUpdateInterval = setInterval(updateUnreadCount, 5000)

    const purchased = await lua.career_modules_business_businessManager.getPurchasedBusinesses("tuningShop")
    if (purchased) {
      let hasShopApp = false
      for (const [id, owned] of Object.entries(purchased)) {
        if (owned) {
          // Check if the shop-app upgrade is unlocked
          const level = await lua.career_modules_business_businessSkillTree.getNodeProgress(id, "quality-of-life", "shop-app")
          if (level && level > 0) {
            hasShopApp = true
            break
          }
        }
      }

      if (hasShopApp) {
        // Add Tuning Shop app if not already present
        if (!apps.value.find(app => app.name === 'Tuning Shop')) {
          apps.value.push({
            name: 'Tuning Shop',
            icon: icons.cars, // Using existing icon
            route: '/career/phone-tuning-shop',
            color: '#F54900', // Tuning shop orange
            iconColor: '#ffffff'
          })
        }
      }
    }
  } catch (e) {
    console.error("Failed to check tuning shop app availability", e)
  }
})

onUnmounted(() => {
  if (unreadUpdateInterval) {
    clearInterval(unreadUpdateInterval)
  }
})
</script>

<style scoped lang="scss">
.home-screen {
  padding: 16px 12px 20px;
  padding-top: 72px;
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 10px 8px;
  height: 100%;
  align-content: flex-start;
  justify-content: flex-start;
  box-sizing: border-box;
  overflow-y: auto;
}

.app-item {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.app-container {
  --app-bg: rgba(0, 0, 0, 0.818);
  --icon-color: white;

  background-color: var(--app-bg);
  border-radius: 16px;
  padding: 8px;
  cursor: pointer;
  transition: all 0.2s ease, background-color 0.2s ease;
  display: flex;
  flex-direction: column;
  align-items: center;
  aspect-ratio: 1/1;
  justify-content: space-between;
  position: relative;
  border: 0px solid transparent;

  &::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    border-radius: inherit;
    background: linear-gradient(
      to bottom, 
      transparent 0%,
      rgba(0, 0, 0, 0.5) 100%
    );
    pointer-events: none;
  }

  &:hover {
    transform: scale(1.05);
  }
}

.notification-badge {
  position: absolute;
  top: -4px;
  right: -4px;
  background-color: #ff3333;
  color: white;
  border-radius: 50%;
  min-width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: bold;
  padding: 0 4px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
  z-index: 10;
  border: 2px solid #000;
}

.app-icon {
  font-size: 3em;
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--icon-color);
  transition: color 0.2s ease;
  position: relative;
}

.app-name {
  color: white;
  font-size: 12px;
  text-align: center;
  font-weight: 500;
  margin-top: 8px;
  width: 100%;
  position: relative;
}

// Override phone wrapper's dark background
:deep(.phone-content) {
  background: linear-gradient(to bottom, #000000, #1509fb);
}
</style>
