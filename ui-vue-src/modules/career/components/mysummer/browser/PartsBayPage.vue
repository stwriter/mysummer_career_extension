<template>
  <div class="partsbay-page">
    <!-- PartsBay Header (retro auction site style) -->
    <div class="site-header">
      <div class="header-top">
        <div class="logo">
          <span class="logo-parts">Parts</span><span class="logo-bay">Bay</span>
          <span class="logo-tagline">The world's online marketplace for car parts!</span>
        </div>
        <div class="header-links">
          <span class="header-link">hi, guest!</span>
          <span class="sep">|</span>
          <a class="header-link" href="#">Sign in</a>
          <span class="sep">|</span>
          <a class="header-link" href="#">My PartsBay</a>
          <span class="sep">|</span>
          <a class="header-link" href="#">Sell</a>
          <span class="sep">|</span>
          <a class="header-link" href="#">Help</a>
        </div>
      </div>
      <div class="header-nav">
        <span class="nav-item">Categories</span>
        <span class="nav-item active">Auto Parts</span>
        <span class="nav-item">Tools</span>
        <span class="nav-item">Accessories</span>
        <span class="nav-item" @click="showOrders = !showOrders" :class="{ highlight: hasOrders }">
          My Orders
          <span v-if="hasOrders" class="orders-badge">{{ totalOrderCount }}</span>
        </span>
        <span class="nav-item">Deals</span>
      </div>
    </div>

    <!-- Breadcrumb -->
    <div class="breadcrumb">
      <a href="#">Home</a> &gt;
      <a href="#">PartsBay Motors</a> &gt;
      <a href="#">Parts & Accessories</a> &gt;
      <span class="current">ETK Parts</span>
    </div>

    <!-- Search Bar -->
    <div class="search-section">
      <div class="search-box">
        <input
          type="text"
          v-model="searchQuery"
          placeholder="Search for parts..."
          class="search-input"
        />
        <button class="search-btn">Search</button>
      </div>
      <div class="search-options">
        <label>
          <input type="checkbox" checked /> Include description
        </label>
      </div>
    </div>

    <!-- Results Header -->
    <div class="results-header">
      <div class="results-info">
        <span class="results-count">{{ filteredListings.length }} results found</span>
        <span class="results-cat">in ETK Parts</span>
      </div>
      <div class="results-controls">
        <label>Sort by:</label>
        <select v-model="sortBy" class="sort-select">
          <option value="price-asc">Price + Shipping: lowest first</option>
          <option value="price-desc">Price + Shipping: highest first</option>
          <option value="distance">Distance: nearest first</option>
          <option value="time">Ending soonest</option>
        </select>
        <button class="refresh-link" @click="refreshListings">
          {{ store.loading ? 'Loading...' : 'Refresh' }}
        </button>
      </div>
    </div>

    <!-- Selection Bar -->
    <div v-if="selectedIds.length > 0" class="selection-bar">
      <span class="selection-icon">***</span>
      <span class="selection-text">{{ selectedIds.length }} item(s) selected</span>
      <span class="selection-total">Total: ${{ formatPrice(selectedTotal) }}</span>
      <button class="selection-btn" @click="acceptSelectedListings">
        Buy Selected ({{ selectedIds.length }})
      </button>
      <a class="clear-link" @click="clearSelection">Clear selection</a>
    </div>

    <!-- Main Content -->
    <div class="main-content">
      <!-- Sidebar Filters -->
      <div class="sidebar">
        <div class="filter-box">
          <h4 class="filter-title">Refine search</h4>
          <div class="filter-section">
            <h5>Condition</h5>
            <label><input type="radio" v-model="conditionFilter" value="all" /> All</label>
            <label><input type="radio" v-model="conditionFilter" value="excellent" /> Like new</label>
            <label><input type="radio" v-model="conditionFilter" value="good" /> Good</label>
            <label><input type="radio" v-model="conditionFilter" value="fair" /> Acceptable</label>
            <label><input type="radio" v-model="conditionFilter" value="poor" /> For parts</label>
          </div>
          <div class="filter-section">
            <h5>Price</h5>
            <div class="price-inputs">
              <input type="number" v-model="priceMin" placeholder="Min" class="price-input" />
              <span>to</span>
              <input type="number" v-model="priceMax" placeholder="Max" class="price-input" />
              <button class="go-btn" @click="applyPriceFilter">Go</button>
            </div>
          </div>
          <div class="filter-section">
            <h5>Location</h5>
            <label><input type="radio" v-model="distanceFilter" value="any" /> Any distance</label>
            <label><input type="radio" v-model="distanceFilter" value="10" /> Within 10 km</label>
            <label><input type="radio" v-model="distanceFilter" value="25" /> Within 25 km</label>
            <label><input type="radio" v-model="distanceFilter" value="50" /> Within 50 km</label>
          </div>
        </div>

        <div class="info-box">
          <h4>Safe Trading Tips</h4>
          <ul>
            <li>Meet in public places</li>
            <li>Check parts before paying</li>
            <li>Trust your instincts!</li>
          </ul>
        </div>
      </div>

      <!-- Listings Grid -->
      <div class="listings-area">
        <div v-if="filteredListings.length === 0" class="no-results">
          <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" class="no-results-img" />
          <h3>No items found</h3>
          <p>Try different keywords or remove some filters</p>
        </div>

        <!-- Grouped listings by category -->
        <div v-for="group in groupedListings" :key="group.id" class="category-group">
          <div class="category-header">
            <span class="category-icon">[+]</span>
            <span class="category-name">{{ group.name }}</span>
            <span class="category-count">({{ group.items.length }} items)</span>
          </div>

          <!-- Product Cards -->
          <div class="listings-grid">
            <div
              v-for="listing in group.items"
              :key="listing.id"
              class="listing-card"
              :class="{ selected: selectedIds.includes(listing.id) }"
            >
            <!-- Selection checkbox -->
            <div class="card-checkbox">
              <input
                type="checkbox"
                :checked="selectedIds.includes(listing.id)"
                @change="toggleSelection(listing.id)"
              />
            </div>

            <!-- Image -->
            <div class="card-image">
              <div class="no-photo">
                <span class="camera-icon">[CAM]</span>
                <span>No Photo</span>
              </div>
              <div class="condition-tag" :class="getConditionClass(listing.condition)">
                {{ getConditionLabel(listing.condition) }}
              </div>
            </div>

            <!-- Details -->
            <div class="card-details">
              <a class="card-title" href="#">{{ listing.partNiceName || listing.partName }}</a>

              <div class="card-meta">
                <span class="meta-seller">
                  Seller: <a href="#">local_parts_guy</a>
                  <span class="seller-rating">({{ Math.floor(Math.random() * 500) + 50 }})</span>
                  <span class="star">*</span>
                </span>
              </div>

              <div class="card-specs">
                <div class="spec-row">
                  <span class="spec-label">Mileage:</span>
                  <span class="spec-value">{{ formatMileage(listing.condition?.odometer) }}</span>
                </div>
                <div class="spec-row">
                  <span class="spec-label">Location:</span>
                  <span class="spec-value">{{ listing.location?.name || 'Unknown' }}</span>
                </div>
                <div class="spec-row">
                  <span class="spec-label">Distance:</span>
                  <span class="spec-value">{{ formatDistance(listing.distance) }} away</span>
                </div>
              </div>

              <!-- Wear bar -->
              <div class="wear-bar-wrap">
                <span class="wear-label">Wear:</span>
                <div class="wear-bar">
                  <div
                    class="wear-fill"
                    :style="{ width: getMileagePercent(listing.condition?.odometer) + '%' }"
                    :class="getMileageClass(listing.condition?.odometer)"
                  ></div>
                </div>
              </div>

              <!-- Time left -->
              <div class="time-left" :class="{ urgent: isExpiringSoon(listing) }">
                <span class="clock-icon">[T]</span>
                Time left: {{ formatTimeRemaining(listing.expiresAt) }}
              </div>
            </div>

            <!-- Price & Buy -->
            <div class="card-price-col">
              <div class="price-main">
                <span class="price-label">Price:</span>
                <span class="price-amount">${{ formatPrice(listing.price) }}</span>
              </div>
              <div class="price-shipping">+$0.00 local pickup</div>

              <button class="buy-now-btn" @click="acceptListing(listing)">
                Buy It Now
              </button>
              <button class="watch-btn">Add to Watchlist</button>
            </div>
          </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Active Pickup Banner -->
    <div v-if="activePickup && !activePickup.isIllegal" class="pickup-banner">
      <div class="banner-icon">[!]</div>
      <div class="banner-content">
        <strong>Pickup scheduled!</strong>
        <span>{{ activePickup.partNiceName || activePickup.partName }}</span>
        <span>at {{ activePickup.location?.name || 'Unknown' }}</span>
        <span>({{ formatDistance(activePickup.distance) }})</span>
      </div>
      <button class="banner-cancel" @click="cancelPickup">Cancel</button>
    </div>

    <!-- Orders Panel -->
    <div class="orders-panel" :class="{ open: showOrders }">
      <div class="orders-header">
        <h3>My Orders</h3>
        <button class="close-orders" @click="showOrders = false">X</button>
      </div>

      <div v-if="!hasOrders" class="orders-empty">
        <span class="empty-icon">[BOX]</span>
        <p>No pending orders</p>
        <p class="empty-sub">Parts you order will appear here</p>
      </div>

      <div v-else class="orders-content">
        <!-- Parts waiting at port -->
        <div v-if="pendingOrders.totalPendingCount > 0" class="order-section">
          <div class="section-header pickup">
            <span class="section-icon">[PORT]</span>
            <div class="section-info">
              <span class="section-title">Waiting at Port</span>
              <span class="section-subtitle">{{ pendingOrders.totalPendingCount }} parts ready for pickup</span>
            </div>
          </div>
          <div class="order-items">
            <div v-for="(part, idx) in pendingOrders.pendingPickup" :key="'pending-' + idx" class="order-item">
              <span class="order-item-name">{{ part.niceName || part.name }}</span>
              <span class="order-item-price">${{ formatPrice(part.price) }}</span>
              <button class="order-item-cancel" @click="cancelOrder(idx + 1)" title="Cancel & Refund">X</button>
            </div>
          </div>
          <div class="order-buttons">
            <button class="waypoint-btn" @click="setWaypointToPickup">
              [GPS] SET WAYPOINT TO PORT
            </button>
            <button class="cancel-all-btn" @click="cancelAllOrders">
              CANCEL ALL (REFUND)
            </button>
          </div>
        </div>

        <!-- Parts in cargo (being transported) -->
        <div v-if="pendingOrders.totalCarryingCount > 0" class="order-section">
          <div class="section-header carrying">
            <span class="section-icon">[TRUCK]</span>
            <div class="section-info">
              <span class="section-title">In Your Cargo</span>
              <span class="section-subtitle">{{ pendingOrders.totalCarryingCount }} parts - deliver to garage</span>
            </div>
          </div>
          <div class="order-items">
            <div v-for="(part, idx) in pendingOrders.carrying" :key="'carrying-' + idx" class="order-item">
              <span class="order-item-name">{{ part.niceName || part.name }}</span>
              <span class="order-item-price">${{ formatPrice(part.price) }}</span>
            </div>
          </div>
          <button class="waypoint-btn delivery" @click="setWaypointToDelivery">
            [GPS] SET WAYPOINT TO GARAGE
          </button>
        </div>
      </div>
    </div>

    <!-- Footer -->
    <div class="site-footer">
      <div class="footer-links">
        <a href="#">About PartsBay</a>
        <span>|</span>
        <a href="#">Announcements</a>
        <span>|</span>
        <a href="#">Community</a>
        <span>|</span>
        <a href="#">Safety Center</a>
        <span>|</span>
        <a href="#">Policies</a>
        <span>|</span>
        <a href="#">Help</a>
      </div>
      <div class="footer-copy">
        Copyright 1999-2005 PartsBay Inc. All Rights Reserved.
        <br />
        Designated trademarks and brands are the property of their respective owners.
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue"
import { useMySummerPartsStore } from "../../../stores/mysummerPartsStore"

