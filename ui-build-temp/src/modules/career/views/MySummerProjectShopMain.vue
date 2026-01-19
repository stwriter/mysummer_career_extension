<template>
  <ComputerWrapper title="Project Parts Shop" :path="['Garage', 'Project Parts']" back @back="close">
    <div class="shop-wrapper">
      <!-- Header -->
      <div class="shop-header">
        <h2>Install Parts - Project Vehicle</h2>
        <div class="money-box">
          <span class="label">Available:</span>
          <span class="amount">${{ formatNum(playerMoney) }}</span>
        </div>
      </div>

      <!-- Main layout -->
      <div class="shop-main">
        <!-- Left: Slots Tree -->
        <div class="slots-side">
          <input v-model="search" placeholder="Search parts..." class="search-input" />

          <div class="slots-list">
            <!-- Loading state -->
            <div v-if="rootNodes.length === 0" class="loading-state">
              Loading parts... ({{ slots.length }} raw slots)
            </div>

            <!-- Render hierarchical tree -->
            <template v-for="node in rootNodes" :key="node.path">
              <SlotNode
                :node="node"
                :expanded="expanded"
                :cart-ids="cartIds"
                :search="search"
                :depth="0"
                @toggle="toggle"
                @add="addToCart"
                @remove="removeFromCart"
                @uninstall="uninstallPart"
              />
            </template>
          </div>
        </div>

        <!-- Right: Cart -->
        <div class="cart-side">
          <h3>Cart ({{ cartItems.length }})</h3>

          <div class="cart-items">
            <div v-if="cartItems.length === 0" class="cart-empty">Select parts to install</div>
            <div v-for="item in cartItems" :key="item.id" class="cart-row">
              <span class="cart-name">{{ item.niceName }}</span>
              <span class="cart-price">{{ item.price === 0 ? 'FREE' : '$' + formatNum(item.price) }}</span>
              <button class="btn-x" @click="removeFromCart(item.id)">×</button>
            </div>
          </div>

          <div class="cart-totals">
            <div class="row"><span>Subtotal:</span><span>${{ formatNum(cart.subtotal) }}</span></div>
            <div class="row"><span>Tax (7%):</span><span>${{ formatNum(cart.taxes) }}</span></div>
            <div class="row total"><span>Total:</span><span>${{ formatNum(cart.total) }}</span></div>
          </div>

          <button class="btn-checkout" :disabled="cartItems.length === 0 || cart.total > playerMoney" @click="checkout">
            Confirm Purchase
          </button>
        </div>
      </div>
    </div>
  </ComputerWrapper>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, h, defineComponent } from "vue"
import { useBridge } from "@/bridge"
import ComputerWrapper from "./ComputerWrapper.vue"

const { events } = useBridge()

