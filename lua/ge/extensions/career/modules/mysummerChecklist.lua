-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.moduleName = "career_modules_mysummerChecklist"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerCore",
  "career_modules_partInventory",
  "career_modules_inventory",  -- For accessing vehicle data including originalParts
}

local logTag = "mysummerChecklist"

-- Target configuration path (relative to game root)
local TARGET_CONFIG_PATH = "vehicles/etki/2400ti_sport_evo_M.pc"

-- State
local state = {
  targetConfig = TARGET_CONFIG_PATH,
  targetParts = {},  -- { slotType = { targetPart, mandatory, category, niceName, slotType } }
  installedParts = {},  -- { slotType = { partName, status, installedAt } }
  projectInventoryId = nil,  -- The vehicle we're tracking
  stats = {
    totalSlots = 0,
    perfectMatches = 0,
    compatibleParts = 0,
    missingParts = 0,
    mandatoryMissing = 0,
    completionPercent = 0,
  },
  missingReasons = {},  -- Array of reasons why vehicle won't work
}

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

local function getSaveFilePath()
  local savePath = career_saveSystem.getSaveRootDirectory()
  if not savePath then
    return nil
  end
  return savePath .. "/career/rls_career/mysummer/checklist.json"
end

local function saveState()
  local saveFile = getSaveFilePath()
  if not saveFile then
    log("W", logTag, "Cannot save - no save path available")
    return
  end

  -- Create directory if needed
  local dir = saveFile:match("(.+)/[^/]+$")
  if dir then
    FS:directoryCreate(dir, true)
  end

  local saveData = {
    targetConfig = state.targetConfig,
    projectInventoryId = state.projectInventoryId,
    installedParts = state.installedParts,
    stats = state.stats,
  }

  jsonWriteFile(saveFile, saveData, true)
  log("I", logTag, "State saved to: " .. saveFile)
end

local function loadState()
  local saveFile = getSaveFilePath()
  if not saveFile then
    log("W", logTag, "Cannot load - no save path available")
    return
  end

  if not FS:fileExists(saveFile) then
    log("I", logTag, "No save file found, using defaults")
    return
  end

  local data = jsonReadFile(saveFile)
  if not data then
    log("E", logTag, "Failed to load save file: " .. saveFile)
    return
  end

  state.targetConfig = data.targetConfig or TARGET_CONFIG_PATH
  state.projectInventoryId = data.projectInventoryId
  state.installedParts = data.installedParts or {}
  state.stats = data.stats or state.stats

  log("I", logTag, "State loaded from: " .. saveFile)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function initializeTargetParts()
  if not career_modules_mysummerCore then
    log("E", logTag, "mysummerCore not available")
    return false
  end

  -- Build checklist from target config
  local checklist = career_modules_mysummerCore.buildPartsChecklistFromConfig(state.targetConfig, "etki")
  if not checklist then
    log("E", logTag, "Failed to build checklist from: " .. state.targetConfig)
    return false
  end

  state.targetParts = checklist

  -- Count total slots
  state.stats.totalSlots = 0
  for _, _ in pairs(state.targetParts) do
    state.stats.totalSlots = state.stats.totalSlots + 1
  end

  log("I", logTag, "Initialized checklist with " .. state.stats.totalSlots .. " target parts")
  return true
end

-- ============================================================================
-- VALIDATION
-- ============================================================================

