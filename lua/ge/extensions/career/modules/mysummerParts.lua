local M = {}

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_inventory",
  "career_modules_payment",
  "career_modules_garageManager",
  "career_modules_partInventory",
  "career_modules_computer",
  "career_modules_vehicleShopping",
  "career_modules_mysummerCore",
  "career_modules_mysummerProjectPartShop",
  "career_modules_mysummerCargo",  -- Cargo system for part pickup
  -- Note: mysummerCareer is optional to avoid circular deps - checked at runtime
  -- Note: insurance_insurance is optional - we check for it but don't require it
  -- "gameplay_police" is also optional
}

local jbeamIO = require("jbeam/io")
local freeroam_facilities = require("freeroam/facilities")
local core_groundMarkers = require("core/groundMarkers")

-- Save file is now in mysummer subdirectory
local saveDir = "/career/rls_career/mysummer"
local saveFileName = "market.json"
local modelKey = "etki"
local targetListings = 6
local targetLeads = 2

local partCache = {}
local pickupLocations = {}
local pickupLocationsLevel = nil
local originComputerId = nil
local loggedConfigModels = {}

-- Initialization flag to ensure RLS is fully loaded
local isFullyInitialized = false

-- Forward declaration of state (defined later)
local state

-- Forward declaration for getProjectPartsData (defined later, needed by sendProjectPartsData)
local getProjectPartsData

-- Forward declaration for getLoadedCargoInfo (defined later, needed by getMarketData)
local getLoadedCargoInfo

-- Check if all required RLS modules are ready
local function checkRLSModulesReady()
  if not career_career or not career_career.isActive then
    return false, "career_career not loaded"
  end

  if not career_modules_inventory or not career_modules_inventory.getVehicles then
    return false, "career_modules_inventory not ready"
  end

  if not career_modules_payment or not career_modules_payment.pay then
    return false, "career_modules_payment not ready"
  end

  if not career_modules_partInventory or not career_modules_partInventory.getInventory then
    return false, "career_modules_partInventory not ready"
  end

  if not career_modules_computer then
    return false, "career_modules_computer not ready"
  end

  if not career_modules_garageManager or not career_modules_garageManager.getNextAvailableSpace then
    return false, "career_modules_garageManager not ready"
  end

  if not career_modules_vehicleShopping then
    return false, "career_modules_vehicleShopping not ready"
  end

  if not career_modules_insurance_insurance or not career_modules_insurance_insurance.getInvVehs then
    return false, "career_modules_insurance_insurance not ready"
  end

  if not gameplay_police then
    return false, "gameplay_police not ready"
  end

  return true
end

state = {
  listings = {},
  leads = {},
  nextListingId = 1,
  nextLeadId = 1,
  activePickup = nil,
  pendingPickups = {},  -- Queue of selected pickups for multiple selection
  hasInitialVehicles = false,
  projectInventoryId = nil,
  pendingIllegalPartId = nil,  -- Part ID in inventory (after unloading)
  pendingIllegalCargoId = nil,  -- Cargo ID in vehicle (before unloading)
  pendingInsuranceSync = false,
  pendingPartSeeds = {},
  -- Heat system: 0-100, affects police pursuit probability
  playerHeat = 0,
  lastHeatDecayTime = 0,  -- Track when heat last decayed
  -- First purchase tracking for contact unlock
  firstPurchaseMade = false,
}

