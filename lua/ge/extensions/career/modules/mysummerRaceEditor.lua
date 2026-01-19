-- MySummer Race Editor
-- Allows players to create custom races by driving the track
-- Usage: Enable editor mode via console, then Shift+B to start/stop recording

local M = {}
M.dependencies = {
  "career_career",
  "career_saveSystem",
}

local saveFile = "mysummer_races.json"

-- Editor state
local state = {
  editorEnabled = false,
  recording = false,
  checkpoints = {},
  lastRecordPos = nil,
  recordDistance = 30, -- meters between auto-checkpoints
  startTime = 0,
  raceName = "",
  circularThreshold = 20, -- meters to detect circular track
}

-- All saved races
local savedRaces = {}

-- Input action name for Shift+B
local inputActionName = "mysummerRaceEditorToggle"

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function toVec3(pos)
  if not pos then return nil end
  if type(pos) == "cdata" or pos.x then
    return vec3(pos.x, pos.y, pos.z)
  end
  if type(pos) == "table" and #pos >= 3 then
    return vec3(pos[1], pos[2], pos[3])
  end
  return nil
end

local function serializeVec3(v)
  return {v.x, v.y, v.z}
end

local function getPlayerVehicle()
  return be:getPlayerVehicle(0)
end

local function getPlayerPosition()
  local veh = getPlayerVehicle()
  if not veh then return nil end
  return veh:getPosition()
end

local function getPlayerRotation()
  local veh = getPlayerVehicle()
  if not veh then return nil end
  return quat(veh:getRotation())
end

local function distanceBetween(pos1, pos2)
  local v1 = toVec3(pos1)
  local v2 = toVec3(pos2)
  if not v1 or not v2 then return math.huge end
  return (v1 - v2):length()
end

local function getCurrentLevel()
  local levelPath = getMissionFilename()
  if levelPath then
    local match = levelPath:match("levels/([^/]+)/")
    if match then return match end
  end
  return "unknown"
end

-- ============================================================================
-- Save/Load System
-- ============================================================================

local function getRacesFolder()
  -- Save in mod folder under settings
  return "settings/mysummer/races/"
end

local function ensureRacesFolder()
  local folder = getRacesFolder()
  if not FS:directoryExists(folder) then
    FS:directoryCreate(folder)
  end
end

local function loadSavedRaces()
  local folder = getRacesFolder()
  savedRaces = {}

  local files = FS:findFiles(folder, "*.json", 0, false, false)
  for _, filePath in ipairs(files) do
    local data = jsonReadFile(filePath)
    if data and data.name then
      savedRaces[data.name] = data
      savedRaces[data.name].filePath = filePath
    end
  end

  log("I", "mysummerRaceEditor", "Loaded " .. tableSize(savedRaces) .. " saved races")
end

local function saveRace(raceData)
  ensureRacesFolder()

  local fileName = raceData.name:gsub("[^%w_-]", "_") .. ".json"
  local filePath = getRacesFolder() .. fileName

  jsonWriteFile(filePath, raceData, true)
  savedRaces[raceData.name] = raceData
  savedRaces[raceData.name].filePath = filePath

  log("I", "mysummerRaceEditor", "Saved race: " .. raceData.name .. " to " .. filePath)
  return filePath
end

-- ============================================================================
-- Editor Mode
-- ============================================================================

local function enableEditorMode()
  state.editorEnabled = true
  log("I", "mysummerRaceEditor", "Editor mode ENABLED. Press Shift+B or use console: career_modules_mysummerRaceEditor.toggleRecording()")
  guihooks.trigger("toastrMsg", {
    type = "info",
    title = "Race Editor",
    msg = "Editor mode enabled. Press Shift+B or use console command to start recording."
  })
  print("MySummer Race Editor: ENABLED - Use Shift+B or career_modules_mysummerRaceEditor.toggleRecording()")
end

local function disableEditorMode()
  state.editorEnabled = false
  state.recording = false
  state.checkpoints = {}
  state.lastRecordPos = nil
  log("I", "mysummerRaceEditor", "Editor mode DISABLED")
  guihooks.trigger("toastrMsg", {
    type = "info",
    title = "Race Editor",
    msg = "Editor mode disabled."
  })
end

local function isEditorEnabled()
  return state.editorEnabled
end

-- ============================================================================
-- Recording Functions
-- ============================================================================

