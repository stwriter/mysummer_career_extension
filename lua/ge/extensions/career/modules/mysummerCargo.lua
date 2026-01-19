-- MySummer Cargo System
-- Handles cargo containers for transporting car parts
-- Integrates with BeamNG's native parcelManager system

local M = {}
M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_delivery_parcelManager",
  "career_modules_delivery_general",
}

-- Part weight/slots definitions (in kg and cargo slots)
-- Slots are scaled so largest item (engine) = ~80 slots
-- Weight remains realistic in kg
local partWeights = {
  -- Engine & Drivetrain (heavy) - realistic weights in kg
  engine = { weight = 250, slots = 80 },      -- Full engine block ~250kg
  turbo = { weight = 35, slots = 12 },        -- Turbocharger
  supercharger = { weight = 45, slots = 14 }, -- Supercharger
  intake = { weight = 12, slots = 6 },        -- Intake manifold
  exhaust = { weight = 40, slots = 16 },      -- Full exhaust system
  radiator = { weight = 18, slots = 10 },     -- Radiator with coolant
  oilcooler = { weight = 12, slots = 6 },     -- Oil cooler
  intercooler = { weight = 15, slots = 8 },   -- Intercooler
  transmission = { weight = 90, slots = 40 }, -- Gearbox ~90kg
  clutch = { weight = 18, slots = 6 },        -- Clutch assembly
  flywheel = { weight = 15, slots = 5 },      -- Flywheel
  differential = { weight = 55, slots = 20 }, -- Differential
  driveshaft = { weight = 25, slots = 10 },   -- Driveshaft
  halfshaft = { weight = 15, slots = 6 },     -- CV axle/halfshaft
  fueltank = { weight = 25, slots = 12 },     -- Fuel tank (empty)

  -- Suspension & Brakes (medium)
  suspension = { weight = 35, slots = 12 },   -- Suspension arm
  strut = { weight = 15, slots = 6 },         -- Strut/shock
  coilover = { weight = 18, slots = 8 },      -- Coilover
  spring = { weight = 8, slots = 3 },         -- Spring
  swaybar = { weight = 12, slots = 4 },       -- Sway bar
  steering = { weight = 20, slots = 8 },      -- Steering rack
  brake = { weight = 15, slots = 6 },         -- Brake caliper+disc
  hub = { weight = 12, slots = 4 },           -- Wheel hub
  axle = { weight = 45, slots = 16 },         -- Rear axle

  -- Body (large, bulky)
  hood = { weight = 25, slots = 20 },         -- Hood/bonnet
  trunk = { weight = 22, slots = 16 },        -- Trunk lid
  door = { weight = 40, slots = 20 },         -- Door with glass
  fender = { weight = 12, slots = 12 },       -- Fender
  bumper = { weight = 20, slots = 14 },       -- Bumper
  grille = { weight = 5, slots = 4 },         -- Grille
  mirror = { weight = 3, slots = 2 },         -- Mirror
  spoiler = { weight = 8, slots = 8 },        -- Spoiler
  splitter = { weight = 6, slots = 6 },       -- Splitter
  diffuser = { weight = 6, slots = 6 },       -- Diffuser
  sideskirt = { weight = 6, slots = 6 },      -- Side skirt
  quarterpanel = { weight = 18, slots = 14 }, -- Quarter panel
  roofpanel = { weight = 20, slots = 16 },    -- Roof panel

  -- Glass (fragile, special handling)
  windshield = { weight = 22, slots = 16 },   -- Windshield
  glass = { weight = 14, slots = 12 },        -- Side/rear glass
  headlight = { weight = 6, slots = 4 },      -- Headlight assembly
  taillight = { weight = 4, slots = 3 },      -- Taillight
  foglight = { weight = 3, slots = 2 },       -- Foglight

  -- Interior (medium)
  seat = { weight = 28, slots = 16 },         -- Car seat ~14kg each, pair
  steer = { weight = 6, slots = 3 },          -- Steering wheel
  dashboard = { weight = 20, slots = 14 },    -- Dashboard
  console = { weight = 14, slots = 8 },       -- Center console
  rollcage = { weight = 55, slots = 30 },     -- Roll cage
  harness = { weight = 5, slots = 3 },        -- Harness
  gauges = { weight = 3, slots = 2 },         -- Gauge cluster
  interior = { weight = 40, slots = 20 },     -- Interior trim

  -- Electrical (small)
  ecu = { weight = 3, slots = 2 },            -- ECU
  battery = { weight = 22, slots = 6 },       -- Car battery ~20kg
  alternator = { weight = 10, slots = 4 },    -- Alternator
  starter = { weight = 12, slots = 5 },       -- Starter motor
  wiring = { weight = 8, slots = 3 },         -- Wiring harness
  sensor = { weight = 1, slots = 1 },         -- Sensors

  -- Small parts (default)
  default = { weight = 8, slots = 3 },
}