-- Heat configuration
local HEAT_CONFIG = {
  maxHeat = 100,
  -- Heat increase per pickup type
  pickupHeatIncrease = {
    normal = 10,
    hot = 20,
    extreme = 35,
  },
  -- Heat decay: -5 per 5 minutes of play
  decayInterval = 300,  -- 5 minutes in seconds
  decayAmount = 5,
  -- Heat reduction when changing vehicle/paint (police can't recognize you)
  vehicleChangeReduction = 0.60,  -- Reduce heat by 60% when switching vehicle
  paintChangeReduction = 0.40,    -- Reduce heat by 40% when repainting same vehicle
  -- Police pursuit probability thresholds
  pursuitChance = {
    { minHeat = 0, chance = 0 },      -- No ambient pursuit at low heat
    { minHeat = 50, chance = 0.10 },  -- 10% chance over 50 heat
    { minHeat = 75, chance = 0.25 },  -- 25% chance over 75 heat
    { minHeat = 90, chance = 0.50 },  -- 50% chance over 90 heat
  },
}

-- Track last known vehicle for heat system
local lastKnownVehicle = {
  inventoryId = nil,
  paintHash = nil,  -- Hash of paint colors to detect repaints
}

local function buildInsuranceVehicleInfo(invVeh)
  if not invVeh then
    return nil
  end

  local model = invVeh.model
  local configName = nil
  if invVeh.config and invVeh.config.partConfigFilename and path and path.splitWithoutExt then
    local _, cfg = path.splitWithoutExt(invVeh.config.partConfigFilename)
    configName = cfg
  end

  local configInfo = {}
  if model and configName and core_vehicles and core_vehicles.getConfig then
    configInfo = core_vehicles.getConfig(model, configName) or {}
  end

  local bodyStyle = configInfo["Body Style"] or configInfo.BodyStyle
  local bodyStyleTable = nil
  if bodyStyle then
    bodyStyleTable = {[bodyStyle] = true}
  end

  return {
    Name = configInfo.Configuration or invVeh.niceName or model,
    Value = configInfo.Value or invVeh.configBaseValue or 1000,
    Population = configInfo.Population or 0,
    BodyStyle = bodyStyleTable,
    aggregates = {
      ["Body Style"] = bodyStyleTable,
      ["InsuranceClass"] = configInfo.InsuranceClass or configInfo["InsuranceClass"],
    },
  }
end

local function ensureInsuranceEntries()
  if not career_modules_insurance_insurance
    or not career_modules_insurance_insurance.getInvVehs
    or not career_modules_insurance_insurance.onVehicleAddedToInventory then
    return false
  end

  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then
    return false
  end

  local invVehs = career_modules_insurance_insurance.getInvVehs() or {}
  local changed = false
  local missing = {}

  for invId, invVeh in pairs(vehicles) do
    local invEntry = invVehs[invId]
    if not invEntry or not invEntry.requiredInsuranceClass then
      local vehicleInfo = buildInsuranceVehicleInfo(invVeh)
      if vehicleInfo then
        career_modules_insurance_insurance.onVehicleAddedToInventory({
          inventoryId = invId,
          vehicleInfo = vehicleInfo,
        })
        changed = true
      else
        missing[invId] = true
      end
    end
  end

  local invVehsAfter = career_modules_insurance_insurance.getInvVehs() or {}
  for invId, _ in pairs(vehicles) do
    if not invVehsAfter[invId] then
      missing[invId] = true
    end
  end

  return next(missing) == nil and (changed or true)
end

local function queueInsuranceSync()
  state.pendingInsuranceSync = true
end

local function hasMissingInsuranceEntries()
  if not career_modules_insurance_insurance or not career_modules_insurance_insurance.getInvVehs then
    return false
  end
  local vehicles = career_modules_inventory and career_modules_inventory.getVehicles and career_modules_inventory.getVehicles() or nil
  if not vehicles then
    return false
  end
  local invVehs = career_modules_insurance_insurance.getInvVehs() or {}
  for invId, _ in pairs(vehicles) do
    local entry = invVehs[invId]
    if not entry or not entry.requiredInsuranceClass then
      return true
    end
  end
  return false
end

local function ensureSaveDir(savePath)
  local dirPath = savePath .. "/career/rls_career"
  if not FS:directoryExists(dirPath) then
    FS:directoryCreate(dirPath)
  end
  -- Also ensure mysummer subdirectory exists
  local mysummerDir = dirPath .. saveDir
  if not FS:directoryExists(mysummerDir) then
    FS:directoryCreate(mysummerDir, true)
  end
  return dirPath
end

local function getSavePath(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  local effectivePath = currentSavePath or savePath
  if not effectivePath then
    return nil
  end
  local dirPath = ensureSaveDir(effectivePath)
  return dirPath .. saveDir .. "/" .. saveFileName
end

local function toVec3(pos)
  if not pos then
    return nil
  end
  if type(pos) == "table" then
    if pos.x then
      return vec3(pos.x, pos.y, pos.z)
    elseif #pos >= 3 then
      return vec3(pos[1], pos[2], pos[3])
    end
  end
  return nil
end

local function serializeVec3(pos)
  if not pos then
    return nil
  end
  return { x = pos.x, y = pos.y, z = pos.z }
end

local function getPlayerPos()
  local veh = getPlayerVehicle(0)
  return veh and veh:getPosition() or nil
end

local function loadState()
  local filePath = getSavePath()
  if not filePath then
    return
  end

  local data = jsonReadFile(filePath) or {}
  state.listings = data.listings or {}
  state.leads = data.leads or {}
  state.nextListingId = tonumber(data.nextListingId) or 1
  state.nextLeadId = tonumber(data.nextLeadId) or 1
  state.activePickup = data.activePickup or nil
  state.pendingPickups = data.pendingPickups or {}
  state.hasInitialVehicles = data.hasInitialVehicles or false
  state.projectInventoryId = data.projectInventoryId or nil
  state.pendingIllegalPartId = data.pendingIllegalPartId or nil
  state.pendingIllegalCargoId = data.pendingIllegalCargoId or nil
  state.playerHeat = tonumber(data.playerHeat) or 0
  state.lastHeatDecayTime = tonumber(data.lastHeatDecayTime) or os.time()
  state.firstPurchaseMade = data.firstPurchaseMade or false
end

local function saveState(currentSavePath)
  local filePath = getSavePath(currentSavePath)
  if not filePath then
    return
  end

  local data = {
    listings = state.listings,
    leads = state.leads,
    nextListingId = state.nextListingId,
    nextLeadId = state.nextLeadId,
    activePickup = state.activePickup,
    pendingPickups = state.pendingPickups,
    hasInitialVehicles = state.hasInitialVehicles,
    projectInventoryId = state.projectInventoryId,
    pendingIllegalPartId = state.pendingIllegalPartId,
    pendingIllegalCargoId = state.pendingIllegalCargoId,
    playerHeat = state.playerHeat,
    lastHeatDecayTime = state.lastHeatDecayTime,
    firstPurchaseMade = state.firstPurchaseMade,
  }
  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
end

local function buildPartsCache(model)
  if partCache[model] then
    log("D", "mysummer", "buildPartsCache: using cached data for " .. model)
    return partCache[model]
  end

  log("I", "mysummer", "buildPartsCache: building cache for " .. model)
  local vehicleDir = string.format("/vehicles/%s/", model)
  if not FS:directoryExists(vehicleDir) then
    log("W", "mysummer", "buildPartsCache: vehicle dir not found: " .. vehicleDir)
    partCache[model] = { parts = {}, legal = {}, illegal = {} }
    return partCache[model]
  end

  local ioCtx = jbeamIO.startLoading({ vehicleDir, "/vehicles/common/" })
  local availableParts = jbeamIO.getAvailableParts(ioCtx) or {}
  local parts = {}

  for partName, partInfo in pairs(availableParts) do
    if partName and partName ~= "" then
      local partData = jbeamIO.getPart(ioCtx, partName) or {}
      local info = partData.information or partInfo.information or {}
      local value = tonumber(info.value) or 0
      local niceName = info.name
      if not niceName then
        if type(partInfo.description) == "table" then
          niceName = partInfo.description.description
        else
          niceName = partInfo.description
        end
      end
      niceName = niceName or partName

      if value > 0 then
        -- MySummer: Exclude wheels, tires, paints, and hubcaps from second-hand/illegal market
        local rawSlotType = partData.slotType or partInfo.slotType
        local slotTypeStr = ""
        if type(rawSlotType) == "string" then
          slotTypeStr = rawSlotType
        elseif type(rawSlotType) == "table" then
          -- slotType can be an array of slot names, use the first one
          slotTypeStr = rawSlotType[1] or ""
        end

        local lowerSlot = string.lower(slotTypeStr)
        local lowerName = string.lower(partName)
        -- MySummer: Exclude cosmetic/wheels/tires/cargo from second-hand market (PartsBay) and illegal market (SilkRoad)
        -- These should only be available from the official shop (SpeedParts) or not at all
        local excludePatterns = {
          "wheel", "tire", "hubcap",           -- Wheels & Tires
          "paint", "skin", "lettering", "logo", "sunstrip",  -- Cosmetics
          "licenseplate",                       -- License plates
          "glass", "windshield",                -- Glass/windows
          "cargo", "toolbox", "bed_", "tonneau", "canopy",  -- Cargo/bed parts (NOT fuel tank)
          "fluidtank", "watertank",             -- Cargo fluid tanks (specific, not fuel)
        }
        local shouldExclude = false
        for _, pattern in ipairs(excludePatterns) do
          if string.find(lowerSlot, pattern) or string.find(lowerName, pattern) then
            shouldExclude = true
            break
          end
        end

        if not shouldExclude then
          table.insert(parts, {
            name = partName,
            niceName = niceName,
            value = value,
            slotType = slotTypeStr,
          })
        end
      end
    end
  end

  table.sort(parts, function(a, b) return a.value < b.value end)
  local legalCut = math.max(1, math.floor(#parts * 0.7))
  local illegalCut = math.max(1, math.floor(#parts * 0.8))
  local legal = {}
  local illegal = {}
  for idx, part in ipairs(parts) do
    if idx <= legalCut then
      table.insert(legal, part)
    end
    if idx >= illegalCut then
      table.insert(illegal, part)
    end
  end

  partCache[model] = { parts = parts, legal = legal, illegal = illegal }
  log("I", "mysummer", string.format("buildPartsCache: built cache for %s - %d total, %d legal, %d illegal",
    model, #parts, #legal, #illegal))
  return partCache[model]
end

local function pickDefaultConfigPath(model)
  if not model or not core_vehicles or not core_vehicles.getModel then
    return nil
  end

  local modelData = core_vehicles.getModel(model)
  if not modelData or not modelData.configs or (tableIsEmpty and tableIsEmpty(modelData.configs)) then
    return nil
  end

  local function normalizeConfigPath(configKey)
    if not configKey or configKey == "" then
      return nil
    end
    local rawKey = tostring(configKey)
    if string.startswith(rawKey, "vehicles/") and string.endswith(rawKey, ".pc") then
      if FS and FS.fileExists and FS:fileExists(rawKey) then
        return rawKey
      end
    end
    local filename = rawKey
    if string.endswith(filename, ".pc") then
      filename = string.sub(filename, 1, -4)
    end
    local candidates = {
      string.format("vehicles/%s/%s.pc", model, filename),
      string.format("vehicles/%s/configurations/%s.pc", model, filename),
    }
    for _, candidate in ipairs(candidates) do
      if FS and FS.fileExists and FS:fileExists(candidate) then
        return candidate
      end
    end
    return nil
  end

  local candidates = {}
  for configKey, configData in pairs(modelData.configs) do
    local configInfo = core_vehicles.getConfig and core_vehicles.getConfig(model, configKey) or nil
    local configType = configData and (configData["Config Type"] or configData.ConfigType or configData.configType)
    if configInfo and (configInfo["Config Type"] or configInfo.ConfigType or configInfo.configType) then
      configType = configInfo["Config Type"] or configInfo.ConfigType or configInfo.configType
    end

    local configName = nil
    if configInfo then
      configName = configInfo.Configuration or configInfo.Name
    end
    if not configName and configData then
      configName = configData.Name or configData.name
    end

    local value = configInfo and tonumber(configInfo.Value) or nil
    local pathCandidate = nil
    if configData then
      pathCandidate = configData.file or configData.filepath or configData.path or configData.partConfigFilename
    end
    local normalized = normalizeConfigPath(pathCandidate or configKey)
    if normalized then
      table.insert(candidates, {
        key = configKey,
        path = normalized,
        configType = tostring(configType or ""),
        name = tostring(configName or ""),
        value = value or math.huge,
      })
    end
  end

  if not loggedConfigModels[model] then
    loggedConfigModels[model] = true
    for _, entry in ipairs(candidates) do
      log("I", "mysummer",
        string.format("Config candidate model=%s key=%s type=%s value=%s path=%s name=%s",
          model, entry.key, entry.configType, tostring(entry.value), entry.path, entry.name))
    end
  end

  local best = nil
  for _, entry in ipairs(candidates) do
    local score = 0
    local typeLower = string.lower(entry.configType)
    local nameLower = string.lower(entry.name)
    if typeLower == "factory" then
      score = score + 40
    elseif typeLower == "base" then
      score = score + 35
    end
    if nameLower:find("base") or nameLower:find("standard") or nameLower:find("stock") then
      score = score + 25
    end
    if nameLower:find("race") or nameLower:find("drift") or nameLower:find("police") then
      score = score - 50
    end
    if not best or score > best.score or (score == best.score and entry.value < best.value) then
      best = {
        path = entry.path,
        key = entry.key,
        score = score,
        value = entry.value,
      }
    end
  end

  if best and best.path then
    log("I", "mysummer", string.format("Picked default config model=%s key=%s path=%s", model, best.key, best.path))
    return best.path
  end

  local fallbacks = {
    string.format("vehicles/%s/%s_base.pc", model, model),
    string.format("vehicles/%s/%s.pc", model, model),
  }
  for _, fallback in ipairs(fallbacks) do
    if FS and FS.fileExists and FS:fileExists(fallback) then
      log("I", "mysummer", string.format("Fallback config model=%s path=%s", model, fallback))
      return fallback
    end
  end

  log("W", "mysummer", string.format("No valid config found for model=%s", model))
  return nil
end

local function resolveConfigPath(model, configIdOrName)
  if not model or not configIdOrName or not core_vehicles or not core_vehicles.getModel then
    return nil
  end

  local function normalizeConfigPath(configKey)
    if not configKey or configKey == "" then
      return nil
    end
    local rawKey = tostring(configKey)
    if string.startswith(rawKey, "vehicles/") and string.endswith(rawKey, ".pc") then
      if FS and FS.fileExists and FS:fileExists(rawKey) then
        return rawKey
      end
    end
    local filename = rawKey
    if string.endswith(filename, ".pc") then
      filename = string.sub(filename, 1, -4)
    end
    local candidates = {
      string.format("vehicles/%s/%s.pc", model, filename),
      string.format("vehicles/%s/configurations/%s.pc", model, filename),
    }
    for _, candidate in ipairs(candidates) do
      if FS and FS.fileExists and FS:fileExists(candidate) then
        return candidate
      end
    end
    return nil
  end

  local direct = normalizeConfigPath(configIdOrName)
  if direct then
    return direct
  end

  local modelData = core_vehicles.getModel(model)
  if not modelData or not modelData.configs or (tableIsEmpty and tableIsEmpty(modelData.configs)) then
    return nil
  end

  local exactEntry = modelData.configs[configIdOrName]
  if exactEntry then
    local pathCandidate = exactEntry.file or exactEntry.path or exactEntry.partConfigFilename or configIdOrName
    local normalized = normalizeConfigPath(pathCandidate)
    if normalized then
      return normalized
    end
  end

  local target = string.lower(tostring(configIdOrName))
  for configKey, configData in pairs(modelData.configs) do
    local info = core_vehicles.getConfig and core_vehicles.getConfig(model, configKey) or nil
    local name = info and (info.Configuration or info.Name) or configData and (configData.Name or configData.name) or ""
    local keyLower = string.lower(tostring(configKey))
    local nameLower = string.lower(tostring(name))
    if keyLower == target or nameLower == target then
      local pathCandidate = configData and (configData.file or configData.path or configData.partConfigFilename) or configKey
      local normalized = normalizeConfigPath(pathCandidate or configKey)
      if normalized then
        return normalized
      end
    end
  end

  for configKey, configData in pairs(modelData.configs) do
    local info = core_vehicles.getConfig and core_vehicles.getConfig(model, configKey) or nil
    local name = info and (info.Configuration or info.Name) or configData and (configData.Name or configData.name) or ""
    local keyLower = string.lower(tostring(configKey))
    local nameLower = string.lower(tostring(name))
    if keyLower:find(target, 1, true) or nameLower:find(target, 1, true) then
      local pathCandidate = configData and (configData.file or configData.path or configData.partConfigFilename) or configKey
      local normalized = normalizeConfigPath(pathCandidate or configKey)
      if normalized then
        return normalized
      end
    end
  end

  return nil
end

local function pickPart(category)
  local cache = buildPartsCache(modelKey)
  local list = category == "illegal" and cache.illegal or cache.legal
  if not list or #list == 0 then
    list = cache.parts
  end
  if not list or #list == 0 then
    return nil
  end

  -- TIER FILTERING: Filter parts by reputation tier
  local reputation = career_modules_mysummerCareer and career_modules_mysummerCareer.getReputation() or { tier = 1 }
  local tier = reputation.tier or 1

  -- Tier value thresholds
  local tierMaxValues = {
    [1] = 500,    -- Tier 1: 0-500
    [2] = 1500,   -- Tier 2: 0-1500
    [3] = 3000,   -- Tier 3: 0-3000
    [4] = 5000,   -- Tier 4: 0-5000
    [5] = 999999, -- Tier 5: All parts
  }

  local maxValue = tierMaxValues[tier] or 999999

  -- Filter parts by value
  local filteredList = {}
  for _, part in ipairs(list) do
    local partValue = part.value or 0
    if partValue <= maxValue then
      table.insert(filteredList, part)
    end
  end

  -- Fallback to unfiltered if no parts match (shouldn't happen)
  if #filteredList == 0 then
    filteredList = list
  end

  return filteredList[math.random(#filteredList)]
end

local function isValidPosition(pos)
  if not pos then return false end
  if type(pos) == "table" then
    local x = pos.x or pos[1]
    local y = pos.y or pos[2]
    local z = pos.z or pos[3]
    -- Check for nil, NaN, or positions at origin (0,0,0)
    if not x or not y or not z then return false end
    if x ~= x or y ~= y or z ~= z then return false end  -- NaN check
    if x == 0 and y == 0 and z == 0 then return false end
    return true
  elseif type(pos) == "cdata" then
    -- vec3 type
    if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then return false end
    if pos.x == 0 and pos.y == 0 and pos.z == 0 then return false end
    return true
  end
  return false
end

local function buildPickupLocations()
  local levelName = getCurrentLevelIdentifier()
  if pickupLocationsLevel == levelName and #pickupLocations > 0 then
    return pickupLocations
  end

  pickupLocations = {}
  pickupLocationsLevel = levelName

  log("I", "mysummer", "Building pickup locations for level: " .. tostring(levelName))

  local facilities = freeroam_facilities.getFacilities(levelName)
  if facilities then
    for groupName, group in pairs(facilities) do
      if type(group) == "table" then
        for facilityId, facility in pairs(group) do
          if type(facility) == "table" and facility.name then
            local pos = nil

            -- Try getAverageDoorPositionForFacility first
            pos = freeroam_facilities.getAverageDoorPositionForFacility(facility)

            -- Fallback to facility.pos
            if not isValidPosition(pos) and facility.pos then
              pos = facility.pos
            end

            -- Fallback to parking spots
            if not isValidPosition(pos) and freeroam_facilities.getParkingSpotsForFacility then
              local spots = freeroam_facilities.getParkingSpotsForFacility(facility)
              if spots and #spots > 0 and spots[1] and spots[1].pos then
                pos = spots[1].pos
              end
            end

            if isValidPosition(pos) then
              table.insert(pickupLocations, {
                name = facility.name,
                pos = serializeVec3(pos),
              })
            end
          end
        end
      end
    end
  end

  log("I", "mysummer", "Found " .. #pickupLocations .. " valid pickup locations")

  -- Fallback: use player position if no valid locations found
  if #pickupLocations == 0 then
    local playerPos = getPlayerPos()
    if playerPos and isValidPosition(playerPos) then
      -- Create multiple fallback locations around the player
      local offsets = {
        vec3(100, 50, 0),
        vec3(-80, 100, 0),
        vec3(50, -120, 0),
        vec3(-100, -80, 0),
      }
      for i, offset in ipairs(offsets) do
        local newPos = playerPos + offset
        table.insert(pickupLocations, {
          name = "Drop Point " .. i,
          pos = serializeVec3(newPos),
        })
      end
      log("W", "mysummer", "Using fallback locations based on player position")
    end
  end

  -- Last resort fallback
  if #pickupLocations == 0 then
    log("E", "mysummer", "No valid pickup locations found, using absolute fallback")
    table.insert(pickupLocations, {
      name = "Unknown Location",
      pos = { x = 500, y = 500, z = 100 },
    })
  end

  return pickupLocations
end

local function pickLocation()
  local locations = buildPickupLocations()
  return deepcopy(locations[math.random(#locations)])
end

local function buildCondition(isIllegal)
  local odometer = isIllegal and math.random(0, 8000) or math.random(5000, 120000)
  return {
    integrityValue = 1,
    odometer = odometer,
    visualValue = 1,
  }
end

local function generateListing()
  local part = pickPart("legal")
  if not part then
    return nil
  end
  local location = pickLocation()
  local condition = buildCondition(false)

  -- Price based on km: more km = lower price (up to 40% discount)
  local kmFactor = 1 - (condition.odometer / 200000) * 0.4
  kmFactor = math.max(0.6, math.min(1, kmFactor))  -- Clamp between 0.6 and 1
  local baseModifier = 0.55 + math.random() * 0.45  -- 55-100% of value
  local price = math.max(50, math.floor(part.value * baseModifier * kmFactor))

  local listing = {
    id = state.nextListingId,
    partName = part.name,
    partNiceName = part.niceName,
    vehicleModel = modelKey,
    slotType = part.slotType,
    baseValue = part.value,
    price = price,
    condition = condition,
    location = location,
    createdAt = os.time(),
    expiresAt = os.time() + math.random(1800, 7200),  -- 30min to 2h rotation
    isIllegal = false,
  }

  -- COLOR GENERATION: Add random paint for body parts
  if part.slotType and career_modules_mysummerCore then
    local slotLower = part.slotType:lower()
    if slotLower:find("body") or slotLower:find("fender") or
       slotLower:find("bumper") or slotLower:find("door") or
       slotLower:find("hood") or slotLower:find("trunk") then
      local paintInfo = career_modules_mysummerCore.generateRandomPaint()
      if paintInfo then
        listing.paintData = paintInfo.paintData
        listing.paintName = paintInfo.paintName
      end
    end
  end

  state.nextListingId = state.nextListingId + 1
  return listing
end

local leadTemplates = {
  "Got a line on a %s. Pickup at %s. Be quick.",
  "Quiet drop for a %s behind %s. Police are sniffing around.",
  "Someone stashed a %s near %s. Bring a fast car.",
  "Heard about a %s at %s. Don't get caught.",
}

local function generateLead()
  local part = pickPart("illegal")
  if not part then
    return nil
  end
  local location = pickLocation()
  local heatRoll = math.random()
  local heatLevel = heatRoll > 0.85 and "extreme" or (heatRoll > 0.5 and "hot" or "normal")

  local lead = {
    id = state.nextLeadId,
    partName = part.name,
    partNiceName = part.niceName,
    vehicleModel = modelKey,
    slotType = part.slotType,
    baseValue = part.value,
    price = 0,
    condition = buildCondition(true),
    location = location,
    createdAt = os.time(),
    expiresAt = os.time() + math.random(900, 3600),  -- 15min to 1h rotation (illegal tips expire faster)
    isIllegal = true,
    heat = heatLevel,
    message = string.format(leadTemplates[math.random(#leadTemplates)], part.niceName, location.name),
  }

  -- COLOR GENERATION: Add random paint for body parts
  if part.slotType and career_modules_mysummerCore then
    local slotLower = part.slotType:lower()
    if slotLower:find("body") or slotLower:find("fender") or
       slotLower:find("bumper") or slotLower:find("door") or
       slotLower:find("hood") or slotLower:find("trunk") then
      local paintInfo = career_modules_mysummerCore.generateRandomPaint()
      if paintInfo then
        lead.paintData = paintInfo.paintData
        lead.paintName = paintInfo.paintName
      end
    end
  end

  state.nextLeadId = state.nextLeadId + 1
  return lead
end

local function ensureMarketStock()
  while #state.listings < targetListings do
    local listing = generateListing()
    if not listing then
      log("W", "mysummer", "ensureMarketStock: generateListing returned nil")
      break
    end
    table.insert(state.listings, listing)
  end

  local cache = buildPartsCache(modelKey)
  log("D", "mysummer", string.format("ensureMarketStock: cache has %d parts, %d legal, %d illegal",
    cache.parts and #cache.parts or 0,
    cache.legal and #cache.legal or 0,
    cache.illegal and #cache.illegal or 0))
  log("D", "mysummer", string.format("ensureMarketStock: current leads=%d, target=%d", #state.leads, targetLeads))

  while #state.leads < targetLeads do
    local lead = generateLead()
    if not lead then
      log("W", "mysummer", "ensureMarketStock: generateLead returned nil")
      break
    end
    table.insert(state.leads, lead)
    log("D", "mysummer", "ensureMarketStock: added lead for " .. (lead.partNiceName or "unknown"))
  end
end

local function buildListingUIEntry(entry, playerPos)
  local result = deepcopy(entry)
  local targetPos = toVec3(result.location and result.location.pos)
  if playerPos and targetPos then
    result.distance = playerPos:distance(targetPos)
  end
  return result
end

local function getMarketData()
  if not isFullyInitialized then
    log("W", "mysummer", "getMarketData called before initialization complete")
    return { listings = {}, leads = {}, activePickup = nil, pendingPickups = {} }
  end

  ensureMarketStock()
  local playerPos = getPlayerPos()
  local data = {
    listings = {},
    leads = {},
    activePickup = nil,
    pendingPickups = {},
    pendingCount = state.pendingPickups and #state.pendingPickups or 0,
  }

  for _, listing in ipairs(state.listings) do
    table.insert(data.listings, buildListingUIEntry(listing, playerPos))
  end

  for _, lead in ipairs(state.leads) do
    table.insert(data.leads, buildListingUIEntry(lead, playerPos))
  end

  if state.activePickup then
    data.activePickup = buildListingUIEntry(state.activePickup, playerPos)
  end

  -- Include pending pickups for UI display
  if state.pendingPickups then
    for _, pickup in ipairs(state.pendingPickups) do
      table.insert(data.pendingPickups, buildListingUIEntry(pickup, playerPos))
    end
  end

  -- Include loaded cargo info
  data.cargo = getLoadedCargoInfo()

  return data
end

local function sendMarketUpdate()
  if not career_career.isActive() then
    return
  end

  if not guihooks then
    log("W", "mysummer", "UI hooks not ready")
    return
  end

  guihooks.trigger("mysummerMarketUpdated", getMarketData())
end

local function setRouteToPickup(pickup)
  if not pickup or not pickup.location or not pickup.location.pos then
    return
  end
  local pos = toVec3(pickup.location.pos)
  if not pos then
    return
  end
  core_groundMarkers.setPath(pos, { clearPathOnReachingTarget = true })
end

local function clearRoute()
  core_groundMarkers.setPath(nil)
end

local function addPartToInventory(partData)
  if not career_modules_partInventory or not partData then
    return nil
  end

  if not partData.description then
    local name = partData.partNiceName or partData.niceName or partData.name or "Part"
    partData.description = { description = name }
  elseif type(partData.description) == "string" then
    partData.description = { description = partData.description }
  elseif type(partData.description) == "table" and not partData.description.description then
    local name = partData.partNiceName or partData.niceName or partData.name or "Part"
    partData.description.description = name
  end

  if not partData.value and partData.baseValue then
    partData.value = partData.baseValue
  end

  local inventory = career_modules_partInventory.getInventory and career_modules_partInventory.getInventory() or nil
  if not inventory then
    return nil
  end

  local idCounter = 1
  while inventory[idCounter] do
    idCounter = idCounter + 1
  end
  inventory[idCounter] = partData

  local slotToPartIdMap = career_modules_partInventory.getSlotToPartIdMap and career_modules_partInventory.getSlotToPartIdMap() or nil
  local partPathToPartIdMap = career_modules_partInventory.getPartPathToPartIdMap and career_modules_partInventory.getPartPathToPartIdMap() or nil
  if slotToPartIdMap and partPathToPartIdMap and partData.location and partData.location > 0 then
    slotToPartIdMap[partData.location] = slotToPartIdMap[partData.location] or {}
    partPathToPartIdMap[partData.location] = partPathToPartIdMap[partData.location] or {}
    if partData.containingSlot then
      slotToPartIdMap[partData.location][partData.containingSlot] = idCounter
    end
    if partData.partPath then
      partPathToPartIdMap[partData.location][partData.partPath] = idCounter
    end
  end

  if career_modules_partInventory.updatePartConditionsInInventory then
    career_modules_partInventory.updatePartConditionsInInventory()
  end

  return idCounter
end

local function seedPartInventoryForVehicle(inventoryId)
  if not inventoryId or not career_modules_partInventory then
    return false
  end

  local partPathToPartIdMap = career_modules_partInventory.getPartPathToPartIdMap and career_modules_partInventory.getPartPathToPartIdMap() or nil
  if not partPathToPartIdMap then
    return false
  end

  if partPathToPartIdMap[inventoryId] and next(partPathToPartIdMap[inventoryId]) then
    return true
  end

  if career_modules_partInventory.onVehicleAdded then
    career_modules_partInventory.onVehicleAdded(inventoryId)
  elseif career_modules_partInventory.generateAndGetPartsFromVehicle then
    local parts = career_modules_partInventory.generateAndGetPartsFromVehicle(inventoryId) or nil
    if parts and #parts > 0 then
      for _, part in ipairs(parts) do
        addPartToInventory(part)
      end
    end
  end

  partPathToPartIdMap = career_modules_partInventory.getPartPathToPartIdMap and career_modules_partInventory.getPartPathToPartIdMap() or nil
  return partPathToPartIdMap and partPathToPartIdMap[inventoryId] and next(partPathToPartIdMap[inventoryId]) ~= nil
end

local function queuePartInventorySeed(inventoryId)
  if not inventoryId then
    return
  end
  state.pendingPartSeeds[inventoryId] = state.pendingPartSeeds[inventoryId] or { tries = 0 }
end

local function processPendingPartSeeds()
  if not career_modules_partInventory or not next(state.pendingPartSeeds) then
    return
  end

  local partPathToPartIdMap = career_modules_partInventory.getPartPathToPartIdMap and career_modules_partInventory.getPartPathToPartIdMap() or nil
  if not partPathToPartIdMap then
    return
  end

  for inventoryId, info in pairs(state.pendingPartSeeds) do
    if partPathToPartIdMap[inventoryId] and next(partPathToPartIdMap[inventoryId]) then
      state.pendingPartSeeds[inventoryId] = nil
    else
      info.tries = (info.tries or 0) + 1
      if info.tries >= 2 then
        seedPartInventoryForVehicle(inventoryId)
        partPathToPartIdMap = career_modules_partInventory.getPartPathToPartIdMap and career_modules_partInventory.getPartPathToPartIdMap() or partPathToPartIdMap
        if partPathToPartIdMap and partPathToPartIdMap[inventoryId] and next(partPathToPartIdMap[inventoryId]) then
          state.pendingPartSeeds[inventoryId] = nil
        elseif info.tries >= 4 then
          state.pendingPartSeeds[inventoryId] = nil
        end
      end
    end
  end
end

local function removePartFromInventory(partId)
  if not partId or not career_modules_partInventory then
    return false
  end
  if career_modules_partInventory.removePart then
    return career_modules_partInventory.removePart(partId)
  end
  if career_modules_partInventory.removePartById then
    return career_modules_partInventory.removePartById(partId)
  end
  return false
end

-- ============================================
-- PLAYER HEAT SYSTEM
-- ============================================

-- Get a simple hash of vehicle paint colors
local function getVehiclePaintHash()
  local veh = getPlayerVehicle(0)
  if not veh then return nil end

  local paintData = veh:getField("paint", "")
  if not paintData or paintData == "" then return nil end

  -- Simple hash: just use first 32 chars of the paint string
  return paintData:sub(1, 32)
end

-- Get current player vehicle inventory ID
local function getCurrentVehicleInventoryId()
  local vehId = be:getPlayerVehicleID(0)
  if not vehId then return nil end

  if career_modules_inventory and career_modules_inventory.getInventoryIdFromVehicleId then
    return career_modules_inventory.getInventoryIdFromVehicleId(vehId)
  end
  return nil
end

-- Add heat (clamped to max)
local function addPlayerHeat(amount)
  local oldHeat = state.playerHeat
  state.playerHeat = math.min(HEAT_CONFIG.maxHeat, math.max(0, state.playerHeat + amount))

  if state.playerHeat ~= oldHeat then
    log("I", "mysummer", string.format("Player heat: %d -> %d (change: %+d)", oldHeat, state.playerHeat, amount))
    saveState()

    -- Notify UI
    guihooks.trigger("mysummerHeatUpdated", { heat = state.playerHeat, maxHeat = HEAT_CONFIG.maxHeat })
  end
end

-- Get current player heat
local function getPlayerHeat()
  return state.playerHeat
end

-- Clear heat completely (used by Shadow contact for a price)
local function clearPlayerHeat()
  local oldHeat = state.playerHeat
  state.playerHeat = 0
  if oldHeat > 0 then
    log("I", "mysummer", "Player heat cleared (was " .. oldHeat .. ")")
    saveState()
    guihooks.trigger("mysummerHeatUpdated", { heat = 0, maxHeat = HEAT_CONFIG.maxHeat })
  end
end

-- Check if vehicle/paint changed and reduce heat accordingly
local function checkVehicleHeatReduction()
  local currentInvId = getCurrentVehicleInventoryId()
  local currentPaintHash = getVehiclePaintHash()

  if not currentInvId then return end

  -- First time tracking
  if not lastKnownVehicle.inventoryId then
    lastKnownVehicle.inventoryId = currentInvId
    lastKnownVehicle.paintHash = currentPaintHash
    return
  end

  -- Check for vehicle change
  if currentInvId ~= lastKnownVehicle.inventoryId then
    if state.playerHeat > 0 then
      local reduction = math.floor(state.playerHeat * HEAT_CONFIG.vehicleChangeReduction)
      addPlayerHeat(-reduction)
      ui_message(string.format("New vehicle! Heat reduced by %d%%", math.floor(HEAT_CONFIG.vehicleChangeReduction * 100)), 3, "Heat")
      log("I", "mysummer", string.format("Vehicle changed: heat reduced by %d (now %d)", reduction, state.playerHeat))
    end
    lastKnownVehicle.inventoryId = currentInvId
    lastKnownVehicle.paintHash = currentPaintHash
    return
  end

  -- Check for paint change on same vehicle
  if currentPaintHash and currentPaintHash ~= lastKnownVehicle.paintHash then
    if state.playerHeat > 0 then
      local reduction = math.floor(state.playerHeat * HEAT_CONFIG.paintChangeReduction)
      addPlayerHeat(-reduction)
      ui_message(string.format("Fresh paint! Heat reduced by %d%%", math.floor(HEAT_CONFIG.paintChangeReduction * 100)), 3, "Heat")
      log("I", "mysummer", string.format("Paint changed: heat reduced by %d (now %d)", reduction, state.playerHeat))
    end
    lastKnownVehicle.paintHash = currentPaintHash
  end
end

-- Process heat decay over time
local function processHeatDecay()
  if state.playerHeat <= 0 then return end

  local now = os.time()
  local elapsed = now - state.lastHeatDecayTime

  if elapsed >= HEAT_CONFIG.decayInterval then
    local decayTicks = math.floor(elapsed / HEAT_CONFIG.decayInterval)
    local totalDecay = decayTicks * HEAT_CONFIG.decayAmount
    addPlayerHeat(-totalDecay)
    state.lastHeatDecayTime = now - (elapsed % HEAT_CONFIG.decayInterval)
  end
end

-- Get police pursuit chance based on current heat
local function getAmbientPursuitChance()
  local chance = 0
  for _, threshold in ipairs(HEAT_CONFIG.pursuitChance) do
    if state.playerHeat >= threshold.minHeat then
      chance = threshold.chance
    end
  end
  return chance
end

-- Check for random police encounter based on heat
local function checkAmbientPoliceEncounter()
  if state.playerHeat < 50 then return end  -- No ambient encounters below 50 heat

  local chance = getAmbientPursuitChance()
  if chance > 0 and math.random() < chance then
    local vehId = be:getPlayerVehicleID(0)
    if vehId and gameplay_police and not gameplay_police.getPursuitData() then
      log("I", "mysummer", string.format("Ambient police encounter triggered (heat: %d, chance: %.0f%%)", state.playerHeat, chance * 100))
      ui_message("The police spotted you! They must have recognized you.", 4, "Heat", "warning")
      startPolicePursuit("normal")
    end
  end
end

local function setPoliceHeat(heatLevel)
  local vars = {
    evadeTime = 35,
    arrestTime = 12,
    arrestRadius = 18,
    evadeLimit = 25,
  }

  if heatLevel == "hot" then
    vars.evadeTime = 45
    vars.arrestTime = 14
    vars.arrestRadius = 20
    vars.evadeLimit = 18
  elseif heatLevel == "extreme" then
    vars.evadeTime = 60
    vars.arrestTime = 16
    vars.arrestRadius = 26
    vars.evadeLimit = 10
  end

  gameplay_police.setPursuitVars(vars)
end

local function startPolicePursuit(heatLevel)
  local vehId = be:getPlayerVehicleID(0)
  if not vehId or not gameplay_police then
    return
  end
  setPoliceHeat(heatLevel)
  gameplay_police.setPursuitMode(1, vehId)
end

-- Criminal chase vehicle configs
local criminalConfigs = {
  { model = "sunburst2", config = "sport_RS_M" },
  { model = "pickup", config = "d15_4wd_offroad_M" },
}

-- Track active criminal vehicles for cleanup
local activeCriminals = {}  -- { [vehId] = { spawnTime, lastPos, stationaryTime } }
local criminalTimeout = 360  -- Despawn after 6 minutes
local criminalStationaryTimeout = 15  -- Despawn if stationary for 15 seconds
local criminalStationaryThreshold = 2  -- Consider stationary if moved less than 2m

local function removeCriminal(vehId)
  local veh = getObjectByID(vehId)
  if veh then
    if gameplay_traffic and gameplay_traffic.removeTraffic then
      gameplay_traffic.removeTraffic(vehId)
    end
    veh:delete()
  end
  activeCriminals[vehId] = nil
end

local function cleanupCriminals()
  for vehId, _ in pairs(activeCriminals) do
    removeCriminal(vehId)
  end
  activeCriminals = {}
end

-- Check criminals for timeout or stationary despawn
local function updateCriminals(dt)
  local now = os.time()
  local toRemove = {}

  for vehId, data in pairs(activeCriminals) do
    local veh = getObjectByID(vehId)
    if not veh then
      -- Vehicle no longer exists
      table.insert(toRemove, vehId)
    else
      -- Check timeout
      if now - data.spawnTime > criminalTimeout then
        log("I", "mysummer", string.format("Criminal %d despawned (timeout)", vehId))
        table.insert(toRemove, vehId)
      else
        -- Check if stationary
        local currentPos = veh:getPosition()
        if data.lastPos then
          local distance = (currentPos - data.lastPos):length()
          if distance < criminalStationaryThreshold then
            data.stationaryTime = (data.stationaryTime or 0) + dt
            if data.stationaryTime > criminalStationaryTimeout then
              log("I", "mysummer", string.format("Criminal %d despawned (stationary)", vehId))
              table.insert(toRemove, vehId)
            end
          else
            data.stationaryTime = 0
          end
        end
        data.lastPos = currentPos
      end
    end
  end

  for _, vehId in ipairs(toRemove) do
    removeCriminal(vehId)
  end
end

local function startCriminalChase(heatLevel)
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then
    log("W", "mysummer", "startCriminalChase: No player vehicle")
    return
  end

  local playerPos = playerVeh:getPosition()
  local playerRot = playerVeh:getRotation()

  -- Determine spawn count by heat level (minimum 3 criminals)
  local minCount, maxCount = 3, 4
  if heatLevel == "hot" then
    minCount, maxCount = 4, 5
  elseif heatLevel == "extreme" then
    minCount, maxCount = 5, 6
  end
  local spawnCount = math.random(minCount, maxCount)

  log("I", "mysummer", string.format("Starting criminal chase with %d vehicles (heat: %s)", spawnCount, heatLevel or "normal"))

  -- Clean up any existing criminals first
  cleanupCriminals()

  -- Spawn criminal vehicles behind/around player
  for i = 1, spawnCount do
    local config = criminalConfigs[math.random(#criminalConfigs)]

    -- Spawn behind player (180-220m back, spread to sides)
    local backOffset = math.random(180, 220)
    local sideOffset = math.random(-40, 40)

    -- Get player's forward direction and calculate spawn position behind
    local forward = playerVeh:getDirectionVector()
    local up = playerVeh:getDirectionVectorUp()
    local right = forward:cross(up)
    right:normalize()
    local spawnPos = playerPos - (forward * backOffset) + (right * sideOffset)
    spawnPos = vec3(spawnPos.x, spawnPos.y, spawnPos.z + 1)  -- Raise slightly

    local options = {
      config = config.config,
      autoEnterVehicle = false,
      pos = spawnPos,
      rot = playerRot,  -- Face same direction as player
    }

    local vehicle = core_vehicles.spawnNewVehicle(config.model, options)

    if vehicle then
      local vehId = vehicle:getID()
      activeCriminals[vehId] = {
        spawnTime = os.time(),
        lastPos = nil,
        stationaryTime = 0,
      }

      -- Insert into traffic system
      if gameplay_traffic and gameplay_traffic.insertTraffic then
        gameplay_traffic.insertTraffic(vehId, true)
      end
      vehicle.playerUsable = false

      -- Set to aggressive chase mode
      vehicle:queueLuaCommand('ai.setMode("chase")')
      vehicle:queueLuaCommand('ai.setAggression(0.9)')
      vehicle:queueLuaCommand('ai.setSpeedMode("off")')
      vehicle:queueLuaCommand('ai.driveInLane("off")')

      -- Turn on lights
      vehicle:queueLuaCommand('electrics.setLightsState(1)')

      log("I", "mysummer", string.format("Spawned criminal %s at distance %.0fm", config.model, backOffset))
    else
      log("W", "mysummer", string.format("Failed to spawn criminal %s with config %s", config.model, config.config))
    end
  end
end

local function completePickup()
  if not state.activePickup then
    return
  end

  local pickup = state.activePickup

  -- Check cargo space first (async)
  local cargoModule = career_modules_mysummerCargo
  if not cargoModule then
    ui_message("Cargo system unavailable.", 4, "Parts Market", "warning")
    return
  end

  cargoModule.checkCargoSpace({ pickup.partName }, function(cargoResult)
    if not cargoResult.canLoad then
      if cargoResult.availableSlots == 0 then
        ui_message("No cargo container found! Install a cargo box in your vehicle.", 5, "Parts Market", "warning")
      else
        local cargoInfo = cargoModule.getPartCargoInfo(pickup.partName)
        ui_message(string.format("Not enough cargo space! Need %d slots, have %d.", cargoInfo.slots, cargoResult.availableSlots), 5, "Parts Market", "warning")
      end
      return
    end

    -- Has cargo space, proceed with payment and pickup
    local price = tonumber(pickup.price) or 0
    if price > 0 then
      local priceData = { money = { amount = price, canBeNegative = false } }
      if not career_modules_payment.canPay(priceData) then
        ui_message("You cannot afford this pickup yet.", 4, "Parts Market", "warning")
        return
      end
      career_modules_payment.pay(priceData, { label = "Parts pickup", tags = { "buying", "parts" } })
    end

    -- Load part into native cargo system (affects vehicle weight, shows in cargo UI)
    local partData = {
      partName = pickup.partName,
      partNiceName = pickup.partNiceName,
      vehicleModel = pickup.vehicleModel,
      slotType = pickup.slotType,
      condition = deepcopy(pickup.condition),
      baseValue = pickup.baseValue,
      isIllegal = pickup.isIllegal,
      heat = pickup.heat,
    }

    cargoModule.loadPartIntoCargo(partData, function(success, cargoIdOrError, container)
      if not success then
        -- Refund payment if cargo loading failed
        if price > 0 then
          career_modules_payment.reward({ money = { amount = price } }, { label = "Parts pickup refund" })
        end
        ui_message("Failed to load cargo: " .. tostring(cargoIdOrError), 4, "Parts Market", "warning")
        return
      end

      local cargoInfo = cargoModule.getPartCargoInfo(pickup.partName)

      if pickup.isIllegal then
        -- Track illegal cargo ID for pursuit system
        state.pendingIllegalCargoId = cargoIdOrError

        -- Increase player heat based on pickup heat level
        local heatIncrease = HEAT_CONFIG.pickupHeatIncrease[pickup.heat or "normal"] or 10
        addPlayerHeat(heatIncrease)

        -- 60% police, 40% criminals
        local chaseRoll = math.random()
        if chaseRoll < 0.4 then
          startCriminalChase(pickup.heat or "normal")
          ui_message("Part loaded! But rival criminals are coming! Escape!", 4, "Parts Market", "warning")
        else
          startPolicePursuit(pickup.heat or "hot")
          ui_message("Part loaded! Police are on the way. Lose them.", 4, "Parts Market", "warning")
        end
      else
        ui_message(string.format("Part loaded into cargo. (%dkg, %d slots)", cargoInfo.weight, cargoInfo.slots), 3, "Parts Market")
      end

      state.activePickup = nil
      clearRoute()

      -- Set V3 context for recent purchase (for DeepWeb conversations)
      if career_modules_mysummerDeepWeb and career_modules_mysummerDeepWeb.setPlayerContext then
        career_modules_mysummerDeepWeb.setPlayerContext("recentPurchase", true)
      end

      -- Detect first purchase -> unlock Ghost contact
      if not state.firstPurchaseMade then
        state.firstPurchaseMade = true
        log("I", "mysummer", "First purchase made! Unlocking Ghost contact.")
        if career_modules_mysummerDeepWeb and career_modules_mysummerDeepWeb.onFirstPurchase then
          career_modules_mysummerDeepWeb.onFirstPurchase()
        end
      end

      -- Check if there are more pickups in the queue (multiple selection)
      if state.pendingPickups and #state.pendingPickups > 0 then
        state.activePickup = table.remove(state.pendingPickups, 1)
        setRouteToPickup(state.activePickup)
        local remaining = #state.pendingPickups
        if remaining > 0 then
          ui_message(string.format("Next pickup set. %d more after this.", remaining), 3, "Parts Market")
        else
          ui_message("Last pickup. Head there now.", 3, "Parts Market")
        end
      end

      ensureMarketStock()
      saveState()
      sendMarketUpdate()
    end)
  end)
end

local function acceptListing(listingId)
  if not isFullyInitialized then
    log("W", "mysummer", "acceptListing called before initialization complete")
    return { success = false, message = "System not ready. Please wait." }
  end

  if state.activePickup then
    return { success = false, message = "Finish your current pickup first." }
  end

  for idx, listing in ipairs(state.listings) do
    if listing.id == listingId then
      local price = tonumber(listing.price) or 0
      if price > 0 then
        local priceData = { money = { amount = price, canBeNegative = false } }
        if not career_modules_payment.canPay(priceData) then
          return { success = false, message = "Not enough money for this listing." }
        end
      end

      state.activePickup = deepcopy(listing)
      table.remove(state.listings, idx)
      setRouteToPickup(state.activePickup)
      saveState()
      sendMarketUpdate()
      return { success = true }
    end
  end

  return { success = false, message = "Listing not found." }
end

local function acceptLead(leadId)
  if not isFullyInitialized then
    log("W", "mysummer", "acceptLead called before initialization complete")
    return { success = false, message = "System not ready. Please wait." }
  end

  if state.activePickup then
    return { success = false, message = "Finish your current pickup first." }
  end

  for idx, lead in ipairs(state.leads) do
    if lead.id == leadId then
      state.activePickup = deepcopy(lead)
      table.remove(state.leads, idx)
      setRouteToPickup(state.activePickup)
      saveState()
      sendMarketUpdate()
      return { success = true }
    end
  end

  return { success = false, message = "Lead not found." }
end

-- Accept multiple listings at once for batch pickup
local function acceptMultipleListings(listingIds)
  if not isFullyInitialized then
    log("W", "mysummer", "acceptMultipleListings called before initialization complete")
    return { success = false, message = "System not ready. Please wait." }
  end

  if not listingIds or #listingIds == 0 then
    return { success = false, message = "No listings selected." }
  end

  -- Check if already have active pickup
  if state.activePickup then
    return { success = false, message = "Finish your current pickup first." }
  end

  -- Calculate total price and verify funds
  local totalPrice = 0
  local validListings = {}

  for _, listingId in ipairs(listingIds) do
    for idx, listing in ipairs(state.listings) do
      if listing.id == listingId then
        totalPrice = totalPrice + (tonumber(listing.price) or 0)
        table.insert(validListings, { idx = idx, listing = listing })
        break
      end
    end
  end

  if #validListings == 0 then
    return { success = false, message = "No valid listings found." }
  end

  -- Check if player can afford total
  if totalPrice > 0 then
    local priceData = { money = { amount = totalPrice, canBeNegative = false } }
    if not career_modules_payment.canPay(priceData) then
      return { success = false, message = string.format("Not enough money. Need $%d total.", totalPrice) }
    end
  end

  -- Sort by index descending to remove without shifting issues
  table.sort(validListings, function(a, b) return a.idx > b.idx end)

  -- Remove from listings and add to pending queue
  for _, item in ipairs(validListings) do
    table.insert(state.pendingPickups, deepcopy(item.listing))
    table.remove(state.listings, item.idx)
  end

  -- Start with the first pickup
  if #state.pendingPickups > 0 then
    state.activePickup = table.remove(state.pendingPickups, 1)
    setRouteToPickup(state.activePickup)
  end

  saveState()
  sendMarketUpdate()
  return { success = true, count = #validListings, totalPrice = totalPrice }
end

local function refreshListings()
  if not isFullyInitialized then
    log("W", "mysummer", "refreshListings called before initialization complete")
    return { listings = {}, leads = {}, activePickup = nil }
  end

  state.listings = {}
  state.leads = {}
  ensureMarketStock()
  saveState()
  sendMarketUpdate()
  return getMarketData()
end

local function cancelActivePickup()
  if not isFullyInitialized then
    log("W", "mysummer", "cancelActivePickup called before initialization complete")
    return { listings = {}, leads = {}, activePickup = nil }
  end

  if state.activePickup then
    state.activePickup = nil
    clearRoute()
    saveState()
    sendMarketUpdate()
  end
  return getMarketData()
end

local function openMenuFromComputer(computerId)
  if not isFullyInitialized then
    log("W", "mysummer", "openMenuFromComputer called before initialization complete")
    ui_message("MySummer system not ready. Please wait a moment.", 3, "MySummer", "warning")
    return
  end

  originComputerId = computerId
  guihooks.trigger("ChangeState", { state = "mysummer-market" })
end

local function closeMenu()
  if not isFullyInitialized then
    return
  end

  if originComputerId then
    local computer = freeroam_facilities.getFacility("computer", originComputerId)
    if computer then
      career_modules_computer.openMenu(computer)
    else
      career_career.closeAllMenus()
    end
    originComputerId = nil
  else
    career_career.closeAllMenus()
  end
end

local function closeAllMenus()
  originComputerId = nil
  career_career.closeAllMenus()
end

local function spawnInitialVehicles()
  if state.hasInitialVehicles then
    return
  end

  local function ensureConfigBaseValue(inventoryId, model, fallbackConfig)
    if not inventoryId or not career_modules_inventory then
      return
    end
    local vehicles = career_modules_inventory.getVehicles()
    if not vehicles or not vehicles[inventoryId] then
      return
    end
    local vehicle = vehicles[inventoryId]
    if type(vehicle.configBaseValue) == "number" then
      return
    end
    local fallbackValue = 5000
    if model and fallbackConfig and core_vehicles and core_vehicles.getConfig then
      local configData = core_vehicles.getConfig(model, fallbackConfig)
      if configData and type(configData.Value) == "number" then
        fallbackValue = configData.Value
      end
    end
    vehicle.configBaseValue = fallbackValue
  end

  local function addStarterVehicle(vehObj, garageId, isProject)
    if not vehObj or not career_modules_inventory then
      return nil
    end
    local vehId = vehObj:getID()
    if not vehId then
      return nil
    end

    -- MySummer: High mileage starter vehicles
    -- Miramar (daily driver): 800k-1M km
    -- ETK-I (project car): 500k-800k km
    -- Note: BeamNG odometer is in METERS, not km. Multiply by 1000.
    local mileage
    if isProject then
      mileage = math.random(500000, 800000) * 1000  -- 500k-800k km in meters
    else
      mileage = math.random(800000, 1000000) * 1000  -- 800k-1M km in meters
    end
    local visualValue = 1
    if career_modules_vehicleShopping and career_modules_vehicleShopping.getVisualValueFromMileage then
      visualValue = career_modules_vehicleShopping.getVisualValueFromMileage(mileage)
    end
    vehObj:queueLuaCommand(string.format("partCondition.initConditions(nil, %d, nil, %f)", mileage, visualValue))

    local invId = career_modules_inventory.addVehicle(vehId, nil, { starter = true })
    if not invId then
      return nil
    end

    if garageId then
      career_modules_inventory.moveVehicleToGarage(invId, garageId)
    end

    if isProject then
      state.projectInventoryId = invId
      ensureConfigBaseValue(invId, "etki", "roller-etki")
      -- Notify Checklist of project vehicle
      if career_modules_mysummerChecklist and career_modules_mysummerChecklist.setProjectVehicle then
        career_modules_mysummerChecklist.setProjectVehicle(invId)
      end
    else
      -- Miramar: ensure configBaseValue to prevent insurance errors
      ensureConfigBaseValue(invId, "miramar", "ute_export_M_early")
    end

    if career_modules_insurance_insurance and career_modules_insurance_insurance.getInvVehs then
      local invVehs = career_modules_insurance_insurance.getInvVehs()
      if not invVehs or not invVehs[invId] then
        local vehicles = career_modules_inventory.getVehicles()
        local invVeh = vehicles and vehicles[invId] or nil
        local vehicleInfo = buildInsuranceVehicleInfo(invVeh)
        if vehicleInfo then
          career_modules_insurance_insurance.onVehicleAddedToInventory({
            inventoryId = invId,
            vehicleInfo = vehicleInfo,
          })
        end
      end
    end

    queuePartInventorySeed(invId)
    queueInsuranceSync()
    saveState()

    return invId
  end

  local existing = career_modules_inventory.getVehicles()
  if existing then
    for invId, veh in pairs(existing) do
      if veh and veh.model == "etki" and veh.config and veh.config.partConfigFilename and veh.config.partConfigFilename:find("mysummer_2400ti_ttsport_chassis") then
        state.projectInventoryId = invId
        state.hasInitialVehicles = true
        ensureConfigBaseValue(invId, "etki", "roller-etki")
        -- Notify Checklist of project vehicle
        if career_modules_mysummerChecklist and career_modules_mysummerChecklist.setProjectVehicle then
          career_modules_mysummerChecklist.setProjectVehicle(invId)
        end
        saveState()
        return
      end
    end
  end

  if career_modules_garageManager and career_modules_garageManager.purchaseDefaultGarage then
    career_modules_garageManager.purchaseDefaultGarage()
  end

  local garageId = career_modules_garageManager.getNextAvailableSpace()
  local garage = garageId and freeroam_facilities.getFacility("garage", garageId) or nil
  local spots = garage and freeroam_facilities.getParkingSpotsForFacility(garage) or {}

  local spotA = spots and spots[1] or nil
  local spotB = spots and spots[2] or nil
  if spotA and not spotB then
    spotB = { pos = spotA.pos + vec3(6, 0, 0), rot = spotA.rot }
  end

  local fallbackPos, fallbackRot
  if garageId and freeroam_facilities and freeroam_facilities.getGaragePosRot then
    fallbackPos, fallbackRot = freeroam_facilities.getGaragePosRot(garageId)
  end
  if not fallbackPos then
    local playerVeh = getPlayerVehicle(0)
    if playerVeh then
      fallbackPos = playerVeh:getPosition() + vec3(6, 0, 0)
      fallbackRot = quatFromDir and quatFromDir(vec3(1, 0, 0)) or nil
    end
  end

  local function spawnAtSpot(model, options, spot)
    if spot then
      options.pos = spot.pos
      options.rot = quat(spot.rot)
    elseif fallbackPos then
      options.pos = fallbackPos
      if fallbackRot then
        options.rot = fallbackRot
      end
    end
    local spawnOptions = sanitizeVehicleSpawnOptions and sanitizeVehicleSpawnOptions(model, options) or options
    spawnOptions.autoEnterVehicle = false
    spawnOptions.spawnWithEngineRunning = false
    spawnOptions.cling = true
    return core_vehicles.spawnNewVehicle(model, spawnOptions)
  end

  local starterModel = "miramar"
  local starterConfigKey = "vehicles/miramar/mysummer_starter.pc"
  local starterModelOk = true
  if core_vehicles and core_vehicles.getModel then
    local modelData = core_vehicles.getModel(starterModel)
    if (tableIsEmpty and tableIsEmpty(modelData)) or (not tableIsEmpty and (not modelData or not next(modelData))) then
      starterModelOk = false
    end
  end

  if not starterModelOk then
    ui_message("Ibishu Miramar content is missing/disabled. Enable it to spawn the starter car.", 6, "My Summer Career", "warning")
  end

  local starterOptions = {}
  local resolvedConfig = resolveConfigPath(starterModel, starterConfigKey)
  if resolvedConfig then
    starterOptions.config = resolvedConfig
  else
    log("W", "mysummer", string.format("Starter config not found for %s: %s", starterModel, starterConfigKey))
    starterOptions.config = pickDefaultConfigPath(starterModel)
  end

  local starterCar = starterModelOk and spawnAtSpot(starterModel, starterOptions, spotA) or nil
  if starterCar then
    -- Set "DADDY" license plate for starter car
    if core_vehicles and core_vehicles.setPlateText then
      core_vehicles.setPlateText("DADDY", starterCar:getID())
    end
    addStarterVehicle(starterCar, garageId, false)
  end

  local etkOptions = { config = "vehicles/etki/mysummer_2400ti_ttsport_chassis.pc" }
  local etk = spawnAtSpot("etki", etkOptions, spotB)
  if etk then
    -- Set permanent "1234-ABC" license plate for project car
    if core_vehicles and core_vehicles.setPlateText then
      core_vehicles.setPlateText("1234-ABC", etk:getID())
    end
    addStarterVehicle(etk, garageId, true)
  end

  state.hasInitialVehicles = true
  queueInsuranceSync()
  saveState()
end

local function ensureProjectConfig()
  local vehicles = career_modules_inventory.getVehicles()
  if not vehicles then
    return
  end
  if not state.projectInventoryId then
    for invId, veh in pairs(vehicles) do
      if veh and veh.model == "etki" and veh.config and veh.config.partConfigFilename and veh.config.partConfigFilename:find("mysummer_2400ti_ttsport_chassis") then
        state.projectInventoryId = invId
        -- Notify Checklist of project vehicle
        if career_modules_mysummerChecklist and career_modules_mysummerChecklist.setProjectVehicle then
          career_modules_mysummerChecklist.setProjectVehicle(invId)
        end
        break
      end
    end
  end
  if state.projectInventoryId then
    local vehicle = vehicles[state.projectInventoryId]
    if vehicle and type(vehicle.configBaseValue) ~= "number" then
      local fallbackValue = 5000
      if core_vehicles and core_vehicles.getConfig then
        local configData = core_vehicles.getConfig("etki", "roller-etki")
        if configData and type(configData.Value) == "number" then
          fallbackValue = configData.Value
        end
      end
      vehicle.configBaseValue = fallbackValue
    end
  end
end

-- Pending data send timer
local pendingProjectPartsDataSend = nil

-- Send project parts data to UI (called after delay to ensure component is mounted)
local function sendProjectPartsData()
  local data = getProjectPartsData()
  log("I", "mysummer", "Sending project parts data to UI: " .. tostring(data.success))
  guihooks.trigger("projectPartsDataUpdated", data)
end

-- Open the custom project parts menu (for project vehicle only)
-- Uses independent mysummerProjectPartShop module
local function openProjectPartsMenu(inventoryId, computerId)
  log("I", "mysummer", "Opening project parts menu for inventory: " .. tostring(inventoryId))

  -- Store context for the menu (used by closeProjectPartsMenu)
  originComputerId = computerId

  -- Use the independent project part shop module
  local projectShop = extensions.career_modules_mysummerProjectPartShop
  if projectShop and projectShop.openShop then
    projectShop.openShop(inventoryId, computerId)
  else
    log("E", "mysummer", "mysummerProjectPartShop module not available")
    ui_message("Project Parts Shop not available", 4, "Parts", "error")
  end
end

local function onComputerAddFunctions(menuData, computerFunctions)
  if not isFullyInitialized then
    log("W", "mysummer", "onComputerAddFunctions called before initialization complete")
    return
  end

  if menuData and menuData.computerFacility and menuData.computerFacility.garageId and state.projectInventoryId then
    if career_modules_inventory and career_modules_inventory.moveVehicleToGarage then
      local garageId = menuData.computerFacility.garageId
      career_modules_inventory.moveVehicleToGarage(state.projectInventoryId, garageId)
      local vehId = career_modules_inventory.getVehicleIdFromInventoryId(state.projectInventoryId)
      if vehId then
        local vehObj = getObjectByID(vehId)
        if vehObj and freeroam_facilities then
          freeroam_facilities.teleportToGarage(garageId, vehObj)
        end
      end
    end
  end

  -- NOTE: Parts Market is now accessed via Internet Browser (mysummerInternet module)
  -- The browser navigates to different "websites" including PartsBay, SpeedParts, SilkRoad, etc.

  if computerFunctions and computerFunctions.vehicleSpecific then
    for vehicleId, functions in pairs(computerFunctions.vehicleSpecific) do
      -- Check if this is the project vehicle (ETK-I with plate 1234-ABC)
      local isProject = tonumber(vehicleId) == tonumber(state.projectInventoryId)

      if isProject then
        -- Remove the standard part shop for project vehicle
        functions.partShop = nil

        -- Add our custom project parts menu
        functions.projectPartsShop = {
          id = "projectPartsShop",
          label = "Install Parts (Project)",
          callback = function()
            log("I", "mysummer", ">>> PROJECT PARTS CALLBACK TRIGGERED! vehicleId=" .. tostring(vehicleId))
            openProjectPartsMenu(vehicleId, menuData.computerFacility.id)
          end,
          order = 1
        }
      else
        -- Normal vehicles get the standard label
        if functions.partShop then
          functions.partShop.label = "Install Parts"
        end
      end
    end
  end
end

local function onReachedTargetPos()
  if not isFullyInitialized or not state.activePickup then
    return
  end

  local targetPos = core_groundMarkers.getTargetPos()
  local pickupPos = toVec3(state.activePickup.location and state.activePickup.location.pos)
  if targetPos and pickupPos and targetPos:distance(pickupPos) < 6 then
    completePickup()
  end
end

-- Cargo transfer to inventory functions
local function isPlayerNearGarage()
  if not career_modules_garageManager then
    return false, nil
  end

  local playerPos = getPlayerPos()
  if not playerPos then
    return false, nil
  end

  local garages = freeroam_facilities.getFacilitiesByType("garage")
  if not garages then
    return false, nil
  end

  for garageId, garage in pairs(garages) do
    -- Check if garage is owned
    if career_modules_garageManager.isPurchasedGarage and career_modules_garageManager.isPurchasedGarage(garageId) then
      local garagePos = garage.pos and toVec3(garage.pos)
      if garagePos and playerPos:distance(garagePos) < 50 then
        return true, garageId
      end
    end
  end

  return false, nil
end

-- Transfer a cargo part from vehicle cargo to part inventory
local function transferCargoPartToInventory(cargoPart)
  -- Build proper part path for inventory system
  local slotPath = "/" .. cargoPart.slotType .. "/"
  local partPath = slotPath .. cargoPart.partName

  local partData = {
    name = cargoPart.partName,
    vehicleModel = cargoPart.vehicleModel,
    partCondition = cargoPart.condition and deepcopy(cargoPart.condition) or { integrityValue = 1, odometer = 0, visualValue = 1 },
    slot = cargoPart.slotType,
    slotType = cargoPart.slotType,
    containingSlot = slotPath,
    partPath = partPath,
    location = 0,
    baseValue = cargoPart.baseValue,
    value = cargoPart.baseValue,
    description = { description = cargoPart.partNiceName or cargoPart.partName },
  }

  local partId = addPartToInventory(partData)
  return partId
end

-- Unload all MySummer parts from cargo to inventory (must be at garage)
local function unloadAllCargo()
  local cargoModule = career_modules_mysummerCargo
  if not cargoModule then
    return { success = false, message = "Cargo system unavailable." }
  end

  local nearGarage, garageId = isPlayerNearGarage()
  if not nearGarage then
    return { success = false, message = "Must be at a garage to unload cargo." }
  end

  -- Get all MySummer parts from native cargo system
  local cargoParts = cargoModule.getMysummerCargoInVehicles()
  if #cargoParts == 0 then
    return { success = false, message = "No parts in cargo to unload." }
  end

  local transferred = 0
  local failed = 0

  for _, cargoPart in ipairs(cargoParts) do
    local partId = transferCargoPartToInventory(cargoPart)
    if partId then
      -- Remove from native cargo
      cargoModule.unloadCargoItem(cargoPart.cargoId)

      -- If this was the illegal cargo we were tracking, set it for pursuit tracking
      if state.pendingIllegalCargoId and cargoPart.cargoId == state.pendingIllegalCargoId then
        state.pendingIllegalPartId = partId
        state.pendingIllegalCargoId = nil
      end

      transferred = transferred + 1
      log("I", "mysummer", string.format("Transferred part '%s' from cargo to inventory (partId=%s)", cargoPart.partName, tostring(partId)))
    else
      failed = failed + 1
      log("W", "mysummer", string.format("Failed to transfer part '%s' to inventory", cargoPart.partName))
    end
  end

  saveState()

  if failed > 0 then
    return { success = true, transferred = transferred, failed = failed, message = string.format("Unloaded %d parts. %d failed.", transferred, failed) }
  else
    return { success = true, transferred = transferred, message = string.format("Unloaded %d parts to inventory.", transferred) }
  end
end

-- Get loaded cargo info using native cargo system
getLoadedCargoInfo = function()
  local cargoModule = career_modules_mysummerCargo
  local cargoParts = cargoModule and cargoModule.getMysummerCargoInVehicles() or {}

  local result = {
    count = #cargoParts,
    totalSlots = 0,
    totalWeight = 0,
    items = {},
    nearGarage = false,
  }

  for _, part in ipairs(cargoParts) do
    result.totalSlots = result.totalSlots + (part.slots or 0)
    result.totalWeight = result.totalWeight + (part.weight or 0)
    table.insert(result.items, {
      partName = part.partNiceName or part.partName,
      vehicleModel = part.vehicleModel,
      slots = part.slots,
      weight = part.weight,
      isIllegal = part.isIllegal,
      cargoId = part.cargoId,
    })
  end

  result.nearGarage = isPlayerNearGarage()
  return result
end

local marketCheckTimer = 0
local marketCheckInterval = 30  -- Check every 30 seconds

-- Heat check timer (don't check every frame)
local heatCheckTimer = 0
local HEAT_CHECK_INTERVAL = 5  -- Check every 5 seconds

local function onUpdate(dt)
  if not isFullyInitialized then
    return
  end

  -- Update criminal vehicles (timeout/stationary despawn)
  updateCriminals(dt)

  -- Heat system updates (periodically)
  heatCheckTimer = heatCheckTimer + dt
  if heatCheckTimer >= HEAT_CHECK_INTERVAL then
    heatCheckTimer = 0
    processHeatDecay()
    checkVehicleHeatReduction()
    -- Random police encounter based on heat (only check once per interval)
    checkAmbientPoliceEncounter()
  end

  -- Handle pending project parts data send (delayed to ensure Vue component is mounted)
  if pendingProjectPartsDataSend then
    pendingProjectPartsDataSend = pendingProjectPartsDataSend - dt
    if pendingProjectPartsDataSend <= 0 then
      pendingProjectPartsDataSend = nil
      sendProjectPartsData()
    end
  end

  if state.pendingInsuranceSync then
    if career_modules_insurance_insurance and career_modules_insurance_insurance.getInvVehs then
      if ensureInsuranceEntries() then
        state.pendingInsuranceSync = false
      end
    end
  elseif hasMissingInsuranceEntries() then
    queueInsuranceSync()
  end

  processPendingPartSeeds()

  -- Wallapop rotation: check for expired listings periodically
  marketCheckTimer = marketCheckTimer + dt
  if marketCheckTimer >= marketCheckInterval then
    marketCheckTimer = 0
    local now = os.time()
    local expiredCount = 0

    -- Remove expired listings
    for i = #state.listings, 1, -1 do
      if state.listings[i].expiresAt and now > state.listings[i].expiresAt then
        table.remove(state.listings, i)
        expiredCount = expiredCount + 1
      end
    end

    -- Remove expired leads
    for i = #state.leads, 1, -1 do
      if state.leads[i].expiresAt and now > state.leads[i].expiresAt then
        table.remove(state.leads, i)
        expiredCount = expiredCount + 1
      end
    end

    -- Regenerate stock if needed
    if expiredCount > 0 then
      ensureMarketStock()
      saveState()
      sendMarketUpdate()
    end
  end

  if not state.activePickup then
    return
  end

  local playerPos = getPlayerPos()
  local pickupPos = toVec3(state.activePickup.location and state.activePickup.location.pos)
  if playerPos and pickupPos and playerPos:distance(pickupPos) < 2 then
    completePickup()
  end
end

local function onPursuitAction(vehId, action, data)
  if not isFullyInitialized then
    return
  end

  local hasIllegalPart = state.pendingIllegalPartId ~= nil
  local hasIllegalCargo = state.pendingIllegalCargoId ~= nil

  if action == "arrest" then
    if hasIllegalPart then
      local removed = removePartFromInventory(state.pendingIllegalPartId)
      if removed then
        ui_message("Police seized your stolen part.", 4, "Parts Market", "warning")
      end
      state.pendingIllegalPartId = nil
    end
    if hasIllegalCargo then
      -- Remove illegal cargo using native cargo system
      local cargoModule = career_modules_mysummerCargo
      if cargoModule and cargoModule.unloadCargoItem then
        cargoModule.unloadCargoItem(state.pendingIllegalCargoId)
        ui_message("Police seized the stolen part from your cargo.", 4, "Parts Market", "warning")
      end
      state.pendingIllegalCargoId = nil
    end
    saveState()
    sendMarketUpdate()
  elseif action == "evade" then
    if hasIllegalPart then
      ui_message("You got away. Keep the part safe.", 3, "Parts Market")
      state.pendingIllegalPartId = nil
    end
    if hasIllegalCargo then
      ui_message("You lost them! The part is still in your cargo.", 3, "Parts Market")
      state.pendingIllegalCargoId = nil
    end
    saveState()
  end
end

local function initializeMySummer()
  local ready, reason = checkRLSModulesReady()
  if not ready then
    log("W", "mysummer", "Cannot initialize - " .. (reason or "RLS not ready"))
    return false
  end

  if not career_career.isActive() then
    log("W", "mysummer", "Career not active, skipping initialization")
    return false
  end

  log("I", "mysummer", "Initializing MySummer Career Extension...")
  loadState()
  ensureProjectConfig()
  queueInsuranceSync()
  ensureMarketStock()

  isFullyInitialized = true
  sendMarketUpdate()
  log("I", "mysummer", "MySummer Career Extension initialized successfully")
  return true
end

local function onCareerActive()
  -- This is called when career becomes active - perfect time to initialize
  initializeMySummer()
end

local function onExtensionLoaded()
  -- Don't initialize here - wait for onCareerActive
  -- Just log that extension is loaded
  log("I", "mysummer", "MySummer extension loaded, waiting for career activation...")
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

local function onSetupInventoryFinished()
  -- This is called after inventory is set up - good time to spawn initial vehicles
  if not isFullyInitialized then
    -- Try to initialize first
    local success = initializeMySummer()
    if not success then
      log("W", "mysummer", "onSetupInventoryFinished: Cannot initialize yet, deferring vehicle spawn")
      return
    end
  end

  -- Spawn initial vehicles (Miramar + ETK-I chassis)
  local spawnSuccess, spawnErr = pcall(spawnInitialVehicles)
  if not spawnSuccess then
    log("E", "mysummer", "Failed to spawn initial vehicles: " .. tostring(spawnErr))
  end
end

-- VENDOR INTEGRATION: Add vendor parts to illegal market
-- Called by mysummerDeepWeb when a vendor is unlocked
local function addVendorParts(vendorId, partsList)
  if not partsList or #partsList == 0 then
    log("W", "mysummer", "addVendorParts: No parts provided for vendor " .. tostring(vendorId))
    return
  end

  local cache = buildPartsCache(modelKey)
  local addedCount = 0

  for _, partName in ipairs(partsList) do
    -- Find the part in cache
    local part = nil
    for _, cachedPart in ipairs(cache.parts) do
      if cachedPart.name == partName then
        part = cachedPart
        break
      end
    end

    if not part then
      log("W", "mysummer", "addVendorParts: Part not found: " .. tostring(partName))
    else
      -- Create a special lead for this vendor part
      local location = pickLocation()

      local lead = {
        id = state.nextLeadId,
        partName = part.name,
        partNiceName = part.niceName,
        vehicleModel = modelKey,
        slotType = part.slotType,
        baseValue = part.value,
        price = 0,
        condition = buildCondition(true),
        location = location,
        createdAt = os.time(),
        isIllegal = true,
        heat = "normal",  -- Vendor parts are "safer"
        vendorId = vendorId,
        vendorExclusive = true,
        message = string.format("Your contact %s has a %s ready. Pick it up at %s.", vendorId, part.niceName, location.name),
      }

      -- Add color if body part
      if part.slotType and career_modules_mysummerCore then
        local slotLower = part.slotType:lower()
        if slotLower:find("body") or slotLower:find("fender") or
           slotLower:find("bumper") or slotLower:find("door") or
           slotLower:find("hood") or slotLower:find("trunk") then
          local paintInfo = career_modules_mysummerCore.generateRandomPaint()
          if paintInfo then
            lead.paintData = paintInfo.paintData
            lead.paintName = paintInfo.paintName
          end
        end
      end

      table.insert(state.leads, lead)
      state.nextLeadId = state.nextLeadId + 1
      addedCount = addedCount + 1
    end
  end

  saveState()
  sendMarketUpdate()

  log("I", "mysummer", string.format("Added %d vendor parts from %s", addedCount, vendorId))
end

-- PROJECT PARTS MENU FUNCTIONS

-- Category definitions for organizing parts
local slotCategories = {
  engine = { "engine", "intake", "exhaust", "turbo", "radiator", "oilpan", "fuel", "ecu", "internals", "flywheel", "transmission", "transfer", "driveshaft", "differential", "n2o" },
  suspension = { "suspension", "coilover", "swaybar", "brake", "steering", "hub", "axle", "wheeldata" },
  wheels = { "wheel", "tire", "rim" },
  body = { "body", "door", "hood", "trunk", "bumper", "fender", "grille", "mirror", "glass", "headlight", "taillight", "sideskirt", "spoiler", "licenseplate", "rollcage", "seat" },
  electrical = { "battery", "alternator", "light", "gauge", "switch" },
  other = {}  -- Catch-all for uncategorized parts
}

local categoryOrder = { "engine", "suspension", "wheels", "body", "electrical", "other" }

local categoryNames = {
  engine = "Engine & Drivetrain",
  suspension = "Suspension & Brakes",
  wheels = "Wheels & Tires",
  body = "Body & Interior",
  electrical = "Electrical",
  other = "Other Parts"
}

-- Determine category for a slot type
local function getCategoryForSlot(slotType)
  if not slotType or type(slotType) ~= "string" then return "other" end
  local slotLower = string.lower(slotType)

  for category, keywords in pairs(slotCategories) do
    for _, keyword in ipairs(keywords) do
      if string.find(slotLower, keyword) then
        return category
      end
    end
  end
  return "other"
end

-- Get data for the project parts menu (forward declared at top of file)
getProjectPartsData = function()
  if not state.projectInventoryId then
    return { success = false, error = "No project vehicle" }
  end

  -- Initialize categories
  local categories = {}
  for _, cat in ipairs(categoryOrder) do
    categories[cat] = {
      id = cat,
      name = categoryNames[cat],
      inventoryParts = {},
      shopParts = {}  -- Only for wheels category
    }
  end

  -- Get parts from part inventory that can be installed on the project vehicle
  if career_modules_partInventory then
    local allParts = career_modules_partInventory.getInventory() or {}
    for partId, part in pairs(allParts) do
      -- Only show parts for ETK-I that are in storage (location = 0 or nil) and not on a vehicle
      if part.vehicleModel == "etki" and (part.location == 0 or part.location == nil) then
        local category = getCategoryForSlot(part.slot)
        table.insert(categories[category].inventoryParts, {
          id = partId,
          name = part.name,
          niceName = part.description and part.description.description or part.name,
          slotType = part.slot,
          slotNiceName = part.slotNiceName or part.slot,
          condition = part.partCondition,
          value = part.value or 0,
          fromInventory = true
        })
      end
    end
  end

  -- Get wheel/tire options from the parts cache (these can be purchased)
  local cache = buildPartsCache(modelKey)
  if cache and cache.parts then
    for _, part in ipairs(cache.parts) do
      if part and type(part.slotType) == "string" then
        local category = getCategoryForSlot(part.slotType)
        -- Only add shop parts for wheels category
        if category == "wheels" then
          table.insert(categories.wheels.shopParts, {
            name = part.name or "Unknown",
            niceName = part.niceName or part.name or "Unknown Part",
            slotType = part.slotType,
            slotNiceName = part.slotNiceName or part.slotType,
            value = part.value or 0,
            fromInventory = false
          })
        end
      end
    end
  end

  -- Convert to array for Vue and filter empty categories
  local result = {}
  for _, cat in ipairs(categoryOrder) do
    local catData = categories[cat]
    local totalParts = #catData.inventoryParts + #catData.shopParts
    if totalParts > 0 then
      table.insert(result, catData)
    end
  end

  return {
    success = true,
    projectInventoryId = state.projectInventoryId,
    categories = result
  }
end

-- Install a part from inventory onto the project vehicle
local function installProjectPart(partId)
  if not state.projectInventoryId then
    return { success = false, error = "No project vehicle" }
  end

  if not partId then
    return { success = false, error = "No part specified" }
  end

  log("I", "mysummer", "Installing part " .. tostring(partId) .. " on project vehicle " .. tostring(state.projectInventoryId))

  -- Get the part from inventory
  local partInventory = career_modules_partInventory
  if not partInventory then
    return { success = false, error = "Part inventory not available" }
  end

  local allParts = partInventory.getInventory() or {}
  local part = allParts[partId]

  if not part then
    return { success = false, error = "Part not found in inventory" }
  end

  -- Get vehicle ID from inventory ID
  local vehicleId = career_modules_inventory.getVehicleIdFromInventoryId(state.projectInventoryId)
  if not vehicleId then
    return { success = false, error = "Vehicle not spawned" }
  end

  -- Use businessComputer to install the part
  local businessComputer = career_modules_business_businessComputer
  if not businessComputer or not businessComputer.applyCartPartsToVehicle then
    return { success = false, error = "Business computer not available" }
  end

  -- Build the cart with this single part
  local cartPart = {
    type = 'part',
    partName = part.name,
    slotPath = part.slot or "",
    fromInventory = true,
    partId = partId,
    price = 0
  }

  -- Apply the part to the vehicle
  log("I", "mysummer", "Calling applyCartPartsToVehicle with vehicleId=" .. tostring(vehicleId) .. " partName=" .. tostring(part.name))
  local success = businessComputer.applyCartPartsToVehicle(nil, vehicleId, { cartPart })
  log("I", "mysummer", "applyCartPartsToVehicle result: " .. tostring(success))

  if success then
    -- Refresh the data
    sendProjectPartsData()
    log("I", "mysummer", "Part installed successfully")
    return { success = true, message = "Part installed successfully" }
  else
    log("W", "mysummer", "Failed to install part")
    return { success = false, error = "Failed to install part" }
  end
end

-- Purchase and install a wheel/tire from the shop
local function purchaseProjectWheelTire(partName, slotType, price)
  if not state.projectInventoryId then
    return { success = false, error = "No project vehicle" }
  end

  log("I", "mysummer", "Purchasing wheel/tire: " .. tostring(partName) .. " for $" .. tostring(price))

  -- Check if player has enough money
  local payment = career_modules_payment
  if not payment or not payment.canPay then
    return { success = false, error = "Payment system not available" }
  end

  -- Check if player can afford
  if not payment.canPay({ money = { amount = price } }) then
    return { success = false, error = "Not enough money" }
  end

  -- Deduct payment
  local paySuccess = payment.pay({ money = { amount = price } }, { label = "Wheel/Tire: " .. partName })
  if not paySuccess then
    return { success = false, error = "Payment failed" }
  end

  -- Get vehicle ID
  local vehicleId = career_modules_inventory.getVehicleIdFromInventoryId(state.projectInventoryId)
  if not vehicleId then
    return { success = false, error = "Vehicle not spawned" }
  end

  -- Use businessComputer to install
  local businessComputer = career_modules_business_businessComputer
  if not businessComputer or not businessComputer.applyCartPartsToVehicle then
    -- Refund if we can't install
    payment.reward({ money = { amount = price } }, { label = "Refund: " .. partName })
    return { success = false, error = "Cannot install part" }
  end

  local cartPart = {
    type = 'part',
    partName = partName,
    slotPath = slotType or "",
    fromInventory = false,
    price = price
  }

  log("I", "mysummer", "Purchase: calling applyCartPartsToVehicle vehicleId=" .. tostring(vehicleId) .. " partName=" .. tostring(partName) .. " slotPath=" .. tostring(slotType))
  local success = businessComputer.applyCartPartsToVehicle(nil, vehicleId, { cartPart })
  log("I", "mysummer", "Purchase: applyCartPartsToVehicle result: " .. tostring(success))

  if success then
    sendProjectPartsData()
    log("I", "mysummer", "Purchase: Wheel/tire installed successfully")
    return { success = true, message = "Wheel/tire installed" }
  else
    -- Refund on failure
    log("W", "mysummer", "Purchase: Failed to install, refunding")
    payment.reward({ money = { amount = price } }, { label = "Refund: " .. partName })
    return { success = false, error = "Failed to install" }
  end
end

-- Close the project parts menu
local function closeProjectPartsMenu()
  if originComputerId then
    local computer = freeroam_facilities.getFacility("computer", originComputerId)
    if computer then
      career_modules_computer.openMenu(computer)
      return
    end
  end
  career_career.closeAllMenus()
end

M.getProjectPartsData = getProjectPartsData
M.sendProjectPartsData = sendProjectPartsData
M.installProjectPart = installProjectPart
M.purchaseProjectWheelTire = purchaseProjectWheelTire
M.closeProjectPartsMenu = closeProjectPartsMenu
M.getMarketData = getMarketData
M.refreshListings = refreshListings
M.acceptListing = acceptListing
M.acceptMultipleListings = acceptMultipleListings
M.acceptLead = acceptLead
M.cancelActivePickup = cancelActivePickup
M.openMenuFromComputer = openMenuFromComputer
M.closeMenu = closeMenu
M.closeAllMenus = closeAllMenus
M.addVendorParts = addVendorParts

-- Cargo functions
M.unloadAllCargo = unloadAllCargo
M.getLoadedCargoInfo = getLoadedCargoInfo
M.isPlayerNearGarage = isPlayerNearGarage

-- Heat system functions
M.getPlayerHeat = getPlayerHeat
M.addPlayerHeat = addPlayerHeat
M.clearPlayerHeat = clearPlayerHeat

-- First purchase tracking (for Ghost contact unlock)
M.hasFirstPurchase = function()
  return state.firstPurchaseMade == true
end

M.triggerFirstPurchase = function()
  if state.firstPurchaseMade then return end  -- Already triggered

  state.firstPurchaseMade = true
  log("I", "mysummer", "First purchase triggered! Unlocking Ghost contact.")

  -- Notify Deep Web module
  if career_modules_mysummerDeepWeb and career_modules_mysummerDeepWeb.onFirstPurchase then
    career_modules_mysummerDeepWeb.onFirstPurchase()
  end

  saveState()
end

M.onComputerAddFunctions = onComputerAddFunctions
M.onReachedTargetPos = onReachedTargetPos
M.onUpdate = onUpdate
M.onPursuitAction = onPursuitAction
M.onCareerActive = onCareerActive
M.onExtensionLoaded = onExtensionLoaded
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onSetupInventoryFinished = onSetupInventoryFinished

return M
