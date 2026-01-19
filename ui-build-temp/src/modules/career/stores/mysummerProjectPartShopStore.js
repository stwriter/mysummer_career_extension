import { ref, computed } from "vue"
import { defineStore } from "pinia"
import { useBridge, lua } from "@/bridge"

export const useMysummerProjectPartShopStore = defineStore("mysummerProjectPartShop", () => {
  const { events } = useBridge()

  // Shop data from Lua
  const shopData = ref({
    isOpen: false,
    categories: [],
    cart: { items: [], subtotal: 0, taxes: 0, total: 0 },
    playerMoney: 0,
  })

  // UI state
  const expandedCategories = ref({})
  const searchQuery = ref("")

  // Computed: filtered categories based on search
  const filteredCategories = computed(() => {
    if (!searchQuery.value) {
      return shopData.value.categories || []
    }

    const query = searchQuery.value.toLowerCase()
    return (shopData.value.categories || []).map(category => {
      const filteredParts = category.parts.filter(part =>
        part.niceName.toLowerCase().includes(query) ||
        part.name.toLowerCase().includes(query) ||
        category.niceName.toLowerCase().includes(query)
      )

      if (filteredParts.length > 0) {
        return { ...category, parts: filteredParts, partCount: filteredParts.length }
      }
      return null
    }).filter(Boolean)
  })

  // Helper to ensure array (Lua empty tables come as objects)
  const ensureArray = (val) => Array.isArray(val) ? val : []

  // Computed: check if a part is in cart
  const isInCart = (partId) => {
    const items = ensureArray(shopData.value.cart?.items)
    return items.some(item => item.id === partId)
  }

  // Computed: can afford checkout
  const canAfford = computed(() => {
    return shopData.value.cart.total <= shopData.value.playerMoney
  })

  // Actions
  const toggleCategory = (slotType) => {
    expandedCategories.value[slotType] = !expandedCategories.value[slotType]
  }

  const expandAll = () => {
    for (const category of shopData.value.categories || []) {
      expandedCategories.value[category.slotType] = true
    }
  }

  const collapseAll = () => {
    expandedCategories.value = {}
  }

  const setSearch = (query) => {
    searchQuery.value = query
    // Auto-expand categories that have matches
    if (query) {
      expandAll()
    }
  }

  // Helper to safely call Lua module
  const luaModule = () => lua?.career_modules_mysummerProjectPartShop

  // Lua calls (with safety checks)
  const addToCart = (partId) => {
    console.log("[ProjectPartShop] Adding to cart:", partId)
    luaModule()?.addToCart(partId)
  }

  const removeFromCart = (partId) => {
    console.log("[ProjectPartShop] Removing from cart:", partId)
    luaModule()?.removeFromCart(partId)
  }

  const clearCart = () => {
    console.log("[ProjectPartShop] Clearing cart")
    luaModule()?.clearCart()
  }

  const checkout = () => {
    console.log("[ProjectPartShop] Checkout")
    luaModule()?.checkout()
  }

  const cancelShop = () => {
    console.log("[ProjectPartShop] Cancel")
    luaModule()?.cancelShop()
  }

  const requestData = () => {
    console.log("[ProjectPartShop] Requesting data")
    if (luaModule()) {
      luaModule().requestData()
    } else {
      console.warn("[ProjectPartShop] Lua module not available yet")
    }
  }

  // Event handler
  const handleShopData = (data) => {
    console.log("[ProjectPartShop] Received shop data:", data)
    // Normalize data - ensure arrays are arrays (Lua empty tables come as objects)
    const normalized = {
      isOpen: data.isOpen || false,
      categories: ensureArray(data.categories),
      cart: {
        items: ensureArray(data.cart?.items),
        subtotal: data.cart?.subtotal || 0,
        taxes: data.cart?.taxes || 0,
        total: data.cart?.total || 0,
      },
      playerMoney: data.playerMoney || 0,
    }
    shopData.value = normalized
    console.log("[ProjectPartShop] Normalized data - categories:", normalized.categories.length)
  }

  // Event listeners
  const listen = (state) => {
    const method = state ? "on" : "off"
    console.log("[ProjectPartShop] Setting up event listener:", method, "mysummerProjectShopData")
    events[method]("mysummerProjectShopData", handleShopData)
  }

  // Initialize listener immediately when store is created
  console.log("[ProjectPartShop] Store initializing, setting up event listener")
  listen(true)

  const dispose = () => {
    listen(false)
    shopData.value = {
      isOpen: false,
      categories: [],
      cart: { items: [], subtotal: 0, taxes: 0, total: 0 },
      playerMoney: 0,
    }
    expandedCategories.value = {}
    searchQuery.value = ""
  }

  return {
    // State
    shopData,
    expandedCategories,
    searchQuery,

    // Computed
    filteredCategories,
    canAfford,

    // Methods
    isInCart,
    toggleCategory,
    expandAll,
    collapseAll,
    setSearch,

    // Lua calls
    addToCart,
    removeFromCart,
    clearCart,
    checkout,
    cancelShop,
    requestData,

    // Lifecycle
    dispose,
  }
})