-- Local state for tracking our cargo IDs
local nextCargoId = 100000  -- Start high to avoid conflicts with delivery system
local mysummerCargoIds = {}  -- Track which cargo IDs are ours

-- Get weight and slots for a part based on its name
local function getPartCargoInfo(partName)
  if not partName then return partWeights.default end

  local lowerName = string.lower(partName)

  -- Check each pattern
  for pattern, info in pairs(partWeights) do
    if pattern ~= "default" and string.find(lowerName, pattern) then
      return info
    end
  end

  return partWeights.default
end

-- Get nearby vehicle cargo containers
local function getNearbyCargoContainers(callback)
  if not career_career or not career_career.isActive() then
    callback({})
    return
  end

  local playerVeh = getPlayerVehicle(0)
  if not playerVeh then
    callback({})
    return
  end

  local playerPos = playerVeh:getPosition()
  local containers = {}
  local pendingRequests = 0
  local totalVehicles = 0

  -- Count vehicles in range first
  for vehId, veh in activeVehiclesIterator() do
    local dist = (playerPos - veh:getPosition()):length()
    if dist < 25 then
      totalVehicles = totalVehicles + 1
    end
  end

  if totalVehicles == 0 then
    callback({})
    return
  end

  -- Request cargo data from each nearby vehicle
  for vehId, veh in activeVehiclesIterator() do
    local dist = (playerPos - veh:getPosition()):length()
    if dist < 25 then
      pendingRequests = pendingRequests + 1

      core_vehicleBridge.requestValue(veh, function(cargoData)
        if cargoData and cargoData[1] then
          for _, container in ipairs(cargoData[1]) do
            -- Check if container accepts parcels (our parts type)
            local acceptsParcels = false
            if container.cargoTypes then
              for _, cType in ipairs(container.cargoTypes) do
                if cType == "parcel" then
                  acceptsParcels = true
                  break
                end
              end
            end

            if acceptsParcels and container.capacity and container.capacity > 0 then
              table.insert(containers, {
                vehId = veh:getID(),
                vehName = veh:getJBeamFilename(),
                containerId = container.id,
                name = container.name or "Cargo",
                capacity = container.capacity,
                usedSlots = container.usedSlots or 0,
                freeSlots = container.capacity - (container.usedSlots or 0),
                cargoTypes = container.cargoTypes,
              })
            end
          end
        end

        pendingRequests = pendingRequests - 1
        if pendingRequests == 0 then
          callback(containers)
        end
      end, "getCargoContainers")
    end
  end
end

-- Check if there's enough cargo space for a list of parts
local function checkCargoSpace(parts, callback)
  getNearbyCargoContainers(function(containers)
    local totalAvailable = 0
    for _, con in ipairs(containers) do
      totalAvailable = totalAvailable + con.freeSlots
    end

    local totalNeeded = 0
    for _, part in ipairs(parts) do
      local partName = type(part) == "table" and part.partName or part
      local info = getPartCargoInfo(partName)
      totalNeeded = totalNeeded + info.slots
    end

    callback({
      canLoad = totalAvailable >= totalNeeded,
      totalSlotsNeeded = totalNeeded,
      availableSlots = totalAvailable,
      containers = containers,
    })
  end)
