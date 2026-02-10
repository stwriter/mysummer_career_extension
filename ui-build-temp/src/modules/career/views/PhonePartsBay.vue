<template>
  <PhoneWrapper app-name="Parts Bay" status-font-color="#90caf9" status-blend-mode="">
    <div class="bay-screen">
      <!-- Header -->
      <div class="bay-header">
        <div class="bay-icon">&#9881;</div>
        <div class="bay-title">Parts Bay</div>
        <div class="bay-subtitle">Pickup Manager</div>
      </div>

      <!-- Active Pickup -->
      <div v-if="activePickup" class="active-section">
        <div class="label">ACTIVE PICKUP</div>
        <div class="active-card">
          <div class="active-dot"></div>
          <div class="active-body">
            <div class="part-name">{{ activePickup.partNiceName || activePickup.partName }}</div>
            <div class="part-location">{{ activePickup.location?.name || 'Unknown' }}</div>
            <div class="part-meta" v-if="activePickup.distance">
              {{ formatDistance(activePickup.distance) }} away
            </div>
          </div>
        </div>
        <div class="active-actions">
          <button class="btn btn-nav" @click="navigateToActive">
            NAVIGATE
          </button>
          <button class="btn btn-stop" @click="cancelActive">
            STOP
          </button>
        </div>
      </div>

      <!-- Pending Queue -->
      <div v-if="pendingPickups.length > 0" class="queue-section">
        <div class="label">QUEUED <span class="count">({{ pendingPickups.length }})</span></div>
        <div
          v-for="(pickup, idx) in pendingPickups"
          :key="idx"
          class="queue-item"
          @click="activatePickup(idx + 1)"
        >
          <div class="queue-num">{{ idx + 1 }}</div>
          <div class="queue-body">
            <div class="part-name">{{ pickup.partNiceName || pickup.partName }}</div>
            <div class="part-location">{{ pickup.location?.name || 'Unknown' }}</div>
            <div class="part-price" v-if="pickup.price">${{ formatPrice(pickup.price) }}</div>
          </div>
          <button class="btn-x" @click.stop="cancelPending(idx + 1)">&#10005;</button>
        </div>
        <div class="queue-hint">Tap a pickup to activate it</div>
      </div>

      <!-- Empty State -->
      <div v-if="!activePickup && pendingPickups.length === 0" class="empty-state">
        <div class="empty-icon">&#9881;</div>
        <div class="empty-title">No pickups</div>
        <div class="empty-sub">Purchase parts from Parts Bay on the computer to queue pickups here.</div>
      </div>
    </div>
  </PhoneWrapper>
</template>

<script setup>
import PhoneWrapper from "./PhoneWrapper.vue"
import { computed, onMounted } from 'vue'
import { useMySummerPartsStore } from "../stores/mysummerPartsStore"

const store = useMySummerPartsStore()

const activePickup = computed(() => {
  const pickup = store.marketData.activePickup
  return pickup && !pickup.isIllegal ? pickup : null
})

const pendingPickups = computed(() => {
  return store.marketData.pendingPickups || []
})

const formatDistance = (distance) => {
  if (!distance && distance !== 0) return "--"
  if (distance >= 1000) return `${(distance / 1000).toFixed(1)} km`
  return `${Math.round(distance)} m`
}

const formatPrice = (value) => {
  return Number(value || 0).toLocaleString("en-US", { minimumFractionDigits: 2 })
}

const navigateToActive = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerParts.setWaypointToActivePickup()')
    window.bngApi.engineLua("guihooks.trigger('closePhone')")
  }
}

const cancelActive = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerParts.cancelActivePickup()')
  }
}

const activatePickup = (index) => {
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerParts.activatePendingPickup(${index})`)
    window.bngApi.engineLua("guihooks.trigger('closePhone')")
  }
}

const cancelPending = (index) => {
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerParts.cancelPendingPickup(${index})`)
  }
}

onMounted(() => {
  store.requestData()
})
</script>