local function startRecording()
  if not state.editorEnabled then
    log("W", "mysummerRaceEditor", "Editor mode not enabled")
    return false
  end

  local pos = getPlayerPosition()
  if not pos then
    log("E", "mysummerRaceEditor", "No player vehicle found")
    return false
  end

  state.recording = true
  state.checkpoints = {}
  state.startTime = os.time()
  state.lastRecordPos = pos

  -- Add first checkpoint (start line)
  local rot = getPlayerRotation()
  table.insert(state.checkpoints, {
    pos = serializeVec3(pos),
    radius = 15,
    isStart = true,
    rotation = rot and {rot.x, rot.y, rot.z, rot.w} or nil
  })

  log("I", "mysummerRaceEditor", "Recording started at checkpoint 1")
  guihooks.trigger("toastrMsg", {
    type = "success",
    title = "Recording Started",
    msg = "Drive the track. Checkpoints are recorded every " .. state.recordDistance .. "m. Press Shift+B to finish."
  })

  -- Send update to UI
  guihooks.trigger("mysummerRaceEditorUpdate", {
    recording = true,
    checkpointCount = 1
  })

  return true
end

local function addCheckpoint()
  local pos = getPlayerPosition()
  if not pos then return false end

  table.insert(state.checkpoints, {
    pos = serializeVec3(pos),
    radius = 15,
    isStart = false
  })

  state.lastRecordPos = pos

  log("I", "mysummerRaceEditor", "Checkpoint " .. #state.checkpoints .. " added")

  -- Send update to UI
  guihooks.trigger("mysummerRaceEditorUpdate", {
    recording = true,
    checkpointCount = #state.checkpoints
  })

  return true
end

local function checkCircularClose()
  if #state.checkpoints < 3 then return false end

  local currentPos = getPlayerPosition()
  if not currentPos then return false end

  local startPos = toVec3(state.checkpoints[1].pos)
  if not startPos then return false end

  local distance = (currentPos - startPos):length()
  return distance < state.circularThreshold
end

local function stopRecording(forceName)
  if not state.recording then
    log("W", "mysummerRaceEditor", "Not currently recording")
    return nil
  end

  state.recording = false

  -- Check if we have enough checkpoints
  if #state.checkpoints < 2 then
    log("W", "mysummerRaceEditor", "Not enough checkpoints (minimum 2)")
    guihooks.trigger("toastrMsg", {
      type = "warning",
      title = "Recording Cancelled",
      msg = "Not enough checkpoints. Drive further before stopping."
    })
    state.checkpoints = {}
    return nil
  end

  -- Check if circular
  local isClosed = checkCircularClose()

  -- Generate race name
  local raceName = forceName or ("Race_" .. os.date("%Y%m%d_%H%M%S"))

  -- Create race data
  local raceData = {
    name = raceName,
    author = "Player",
    created = os.time(),
    level = getCurrentLevel(),
    type = isClosed and "circuit" or "sprint",
    checkpoints = deepcopy(state.checkpoints),
    closed = isClosed,
    laps = isClosed and 3 or 1,
    aiConfig = {
      count = 4,
      gridOrder = "random",
      racers = {}  -- Will use random pilots
    },
    settings = {
      traffic = false,
      countdown = true
    },
    timeAttack = {
      gold = 0,
      silver = 0,
      bronze = 0
    },
    rewards = {
      reputation = 50,
      money = {
        first = 5000,
        second = 2500,
        third = 1000
      }
    }
  }

  log("I", "mysummerRaceEditor", string.format(
    "Recording stopped. %d checkpoints, %s track",
    #state.checkpoints,
    isClosed and "closed" or "open"
  ))

  -- Clear state
  state.checkpoints = {}
  state.lastRecordPos = nil

  -- Notify UI to show config screen
  guihooks.trigger("mysummerRaceEditorUpdate", {
    recording = false,
    checkpointCount = 0
  })

  guihooks.trigger("mysummerRaceConfig", raceData)

  return raceData
end

local function toggleRecording()
  if state.recording then
    stopRecording()
  else
    startRecording()
  end
end

-- ============================================================================
-- Manual Checkpoint (Shift+B alternative)
-- ============================================================================

local function addManualCheckpoint()
  if not state.recording then
    log("W", "mysummerRaceEditor", "Not recording")
    return false
  end
  return addCheckpoint()
end

-- ============================================================================
-- Update Loop
-- ============================================================================

local function onUpdate(dt)
  if not state.editorEnabled then return end
  if not state.recording then return end

  local currentPos = getPlayerPosition()
  if not currentPos then return end

  -- Check for circular close
  if #state.checkpoints >= 3 and checkCircularClose() then
    log("I", "mysummerRaceEditor", "Circular track detected - auto-closing")
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = "Circular Track",
      msg = "Returned to start - track will be closed circuit."
    })
    stopRecording()
    return
  end

  -- Check distance for auto-checkpoint
  if state.lastRecordPos then
    local distance = (currentPos - toVec3(state.lastRecordPos)):length()
    if distance >= state.recordDistance then
      addCheckpoint()
    end
  end
end

-- ============================================================================
-- Input Handling (Shift+B detection)
-- ============================================================================

local shiftHeld = false
local bPressed = false

