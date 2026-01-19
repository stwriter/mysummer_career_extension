-- mysummerProjectPartShop.lua
-- Independent Part Shop for the MySummer project vehicle
-- Completely separate from career_modules_partShopping to avoid conflicts

local M = {}

M.dependencies = {
  "career_career",
  "career_modules_inventory",
  "career_modules_payment",
  "career_modules_business_businessPartInventory",
}

local jbeamIO = require("jbeam/io")

-- Shop state
local shopState = {
  isOpen = false,
  inventoryId = nil,
  vehicleId = nil,

  -- Parts organized by slot type
  slotCategories = {},  -- { slotType = { niceName, parts = [...] } }

  -- Shopping cart
  cart = {
    items = {},      -- { partId, name, niceName, slotType, price, source }
    subtotal = 0,
    taxes = 0,
    total = 0,
  },

  playerMoney = 0,
  originComputerId = nil,

  -- Original config for preview mode (restore on cancel)
  originalConfig = nil,
  modelKey = nil,
}

-- Tax rate
local TAX_RATE = 0.07

-- Wheel/tire patterns (purchasable from shop)
local wheelTirePatterns = { "wheel", "tire", "rim", "hubcap" }

local function isWheelTireSlot(slotType)
  if not slotType or type(slotType) ~= "string" then return false end
  local slotLower = string.lower(slotType)
  for _, pattern in ipairs(wheelTirePatterns) do
    if string.find(slotLower, pattern) then
      return true
    end
  end
  return false
end

-- Get nice name for a slot type
local function getSlotNiceName(slotType)
  if not slotType then return "Unknown" end

  -- Common slot type mappings
  local niceNames = {
    engine = "Engine",
    transmission = "Transmission",
    wheel_FL = "Front Left Wheel",
    wheel_FR = "Front Right Wheel",
    wheel_RL = "Rear Left Wheel",
    wheel_RR = "Rear Right Wheel",
    tire_FL = "Front Left Tire",
    tire_FR = "Front Right Tire",
    tire_RL = "Rear Left Tire",
    tire_RR = "Rear Right Tire",
    suspension_F = "Front Suspension",
    suspension_R = "Rear Suspension",
    brakes_F = "Front Brakes",
    brakes_R = "Rear Brakes",
    exhaust = "Exhaust",
    intake = "Intake",
    turbo = "Turbo",
    hood = "Hood",
    trunk = "Trunk",
    bumper_F = "Front Bumper",
    bumper_R = "Rear Bumper",
    fender_L = "Left Fender",
    fender_R = "Right Fender",
    door_L = "Left Door",
    door_R = "Right Door",
    mirror_L = "Left Mirror",
    mirror_R = "Right Mirror",
    radiator = "Radiator",
    fuel_tank = "Fuel Tank",
    differential = "Differential",
    driveshaft = "Driveshaft",
  }

  if niceNames[slotType] then
    return niceNames[slotType]
  end

  -- Fallback: capitalize and replace underscores
  local nice = slotType:gsub("_", " ")
  nice = nice:gsub("(%a)([%w]*)", function(a, b) return string.upper(a) .. b end)
  return nice
end

-- Build inventory lookup by part name
local function buildOwnedPartsLookup(vehicleModel)
  local lookup = {}
  if not career_modules_business_businessPartInventory then return lookup end

  local allParts = career_modules_business_businessPartInventory.getInventory() or {}
  for partId, part in pairs(allParts) do
    -- Only parts for this model that are in storage (not on a vehicle)
    if part.vehicleModel == vehicleModel and (part.location == 0 or part.location == nil) then
      local partName = part.name
      if not lookup[partName] then
        lookup[partName] = {}
      end

      local niceName = part.name
      if part.description and part.description.description then
        niceName = part.description.description
      end

      table.insert(lookup[partName], {
        partId = partId,
        name = partName,
        niceName = niceName,
        condition = part.partCondition or { integrityValue = 1, visualValue = 1, odometer = 0 },
        slot = part.slot or part.slotType,
      })
    end
  end

  return lookup
end