<style scoped lang="scss">
$accent: #64b5f6;
$accent-dim: rgba(100, 181, 246, 0.15);
$green: #66bb6a;
$green-dim: rgba(102, 187, 106, 0.15);
$red: #ef5350;
$red-dim: rgba(239, 83, 80, 0.12);
$text: #e0e0e0;
$text-dim: #888;
$bg-card: rgba(255, 255, 255, 0.04);
$border: rgba(255, 255, 255, 0.08);

.bay-screen {
  padding: 12px 14px 20px;
  padding-top: 68px;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  overflow-y: auto;
  color: $text;
}

.bay-header {
  text-align: center;
  padding-bottom: 14px;
  margin-bottom: 14px;
  border-bottom: 1px solid $border;
}

.bay-icon {
  font-size: 1.6rem;
  color: $accent;
  margin-bottom: 4px;
}

.bay-title {
  font-size: 1.1rem;
  font-weight: 700;
  color: white;
  letter-spacing: 0.5px;
}

.bay-subtitle {
  font-size: 0.7rem;
  color: $text-dim;
  margin-top: 2px;
}

.label {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 1.2px;
  color: $text-dim;
  margin-bottom: 8px;

  .count {
    color: $accent;
  }
}

// Active pickup
.active-section {
  margin-bottom: 18px;
}

.active-card {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 12px;
  background: $green-dim;
  border: 1px solid rgba(102, 187, 106, 0.3);
  border-radius: 10px;
  margin-bottom: 8px;
}

.active-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: $green;
  margin-top: 5px;
  flex-shrink: 0;
  box-shadow: 0 0 6px rgba(102, 187, 106, 0.6);
  animation: pulse 2s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

.active-body {
  flex: 1;
  min-width: 0;
}

.active-actions {
  display: flex;
  gap: 8px;
}

.btn {
  flex: 1;
  padding: 10px 0;
  border: none;
  border-radius: 8px;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.8px;
  cursor: pointer;
  transition: background 0.15s;
}

.btn-nav {
  background: $green;
  color: #fff;

  &:hover { background: darken(#66bb6a, 8%); }
}

.btn-stop {
  background: $red-dim;
  color: $red;
  border: 1px solid rgba(239, 83, 80, 0.25);

  &:hover { background: rgba(239, 83, 80, 0.25); }
}

// Queue
.queue-section {
  flex: 1;
}

.queue-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  background: $bg-card;
  border: 1px solid $border;
  border-radius: 10px;
  margin-bottom: 6px;
  cursor: pointer;
  transition: all 0.15s;

  &:hover {
    border-color: rgba(100, 181, 246, 0.35);
    background: $accent-dim;
  }

  &:active {
    transform: scale(0.98);
  }
}

.queue-num {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.08);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.65rem;
  font-weight: 700;
  color: $text-dim;
  flex-shrink: 0;
}

.queue-body {
  flex: 1;
  min-width: 0;
}

.queue-hint {
  text-align: center;
  font-size: 0.6rem;
  color: #555;
  margin-top: 6px;
}

.btn-x {
  width: 26px;
  height: 26px;
  border-radius: 50%;
  border: none;
  background: $red-dim;
  color: $red;
  font-size: 0.65rem;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: background 0.15s;

  &:hover { background: rgba(239, 83, 80, 0.3); }
}

// Shared text
.part-name {
  font-size: 0.8rem;
  font-weight: 600;
  color: white;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.part-location {
  font-size: 0.65rem;
  color: $text-dim;
  margin-top: 1px;
}

.part-meta {
  font-size: 0.65rem;
  color: $green;
  margin-top: 2px;
}

.part-price {
  font-size: 0.65rem;
  color: $accent;
  margin-top: 2px;
}

// Empty
.empty-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 40px 24px;
}

.empty-icon {
  font-size: 2.2rem;
  color: #333;
  margin-bottom: 12px;
}

.empty-title {
  font-size: 0.95rem;
  color: #555;
  font-weight: 600;
}

.empty-sub {
  font-size: 0.7rem;
  color: #444;
  margin-top: 6px;
  line-height: 1.4;
}

:deep(.phone-content) {
  background: linear-gradient(to bottom, #0d1117, #161b22);
}
</style>