end

-- Load a part into vehicle cargo using native parcelManager
-- This adds the part to the BeamNG cargo system (affects weight, shows in UI)
-- Optional destinationData: { type = "facilityParkingspot", facId = "garage_id", psPath = "path" }
--                       or: { pos = {x,y,z} } for a position-based destination
local function loadPartIntoCargo(partData, callback, destinationData)
  getNearbyCargoContainers(function(containers)
    if #containers == 0 then
      callback(false, "No cargo containers available")
      return
    end

    local cargoInfo = getPartCargoInfo(partData.partName)

    -- Find a container with enough space
    local targetContainer = nil
    for _, con in ipairs(containers) do
      if con.freeSlots >= cargoInfo.slots then
        targetContainer = con
        break
      end
    end

    if not targetContainer then
      callback(false, "Not enough cargo space")
      return
    end

    -- Create cargo item for parcelManager
    nextCargoId = nextCargoId + 1
    local cargoId = nextCargoId

    local cargoItem = {
      id = cargoId,
      templateId = -1,  -- Custom cargo, no template
      groupId = cargoId,  -- Each part is its own group
      name = partData.partNiceName or partData.partName,
      type = "parcel",
      slots = cargoInfo.slots,
      weight = cargoInfo.weight,
      offerExpiresAt = math.huge,  -- Never expires
      data = {
        isMysummerPart = true,
        partName = partData.partName,
        partNiceName = partData.partNiceName,
        vehicleModel = partData.vehicleModel,
        slotType = partData.slotType,
        condition = partData.condition,
        baseValue = partData.baseValue,
        isIllegal = partData.isIllegal,
        heat = partData.heat,
      },
      rewards = { money = 0 },
      modifiers = {},
      location = {
        type = "vehicle",
        vehId = targetContainer.vehId,
        containerId = targetContainer.containerId,
      },
      origin = {
        type = "vehicle",
        vehId = targetContainer.vehId,
        containerId = targetContainer.containerId,
      },
      -- Destination for delivery system - use provided data or default to custom type
      destination = destinationData or {
        type = "mysummerInventory",  -- Custom type, not recognized by delivery system
        description = "Player inventory at garage",
      },
      generatorLabel = "mysummerParts",
      generatedAtTimestamp = os.time(),
      automaticDropOff = false,
    }

    -- Add to parcelManager
    if career_modules_delivery_parcelManager and career_modules_delivery_parcelManager.addCargo then
      career_modules_delivery_parcelManager.addCargo(cargoItem)
      mysummerCargoIds[cargoId] = true

      -- Request weight update
      if career_modules_delivery_general and career_modules_delivery_general.requestUpdateContainerWeights then
        career_modules_delivery_general.requestUpdateContainerWeights()
      end

      log("I", "mysummerCargo", string.format("Loaded part '%s' into cargo (id=%d, veh=%d, container=%d, slots=%d, weight=%dkg)",
        partData.partName, cargoId, targetContainer.vehId, targetContainer.containerId, cargoInfo.slots, cargoInfo.weight))

      callback(true, cargoId, targetContainer)
    else
      log("W", "mysummerCargo", "parcelManager not available, cargo not loaded")
      callback(false, "Delivery system not available")
    end
  end)
end

-- Get all MySummer parts currently in cargo
local function getMysummerCargoInVehicles()
  local parts = {}

  if not career_modules_delivery_parcelManager then
    return parts
  end

  local allCargo = career_modules_delivery_parcelManager.getAllCargoInVehicles and
                   career_modules_delivery_parcelManager.getAllCargoInVehicles() or {}

  for _, cargo in ipairs(allCargo) do
    if cargo.data and cargo.data.isMysummerPart then
      table.insert(parts, {
        cargoId = cargo.id,
        partName = cargo.data.partName,
        partNiceName = cargo.data.partNiceName or cargo.name,
        vehicleModel = cargo.data.vehicleModel,
        slotType = cargo.data.slotType,
        condition = cargo.data.condition,
        baseValue = cargo.data.baseValue,
        isIllegal = cargo.data.isIllegal,
        heat = cargo.data.heat,
        slots = cargo.slots,
        weight = cargo.weight,
        location = cargo.location,
      })
    end
  end

  return parts