// Recursive SlotNode component
const SlotNode = defineComponent({
  name: 'SlotNode',
  props: ['node', 'expanded', 'cartIds', 'search', 'depth'],
  emits: ['toggle', 'add', 'remove', 'uninstall'],
  setup(props, { emit }) {
    const toArray = (v) => Array.isArray(v) ? v : []
    const formatNum = (n) => (parseFloat(n) || 0).toFixed(2)

    const isExpanded = computed(() => props.expanded[props.node.path])
    const hasParts = computed(() => toArray(props.node.parts).length > 0)
    const hasChildren = computed(() => toArray(props.node.children).length > 0)
    const hasContent = computed(() => hasParts.value || hasChildren.value)

    // Filter by search
    const matchesSearch = computed(() => {
      if (!props.search) return true
      const q = props.search.toLowerCase()
      if (props.node.niceName?.toLowerCase().includes(q)) return true
      if (props.node.installedPartNiceName?.toLowerCase().includes(q)) return true
      return toArray(props.node.parts).some(p =>
        p.niceName?.toLowerCase().includes(q) || p.name?.toLowerCase().includes(q)
      )
    })

    const childMatchesSearch = computed(() => {
      if (!props.search) return true
      return toArray(props.node.children).some(child => {
        const q = props.search.toLowerCase()
        if (child.niceName?.toLowerCase().includes(q)) return true
        return toArray(child.parts).some(p =>
          p.niceName?.toLowerCase().includes(q) || p.name?.toLowerCase().includes(q)
        )
      })
    })

    const visible = computed(() => matchesSearch.value || childMatchesSearch.value)

    return () => {
      if (!visible.value) return null

      const indent = { marginLeft: `${props.depth * 1}rem` }
      const elements = []

      // Slot header
      if (hasContent.value) {
        const slotDisplayName = props.node.niceName || props.node.slotName || ''
        const installedName = props.node.installedPartNiceName || ''
        // Only show installed badge if meaningfully different from slot name
        const showBadge = installedName &&
          installedName.toLowerCase().trim() !== slotDisplayName.toLowerCase().trim()

        const headerChildren = [
          h('span', { class: 'arrow' }, isExpanded.value ? '▼' : '▶'),
          h('span', { class: 'slot-name' }, slotDisplayName)
        ]
        if (showBadge) {
          headerChildren.push(h('span', { class: 'installed-badge' }, '→ ' + installedName))
        }

        elements.push(
          h('div', {
            class: ['slot-header', { 'has-parts': hasParts.value }],
            style: indent,
            onClick: () => emit('toggle', props.node.path)
          }, headerChildren)
        )
      }

      // Parts list (when expanded)
      if (isExpanded.value && hasParts.value) {
        const partElements = toArray(props.node.parts).map(part =>
          h('div', {
            key: part.id,
            class: ['part-row', {
              installed: part.installed,
              owned: part.source === 'inventory',
              incart: props.cartIds.has(part.id)
            }],
            style: { marginLeft: `${(props.depth + 1) * 1}rem` }
          }, [
            h('div', { class: 'part-info' }, [
              h('div', { class: 'part-name' }, [
                h('span', { class: 'part-label' }, part.niceName || part.name),
                part.installed ? h('span', { class: 'tag installed-tag' }, 'INSTALLED') : null,
                !part.installed && part.source === 'inventory' ? h('span', { class: 'tag owned-tag' }, 'OWNED') : null
              ].filter(Boolean)),
              h('span', { class: ['part-price', { free: part.price === 0 }] },
                part.price === 0 ? 'FREE' : '$' + formatNum(part.price)
              )
            ]),
            !part.installed && !props.cartIds.has(part.id) ? h('button', {
              class: 'btn-add',
              onClick: (e) => { e.stopPropagation(); emit('add', part.id) }
            }, '+') : null,
            props.cartIds.has(part.id) ? h('button', {
              class: 'btn-remove',
              onClick: (e) => { e.stopPropagation(); emit('remove', part.id) }
            }, '−') : null,
            part.installed ? h('button', {
              class: 'btn-uninstall',
              onClick: (e) => { e.stopPropagation(); emit('uninstall', props.node.path) }
            }, '✕') : null
          ].filter(Boolean))
        )
        elements.push(h('div', { class: 'parts-list' }, partElements))
      }

      // Children (recursive)
      if (isExpanded.value && hasChildren.value) {
        const childElements = toArray(props.node.children).map(child =>
          h(SlotNode, {
            key: child.path,
            node: child,
            expanded: props.expanded,
            cartIds: props.cartIds,
            search: props.search,
            depth: props.depth + 1,
            onToggle: (path) => emit('toggle', path),
            onAdd: (id) => emit('add', id),
            onRemove: (id) => emit('remove', id),
            onUninstall: (path) => emit('uninstall', path)
          })
        )
        elements.push(...childElements)
      }

      return h('div', { class: 'slot-item' }, elements)
    }
  }
})

// State
const slots = ref([])
const cart = ref({ items: [], subtotal: 0, taxes: 0, total: 0 })
const playerMoney = ref(0)
const expanded = ref({})
const search = ref("")

// Helpers
const toArray = (v) => Array.isArray(v) ? v : []
const formatNum = (n) => (parseFloat(n) || 0).toFixed(2)

// Build tree structure from flat slots array
const buildTree = (flatSlots) => {
  const slotMap = {}
  const roots = []

  // Create map by path
  flatSlots.forEach(slot => {
    slotMap[slot.path] = { ...slot, children: [] }
  })

  // Build parent-child relationships based on path
  flatSlots.forEach(slot => {
    const node = slotMap[slot.path]
    // Find parent by checking path segments
    const pathParts = slot.path.split('/').filter(p => p)
    if (pathParts.length > 1) {
      // Try to find parent slot
      const parentPath = '/' + pathParts.slice(0, -1).join('/') + '/'
      if (slotMap[parentPath]) {
        slotMap[parentPath].children.push(node)
        return
      }
    }
    // No parent found, this is a root
    roots.push(node)
  })

  // Sort children by name
  const sortChildren = (node) => {
    if (node.children && node.children.length > 0) {
      node.children.sort((a, b) => (a.niceName || '').localeCompare(b.niceName || ''))
      node.children.forEach(sortChildren)
    }
  }
  roots.forEach(sortChildren)
  roots.sort((a, b) => (a.niceName || '').localeCompare(b.niceName || ''))

  return roots
}

// Computed
const rootNodes = computed(() => buildTree(toArray(slots.value)))
const cartItems = computed(() => toArray(cart.value.items))
const cartIds = computed(() => new Set(cartItems.value.map(i => i.id)))

