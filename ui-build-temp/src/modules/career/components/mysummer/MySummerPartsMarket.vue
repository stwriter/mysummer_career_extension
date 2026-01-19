<template>
  <div class="wallapop-root" :class="{ compact }">
    <!-- Header -->
    <div class="wallapop-header">
      <div class="header-left">
        <h2>PARTS_MARKET.onion</h2>
      </div>
      <button class="refresh-btn" @click="refreshListings" :disabled="store.loading">[R]</button>
    </div>

    <!-- Error message -->
    <div v-if="errorMessage" class="error-banner">
      {{ errorMessage }}
    </div>

    <!-- Search and filters -->
    <div class="search-bar">
      <input
        type="text"
        v-model="searchQuery"
        placeholder="Buscar pieza..."
        class="search-input"
      />
      <select v-model="sortBy" class="sort-select">
        <option value="price-asc">Precio: menor</option>
        <option value="price-desc">Precio: mayor</option>
        <option value="distance">Distancia</option>
        <option value="time">Expira pronto</option>
      </select>
    </div>

    <!-- Tabs -->
    <div class="tabs">
      <button class="tab" :class="{ active: activeTab === 'listings' }" @click="activeTab = 'listings'">
        [LISTINGS]
        <span class="tab-count">{{ filteredListings.length }}</span>
      </button>
      <button class="tab" :class="{ active: activeTab === 'leads' }" @click="activeTab = 'leads'">
        [LEADS]
        <span class="tab-count danger">{{ leads.length }}</span>
      </button>
      <button class="tab" :class="{ active: activeTab === 'active' }" @click="activeTab = 'active'">
        [ACTIVE]
        <span v-if="activePickup || pendingCount > 0" class="tab-dot"></span>
      </button>
    </div>

    <!-- Selection bar for multiple selection -->
    <div v-if="selectedIds.length > 0 && activeTab === 'listings'" class="selection-bar">
      <span>SELECTED: {{ selectedIds.length }}</span>
      <span class="selection-total">${{ formatPrice(selectedTotal) }}</span>
      <button class="batch-btn" @click="acceptSelectedListings">
        [PICKUP {{ selectedIds.length }}]
      </button>
      <button class="clear-btn" @click="clearSelection">[X]</button>
    </div>

    <!-- Content -->
    <div class="content-area">
      <!-- Listings Tab - Grid of cards -->
      <div v-if="activeTab === 'listings'" class="listings-grid">
        <div v-if="filteredListings.length === 0" class="empty-state">
          <span class="empty-icon">[?]</span>
          <p>NO_LISTINGS_FOUND</p>
        </div>

        <div
          v-for="listing in filteredListings"
          :key="listing.id"
          class="part-card"
          :class="{ selected: selectedIds.includes(listing.id) }"
          @click="toggleSelection(listing.id)"
        >
          <!-- Checkbox -->
          <div class="card-checkbox">
            <input
              type="checkbox"
              :checked="selectedIds.includes(listing.id)"
              @click.stop="toggleSelection(listing.id)"
            />
          </div>

          <!-- Part info -->
          <div class="card-body">
            <h3 class="card-title">{{ listing.partNiceName || listing.partName }}</h3>

            <!-- Mileage bar -->
            <div class="mileage-row">
              <span class="mileage-label">{{ formatMileage(listing.condition?.odometer) }}</span>
              <div class="mileage-bar">
                <div class="mileage-fill" :style="{ width: getMileagePercent(listing.condition?.odometer) + '%' }"></div>
              </div>
            </div>

            <!-- Price -->
            <div class="card-price">{{ formatPrice(listing.price) }}</div>

            <!-- Meta info -->
            <div class="card-meta">
              <span class="meta-item">
                <span class="meta-icon">@</span>
                {{ formatDistance(listing.distance) }}
              </span>
              <span class="meta-item expiry" :class="{ urgent: isExpiringSoon(listing) }">
                <span class="meta-icon">T</span>
                {{ formatTimeRemaining(listing.expiresAt) }}
              </span>
            </div>
          </div>

          <!-- Quick action -->
          <button
            class="card-action"
            @click.stop="acceptListing(listing)"
            title="Reserve"
          >
            [GET]
          </button>
        </div>
      </div>

      <!-- Leads Tab - Illegal parts -->
      <div v-if="activeTab === 'leads'" class="leads-grid">
        <div v-if="leads.length === 0" class="empty-state">
          <span class="empty-icon">[X]</span>
          <p>NO_LEADS_AVAILABLE</p>
        </div>

        <div v-for="lead in leads" :key="lead.id" class="lead-card" :class="`heat-${lead.heat}`">
          <div class="lead-badge">
            <span class="badge-icon">!</span>
            <span class="badge-heat">{{ lead.heat.toUpperCase() }}</span>
          </div>

          <div class="lead-body">
            <h3 class="lead-title">{{ lead.partNiceName || lead.partName }}</h3>
            <p class="lead-message">"{{ lead.message }}"</p>

            <div class="lead-meta">
              <span>@ {{ lead.location?.name || "Desconocido" }}</span>
              <span>T {{ formatTimeRemaining(lead.expiresAt) }}</span>
            </div>
          </div>

          <div class="lead-footer">
            <span class="lead-price">FREE</span>
            <button class="lead-action" @click="acceptLead(lead)">
              [ACCEPT_LEAD]
            </button>
          </div>
        </div>
      </div>

      <!-- Active Tab - Current pickup -->
      <div v-if="activeTab === 'active'" class="active-pane">
        <div v-if="!activePickup && pendingCount === 0" class="empty-state">
          <span class="empty-icon">[_]</span>
          <p>QUEUE_EMPTY</p>
        </div>

        <div v-if="activePickup" class="active-card">
          <div class="active-status">
            <span class="status-dot" :class="{ illegal: activePickup.isIllegal }"></span>
            <span>{{ activePickup.isIllegal ? 'LEAD_ACTIVE' : 'PICKUP_ACTIVE' }}</span>
          </div>

          <h3 class="active-title">{{ activePickup.partNiceName || activePickup.partName }}</h3>

          <div class="active-details">
            <div class="detail-row">
              <span class="detail-label">Location</span>
              <span class="detail-value">{{ activePickup.location?.name || "Unknown" }}</span>
            </div>
            <div class="detail-row">
              <span class="detail-label">Distance</span>
              <span class="detail-value">{{ formatDistance(activePickup.distance) }}</span>
            </div>
            <div v-if="activePickup.price" class="detail-row">
              <span class="detail-label">Price</span>
              <span class="detail-value price">${{ formatPrice(activePickup.price) }}</span>
            </div>
          </div>

          <div v-if="activePickup.isIllegal" class="warning-box">
            WARNING: EXPECT PURSUIT AFTER PICKUP
          </div>

          <button class="cancel-btn" @click="cancelPickup">
            [CANCEL]
          </button>
        </div>

        <!-- Pending pickups queue -->
        <div v-if="pendingCount > 0" class="pending-section">
          <h4>PICKUP_QUEUE [{{ pendingCount }}]</h4>
          <div class="pending-list">
            <div v-for="(pending, idx) in pendingPickups" :key="idx" class="pending-item">
              <span class="pending-num">{{ idx + 1 }}</span>
              <span class="pending-name">{{ pending.partNiceName || pending.partName }}</span>
              <span class="pending-price">${{ formatPrice(pending.price) }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref, onUnmounted } from "vue"