-- Recursively process partsTree to build slot list
local function processPartsTree(node, path, availableParts, ownedLookup, ioCtx, slotsNiceName, result, parentSlotName)
  if not node then return end

  local isRootNode = (path == "/")

  -- Process children first (they contain the actual slots)
  if node.children then
    for slotName, childNode in pairs(node.children) do
      local childPath = path .. slotName .. "/"

      -- Get slot nice name
      local slotNiceName = slotsNiceName[slotName] or getSlotNiceName(slotName)

      -- Get currently installed part info
      local installedPartName = childNode.chosenPartName
      local installedPartNiceName = installedPartName
      local installedPartValue = 0

      if installedPartName and availableParts[installedPartName] then
        local partInfo = availableParts[installedPartName]
        local desc = partInfo.description
        installedPartNiceName = type(desc) == "table" and desc.description or desc or installedPartName
        -- Get value from jbeam for installed part
        local jbeamData = jbeamIO.getPart(ioCtx, installedPartName)
        if jbeamData and jbeamData.information and jbeamData.information.value then
          installedPartValue = tonumber(jbeamData.information.value) or 0
        elseif partInfo.information and partInfo.information.value then
          installedPartValue = tonumber(partInfo.information.value) or 0
        end
      end

      -- Build list of available parts for this slot
      local slotParts = {}
      local suitableNames = childNode.suitablePartNames or {}

      for _, partName in ipairs(suitableNames) do
        local partInfo = availableParts[partName]
        if partInfo then
          local desc = partInfo.description
          local niceName = type(desc) == "table" and desc.description or desc or partName

          -- Get value from jbeam
          local value = 0
          local jbeamData = jbeamIO.getPart(ioCtx, partName)
          if jbeamData and jbeamData.information and jbeamData.information.value then
            value = tonumber(jbeamData.information.value) or 0
          elseif partInfo.information and partInfo.information.value then
            value = tonumber(partInfo.information.value) or 0
          end

          local isInstalled = (installedPartName == partName)
          local ownedVariants = ownedLookup[partName]
          local hasOwned = ownedVariants and #ownedVariants > 0

          -- Only add if it's a wheel/tire slot OR if we have it in inventory
          local isWheelTire = isWheelTireSlot(slotName)

          if isWheelTire or hasOwned or isInstalled then
            table.insert(slotParts, {
              id = hasOwned and ("inv_" .. ownedVariants[1].partId) or ("shop_" .. partName),
              partId = hasOwned and ownedVariants[1].partId or nil,
              name = partName,
              niceName = niceName,
              price = hasOwned and 0 or value,  -- Free if owned, otherwise shop price
              source = hasOwned and "inventory" or "shop",
              installed = isInstalled,
              hasOwned = hasOwned,
              ownedVariants = ownedVariants,
            })
          end
        end
      end

      -- Only add slot if it has parts or is installed
      if #slotParts > 0 or installedPartName then
        -- Sort: installed first, then owned, then by name
        table.sort(slotParts, function(a, b)
          if a.installed and not b.installed then return true end
          if not a.installed and b.installed then return false end
          if a.source == "inventory" and b.source ~= "inventory" then return true end
          if a.source ~= "inventory" and b.source == "inventory" then return false end
          return (a.niceName or "") < (b.niceName or "")
        end)

        table.insert(result, {
          path = childPath,
          slotName = slotName,
          slotNiceName = slotNiceName,
          installedPart = installedPartName,
          installedPartNiceName = installedPartNiceName,
          installedPartValue = installedPartValue,
          parts = slotParts,
          partCount = #slotParts,
          parentSlot = parentSlotName,
        })
      end

      -- Recurse into children
      processPartsTree(childNode, childPath, availableParts, ownedLookup, ioCtx, slotsNiceName, result, slotName)
    end
  end
end

-- Build the shop data from vehicle's actual partsTree
local function buildShopData()
  shopState.slotCategories = {}

  -- Get player money
  if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
    shopState.playerMoney = career_modules_playerAttributes.getAttributeValue("money") or 0
  end

  -- Need a spawned vehicle
  if not shopState.vehicleId then
    log("E", "mysummerProjectPartShop", "No vehicle ID for building shop data")
    return
  end

  -- Get vehicle data from BeamNG
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(shopState.vehicleId)
  if not vehicleData or not vehicleData.config or not vehicleData.config.partsTree then
    log("E", "mysummerProjectPartShop", "Could not get vehicle partsTree")
    return
  end

  local partsTree = vehicleData.config.partsTree
  local ioCtx = vehicleData.ioCtx
  local availableParts = jbeamIO.getAvailableParts(ioCtx) or {}

  -- Get vehicle model
  local vehObj = be:getObjectByID(shopState.vehicleId)
  local vehicleModel = vehObj and vehObj:getJBeamFilename() or "etki"

  -- Build slot nice names from parts info
  local slotsNiceName = {}
  for partName, partInfo in pairs(availableParts) do
    if partInfo.slotInfoUi then
      for slotName, slotInfo in pairs(partInfo.slotInfoUi) do
        if type(slotInfo) == "table" and slotInfo.description then
          slotsNiceName[slotName] = type(slotInfo.description) == "table" and slotInfo.description.description or slotInfo.description
        elseif type(slotInfo) == "string" then
          slotsNiceName[slotName] = slotInfo
        end
      end
    end
  end

  -- Build owned parts lookup
  local ownedLookup = buildOwnedPartsLookup(vehicleModel)

  -- Process the parts tree
  local slotsList = {}
  processPartsTree(partsTree, "/", availableParts, ownedLookup, ioCtx, slotsNiceName, slotsList, nil)

  -- Convert to categories format for UI
  for _, slot in ipairs(slotsList) do
    shopState.slotCategories[slot.path] = {
      slotType = slot.slotName,
      path = slot.path,
      niceName = slot.slotNiceName,
      installedPart = slot.installedPart,
      installedPartNiceName = slot.installedPartNiceName,
      installedPartValue = slot.installedPartValue or 0,
      parts = slot.parts,
      partCount = slot.partCount,
      parentSlot = slot.parentSlot,
    }
  end

  log("I", "mysummerProjectPartShop", string.format("Built shop data: %d slots from vehicle partsTree", tableSize(shopState.slotCategories)))
end

