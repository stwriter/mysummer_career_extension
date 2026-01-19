-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.moduleName = "career_modules_mysummerCore"

-- NO CAREER DEPENDENCIES - This is a utility module
M.dependencies = {}

local logTag = "mysummerCore"

-- Color definitions for paint generation
local colorDefinitions = {
  red = {
    name = "Red",
    baseColor = {x = 0.8, y = 0.1, z = 0.1, w = 1.0},
  },
  blue = {
    name = "Blue",
    baseColor = {x = 0.1, y = 0.2, z = 0.8, w = 1.0},
  },
  green = {
    name = "Green",
    baseColor = {x = 0.1, y = 0.6, z = 0.2, w = 1.0},
  },
  white = {
    name = "White",
    baseColor = {x = 0.95, y = 0.95, z = 0.95, w = 1.0},
  },
  black = {
    name = "Black",
    baseColor = {x = 0.05, y = 0.05, z = 0.05, w = 1.0},
  },
  silver = {
    name = "Silver",
    baseColor = {x = 0.75, y = 0.75, z = 0.75, w = 1.0},
  },
  gold = {
    name = "Gold",
    baseColor = {x = 0.85, y = 0.65, z = 0.13, w = 1.0},
  },
}

local finishTypes = {
  solid = {
    name = "Solid",
    metallic = 0.0,
    roughness = 0.8,
  },
  metallic = {
    name = "Metallic",
    metallic = 1.0,
    roughness = 0.3,
  },
  pearlescent = {
    name = "Pearlescent",
    metallic = 0.8,
    roughness = 0.2,
  },
}

-- ============================================================================
-- PAINT GENERATION
-- ============================================================================

