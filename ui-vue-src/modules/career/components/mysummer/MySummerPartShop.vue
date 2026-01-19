<template>
  <div class="part-shop">
    <!-- Shop Header -->
    <div class="shop-header">
      <div class="header-left">
        <h2>{{ shopData.shopName || 'Parts Shop' }}</h2>
        <p class="shop-description">{{ shopData.shopDescription }}</p>
      </div>
      <div class="header-right">
        <div class="player-funds">
          <span class="label">Your funds:</span>
          <span class="amount">${{ formatNumber(playerFunds) }}</span>
        </div>
        <button class="close-btn" @click="closeShop">✕ Close</button>
      </div>
    </div>

    <!-- Parts List -->
    <div class="parts-container">
      <div class="parts-header">
        <span class="col-name">Part Name</span>
        <span class="col-slot">Type</span>
        <span class="col-price">Price</span>
        <span class="col-action"></span>
      </div>

      <div class="parts-list">
        <div
          v-for="part in filteredParts"
          :key="part.name"
          class="part-row"
          :class="{ 'cannot-afford': part.shopPrice > playerFunds }"
        >
          <span class="col-name">{{ part.niceName }}</span>
          <span class="col-slot">{{ formatSlotType(part.slotType) }}</span>
          <span class="col-price">${{ formatNumber(part.shopPrice) }}</span>
          <span class="col-action">
            <button
              class="buy-btn"
              :disabled="part.shopPrice > playerFunds || purchasing"
              @click="buyPart(part)"
            >
              Buy
            </button>
          </span>
        </div>

        <div v-if="filteredParts.length === 0" class="no-parts">
          No parts available
        </div>
      </div>
    </div>

    <!-- Search/Filter -->
    <div class="filter-bar">
      <input
        v-model="searchQuery"
        type="text"
        placeholder="Search parts..."
        class="search-input"
      />
      <select v-model="selectedSlotType" class="slot-filter">
        <option value="">All Types</option>
        <option v-for="slot in slotTypes" :key="slot" :value="slot">{{ formatSlotType(slot) }}</option>
      </select>
    </div>

    <!-- Purchase feedback -->
    <div v-if="lastPurchase" class="purchase-feedback" :class="lastPurchase.success ? 'success' : 'error'">
      {{ lastPurchase.message }}
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useBridge } from '@/bridge'

const { lua, events } = useBridge()

// Close shop and restore game state
const closeShop = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.closeShopMenu()')
  }
}

const shopData = ref({
  shopId: null,
  shopName: 'Parts Shop',
  shopDescription: '',
  priceMultiplier: 2.0,
  parts: []
})

const playerFunds = ref(0)
const searchQuery = ref('')
const selectedSlotType = ref('')
const purchasing = ref(false)
const lastPurchase = ref(null)

// Get unique slot types from parts
const slotTypes = computed(() => {
  const types = new Set()
  for (const part of shopData.value.parts) {
    if (part.slotType) {
      types.add(part.slotType)
    }
  }
  return Array.from(types).sort()
})

// Filter parts by search and slot type
const filteredParts = computed(() => {
  let parts = shopData.value.parts

  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase()
    parts = parts.filter(p =>
      p.niceName.toLowerCase().includes(query) ||
      p.name.toLowerCase().includes(query)
    )
  }

  if (selectedSlotType.value) {
    parts = parts.filter(p => p.slotType === selectedSlotType.value)
  }

  return parts
})

// Format number with commas
const formatNumber = (num) => {
  return num.toLocaleString()
}