-- Get currently installed parts on a vehicle
-- @param inventoryId: Vehicle inventory ID
-- @return: { slotType = partName } or nil
local function getInstalledPartsForVehicle(inventoryId)
  log("I", logTag, "=== getInstalledPartsForVehicle called for: " .. tostring(inventoryId) .. " ===")

  local vehicleParts = {}

  -- Helper to extract slot ID from path (e.g., "/etki_body/etki_door_FL/" -> "etki_door_FL")
  local function extractSlotId(slotPath)
    if not slotPath then return nil end
    -- Remove trailing slash and get last component
    local cleanPath = slotPath:gsub("/$", "")
    local slotId = cleanPath:match("([^/]+)$")
    return slotId
  end

  -- APPROACH 1: Try to get parts from partInventory
  if career_modules_partInventory then
    local allParts = career_modules_partInventory.getInventory and career_modules_partInventory.getInventory() or nil
    if allParts then
      local totalParts = 0
      for partId, part in pairs(allParts) do
        totalParts = totalParts + 1
        if part.location == inventoryId and part.containingSlot then
          local slotId = extractSlotId(part.containingSlot)
          if slotId then
            vehicleParts[slotId] = part.name
          end
        end
      end
      log("I", logTag, "Approach 1 (partInventory): " .. totalParts .. " total parts, " .. tableSize(vehicleParts) .. " on vehicle " .. tostring(inventoryId))
    else
      log("W", logTag, "Approach 1: getInventory() returned nil")
    end
  else
    log("W", logTag, "career_modules_partInventory not available")
  end

  -- APPROACH 2: Try to get originalParts from inventory vehicle
  if career_modules_inventory then
    local vehicles = career_modules_inventory.getVehicles and career_modules_inventory.getVehicles() or nil
    if vehicles then
      local vehicle = vehicles[inventoryId]
      if vehicle then
        log("I", logTag, "Approach 2: Found vehicle in inventory, checking originalParts...")
        if vehicle.originalParts then
          local count = 0
          for slotType, partInfo in pairs(vehicle.originalParts) do
            count = count + 1
            if type(partInfo) == "table" and partInfo.name then
              if not vehicleParts[slotType] then
                vehicleParts[slotType] = partInfo.name
              end
            elseif type(partInfo) == "string" then
              if not vehicleParts[slotType] then
                vehicleParts[slotType] = partInfo
              end
            end
          end
          log("I", logTag, "Approach 2 (originalParts): " .. count .. " original parts found")
        else
          log("W", logTag, "Approach 2: vehicle.originalParts is nil")
        end
      else
        log("W", logTag, "Approach 2: Vehicle " .. tostring(inventoryId) .. " not found in inventory")
      end
    else
      log("W", logTag, "Approach 2: getVehicles() returned nil")
    end
  else
    log("W", logTag, "career_modules_inventory not available")
  end

  -- APPROACH 3: Try to get parts from the spawned vehicle object directly
  if tableSize(vehicleParts) == 0 then
    -- Get vehicle ID from inventory ID
    local vehId = nil
    if career_modules_inventory and career_modules_inventory.getVehicleIdFromInventoryId then
      vehId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
    end

    if vehId then
      log("I", logTag, "Approach 3: Found spawned vehicle ID: " .. tostring(vehId))
      local vehicleData = core_vehicle_manager and core_vehicle_manager.getVehicleData and core_vehicle_manager.getVehicleData(vehId)

      if vehicleData then
        -- Try config.parts first
        if vehicleData.config and vehicleData.config.parts then
          local count = 0
          for slotType, partName in pairs(vehicleData.config.parts) do
            count = count + 1
            if partName and partName ~= "" then
              vehicleParts[slotType] = partName
            end
          end
          log("I", logTag, "Approach 3a (config.parts): " .. count .. " parts found")
        end

        -- Also try partsTree if parts is empty
        if tableSize(vehicleParts) == 0 and vehicleData.config and vehicleData.config.partsTree then
          -- Debug: log partsTree structure
          local function logTreeSample(tree, depth, maxDepth)
            depth = depth or 0
            maxDepth = maxDepth or 2
            if depth > maxDepth then return end
            local count = 0
            for key, value in pairs(tree) do
              count = count + 1
              if count <= 3 then
                local valueType = type(value)
                if valueType == "table" then
                  local subkeys = {}
                  for k, _ in pairs(value) do table.insert(subkeys, tostring(k)) end
                  log("D", logTag, string.rep("  ", depth) .. "partsTree[" .. tostring(key) .. "] = table with keys: " .. table.concat(subkeys, ", "))
                  logTreeSample(value, depth + 1, maxDepth)
                else
                  log("D", logTag, string.rep("  ", depth) .. "partsTree[" .. tostring(key) .. "] = " .. tostring(value))
                end
              end
            end
          end
          log("D", logTag, "Approach 3b: Inspecting partsTree structure...")
          logTreeSample(vehicleData.config.partsTree)

          -- Extract parts from partsTree structure
          -- Structure: node.id = slotType, node.chosenPartName = installed part, node.children = nested slots
          local function extractPartsRecursive(tree)
            if not tree then return end
            for key, node in pairs(tree) do
              if type(node) == "table" then
                -- The slot ID is in node.id, the installed part is in node.chosenPartName
                local slotId = node.id or key
                local partName = node.chosenPartName

                if partName and partName ~= "" then
                  vehicleParts[slotId] = partName
                end

                -- Recurse into children
                if node.children then
                  extractPartsRecursive(node.children)
                end
              end
            end
          end
          extractPartsRecursive(vehicleData.config.partsTree.children or vehicleData.config.partsTree)
          log("I", logTag, "Approach 3b (partsTree): " .. tableSize(vehicleParts) .. " parts extracted")
        end

        -- Debug: log what we have in vehicleData
        if tableSize(vehicleParts) == 0 then
          log("W", logTag, "Approach 3: vehicleData.config exists but no parts found")
          if vehicleData.config then
            local keys = {}
            for k, _ in pairs(vehicleData.config) do
              table.insert(keys, k)
            end
            log("D", logTag, "  config keys: " .. table.concat(keys, ", "))
          end
        end
      else
        log("W", logTag, "Approach 3: getVehicleData returned nil for vehId " .. tostring(vehId))
      end
    else
      log("W", logTag, "Approach 3: Could not get vehicle ID from inventory ID " .. tostring(inventoryId))
    end
  end

  -- APPROACH 4: Try getting parts from inventory vehicle's stored config
  if tableSize(vehicleParts) == 0 and career_modules_inventory then
    local vehicles = career_modules_inventory.getVehicles and career_modules_inventory.getVehicles() or nil
    if vehicles and vehicles[inventoryId] then
      local vehicle = vehicles[inventoryId]
      if vehicle.config and vehicle.config.parts then
        for slotType, partName in pairs(vehicle.config.parts) do
          if partName and partName ~= "" then
            vehicleParts[slotType] = partName
          end
        end
        log("I", logTag, "Approach 4 (inventory config.parts): " .. tableSize(vehicleParts) .. " parts")
      elseif vehicle.config and vehicle.config.partsTree then
        -- Similar extraction from partsTree
        local function extractParts(tree)
          for slotType, node in pairs(tree) do
            if type(node) == "table" and node.val and node.val ~= "" then
              vehicleParts[slotType] = node.val
            end
          end
        end
        extractParts(vehicle.config.partsTree)
        log("I", logTag, "Approach 4 (inventory partsTree): " .. tableSize(vehicleParts) .. " parts")
      end
    end
  end

  log("I", logTag, "Final result: " .. tableSize(vehicleParts) .. " parts found for vehicle " .. tostring(inventoryId))

  -- Debug: log first few slot types
  local count = 0
  for slotType, partName in pairs(vehicleParts) do
    if count < 5 then
      log("D", logTag, "  Slot: '" .. tostring(slotType) .. "' = '" .. tostring(partName) .. "'")
      count = count + 1
    end
  end

  return vehicleParts
