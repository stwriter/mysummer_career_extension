<template>
  <div class="parts-orders-tab">
    <div class="tab-header">
      <h2>Parts Orders</h2>
      <p>Order parts for personal builds and pick them up at the tuning shop.</p>
    </div>

    <div class="orders-stats">
      <div class="stat">
        <span class="label">Pending Orders</span>
        <span class="value">{{ pendingOrders.length }}</span>
      </div>
      <div class="stat">
        <span class="label">Pending Value</span>
        <span class="value">${{ formatPrice(pendingTotal) }}</span>
      </div>
      <div class="zone-note" :class="{ ready: store.playerInZone }">
        {{ store.playerInZone ? "Pickup available in garage zone" : "Enter the tuning shop garage to collect orders" }}
      </div>
      <button class="btn btn-secondary refresh-button" @click="refresh" :disabled="isRefreshing">
        Refresh
      </button>
    </div>

    <div v-if="orders.length === 0" class="empty-state">
      No parts orders yet.
    </div>

    <div v-else class="orders-list">
      <div
        v-for="order in orders"
        :key="order.id"
        class="order-card"
      >
        <div class="order-details">
          <h3>{{ order.partNiceName || order.partName }}</h3>
          <div class="order-meta">
            <span>{{ order.vehicleModel }}</span>
            <span>Qty {{ order.quantity }}</span>
            <span v-if="order.slotNiceName">{{ order.slotNiceName }}</span>
          </div>
        </div>
        <div class="order-actions">
          <span class="order-price">${{ formatPrice(order.totalPrice || order.price || 0) }}</span>
          <span class="order-status" :class="`status-${order.status}`">{{ order.status }}</span>
          <button
            v-if="order.status === 'pending'"
            class="btn btn-primary"
            @click="collectOrder(order)"
            :disabled="!store.playerInZone || collectingId === order.id"
          >
            Collect
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref, watch } from "vue"
import { lua } from "@/bridge"
import { useBusinessComputerStore } from "../../stores/businessComputerStore"
import { formatPrice } from "../../utils/businessUtils"

const store = useBusinessComputerStore()
const collectingId = ref(null)
const isRefreshing = ref(false)

const orders = computed(() => {
  const list = store.businessData?.partsOrders || []
  return Array.isArray(list) ? list : []
})

const pendingOrders = computed(() => orders.value.filter(order => order.status === "pending"))

const pendingTotal = computed(() => {
  return pendingOrders.value.reduce((sum, order) => {
    const price = order.totalPrice || (order.price || 0) * (order.quantity || 1)
    return sum + price
  }, 0)
})

const refresh = async () => {
  if (!store.businessId || !store.businessType) return
  isRefreshing.value = true
  try {
    await store.loadBusinessData(store.businessType, store.businessId)
  } finally {
    isRefreshing.value = false
  }
}

const collectOrder = async (order) => {
  if (!order || !store.businessId) return
  collectingId.value = order.id
  try {
    const result = await lua.career_modules_business_tuningShop.collectPartOrder(store.businessId, order.id)
    if (result && result.success === false && result.message) {
      lua.ui_message(result.message, 4, "Parts Orders", "error")
    }
    await refresh()
  } catch (error) {
  } finally {
    collectingId.value = null
  }
}

onMounted(() => {
  refresh()
})

watch(() => store.businessId, (value) => {
  if (value) {
    refresh()
  }
})
</script>

<style scoped lang="scss">
.parts-orders-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5em;
}

.tab-header {
  h2 {
    margin: 0 0 0.5em 0;
    color: rgba(245, 73, 0, 1);
    font-size: 1.5em;
    font-weight: 600;
  }

  p {
    margin: 0;
    color: rgba(255, 255, 255, 0.6);
    font-size: 0.875em;
  }
}

.orders-stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 1em;
  align-items: center;

  .stat {
    padding: 1em;
    background: rgba(23, 23, 23, 0.5);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 0.5em;
    display: flex;
    flex-direction: column;

    .label {
      color: rgba(255, 255, 255, 0.6);
      font-size: 0.875em;
    }

    .value {
      color: rgba(245, 73, 0, 1);
      font-size: 1.25em;
      font-weight: 500;
    }
  }

  .zone-note {
    padding: 0.85em 1em;
    background: rgba(23, 23, 23, 0.5);
    border-radius: 0.5em;
    border: 1px solid rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.7);
    font-size: 0.85em;
  }

  .zone-note.ready {
    border-color: rgba(34, 197, 94, 0.6);
    color: rgba(34, 197, 94, 0.9);
  }

  .refresh-button {
    justify-self: start;
  }
}

.orders-list {
  display: flex;
  flex-direction: column;
  gap: 0.75em;
}

.order-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1em;
  padding: 1em 1.25em;
  background: rgba(23, 23, 23, 0.5);
  border: 1px solid rgba(245, 73, 0, 0.3);
  border-radius: 0.5em;
}

.order-details {
  display: flex;
  flex-direction: column;
  gap: 0.35em;

  h3 {
    margin: 0;
    color: white;
    font-size: 1em;
    font-weight: 600;
  }
}

.order-meta {
  display: flex;
  gap: 1em;
  color: rgba(255, 255, 255, 0.6);
  font-size: 0.85em;
}

.order-actions {
  display: flex;
  align-items: center;
  gap: 0.75em;
}

.order-price {
  color: rgba(245, 73, 0, 1);
  font-weight: 600;
}

.order-status {
  text-transform: capitalize;
  font-size: 0.85em;
  color: rgba(255, 255, 255, 0.7);
}

.order-status.status-collected {
  color: rgba(34, 197, 94, 0.9);
}

.empty-state {
  padding: 2em;
  border-radius: 0.5em;
  background: rgba(23, 23, 23, 0.35);
  border: 1px dashed rgba(255, 255, 255, 0.2);
  color: rgba(255, 255, 255, 0.6);
  text-align: center;
}
</style>