const emit = defineEmits(["navigate"])
const store = useMySummerPartsStore()

const searchQuery = ref("")
const sortBy = ref("price-asc")
const selectedIds = ref([])
const showOrders = ref(false)

// Filter state
const conditionFilter = ref("all") // all, excellent, good, fair
const priceMin = ref("")
const priceMax = ref("")
const distanceFilter = ref("any") // any, 10, 25

// Pending orders state
const pendingOrders = ref({
  pendingPickup: [],
  carrying: [],
  totalPendingCount: 0,
  totalCarryingCount: 0,
})

const hasOrders = computed(() => pendingOrders.value.totalPendingCount > 0 || pendingOrders.value.totalCarryingCount > 0)
const totalOrderCount = computed(() => pendingOrders.value.totalPendingCount + pendingOrders.value.totalCarryingCount)

const listings = computed(() => store.marketData.listings || [])
const activePickup = computed(() => {
  const pickup = store.marketData.activePickup
  return pickup && !pickup.isIllegal ? pickup : null
})

// Category system matching Lua backend (mysummerParts.lua)
// NOTE: wheeldata = spindles, should be in suspension (same as OfficialStorePage)
const slotCategories = {
  engine: ["engine", "intake", "exhaust", "turbo", "radiator", "oilpan", "fuel", "ecu", "internals", "flywheel", "transmission", "transfer", "driveshaft", "differential", "n2o", "intercooler", "clutch", "oilcooler"],
  suspension: ["suspension", "coilover", "swaybar", "brake", "steering", "hub", "axle", "wheeldata", "strut"],
  wheels: ["wheel_f_", "wheel_r_", "tire_f_", "tire_r_", "hubcap"],
  body: ["body", "door", "hood", "trunk", "bumper", "fender", "grille", "mirror", "glass", "headlight", "taillight", "sideskirt", "spoiler", "licenseplate", "rollcage", "seat"],
  electrical: ["battery", "alternator", "light", "gauge", "switch", "wiring"],
  other: []
}