end

-- Validate checklist against currently installed parts
-- @param inventoryId: Vehicle inventory ID to check
-- @return: success (boolean)
local function validateChecklist(inventoryId)
  if not inventoryId then
    inventoryId = state.projectInventoryId
  end

  if not inventoryId then
    log("W", logTag, "No project vehicle set for validation")
    return false
  end

  -- Get currently installed parts
  local installedParts = getInstalledPartsForVehicle(inventoryId)
  if not installedParts then
    log("W", logTag, "Could not get installed parts for vehicle: " .. tostring(inventoryId))
    return false
  end

  -- Reset stats
  state.stats.perfectMatches = 0
  state.stats.compatibleParts = 0
  state.stats.missingParts = 0
  state.stats.mandatoryMissing = 0
  state.missingReasons = {}

  -- Debug: log first few target slot types
  local debugCount = 0
  for slotType, targetData in pairs(state.targetParts) do
    if debugCount < 5 then
      log("D", logTag, "  Target slot: '" .. tostring(slotType) .. "' expects '" .. tostring(targetData.targetPart) .. "'")
      debugCount = debugCount + 1
    end
  end

  -- Compare each slot
  local timestamp = os.time()
  for slotType, targetData in pairs(state.targetParts) do
    local installedPart = installedParts[slotType]

    if installedPart and installedPart ~= "" and installedPart ~= "none" then
      -- Part is installed
      if installedPart == targetData.targetPart then
        -- Perfect match
        state.installedParts[slotType] = {
          partName = installedPart,
          status = "perfect",
          installedAt = state.installedParts[slotType] and state.installedParts[slotType].installedAt or timestamp,
        }
        state.stats.perfectMatches = state.stats.perfectMatches + 1
      else
        -- Compatible (different part but slot is filled)
        state.installedParts[slotType] = {
          partName = installedPart,
          status = "compatible",
          installedAt = state.installedParts[slotType] and state.installedParts[slotType].installedAt or timestamp,
        }
        state.stats.compatibleParts = state.stats.compatibleParts + 1
      end
    else
      -- Part is missing
      state.installedParts[slotType] = {
        partName = nil,
        status = "missing",
        installedAt = nil,
      }
      state.stats.missingParts = state.stats.missingParts + 1

      -- Check if mandatory
      if targetData.mandatory then
        state.stats.mandatoryMissing = state.stats.mandatoryMissing + 1

        -- Add reason why car won't work
        local reason = nil
        if slotType:lower():find("engine") then
          reason = "No engine - car won't start"
        elseif slotType:lower():find("transmission") then
          reason = "No transmission - can't shift gears"
        elseif slotType:lower():find("differential") then
          reason = "No differential - wheels won't turn"
        end

        if reason then
          -- Check if reason already exists
          local exists = false
          for _, r in ipairs(state.missingReasons) do
            if r == reason then
              exists = true
              break
            end
          end
          if not exists then
            table.insert(state.missingReasons, reason)
          end
        end
      end
    end
  end

  -- Calculate completion percentage
  if state.stats.totalSlots > 0 then
    state.stats.completionPercent = (state.stats.perfectMatches / state.stats.totalSlots) * 100
  else
    state.stats.completionPercent = 0
  end

  log("I", logTag, string.format("Validation complete: %d%% (%d/%d perfect, %d compatible, %d missing, %d mandatory missing)",
    math.floor(state.stats.completionPercent),
    state.stats.perfectMatches,
    state.stats.totalSlots,
    state.stats.compatibleParts,
    state.stats.missingParts,
    state.stats.mandatoryMissing
  ))

  saveState()
  return true
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Set the project vehicle to track
-- @param inventoryId: Vehicle inventory ID
local function setProjectVehicle(inventoryId)
  state.projectInventoryId = inventoryId
  log("I", logTag, "Project vehicle set to: " .. tostring(inventoryId))

  -- Immediately validate
  validateChecklist(inventoryId)
  saveState()