-- Generate a random paint configuration for body parts
-- Returns: { paintData = { baseColor, metallic, roughness }, paintName = "Red Metallic" }
local function generateRandomPaint()
  -- Pick random color
  local colorKeys = {}
  for k, _ in pairs(colorDefinitions) do
    table.insert(colorKeys, k)
  end
  local colorKey = colorKeys[math.random(#colorKeys)]
  local color = colorDefinitions[colorKey]

  -- Pick random finish
  local finishKeys = {}
  for k, _ in pairs(finishTypes) do
    table.insert(finishKeys, k)
  end
  local finishKey = finishKeys[math.random(#finishKeys)]
  local finish = finishTypes[finishKey]

  -- Combine into paint data
  local paintData = {
    baseColor = {
      x = color.baseColor.x,
      y = color.baseColor.y,
      z = color.baseColor.z,
      w = color.baseColor.w,
    },
    metallic = finish.metallic,
    roughness = finish.roughness,
  }

  local paintName = color.name .. " " .. finish.name

  return {
    paintData = paintData,
    paintName = paintName,
  }
end

-- ============================================================================
-- CONFIG PATH RESOLUTION
-- ============================================================================

-- Resolve a config path for a vehicle model
-- @param model: Vehicle model key (e.g., "etki", "miramar")
-- @param configIdOrName: Either a full path or a short config name
-- @return: Full config path or nil if not found
local function resolveConfigPath(model, configIdOrName)
  if not model or not configIdOrName then
    return nil
  end

  -- If it's already a full path, return it
  if configIdOrName:find("vehicles/") then
    return configIdOrName
  end

  -- Otherwise, try to find it in the vehicle's configs
  local configPath = "vehicles/" .. model .. "/" .. configIdOrName

  -- Check if .pc extension is missing
  if not configIdOrName:find("%.pc$") then
    configPath = configPath .. ".pc"
  end

  -- Try to check if file exists
  if FS and FS.fileExists then
    if FS:fileExists(configPath) then
      return configPath
    end
  end

  -- Return the path anyway - let the caller handle if it doesn't exist
  return configPath
end

-- Pick a default config path for a vehicle model
-- Prefers configs with "Factory" or "Base" in the name
-- @param model: Vehicle model key (e.g., "etki", "miramar")
-- @return: Config path or nil
local function pickDefaultConfigPath(model)
  if not model then
    return nil
  end

  -- Try to get vehicle info
  local vehicleInfo = core_vehicles.getModel(model)
  if not vehicleInfo then
    log("W", logTag, "Could not find vehicle model: " .. tostring(model))
    return nil
  end

  -- Get all configs for this model
  local configs = vehicleInfo.configs or {}

  -- First pass: look for "Factory" or "Base" configs
  for configKey, configData in pairs(configs) do
    local configName = configData.Name or configKey
    if configName:lower():find("factory") or configName:lower():find("base") then
      return "vehicles/" .. model .. "/" .. configKey .. ".pc"
    end
  end

  -- Second pass: just pick the first one
  for configKey, _ in pairs(configs) do
    return "vehicles/" .. model .. "/" .. configKey .. ".pc"
  end

  log("W", logTag, "No configs found for model: " .. tostring(model))
  return nil
end

-- ============================================================================
-- VEHICLE CONFIG PARSING
-- ============================================================================

-- Parse a vehicle PC file and extract parts list
-- @param configPath: Path to .pc file (e.g., "vehicles/etki/2400ti.pc")
-- @return: { model = "etki", parts = { slotType = partName }, vars = { ... } } or nil on error
local function parseVehicleConfig(configPath)
  if not configPath then
    log("E", logTag, "parseVehicleConfig: No config path provided")
    return nil
  end

  -- Read the file
  local fileContent = readFile(configPath)
  if not fileContent then
    log("E", logTag, "parseVehicleConfig: Could not read file: " .. tostring(configPath))
    return nil
  end

  -- Parse JSON
  local success, configData = pcall(jsonDecode, fileContent)
  if not success or not configData then
    log("E", logTag, "parseVehicleConfig: Failed to parse JSON from: " .. tostring(configPath))
    return nil
  end

  -- Extract model name from path (e.g., "vehicles/etki/config.pc" -> "etki")
  local model = configPath:match("vehicles/([^/]+)/")
  if not model then
    log("W", logTag, "parseVehicleConfig: Could not extract model from path: " .. tostring(configPath))
  end

  -- Extract parts from config
  local parts = {}
  if configData.parts then
    for slotType, partName in pairs(configData.parts) do
      parts[slotType] = partName
    end
  end

  -- Extract vars
  local vars = {}
  if configData.vars then
    for varName, varValue in pairs(configData.vars) do
      vars[varName] = varValue
    end
  end

  return {
    model = model,
    parts = parts,
    vars = vars,
    configPath = configPath,
  }
end

-- ============================================================================
-- CHECKLIST BUILDING
-- ============================================================================

-- Part categories for organizing checklist
local partCategories = {
  -- Drivetrain
  engine = "drivetrain",
  transmission = "drivetrain",
  differential = "drivetrain",
  transfer_case = "drivetrain",
  driveshaft = "drivetrain",
  axle = "drivetrain",

  -- Suspension
  suspension = "suspension",
  coilover = "suspension",
  spring = "suspension",
  shock = "suspension",
  strut = "suspension",

  -- Exterior
  body = "exterior",
  fender = "exterior",
  bumper = "exterior",
  door = "exterior",
  hood = "exterior",
  trunk = "exterior",
  roof = "exterior",
  mirror = "exterior",
  grille = "exterior",
  headlight = "exterior",
  taillight = "exterior",

  -- Interior
  interior = "interior",
  seat = "interior",
  dashboard = "interior",
  steering = "interior",

  -- Other
  wheel = "other",
  tire = "other",
  brake = "other",
  exhaust = "other",
}

-- Determine category for a slot type
-- @param slotType: Part slot type string
-- @return: Category name ("drivetrain", "suspension", "exterior", "interior", "other")
local function categorizeSlotType(slotType)
  if not slotType then
    return "other"
  end

  local slotLower = slotType:lower()

  -- Check against category keywords
  for keyword, category in pairs(partCategories) do
    if slotLower:find(keyword) then
      return category
    end
  end

  return "other"
end

-- Determine if a part slot is mandatory (required for vehicle to function)
-- @param slotType: Part slot type string
-- @return: boolean
local function isSlotMandatory(slotType)
  if not slotType then
    return false
  end

  local slotLower = slotType:lower()

  -- Mandatory slots: engine, transmission, differential
  if slotLower:find("engine") then
    return true
  end
  if slotLower:find("transmission") then
    return true
  end
  if slotLower:find("differential") then
    return true
  end

  return false
end

-- Generate a nice human-readable name for a part
-- @param partName: Internal part name (e.g., "etki_engine_i4_sport")
-- @return: Nice name (e.g., "2.4L Sport Engine")
local function generateNiceName(partName)
  if not partName then
    return "Unknown Part"
  end

  -- Try to get part info from jbeam
  local partInfo = nil
  if jbeamIO and jbeamIO.getPart then
    partInfo = jbeamIO.getPart(partName)
  end

  if partInfo and partInfo.name then
    return partInfo.name
  end

  -- Fallback: clean up the part name
  -- Remove model prefix (e.g., "etki_" -> "")
  local cleanName = partName:gsub("^[^_]+_", "")

  -- Replace underscores with spaces
  cleanName = cleanName:gsub("_", " ")

  -- Capitalize first letter of each word
  cleanName = cleanName:gsub("(%a)([%w_']*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)

  return cleanName
end

-- Build a parts checklist from a target vehicle config
-- @param configPath: Path to target .pc file
-- @param model: Vehicle model key (optional, will be extracted from path if not provided)
-- @return: { slotType = { targetPart, mandatory, category, niceName } } or nil on error
local function buildPartsChecklistFromConfig(configPath, model)
  -- Parse the config
  local configData = parseVehicleConfig(configPath)
  if not configData then
    log("E", logTag, "buildPartsChecklistFromConfig: Failed to parse config: " .. tostring(configPath))
    return nil
  end

  -- Use model from config if not provided
  if not model then
    model = configData.model
  end

  -- Build checklist
  local checklist = {}
  for slotType, partName in pairs(configData.parts) do
    checklist[slotType] = {
      targetPart = partName,
      mandatory = isSlotMandatory(slotType),
      category = categorizeSlotType(slotType),
      niceName = generateNiceName(partName),
      slotType = slotType,
    }
  end

  log("I", logTag, "Built checklist with " .. tostring(tableSize(checklist)) .. " parts from: " .. tostring(configPath))

  return checklist
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

M.generateRandomPaint = generateRandomPaint
M.resolveConfigPath = resolveConfigPath
M.pickDefaultConfigPath = pickDefaultConfigPath
M.parseVehicleConfig = parseVehicleConfig
M.buildPartsChecklistFromConfig = buildPartsChecklistFromConfig
M.categorizeSlotType = categorizeSlotType
M.isSlotMandatory = isSlotMandatory
M.generateNiceName = generateNiceName

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Core module loaded")
end

M.onExtensionLoaded = onExtensionLoaded

return M
