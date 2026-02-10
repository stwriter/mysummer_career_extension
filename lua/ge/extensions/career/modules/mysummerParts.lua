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
  -- Note: career_modules_mysummerCargo is optional - depends on base game delivery modules that may not load
  -- Note: mysummerCareer is optional to avoid circular deps - checked at runtime
  -- Note: insurance_insurance is optional - we check for it but don't require it
  -- "gameplay_police" is also optional
}

local jbeamIO = require("jbeam/io")
local freeroam_facilities = require("freeroam/facilities")
local core_groundMarkers = require("core/groundMarkers")

-- Save file in mysummer subdirectory
local saveFileName = "mysummer_market.json"
local modelKey = "etki"
local targetListings = 40  -- Was 6; expanded for larger PartsBay catalog
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
  completingPickup = false,  -- Guard to prevent duplicate pickup during async cargo loading
  pendingPickups = {},  -- Queue of selected pickups for multiple selection
  hasInitialVehicles = false,
  projectInventoryId = nil,
  pendingIllegalPartId = nil,  -- Part ID in inventory (after unloading)
  pendingIllegalCargoId = nil,  -- Cargo ID in vehicle (before unloading)
  pendingInsuranceSync = false,
  pendingPartSeeds = {},
  carryingParts = {},  -- Parts loaded in cargo, tracked locally (like SpeedParts pattern)
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