end

-- Get the full checklist data for UI
-- @return: { checklist = { ... }, stats = { ... }, missingReasons = [ ... ] }
local function getChecklistData()
  log("I", logTag, "getChecklistData called - targetParts count: " .. tableSize(state.targetParts) .. ", projectId: " .. tostring(state.projectInventoryId))

  -- Build full checklist with status
  local checklist = {}
  for slotType, targetData in pairs(state.targetParts) do
    local installed = state.installedParts[slotType] or { status = "missing" }

    checklist[slotType] = {
      -- Target info
      targetPart = targetData.targetPart,
      mandatory = targetData.mandatory,
      category = targetData.category,
      niceName = targetData.niceName,
      slotType = slotType,

      -- Installed status
      installedPart = installed.partName,
      status = installed.status,
      installedAt = installed.installedAt,
    }
  end

  return {
    checklist = checklist,
    stats = state.stats,
    missingReasons = state.missingReasons,
    projectInventoryId = state.projectInventoryId,
  }
end

-- Get just the stats (lighter weight for quick checks)
-- @return: { totalSlots, perfectMatches, compatibleParts, missingParts, mandatoryMissing, completionPercent }
local function getStats()
  return state.stats
end

-- ============================================================================
-- UI COMMUNICATION
-- ============================================================================

