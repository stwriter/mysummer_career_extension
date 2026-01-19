<template>
  <div class="project-parts-root">
    <div class="project-parts-header">
      <div>
        <h2>Project Vehicle - Part Installation</h2>
        <p>Install parts from your inventory. Wheels and tires can be purchased.</p>
      </div>
    </div>

    <div v-if="loading" class="loading-state">
      <p>Loading parts data...</p>
    </div>

    <div v-else-if="error" class="error-state">
      <p>{{ error }}</p>
    </div>

    <template v-else>
      <!-- Search -->
      <div class="search-section">
        <input
          v-model="searchQuery"
          type="text"
          placeholder="Search parts..."
          class="search-input"
        />
      </div>

      <!-- Categories -->
      <div class="categories-container">
        <div
          v-for="category in filteredCategories"
          :key="category.id"
          class="category-section"
        >
          <div
            class="category-header"
            @click="toggleCategory(category.id)"
          >
            <span class="category-name">{{ category.name }}</span>
            <span class="category-count">
              {{ getCategoryPartCount(category) }} parts
            </span>
            <span class="category-toggle">
              {{ expandedCategories[category.id] ? '▼' : '▶' }}
            </span>
          </div>

          <div v-if="expandedCategories[category.id]" class="category-parts">
            <!-- Inventory Parts (FREE) -->
            <template v-if="category.inventoryParts && category.inventoryParts.length > 0">
              <div class="parts-subsection">
                <div class="subsection-header">From Inventory (Free)</div>
                <div
                  v-for="part in filterParts(category.inventoryParts)"
                  :key="'inv-' + part.id"
                  class="part-card inventory"
                >
                  <div class="part-info">
                    <div class="part-name">{{ part.niceName || part.name }}</div>
                    <div class="part-meta">
                      <span class="part-slot">{{ part.slotNiceName || part.slotType }}</span>
                      <span v-if="part.condition" class="part-condition">
                        {{ formatCondition(part.condition) }}
                      </span>
                    </div>
                  </div>
                  <div class="part-actions">
                    <span class="part-price free">FREE</span>
                    <button
                      class="action-btn install"
                      @click="installPart(part)"
                      :disabled="installing"
                    >
                      Install
                    </button>
                  </div>
                </div>
              </div>
            </template>

            <!-- Shop Parts (only for wheels) - Grouped by size -->
            <template v-if="category.shopParts && category.shopParts.length > 0">
              <div class="parts-subsection">
                <div class="subsection-header">Available for Purchase (by size)</div>

                <!-- Group parts by size for wheels category -->
                <template v-if="category.id === 'wheels'">
                  <div
                    v-for="sizeGroup in groupPartsBySize(filterParts(category.shopParts)).groupOrder"
                    :key="'size-' + sizeGroup"
                    class="size-group"
                  >
                    <div class="size-group-header">{{ sizeGroup }}</div>
                    <div
                      v-for="(part, index) in groupPartsBySize(filterParts(category.shopParts)).groups[sizeGroup]"
                      :key="'shop-' + part.name + '-' + index"
                      class="part-card shop"
                    >
                      <div class="part-info">
                        <div class="part-name">{{ part.niceName || part.name }}</div>
                        <div class="part-meta">
                          <span class="part-slot">{{ part.slotNiceName || part.slotType }}</span>
                        </div>
                      </div>
                      <div class="part-actions">
                        <span class="part-price">$ {{ formatPrice(part.value) }}</span>
                        <button
                          class="action-btn buy"
                          @click="purchasePart(part)"
                          :disabled="installing"
                        >
                          Buy & Install
                        </button>
                      </div>
                    </div>
                  </div>
                </template>

                <!-- Non-wheel shop parts (unlikely but handle just in case) -->
                <template v-else>
                  <div
                    v-for="(part, index) in filterParts(category.shopParts)"
                    :key="'shop-' + part.name + '-' + index"
                    class="part-card shop"
                  >
                    <div class="part-info">
                      <div class="part-name">{{ part.niceName || part.name }}</div>
                      <div class="part-meta">
                        <span class="part-slot">{{ part.slotNiceName || part.slotType }}</span>
                      </div>
                    </div>
                    <div class="part-actions">
                      <span class="part-price">$ {{ formatPrice(part.value) }}</span>
                      <button
                        class="action-btn buy"
                        @click="purchasePart(part)"
                        :disabled="installing"
                      >
                        Buy & Install
                      </button>
                    </div>
                  </div>
                </template>
              </div>
            </template>

            <!-- Empty category message -->
            <div
              v-if="getCategoryPartCount(category) === 0"
              class="empty-category"
            >
              <p>No parts available in this category</p>
            </div>
          </div>
        </div>

        <!-- No results message -->
        <div v-if="filteredCategories.length === 0" class="no-results">
          <p v-if="searchQuery">No parts match "{{ searchQuery }}"</p>
          <p v-else>No parts available. Collect parts from Parts Market leads!</p>
        </div>
      </div>
    </template>

    <!-- Toast Message -->
    <div v-if="message" class="toast-message" :class="messageType">
      {{ message }}
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, reactive } from 'vue'
import { useBridge } from '@/bridge'

