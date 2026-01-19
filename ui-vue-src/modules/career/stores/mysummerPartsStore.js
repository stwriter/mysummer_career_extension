import { ref } from "vue"
import { defineStore } from "pinia"
import { lua, useBridge } from "@/bridge"

export const useMySummerPartsStore = defineStore("mysummerParts", () => {
  const { events } = useBridge()

  const marketData = ref({
    listings: [],
    leads: [],
    activePickup: null,
  })
  const loading = ref(false)
  const error = ref(null)

  const setMarketData = (data) => {
    marketData.value = data || { listings: [], leads: [], activePickup: null }
  }

  const requestData = async () => {
    loading.value = true
    error.value = null
    try {
      const data = await lua.career_modules_mysummerParts.getMarketData()
      setMarketData(data)
    } catch (err) {
      error.value = err
    } finally {
      loading.value = false
    }
  }

  const refreshListings = async () => {
    loading.value = true
    error.value = null
    try {
      const data = await lua.career_modules_mysummerParts.refreshListings()
      setMarketData(data)
      return data
    } catch (err) {
      error.value = err
      throw err
    } finally {
      loading.value = false
    }
  }

  const acceptListing = async (listingId) => {
    const result = await lua.career_modules_mysummerParts.acceptListing(listingId)
    return result
  }

  const acceptLead = async (leadId) => {
    const result = await lua.career_modules_mysummerParts.acceptLead(leadId)
    return result
  }

  const acceptMultipleListings = async (listingIds) => {
    const result = await lua.career_modules_mysummerParts.acceptMultipleListings(listingIds)
    if (result) {
      setMarketData(result)
    }
    return result
  }

  const cancelPickup = async () => {
    const data = await lua.career_modules_mysummerParts.cancelActivePickup()
    setMarketData(data)
    return data
  }

  const closeMenu = async () => {
    await lua.career_modules_mysummerParts.closeMenu()
  }

  const handleMarketUpdate = (data) => {
    setMarketData(data)
  }

  const dispose = () => {
    events.off("mysummerMarketUpdated", handleMarketUpdate)
  }

  events.on("mysummerMarketUpdated", handleMarketUpdate)

  return {
    marketData,
    loading,
    error,
    requestData,
    refreshListings,
    acceptListing,
    acceptLead,
    acceptMultipleListings,
    cancelPickup,
    closeMenu,
    dispose,
  }
})