-- Rebuild shop data with cart items simulated as installed
-- This allows the UI to show child slots that will become available after checkout
local function rebuildWithCartSimulation()
  if not shopState.vehicleId then return end

  -- Get vehicle data
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(shopState.vehicleId)
  if not vehicleData or not vehicleData.config or not vehicleData.config.partsTree then
    return
  end

  -- Deep copy the partsTree so we can modify it
  local simulatedTree = deepcopy(vehicleData.config.partsTree)
  local ioCtx = vehicleData.ioCtx
  local availableParts = jbeamIO.getAvailableParts(ioCtx) or {}

  -- Helper to get node from path
  local function getNodeFromPath(tree, path)
    if not tree or not path then return nil end
    if path == "/" then return tree end

    local segments = {}
    for segment in string.gmatch(path, "[^/]+") do
      table.insert(segments, segment)
    end

    local currentNode = tree
    for _, segment in ipairs(segments) do
      if currentNode.children and currentNode.children[segment] then
        currentNode = currentNode.children[segment]
      else
        return nil
      end
    end
    return currentNode
  end

  -- Apply cart items to simulated tree (simulate installations)
  local simulatedInstalls = 0
  for _, item in ipairs(shopState.cart.items) do
    if item.action ~= "uninstall" and item.slotPath and item.name then
      local node = getNodeFromPath(simulatedTree, item.slotPath)
      if node then
        node.chosenPartName = item.name
        node.emptyPlaceholder = nil
        simulatedInstalls = simulatedInstalls + 1
        log("D", "mysummerProjectPartShop", "Simulated install: " .. item.name .. " at " .. item.slotPath)
      end
    end
  end

  if simulatedInstalls == 0 then
    -- No simulations needed, just use current data
    return
  end

  -- Get vehicle model
  local vehObj = be:getObjectByID(shopState.vehicleId)
  local vehicleModel = vehObj and vehObj:getJBeamFilename() or "etki"

  -- Build slot nice names
  local slotsNiceName = {}
  for partName, partInfo in pairs(availableParts) do
    if partInfo.slotInfoUi then
      for slotName, slotInfo in pairs(partInfo.slotInfoUi) do
        if type(slotInfo) == "table" and slotInfo.description then
          slotsNiceName[slotName] = type(slotInfo.description) == "table" and slotInfo.description.description or slotInfo.description
        elseif type(slotInfo) == "string" then
          slotsNiceName[slotName] = slotInfo
        end
      end
    end
  end

  -- Build owned parts lookup
  local ownedLookup = buildOwnedPartsLookup(vehicleModel)

  -- Process the simulated tree
  local slotsList = {}
  processPartsTree(simulatedTree, "/", availableParts, ownedLookup, ioCtx, slotsNiceName, slotsList, nil)

  -- Update categories
  shopState.slotCategories = {}
  for _, slot in ipairs(slotsList) do
    shopState.slotCategories[slot.path] = {
      slotType = slot.slotName,
      path = slot.path,
      niceName = slot.slotNiceName,
      installedPart = slot.installedPart,
      installedPartNiceName = slot.installedPartNiceName,
      installedPartValue = slot.installedPartValue or 0,
      parts = slot.parts,
      partCount = slot.partCount,
      parentSlot = slot.parentSlot,
    }
  end

  log("I", "mysummerProjectPartShop", string.format("Rebuilt with %d simulated installs: %d slots", simulatedInstalls, tableSize(shopState.slotCategories)))
end

-- Apply cart changes to vehicle in real-time (preview mode)
-- The vehicle is respawned with cart items installed/uninstalled
local function applyCartPreview()
  if not shopState.originalConfig or not shopState.vehicleId then
    log("W", "mysummerProjectPartShop", "Cannot apply preview - no original config")
    return
  end

  -- Start from original config
  local previewConfig = deepcopy(shopState.originalConfig)

  -- Helper to get node from path
  local function getNodeFromPath(tree, path)
    if not tree or not path then return nil end
    if path == "/" then return tree end

    local segments = {}
    for segment in string.gmatch(path, "[^/]+") do
      table.insert(segments, segment)
    end

    local currentNode = tree
    for _, segment in ipairs(segments) do
      if currentNode.children and currentNode.children[segment] then
        currentNode = currentNode.children[segment]
      else
        return nil
      end
    end
    return currentNode
  end

  -- Apply cart items to preview config
  local changes = 0
  for _, item in ipairs(shopState.cart.items) do
    if item.slotPath and previewConfig.partsTree then
      local node = getNodeFromPath(previewConfig.partsTree, item.slotPath)
      if node then
        if item.action == "uninstall" then
          -- Uninstall: set to empty
          node.chosenPartName = ""
          node.emptyPlaceholder = true
        else
          -- Install: set part name
          node.chosenPartName = item.name
          node.emptyPlaceholder = nil
        end
        changes = changes + 1
      end
    end
  end

  -- Get vehicle object
  local vehObj = be:getObjectByID(shopState.vehicleId)
  if not vehObj then
    log("W", "mysummerProjectPartShop", "Vehicle not found for preview")
    return
  end

  -- Always respawn - even if no changes, restore to original config
  if changes == 0 then
    log("I", "mysummerProjectPartShop", "Cart empty - restoring original config")
  else
    log("I", "mysummerProjectPartShop", "Applying cart preview with " .. changes .. " changes...")
  end

  local spawnOptions = {
    config = previewConfig,
    keepOtherVehRotation = true,
  }

  core_vehicles.replaceVehicle(shopState.modelKey, spawnOptions, vehObj)

  -- Schedule rebuild of shop data after respawn
  shopState.pendingPreviewRebuild = true
  shopState.pendingPreviewDelay = 0.3
end

-- Calculate cart totals
local function updateCartTotals()
  local subtotal = 0
  for _, item in ipairs(shopState.cart.items) do
    subtotal = subtotal + (item.price or 0)
  end

  shopState.cart.subtotal = subtotal
  shopState.cart.taxes = math.floor(subtotal * TAX_RATE * 100) / 100
  shopState.cart.total = subtotal + shopState.cart.taxes
end

-- Send shop data to Vue
local function sendShopDataToUI()
  -- Convert slotCategories to array for Vue (include all fields)
  local categories = {}
  for path, slot in pairs(shopState.slotCategories) do
    table.insert(categories, {
      path = slot.path,
      slotType = slot.slotType,
      niceName = slot.niceName,
      installedPart = slot.installedPart,
      installedPartNiceName = slot.installedPartNiceName,
      installedPartValue = slot.installedPartValue or 0,
      parts = slot.parts or {},
      partCount = slot.partCount or 0,
      parentSlot = slot.parentSlot,
    })
  end

  -- Sort categories by nice name
  table.sort(categories, function(a, b)
    return (a.niceName or "") < (b.niceName or "")
  end)

  local data = {
    isOpen = shopState.isOpen,
    categories = categories,
    cart = shopState.cart,
    playerMoney = shopState.playerMoney,
  }

  log("I", "mysummerProjectPartShop", string.format(
    "Sending shop data: %d slots, cart total: %.2f",
    #categories, shopState.cart.total
  ))

  guihooks.trigger("mysummerProjectShopData", data)