const { events, api } = useBridge()

// Helper to run raw Lua code (bypasses JS bridge cache)
const runLua = (code) => {
  return new Promise((resolve) => {
    api.engineLua(code, resolve)
  })
}

// State
const loading = ref(true)
const error = ref(null)
const installing = ref(false)
const searchQuery = ref('')
const message = ref('')
const messageType = ref('info')
const categories = ref([])
const expandedCategories = reactive({})

// Computed
const filteredCategories = computed(() => {
  if (!searchQuery.value) return categories.value

  const query = searchQuery.value.toLowerCase()
  return categories.value.filter(cat => {
    const invMatches = (cat.inventoryParts || []).some(p => matchesPart(p, query))
    const shopMatches = (cat.shopParts || []).some(p => matchesPart(p, query))
    return invMatches || shopMatches
  })
})

// Helper functions
const matchesPart = (part, query) => {
  const name = (part.niceName || part.name || '').toLowerCase()
  const slot = (part.slotNiceName || part.slotType || '').toLowerCase()
  return name.includes(query) || slot.includes(query)
}

const filterParts = (parts) => {
  if (!parts || !Array.isArray(parts)) return []
  if (!searchQuery.value) return parts
  const query = searchQuery.value.toLowerCase()
  return parts.filter(p => matchesPart(p, query))
}

const getCategoryPartCount = (category) => {
  const invCount = filterParts(category.inventoryParts || []).length
  const shopCount = filterParts(category.shopParts || []).length
  return invCount + shopCount
}

const toggleCategory = (categoryId) => {
  expandedCategories[categoryId] = !expandedCategories[categoryId]
}

// Wheel/Tire size grouping patterns
const rgxWheel = /^(\d+(?:\.\d+)?)(x)(\d+(?:\.\d+)?)/i
const rgxTire = /^(\d+(?:\.\d+)?)(\/)(\d+(?:\.\d+)?)(R)(\d+(?:\.\d+)?)/i

// Extract size group from part name (e.g., "4x12" or "200/60R15")
const getSizeGroup = (partName) => {
  const name = partName || ''
  const wheelMatch = name.match(rgxWheel)
  if (wheelMatch) {
    return wheelMatch.slice(1, 4).join('')
  }
  const tireMatch = name.match(rgxTire)
  if (tireMatch) {
    return tireMatch.slice(1, 6).join('')
  }
  return null
}

// Group parts by size (for wheels/tires)
const groupPartsBySize = (parts) => {
  const groups = {}
  const groupOrder = []

  if (!parts || !Array.isArray(parts) || parts.length === 0) {
    return { groups, groupOrder }
  }

  for (const part of parts) {
    const size = getSizeGroup(part.niceName || part.name) || 'Other'
    if (!groups[size]) {
      groups[size] = []
      groupOrder.push(size)
    }
    groups[size].push(part)
  }

  // Sort groups by size (numerical sort)
  groupOrder.sort((a, b) => {
    // Extract first number for sorting
    const numA = parseFloat(a) || 999
    const numB = parseFloat(b) || 999
    return numA - numB
  })

  return { groups, groupOrder }
}