import { useMySummerPartsStore } from "../../stores/mysummerPartsStore"

const props = defineProps({
  compact: {
    type: Boolean,
    default: false,
  },
})

const store = useMySummerPartsStore()
const activeTab = ref("listings")
const errorMessage = ref("")
const searchQuery = ref("")
const sortBy = ref("price-asc")
const selectedIds = ref([])

// Computed
const listings = computed(() => store.marketData.listings || [])
const leads = computed(() => store.marketData.leads || [])
const activePickup = computed(() => store.marketData.activePickup)
const pendingPickups = computed(() => store.marketData.pendingPickups || [])
const pendingCount = computed(() => store.marketData.pendingCount || 0)

const filteredListings = computed(() => {
  let result = [...listings.value]

  // Search filter
  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase()
    result = result.filter(l =>
      (l.partNiceName || l.partName || "").toLowerCase().includes(query)
    )
  }

  // Sort
  switch (sortBy.value) {
    case "price-asc":
      result.sort((a, b) => (a.price || 0) - (b.price || 0))
      break
    case "price-desc":
      result.sort((a, b) => (b.price || 0) - (a.price || 0))
      break
    case "distance":
      result.sort((a, b) => (a.distance || 9999) - (b.distance || 9999))
      break
    case "time":
      result.sort((a, b) => (a.expiresAt || 0) - (b.expiresAt || 0))
      break
  }

  return result
})