end

-- Open the shop
local function openShop(inventoryId, computerId)
  log("I", "mysummerProjectPartShop", "Opening shop for inventory: " .. tostring(inventoryId))

  -- Get project inventory from mysummerParts if not provided
  if not inventoryId then
    local mysummerParts = extensions.career_modules_mysummerParts
    if mysummerParts and mysummerParts.getProjectPartsData then
      local data = mysummerParts.getProjectPartsData()
      if data and data.projectInventoryId then
        inventoryId = data.projectInventoryId
      end
    end
  end

  if not inventoryId then
    log("E", "mysummerProjectPartShop", "No inventory ID provided")
    ui_message("Cannot open shop - no project vehicle found", 4, "Parts Shop", "error")
    return false
  end

  -- Get vehicle ID
  local vehicleId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
  if not vehicleId then
    log("E", "mysummerProjectPartShop", "Vehicle not spawned")
    ui_message("Cannot open shop - vehicle not spawned", 4, "Parts Shop", "error")
    return false
  end

  -- Store state
  shopState.isOpen = true
  shopState.inventoryId = inventoryId
  shopState.vehicleId = vehicleId
  shopState.originComputerId = computerId

  -- Save original config for preview mode (restore on cancel)
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehicleId)
  if vehicleData and vehicleData.config then
    shopState.originalConfig = deepcopy(vehicleData.config)
    shopState.modelKey = vehicleData.config.mainPartName or "etki"
    log("I", "mysummerProjectPartShop", "Saved original config for preview mode")
  end

  -- Clear cart
  shopState.cart = {
    items = {},
    subtotal = 0,
    taxes = 0,
    total = 0,
  }

  -- Build shop data
  buildShopData()

  -- Navigate to our custom shop view
  log("I", "mysummerProjectPartShop", "Triggering ChangeState to mysummer-project-shop")
  if guihooks and guihooks.trigger then
    guihooks.trigger("ChangeState", { state = "mysummer-project-shop" })
    log("I", "mysummerProjectPartShop", "ChangeState triggered successfully")
  else
    log("E", "mysummerProjectPartShop", "guihooks.trigger not available!")
  end

  -- Set flag to send data after delay (handled in onUpdate)
  shopState.pendingSendDelay = 0.5  -- seconds

  return true
end