local function sendChecklistUpdate()
  if not guihooks then
    return
  end

  local data = getChecklistData()
  guihooks.trigger("mysummerChecklistUpdated", data)
end

-- Refresh validation (called externally when parts change)
local function refresh()
  if state.projectInventoryId then
    validateChecklist(state.projectInventoryId)
    sendChecklistUpdate()
  end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Called when parts change on any vehicle
local function onVehiclePartChanged(data)
  -- Only care about our project vehicle
  if data and data.inventoryId == state.projectInventoryId then
    log("I", logTag, "Parts changed on project vehicle, revalidating...")
    validateChecklist(state.projectInventoryId)
    sendChecklistUpdate()
  end
end

-- Called when parts are installed/removed
local function onPartInventoryChanged()
  -- Revalidate in case parts were added/removed from project vehicle
  if state.projectInventoryId then
    log("I", logTag, "onPartInventoryChanged triggered, revalidating...")
    validateChecklist(state.projectInventoryId)
    sendChecklistUpdate()
  end
end

-- Called when part shopping transaction completes (parts installed via tuning shop)
local function onPartShoppingTransactionComplete(data)
  log("I", logTag, "onPartShoppingTransactionComplete triggered")
  if state.projectInventoryId then
    -- Small delay to let the vehicle update
    log("I", logTag, "Revalidating checklist after part shopping...")
    validateChecklist(state.projectInventoryId)
    sendChecklistUpdate()
  end
end

-- Called when vehicle config changes
local function onVehicleConfigChanged(vehId, newConfig)
  log("I", logTag, "onVehicleConfigChanged triggered for vehicle: " .. tostring(vehId))
  if state.projectInventoryId then
    -- Check if this is our project vehicle
    local projectVehId = career_modules_inventory and
                         career_modules_inventory.getVehicleIdFromInventoryId and
                         career_modules_inventory.getVehicleIdFromInventoryId(state.projectInventoryId)
    if projectVehId == vehId then
      log("I", logTag, "Project vehicle config changed, revalidating...")
      validateChecklist(state.projectInventoryId)
      sendChecklistUpdate()
    end
  end
end

-- ============================================================================
-- COMPUTER INTEGRATION
-- ============================================================================

local function onComputerAddFunctions(menuData, computerFunctions)
  -- NOTE: Build Checklist is now accessed via Internet Browser (mysummerInternet module)
  -- No separate menu entry needed - user navigates to Project page from the browser
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Checklist module loaded")
end

local function onCareerActive(enabled)
  if not enabled then
    return
  end

  log("I", logTag, "Initializing MySummer Checklist...")

  -- Load saved state
  loadState()

  -- Initialize target parts from config
  if not initializeTargetParts() then
    log("E", logTag, "Failed to initialize target parts")
    return
  end

  -- If we have a project vehicle, validate it
  if state.projectInventoryId then
    validateChecklist(state.projectInventoryId)
  end

  log("I", logTag, "MySummer Checklist initialized successfully")
end

-- ============================================================================
-- PUBLIC EXPORTS
-- ============================================================================

M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onVehiclePartChanged = onVehiclePartChanged
M.onPartInventoryChanged = onPartInventoryChanged
M.onPartShoppingTransactionComplete = onPartShoppingTransactionComplete
M.onVehicleConfigChanged = onVehicleConfigChanged
M.onComputerAddFunctions = onComputerAddFunctions

M.setProjectVehicle = setProjectVehicle
M.getChecklistData = getChecklistData
M.getStats = getStats
M.refresh = refresh

return M