const selectedTotal = computed(() => {
  return listings.value
    .filter(l => selectedIds.value.includes(l.id))
    .reduce((sum, l) => sum + (l.price || 0), 0)
})

// Methods
const toggleSelection = (id) => {
  const idx = selectedIds.value.indexOf(id)
  if (idx >= 0) {
    selectedIds.value.splice(idx, 1)
  } else {
    selectedIds.value.push(id)
  }
}

const clearSelection = () => {
  selectedIds.value = []
}

const acceptSelectedListings = async () => {
  if (selectedIds.value.length === 0) return
  errorMessage.value = ""

  const result = await store.acceptMultipleListings(selectedIds.value)
  if (result && result.success === false) {
    errorMessage.value = result.message || "No se pudieron reservar las piezas."
  } else {
    selectedIds.value = []
    activeTab.value = "active"
  }
}

const refreshListings = async () => {
  errorMessage.value = ""
  try {
    await store.refreshListings()
  } catch (err) {
    errorMessage.value = "Error al refrescar."
  }
}

const acceptListing = async (listing) => {
  errorMessage.value = ""
  const result = await store.acceptListing(listing.id)
  if (result && result.success === false) {
    errorMessage.value = result.message || "No se pudo reservar."
  } else {
    activeTab.value = "active"
  }
}

const acceptLead = async (lead) => {
  errorMessage.value = ""
  const result = await store.acceptLead(lead.id)
  if (result && result.success === false) {
    errorMessage.value = result.message || "No se pudo aceptar el soplo."
  } else {
    activeTab.value = "active"
  }
}

const cancelPickup = async () => {
  errorMessage.value = ""
  await store.cancelPickup()
}

// Formatting
const formatPrice = (value) => {
  return Number(value || 0).toLocaleString("es-ES")
}

const formatDistance = (distance) => {
  if (!distance && distance !== 0) return "--"
  if (distance >= 1000) return `${(distance / 1000).toFixed(1)} km`
  return `${Math.round(distance)} m`
}

const formatMileage = (odometer) => {
  if (!odometer && odometer !== 0) return "-- km"
  return `${Math.round(odometer / 1000).toLocaleString("es-ES")} km`
}

const getMileagePercent = (odometer) => {
  if (!odometer) return 0
  // 0-200k km scale
  return Math.min(100, (odometer / 200000) * 100)
}

const formatTimeRemaining = (expiresAt) => {
  if (!expiresAt) return "--"
  const now = Math.floor(Date.now() / 1000)
  const diff = expiresAt - now
  if (diff <= 0) return "Expirado"
  if (diff < 60) return `${diff}s`
  if (diff < 3600) return `${Math.floor(diff / 60)}min`
  return `${Math.floor(diff / 3600)}h ${Math.floor((diff % 3600) / 60)}m`
}

const isExpiringSoon = (listing) => {
  if (!listing.expiresAt) return false
  const now = Math.floor(Date.now() / 1000)
  return (listing.expiresAt - now) < 600 // Less than 10 min
}

onMounted(() => {
  store.requestData()
})

onUnmounted(() => {
  store.dispose()
})
</script>

<style scoped lang="scss">
// ============================================
// RETRO DEEP WEB BROWSER STYLE
// Inspired by early 2000s browsers & dark web
// ============================================

$terminal-green: #00ff41;
$terminal-amber: #ffb000;
$terminal-red: #ff3333;
$terminal-cyan: #00ffff;
$bg-dark: #0a0a0a;
$bg-panel: #111111;
$border-color: #333333;