const categoryOrder = ["engine", "suspension", "wheels", "body", "electrical", "other"]

const categoryNames = {
  engine: "Engine & Drivetrain",
  suspension: "Suspension & Brakes",
  wheels: "Wheels & Tires",
  body: "Body & Interior",
  electrical: "Electrical",
  other: "Other Parts"
}

// Determine category for a slot (matches Lua getCategoryForSlot)
const getCategoryForSlot = (slotType) => {
  if (!slotType || typeof slotType !== "string") return "other"
  const slotLower = slotType.toLowerCase()

  for (const [category, keywords] of Object.entries(slotCategories)) {
    for (const keyword of keywords) {
      if (slotLower.includes(keyword)) {
        return category
      }
    }
  }
  return "other"
}

// Get category for a listing
const getListingCategory = (listing) => {
  return getCategoryForSlot(listing.slot || "")
}

const filteredListings = computed(() => {
  let result = [...listings.value]

  // Search filter
  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase()
    result = result.filter(l =>
      (l.partNiceName || l.partName || "").toLowerCase().includes(query)
    )
  }

  // Condition filter
  if (conditionFilter.value !== "all") {
    result = result.filter(l => {
      const integrity = l.condition?.integrityValue || 0
      switch (conditionFilter.value) {
        case "excellent": return integrity >= 0.9
        case "good": return integrity >= 0.7 && integrity < 0.9
        case "fair": return integrity >= 0.5 && integrity < 0.7
        case "poor": return integrity < 0.5
        default: return true
      }
    })
  }

  // Price filter
  const minPrice = parseFloat(priceMin.value) || 0
  const maxPrice = parseFloat(priceMax.value) || Infinity
  if (minPrice > 0 || maxPrice < Infinity) {
    result = result.filter(l => {
      const price = l.price || 0
      return price >= minPrice && price <= maxPrice
    })
  }

  // Distance filter
  if (distanceFilter.value !== "any") {
    const maxDist = parseInt(distanceFilter.value) * 1000 // km to m
    result = result.filter(l => (l.distance || 0) <= maxDist)
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

// Group filtered listings by category
const groupedListings = computed(() => {
  const groups = {}

  filteredListings.value.forEach(listing => {
    const category = getListingCategory(listing)
    if (!groups[category]) {
      groups[category] = {
        id: category,
        name: categoryNames[category] || category,
        items: []
      }
    }
    groups[category].items.push(listing)
  })

  // Sort groups by predefined order (matches Lua categoryOrder)
  return categoryOrder
    .filter(cat => groups[cat])
    .map(cat => groups[cat])
})

const applyPriceFilter = () => {
  // Triggers recompute by changing refs (already reactive)
}

const selectedTotal = computed(() => {
  return listings.value
    .filter(l => selectedIds.value.includes(l.id))
    .reduce((sum, l) => sum + (l.price || 0), 0)
})

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
  const result = await store.acceptMultipleListings(selectedIds.value)
  if (result && result.success !== false) {
    selectedIds.value = []
  }
}

const refreshListings = async () => {
  await store.refreshListings()
}

const acceptListing = async (listing) => {
  await store.acceptListing(listing.id)
}

const cancelPickup = async () => {
  await store.cancelPickup()
}

const formatPrice = (value) => {
  return Number(value || 0).toLocaleString("en-US", { minimumFractionDigits: 2 })
}

const formatDistance = (distance) => {
  if (!distance && distance !== 0) return "--"
  if (distance >= 1000) return `${(distance / 1000).toFixed(1)} km`
  return `${Math.round(distance)} m`
}

const formatMileage = (odometer) => {
  if (!odometer && odometer !== 0) return "-- km"
  return `${Math.round(odometer / 1000).toLocaleString("en-US")} km`
}

const getMileagePercent = (odometer) => {
  if (!odometer) return 0
  return Math.min(100, (odometer / 200000) * 100)
}

const getMileageClass = (odometer) => {
  if (!odometer) return "low"
  const percent = (odometer / 200000) * 100
  if (percent < 30) return "low"
  if (percent < 70) return "medium"
  return "high"
}

const getConditionClass = (condition) => {
  if (!condition?.integrityValue) return "unknown"
  const integrity = condition.integrityValue
  if (integrity >= 0.9) return "excellent"
  if (integrity >= 0.7) return "good"
  if (integrity >= 0.5) return "fair"
  return "poor"
}

const getConditionLabel = (condition) => {
  if (!condition?.integrityValue) return "N/A"
  const integrity = condition.integrityValue
  if (integrity >= 0.9) return "Like New"
  if (integrity >= 0.7) return "Good"
  if (integrity >= 0.5) return "Acceptable"
  return "For Parts"
}

const formatTimeRemaining = (expiresAt) => {
  if (!expiresAt) return "--"
  const now = Math.floor(Date.now() / 1000)
  const diff = expiresAt - now
  if (diff <= 0) return "Ended"
  if (diff < 60) return `${diff}s`
  if (diff < 3600) return `${Math.floor(diff / 60)}m ${diff % 60}s`
  const h = Math.floor(diff / 3600)
  const m = Math.floor((diff % 3600) / 60)
  return `${h}h ${m}m`
}

const isExpiringSoon = (listing) => {
  if (!listing.expiresAt) return false
  const now = Math.floor(Date.now() / 1000)
  return (listing.expiresAt - now) < 600
}

// Load pending orders from SpeedParts module
const loadPendingOrders = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.getPendingOrders()', (result) => {
      if (result) {
        pendingOrders.value = result
      }
    })
  }
}

