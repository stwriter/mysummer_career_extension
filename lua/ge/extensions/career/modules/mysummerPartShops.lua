-- MySummer Part Shops - Physical stores for buying new ETK-I parts
-- Parts are added to inventory (not installed directly)
-- Prices are base game price + markup percentage

local M = {}
M.moduleName = "career_modules_mysummerPartShops"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_payment",
  "career_modules_playerAttributes",
  "career_modules_business_businessPartInventory",
  "career_modules_mysummerCargo",  -- Native cargo integration
}

local logTag = "mysummerPartShops"
local jbeamIO = nil

-- Lazy load jbeamIO to avoid issues at module load time
local function getJbeamIO()
  if not jbeamIO then
    jbeamIO = require("jbeam/io")
  end
  return jbeamIO
end

-- ============================================================================
-- SHOP DEFINITIONS
-- ============================================================================

-- Shop locations on West Coast USA
local shopDefinitions = {
  fastAutoParts = {
    id = "fastAutoParts",
    name = "Fast Auto Parts",
    description = "Premium parts at premium prices",
    priceMultiplier = 2.5,  -- 150% markup
    pos = { 902, -545, 164 },  -- Near Fast Auto tuning shop
    radius = 15,
    icon = "shopping_cart",
  },
  belascoParts = {
    id = "belascoParts",
    name = "Belasco Auto Parts",
    description = "Standard parts store",
    priceMultiplier = 2.0,  -- 100% markup (base x2)
    pos = { -698, 808, 75 },  -- Near Belasco Auto
    radius = 15,
    icon = "shopping_cart",
  },
  joesParts = {
    id = "joesParts",
    name = "Joe's Discount Parts",
    description = "Cheaper parts, limited selection",
    priceMultiplier = 1.5,  -- 50% markup
    pos = { -68, 2, 120 },  -- Near Jerry Rigs/Joe's area
    radius = 15,
    icon = "shopping_cart",
    limitedStock = true,  -- Only shows subset of parts
  },
}

-- ============================================================================
-- CHAPTER-BASED PART UNLOCKS
-- ============================================================================
-- Only UPGRADES are locked. Base/stock parts are always available (chapter 1).
-- Parts not in this list = always available (no restriction).

local upgradeChapterRequirements = {
  -- Chapter 2: Estética + mejoras leves
  ["etki_bumper_F_kit"] = 2,
  ["etki_bumper_R_kit"] = 2,
  ["etki_spoiler_kit"] = 2,
  ["etki_sideskirt_kit"] = 2,
  ["etki_hood_vents"] = 2,
  ["etki_trim_kit"] = 2,
  ["etki_exhaust_wide"] = 2,
  ["etki_oilcooler"] = 2,

  -- Chapter 3: Rendimiento medio
  ["etki_brake_F_race"] = 3,
  ["etki_brake_R_race"] = 3,
  ["brakepad_F_semi_race"] = 3,
  ["brakepad_R_semi_race"] = 3,
  ["etki_radiator_race"] = 3,
  ["etki_oilpan_race"] = 3,
  ["etki_swaybar_F_race"] = 3,
  ["etki_swaybar_R_race"] = 3,
  ["etki_strut_bar"] = 3,
  ["etki_fenderflare_FL_kit"] = 3,
  ["etki_fenderflare_FR_kit"] = 3,
  ["etki_fenderflare_R_kit"] = 3,
  ["etki_chinspoiler_kit"] = 3,

  -- Chapter 4: Racing
  ["etki_strut_F_race"] = 4,
  ["etki_coilover_R_race"] = 4,
  ["etki_steeringbox_race"] = 4,
  ["etki_transmission_6M_race"] = 4,
  ["etki_differential_R_race"] = 4,
  ["etki_engine_internals_heavy"] = 4,
  ["etki_turbo_stage1"] = 4,

  -- Chapter 5: Elite
  ["etki_turbo_stage2"] = 5,
  ["etki_engine_internals_ultra"] = 5,
  ["etki_engine_ecu_race"] = 5,
}

-- Get current chapter from mysummerCareer module
local function getCurrentChapter()
  if career_modules_mysummerCareer and career_modules_mysummerCareer.getCurrentChapter then
    local chapter = career_modules_mysummerCareer.getCurrentChapter()
    -- Defensive: ensure we get a valid number
    if type(chapter) == "number" and chapter >= 1 then
      return chapter
    end
    log("W", logTag, "getCurrentChapter returned invalid value: " .. tostring(chapter) .. ", defaulting to 1")
  end
  return 1  -- Default to chapter 1 if module not available
end

-- Check if a part is unlocked based on current chapter
local function getPartChapterRequirement(partName)
  return upgradeChapterRequirements[partName] or 1
end

local function isPartUnlocked(partName)
  local required = getPartChapterRequirement(partName)
  return getCurrentChapter() >= required
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  nearShop = nil,  -- Current shop player is near (or nil)
  shopMenuOpen = false,
  partsCache = nil,  -- Cached parts list for ETK-I
  lastNotificationTime = 0,
  pendingPickup = {},  -- Parts waiting to be picked up at port
  carryingParts = {},  -- Parts currently being transported
  deliveryLocation = nil,  -- Where to deliver (garage position)
  nearPickup = false,  -- Is player near pickup location
  nearDelivery = false,  -- Is player near delivery location
}

-- Pickup location at port (near Import Dealership / online parking area)
local pickupLocation = {
  pos = { 428, 1682, 75 },  -- Island shipping yard on West Coast USA
  radius = 20,
  name = "Import Warehouse",
}

-- ============================================================================
-- SAVE/LOAD STATE (defined early so they can be used throughout)
-- ============================================================================

local saveFile = "mysummerPartShops.json"