.wallapop-root {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  color: $terminal-green;
  background: $bg-dark;
  border: 2px solid $border-color;
  padding: 0.5rem;
  height: 100%;
  overflow: hidden;
  font-family: "Courier New", Courier, monospace;
  font-size: 13px;
  image-rendering: pixelated;

  // CRT scanline effect
  &::before {
    content: "";
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: repeating-linear-gradient(
      0deg,
      rgba(0, 0, 0, 0.15) 0px,
      rgba(0, 0, 0, 0.15) 1px,
      transparent 1px,
      transparent 2px
    );
    pointer-events: none;
    z-index: 100;
  }
}

.wallapop-root.compact {
  border: none;
  padding-top: 2.5rem;
}

// Header - Old browser title bar style
.wallapop-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.4rem 0.6rem;
  background: linear-gradient(180deg, #2a2a2a 0%, #1a1a1a 100%);
  border: 1px solid $border-color;
  border-bottom: 2px solid #444;

  h2 {
    margin: 0;
    font-size: 14px;
    font-weight: normal;
    color: $terminal-green;
    text-transform: uppercase;
    letter-spacing: 2px;
    text-shadow: 0 0 10px rgba(0, 255, 65, 0.5);

    &::before {
      content: ">> ";
      color: $terminal-amber;
    }
  }

  p {
    display: none;
  }
}

.refresh-btn {
  width: 24px;
  height: 24px;
  background: $bg-panel;
  border: 1px solid $border-color;
  color: $terminal-green;
  font-size: 12px;
  cursor: pointer;
  font-family: inherit;

  &:hover:not(:disabled) {
    background: #222;
    color: $terminal-amber;
    border-color: $terminal-amber;
  }

  &:active {
    background: #000;
  }
}

// Error - Terminal style
.error-banner {
  padding: 0.4rem 0.6rem;
  background: rgba(255, 51, 51, 0.1);
  border: 1px dashed $terminal-red;
  font-size: 12px;
  color: $terminal-red;

  &::before {
    content: "[ERROR] ";
    font-weight: bold;
  }
}

// Search - Command line style
.search-bar {
  display: flex;
  gap: 0.3rem;
  padding: 0.3rem;
  background: $bg-panel;
  border: 1px solid $border-color;
}

.search-input {
  flex: 1;
  padding: 0.3rem 0.5rem;
  background: #000;
  border: 1px inset #333;
  color: $terminal-green;
  font-family: inherit;
  font-size: 12px;

  &::placeholder {
    color: #555;
  }

  &:focus {
    outline: none;
    border-color: $terminal-green;
    box-shadow: 0 0 5px rgba(0, 255, 65, 0.3);
  }
}

.sort-select {
  padding: 0.3rem 0.5rem;
  background: #000;
  border: 1px inset #333;
  color: $terminal-green;
  font-family: inherit;
  font-size: 11px;
  cursor: pointer;

  option {
    background: #000;
    color: $terminal-green;
  }
}

// Tabs - Old browser tabs
.tabs {
  display: flex;
  gap: 2px;
  background: #222;
  padding: 2px 2px 0;
  border: 1px solid $border-color;
  border-bottom: none;
}