-- Helper: Get all child parts that would be installed with a parent part
-- This checks the jbeam structure (slots2) to find required/default child parts
local function getChildPartsForPart(partName, ioCtx, availableParts, ownedLookup)
  local childParts = {}
  
  if not partName or not ioCtx or not availableParts then
    return childParts
  end
  
  -- Get jbeam data for this part
  local jbeamData = jbeamIO.getPart(ioCtx, partName)
  if not jbeamData then
    log("D", "mysummerProjectPartShop", "No jbeam data for part: " .. partName)
    return childParts
  end
  
  -- BeamNG uses slots2 for slot definitions with default parts
  if jbeamData.slots2 then
    log("D", "mysummerProjectPartShop", "Checking slots2 for part: " .. partName .. " (" .. #jbeamData.slots2 .. " slots)")
    for _, slotDef in ipairs(jbeamData.slots2) do
      if type(slotDef) == "table" then
        local slotName = slotDef.name or slotDef.type
        local defaultPart = slotDef.default
        
        -- If there's a default part for this slot, it will be auto-installed
        if defaultPart and defaultPart ~= "" then
          -- Check if player owns this part
          local isOwned = ownedLookup and ownedLookup[defaultPart] and #ownedLookup[defaultPart] > 0
          
          -- Get part info
          local childPartInfo = availableParts[defaultPart]
          local childValue = 0
          local childNiceName = defaultPart
          
          if childPartInfo then
            if childPartInfo.information and childPartInfo.information.value then
              childValue = tonumber(childPartInfo.information.value) or 0
            end
            local desc = childPartInfo.description
            childNiceName = type(desc) == "table" and desc.description or desc or defaultPart
          end
          
          -- Only charge if not owned and has value
          if not isOwned and childValue > 0 then
            table.insert(childParts, {
              name = defaultPart,
              niceName = childNiceName,
              price = childValue,
              slotType = slotName,
              source = "shop",
              isChildPart = true,
            })
            log("I", "mysummerProjectPartShop", "Found child part: " .. childNiceName .. " (price: " .. childValue .. ")")
          elseif isOwned then
            log("D", "mysummerProjectPartShop", "Child part owned, skipping: " .. defaultPart)
          end
          
          -- Recursively check this child part's children
          local grandChildren = getChildPartsForPart(defaultPart, ioCtx, availableParts, ownedLookup)
          for _, grandChild in ipairs(grandChildren) do
            table.insert(childParts, grandChild)
          end
        end
      end
    end
  end
  
  -- Also check slotInfoUi for slots this part provides
  if jbeamData.slotInfoUi then
    log("D", "mysummerProjectPartShop", "Checking slotInfoUi for part: " .. partName)
    for slotName, slotInfo in pairs(jbeamData.slotInfoUi) do
      -- slotInfoUi doesn't have default parts info, but we can check if any of our
      -- available parts are set as default via slots2 or the part descriptions
      -- This is handled by the slots2 check above
    end
  end
  
  return childParts
end

-- Add item to cart
local function addToCart(partId)
  log("I", "mysummerProjectPartShop", "addToCart called with: " .. tostring(partId))

  if not shopState.isOpen then
    log("W", "mysummerProjectPartShop", "addToCart called but shop not open")
    return false
  end

  -- Find the part in categories
  local foundPart = nil
  local foundSlotPath = nil
  local searchedSlots = 0
  for path, category in pairs(shopState.slotCategories) do
    searchedSlots = searchedSlots + 1
    if category.parts then
      for _, part in pairs(category.parts) do
        if part.id == partId then
          foundPart = part
          foundSlotPath = path
          log("I", "mysummerProjectPartShop", "Found part in slot: " .. tostring(path))
          break
        end
      end
    end
    if foundPart then break end
  end

  log("I", "mysummerProjectPartShop", "Searched " .. searchedSlots .. " slots, found: " .. tostring(foundPart ~= nil))

  if not foundPart then
    log("W", "mysummerProjectPartShop", "Part not found: " .. tostring(partId))
    return false
  end

  -- Check if this exact part is already in cart
  for _, item in ipairs(shopState.cart.items) do
    if item.id == partId then
      log("I", "mysummerProjectPartShop", "Part already in cart: " .. partId)
      return false
    end
  end

  -- Remove any existing cart item for this slot (can only have one part per slot)
  -- Also remove any uninstall for this slot (installing replaces uninstall)
  for i = #shopState.cart.items, 1, -1 do
    local item = shopState.cart.items[i]
    if item.slotPath == foundSlotPath then
      log("I", "mysummerProjectPartShop", "Removing existing cart item for slot: " .. item.niceName)
      table.remove(shopState.cart.items, i)
    end
  end

  -- Add main part to cart
  table.insert(shopState.cart.items, {
    id = foundPart.id,
    partId = foundPart.partId,
    name = foundPart.name,
    niceName = foundPart.niceName,
    slotType = foundPart.slotType,
    slotPath = foundSlotPath,
    price = foundPart.price,
    source = foundPart.source,
  })

  log("I", "mysummerProjectPartShop", "Added to cart: " .. foundPart.niceName)

  -- If this is a shop purchase (not from inventory), check for child parts that need to be purchased too
  if foundPart.source == "shop" then
    local vehicleData = extensions.core_vehicle_manager.getVehicleData(shopState.vehicleId)
    if vehicleData and vehicleData.ioCtx then
      local ioCtx = vehicleData.ioCtx
      local availableParts = jbeamIO.getAvailableParts(ioCtx) or {}
      
      -- Build owned lookup
      local vehObj = be:getObjectByID(shopState.vehicleId)
      local vehicleModel = vehObj and vehObj:getJBeamFilename() or "etki"
      local ownedLookup = buildOwnedPartsLookup(vehicleModel)
      
      -- Get child parts that would be auto-installed
      local childParts = getChildPartsForPart(foundPart.name, ioCtx, availableParts, ownedLookup)
      
      if #childParts > 0 then
        log("I", "mysummerProjectPartShop", "Adding " .. #childParts .. " child parts to cart")
        
        for _, childPart in ipairs(childParts) do
          -- Check if this child part is already in cart
          local alreadyInCart = false
          for _, item in ipairs(shopState.cart.items) do
            if item.name == childPart.name then
              alreadyInCart = true
              break
            end
          end
          
          if not alreadyInCart then
            table.insert(shopState.cart.items, {
              id = "child_" .. foundPart.id .. "_" .. childPart.name,
              name = childPart.name,
              niceName = childPart.niceName .. " (required)",
              slotType = childPart.slotType,
              slotPath = foundSlotPath,  -- Same slot path as parent
              price = childPart.price,
              source = "shop",
              isChildPart = true,
              parentPartId = foundPart.id,
            })
            log("I", "mysummerProjectPartShop", "Added child part: " .. childPart.niceName .. " ($" .. childPart.price .. ")")
          end
        end
      end
    end
  end

  updateCartTotals()

  -- Apply changes to vehicle in real-time (preview mode)
  applyCartPreview()

  return true
end

-- Add uninstall to cart (remove installed part)
local function addUninstallToCart(slotPath)
  log("I", "mysummerProjectPartShop", "addUninstallToCart called for slot: " .. tostring(slotPath))

  if not shopState.isOpen then
    return false
  end

  -- Find the slot
  local category = shopState.slotCategories[slotPath]
  if not category then
    log("W", "mysummerProjectPartShop", "Slot not found: " .. tostring(slotPath))
    return false
  end

  -- Check if there is an installed part
  if not category.installedPart or category.installedPart == "" then
    log("W", "mysummerProjectPartShop", "No part installed in slot: " .. tostring(slotPath))
    return false
  end

  local uninstallId = "uninstall_" .. slotPath

  -- Check if already in cart
  for _, item in ipairs(shopState.cart.items) do
    if item.id == uninstallId then
      log("I", "mysummerProjectPartShop", "Uninstall already in cart for: " .. slotPath)
      return false
    end
  end

  -- Add uninstall action to cart (store installed part info for inventory transfer)
  table.insert(shopState.cart.items, {
    id = uninstallId,
    name = "",
    niceName = "Remove: " .. (category.installedPartNiceName or category.installedPart),
    slotPath = slotPath,
    price = 0,
    source = "uninstall",
    action = "uninstall",
    -- Store the installed part data so we can add it to inventory on checkout
    installedPartName = category.installedPart,
    installedPartNiceName = category.installedPartNiceName,
    installedPartValue = category.installedPartValue or 0,
  })

  log("I", "mysummerProjectPartShop", "Added uninstall to cart: " .. category.installedPartNiceName)

  updateCartTotals()

  -- Apply changes to vehicle in real-time (preview mode)
  applyCartPreview()

  return true
end

-- Remove item from cart
local function removeFromCart(partId)
  if not shopState.isOpen then
    log("W", "mysummerProjectPartShop", "removeFromCart called but shop not open")
    return false
  end

  local removedIndex = nil
  for i, item in ipairs(shopState.cart.items) do
    if item.id == partId then
      removedIndex = i
      break
    end
  end

  if removedIndex then
    local removed = table.remove(shopState.cart.items, removedIndex)
    log("I", "mysummerProjectPartShop", "Removed from cart: " .. removed.niceName)

    updateCartTotals()

    -- Apply changes to vehicle in real-time (preview mode)
    applyCartPreview()

    return true
  end

  return false
end

-- Clear cart
local function clearCart()
  shopState.cart.items = {}
  updateCartTotals()
  sendShopDataToUI()
end

-- Checkout - process purchase and install parts
local function checkout()
  if not shopState.isOpen then
    log("W", "mysummerProjectPartShop", "checkout called but shop not open")
    return false
  end

  if #shopState.cart.items == 0 then
    log("I", "mysummerProjectPartShop", "Cart is empty")
    ui_message("Cart is empty", 3, "Parts Shop", "info")
    return false
  end

  local total = shopState.cart.total

  -- Check if player can afford
  if total > 0 then
    if not career_modules_payment or not career_modules_payment.canPay then
      log("E", "mysummerProjectPartShop", "Payment module not available")
      return false
    end

    if not career_modules_payment.canPay({ money = { amount = total } }) then
      log("W", "mysummerProjectPartShop", "Player cannot afford: " .. tostring(total))
      ui_message("Not enough money!", 4, "Parts Shop", "warning")
      return false
    end

    -- Process payment
    local paySuccess = career_modules_payment.pay(
      { money = { amount = total } },
      { label = "Project Vehicle Parts" }
    )

    if not paySuccess then
      log("E", "mysummerProjectPartShop", "Payment failed")
      ui_message("Payment failed", 4, "Parts Shop", "error")
      return false
    end
  end

  -- Get vehicle object for applying parts
  local vehObj = be:getObjectByID(shopState.vehicleId)
  if not vehObj then
    log("E", "mysummerProjectPartShop", "Vehicle object not found")
    ui_message("Vehicle not found", 4, "Parts Shop", "error")
    return false
  end

  -- Get current vehicle config
  local vehicleData = core_vehicle_manager.getVehicleData(shopState.vehicleId)
  if not vehicleData or not vehicleData.config then
    log("E", "mysummerProjectPartShop", "Could not get vehicle config")
    ui_message("Could not get vehicle configuration", 4, "Parts Shop", "error")
    return false
  end

  local currentConfig = deepcopy(vehicleData.config)
  local modelKey = vehicleData.config.mainPartName or "etki"

  -- Helper: Get node from slot path (same as businessPartCustomization)
  local function getNodeFromSlotPath(tree, path)
    if not tree or not path then return nil end
    if path == "/" then return tree end

    local segments = {}
    for segment in string.gmatch(path, "[^/]+") do
      table.insert(segments, segment)
    end

    local currentNode = tree
    for _, segment in ipairs(segments) do
      if currentNode.children and currentNode.children[segment] then
        currentNode = currentNode.children[segment]
      else
        return nil
      end
    end
    return currentNode
  end

  -- Helper: Update part in partsTree (same as businessPartCustomization)
  local function createOrUpdatePartsTreeNode(partsTree, partName, slotPath)
    if not partsTree or not slotPath then return false end

    local node = getNodeFromSlotPath(partsTree, slotPath)
    if node then
      node.chosenPartName = partName or ""
      node.emptyPlaceholder = (partName == "" or not partName) and true or nil
      log("I", "mysummerProjectPartShop", "Updated node at " .. slotPath .. " to " .. tostring(partName))
      return true
    end

    log("W", "mysummerProjectPartShop", "Could not find node at " .. slotPath)
    return false
  end

  -- Helper: Recursively collect all installed parts from a node and its children
  local function collectInstalledPartsRecursive(node, path, collectedParts)
    if not node then return end

    -- If this node has an installed part, collect it
    if node.chosenPartName and node.chosenPartName ~= "" then
      local slotName = path:match("[^/]+$") or "misc"
      table.insert(collectedParts, {
        path = path,
        partName = node.chosenPartName,
        slotName = slotName,
      })
    end

    -- Recurse into children
    if node.children then
      for childSlot, childNode in pairs(node.children) do
        local childPath = path .. childSlot .. "/"
        collectInstalledPartsRecursive(childNode, childPath, collectedParts)
      end
    end
  end

  -- Helper: Add a part to player inventory (uses business part inventory)
  local function addPartToInventory(partName, slotName, partValue)
    log("I", "mysummerProjectPartShop", "addPartToInventory called: " .. tostring(partName) .. " slot: " .. tostring(slotName) .. " value: " .. tostring(partValue))

    -- Use business part inventory module (correct module name)
    local partInventory = career_modules_business_businessPartInventory

    if not partInventory then
      log("W", "mysummerProjectPartShop", "career_modules_business_businessPartInventory not available")
      return false
    end

    if not partInventory.addPart then
      log("W", "mysummerProjectPartShop", "businessPartInventory.addPart not available")
      return false
    end

    -- Try to get nice name from available parts
    local niceName = partName
    local vehicleData = core_vehicle_manager.getVehicleData(shopState.vehicleId)
    if vehicleData and vehicleData.vdata and vehicleData.vdata.availableParts then
      local partInfo = vehicleData.vdata.availableParts[partName]
      if partInfo and partInfo.description then
        local desc = partInfo.description
        niceName = type(desc) == "table" and desc.description or desc or partName
      end
    end

    local partData = {
      name = partName,
      vehicleModel = modelKey,
      partCondition = { integrityValue = 1, odometer = 0, visualValue = 1 },
      slot = slotName,
      location = 0, -- 0 = in storage
      value = partValue or 0,
      description = { description = niceName }
    }

    log("I", "mysummerProjectPartShop", "Calling addPart with data: " .. tostring(partData.name))
    local newPartId = partInventory.addPart(partData)
    log("I", "mysummerProjectPartShop", "addPart returned: " .. tostring(newPartId))
    if newPartId then
      log("I", "mysummerProjectPartShop", "Added to inventory: " .. niceName .. " (ID: " .. tostring(newPartId) .. ")")
      return true
    else
      log("W", "mysummerProjectPartShop", "addPart returned nil/false for: " .. tostring(partName))
    end
    return false
  end

  -- Apply each part to the config
  local installedCount = 0
  local uninstalledCount = 0
  for _, item in ipairs(shopState.cart.items) do
    if item.action == "uninstall" then
      -- UNINSTALL: Remove part from vehicle and add ALL child parts to inventory (cascade)
      log("I", "mysummerProjectPartShop", "Uninstalling (cascade): " .. (item.installedPartNiceName or "unknown") .. " from slot " .. tostring(item.slotPath))

      -- IMPORTANT: Use originalConfig to find parts to remove, NOT currentConfig
      -- (currentConfig already has parts removed by preview mode)
      local sourceConfig = shopState.originalConfig or currentConfig
      if item.slotPath and sourceConfig.partsTree then
        -- Get the node at this path from ORIGINAL config
        local node = getNodeFromSlotPath(sourceConfig.partsTree, item.slotPath)

        if node then
          -- Collect all installed parts from this node and children
          local partsToRemove = {}
          collectInstalledPartsRecursive(node, item.slotPath, partsToRemove)

          log("I", "mysummerProjectPartShop", "Found " .. #partsToRemove .. " parts to remove (including children)")

          -- Add all parts to inventory
          for _, partInfo in ipairs(partsToRemove) do
            -- Get value from slotCategories if available
            local partValue = 0
            local category = shopState.slotCategories[partInfo.path]
            if category and category.installedPartValue then
              partValue = category.installedPartValue
            end

            if addPartToInventory(partInfo.partName, partInfo.slotName, partValue) then
              uninstalledCount = uninstalledCount + 1
            end
          end

          -- Remove the main part from vehicle (children will be cleared automatically)
          createOrUpdatePartsTreeNode(currentConfig.partsTree, "", item.slotPath)
        end
      end
    else
      -- INSTALL: Normal part installation
      log("I", "mysummerProjectPartShop", "Installing: " .. item.niceName .. " (" .. item.name .. ") to slot " .. tostring(item.slotPath))

      if item.slotPath and currentConfig.partsTree then
        if createOrUpdatePartsTreeNode(currentConfig.partsTree, item.name, item.slotPath) then
          installedCount = installedCount + 1
        end
      end
    end
  end

  local totalChanges = installedCount + uninstalledCount

  -- Save the part inventory if parts were removed
  if uninstalledCount > 0 then
    local partInventory = career_modules_business_businessPartInventory
    if partInventory and partInventory.saveInventory then
      partInventory.saveInventory()
      log("I", "mysummerProjectPartShop", "Saved part inventory with " .. uninstalledCount .. " new parts")
    end
  end

  -- Apply the new config by respawning the vehicle
  if totalChanges > 0 then
    log("I", "mysummerProjectPartShop", "Respawning vehicle with new config...")

    local spawnOptions = {
      config = currentConfig,
      keepOtherVehRotation = true,
    }

    core_vehicles.replaceVehicle(modelKey, spawnOptions, vehObj)
    log("I", "mysummerProjectPartShop", "Vehicle respawned with " .. totalChanges .. " parts changed (" .. installedCount .. " installed, " .. uninstalledCount .. " removed)")
    -- IMPORTANT: Update the inventory stored config so it persists on save/load
    if career_modules_inventory and shopState.inventoryId then
      local inventoryVehicle = career_modules_inventory.getVehicle(shopState.inventoryId)
      if inventoryVehicle then
        -- Update the stored config with our modified partsTree
        inventoryVehicle.config = currentConfig
        log("I", "mysummerProjectPartShop", "Updated inventory config for vehicle " .. shopState.inventoryId)

        -- Mark vehicle as dirty so it gets saved
        if career_modules_inventory.setVehicleDirty then
          career_modules_inventory.setVehicleDirty(shopState.inventoryId)
          log("I", "mysummerProjectPartShop", "Marked vehicle as dirty for save")
        end

        -- Update part conditions from the respawned vehicle
        if career_modules_inventory.updatePartConditions then
          career_modules_inventory.updatePartConditions(shopState.vehicleId, shopState.inventoryId)
        end
      end
    end
  end

  -- Update inventory tracking
  if career_modules_business_businessPartInventory and career_modules_business_businessPartInventory.updatePartConditionsInInventory then
    career_modules_business_businessPartInventory.updatePartConditionsInInventory()
  end

  log("I", "mysummerProjectPartShop", string.format(
    "Checkout complete: %d installed, %d removed, total paid: %.2f",
    installedCount, uninstalledCount, total
  ))

  -- Build appropriate message
  local msg = ""
  if installedCount > 0 and uninstalledCount > 0 then
    msg = string.format("%d parts installed, %d removed to inventory!", installedCount, uninstalledCount)
  elseif installedCount > 0 then
    msg = string.format("%d parts installed!", installedCount)
  elseif uninstalledCount > 0 then
    msg = string.format("%d parts removed to inventory!", uninstalledCount)
  end
  if msg ~= "" then
    ui_message(msg, 3, "Parts Shop", "success")
  end

  -- Clear cart (changes are now committed)
  shopState.cart = { items = {}, subtotal = 0, taxes = 0, total = 0 }

  -- Update original config to current state (changes are committed, not preview anymore)
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(shopState.vehicleId)
  if vehicleData and vehicleData.config then
    shopState.originalConfig = deepcopy(vehicleData.config)
    log("I", "mysummerProjectPartShop", "Committed changes - updated original config")
  end

  -- If parts were installed, refresh the shop to show new available slots
  if installedCount > 0 then
    log("I", "mysummerProjectPartShop", "Refreshing shop to show new slots after installation...")

    -- Small delay to let vehicle respawn complete, then rebuild shop data
    shopState.pendingRefresh = true
    shopState.pendingRefreshDelay = 0.5
  else
    -- Only uninstalls, close shop (but don't restore since changes are committed)
    shopState.originalConfig = nil  -- Clear so cancelShop won't restore
    M.cancelShop()
  end

  return true
end

-- Cancel and close shop
local function cancelShop()
  log("I", "mysummerProjectPartShop", "Closing shop")

  -- If there were uncommitted changes (cart had items), restore original config
  if shopState.originalConfig and shopState.vehicleId and #shopState.cart.items > 0 then
    log("I", "mysummerProjectPartShop", "Restoring original vehicle config (canceling preview changes)")

    local vehObj = be:getObjectByID(shopState.vehicleId)
    if vehObj and shopState.modelKey then
      local spawnOptions = {
        config = shopState.originalConfig,
        keepOtherVehRotation = true,
      }
      core_vehicles.replaceVehicle(shopState.modelKey, spawnOptions, vehObj)
    end
  end

  shopState.isOpen = false
  shopState.inventoryId = nil
  shopState.vehicleId = nil
  shopState.slotCategories = {}
  shopState.cart = { items = {}, subtotal = 0, taxes = 0, total = 0 }
  shopState.originalConfig = nil
  shopState.modelKey = nil

  -- Return to computer menu
  career_career.closeAllMenus()
end

-- Check if shop is open
local function isShopOpen()
  return shopState.isOpen
end

-- Request data refresh (called by Vue on mount)
local function requestData()
  if shopState.isOpen then
    sendShopDataToUI()
  end
end

-- Handle delayed data send and refresh
local function onUpdate(dtReal, dtSim, dtRaw)
  -- Handle initial delayed send
  if shopState.pendingSendDelay and shopState.pendingSendDelay > 0 then
    shopState.pendingSendDelay = shopState.pendingSendDelay - dtReal
    if shopState.pendingSendDelay <= 0 then
      shopState.pendingSendDelay = nil
      if shopState.isOpen then
        log("I", "mysummerProjectPartShop", "Sending delayed shop data to UI")
        sendShopDataToUI()
      end
    end
  end

  -- Handle refresh after checkout (to show new slots dynamically)
  if shopState.pendingRefresh and shopState.pendingRefreshDelay then
    shopState.pendingRefreshDelay = shopState.pendingRefreshDelay - dtReal
    if shopState.pendingRefreshDelay <= 0 then
      shopState.pendingRefresh = nil
      shopState.pendingRefreshDelay = nil

      if shopState.isOpen and shopState.inventoryId then
        log("I", "mysummerProjectPartShop", "Rebuilding shop data after checkout...")

        -- Get fresh vehicle ID (may have changed after respawn)
        local inventoryVehicle = career_modules_inventory.getVehicle(shopState.inventoryId)
        if inventoryVehicle and inventoryVehicle.id then
          local vehObj = be:getObjectByID(inventoryVehicle.id)
          if vehObj then
            shopState.vehicleId = inventoryVehicle.id
          end
        end

        -- Save new original config (this is now the committed state)
        local vehicleData = extensions.core_vehicle_manager.getVehicleData(shopState.vehicleId)
        if vehicleData and vehicleData.config then
          shopState.originalConfig = deepcopy(vehicleData.config)
        end

        -- Rebuild categories with new vehicle state
        buildShopData()

        -- Send updated data to UI
        sendShopDataToUI()
        log("I", "mysummerProjectPartShop", "Shop refreshed with new slots")
      end
    end
  end

  -- Handle rebuild after cart preview (real-time vehicle update)
  if shopState.pendingPreviewRebuild and shopState.pendingPreviewDelay then
    shopState.pendingPreviewDelay = shopState.pendingPreviewDelay - dtReal
    if shopState.pendingPreviewDelay <= 0 then
      shopState.pendingPreviewRebuild = nil
      shopState.pendingPreviewDelay = nil

      if shopState.isOpen then
        log("I", "mysummerProjectPartShop", "Rebuilding UI after preview...")

        -- Rebuild shop data from current vehicle state
        buildShopData()

        -- Send updated data to UI
        sendShopDataToUI()
      end
    end
  end
end

-- Public API
M.openShop = openShop
M.addToCart = addToCart
M.addUninstallToCart = addUninstallToCart
M.removeFromCart = removeFromCart
M.clearCart = clearCart
M.checkout = checkout
M.cancelShop = cancelShop
M.isShopOpen = isShopOpen
M.requestData = requestData
M.onUpdate = onUpdate

return M