// Formatters
const formatPrice = (value) => {
  if (!value) return '0.00'
  return Number(value).toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })
}

const formatCondition = (condition) => {
  if (!condition) return ''
  const integrity = Math.round((condition.integrityValue || 1) * 100)
  return `${integrity}%`
}

// Toast
const showMessage = (text, type = 'info') => {
  message.value = text
  messageType.value = type
  setTimeout(() => { message.value = '' }, 4000)
}

// Handle data from Lua event
const handlePartsData = (data) => {
  if (!data || !data.success) {
    error.value = (data && data.error) || 'Failed to load parts data'
    loading.value = false
    return
  }

  categories.value = data.categories || []

  // Expand first category by default
  if (categories.value.length > 0) {
    expandedCategories[categories.value[0].id] = true
  }

  loading.value = false
}

// Install part from inventory (uses runLua to bypass JS bridge cache)
const installPart = async (part) => {
  installing.value = true
  showMessage(`Installing ${part.niceName || part.name}...`, 'info')

  try {
    const result = await runLua(`career_modules_mysummerParts.installProjectPart(${part.id})`)

    if (result && result.success) {
      showMessage(result.message || 'Part installed!', 'success')
    } else {
      showMessage(result?.error || 'Failed to install part', 'error')
    }
  } catch (e) {
    console.error('Error installing part:', e)
    showMessage('Error installing part', 'error')
  }

  installing.value = false
}