.tab {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.3rem;
  padding: 0.4rem 0.6rem;
  background: linear-gradient(180deg, #1a1a1a 0%, #0d0d0d 100%);
  border: 1px solid $border-color;
  border-bottom: none;
  color: #666;
  font-weight: normal;
  font-size: 11px;
  font-family: inherit;
  text-transform: uppercase;
  cursor: pointer;

  &.active {
    background: $bg-dark;
    color: $terminal-green;
    border-bottom: 1px solid $bg-dark;
    margin-bottom: -1px;
    text-shadow: 0 0 8px rgba(0, 255, 65, 0.4);
  }

  &:hover:not(.active) {
    color: #888;
  }
}

.tab-count {
  font-size: 10px;
  padding: 0 0.3rem;
  background: #222;
  border: 1px solid #444;

  &.danger {
    background: rgba(255, 51, 51, 0.2);
    border-color: $terminal-red;
    color: $terminal-red;
  }
}

.tab-dot {
  width: 6px;
  height: 6px;
  background: $terminal-green;
  animation: blink 1s infinite;
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

// Selection bar - Status bar style
.selection-bar {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.3rem 0.6rem;
  background: #1a1a00;
  border: 1px solid $terminal-amber;
  font-size: 11px;
  color: $terminal-amber;

  &::before {
    content: "[!] ";
  }
}

.selection-total {
  font-weight: bold;
  color: $terminal-amber;
}

.batch-btn {
  margin-left: auto;
  padding: 0.2rem 0.6rem;
  background: #222;
  border: 1px solid $terminal-amber;
  color: $terminal-amber;
  font-family: inherit;
  font-size: 11px;
  cursor: pointer;
  text-transform: uppercase;

  &:hover {
    background: $terminal-amber;
    color: #000;
  }
}

.clear-btn {
  padding: 0.2rem 0.4rem;
  background: transparent;
  border: 1px solid #555;
  color: #888;
  font-family: inherit;
  cursor: pointer;

  &:hover {
    border-color: $terminal-red;
    color: $terminal-red;
  }
}

// Content area
.content-area {
  flex: 1;
  overflow: auto;
  background: #000;
  border: 1px solid $border-color;
  padding: 0.5rem;
}

.content-area::-webkit-scrollbar {
  width: 12px;
  background: #111;
}

.content-area::-webkit-scrollbar-thumb {
  background: linear-gradient(180deg, #444 0%, #222 100%);
  border: 1px solid #555;
}

.content-area::-webkit-scrollbar-button {
  height: 12px;
  background: #222;
  border: 1px solid #444;
}

// Empty state
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 2rem 1rem;
  color: #555;
  text-align: center;

  .empty-icon {
    font-size: 1.5rem;
    margin-bottom: 0.5rem;
    filter: grayscale(1);
  }

  p {
    margin: 0;
    font-size: 11px;
    text-transform: uppercase;

    &::before {
      content: "-- ";
    }
    &::after {
      content: " --";
    }
  }
}

// Listings grid - Table-like layout
.listings-grid {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

// Part card - Row style like old file listings
.part-card {
  position: relative;
  display: grid;
  grid-template-columns: 24px 1fr auto;
  align-items: center;
  gap: 0.5rem;
  background: rgba(0, 255, 65, 0.02);
  border: 1px solid transparent;
  padding: 0.4rem 0.5rem;
  cursor: pointer;

  &:nth-child(odd) {
    background: rgba(0, 255, 65, 0.05);
  }

  &:hover {
    background: rgba(0, 255, 65, 0.1);
    border-color: rgba(0, 255, 65, 0.3);
  }

  &.selected {
    background: rgba(255, 176, 0, 0.1);
    border-color: $terminal-amber;
    color: $terminal-amber;
  }
}

.card-checkbox {
  display: flex;
  align-items: center;
  justify-content: center;

  input {
    width: 14px;
    height: 14px;
    accent-color: $terminal-green;
    cursor: pointer;
  }
}

.card-body {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.3rem 1rem;
  min-width: 0;
}

.card-title {
  margin: 0;
  font-size: 12px;
  font-weight: normal;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 180px;
}

.mileage-row {
  display: flex;
  align-items: center;
  gap: 0.3rem;
}

.mileage-label {
  font-size: 10px;
  color: #888;
  min-width: 60px;
}

.mileage-bar {
  width: 50px;
  height: 6px;
  background: #222;
  border: 1px inset #333;
  overflow: hidden;
}

.mileage-fill {
  height: 100%;
  background: $terminal-green;
}

.card-price {
  font-size: 12px;
  font-weight: bold;
  color: $terminal-cyan;

  &::before {
    content: "$";
  }
}

.card-meta {
  display: flex;
  gap: 0.8rem;
  font-size: 10px;
  color: #666;
}

.meta-item {
  display: flex;
  align-items: center;
  gap: 0.2rem;

  &.expiry.urgent {
    color: $terminal-red;
    animation: blink 1s infinite;
  }
}

.meta-icon {
  font-size: 10px;
}

.card-action {
  padding: 0.2rem 0.5rem;
  background: #111;
  border: 1px solid #444;
  color: $terminal-green;
  font-family: inherit;
  font-size: 10px;
  cursor: pointer;
  opacity: 0;

  .part-card:hover & {
    opacity: 1;
  }

  &:hover {
    background: $terminal-green;
    color: #000;
    border-color: $terminal-green;
  }
}

// Leads grid
.leads-grid {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.lead-card {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  padding: 0.6rem;
  background: rgba(255, 51, 51, 0.05);
  border: 1px solid #333;
  border-left: 3px solid;

  &.heat-normal {
    border-left-color: $terminal-green;
  }
  &.heat-hot {
    border-left-color: $terminal-amber;
  }
  &.heat-extreme {
    border-left-color: $terminal-red;
    animation: danger-pulse 2s infinite;
  }
}

@keyframes danger-pulse {
  0%, 100% { background: rgba(255, 51, 51, 0.05); }
  50% { background: rgba(255, 51, 51, 0.15); }
}

.lead-badge {
  display: flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 10px;
  font-weight: bold;
  text-transform: uppercase;
  letter-spacing: 1px;

  .badge-icon {
    font-size: 12px;
  }

  .heat-normal & { color: $terminal-green; }
  .heat-hot & { color: $terminal-amber; }
  .heat-extreme & { color: $terminal-red; }
}

.lead-title {
  margin: 0;
  font-size: 13px;
  color: #ddd;
}

.lead-message {
  margin: 0;
  font-size: 11px;
  color: #888;
  font-style: italic;

  &::before {
    content: "> ";
    color: #555;
  }
}

.lead-meta {
  display: flex;
  gap: 1rem;
  font-size: 10px;
  color: #666;
}

.lead-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 0.2rem;
  padding-top: 0.4rem;
  border-top: 1px dashed #333;
}

.lead-price {
  font-size: 14px;
  font-weight: bold;
  color: $terminal-green;
  text-shadow: 0 0 8px rgba(0, 255, 65, 0.5);
}

.lead-action {
  padding: 0.3rem 0.8rem;
  background: #220000;
  border: 1px solid $terminal-red;
  color: $terminal-red;
  font-family: inherit;
  font-size: 11px;
  text-transform: uppercase;
  cursor: pointer;

  &:hover {
    background: $terminal-red;
    color: #000;
  }
}

// Active pane
.active-pane {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.active-card {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0.6rem;
  background: rgba(0, 255, 65, 0.03);
  border: 1px solid $terminal-green;
}

.active-status {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 10px;
  font-weight: bold;
  text-transform: uppercase;
  letter-spacing: 1px;
  color: $terminal-green;
}

.status-dot {
  width: 8px;
  height: 8px;
  background: $terminal-green;
  animation: blink 0.5s infinite;

  &.illegal {
    background: $terminal-red;
  }
}

.active-title {
  margin: 0;
  font-size: 14px;
  color: #fff;
}

.active-details {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  font-size: 11px;
}

.detail-row {
  display: flex;
  justify-content: space-between;
}

.detail-label {
  color: #666;

  &::after {
    content: ":";
  }
}

.detail-value {
  color: $terminal-green;

  &.price {
    color: $terminal-cyan;
  }
}

.warning-box {
  padding: 0.4rem 0.6rem;
  background: rgba(255, 51, 51, 0.1);
  border: 1px dashed $terminal-red;
  font-size: 11px;
  color: $terminal-red;
  animation: blink 2s infinite;
}

.cancel-btn {
  padding: 0.3rem;
  background: #111;
  border: 1px solid #555;
  color: #888;
  font-family: inherit;
  font-size: 11px;
  text-transform: uppercase;
  cursor: pointer;

  &:hover {
    border-color: $terminal-red;
    color: $terminal-red;
  }
}

// Pending section
.pending-section {
  padding: 0.5rem;
  background: rgba(255, 176, 0, 0.03);
  border: 1px solid #333;

  h4 {
    margin: 0 0 0.5rem;
    font-size: 11px;
    font-weight: normal;
    color: $terminal-amber;
    text-transform: uppercase;

    &::before {
      content: "// ";
    }
  }
}

.pending-list {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.pending-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.3rem 0.4rem;
  background: rgba(255, 176, 0, 0.05);
  font-size: 11px;
}

.pending-num {
  width: 16px;
  height: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #222;
  border: 1px solid #444;
  font-size: 9px;
  color: $terminal-amber;
}

.pending-name {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #888;
}

.pending-price {
  color: #666;
}
</style>