end

-- Unload a specific cargo item (remove from vehicle cargo)
local function unloadCargoItem(cargoId)
  if not career_modules_delivery_parcelManager then
    return false
  end

  if career_modules_delivery_parcelManager.changeCargoLocation then
    career_modules_delivery_parcelManager.changeCargoLocation(cargoId, {type = "deleted"})
    mysummerCargoIds[cargoId] = nil

    -- Request weight update
    if career_modules_delivery_general and career_modules_delivery_general.requestUpdateContainerWeights then
      career_modules_delivery_general.requestUpdateContainerWeights()
    end

    log("I", "mysummerCargo", "Unloaded cargo item " .. cargoId)
    return true
  end

  return false
end

-- Unload all MySummer parts from cargo
local function unloadAllMysummerCargo()
  local parts = getMysummerCargoInVehicles()
  local unloaded = {}

  for _, part in ipairs(parts) do
    if unloadCargoItem(part.cargoId) then
      table.insert(unloaded, part)
    end
  end

  return unloaded
end

-- Get cargo info for UI display
local function getCargoInfoForUi(callback)
  getNearbyCargoContainers(function(containers)
    local mysummerParts = getMysummerCargoInVehicles()

    local result = {
      hasContainers = #containers > 0,
      containers = {},
      totalCapacity = 0,
      totalUsed = 0,
      totalFree = 0,
      mysummerParts = mysummerParts,
      mysummerPartsCount = #mysummerParts,
      mysummerSlotsUsed = 0,
      mysummerWeightTotal = 0,
    }

    for _, con in ipairs(containers) do
      table.insert(result.containers, {
        vehId = con.vehId,
        vehName = con.vehName,
        containerId = con.containerId,
        name = con.name,
        capacity = con.capacity,
        used = con.usedSlots,
        free = con.freeSlots,
      })
      result.totalCapacity = result.totalCapacity + con.capacity
      result.totalUsed = result.totalUsed + con.usedSlots
      result.totalFree = result.totalFree + con.freeSlots
    end

    for _, part in ipairs(mysummerParts) do
      result.mysummerSlotsUsed = result.mysummerSlotsUsed + (part.slots or 0)
      result.mysummerWeightTotal = result.mysummerWeightTotal + (part.weight or 0)
    end

    callback(result)
  end)
end

-- Check if a single part can be loaded
local function canLoadPart(partName, callback)
  checkCargoSpace({ partName }, function(result)
    callback(result.canLoad, result)
  end)
end

-- Get total cargo capacity of nearby vehicles
local function getTotalCargoCapacity(callback)
  getNearbyCargoContainers(function(containers)
    local total = 0
    local used = 0
    for _, con in ipairs(containers) do
      total = total + con.capacity
      used = used + con.usedSlots
    end
    callback({
      total = total,
      used = used,
      free = total - used,
      containerCount = #containers,
    })
  end)
end

-- Public API
M.getPartCargoInfo = getPartCargoInfo
M.getNearbyCargoContainers = getNearbyCargoContainers
M.checkCargoSpace = checkCargoSpace
M.canLoadPart = canLoadPart
M.getTotalCargoCapacity = getTotalCargoCapacity
M.getCargoInfoForUi = getCargoInfoForUi
M.loadPartIntoCargo = loadPartIntoCargo
M.getMysummerCargoInVehicles = getMysummerCargoInVehicles
M.unloadCargoItem = unloadCargoItem
M.unloadAllMysummerCargo = unloadAllMysummerCargo

-- Module callbacks
local function onExtensionLoaded()
  log("I", "mysummerCargo", "MySummer Cargo module loaded")
end

M.onExtensionLoaded = onExtensionLoaded

return M