// Actions
const toggle = (path) => { expanded.value[path] = !expanded.value[path] }

const addToCart = (id) => {
  console.log("[ProjectShop] addToCart called with id:", id)
  if (window.bngApi) {
    const escaped = id.replace(/"/g, '\\"')
    window.bngApi.engineLua(`career_modules_mysummerProjectPartShop.addToCart("${escaped}")`)
  }
}


const uninstallPart = (slotPath) => {
  console.log("[ProjectShop] uninstallPart called for slot:", slotPath)
  if (window.bngApi) {
    const escaped = slotPath.replace(/"/g, '\\"')
    window.bngApi.engineLua('career_modules_mysummerProjectPartShop.addUninstallToCart("' + escaped + '")')
  }
}

const removeFromCart = (id) => {
  console.log("[ProjectShop] removeFromCart called with id:", id)
  if (window.bngApi) {
    const escaped = id.replace(/"/g, '\\"')
    console.log("[ProjectShop] Calling Lua removeFromCart with:", escaped)
    window.bngApi.engineLua(`career_modules_mysummerProjectPartShop.removeFromCart("${escaped}")`)
  }
}

const checkout = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerProjectPartShop.checkout()')
  }
}

const close = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerProjectPartShop.cancelShop()')
  }
}

// Event handler
const onData = (data) => {
  console.log("[ProjectShop] Received data:", data)
  const cats = data.categories
  if (cats && typeof cats === 'object') {
    slots.value = Object.values(cats)
  } else {
    slots.value = toArray(cats)
  }
  cart.value = {
    items: toArray(data.cart?.items),
    subtotal: data.cart?.subtotal || 0,
    taxes: data.cart?.taxes || 0,
    total: data.cart?.total || 0,
  }
  playerMoney.value = data.playerMoney || 0
  console.log("[ProjectShop] Built tree from", slots.value.length, "slots")
}

onMounted(() => {
  console.log("[ProjectShop] Component MOUNTED")
  events.on("mysummerProjectShopData", onData)

  const requestDataFromLua = () => {
    if (window.bngApi) {
      console.log("[ProjectShop] Requesting data from Lua...")
      window.bngApi.engineLua('career_modules_mysummerProjectPartShop.requestData()')
    }
  }

  // Initial request
  requestDataFromLua()

  // Retry if no data after 1 second
  setTimeout(() => {
    if (slots.value.length === 0) {
      console.log("[ProjectShop] No data after 1s, retrying...")
      requestDataFromLua()
    }
  }, 1000)

  // Final retry at 2 seconds
  setTimeout(() => {
    if (slots.value.length === 0) {
      console.log("[ProjectShop] No data after 2s, final retry...")
      requestDataFromLua()
    }
  }, 2000)
})

onUnmounted(() => {
  events.off("mysummerProjectShopData", onData)
})
</script>