local function loadState()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/rls_career/" .. saveFile
  local data = jsonReadFile(filePath)
  if data then
    state.pendingPickup = data.pendingPickup or {}
    local carryingParts = data.carryingParts or {}

    -- Move any carryingParts back to pendingPickup on load
    -- This handles crashes/restarts - player must pick up again
    if #carryingParts > 0 then
      log("I", logTag, "Moving " .. #carryingParts .. " carrying parts back to pendingPickup (restart recovery)")
      for _, part in ipairs(carryingParts) do
        table.insert(state.pendingPickup, part)
      end
    end

    -- Always start with empty carryingParts - cargo system is source of truth
    state.carryingParts = {}
    state.deliveryLocation = data.deliveryLocation

    log("I", logTag, "Loaded state: " .. #state.pendingPickup .. " pending (including recovered)")
  end
end

local function saveState(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  savePath = currentSavePath or savePath
  if not savePath then return end

  local filePath = savePath .. "/career/rls_career/" .. saveFile
  local data = {
    pendingPickup = state.pendingPickup,
    carryingParts = state.carryingParts,
    deliveryLocation = state.deliveryLocation,
  }

  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("I", logTag, "Saved state: " .. #state.pendingPickup .. " pending, " .. #state.carryingParts .. " carrying")
end

-- ============================================================================
-- PARTS LOADING
-- ============================================================================

-- Build cache of all available parts for ETK-I
local function buildPartsCache(forceRebuild)
  -- Return cached if we have parts (unless forced)
  if not forceRebuild and state.partsCache and #state.partsCache > 0 then
    return state.partsCache
  end

  local io = getJbeamIO()
  if not io then
    log("E", logTag, "Failed to load jbeam/io module")
    state.partsCache = {}
    return state.partsCache
  end

  -- Try to get ioCtx from a spawned ETK-I vehicle first
  local ioCtx = nil
  local availablePartNames = {}

  -- Look for any spawned ETK-I
  for _, vehObj in ipairs(getAllVehiclesByType()) do
    if vehObj then
      local model = vehObj:getJBeamFilename()
      if model == "etki" then
        local vehId = vehObj:getId()
        local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehId)
        if vehicleData and vehicleData.ioCtx then
          ioCtx = vehicleData.ioCtx
          availablePartNames = io.getAvailableParts(ioCtx) or {}
          log("I", logTag, "Using spawned ETK-I (id: " .. vehId .. ") for parts cache")
          break
        end
      end
    end
  end

  -- Fallback: try to load directly
  if not ioCtx then
    local vehicleDir = "/vehicles/etki/"
    if FS:directoryExists(vehicleDir) then
      ioCtx = io.startLoading({ vehicleDir, "/vehicles/common/" })
      if ioCtx then
        availablePartNames = io.getAvailableParts(ioCtx) or {}
        log("I", logTag, "Using direct jbeam loading for parts cache")
      end
    end
  end

  if not ioCtx then
    log("W", logTag, "Could not get ioCtx for parts loading")
    state.partsCache = {}
    return state.partsCache
  end

  local parts = {}
  local partCount = 0

  -- Helper to check if a part should be included (ETK-I compatible only)
  local function shouldIncludePart(partName, slotType)
    if not partName or partName == "" then return false end

    -- Always include ETK-I specific parts
    if partName:find("^etki_") then return true end

    -- For common parts, check slotType to ensure ETK-I compatibility
    -- Exclude parts from other vehicles (pigeon_, pickup_, etc.)
    if partName:find("^pigeon_") or partName:find("^pickup_") or partName:find("^fullsize_")
       or partName:find("^van_") or partName:find("^covet_") or partName:find("^legran_")
       or partName:find("^roamer_") or partName:find("^d_series_") or partName:find("^semi_")
       or partName:find("^sunburst_") or partName:find("^pessima_") or partName:find("^midsize_")
       or partName:find("^hopper_") or partName:find("^moonhawk_") or partName:find("^bluebuck_")
       or partName:find("^bolide_") or partName:find("^barstow_") or partName:find("^burnside_")
       or partName:find("^wendover_") or partName:find("^vivace_") or partName:find("^sbr_")
       or partName:find("^scintilla_") or partName:find("^autobello_") or partName:find("^miramar_")
       or partName:find("^bastion_") or partName:find("^lansdale_") or partName:find("^alder_")
       or partName:find("^bogie_") or partName:find("^trailer_") then
      return false
    end

    -- Include generic tires (tire_F_, tire_R_)
    if partName:find("^tire_[FR]_") then return true end

    -- Include wheels/rims - they end with _F or _R (e.g., wheel_19a_15x7_F, etk_wheel_07a_16x7_R)
    -- But NOT flywheel, wheeldata, or steering wheel
    if partName:find("_[FR]$") and partName:find("wheel") and not partName:find("flywheel") and not partName:find("wheeldata") and not partName:find("steer") then
      return true
    end

    -- Include brake pads (brakepad_F, brakepad_R)
    if partName:find("^brakepad_[FR]") then return true end

    -- Include hubcaps (hubcap_F_, hubcap_R_)
    if partName:find("^hubcap_[FR]_") then return true end

    -- Include steelies
    if partName:find("^steelies_") then return true end

    -- Include license plates and GPS
    if partName:find("^licenseplate_") or partName:find("^gps") then return true end

    return false
  end

  -- For each available part, get full info using getPart
  for partName, _ in pairs(availablePartNames) do
    if shouldIncludePart(partName) then
      local partData = io.getPart(ioCtx, partName)
      if partData then
        local value = 0
        local niceName = partName
        local slotType = "unknown"

        -- Get value from information block
        if partData.information and partData.information.value then
          value = tonumber(partData.information.value) or 0
        end

        -- Get nice name
        if partData.information and partData.information.name then
          niceName = partData.information.name
        end

        -- Get slot type (can be a string or table)
        if partData.slotType then
          if type(partData.slotType) == "string" then
            slotType = partData.slotType
          elseif type(partData.slotType) == "table" and partData.slotType[1] then
            slotType = partData.slotType[1]
          end
        end

        -- Only include parts with value > 0 (real purchasable parts)
        if value > 0 then
          table.insert(parts, {
            name = partName,
            niceName = niceName,
            slotType = slotType,
            baseValue = value,
          })
          partCount = partCount + 1
        end
      end
    end
  end

  -- Sort by name
  table.sort(parts, function(a, b) return a.niceName < b.niceName end)

  -- DEBUG: Log all unique slotTypes for categorization
  local slotTypes = {}
  for _, part in ipairs(parts) do
    if part.slotType and type(part.slotType) == "string" and part.slotType ~= "unknown" then
      slotTypes[part.slotType] = (slotTypes[part.slotType] or 0) + 1
    end
  end
  log("I", logTag, "=== UNIQUE SLOT TYPES ===")
  for slotType, count in pairs(slotTypes) do
    if type(slotType) == "string" then
      log("I", logTag, "  " .. slotType .. " (" .. count .. " parts)")
    end
  end
  log("I", logTag, "=========================")

  log("I", logTag, "Built parts cache with " .. #parts .. " parts for ETK-I")
  state.partsCache = parts
  return state.partsCache
end

-- ============================================================================
-- CHILD PARTS DETECTION
-- ============================================================================

-- Helper to extract all part names from a partsTree recursively
local function extractPartNamesFromTree(tree, partNames)
  partNames = partNames or {}
  if not tree then return partNames end

  -- Add this node's chosen part
  if tree.chosenPartName and tree.chosenPartName ~= "" then
    partNames[tree.chosenPartName] = true
  end

  -- Recurse into children
  if tree.children then
    for _, child in pairs(tree.children) do
      extractPartNamesFromTree(child, partNames)
    end
  end

  return partNames
end

-- Check if player owns a part (in part inventory or installed on ETK-I)
local function playerOwnsPart(partName)
  -- 1. Check business part inventory (loose parts in storage)
  local partInventory = career_modules_business_businessPartInventory
  if partInventory and partInventory.getInventory then
    local inventory = partInventory.getInventory() or {}
    for _, part in pairs(inventory) do
      if part.name == partName and part.vehicleModel == "etki" then
        log("D", logTag, "playerOwnsPart: " .. partName .. " found in part inventory")
        return true
      end
    end
  end

  -- 2. Check spawned ETK-I vehicle
  for _, vehObj in ipairs(getAllVehiclesByType()) do
    if vehObj then
      local model = vehObj:getJBeamFilename()
      if model == "etki" then
        local vehId = vehObj:getId()
        local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehId)
        if vehicleData and vehicleData.config and vehicleData.config.partsTree then
          local installedParts = extractPartNamesFromTree(vehicleData.config.partsTree)
          if installedParts[partName] then
            log("D", logTag, "playerOwnsPart: " .. partName .. " found on ETK-I (vehId: " .. vehId .. ")")
            return true
          end
        end
      end
    end
  end

  return false
end

-- Get all child parts (default parts in slots) for a given part
-- Returns list of { name, niceName, price, slotType } for parts not owned
local function getRequiredChildParts(partName, priceMultiplier)
  local childParts = {}
  local io = getJbeamIO()
  if not io then return childParts end
  
  -- Get ioCtx from spawned ETK-I or load directly
  local ioCtx = nil
  for _, vehObj in ipairs(getAllVehiclesByType()) do
    if vehObj and vehObj:getJBeamFilename() == "etki" then
      local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehObj:getId())
      if vehicleData and vehicleData.ioCtx then
        ioCtx = vehicleData.ioCtx
        break
      end
    end
  end
  
  if not ioCtx then
    local vehicleDir = "/vehicles/etki/"
    if FS:directoryExists(vehicleDir) then
      ioCtx = io.startLoading({ vehicleDir, "/vehicles/common/" })
    end
  end
  
  if not ioCtx then return childParts end
  
  -- Recursive function to find all child parts
  local function findChildParts(pName, visited)
    visited = visited or {}
    if visited[pName] then return end
    visited[pName] = true
    
    local partData = io.getPart(ioCtx, pName)
    if not partData then return end
    
    -- Check slots2 for default parts
    if partData.slots2 then
      for _, slotDef in ipairs(partData.slots2) do
        if type(slotDef) == "table" then
          local defaultPart = slotDef.default
          if defaultPart and defaultPart ~= "" and not visited[defaultPart] then
            -- Check if player owns this part
            if not playerOwnsPart(defaultPart) then
              -- Get part info
              local childData = io.getPart(ioCtx, defaultPart)
              if childData then
                local value = 0
                local niceName = defaultPart
                local slotType = slotDef.name or slotDef.type or "unknown"
                
                if childData.information then
                  value = tonumber(childData.information.value) or 0
                  niceName = childData.information.name or defaultPart
                end
                
                if value > 0 then
                  table.insert(childParts, {
                    name = defaultPart,
                    niceName = niceName .. " (required)",
                    slotType = slotType,
                    price = math.floor(value * priceMultiplier),
                    baseValue = value,
                    isChildPart = true,
                    parentPart = pName,
                  })
                  log("I", logTag, "Found required child part: " .. niceName .. " ($" .. math.floor(value * priceMultiplier) .. ")")
                end
              end
            end
            
            -- Recursively check this child's children
            findChildParts(defaultPart, visited)
          end
        end
      end
    end
  end
  
  findChildParts(partName, {})
  return childParts
end

-- Get parts list for a specific shop (with prices calculated)
local function getShopParts(shopId)
  local shop = shopDefinitions[shopId]
  if not shop then
    return {}
  end

  local allParts = buildPartsCache()
  local shopParts = {}

  for _, part in ipairs(allParts) do
    -- If limited stock shop, only include some parts
    if shop.limitedStock then
      -- Joe's only has cheaper parts (under $500 base value)
      if part.baseValue > 500 then
        goto continue
      end
    end

    local shopPrice = math.floor(part.baseValue * shop.priceMultiplier)

    -- Check chapter-based unlock
    local partUnlocked = isPartUnlocked(part.name)
    local requiredChap = getPartChapterRequirement(part.name)

    table.insert(shopParts, {
      name = part.name,
      niceName = part.niceName,
      slotType = part.slotType,
      baseValue = part.baseValue,
      shopPrice = shopPrice,
      locked = not partUnlocked,
      requiredChapter = requiredChap,
    })

    ::continue::
  end

  return shopParts
end

-- ============================================================================
-- SHOP INTERACTION
-- ============================================================================

-- Check if player is near any shop
local function checkPlayerNearShop()
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then
    return nil
  end

  local playerPos = playerVeh:getPosition()
  if not playerPos then
    return nil
  end

  for shopId, shop in pairs(shopDefinitions) do
    local shopPos = vec3(shop.pos[1], shop.pos[2], shop.pos[3])
    local distance = (playerPos - shopPos):length()

    if distance <= shop.radius then
      return shopId
    end
  end

  return nil
end

-- Open shop menu
local function openShopMenu(shopId)
  local shop = shopDefinitions[shopId]
  if not shop then
    log("W", logTag, "Unknown shop: " .. tostring(shopId))
    return
  end

  log("I", logTag, "Opening shop menu: " .. shop.name)
  state.shopMenuOpen = true

  -- Get parts for this shop
  local parts = getShopParts(shopId)

  -- Send data to UI
  local shopData = {
    shopId = shopId,
    shopName = shop.name,
    shopDescription = shop.description,
    priceMultiplier = shop.priceMultiplier,
    parts = parts,
  }

  if guihooks then
    guihooks.trigger("mysummerPartShopOpened", shopData)
    guihooks.trigger("ChangeState", { state = "mysummer-part-shop" })
  end
end

-- Close shop menu
local function closeShopMenu()
  state.shopMenuOpen = false
  if guihooks then
    guihooks.trigger("mysummerPartShopClosed")
  end
  -- Return to game
  if career_career and career_career.closeAllMenus then
    career_career.closeAllMenus()
  end
end

-- Purchase a part (add to inventory)
local function purchasePart(shopId, partName)
  local shop = shopDefinitions[shopId]
  if not shop then
    return { success = false, message = "Invalid shop" }
  end

  -- Find the part
  local parts = getShopParts(shopId)
  local partToBuy = nil
  for _, part in ipairs(parts) do
    if part.name == partName then
      partToBuy = part
      break
    end
  end

  if not partToBuy then
    return { success = false, message = "Part not available" }
  end

  -- Check if part is locked by chapter
  if partToBuy.locked then
    return { success = false, message = "Part locked. Requires Chapter " .. tostring(partToBuy.requiredChapter) }
  end

  -- Check if player can afford it
  local playerFunds = 0
  if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
    playerFunds = career_modules_playerAttributes.getAttributeValue("money") or 0
  end

  if playerFunds < partToBuy.shopPrice then
    return { success = false, message = "Insufficient funds" }
  end

  -- Deduct money
  if career_modules_payment and career_modules_payment.pay then
    local payResult = career_modules_payment.pay(
      {money = {amount = partToBuy.shopPrice}},
      {label = "Bought: " .. partToBuy.niceName, tags = {"buying", "parts"}}
    )
    if not payResult then
      return { success = false, message = "Payment failed" }
    end
  end

  -- Add part to inventory
  local partInventory = career_modules_business_businessPartInventory
  if not partInventory or not partInventory.addPart then
    log("E", logTag, "Part inventory module not available")
    return { success = false, message = "Inventory system error" }
  end

  local partData = {
    name = partToBuy.name,
    vehicleModel = "etki",
    partCondition = { integrityValue = 1, odometer = 0, visualValue = 1 },  -- New part
    slot = partToBuy.slotType,
    location = 0,  -- 0 = in storage (inventory)
    value = partToBuy.shopPrice,
    description = { description = partToBuy.niceName }
  }

  local newPartId = partInventory.addPart(partData)
  if newPartId then
    log("I", logTag, "Purchased and added to inventory: " .. partToBuy.niceName .. " for $" .. partToBuy.shopPrice)

    -- Show notification
    if ui_message then
      ui_message("Purchased: " .. partToBuy.niceName .. " - Added to inventory", 3, "Shop", "success")
    end

    return { success = true, message = "Part purchased", partId = newPartId }
  else
    -- Refund if adding to inventory failed
    if career_modules_payment and career_modules_payment.earn then
      career_modules_payment.earn(partToBuy.shopPrice, "Refund: " .. partToBuy.niceName)
    end
    return { success = false, message = "Failed to add to inventory" }
  end
end

-- ============================================================================
-- ONLINE SHOP SYSTEM
-- ============================================================================

local onlinePriceMultiplier = 2.0  -- 100% markup for online orders

-- Get parts for online shop (fixed pricing with stock status)
local function getOnlineShopParts()
  -- Force rebuild cache to get fresh parts including wheels/tires
  local allParts = buildPartsCache(true)
  log("I", logTag, "getOnlineShopParts: returning " .. #allParts .. " parts")
  local shopParts = {}

  for _, part in ipairs(allParts) do
    local shopPrice = math.floor(part.baseValue * onlinePriceMultiplier)
    
    -- Check if player already owns this part (out of stock if owned)
    local isOwned = playerOwnsPart(part.name)
    
    -- Also check if part is in pending pickup (already ordered)
    local isPending = false
    for _, pendingPart in ipairs(state.pendingPickup) do
      if pendingPart.name == part.name then
        isPending = true
        break
      end
    end
    
    -- Also check if part is being carried
    local isCarrying = false
    for _, carryingPart in ipairs(state.carryingParts) do
      if carryingPart.name == part.name then
        isCarrying = true
        break
      end
    end

    -- Check chapter-based unlock
    local partUnlocked = isPartUnlocked(part.name)
    local requiredChap = getPartChapterRequirement(part.name)

    table.insert(shopParts, {
      name = part.name,
      niceName = part.niceName,
      slotType = part.slotType,
      baseValue = part.baseValue,
      shopPrice = shopPrice,
      inStock = not isOwned and not isPending and not isCarrying,
      owned = isOwned,
      pending = isPending,
      carrying = isCarrying,
      locked = not partUnlocked,
      requiredChapter = requiredChap,
    })
  end

  return shopParts
end

-- Place an online order (from cart)
local function placeOnlineOrder(orderDataJson)
  log("I", logTag, "placeOnlineOrder called with: " .. tostring(orderDataJson))

  -- Parse order data
  local orderItems = jsonDecode(orderDataJson)
  if not orderItems or #orderItems == 0 then
    log("W", logTag, "placeOnlineOrder: Invalid order data")
    return { success = false, message = "Invalid order data" }
  end

  log("I", logTag, "placeOnlineOrder: Processing " .. #orderItems .. " items, current chapter: " .. tostring(getCurrentChapter()))

  -- Check for locked parts (chapter-gated)
  for _, item in ipairs(orderItems) do
    local partName = item.name or "unknown"
    local unlocked = isPartUnlocked(partName)
    log("D", logTag, "Checking part: " .. partName .. ", unlocked: " .. tostring(unlocked))

    if not unlocked then
      local requiredChap = getPartChapterRequirement(partName)
      local partDisplayName = item.niceName or item.name or "Unknown"
      local msg = "Part locked: " .. tostring(partDisplayName) .. " requires Chapter " .. tostring(requiredChap)
      log("W", logTag, msg)
      return { success = false, message = msg }
    end
  end

  -- Add required child parts for each item in order
  local expandedItems = {}
  local addedChildParts = {}  -- Track to avoid duplicates
  
  for _, item in ipairs(orderItems) do
    -- Add the original item
    table.insert(expandedItems, item)
    
    -- Check for required child parts
    local childParts = getRequiredChildParts(item.name, onlinePriceMultiplier)
    for _, childPart in ipairs(childParts) do
      -- Skip if already added or in original order
      if not addedChildParts[childPart.name] then
        local alreadyInOrder = false
        for _, existingItem in ipairs(orderItems) do
          if existingItem.name == childPart.name then
            alreadyInOrder = true
            break
          end
        end
        
        if not alreadyInOrder then
          table.insert(expandedItems, {
            name = childPart.name,
            niceName = childPart.niceName,
            slotType = childPart.slotType,
            price = childPart.price,
            quantity = 1,
            isChildPart = true,
          })
          addedChildParts[childPart.name] = true
          log("I", logTag, "Auto-added required child part: " .. childPart.niceName)
        end
      end
    end
  end
  
  -- Use expanded items list
  orderItems = expandedItems

  -- Calculate total cost (including child parts)
  local totalCost = 0
  for _, item in ipairs(orderItems) do
    totalCost = totalCost + (item.price * (item.quantity or 1))
  end

  -- Check if player can afford it
  local playerFunds = 0
  if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
    playerFunds = career_modules_playerAttributes.getAttributeValue("money") or 0
  end

  if playerFunds < totalCost then
    return { success = false, message = "Insufficient funds (including required child parts)" }
  end

  -- Deduct money
  if career_modules_payment and career_modules_payment.pay then
    log("I", logTag, "Attempting payment of $" .. totalCost .. " (includes required child parts)")
    local payResult = career_modules_payment.pay(
      {money = {amount = totalCost}},
      {label = "Online Parts Order", tags = {"buying", "parts"}}
    )
    if not payResult then
      log("W", logTag, "Payment failed for $" .. totalCost)
      return { success = false, message = "Payment failed" }
    end
    log("I", logTag, "Payment successful: $" .. totalCost)
  else
    log("W", logTag, "Payment module not available, order placed without payment!")
  end

  -- Save delivery location (current player position - should be at garage computer)
  local playerVeh = be:getPlayerVehicle(0)
  if playerVeh then
    local playerPos = playerVeh:getPosition()
    if playerPos then
      state.deliveryLocation = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
    end
  end

  -- Add items to pending pickup
  for _, item in ipairs(orderItems) do
    for i = 1, item.quantity do
      table.insert(state.pendingPickup, {
        name = item.name,
        niceName = item.niceName,
        slotType = item.slotType,
        price = item.price,
        orderTime = os.time(),
      })
    end
  end

  log("I", logTag, "Online order placed: " .. #orderItems .. " item types, total: $" .. totalCost)

  -- Save state immediately
  saveState()

  -- Show notification
  if ui_message then
    ui_message("Order placed! Pick up your parts at the Import Warehouse.", 5, "Shop", "success")
  end

  -- Set waypoint to pickup location
  local pickupPos = vec3(pickupLocation.pos[1], pickupLocation.pos[2], pickupLocation.pos[3])
  if core_groundMarkers then
    core_groundMarkers.setFocus(pickupPos)
  end

  return { success = true, message = "Order placed", itemCount = #state.pendingPickup }
end

-- Check if player is near pickup location (port)
local function checkPlayerNearPickup()
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then return false end

  local playerPos = playerVeh:getPosition()
  if not playerPos then return false end

  local pickupPos = vec3(pickupLocation.pos[1], pickupLocation.pos[2], pickupLocation.pos[3])
  local distance = (playerPos - pickupPos):length()

  return distance <= pickupLocation.radius
end

-- Check if player is near delivery location (garage where order was placed)
local function checkPlayerNearDelivery()
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then return false end

  local playerPos = playerVeh:getPosition()
  if not playerPos then return false end

  -- First check specific delivery location if set (where order was placed)
  if state.deliveryLocation then
    local deliveryPos = vec3(state.deliveryLocation.x, state.deliveryLocation.y, state.deliveryLocation.z)
    local distance = (playerPos - deliveryPos):length()
    if distance <= 5 then
      return true
    end
  end

  -- Check if player is near any PURCHASED garage
  -- Use freeroam_facilities.getAverageDoorPositionForFacility for accurate positions
  local garageManager = career_modules_garageManager
  if not garageManager or not garageManager.getPurchasedGarages then
    return false
  end

  local purchasedGarageIds = garageManager.getPurchasedGarages()
  if not purchasedGarageIds then
    return false
  end

  -- Convert array to lookup table (getPurchasedGarages returns array of IDs)
  local purchasedLookup = {}
  if type(purchasedGarageIds) == "table" then
    if purchasedGarageIds[1] then
      -- It's an array of IDs
      for _, gid in ipairs(purchasedGarageIds) do
        purchasedLookup[gid] = true
      end
    else
      -- It's already a map
      purchasedLookup = purchasedGarageIds
    end
  end

  -- Check each purchased garage using freeroam_facilities API
  if freeroam_facilities and freeroam_facilities.getFacility then
    for garageId, _ in pairs(purchasedLookup) do
      local garage = freeroam_facilities.getFacility("garage", garageId)
      if garage then
        -- Use getAverageDoorPositionForFacility for accurate position
        local garagePos = nil
        if freeroam_facilities.getAverageDoorPositionForFacility then
          garagePos = freeroam_facilities.getAverageDoorPositionForFacility(garage)
        end

        if garagePos then
          local distance = (playerPos - garagePos):length()
          if distance <= 5 then
            log("I", logTag, "Player near purchased garage '" .. (garage.name or garageId) .. "' (dist=" .. math.floor(distance) .. "m)")
            return true
          end
        end
      end
    end
  end

  return false
end

-- Step 1: Pick up parts at port (load into vehicle cargo using native system)
-- Loads as many parts as will fit, leaves the rest for later pickup
local function pickupPartsAtPort()
  if #state.pendingPickup == 0 then
    return { success = false, message = "No parts to pick up" }
  end

  local cargoModule = career_modules_mysummerCargo
  if not cargoModule then
    -- Fallback to old system if cargo module not available
    for _, part in ipairs(state.pendingPickup) do
      table.insert(state.carryingParts, part)
    end
    local count = #state.pendingPickup
    state.pendingPickup = {}
    saveState()
    ui_message("Loaded " .. count .. " parts! Deliver them to your garage.", 5, "Shop", "success")
    return { success = true, count = count }
  end

  -- Get available cargo space first
  cargoModule.getNearbyCargoContainers(function(containers)
    if #containers == 0 then
      ui_message("No cargo container! Install a cargo box in your vehicle.", 5, "Shop", "warning")
      return
    end

    -- Calculate total available space
    local totalFreeSlots = 0
    for _, con in ipairs(containers) do
      totalFreeSlots = totalFreeSlots + con.freeSlots
    end

    if totalFreeSlots == 0 then
      ui_message("Cargo container is full! Deliver current parts first.", 5, "Shop", "warning")
      return
    end

    -- Load parts one by one until we run out of space
    local loadedCount = 0
    local remainingParts = {}
    local partsToLoad = deepcopy(state.pendingPickup)
    local usedSlots = 0

    local function loadNextPart(index)
      if index > #partsToLoad then
        -- All parts processed - update pending with remaining parts
        state.pendingPickup = remainingParts
        saveState()

        if loadedCount == 0 then
          ui_message("Parts too large for available cargo space!", 5, "Shop", "warning")
        elseif #remainingParts > 0 then
          ui_message(string.format("Loaded %d parts. %d remaining - come back for them!", loadedCount, #remainingParts), 5, "Shop", "warning")
        else
          ui_message(string.format("Loaded %d parts into cargo! Deliver to your garage.", loadedCount), 5, "Shop", "success")
        end

        -- Set waypoint to delivery location if we loaded anything
        if loadedCount > 0 and core_groundMarkers then
          local deliveryPos = nil

          -- First try to use saved delivery location
          if state.deliveryLocation then
            deliveryPos = vec3(state.deliveryLocation.x, state.deliveryLocation.y, state.deliveryLocation.z)
            log("I", logTag, "Setting waypoint to saved delivery location")
          else
            -- Fallback: get first purchased garage position
            local garageManager = career_modules_garageManager
            if garageManager and garageManager.getPurchasedGarages and freeroam_facilities then
              local purchasedIds = garageManager.getPurchasedGarages()
              if purchasedIds and #purchasedIds > 0 then
                local garageId = purchasedIds[1]
                local garage = freeroam_facilities.getFacility("garage", garageId)
                if garage and freeroam_facilities.getAverageDoorPositionForFacility then
                  deliveryPos = freeroam_facilities.getAverageDoorPositionForFacility(garage)
                  log("I", logTag, "Setting waypoint to first purchased garage: " .. (garage.name or garageId))
                end
              end
            end
          end

          if deliveryPos then
            core_groundMarkers.setFocus(deliveryPos)
            log("I", logTag, "Waypoint set to delivery location: " .. tostring(deliveryPos))
          else
            log("W", logTag, "Could not set waypoint - no delivery location available")
          end
        end

        return
      end

      local part = partsToLoad[index]
      local cargoInfo = cargoModule.getPartCargoInfo(part.name)

      -- Check if this part will fit
      if usedSlots + cargoInfo.slots > totalFreeSlots then
        -- This part won't fit, save for later
        table.insert(remainingParts, part)
        log("I", logTag, string.format("Part '%s' won't fit (need %d, have %d free)", part.name, cargoInfo.slots, totalFreeSlots - usedSlots))
        loadNextPart(index + 1)
        return
      end

      local partData = {
        partName = part.name,
        partNiceName = part.niceName,
        vehicleModel = "etki",
        slotType = part.slotType,
        condition = { integrityValue = 1, odometer = 0, visualValue = 1 },
        baseValue = part.price,
        isIllegal = false,
      }

      -- Build destination data for the cargo system (garage where order was placed)
      local destinationData = {
        type = "mysummerGarage",
        description = "Your garage",
      }
      if state.deliveryLocation then
        destinationData.pos = state.deliveryLocation
      end

      cargoModule.loadPartIntoCargo(partData, function(success, cargoIdOrError, container)
        if success then
          loadedCount = loadedCount + 1
          usedSlots = usedSlots + cargoInfo.slots
          -- Track cargo ID for delivery
          table.insert(state.carryingParts, {
            name = part.name,
            niceName = part.niceName,
            slotType = part.slotType,
            price = part.price,
            cargoId = cargoIdOrError,
          })
          log("I", logTag, string.format("Loaded part '%s' into cargo (id=%d, slots=%d)", part.name, cargoIdOrError, cargoInfo.slots))
        else
          -- Failed to load - save for later
          table.insert(remainingParts, part)
          log("W", logTag, "Failed to load part: " .. tostring(cargoIdOrError))
        end

        -- Load next part
        loadNextPart(index + 1)
      end, destinationData)
    end

    -- Start loading parts sequentially
    loadNextPart(1)
  end)

  return { success = true, message = "Loading parts..." }
end

-- Step 2: Deliver parts at garage (unload from cargo and add to inventory)
local function deliverPartsAtGarage()
  local cargoModule = career_modules_mysummerCargo

  -- Get parts from native cargo system as primary source
  local nativeCargoParts = cargoModule and cargoModule.getMysummerCargoInVehicles() or {}

  -- Use state.carryingParts as fallback if native is empty
  local partsToDeliver = #nativeCargoParts > 0 and nativeCargoParts or state.carryingParts

  if #partsToDeliver == 0 then
    log("W", logTag, "deliverPartsAtGarage called but no parts to deliver (state=" .. #state.carryingParts .. ", native=" .. #nativeCargoParts .. ")")
    return { success = false, message = "No parts to deliver" }
  end

  local partInventory = career_modules_business_businessPartInventory
  if not partInventory or not partInventory.addPart then
    log("E", logTag, "Part inventory module not available")
    return { success = false, message = "Inventory system error" }
  end

  local deliveredCount = 0

  for _, partInfo in ipairs(partsToDeliver) do
    -- Handle both native cargo format and state.carryingParts format
    local partName = partInfo.partName or partInfo.name
    local partNiceName = partInfo.partNiceName or partInfo.niceName or partName
    local partSlot = partInfo.slotType or partInfo.slot
    local partValue = partInfo.baseValue or partInfo.price or 0
    local partCondition = partInfo.condition or { integrityValue = 1, odometer = 0, visualValue = 1 }
    local cargoId = partInfo.cargoId

    local partData = {
      name = partName,
      vehicleModel = "etki",
      partCondition = partCondition,
      slot = partSlot,
      location = 0,
      value = partValue,
      description = { description = partNiceName }
    }

    local newPartId = partInventory.addPart(partData)
    if newPartId then
      deliveredCount = deliveredCount + 1
      log("I", logTag, string.format("Added part '%s' to inventory (id=%s)", partName, tostring(newPartId)))

      -- Unload from native cargo system
      if cargoModule and cargoId then
        cargoModule.unloadCargoItem(cargoId)
        log("I", logTag, string.format("Unloaded cargo item %d for part '%s'", cargoId, partName))
      end
    else
      log("W", logTag, "Failed to add part to inventory: " .. partName)
    end
  end

  log("I", logTag, "Delivered " .. deliveredCount .. " parts to inventory")

  -- Detect first purchase -> unlock Ghost contact
  if deliveredCount > 0 then
    if career_modules_mysummerParts and career_modules_mysummerParts.hasFirstPurchase then
      if not career_modules_mysummerParts.hasFirstPurchase() then
        -- Trigger first purchase in mysummerParts module
        if career_modules_mysummerParts.triggerFirstPurchase then
          career_modules_mysummerParts.triggerFirstPurchase()
          log("I", logTag, "First online shop purchase! Triggered Ghost unlock.")
        end
      end
    end
  end

  -- Clear carrying and delivery location
  state.carryingParts = {}
  state.deliveryLocation = nil

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setFocus(nil)
  end

  -- Show notification
  if ui_message then
    ui_message("Delivered " .. deliveredCount .. " parts! Check your inventory.", 5, "Shop", "success")
  end

  saveState()
  return { success = true, count = deliveredCount }
end

-- Get current transport status
local function getTransportStatus()
  return {
    pendingPickup = state.pendingPickup,
    pendingCount = #state.pendingPickup,
    carryingParts = state.carryingParts,
    carryingCount = #state.carryingParts,
    pickupLocation = pickupLocation,
    deliveryLocation = state.deliveryLocation,
  }
end

-- ============================================================================
-- POI SYSTEM (Map markers - bigmap only, minimap requires physical objects)
-- ============================================================================

-- Called when POIs need to be refreshed
local function onGetRawPoiListForLevel(levelIdentifier, elements)
  if not career_career or not career_career.isActive() then return end

  -- Add shop POIs (kept for reference but not primary access method)
  for shopId, shop in pairs(shopDefinitions) do
    local poiData = {
      id = "mysummerPartShop_" .. shopId,
      data = {
        type = "mysummerPartShop",
        shopId = shopId,
      },
      markerInfo = {
        bigmapMarker = {
          pos = vec3(shop.pos[1], shop.pos[2], shop.pos[3]),
          name = shop.name,
          description = shop.description .. "\n\nPrice markup: " .. string.format("%.0f%%", (shop.priceMultiplier - 1) * 100),
          icon = "poi_shop_round",
          label = shop.name,
        }
      }
    }
    table.insert(elements, poiData)
  end

  -- Add pickup location POI (when there are parts waiting at port)
  if #state.pendingPickup > 0 then
    local pickupPoi = {
      id = "mysummerPartShop_pickup",
      data = {
        type = "mysummerPartShopPickup",
      },
      markerInfo = {
        bigmapMarker = {
          pos = vec3(pickupLocation.pos[1], pickupLocation.pos[2], pickupLocation.pos[3]),
          name = pickupLocation.name,
          description = "Pick up your order (" .. #state.pendingPickup .. " parts waiting)",
          icon = "poi_warehouse_round",
          label = "Parts Pickup",
        }
      }
    }
    table.insert(elements, pickupPoi)
  end

  -- Add delivery location POI (when carrying parts to deliver)
  if #state.carryingParts > 0 and state.deliveryLocation then
    local deliveryPoi = {
      id = "mysummerPartShop_delivery",
      data = {
        type = "mysummerPartShopDelivery",
      },
      markerInfo = {
        bigmapMarker = {
          pos = vec3(state.deliveryLocation.x, state.deliveryLocation.y, state.deliveryLocation.z),
          name = "Your Garage",
          description = "Deliver " .. #state.carryingParts .. " parts",
          icon = "poi_garage_round",
          label = "Parts Delivery",
        }
      }
    }
    table.insert(elements, deliveryPoi)
  end
end

-- ============================================================================
-- UPDATE LOOP (Proximity detection + prompt)
-- ============================================================================


local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Don't check while menu is open
  if state.shopMenuOpen then
    return
  end

  -- Step 1: Check if player arrived at port to pick up parts
  if #state.pendingPickup > 0 then
    local nearPickup = checkPlayerNearPickup()

    if nearPickup and not state.nearPickup then
      log("I", logTag, "Player arrived at port, picking up " .. #state.pendingPickup .. " parts")
      pickupPartsAtPort()
    end

    state.nearPickup = nearPickup
  else
    state.nearPickup = false
  end

  -- Step 2: Check if player arrived at garage to deliver parts
  -- Check both state.carryingParts AND native cargo system
  local cargoModule = career_modules_mysummerCargo
  local nativeCargoParts = cargoModule and cargoModule.getMysummerCargoInVehicles() or {}
  local hasCargoToDeliver = #state.carryingParts > 0 or #nativeCargoParts > 0

  if hasCargoToDeliver then
    local nearDelivery = checkPlayerNearDelivery()

    -- Debug log every 5 seconds
    if not state.deliveryDebugTime then state.deliveryDebugTime = 0 end
    state.deliveryDebugTime = state.deliveryDebugTime + dtReal
    if state.deliveryDebugTime >= 5 then
      log("I", logTag, string.format("Carrying: state=%d, native=%d, nearDelivery=%s, state.nearDelivery=%s, deliveryLocation=%s",
        #state.carryingParts, #nativeCargoParts, tostring(nearDelivery), tostring(state.nearDelivery),
        state.deliveryLocation and "set" or "nil"))
      state.deliveryDebugTime = 0
    end

    if nearDelivery and not state.nearDelivery then
      log("I", logTag, "Player arrived at garage, delivering parts (state=" .. #state.carryingParts .. ", native=" .. #nativeCargoParts .. ")")
      deliverPartsAtGarage()
    end

    state.nearDelivery = nearDelivery

    -- Show carrying message periodically
    local totalParts = math.max(#state.carryingParts, #nativeCargoParts)
    if not state.carryingMsgTime then state.carryingMsgTime = 0 end
    state.carryingMsgTime = state.carryingMsgTime + dtReal
    if state.carryingMsgTime >= 30 then  -- Every 30 seconds
      guihooks.trigger("Message", {
        ttl = 5,
        msg = "Carrying " .. totalParts .. " parts - deliver to garage",
        category = "partsCarrying",
        icon = "inventory_2"
      })
      state.carryingMsgTime = 0
    end
  else
    state.nearDelivery = false
    state.carryingMsgTime = nil
    state.deliveryDebugTime = nil
  end

  -- Update nearShop state
  state.nearShop = checkPlayerNearShop()
end

-- ============================================================================
-- INPUT HANDLING - Using the freeroam interaction system
-- ============================================================================

-- This is called by the base game when player uses interaction key near facilities
local function onActivityAcceptGatherData(elemData, activityData)
  log("I", logTag, "onActivityAcceptGatherData called, pendingPickup=" .. #state.pendingPickup .. ", nearPickup=" .. tostring(checkPlayerNearPickup()))

  -- Check if player is near pickup location (priority over shops)
  if #state.pendingPickup > 0 and checkPlayerNearPickup() then
    local pickupData = {
      icon = "poi_warehouse_round",
      heading = pickupLocation.name,
      preheadings = {"Parts Pickup"},
      sorting = {
        type = "mysummerPartShopPickup",
        order = 40,
        id = "pickup"
      },
      props = {
        {
          icon = "inventory_2",
          keyLabel = "Parts Waiting",
          valueLabel = tostring(#state.pendingPickup)
        }
      },
      buttonLabel = "Collect Parts",
      buttonFun = function()
        local result = collectPendingParts()
        if result.success then
          -- Save state after collecting
          saveState()
        end
      end
    }
    table.insert(activityData, pickupData)
  end

  -- Check if player is near any of our shops
  local nearShop = checkPlayerNearShop()
  if not nearShop then return end

  local shop = shopDefinitions[nearShop]
  if not shop then return end

  -- Add our shop to the activity prompt
  local data = {
    icon = "poi_shop_round",
    heading = shop.name,
    preheadings = {"Parts Shop"},
    sorting = {
      type = "mysummerPartShop",
      order = 50,
      id = nearShop
    },
    props = {
      {
        icon = "monetization_on",
        keyLabel = "Price Markup",
        valueLabel = string.format("%.0f%%", (shop.priceMultiplier - 1) * 100)
      }
    },
    buttonLabel = "Enter Shop",
    buttonFun = function()
      openShopMenu(nearShop)
    end
  }

  if shop.limitedStock then
    table.insert(data.props, {
      icon = "inventory_2",
      keyLabel = "Stock",
      valueLabel = "Limited (parts under $500)"
    })
  end

  table.insert(activityData, data)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Get list of all shops with their info
local function getShops()
  local shops = {}
  for shopId, shop in pairs(shopDefinitions) do
    table.insert(shops, {
      id = shopId,
      name = shop.name,
      description = shop.description,
      priceMultiplier = shop.priceMultiplier,
      pos = shop.pos,
    })
  end
  return shops
end

-- Get current shop player is near
local function getNearShop()
  return state.nearShop
end

-- Check if shop menu is open
local function isShopOpen()
  return state.shopMenuOpen
end

-- Get pending orders status (for UI to show "My Orders" section)
local function getPendingOrders()
  local orders = {
    pendingPickup = {},  -- At port waiting to be collected
    carrying = {},       -- Currently in vehicle cargo
    totalPendingCount = #state.pendingPickup,
    totalCarryingCount = #state.carryingParts,
  }

  -- Parts waiting at port
  for _, part in ipairs(state.pendingPickup) do
    table.insert(orders.pendingPickup, {
      name = part.name,
      niceName = part.niceName,
      slotType = part.slotType,
      price = part.price,
    })
  end

  -- Parts in cargo (being transported)
  for _, part in ipairs(state.carryingParts) do
    table.insert(orders.carrying, {
      name = part.name,
      niceName = part.niceName,
      slotType = part.slotType,
      price = part.price,
      cargoId = part.cargoId,
    })
  end

  -- Add pickup location info if there are pending parts
  if #state.pendingPickup > 0 then
    orders.pickupLocation = {
      name = pickupLocation.name,
      pos = pickupLocation.pos,
    }
  end

  -- Add delivery location if carrying parts
  if #state.carryingParts > 0 and state.deliveryLocation then
    orders.deliveryLocation = state.deliveryLocation
  end

  return orders
end

-- Set waypoint to pickup location
local function setWaypointToPickup()
  if core_groundMarkers then
    local pos = vec3(pickupLocation.pos[1], pickupLocation.pos[2], pickupLocation.pos[3])
    core_groundMarkers.setFocus(pos)
    ui_message("Waypoint set to " .. pickupLocation.name, 3, "Shop", "success")
  end
end

-- Set waypoint to delivery location (any purchased garage)
local function setWaypointToDelivery()
  if not core_groundMarkers then return end

  local deliveryPos = nil

  -- First try saved delivery location
  if state.deliveryLocation then
    deliveryPos = vec3(state.deliveryLocation.x, state.deliveryLocation.y, state.deliveryLocation.z)
  else
    -- Fallback: get first purchased garage position
    local garageManager = career_modules_garageManager
    if garageManager and garageManager.getPurchasedGarages and freeroam_facilities then
      local purchasedIds = garageManager.getPurchasedGarages()
      if purchasedIds and #purchasedIds > 0 then
        local garageId = purchasedIds[1]
        local garage = freeroam_facilities.getFacility("garage", garageId)
        if garage and freeroam_facilities.getAverageDoorPositionForFacility then
          deliveryPos = freeroam_facilities.getAverageDoorPositionForFacility(garage)
        end
      end
    end
  end

  if deliveryPos then
    core_groundMarkers.setFocus(deliveryPos)
    ui_message("Waypoint set to your garage", 3, "Shop", "success")
  else
    ui_message("No garage found for delivery", 3, "Shop", "warning")
  end
end

-- Called when career save happens
local function onSaveCareerData(currentSavePath)
  saveState(currentSavePath)
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Part Shops module loaded")
end

local function onCareerActive(enabled)
  if enabled then
    log("I", logTag, "Part Shops initialized")
    -- Load saved state
    loadState()
    -- Pre-build parts cache
    buildPartsCache()
  else
    state.nearShop = nil
    state.shopMenuOpen = false
    state.pendingPickup = {}
    state.carryingParts = {}
    state.deliveryLocation = nil
    state.nearPickup = false
    state.nearDelivery = false
  end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onUpdate = onUpdate
M.onSaveCareerData = onSaveCareerData

-- POI hooks
M.onGetRawPoiListForLevel = onGetRawPoiListForLevel
M.onActivityAcceptGatherData = onActivityAcceptGatherData

-- Public API
M.getShops = getShops
M.getNearShop = getNearShop
M.isShopOpen = isShopOpen
M.openShopMenu = openShopMenu
M.closeShopMenu = closeShopMenu
M.purchasePart = purchasePart
M.getShopParts = getShopParts

-- Online shop API
M.getOnlineShopParts = getOnlineShopParts
M.placeOnlineOrder = placeOnlineOrder
M.getTransportStatus = getTransportStatus
M.getRequiredChildParts = getRequiredChildParts  -- For UI to show required child parts
M.playerOwnsPart = playerOwnsPart  -- For UI to check ownership

-- Orders API (for "My Orders" UI)
M.getPendingOrders = getPendingOrders
M.setWaypointToPickup = setWaypointToPickup
M.setWaypointToDelivery = setWaypointToDelivery

-- Cancel pending order and refund
local function cancelPendingOrder(partIndex)
  if not partIndex or partIndex < 1 or partIndex > #state.pendingPickup then
    return { success = false, message = "Invalid part index" }
  end

  local part = state.pendingPickup[partIndex]
  if not part then
    return { success = false, message = "Part not found" }
  end

  local refundAmount = part.price or 0

  -- Refund the money
  if refundAmount > 0 and career_modules_payment and career_modules_payment.reward then
    career_modules_payment.reward(
      {money = {amount = refundAmount}},
      {label = "Order Cancelled - Refund", tags = {"refund", "parts"}}
    )
    log("I", logTag, "Refunded $" .. refundAmount .. " for cancelled part: " .. (part.niceName or part.name))
  end

  -- Remove from pending
  table.remove(state.pendingPickup, partIndex)
  saveState()

  return { success = true, refundAmount = refundAmount, message = "Order cancelled, $" .. refundAmount .. " refunded" }
end

-- Cancel all pending orders
local function cancelAllPendingOrders()
  local totalRefund = 0
  local count = #state.pendingPickup

  for _, part in ipairs(state.pendingPickup) do
    totalRefund = totalRefund + (part.price or 0)
  end

  if totalRefund > 0 and career_modules_payment and career_modules_payment.reward then
    career_modules_payment.reward(
      {money = {amount = totalRefund}},
      {label = "All Orders Cancelled - Refund", tags = {"refund", "parts"}}
    )
    log("I", logTag, "Refunded $" .. totalRefund .. " for " .. count .. " cancelled parts")
  end

  state.pendingPickup = {}
  saveState()

  return { success = true, refundAmount = totalRefund, count = count }
end

M.cancelPendingOrder = cancelPendingOrder
M.cancelAllPendingOrders = cancelAllPendingOrders

-- Handle towing - move carryingParts back to pendingPickup
local function onVehicleTowed(vehId)
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh or playerVeh:getID() ~= vehId then return end

  -- Check if we have cargo in the vehicle
  local cargoModule = career_modules_mysummerCargo
  local nativeCargoParts = cargoModule and cargoModule.getMysummerCargoInVehicles() or {}

  if #state.carryingParts > 0 or #nativeCargoParts > 0 then
    log("I", logTag, "Vehicle towed with cargo! Moving parts back to pendingPickup")

    -- Move state.carryingParts back
    for _, part in ipairs(state.carryingParts) do
      table.insert(state.pendingPickup, part)
    end
    state.carryingParts = {}

    -- Unload native cargo and move to pendingPickup
    for _, part in ipairs(nativeCargoParts) do
      table.insert(state.pendingPickup, {
        name = part.partName,
        niceName = part.partNiceName,
        slotType = part.slotType,
        price = part.baseValue or 0,
      })
      if cargoModule and part.cargoId then
        cargoModule.unloadCargoItem(part.cargoId)
      end
    end

    saveState()
    ui_message("Your cargo was returned to the warehouse for pickup.", 5, "Shop", "warning")
  end
end

M.onVehicleTowed = onVehicleTowed

-- DEBUG: Dump all available slots for etki
local function dumpAllSlots()
  local slots = {}
  local allParts = jbeamIO.getAvailableParts("etki")
  if allParts then
    for slotType, partsList in pairs(allParts) do
      slots[slotType] = #partsList
    end
  end
  -- Sort and print
  local sortedSlots = {}
  for slot, count in pairs(slots) do
    table.insert(sortedSlots, {slot = slot, count = count})
  end
  table.sort(sortedSlots, function(a, b) return a.slot < b.slot end)

  log("I", logTag, "=== ALL AVAILABLE SLOTS FOR ETKI ===")
  for _, item in ipairs(sortedSlots) do
    log("I", logTag, string.format("  %s (%d parts)", item.slot, item.count))
  end
  log("I", logTag, "=== END SLOTS ===")
  return slots
end
M.dumpAllSlots = dumpAllSlots

return M