local function onKeyPressed(key, isDown)
  -- Track shift key state
  if key == "lshift" or key == "rshift" then
    shiftHeld = isDown
  end

  -- Detect B key with shift
  if key == "b" and isDown and shiftHeld then
    if state.editorEnabled then
      toggleRecording()
    end
  end
end

-- Alternative: Use filterDirectInput for raw keyboard input
local function filterDirectInput(devName, devOrdinal, devType, isUp, isTwoWay, inputType, inputValue, inputAction, defaultValue, inputCategory)
  -- Only process keyboard
  if devType ~= "keyboard" then return end

  local isDown = not isUp
  local keyLower = inputType and string.lower(inputType) or ""

  -- Debug logging - enabled to diagnose input issues
  if isDown and state.editorEnabled then
    log("I", "mysummerRaceEditor", "Key pressed: '" .. tostring(inputType) .. "' action: '" .. tostring(inputAction) .. "'")
  end

  -- Track shift (check multiple possible names)
  if keyLower == "lshift" or keyLower == "rshift" or keyLower == "shift" or
     inputType == "keyboard_lshift" or inputType == "keyboard_rshift" then
    shiftHeld = isDown
  end

  -- Shift+B to toggle recording
  if (keyLower == "b" or inputType == "keyboard_b") and isDown and shiftHeld then
    if state.editorEnabled then
      log("I", "mysummerRaceEditor", "Shift+B detected! Toggling recording...")
      toggleRecording()
      return true  -- Consume the input
    end
  end
end

-- onFilteredInputBegin hook - alternative input method
local function onFilteredInputBegin(devName, action, iValue, fValue, devType, isJoystick, ffbEffectRunning)
  if not state.editorEnabled then return end

  -- Check for our custom action or direct key
  if action == "toggleRaceRecording" or action == "mysummerRaceEditorToggle" then
    log("I", "mysummerRaceEditor", "Toggle action received")
    toggleRecording()
    return true
  end
end

-- ============================================================================
-- API Functions (called from console or UI)
-- ============================================================================

-- Console command: career_modules_mysummerRaceEditor.enableEditor()
local function enableEditor()
  enableEditorMode()
end

-- Console command: career_modules_mysummerRaceEditor.disableEditor()
local function disableEditor()
  disableEditorMode()
end

-- Console command: career_modules_mysummerRaceEditor.toggle()
local function toggle()
  if state.editorEnabled then
    if state.recording then
      toggleRecording()
    else
      disableEditorMode()
    end
  else
    enableEditorMode()
  end
end

-- Get list of all saved races
local function getRaces()
  return deepcopy(savedRaces)
end

-- Get races for current level
local function getRacesForLevel(level)
  level = level or getCurrentLevel()
  local result = {}
  for name, race in pairs(savedRaces) do
    if race.level == level then
      result[name] = race
    end
  end
  return result
end

-- Save race from UI config
local function saveRaceFromConfig(raceData)
  if not raceData or not raceData.name then
    log("E", "mysummerRaceEditor", "Invalid race data")
    return nil
  end

  local filePath = saveRace(raceData)

  guihooks.trigger("toastrMsg", {
    type = "success",
    title = "Race Saved",
    msg = "Race '" .. raceData.name .. "' saved successfully!"
  })

  return filePath
end

-- Delete a race
local function deleteRace(raceName)
  local race = savedRaces[raceName]
  if not race then
    log("W", "mysummerRaceEditor", "Race not found: " .. raceName)
    return false
  end

  if race.filePath and FS:fileExists(race.filePath) then
    FS:removeFile(race.filePath)
  end

  savedRaces[raceName] = nil
  log("I", "mysummerRaceEditor", "Deleted race: " .. raceName)
  return true
end

-- Set recording distance
local function setRecordDistance(distance)
  state.recordDistance = math.max(10, math.min(100, distance or 30))
  log("I", "mysummerRaceEditor", "Record distance set to " .. state.recordDistance .. "m")
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

local function onExtensionLoaded()
  log("I", "mysummerRaceEditor", "MySummer Race Editor loaded")
  loadSavedRaces()
end

local function onCareerActive(active)
  if active then
    loadSavedRaces()
  else
    disableEditorMode()
  end
end

-- ============================================================================
-- Module Interface
-- ============================================================================

-- Public API
M.enableEditor = enableEditor
M.disableEditor = disableEditor
M.toggle = toggle
M.toggleRecording = toggleRecording
M.addManualCheckpoint = addManualCheckpoint
M.stopRecording = stopRecording
M.isEditorEnabled = isEditorEnabled
M.getRaces = getRaces
M.getRacesForLevel = getRacesForLevel
M.saveRaceFromConfig = saveRaceFromConfig
M.deleteRace = deleteRace
M.setRecordDistance = setRecordDistance

-- Lifecycle hooks
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onUpdate = onUpdate

-- Input hooks
M.filterDirectInput = filterDirectInput
M.onFilteredInputBegin = onFilteredInputBegin

return M