// Purchase and install wheel/tire (uses runLua to bypass JS bridge cache)
const purchasePart = async (part) => {
  installing.value = true
  showMessage(`Purchasing ${part.niceName || part.name}...`, 'info')

  try {
    // Escape strings properly for Lua
    const partName = part.name.replace(/"/g, '\\"')
    const slotType = part.slotType.replace(/"/g, '\\"')
    const result = await runLua(`career_modules_mysummerParts.purchaseProjectWheelTire("${partName}", "${slotType}", ${part.value})`)

    if (result && result.success) {
      showMessage(result.message || 'Purchased and installed!', 'success')
    } else {
      showMessage(result?.error || 'Failed to purchase', 'error')
    }
  } catch (e) {
    console.error('Error purchasing part:', e)
    showMessage('Error purchasing part', 'error')
  }

  installing.value = false
}

onMounted(() => {
  events.on('projectPartsDataUpdated', handlePartsData)

  setTimeout(() => {
    if (loading.value) {
      error.value = 'Timeout waiting for parts data'
      loading.value = false
    }
  }, 3000)
})

onUnmounted(() => {
  events.off('projectPartsDataUpdated', handlePartsData)
})
</script>

<style scoped lang="scss">
.project-parts-root {
  padding: 1rem;
  color: white;
  font-family: inherit;
  position: relative;
  background: rgba(16, 16, 16, 0.95);
  min-height: 500px;
  max-height: 80vh;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.project-parts-header {
  margin-bottom: 1rem;
  flex-shrink: 0;

  h2 {
    margin: 0 0 0.25rem 0;
    font-size: 1.3rem;
    color: #f0f0f0;
  }

  p {
    margin: 0;
    opacity: 0.7;
    font-size: 0.85rem;
  }
}

.loading-state,
.error-state,
.no-results,
.empty-category {
  padding: 2rem;
  text-align: center;

  p {
    margin: 0;
    opacity: 0.7;
  }
}

.error-state p {
  color: #ff6b6b;
}

.search-section {
  margin-bottom: 1rem;
  flex-shrink: 0;

  .search-input {
    width: 100%;
    padding: 0.6rem 1rem;
    background: rgba(0, 0, 0, 0.4);
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 4px;
    color: white;
    font-size: 0.9rem;

    &::placeholder {
      color: rgba(255, 255, 255, 0.5);
    }

    &:focus {
      outline: none;
      border-color: rgba(100, 180, 255, 0.5);
    }
  }
}

.categories-container {
  flex: 1;
  overflow-y: auto;
  padding-right: 0.5rem;
}

.category-section {
  margin-bottom: 0.5rem;
  background: rgba(255, 255, 255, 0.03);
  border-radius: 4px;
  overflow: hidden;
}

.category-header {
  display: flex;
  align-items: center;
  padding: 0.75rem 1rem;
  background: rgba(255, 255, 255, 0.08);
  cursor: pointer;
  transition: background 0.2s;

  &:hover {
    background: rgba(255, 255, 255, 0.12);
  }

  .category-name {
    flex: 1;
    font-weight: 500;
    font-size: 1rem;
  }

  .category-count {
    font-size: 0.8rem;
    opacity: 0.6;
    margin-right: 0.75rem;
  }

  .category-toggle {
    font-size: 0.7rem;
    opacity: 0.5;
  }
}

.category-parts {
  padding: 0.5rem;
}

.parts-subsection {
  margin-bottom: 0.75rem;

  &:last-child {
    margin-bottom: 0;
  }
}

.subsection-header {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.5;
  margin-bottom: 0.5rem;
  padding-left: 0.5rem;
}

.size-group {
  margin-bottom: 0.75rem;

  &:last-child {
    margin-bottom: 0;
  }
}

.size-group-header {
  font-size: 0.8rem;
  font-weight: 600;
  color: #fbbf24;
  padding: 0.4rem 0.5rem;
  background: rgba(251, 191, 36, 0.1);
  border-radius: 3px;
  margin-bottom: 0.35rem;
  border-left: 2px solid #fbbf24;
}

.part-card {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.6rem 0.75rem;
  background: rgba(0, 0, 0, 0.3);
  border-radius: 4px;
  margin-bottom: 0.35rem;
  border-left: 3px solid transparent;

  &.inventory {
    border-left-color: #4ade80;
  }

  &.shop {
    border-left-color: #fbbf24;
  }
}

.part-info {
  flex: 1;
  min-width: 0;

  .part-name {
    font-size: 0.9rem;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .part-meta {
    display: flex;
    gap: 0.5rem;
    font-size: 0.75rem;
    opacity: 0.6;
    margin-top: 0.15rem;
  }
}

.part-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-left: 0.5rem;
}

.part-price {
  font-weight: 600;
  font-size: 0.85rem;
  min-width: 50px;
  text-align: right;

  &.free {
    color: #4ade80;
  }
}

.action-btn {
  padding: 0.35rem 0.7rem;
  border: none;
  border-radius: 3px;
  font-size: 0.75rem;
  cursor: pointer;
  transition: all 0.2s;
  white-space: nowrap;

  &.install {
    background: rgba(74, 222, 128, 0.2);
    color: #4ade80;
    border: 1px solid rgba(74, 222, 128, 0.3);

    &:hover:not(:disabled) {
      background: rgba(74, 222, 128, 0.35);
    }
  }

  &.buy {
    background: rgba(251, 191, 36, 0.2);
    color: #fbbf24;
    border: 1px solid rgba(251, 191, 36, 0.3);

    &:hover:not(:disabled) {
      background: rgba(251, 191, 36, 0.35);
    }
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.toast-message {
  position: fixed;
  bottom: 1.5rem;
  left: 50%;
  transform: translateX(-50%);
  padding: 0.75rem 1.5rem;
  background: rgba(0, 0, 0, 0.9);
  color: white;
  border-radius: 4px;
  z-index: 100;
  font-size: 0.9rem;

  &.warning {
    background: rgba(251, 191, 36, 0.9);
    color: #1a1a1a;
  }

  &.error {
    background: rgba(239, 68, 68, 0.9);
  }

  &.success {
    background: rgba(74, 222, 128, 0.9);
    color: #1a1a1a;
  }
}
</style>