local function getSavePath(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  local effectivePath = currentSavePath or savePath
  if not effectivePath then
    return nil
  end
  local dirPath = effectivePath .. "/career/mysummer"
  FS:directoryCreate(dirPath, true)
  return dirPath .. "/" .. saveFileName
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
  state.completingPickup = false  -- Always reset transient flag on load
  state.pendingPickups = data.pendingPickups or {}
  state.hasInitialVehicles = data.hasInitialVehicles or false
  state.projectInventoryId = data.projectInventoryId or nil
  state.pendingIllegalPartId = data.pendingIllegalPartId or nil
  state.pendingIllegalCargoId = data.pendingIllegalCargoId or nil
  state.carryingParts = data.carryingParts or {}
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
    carryingParts = state.carryingParts,
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
        -- MySummer: Exclude parts from other vehicles (only ETK-I and generic parts allowed)
        local lowerPartName = string.lower(partName)
        local otherVehiclePrefixes = {
          "pickup_", "pigeon_", "fullsize_", "van_", "covet_", "legran_",
          "roamer_", "d_series_", "semi_", "sunburst_", "pessima_", "midsize_",
          "hopper_", "moonhawk_", "bluebuck_", "bolide_", "barstow_", "burnside_",
          "wendover_", "vivace_", "sbr_", "scintilla_", "autobello_", "miramar_",
          "bastion_", "lansdale_", "alder_", "bogie_", "trailer_",
        }
        local isOtherVehicle = false
        for _, prefix in ipairs(otherVehiclePrefixes) do
          if lowerPartName:find("^" .. prefix) then
            isOtherVehicle = true
            break
          end
        end

        if not isOtherVehicle then
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
            "wheel", "tire", "hubcap",           -- Wheels & Tires (available in SpeedParts)
            "paint", "skin", "lettering", "logo", "sunstrip",  -- Cosmetics
            "licenseplate",                       -- License plates
            -- "glass", "windshield",             -- Glass/windows - now allowed in PartsBay
            "toolbox", "tonneau", "canopy",       -- Cargo accessories (specific items only)
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
        end -- not isOtherVehicle
      end
    end
  end

  table.sort(parts, function(a, b) return a.value < b.value end)
  local legalCut = math.max(1, math.floor(#parts * 0.9))  -- Was 0.7; expanded to include more parts in PartsBay
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
  -- NOTE: BeamNG odometer is in METERS, not km. Multiply by 1000 to get realistic km values.
  -- Legal parts: 5,000 - 200,000 km  |  Illegal/stolen: 0 - 8,000 km
  local odometerKm = isIllegal and math.random(0, 8000) or math.random(5000, 200000)
  return {
    integrityValue = 1,
    odometer = odometerKm * 1000,  -- Convert km to meters for BeamNG
    visualValue = 1,
  }
end

-- ============================================================================
-- LISTING DESCRIPTIONS (Humorous second-hand ad style, bilingual)
-- Organized by specific part type so descriptions reference the actual part.
-- ============================================================================

-- Generic descriptions that work for ANY part (no part-specific references)
local genericDescriptions = {
  {es = "Bendo por no usar. Nunca circuito, solo garaje.", en = "Selling bc not using. Never raced, garage only."},
  {es = "Urge bender por mudanza. No hago envios.", en = "Urgent sale, moving. No shipping."},
  {es = "Funciona perfectamente. La cambio porque quiero una mejor.", en = "Works perfectly. Changing bc I want a better one."},
  {es = "Original de fabrica, no replica. Casi seguro.", en = "Factory original, not replica. Pretty sure."},
  {es = "Mi mecanico dice que esta bien. Yo no entiendo de coches.", en = "My mechanic says its fine. I dont know about cars."},
  {es = "Regalo por dejar el hobby. Mi mujer me ha dado un ultimatum.", en = "Giving away, quitting the hobby. Wife gave me an ultimatum."},
  {es = "La compre nueva pero nunca la monte. Perdi las ganas.", en = "Bought it new but never installed it. Lost motivation."},
  {es = "Esta como nueva. Bueno, casi. Bueno, funciona.", en = "Like new. Well, almost. Well, it works."},
  {es = "Vendo por necesidad economica. No acepto cambios.", en = "Selling out of financial need. No trades."},
  {es = "La tenia de repuesto y nunca la necesite. Su ganancia.", en = "Had it as a spare and never needed it. Your gain."},
  {es = "Precio de ganga. Si la quieres ven hoy, manyana no estara.", en = "Bargain price. If you want it come today, tomorrow its gone."},
  {es = "Solo 3 duenyos anteriores. Todos mecanicos de confianza.", en = "Only 3 previous owners. All trusted mechanics."},
  {es = "Se la quite al coche antes de venderlo. Lastima desperdiciarla.", en = "Took it off the car before selling. Shame to waste it."},
  {es = "Garantia: si se rompe me llamas y hablamos.", en = "Warranty: if it breaks call me and we'll talk."},
  {es = "No tengo factura pero te doy mi palabra.", en = "No receipt but you have my word."},
  {es = "Ideal para el que sepa. Yo no se pero me han dicho que vale.", en = "Ideal for someone who knows. I dont but was told its good."},
  {es = "Mi hijo la compro y resulta que era para otro coche. Juventud...", en = "My son bought it and turns out it was for another car. Kids..."},
  {es = "Desmontada con carinio y herramientas profesionales (un martillo).", en = "Removed with care and professional tools (a hammer)."},
  {es = "La tuve guardada 5 anyos. Ahora necesito el espacio.", en = "Stored it for 5 years. Now I need the space."},
  {es = "Acepto ofertas razonables. Y tambien las que no.", en = "Accepting reasonable offers. And unreasonable ones too."},
  {es = "No me llamen antes de las 12, curro de noche.", en = "Dont call before noon, I work nights."},
  {es = "Pieza verificada por mi vecino que sabe mucho de coches.", en = "Part verified by my neighbor who knows a lot about cars."},
  {es = "La vendo mas barata que nueva. Logico, no es nueva.", en = "Selling cheaper than new. Obviously, its not new."},
  {es = "Compatible con ETK-I. Creo. Mejor que lo verifiques tu.", en = "Compatible with ETK-I. I think. Better verify yourself."},
  {es = "La saque del coche de mi cunyao. El dice que funciona.", en = "Took it from my brother-in-law's car. He says it works."},
  {es = "Tiene un poquito de oxido pero pa eso esta el papel de lija.", en = "Has a lil rust but thats what sandpaper is for."},
  {es = "El envoltorio original se perdio en la mudanza. La pieza esta 10/10.", en = "Lost the original packaging in the move. Part is 10/10."},
  {es = "En perfecto estado, solo tiene 180.000km. Precio no negociable.", en = "Perfect condition, only 180,000km. Price firm."},
  {es = "Solo un aranhazo estetico. No afecta al funcionamiento. Creo.", en = "Just a cosmetic scratch. Doesnt affect function. I think."},
  {es = "Solo usada los domingos para ir a misa. 200.000km.", en = "Only used Sundays for church. 200,000km."},
}

-- Part-specific descriptions: each key is a pattern matched against slotType+partName
-- Descriptions MUST reference that specific part type
local partSpecificDescriptions = {
  -- === ENGINE BLOCK ===
  engine = {
    {es = "Bloque motor sacado de un ETK con 50.000km. Arrancaba a la primera.", en = "Engine block from an ETK with 50,000km. Started first try."},
    {es = "Motor completo. Suena como un gatito... un gatito con asma.", en = "Complete engine. Sounds like a kitten... a kitten with asthma."},
    {es = "Motor reconstruido. Bueno, le cambie las bujias y lo limpie.", en = "Rebuilt engine. Well, I changed the spark plugs and cleaned it."},
    {es = "Motor con mucha vida. Eso o el ruido que hace es normal.", en = "Engine with lots of life. That or the noise it makes is normal."},
    {es = "El motor perfecto para tu proyecto. O para un ancla muy cara.", en = "The perfect engine for your project. Or for a very expensive anchor."},
  },
  -- === TURBO ===
  turbo = {
    {es = "Turbo en buen estado. Solo echa un poquito de humo azul al arrancar.", en = "Turbo in good condition. Only a little blue smoke on startup."},
    {es = "Turbo sin holgura en el eje. Lo comprobe girandolo con el dedo.", en = "Turbo with no shaft play. Checked by spinning it with my finger."},
    {es = "Turbo stage 1. Transforma tu coche en un cohete. O en una bomba.", en = "Stage 1 turbo. Turns your car into a rocket. Or a bomb."},
    {es = "Turbo funcional. La caracola tiene un arayanzo pero le da caracter.", en = "Working turbo. Housing has a scratch but it adds character."},
  },
  -- === RADIATOR ===
  radiator = {
    {es = "Radiador sin fugas. Lo probe llenandolo de agua del grifo.", en = "Radiator no leaks. Tested by filling it with tap water."},
    {es = "Radiador de aluminio. Enfria mejor que el de serie. En teoria.", en = "Aluminum radiator. Cools better than stock. In theory."},
    {es = "Radiador con todas las aletas intactas. Bueno, casi todas.", en = "Radiator with all fins intact. Well, almost all of them."},
  },
  -- === EXHAUST ===
  exhaust = {
    {es = "Escape deportivo. Los vecinos te odiaran. Merece la pena.", en = "Sport exhaust. Neighbors will hate you. Worth it."},
    {es = "Escape de acero inoxidable. Solo tiene un poquito de oxido.", en = "Stainless steel exhaust. Only has a tiny bit of rust."},
    {es = "Escape con sonido grave. Ideal para despertar al barrio a las 6am.", en = "Exhaust with deep sound. Ideal for waking the neighborhood at 6am."},
    {es = "Colector de escape en buen estado. Sin fisuras visibles.", en = "Exhaust manifold in good shape. No visible cracks."},
  },
  -- === INTAKE / AIR FILTER ===
  intake = {
    {es = "Admision directa. +5cv asegurados. Bueno, eso dice la caja.", en = "Cold air intake. +5hp guaranteed. Well, thats what the box says."},
    {es = "Filtro de aire reutilizable. Lo limpie con el secador de mi mujer.", en = "Reusable air filter. Cleaned it with my wifes hair dryer."},
    {es = "Kit de admision completo. Tu motor respirara mejor que tu.", en = "Full intake kit. Your engine will breathe better than you."},
  },
  -- === ECU / ELECTRONICS ===
  ecu = {
    {es = "ECU original. No hackeada. Bueno, solo un poquito.", en = "Original ECU. Not hacked. Well, just a little."},
    {es = "Centralita con mapeo de serie. O eso quiero creer.", en = "ECU with stock mapping. Or so I want to believe."},
    {es = "ECU en perfecto estado. La guarde en una bolsa de arroz por si acaso.", en = "ECU in perfect condition. Stored it in a bag of rice just in case."},
  },
  -- === TRANSMISSION ===
  transmission = {
    {es = "Caja de cambios manual. 5 marchas. Todas entran. Casi todas.", en = "Manual gearbox. 5 gears. All engage. Most of them."},
    {es = "Transmision con 60.000km. La tercera cruje un poquito, es normal.", en = "Transmission with 60,000km. Third gear crunches a bit, its normal."},
    {es = "Caja de cambios racing. Ideal para circuito. No para ir al super.", en = "Racing gearbox. Ideal for track. Not for grocery shopping."},
  },
  -- === CLUTCH ===
  clutch = {
    {es = "Embrague con vida util restante. Cuanta? No se, alguna.", en = "Clutch with remaining life. How much? Dunno, some."},
    {es = "Kit de embrague completo. El disco tiene buen grosor todavia.", en = "Full clutch kit. The disc still has good thickness."},
    {es = "Embrague reforzado. Ideal para mas de 200cv. O para atascos.", en = "Reinforced clutch. Ideal for 200+hp. Or for traffic jams."},
  },
  -- === DIFFERENTIAL ===
  differential = {
    {es = "Diferencial trasero. Hace un ruidito pero dicen que es normal.", en = "Rear diff. Makes a little noise but they say its normal."},
    {es = "Diferencial autoblocante. Tus ruedas traseras te lo agradeceran.", en = "LSD differential. Your rear tires will thank you."},
    {es = "Diferencial con aceite recien cambiado. Bueno, hace 2 anyos.", en = "Diff with freshly changed oil. Well, 2 years ago."},
  },
  -- === FLYWHEEL ===
  flywheel = {
    {es = "Volante motor aligerado. Ideal para subir de vueltas rapido.", en = "Lightened flywheel. Ideal for quick revving."},
    {es = "Volante motor bimasa. Todavia no cascabelea. Todavia.", en = "Dual-mass flywheel. Doesnt rattle yet. Yet."},
  },
  -- === DRIVESHAFT ===
  driveshaft = {
    {es = "Arbol de transmision equilibrado. No vibra. Casi no vibra.", en = "Balanced driveshaft. No vibrations. Almost no vibrations."},
    {es = "Palier en buen estado. Las gomas estan blanditas pero aguantan.", en = "CV axle in good shape. Boots are soft but holding up."},
  },
  -- === OIL PAN / OIL COOLER ===
  oilpan = {
    {es = "Carter de aceite sin abolladuras. Milagrosamente.", en = "Oil pan with no dents. Miraculously."},
    {es = "Carter reforzado. Ideal si te gustan los bordillos.", en = "Reinforced oil pan. Ideal if you like curbs."},
  },
  oilcooler = {
    {es = "Radiador de aceite. Tu motor se mantendra fresquito.", en = "Oil cooler. Your engine will stay nice and cool."},
    {es = "Radiador de aceite con latiguillos incluidos. Ganga.", en = "Oil cooler with lines included. Bargain."},
  },
  -- === INTERCOOLER ===
  intercooler = {
    {es = "Intercooler grande. Tu motor lo agradecera. Tu cartera no.", en = "Big intercooler. Your engine will thank you. Your wallet wont."},
    {es = "Intercooler frontal. Aire frio = mas potencia. Ciencia basica.", en = "Front mount intercooler. Cold air = more power. Basic science."},
  },
  -- === FUEL ===
  fuel = {
    {es = "Bomba de gasolina. Bombea. Que mas quieres.", en = "Fuel pump. It pumps. What more do you want."},
    {es = "Deposito de combustible sin fugas. Lo llene de agua para probarlo.", en = "Fuel tank no leaks. Filled it with water to test."},
    {es = "Inyectores limpios. Los lave con limpiacristales.", en = "Clean injectors. Washed them with window cleaner."},
  },
  -- === N2O ===
  n2o = {
    {es = "Kit de nitro. Rapido y furioso edition. Pegatina incluida.", en = "Nitro kit. Fast and Furious edition. Sticker included."},
    {es = "Sistema NOS. Nunca usado en via publica. Eso digo yo.", en = "NOS system. Never used on public roads. Thats my story."},
  },
  -- === SUSPENSION (generic) ===
  suspension = {
    {es = "Amortiguadores con 40.000km. Solo chillan un poco en frio.", en = "Shocks with 40,000km. Only squeak a bit when cold."},
    {es = "Muelles deportivos. Tu espalda te odiara pero tu coche volara.", en = "Sport springs. Your back will hate you but your car will fly."},
    {es = "Suspension de segunda mano. El coche que la tenia iba muy fino.", en = "Used suspension. The car it was on rode very smooth."},
  },
  -- === COILOVERS ===
  coilover = {
    {es = "Coilovers ajustables. Los puse duro y me dolio la espalda.", en = "Adjustable coilovers. Set them stiff and my back hurt."},
    {es = "Coilovers regulables en altura. Baja el coche sin poner tacos de madera.", en = "Height-adjustable coilovers. Lower the car without wooden blocks."},
    {es = "Coilovers con 20.000km. Todavia tienen la pegatina del fabricante.", en = "Coilovers with 20,000km. Still have the manufacturer sticker."},
  },
  -- === STRUT ===
  strut = {
    {es = "Torretas reforzadas. Ideales si tu coche vibra como una lavadora.", en = "Reinforced strut towers. Ideal if your car shakes like a washing machine."},
    {es = "Barra de torretas. Le da rigidez al chasis. Y a tu vida.", en = "Strut bar. Adds rigidity to the chassis. And to your life."},
  },
  -- === SWAY BAR ===
  swaybar = {
    {es = "Barra estabilizadora. Estabiliza. No se que mas decir.", en = "Sway bar. It stabilizes. Dunno what else to say."},
    {es = "Barra estabilizadora mas gruesa. Menos balanceo, mas control.", en = "Thicker sway bar. Less body roll, more control."},
  },
  -- === BRAKES ===
  brake = {
    {es = "Discos de freno. Aun les queda material. Algo.", en = "Brake discs. Still have material left. Some."},
    {es = "Pastillas de freno semi-racing. Frenan bien cuando calientan.", en = "Semi-racing brake pads. Brake well when warmed up."},
    {es = "Kit de frenos delantero. Paran el coche. Que es lo importante.", en = "Front brake kit. They stop the car. Which is whats important."},
    {es = "Pinzas de freno reconstruidas. Les cambie el liquido y listo.", en = "Rebuilt brake calipers. Changed the fluid and done."},
    {es = "Frenos en buen estado. Testados en situacion real de panico.", en = "Brakes in good condition. Tested in a real panic situation."},
  },
  -- === STEERING ===
  steering = {
    {es = "Caja de direccion. Gira para los dos lados, que no es poco.", en = "Steering box. Turns both ways, which is something."},
    {es = "Direccion asistida. Asiste bastante. A veces demasiado.", en = "Power steering. Assists plenty. Sometimes too much."},
    {es = "Cremallera de direccion sin juego. Bueno, con juego minimo.", en = "Steering rack with no play. Well, minimal play."},
  },
  -- === BUMPER ===
  bumper = {
    {es = "Paragolpes sin golpes. Ironico, lo se.", en = "Bumper without bumps. Ironic, I know."},
    {es = "Paragolpes original ETK-I. Ningun arbol fue danyado en su uso.", en = "Original ETK-I bumper. No trees were harmed during its use."},
    {es = "Paragolpes con soporte incluido. Listo para montar y chocar.", en = "Bumper with bracket included. Ready to mount and crash."},
  },
  -- === HOOD ===
  hood = {
    {es = "Capo en buen estado. Solo una pequenya abolladura de granizo.", en = "Hood in good shape. Just a small hail dent."},
    {es = "Capo con toma de aire. +15cv visuales garantizados.", en = "Hood with air scoop. +15 visual hp guaranteed."},
    {es = "Capo original. Abre, cierra, y tiene bisagras. Completo.", en = "Original hood. Opens, closes, and has hinges. Complete."},
  },
  -- === TRUNK ===
  trunk = {
    {es = "Tapa del maletero. Cierra bien. Hay que dar un golpecito.", en = "Trunk lid. Closes well. Just needs a little bump."},
    {es = "Maletero con llave original. Bueno, con una llave que encaja.", en = "Trunk with original key. Well, with a key that fits."},
  },
  -- === DOOR ===
  door = {
    {es = "Puerta completa con cristal. El cristal tiene un arayanzo.", en = "Complete door with glass. Glass has a scratch."},
    {es = "Puerta con mecanismo electrico. Sube y baja. A veces sola.", en = "Door with electric mechanism. Goes up and down. Sometimes by itself."},
    {es = "Puerta en buen color. Bueno, parecido al tuyo. Con sol.", en = "Door in good color. Well, similar to yours. In sunlight."},
  },
  -- === FENDER ===
  fender = {
    {es = "Aleta delantera sin oxido. Color original. Creo.", en = "Front fender no rust. Original color. I think."},
    {es = "Aleta ancha tipo rally. Tu coche parecera un WRC. De lejos.", en = "Wide fender flare, rally style. Your car will look like a WRC. From far away."},
    {es = "Guardabarros sin golpes. La quite antes de que le pasara algo.", en = "Fender with no dents. Removed it before anything could happen."},
  },
  -- === MIRROR ===
  mirror = {
    {es = "Espejo retrovisor completo. Te veras guapo mientras conduces.", en = "Complete side mirror. Youll look handsome while driving."},
    {es = "Retrovisor electrico. Se pliega solo. Cuando quiere.", en = "Electric mirror. Folds by itself. When it wants to."},
  },
  -- === SPOILER / WING ===
  spoiler = {
    {es = "Aleron trasero. +10 caballos garantizados. Fuente: creeme.", en = "Rear spoiler. +10hp guaranteed. Source: trust me."},
    {es = "Aleron racing. Downforce real a partir de 200km/h. O eso dicen.", en = "Racing wing. Real downforce above 200km/h. Or so they say."},
    {es = "Aleron original ETK-I. Discreto pero funcional. Dice el fabricante.", en = "Original ETK-I spoiler. Subtle but functional. Says the manufacturer."},
  },
  -- === SIDESKIRT ===
  sideskirt = {
    {es = "Faldones laterales. Le dan un look deportivo al coche.", en = "Side skirts. Give the car a sporty look."},
    {es = "Taloneras sin rozaduras. Nunca entre en un parking bajo.", en = "Side skirts with no scrapes. I never went into a low parking garage."},
  },
  -- === GRILLE ===
  grille = {
    {es = "Parrilla delantera. Faltan 2 listones pero no se nota.", en = "Front grille. Missing 2 slats but you cant tell."},
    {es = "Calandra en buen estado. Solo tiene un mosquito incrustado.", en = "Grille in good shape. Only has one embedded bug."},
  },
  -- === GLASS / WINDSHIELD ===
  glass = {
    {es = "Cristal sin tinte. O sea, legal.", en = "Glass, no tint. Meaning, legal."},
    {es = "Cristal original ETK-I. Sin aranyazos. Visible.", en = "Original ETK-I glass. No scratches. Visible ones."},
  },
  windshield = {
    {es = "Parabrisas con una estrellita de piedra abajo a la derecha.", en = "Windshield with one small stone chip, bottom right."},
    {es = "Parabrisas original. Sin grietas. Las micro-fisuras no cuentan.", en = "Original windshield. No cracks. Micro-cracks dont count."},
  },
  -- === HEADLIGHT / TAILLIGHT ===
  headlight = {
    {es = "Faros delanteros. Iluminan. Eso es lo importante.", en = "Headlights. They light up. Thats whats important."},
    {es = "Opticas delanteras cristalinas. Las puli con pasta de dientes.", en = "Clear headlights. Polished them with toothpaste."},
  },
  taillight = {
    {es = "Pilotos traseros. Un poco amarillentos pero funcionales.", en = "Tail lights. A bit yellowed but functional."},
    {es = "Pilotos originales. Se encienden los dos. A la vez incluso.", en = "Original tail lights. Both light up. Even at the same time."},
  },
  -- === SEAT ===
  seat = {
    {es = "Asiento deportivo. Muy comodo para sprints. No para viajes largos.", en = "Sport seat. Very comfy for sprints. Not for road trips."},
    {es = "Asiento con arneses de 4 puntos. Tu copiloto te odiara.", en = "Seat with 4-point harness. Your copilot will hate you."},
    {es = "Bucket seat. Te mantiene en sitio. Literalmente no te puedes mover.", en = "Bucket seat. Keeps you in place. Literally cant move."},
  },
  -- === ROLLCAGE ===
  rollcage = {
    {es = "Jaula antivuelco. Esperemos que no la necesites.", en = "Roll cage. Lets hope you wont need it."},
    {es = "Barra antivuelco homologada. Para que ITV no te mire mal.", en = "Approved roll bar. So inspection wont give you the look."},
  },
  -- === BATTERY / ALTERNATOR ===
  battery = {
    {es = "Bateria nueva. Del anyo pasado. Carga bien.", en = "New battery. From last year. Charges fine."},
    {es = "Bateria con terminal limpio. La cargue antes de venderla.", en = "Battery with clean terminals. Charged it before selling."},
  },
  alternator = {
    {es = "Alternador funcional. Alterna. No se mucho mas.", en = "Working alternator. It alternates. Dont know much more."},
    {es = "Alternador reconstruido. Los escobillos son nuevos al menos.", en = "Rebuilt alternator. The brushes are new at least."},
  },
  -- === GPS ===
  gps = {
    {es = "GPS original. Los mapas son del 2015 pero las calles no cambian tanto.", en = "Original GPS. Maps from 2015 but streets dont change much."},
    {es = "Navegador con voz. Te grita las direcciones. Como mi ex.", en = "GPS with voice. Yells directions at you. Like my ex."},
  },
}

-- Bundle-specific descriptions
local bundleDescriptions = {
  {es = "Despiece de ETK-I accidentado. Lo que no se rompio, aqui esta.", en = "Salvage from crashed ETK-I. What didnt break is here."},
  {es = "Lote de piezas de un ETK-I que se jubila. Buen precio.", en = "Parts lot from a retiring ETK-I. Good price."},
  {es = "Me sobran estas piezas del proyecto que no acabe.", en = "Leftover parts from the project I never finished."},
  {es = "ETK-I de desguace, seleccion de piezas aprovechables.", en = "Junkyard ETK-I, selection of usable parts."},
  {es = "Compra a ciegas. Buen precio, sin devoluciones.", en = "Blind buy. Good price, no returns."},
  {es = "Lote sorpresa. Puede salir algo bueno. O no. Suerte!", en = "Surprise lot. Might get something good. Or not. Good luck!"},
  {es = "Mi mecanico dijo: esto vale, esto no. Aqui esta lo que vale.", en = "My mechanic said: this is good, this isnt. Heres the good stuff."},
  {es = "Todo original ETK-I. Sin garantia pero con carinho.", en = "All original ETK-I. No warranty but with love."},
  {es = "Estas piezas cuentan historias. Sobre todo la del accidente.", en = "These parts tell stories. Especially the one about the crash."},
  {es = "Vendo lote porque necesito sitio para el siguiente proyecto.", en = "Selling lot because I need space for the next project."},
}

-- Match slotType+partName against specific description keys.
-- Returns the most specific match, or nil if no match found.
-- Checks partName first (more specific), then slotType patterns.
local descriptionMatchOrder = {
  -- Specific part types (checked against both partName and slotType)
  { key = "turbo",        patterns = {"turbo"} },
  { key = "intercooler",  patterns = {"intercooler"} },
  { key = "radiator",     patterns = {"radiator"} },
  { key = "exhaust",      patterns = {"exhaust"} },
  { key = "intake",       patterns = {"intake", "airfilter"} },
  { key = "ecu",          patterns = {"ecu"} },
  { key = "transmission", patterns = {"transmission", "gearbox"} },
  { key = "clutch",       patterns = {"clutch"} },
  { key = "differential", patterns = {"differential"} },
  { key = "flywheel",     patterns = {"flywheel"} },
  { key = "driveshaft",   patterns = {"driveshaft", "halfshaft", "axle_"} },
  { key = "oilpan",       patterns = {"oilpan"} },
  { key = "oilcooler",    patterns = {"oilcooler"} },
  { key = "n2o",          patterns = {"n2o", "nos", "nitro"} },
  { key = "fuel",         patterns = {"fuel", "injector"} },
  { key = "engine",       patterns = {"engine"} },
  -- Suspension / brakes
  { key = "coilover",     patterns = {"coilover"} },
  { key = "strut",        patterns = {"strut"} },
  { key = "swaybar",      patterns = {"swaybar", "stabilizer"} },
  { key = "brake",        patterns = {"brake", "brakepad"} },
  { key = "steering",     patterns = {"steering", "steeringbox"} },
  { key = "suspension",   patterns = {"suspension", "spring", "shock"} },
  -- Body
  { key = "bumper",       patterns = {"bumper"} },
  { key = "hood",         patterns = {"hood"} },
  { key = "trunk",        patterns = {"trunk", "tailgate"} },
  { key = "door",         patterns = {"door"} },
  { key = "fender",       patterns = {"fender", "fenderflare"} },
  { key = "mirror",       patterns = {"mirror"} },
  { key = "spoiler",      patterns = {"spoiler", "wing"} },
  { key = "sideskirt",    patterns = {"sideskirt", "skirt"} },
  { key = "grille",       patterns = {"grille"} },
  { key = "windshield",   patterns = {"windshield"} },
  { key = "glass",        patterns = {"glass"} },
  { key = "headlight",    patterns = {"headlight", "signal_"} },
  { key = "taillight",    patterns = {"taillight", "reverselight"} },
  { key = "seat",         patterns = {"seat"} },
  { key = "rollcage",     patterns = {"rollcage", "rollbar"} },
  -- Electrical
  { key = "battery",      patterns = {"battery"} },
  { key = "alternator",   patterns = {"alternator"} },
  { key = "gps",          patterns = {"gps"} },
}

-- Pick a random description for a listing based on slotType AND partName
local function pickDescription(slotType, partName)
  local sLower = slotType and string.lower(slotType) or ""
  local pLower = partName and string.lower(partName) or ""
  local combined = sLower .. " " .. pLower

  -- Try to find a specific match
  for _, entry in ipairs(descriptionMatchOrder) do
    for _, pattern in ipairs(entry.patterns) do
      if combined:find(pattern, 1, true) then
        local pool = partSpecificDescriptions[entry.key]
        if pool and #pool > 0 then
          -- 70% specific, 30% generic
          if math.random() < 0.7 then
            return pool[math.random(#pool)]
          else
            return genericDescriptions[math.random(#genericDescriptions)]
          end
        end
      end
    end
  end

  -- No specific match: use generic
  return genericDescriptions[math.random(#genericDescriptions)]
end

-- Pick a random description for a bundle
local function pickBundleDescription()
  return bundleDescriptions[math.random(#bundleDescriptions)]
end

-- ============================================================================
-- LISTING GENERATION
-- ============================================================================

local function generateListing()
  local part = pickPart("legal")
  if not part then
    return nil
  end
  local location = pickLocation()
  local condition = buildCondition(false)

  -- Price based on km: more km = lower price (up to 40% discount)
  -- odometer is in meters; 200,000 km = 200,000,000 meters
  local kmFactor = 1 - (condition.odometer / 200000000) * 0.4
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
    description = pickDescription(part.slotType, part.name),
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

-- Bundle configs for "despiece" (random source configurations)
local bundleConfigs = {
  {es = "ETK-I 2400ti Sport", en = "ETK-I 2400ti Sport"},
  {es = "ETK-I 2400 Turbo", en = "ETK-I 2400 Turbo"},
  {es = "ETK-I 2000 Base", en = "ETK-I 2000 Base"},
  {es = "ETK-I 2400ti Rally", en = "ETK-I 2400ti Rally"},
  {es = "ETK-I 1800 Economico", en = "ETK-I 1800 Economy"},
  {es = "ETK-I 2400ti GT", en = "ETK-I 2400ti GT"},
}

local function generateBundle()
  local cache = buildPartsCache(modelKey)
  if not cache or not cache.legal or #cache.legal < 5 then return nil end

  local bundleSize = math.random(4, 5)
  local parts = {}
  local usedIndices = {}

  for i = 1, bundleSize do
    local idx
    local attempts = 0
    repeat
      idx = math.random(#cache.legal)
      attempts = attempts + 1
    until not usedIndices[idx] or attempts > 50
    if attempts > 50 then break end
    usedIndices[idx] = true
    table.insert(parts, cache.legal[idx])
  end

  if #parts < 3 then return nil end -- Need at least 3 parts for a bundle

  -- Shared condition for all parts in the lot
  local sharedCondition = buildCondition(false)

  -- Total value + discount (30-50% of real value)
  local totalValue = 0
  for _, p in ipairs(parts) do totalValue = totalValue + p.value end
  local discount = 0.3 + math.random() * 0.2
  local bundlePrice = math.max(100, math.floor(totalValue * discount))

  -- Source configuration (cosmetic/informative)
  local sourceConfig = bundleConfigs[math.random(#bundleConfigs)]

  local bundle = {
    id = state.nextListingId,
    isBundle = true,
    bundleParts = parts,          -- HIDDEN from player until pickup
    bundleSize = #parts,
    sourceConfig = sourceConfig,  -- Which config the parts came from
    sharedCondition = sharedCondition,
    partName = "bundle_etki_" .. state.nextListingId,
    partNiceName = "Despiece ETK-I (" .. #parts .. " piezas)",
    vehicleModel = modelKey,
    slotType = "bundle",
    baseValue = totalValue,
    price = bundlePrice,
    condition = sharedCondition,
    location = pickLocation(),
    createdAt = os.time(),
    expiresAt = os.time() + math.random(3600, 10800),  -- 1-3h
    isIllegal = false,
    description = pickBundleDescription(),
  }

  state.nextListingId = state.nextListingId + 1
  log("I", "mysummer", string.format("generateBundle: %d parts, total value %d, price %d (%.0f%% discount)",
    #parts, totalValue, bundlePrice, (1 - discount) * 100))
  return bundle
end

local function ensureMarketStock()
  while #state.listings < targetListings do
    -- 25% chance to generate a bundle instead of a regular listing
    if math.random() < 0.25 then
      local bundle = generateBundle()
      if bundle then
        table.insert(state.listings, bundle)
        goto continue
      end
    end
    local listing = generateListing()
    if not listing then
      log("W", "mysummer", "ensureMarketStock: generateListing returned nil")
      break
    end
    table.insert(state.listings, listing)
    ::continue::
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
  if not partData then
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

  -- Add to base game partInventory
  if not career_modules_partInventory then
    log("E", "mysummer", "addPartToInventory: partInventory not available")
    return nil
  end

  local slotType = partData.slot or partData.slotType or partData.containingSlot or ""
  local entry = {
    name = partData.name,
    vehicleModel = partData.vehicleModel or modelKey or "etki",
    partCondition = partData.partCondition or { integrityValue = 1, odometer = 0, visualValue = 1 },
    containingSlot = slotType,
    partPath = slotType .. (partData.name or ""),
    location = 0,
    tags = partData.tags or {},
    mainPart = false,
    value = partData.value or partData.baseValue or 100,
    description = partData.description or { description = partData.name },
  }

  career_modules_partInventory.addPartToInventory(entry)

  -- Find the ID that was just assigned (addPartToInventory doesn't return it)
  local newId = nil
  local inv = career_modules_partInventory.getInventory()
  for id, p in pairs(inv) do
    if p.name == entry.name and p.containingSlot == entry.containingSlot and p.location == 0 then
      newId = id
    end
  end

  log("I", "mysummer", "Added part '" .. (partData.name or "unknown") .. "' to partInventory (id=" .. tostring(newId) .. ", slot=" .. slotType .. ")")
  return newId
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
  -- For parts in storage (location=0), directly remove from inventory table
  -- Base game removePart() is for uninstalling from vehicles, not for deleting stored parts
  local inv = career_modules_partInventory.getInventory()
  if inv and inv[partId] then
    inv[partId] = nil
    return true
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

-- Helper: finish pickup after cargo is loaded (shared by normal and bundle pickups)
local function finishPickupAfterLoad(pickup, price)
  state.activePickup = nil
  state.completingPickup = false
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
end

-- Complete a bundle pickup: load each part sequentially into cargo, reveal names
local function completeBundlePickup(pickup, cargoModule, price)
  local bundleParts = pickup.bundleParts or {}
  local sharedCondition = pickup.sharedCondition or buildCondition(false)
  local loadedParts = {}
  local failedCount = 0

  local function loadNextBundlePart(index)
    if index > #bundleParts then
      -- All parts processed - show reveal message
      if #loadedParts > 0 then
        local partNames = {}
        for _, p in ipairs(loadedParts) do
          table.insert(partNames, p.niceName or p.name)
        end
        local revealMsg = "Bundle opened! You got: " .. table.concat(partNames, ", ")
        ui_message(revealMsg, 8, "Parts Market", "success")
        log("I", "mysummer", "Bundle revealed: " .. #loadedParts .. " parts loaded, " .. failedCount .. " failed")

        -- Send bundle reveal data to UI
        guihooks.trigger("mysummerBundleRevealed", {
          parts = loadedParts,
          sourceConfig = pickup.sourceConfig,
          totalLoaded = #loadedParts,
          totalFailed = failedCount,
        })
      end
      finishPickupAfterLoad(pickup, price)
      return
    end

    local bundlePart = bundleParts[index]
    local partData = {
      partName = bundlePart.name,
      partNiceName = bundlePart.niceName,
      vehicleModel = pickup.vehicleModel or modelKey,
      slotType = bundlePart.slotType,
      condition = deepcopy(sharedCondition),
      baseValue = bundlePart.value,
      isIllegal = false,
    }

    cargoModule.loadPartIntoCargo(partData, function(success, cargoIdOrError, container)
      if success then
        table.insert(loadedParts, {
          name = bundlePart.name,
          niceName = bundlePart.niceName,
          slotType = bundlePart.slotType,
          value = bundlePart.value,
        })
        -- Track in state.carryingParts (SpeedParts pattern - survives save/load)
        table.insert(state.carryingParts, {
          name = bundlePart.name,
          niceName = bundlePart.niceName,
          slotType = bundlePart.slotType,
          price = bundlePart.value,
          vehicleModel = pickup.vehicleModel or modelKey,
          condition = deepcopy(sharedCondition),
          cargoId = cargoIdOrError,
        })
      else
        failedCount = failedCount + 1
        log("W", "mysummer", "Failed to load bundle part: " .. (bundlePart.niceName or bundlePart.name) .. " - " .. tostring(cargoIdOrError))
      end
      loadNextBundlePart(index + 1)
    end)
  end

  loadNextBundlePart(1)
end

local function completePickup()
  if not state.activePickup then
    return
  end
  if state.completingPickup then
    return -- Prevent re-entry during async cargo operations
  end

  state.completingPickup = true -- Set flag immediately to prevent duplicate calls
  local pickup = state.activePickup
  log("I", "mysummer", "completePickup: starting for " .. (pickup.partNiceName or pickup.partName or "unknown"))

  -- Check cargo module availability
  local cargoModule = career_modules_mysummerCargo
  if not cargoModule then
    -- Fallback: add part directly to inventory when cargo system is unavailable
    log("W", "mysummer", "completePickup: cargo module unavailable, adding part directly to inventory")

    local price = tonumber(pickup.price) or 0
    if price > 0 then
      local priceData = { money = { amount = price, canBeNegative = false } }
      if not career_modules_payment.canPay(priceData) then
        state.completingPickup = false
        ui_message("You cannot afford this pickup yet.", 4, "Parts Market", "warning")
        return
      end
      career_modules_payment.pay(priceData, { label = "Parts pickup", tags = { "buying", "parts" } })
    end

    if pickup.isBundle and pickup.bundleParts then
      for _, bp in ipairs(pickup.bundleParts) do
        local partData = {
          name = bp.name,
          vehicleModel = pickup.vehicleModel or modelKey,
          partCondition = pickup.sharedCondition and deepcopy(pickup.sharedCondition) or { integrityValue = 1, odometer = 0, visualValue = 1 },
          slot = bp.slotType,
          location = 0,
          value = bp.value,
          description = { description = bp.niceName or bp.name },
        }
        addPartToInventory(partData)
      end
      local names = {}
      for _, bp in ipairs(pickup.bundleParts) do table.insert(names, bp.niceName or bp.name) end
      ui_message("Bundle opened! You got: " .. table.concat(names, ", "), 8, "Parts Market", "success")
    else
      local partData = {
        name = pickup.partName,
        vehicleModel = pickup.vehicleModel or modelKey,
        partCondition = pickup.condition and deepcopy(pickup.condition) or { integrityValue = 1, odometer = 0, visualValue = 1 },
        slot = pickup.slotType,
        location = 0,
        value = pickup.baseValue,
        description = { description = pickup.partNiceName or pickup.partName },
      }
      addPartToInventory(partData)
      ui_message("Part picked up: " .. (pickup.partNiceName or pickup.partName), 4, "Parts Market", "success")
    end

    if pickup.isIllegal then
      local heatIncrease = HEAT_CONFIG.pickupHeatIncrease[pickup.heat or "normal"] or 10
      addPlayerHeat(heatIncrease)
      local chaseRoll = math.random()
      if chaseRoll < 0.4 then
        startCriminalChase(pickup.heat or "normal")
      else
        startPolicePursuit(pickup.heat or "hot")
      end
    end

    finishPickupAfterLoad(pickup, price)
    return
  end

  -- For bundles, check space for first part (best effort - may not fit all)
  local checkPartName = pickup.partName
  if pickup.isBundle and pickup.bundleParts and #pickup.bundleParts > 0 then
    checkPartName = pickup.bundleParts[1].name
  end

  cargoModule.checkCargoSpace({ checkPartName }, function(cargoResult)
    if not cargoResult.canLoad then
      state.completingPickup = false -- Reset flag so player can retry
      if cargoResult.availableSlots == 0 then
        ui_message("No cargo container found! Install a cargo box in your vehicle.", 5, "Parts Market", "warning")
      else
        ui_message(string.format("Not enough cargo space! Need %d slots, have %d.", cargoResult.totalSlotsNeeded or 0, cargoResult.availableSlots), 5, "Parts Market", "warning")
      end
      return
    end

    -- Has cargo space, proceed with payment and pickup
    local price = tonumber(pickup.price) or 0
    if price > 0 then
      local priceData = { money = { amount = price, canBeNegative = false } }
      if not career_modules_payment.canPay(priceData) then
        state.completingPickup = false -- Reset flag so player can retry
        ui_message("You cannot afford this pickup yet.", 4, "Parts Market", "warning")
        return
      end
      career_modules_payment.pay(priceData, { label = "Parts pickup", tags = { "buying", "parts" } })
    end

    -- BUNDLE PICKUP: Load each part individually and reveal
    if pickup.isBundle and pickup.bundleParts then
      completeBundlePickup(pickup, cargoModule, price)
      return
    end

    -- NORMAL PICKUP: Load single part into native cargo system
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
        state.completingPickup = false -- Reset flag so player can retry
        -- Refund payment if cargo loading failed
        if price > 0 then
          career_modules_payment.reward({ money = { amount = price } }, { label = "Parts pickup refund" })
        end
        ui_message("Failed to load cargo: " .. tostring(cargoIdOrError), 4, "Parts Market", "warning")
        return
      end

      -- Track in state.carryingParts (SpeedParts pattern - survives save/load)
      table.insert(state.carryingParts, {
        name = pickup.partName,
        niceName = pickup.partNiceName,
        slotType = pickup.slotType,
        price = pickup.baseValue,
        vehicleModel = pickup.vehicleModel,
        condition = deepcopy(pickup.condition),
        cargoId = cargoIdOrError,
        isIllegal = pickup.isIllegal,
        heat = pickup.heat,
      })

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

      finishPickupAfterLoad(pickup, price)
    end)
  end)
end

local function acceptListing(listingId)
  if not isFullyInitialized then
    log("W", "mysummer", "acceptListing called before initialization complete")
    return { success = false, message = "System not ready. Please wait." }
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

      local listingCopy = deepcopy(listing)
      table.remove(state.listings, idx)

      local partName = listingCopy.partNiceName or listingCopy.partName or "Part"
      if state.activePickup then
        -- Queue behind active pickup
        table.insert(state.pendingPickups, listingCopy)
        log("I", "mysummer", "Queued pickup: " .. partName .. " (pending: " .. #state.pendingPickups .. ")")
        ui_message("Purchased! " .. partName .. " queued for pickup (" .. #state.pendingPickups .. " in queue)", 5, "PartsBay", "info")
      else
        -- Set as active pickup
        state.activePickup = listingCopy
        setRouteToPickup(state.activePickup)
        ui_message("Purchased! Go pick up " .. partName .. " - follow the waypoint", 5, "PartsBay", "info")
      end

      saveState()
      sendMarketUpdate()
      return { success = true, message = "Purchased! " .. partName }
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

  -- Start with the first pickup if none active
  if not state.activePickup and #state.pendingPickups > 0 then
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
    -- Move active pickup back to pending queue (at the beginning)
    if not state.pendingPickups then state.pendingPickups = {} end
    table.insert(state.pendingPickups, 1, state.activePickup)
    state.activePickup = nil
    clearRoute()
    saveState()
    sendMarketUpdate()
  end
  return getMarketData()
end

local function setWaypointToActivePickup()
  if state.activePickup then
    setRouteToPickup(state.activePickup)
    return { success = true }
  end
  return { success = false, message = "No active pickup" }
end

local function cancelPendingPickup(index)
  if not state.pendingPickups or not state.pendingPickups[index] then
    return { success = false, message = "Invalid pickup index" }
  end
  table.remove(state.pendingPickups, index)
  saveState()
  sendMarketUpdate()
  return getMarketData()
end

local function activatePendingPickup(index)
  if not state.pendingPickups or not state.pendingPickups[index] then
    return { success = false, message = "Invalid pickup index" }
  end

  -- If there's already an active pickup, move it back to pending
  if state.activePickup then
    table.insert(state.pendingPickups, 1, state.activePickup)
    -- Adjust index since we just inserted at position 1
    index = index + 1
  end

  -- Pull the selected pickup out of pending and make it active
  state.activePickup = table.remove(state.pendingPickups, index)
  setRouteToPickup(state.activePickup)
  ui_message("Navigating to: " .. (state.activePickup.partNiceName or state.activePickup.partName), 4, "PartsBay")
  saveState()
  sendMarketUpdate()
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
  log("D", "mysummer", "onReachedTargetPos called, initialized=" .. tostring(isFullyInitialized) .. ", activePickup=" .. tostring(state.activePickup ~= nil))
  if not isFullyInitialized or not state.activePickup then
    return
  end

  local targetPos = core_groundMarkers.getTargetPos()
  local pickupPos = toVec3(state.activePickup.location and state.activePickup.location.pos)
  log("D", "mysummer", "onReachedTargetPos: targetPos=" .. tostring(targetPos) .. ", pickupPos=" .. tostring(pickupPos))
  if targetPos and pickupPos then
    local dist = targetPos:distance(pickupPos)
    log("D", "mysummer", "onReachedTargetPos: distance=" .. tostring(dist))
    if dist < 5 then
      completePickup()
    end
  else
    -- Fallback: if no target pos but we have an active pickup, check player distance directly
    local playerPos = getPlayerPos()
    if playerPos and pickupPos then
      local playerDist = playerPos:distance(pickupPos)
      log("D", "mysummer", "onReachedTargetPos fallback: playerDist=" .. tostring(playerDist))
      if playerDist < 15 then
        completePickup()
      end
    end
  end
end

-- Cargo transfer to inventory functions
-- Check if player is near any purchased garage (matches SpeedParts pattern)
local function isPlayerNearGarage()
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then return false, nil end

  local playerPos = playerVeh:getPosition()
  if not playerPos then return false, nil end

  local garageManager = career_modules_garageManager
  if not garageManager or not garageManager.getPurchasedGarages then
    return false, nil
  end

  local purchasedGarageIds = garageManager.getPurchasedGarages()
  if not purchasedGarageIds then return false, nil end

  -- Convert to lookup (getPurchasedGarages may return array or map)
  local purchasedLookup = {}
  if type(purchasedGarageIds) == "table" then
    if purchasedGarageIds[1] then
      for _, gid in ipairs(purchasedGarageIds) do
        purchasedLookup[gid] = true
      end
    else
      purchasedLookup = purchasedGarageIds
    end
  end

  -- Check each purchased garage using accurate door position
  if freeroam_facilities and freeroam_facilities.getFacility then
    for garageId, _ in pairs(purchasedLookup) do
      local garage = freeroam_facilities.getFacility("garage", garageId)
      if garage then
        local garagePos = nil
        if freeroam_facilities.getAverageDoorPositionForFacility then
          garagePos = freeroam_facilities.getAverageDoorPositionForFacility(garage)
        end
        if not garagePos and garage.pos then
          garagePos = toVec3(garage.pos)
        end
        if garagePos then
          local distance = (playerPos - garagePos):length()
          if distance <= 15 then
            return true, garageId
          end
        end
      end
    end
  end

  return false, nil
end

-- Transfer a cargo part from vehicle cargo to part inventory
local function transferCargoPartToInventory(cargoPart)
  local partData = {
    name = cargoPart.partName,
    vehicleModel = cargoPart.vehicleModel or "etki",
    partCondition = cargoPart.condition and deepcopy(cargoPart.condition) or { integrityValue = 1, odometer = 0, visualValue = 1 },
    slot = cargoPart.slotType,
    location = 0,
    value = cargoPart.baseValue,
    description = { description = cargoPart.partNiceName or cargoPart.partName },
  }

  local partId = addPartToInventory(partData)
  return partId
end

-- Deliver parts at garage (only from OUR state.carryingParts)
local function deliverPartsAtGarage()
  local cargoModule = career_modules_mysummerCargo

  -- Only deliver from OUR state.carryingParts (not native cargo, which may belong to SpeedParts)
  if #state.carryingParts == 0 then
    log("W", "mysummer", "deliverPartsAtGarage: no parts to deliver")
    return { success = false, message = "No parts to deliver" }
  end

  -- Early exit if partInventory not available (e.g. during quickTravel/recovery)
  if not career_modules_partInventory then
    log("W", "mysummer", "deliverPartsAtGarage: partInventory not available yet, will retry")
    return { success = false, message = "Inventory system not ready" }
  end

  local partsToDeliver = state.carryingParts

  local transferred = 0

  for _, partInfo in ipairs(partsToDeliver) do
    -- Handle both state.carryingParts format and native cargo format
    local partName = partInfo.name or partInfo.partName
    local partNiceName = partInfo.niceName or partInfo.partNiceName or partName
    local partSlot = partInfo.slotType or partInfo.slot
    local partValue = partInfo.price or partInfo.baseValue or 0
    local partCondition = partInfo.condition or { integrityValue = 1, odometer = 0, visualValue = 1 }
    local cargoId = partInfo.cargoId
    local isIllegal = partInfo.isIllegal

    local partData = {
      name = partName,
      vehicleModel = partInfo.vehicleModel or modelKey or "etki",
      partCondition = deepcopy(partCondition),
      slot = partSlot,
      location = 0,
      value = partValue,
      description = { description = partNiceName },
    }

    local newPartId = addPartToInventory(partData)
    if newPartId then
      transferred = transferred + 1
      log("I", "mysummer", string.format("Delivered part '%s' to inventory (id=%s)", partName, tostring(newPartId)))

      -- Unload from native cargo if we have a cargoId
      if cargoModule and cargoId then
        cargoModule.unloadCargoItem(cargoId)
      end

      -- Track illegal part for pursuit system
      if isIllegal and state.pendingIllegalCargoId and cargoId == state.pendingIllegalCargoId then
        state.pendingIllegalPartId = newPartId
        state.pendingIllegalCargoId = nil
      end
    else
      log("W", "mysummer", "Failed to add part to inventory: " .. partName)
    end
  end

  -- Clear carrying state
  state.carryingParts = {}

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setFocus(nil)
  end

  if transferred > 0 then
    ui_message("Delivered " .. transferred .. " part(s) to inventory!", 5, "PartsBay", "success")
  end

  saveState()
  return { success = true, transferred = transferred }
end

-- Get loaded cargo info (only OUR state.carryingParts)
getLoadedCargoInfo = function()
  local result = {
    count = #state.carryingParts,
    totalSlots = 0,
    totalWeight = 0,
    items = {},
    nearGarage = false,
  }

  for _, part in ipairs(state.carryingParts) do
    table.insert(result.items, {
      partName = part.niceName or part.partNiceName or part.name or part.partName,
      vehicleModel = part.vehicleModel or modelKey,
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

-- Garage auto-unload state (matches SpeedParts delivery pattern)
local wasNearGarage = false
local deliveryRetryTime = nil
local cargoReminderTimer = 0

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

  -- Auto-deliver at garage (only from OUR state.carryingParts)
  local hasCargoToDeliver = #state.carryingParts > 0

  if hasCargoToDeliver then
    local nearGarage, garageId = isPlayerNearGarage()

    -- Retry delivery while at garage with cargo (handles quickTravel/recovery where partInventory may be temporarily nil)
    if nearGarage then
      if not deliveryRetryTime then deliveryRetryTime = 0 end
      deliveryRetryTime = deliveryRetryTime + dt
      if not wasNearGarage or deliveryRetryTime >= 2 then
        deliveryRetryTime = 0
        log("I", "mysummer", "Attempting delivery of " .. #state.carryingParts .. " PartsBay parts" .. (wasNearGarage and " (retry)" or ""))
        local result = deliverPartsAtGarage()
        if result and result.transferred and result.transferred > 0 then
          sendMarketUpdate()
        end
      end
    else
      deliveryRetryTime = nil
    end

    wasNearGarage = nearGarage

    -- Periodic reminder while carrying parts
    local totalParts = #state.carryingParts
    cargoReminderTimer = cargoReminderTimer + dt
    if cargoReminderTimer >= 30 then
      cargoReminderTimer = 0
      ui_message("Carrying " .. totalParts .. " part(s) - deliver to your garage", 5, "PartsBay")
    end
  else
    wasNearGarage = false
    cargoReminderTimer = 0
  end

  if not state.activePickup then
    return
  end

  -- Proximity check for active pickup completion
  if not state.completingPickup then
    local playerPos = getPlayerPos()
    local pickupPos = toVec3(state.activePickup.location and state.activePickup.location.pos)
    if playerPos and pickupPos then
      local dist = playerPos:distance(pickupPos)
      if dist < 5 then
        log("I", "mysummer", "Player near pickup location (dist=" .. string.format("%.1f", dist) .. "m), completing pickup")
        completePickup()
      end
    end
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

  -- Restore waypoint for active pickup if one exists from saved state
  if state.activePickup then
    log("I", "mysummer", "Restoring waypoint for active pickup: " .. (state.activePickup.partNiceName or state.activePickup.partName or "unknown"))
    setRouteToPickup(state.activePickup)
  end

  sendMarketUpdate()
  log("I", "mysummer", "MySummer Career Extension initialized successfully")
  return true
end

local function onCareerActive()
  -- This is called when career becomes active - perfect time to initialize
  initializeMySummer()
end

local function onExtensionLoaded()
  -- Force-load base game partInventory module
  -- RLS career override doesn't include it in its module discovery, so it never gets loaded.
  -- RLS modules (enforcement, valueCalculator, insurance) also reference it without declaring dependency.
  if not career_modules_partInventory then
    log("I", "mysummer", "career_modules_partInventory not loaded, forcing load via extensions.load()")
    extensions.load("career_modules_partInventory")
  end

  if career_modules_partInventory then
    log("I", "mysummer", "career_modules_partInventory loaded successfully — API: getInventory=" .. tostring(career_modules_partInventory.getInventory ~= nil) .. ", addPartToInventory=" .. tostring(career_modules_partInventory.addPartToInventory ~= nil) .. ", removePart=" .. tostring(career_modules_partInventory.removePart ~= nil) .. ", sellParts=" .. tostring(career_modules_partInventory.sellParts ~= nil))
  else
    log("E", "mysummer", "FAILED to load career_modules_partInventory — base game module not found")
  end

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
        local slotType = part.containingSlot or part.slot or ""
        local category = getCategoryForSlot(slotType)
        table.insert(categories[category].inventoryParts, {
          id = partId,
          name = part.name,
          niceName = part.description and part.description.description or part.name,
          slotType = slotType,
          slotNiceName = part.slotNiceName or slotType,
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
  if not career_modules_partInventory then
    return { success = false, error = "Part inventory not available" }
  end

  local allParts = career_modules_partInventory.getInventory() or {}
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
M.setWaypointToActivePickup = setWaypointToActivePickup
M.cancelPendingPickup = cancelPendingPickup
M.activatePendingPickup = activatePendingPickup
M.openMenuFromComputer = openMenuFromComputer
M.closeMenu = closeMenu
M.closeAllMenus = closeAllMenus
M.addVendorParts = addVendorParts

-- Cargo functions
M.unloadAllCargo = deliverPartsAtGarage  -- Legacy alias
M.deliverPartsAtGarage = deliverPartsAtGarage
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