// Format slot type for display
const formatSlotType = (slot) => {
  if (!slot) return 'Unknown'
  // Convert etki_engine to Engine, etc.
  return slot
    .replace(/^etki_/, '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, l => l.toUpperCase())
}

// Buy a part
const buyPart = async (part) => {
  if (purchasing.value) return

  purchasing.value = true
  lastPurchase.value = null

  try {
    const result = await lua.career_modules_mysummerPartShops.purchasePart(shopData.value.shopId, part.name)

    if (result.success) {
      lastPurchase.value = { success: true, message: `Purchased: ${part.niceName}` }
      // Refresh funds
      updatePlayerFunds()
    } else {
      lastPurchase.value = { success: false, message: result.message || 'Purchase failed' }
    }
  } catch (err) {
    lastPurchase.value = { success: false, message: 'Error purchasing part' }
    console.error('Purchase error:', err)
  }

  purchasing.value = false

  // Clear message after 3 seconds
  setTimeout(() => {
    lastPurchase.value = null
  }, 3000)
}

// Update player funds
const updatePlayerFunds = async () => {
  try {
    const funds = await lua.career_modules_playerAttributes.getAttributeValue("money")
    playerFunds.value = funds || 0
  } catch (err) {
    console.error('Error getting funds:', err)
  }
}

// Handle shop data update from Lua
const handleShopOpened = (data) => {
  console.log('[MySummerPartShop] Shop opened:', data)
  shopData.value = data
  updatePlayerFunds()
}

onMounted(() => {
  events.on('mysummerPartShopOpened', handleShopOpened)
  updatePlayerFunds()
})

onUnmounted(() => {
  events.off('mysummerPartShopOpened', handleShopOpened)
})
</script>

<style scoped lang="scss">
.part-shop {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: 1rem;
  color: #e0e0e0;
}

.shop-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 1rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid #444;

  .header-left {
    h2 {
      margin: 0 0 0.5rem 0;
      color: #ff9800;
    }

    .shop-description {
      margin: 0;
      color: #aaa;
      font-size: 0.9rem;
    }
  }

  .header-right {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 0.5rem;
  }

  .player-funds {
    display: flex;
    gap: 0.5rem;
    font-size: 1.1rem;

    .label {
      color: #888;
    }

    .amount {
      color: #4caf50;
      font-weight: bold;
    }
  }

  .close-btn {
    padding: 0.5rem 1rem;
    background: #c62828;
    border: none;
    border-radius: 4px;
    color: #fff;
    cursor: pointer;
    font-weight: bold;
    transition: background 0.2s;

    &:hover {
      background: #e53935;
    }
  }
}

.filter-bar {
  display: flex;
  gap: 1rem;
  margin-bottom: 1rem;

  .search-input {
    flex: 1;
    padding: 0.5rem;
    background: #333;
    border: 1px solid #555;
    border-radius: 4px;
    color: #fff;

    &::placeholder {
      color: #777;
    }
  }

  .slot-filter {
    padding: 0.5rem;
    background: #333;
    border: 1px solid #555;
    border-radius: 4px;
    color: #fff;
    min-width: 150px;
  }
}

.parts-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.parts-header {
  display: flex;
  padding: 0.5rem;
  background: #333;
  font-weight: bold;
  border-radius: 4px 4px 0 0;
}

.parts-list {
  flex: 1;
  overflow-y: auto;
  background: #222;
  border-radius: 0 0 4px 4px;
}

.part-row {
  display: flex;
  padding: 0.75rem 0.5rem;
  border-bottom: 1px solid #333;
  transition: background 0.2s;

  &:hover {
    background: #2a2a2a;
  }

  &.cannot-afford {
    opacity: 0.5;
  }
}

.col-name {
  flex: 2;
}

.col-slot {
  flex: 1;
  color: #888;
}

.col-price {
  flex: 1;
  text-align: right;
  color: #ff9800;
  font-weight: bold;
}

.col-action {
  flex: 0 0 80px;
  text-align: right;
}

.buy-btn {
  padding: 0.4rem 1rem;
  background: #4caf50;
  border: none;
  border-radius: 4px;
  color: #fff;
  cursor: pointer;
  font-weight: bold;
  transition: background 0.2s;

  &:hover:not(:disabled) {
    background: #66bb6a;
  }

  &:disabled {
    background: #555;
    cursor: not-allowed;
  }
}

.no-parts {
  padding: 2rem;
  text-align: center;
  color: #666;
}

.purchase-feedback {
  margin-top: 1rem;
  padding: 0.75rem;
  border-radius: 4px;
  text-align: center;
  font-weight: bold;

  &.success {
    background: rgba(76, 175, 80, 0.2);
    color: #4caf50;
  }

  &.error {
    background: rgba(244, 67, 54, 0.2);
    color: #f44336;
  }
}
</style>