const setWaypointToPickup = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.setWaypointToPickup()')
  }
}

const setWaypointToDelivery = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.setWaypointToDelivery()')
  }
}

const cancelOrder = (index) => {
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerPartShops.cancelPendingOrder(${index})`, (result) => {
      if (result && result.success) {
        loadPendingOrders()
      }
    })
  }
}

const cancelAllOrders = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.cancelAllPendingOrders()', (result) => {
      if (result && result.success) {
        loadPendingOrders()
      }
    })
  }
}

onMounted(() => {
  loadPendingOrders()
})
</script>

<style scoped lang="scss">
// PartsBay colors (retro auction site style)
$pb-blue: #0654ba;
$pb-yellow: #f5af02;
$pb-red: #e53238;
$pb-green: #86b817;
$bg-white: #ffffff;
$bg-gray: #f5f5f5;
$bg-cream: #fffef0;
$text-dark: #333333;
$text-link: #0654ba;
$border-color: #dddddd;

.partsbay-page {
  min-height: 100%;
  background: $bg-white;
  font-family: Arial, Helvetica, sans-serif;
  font-size: 12px;
  color: $text-dark;
}

// Header
.site-header {
  background: $bg-cream;
  border-bottom: 1px solid $border-color;
}

.header-top {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
}

.logo {
  display: flex;
  flex-direction: column;
}

.logo-parts {
  font-size: 24px;
  font-weight: bold;
  color: $pb-red;
  font-style: italic;
}

.logo-bay {
  font-size: 24px;
  font-weight: bold;
  color: $pb-blue;
  font-style: italic;
}

.logo-tagline {
  font-size: 9px;
  color: #666;
}

.header-links {
  display: flex;
  gap: 4px;
  font-size: 11px;
}

.header-link {
  color: $text-link;
  text-decoration: none;
  cursor: pointer;

  &:hover {
    text-decoration: underline;
  }
}

.sep {
  color: #999;
}

.header-nav {
  display: flex;
  padding: 4px 12px;
  background: linear-gradient(180deg, $pb-yellow 0%, darken($pb-yellow, 10%) 100%);
  border-top: 1px solid darken($pb-yellow, 15%);
}

.nav-item {
  padding: 4px 12px;
  cursor: pointer;
  font-weight: bold;
  font-size: 11px;

  &:hover {
    text-decoration: underline;
  }

  &.active {
    background: rgba(255, 255, 255, 0.5);
    border-radius: 2px;
  }
}

// Breadcrumb
.breadcrumb {
  padding: 6px 12px;
  font-size: 11px;
  background: $bg-gray;
  border-bottom: 1px solid $border-color;

  a {
    color: $text-link;
    text-decoration: none;

    &:hover {
      text-decoration: underline;
    }
  }

  .current {
    font-weight: bold;
  }
}

// Search
.search-section {
  padding: 10px 12px;
  background: $bg-white;
  border-bottom: 1px solid $border-color;
}

.search-box {
  display: flex;
  gap: 4px;
}

.search-input {
  flex: 1;
  padding: 6px 8px;
  border: 2px solid $pb-blue;
  font-size: 12px;
}

.search-btn {
  padding: 6px 20px;
  background: $pb-blue;
  border: none;
  color: white;
  font-weight: bold;
  cursor: pointer;

  &:hover {
    background: darken($pb-blue, 10%);
  }
}

.search-options {
  margin-top: 4px;
  font-size: 10px;

  label {
    cursor: pointer;
  }
}

// Results Header
.results-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
  background: #e8f4ff;
  border-bottom: 1px solid $border-color;
}

.results-count {
  font-weight: bold;
}

.results-cat {
  color: #666;
}

.results-controls {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 11px;
}

.sort-select {
  padding: 2px 4px;
  border: 1px solid $border-color;
  font-size: 11px;
}

.refresh-link {
  background: none;
  border: none;
  color: $text-link;
  cursor: pointer;
  text-decoration: underline;
  font-size: 11px;
}

// Selection Bar
.selection-bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  background: #ffffcc;
  border-bottom: 1px solid #cccc00;
}

.selection-icon {
  color: $pb-red;
  font-weight: bold;
}

.selection-total {
  font-weight: bold;
  color: $pb-red;
}

.selection-btn {
  margin-left: auto;
  padding: 6px 16px;
  background: $pb-green;
  border: none;
  color: white;
  font-weight: bold;
  cursor: pointer;

  &:hover {
    background: darken($pb-green, 10%);
  }
}

.clear-link {
  color: $text-link;
  cursor: pointer;
  text-decoration: underline;
  font-size: 11px;
}

// Main Content
.main-content {
  display: flex;
  min-height: 400px;
}

// Sidebar
.sidebar {
  width: 180px;
  padding: 12px;
  background: $bg-gray;
  border-right: 1px solid $border-color;
  flex-shrink: 0;
}

.filter-box {
  background: $bg-white;
  border: 1px solid $border-color;
  padding: 8px;
  margin-bottom: 12px;
}

.filter-title {
  margin: 0 0 8px;
  padding-bottom: 4px;
  border-bottom: 1px solid $border-color;
  font-size: 12px;
  color: $pb-blue;
}

.filter-section {
  margin-bottom: 10px;

  h5 {
    margin: 0 0 4px;
    font-size: 11px;
    font-weight: bold;
  }

  label {
    display: block;
    font-size: 10px;
    cursor: pointer;
    padding: 1px 0;
  }
}

.price-inputs {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
}

.price-input {
  width: 40px;
  padding: 2px 4px;
  border: 1px solid $border-color;
  font-size: 10px;
}

.go-btn {
  padding: 2px 8px;
  background: $pb-blue;
  border: none;
  color: white;
  font-size: 10px;
  cursor: pointer;
}

.info-box {
  background: #ffffee;
  border: 1px solid #cccc99;
  padding: 8px;
  font-size: 10px;

  h4 {
    margin: 0 0 6px;
    font-size: 11px;
    color: $pb-blue;
  }

  ul {
    margin: 0;
    padding-left: 16px;
  }

  li {
    margin-bottom: 2px;
  }
}

// Listings
.listings-area {
  flex: 1;
  padding: 12px;
}

// Category Groups
.category-group {
  margin-bottom: 16px;

  &:last-child {
    margin-bottom: 0;
  }
}

.category-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  background: linear-gradient(180deg, $pb-yellow 0%, darken($pb-yellow, 8%) 100%);
  border: 1px solid darken($pb-yellow, 15%);
  margin-bottom: 8px;
  cursor: pointer;

  &:hover {
    background: linear-gradient(180deg, lighten($pb-yellow, 5%) 0%, $pb-yellow 100%);
  }
}

.category-icon {
  font-family: monospace;
  font-weight: bold;
  color: $pb-blue;
}

.category-name {
  font-weight: bold;
  font-size: 13px;
  color: $text-dark;
}

.category-count {
  color: #666;
  font-size: 11px;
}

.no-results {
  text-align: center;
  padding: 40px 20px;
  color: #666;

  h3 {
    margin: 8px 0 4px;
  }

  p {
    margin: 0;
    font-size: 11px;
  }
}

.listings-grid {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

// Listing Card
.listing-card {
  display: flex;
  gap: 12px;
  padding: 10px;
  background: $bg-white;
  border: 1px solid $border-color;

  &:hover {
    background: #fafafa;
    border-color: $pb-blue;
  }

  &.selected {
    background: #fffff0;
    border-color: $pb-yellow;
    border-width: 2px;
  }
}

.card-checkbox {
  padding-top: 4px;

  input {
    width: 14px;
    height: 14px;
    cursor: pointer;
  }
}

.card-image {
  width: 100px;
  height: 100px;
  background: $bg-gray;
  border: 1px solid $border-color;
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
  flex-shrink: 0;
}

.no-photo {
  display: flex;
  flex-direction: column;
  align-items: center;
  color: #aaa;
  font-size: 10px;

  .camera-icon {
    font-size: 16px;
    margin-bottom: 2px;
  }
}

.condition-tag {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  padding: 2px 4px;
  text-align: center;
  font-size: 9px;
  font-weight: bold;

  &.excellent { background: $pb-green; color: white; }
  &.good { background: #88aa00; color: white; }
  &.fair { background: $pb-yellow; color: #333; }
  &.poor { background: $pb-red; color: white; }
  &.unknown { background: #999; color: white; }
}

.card-details {
  flex: 1;
  min-width: 0;
}

.card-title {
  display: block;
  font-size: 14px;
  font-weight: bold;
  color: $text-link;
  text-decoration: none;
  margin-bottom: 4px;

  &:hover {
    text-decoration: underline;
    color: darken($text-link, 10%);
  }
}

.card-meta {
  font-size: 10px;
  color: #666;
  margin-bottom: 6px;

  a {
    color: $text-link;
    text-decoration: none;

    &:hover {
      text-decoration: underline;
    }
  }

  .seller-rating {
    color: #666;
  }

  .star {
    color: $pb-yellow;
  }
}

.card-specs {
  margin-bottom: 6px;
}

.spec-row {
  display: flex;
  font-size: 10px;
  margin-bottom: 2px;
}

.spec-label {
  min-width: 60px;
  color: #666;
}

.spec-value {
  color: $text-dark;
}

.wear-bar-wrap {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 4px;
}

.wear-label {
  font-size: 10px;
  color: #666;
  min-width: 35px;
}

.wear-bar {
  flex: 1;
  max-width: 100px;
  height: 8px;
  background: #e0e0e0;
  border: 1px inset #ccc;
}

.wear-fill {
  height: 100%;

  &.low { background: $pb-green; }
  &.medium { background: $pb-yellow; }
  &.high { background: $pb-red; }
}

.time-left {
  font-size: 10px;
  color: #666;

  &.urgent {
    color: $pb-red;
    font-weight: bold;
    animation: pulse 1s infinite;
  }

  .clock-icon {
    font-family: monospace;
  }
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.6; }
}

.card-price-col {
  width: 130px;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
  flex-shrink: 0;
}

.price-main {
  text-align: right;
}

.price-label {
  font-size: 10px;
  color: #666;
  display: block;
}

.price-amount {
  font-size: 18px;
  font-weight: bold;
  color: $text-dark;
}

.price-shipping {
  font-size: 10px;
  color: #666;
}

.buy-now-btn {
  width: 100%;
  padding: 6px 12px;
  background: $pb-blue;
  border: none;
  color: white;
  font-weight: bold;
  font-size: 11px;
  cursor: pointer;

  &:hover {
    background: darken($pb-blue, 10%);
  }
}

.watch-btn {
  width: 100%;
  padding: 4px 12px;
  background: $bg-gray;
  border: 1px solid $border-color;
  font-size: 10px;
  cursor: pointer;

  &:hover {
    background: darken($bg-gray, 5%);
  }
}

// Pickup Banner
.pickup-banner {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  background: #fff3cd;
  border: 1px solid #ffc107;
  margin: 12px;
}

.banner-icon {
  font-weight: bold;
  color: $pb-red;
  font-size: 16px;
}

.banner-content {
  flex: 1;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  font-size: 11px;
}

.banner-cancel {
  padding: 4px 12px;
  background: $bg-gray;
  border: 1px solid $border-color;
  cursor: pointer;
  font-size: 11px;
}

// Footer
.site-footer {
  padding: 12px;
  background: $bg-gray;
  border-top: 1px solid $border-color;
  text-align: center;
  font-size: 10px;
}

.footer-links {
  margin-bottom: 8px;

  a {
    color: $text-link;
    text-decoration: none;
    margin: 0 4px;

    &:hover {
      text-decoration: underline;
    }
  }
}

.footer-copy {
  color: #666;
  font-size: 9px;
}

// My Orders nav highlight
.nav-item.highlight {
  background: $pb-blue;
  color: white;
  position: relative;
}

.orders-badge {
  background: $pb-yellow;
  color: $text-dark;
  font-size: 9px;
  font-weight: bold;
  padding: 1px 5px;
  border-radius: 8px;
  margin-left: 4px;
}

// Orders Panel
.orders-panel {
  position: fixed;
  top: 0;
  right: -320px;
  width: 320px;
  height: 100%;
  background: $bg-white;
  border-left: 2px solid $pb-blue;
  box-shadow: -4px 0 12px rgba(0, 0, 0, 0.15);
  display: flex;
  flex-direction: column;
  transition: right 0.3s ease;
  z-index: 100;

  &.open {
    right: 0;
  }
}

.orders-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px;
  background: $pb-blue;
  color: white;

  h3 {
    margin: 0;
    font-size: 12px;
  }
}

.close-orders {
  background: none;
  border: none;
  color: white;
  font-size: 14px;
  cursor: pointer;
  font-weight: bold;

  &:hover {
    color: $pb-yellow;
  }
}

.orders-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 20px;
  text-align: center;
  color: #666;

  .empty-icon {
    font-size: 24px;
    margin-bottom: 8px;
  }

  .empty-sub {
    font-size: 10px;
    color: #999;
  }
}

.orders-content {
  flex: 1;
  overflow-y: auto;
  padding: 10px;
}

.order-section {
  background: $bg-gray;
  border: 1px solid $border-color;
  margin-bottom: 12px;
  border-radius: 4px;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px;
  border-bottom: 1px solid $border-color;

  &.pickup {
    background: #fff8e1;
    border-color: $pb-yellow;
  }

  &.carrying {
    background: #e3f2fd;
    border-color: $pb-blue;
  }
}

.section-icon {
  font-size: 16px;
  color: $pb-blue;
}

.section-info {
  display: flex;
  flex-direction: column;
}

.section-title {
  font-weight: bold;
  font-size: 11px;
  color: $pb-blue;
}

.section-subtitle {
  font-size: 10px;
  color: #666;
}

.order-items {
  padding: 8px;
  max-height: 150px;
  overflow-y: auto;
}

.order-item {
  display: flex;
  justify-content: space-between;
  padding: 4px 6px;
  font-size: 10px;
  border-bottom: 1px dashed #ddd;

  &:last-child {
    border-bottom: none;
  }
}

.order-item-name {
  flex: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-right: 8px;
}

.order-item-price {
  color: $pb-red;
  font-weight: bold;
}

.order-item-cancel {
  background: $pb-red;
  color: white;
  border: none;
  width: 16px;
  height: 16px;
  font-size: 10px;
  font-weight: bold;
  cursor: pointer;
  margin-left: 4px;
  border-radius: 2px;

  &:hover {
    background: darken($pb-red, 10%);
  }
}

.order-buttons {
  display: flex;
  gap: 4px;
}

.cancel-all-btn {
  flex: 1;
  padding: 8px;
  background: $pb-red;
  border: none;
  color: white;
  font-weight: bold;
  font-size: 9px;
  cursor: pointer;
  border-radius: 0 0 3px 0;

  &:hover {
    background: darken($pb-red, 10%);
  }
}

.waypoint-btn {
  flex: 1;
  padding: 8px;
  background: $pb-yellow;
  border: none;
  color: $text-dark;
  font-weight: bold;
  font-size: 10px;
  cursor: pointer;
  border-radius: 0 0 3px 3px;

  &:hover {
    background: darken($pb-yellow, 10%);
  }

  &.delivery {
    background: $pb-green;
    color: white;

    &:hover {
      background: darken($pb-green, 10%);
    }
  }
}
</style>