<style scoped>
.shop-wrapper {
  display: flex;
  flex-direction: column;
  height: 100%;
  color: #fff;
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
}
.shop-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem;
  border-bottom: 1px solid rgba(255,255,255,0.2);
  background: rgba(0,0,0,0.2);
}
.shop-header h2 { margin: 0; font-size: 1.25rem; }
.money-box .label { color: #aaa; margin-right: 0.5rem; }
.money-box .amount { color: #4ade80; font-weight: bold; font-size: 1.2rem; }

.shop-main { display: flex; flex: 1; overflow: hidden; }

.slots-side {
  flex: 2;
  display: flex;
  flex-direction: column;
  border-right: 1px solid rgba(255,255,255,0.2);
  background: rgba(0,0,0,0.1);
}
.search-input {
  margin: 0.5rem;
  padding: 0.5rem;
  background: rgba(0,0,0,0.3);
  border: 1px solid rgba(255,255,255,0.3);
  border-radius: 4px;
  color: #fff;
}
.slots-list { flex: 1; overflow-y: auto; padding: 0.5rem; }

/* Use :deep() for elements created with h() inside SlotNode */
/* All styles below use :deep() because SlotNode uses h() render functions */
.slots-list :deep(.slot-item) { margin-bottom: 2px; }
.slots-list :deep(.slot-header) {
  display: flex;
  align-items: center;
  padding: 0.4rem 0.5rem;
  background: rgba(59,130,246,0.15);
  border-radius: 4px;
  cursor: pointer;
  gap: 0.5rem;
  transition: background 0.15s;
}
.slots-list :deep(.slot-header:hover) { background: rgba(59,130,246,0.25); }
.slots-list :deep(.slot-header.has-parts) { background: rgba(59,130,246,0.2); }
.slots-list :deep(.slot-header.has-parts:hover) { background: rgba(59,130,246,0.3); }
.slots-list :deep(.arrow) { width: 1rem; font-size: 0.65rem; flex-shrink: 0; color: #888; }
.slots-list :deep(.slot-name) { flex: 1; font-weight: 500; font-size: 0.9rem; }
.slots-list :deep(.installed-badge) {
  font-size: 0.7rem;
  color: #a3e635;
  background: rgba(163,230,53,0.15);
  padding: 0.1rem 0.35rem;
  border-radius: 3px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 150px;
}

.slots-list :deep(.parts-list) { margin: 0.25rem 0; padding-left: 1rem; }
.slots-list :deep(.part-row) {
  display: flex;
  align-items: center;
  padding: 0.35rem 0.5rem;
  margin: 1px 0;
  background: rgba(0,0,0,0.2);
  border-radius: 4px;
}
.slots-list :deep(.part-row.installed) { background: rgba(163,230,53,0.15); border-left: 3px solid #a3e635; }
.slots-list :deep(.part-row.owned) { border-left: 3px solid #4ade80; }
.slots-list :deep(.part-row.incart) { background: rgba(59,130,246,0.3); }
.slots-list :deep(.part-info) { flex: 1; min-width: 0; }
.slots-list :deep(.part-name) { display: flex; align-items: center; gap: 0.4rem; font-size: 0.85rem; white-space: nowrap; overflow: hidden; }
.slots-list :deep(.part-label) { overflow: hidden; text-overflow: ellipsis; }
.slots-list :deep(.tag) { font-size: 0.6rem; padding: 0.1rem 0.25rem; border-radius: 2px; flex-shrink: 0; margin-left: 0.3rem; }
.slots-list :deep(.installed-tag) { background: #a3e635; color: #000; }
.slots-list :deep(.owned-tag) { background: #4ade80; color: #000; }
.slots-list :deep(.part-price) { font-size: 0.75rem; color: #fbbf24; display: block; }
.slots-list :deep(.part-price.free) { color: #4ade80; }
.slots-list :deep(.btn-add),
.slots-list :deep(.btn-remove) {
  width: 26px;
  height: 26px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1.1rem;
  flex-shrink: 0;
  margin-left: 0.5rem;
}
.slots-list :deep(.btn-add) { background: #3b82f6; color: #fff; }
.slots-list :deep(.btn-add:hover) { background: #2563eb; }
.slots-list :deep(.btn-remove) { background: #ef4444; color: #fff; }
.slots-list :deep(.btn-remove:hover) { background: #dc2626; }

.slots-list :deep(.btn-uninstall) {
  width: 26px;
  height: 26px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1.1rem;
  flex-shrink: 0;
  margin-left: 0.5rem;
  background: #dc2626;
  color: #fff;
}
.slots-list :deep(.btn-uninstall:hover) { background: #b91c1c; }

.cart-side {
  flex: 1;
  display: flex;
  flex-direction: column;
  padding: 1rem;
  min-width: 200px;
  background: rgba(0,0,0,0.2);
}
.cart-side h3 {
  margin: 0 0 0.5rem 0;
  border-bottom: 1px solid rgba(255,255,255,0.2);
  padding-bottom: 0.5rem;
  font-size: 1rem;
}
.cart-items { flex: 1; overflow-y: auto; }
.cart-empty { color: #666; text-align: center; padding: 2rem; font-size: 0.85rem; }
.cart-row {
  display: flex;
  align-items: center;
  padding: 0.35rem;
  margin-bottom: 2px;
  background: rgba(255,255,255,0.05);
  border-radius: 4px;
}
.cart-name { flex: 1; font-size: 0.8rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cart-price { color: #fbbf24; font-size: 0.8rem; margin-right: 0.5rem; }
.btn-x { background: none; border: none; color: #ef4444; font-size: 1.1rem; cursor: pointer; padding: 0 0.25rem; }

.cart-totals { border-top: 1px solid rgba(255,255,255,0.2); padding: 0.75rem 0; margin-top: 0.5rem; }
.cart-totals .row { display: flex; justify-content: space-between; font-size: 0.85rem; margin-bottom: 0.25rem; }
.cart-totals .total {
  font-weight: bold;
  font-size: 0.95rem;
  margin-top: 0.5rem;
  padding-top: 0.5rem;
  border-top: 1px solid rgba(255,255,255,0.1);
}

.btn-checkout {
  padding: 0.7rem;
  background: #22c55e;
  color: #fff;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-weight: bold;
  margin-top: 0.5rem;
  font-size: 0.9rem;
}
.btn-checkout:hover { background: #16a34a; }
.btn-checkout:disabled { background: #555; cursor: not-allowed; }

.loading-state {
  color: #fbbf24;
  text-align: center;
  padding: 2rem;
  font-size: 1rem;
}
</style>
