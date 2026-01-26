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
-- Native Format Export & Mission Generation
-- ============================================================================

local function getMissionsFolder()
  return "gameplay/missions/" .. getCurrentLevel() .. "/aiRace/"
end

-- Calculate normal vector (direction to next point)
local function calculateNormal(pos1, pos2)
  local v1 = toVec3(pos1)
  local v2 = toVec3(pos2)
  if not v1 or not v2 then
    return {-1, 0, 0}  -- Default facing
  end
  local dir = (v2 - v1):normalized()
  return {dir.x, dir.y, dir.z}
end

-- Generate grid of start positions based on first checkpoint
local function generateStartPositions(startPos, startRot, count)
  local positions = {}
  local pos = toVec3(startPos)
  if not pos then return positions end

  -- Default rotation if not provided
  local rot = startRot or {0, 0, 0, 1}

  -- Calculate perpendicular vector for grid offset
  local forward = vec3(rot[1] or 0, rot[2] or 0, 0):normalized()
  if forward:length() < 0.1 then
    forward = vec3(1, 0, 0)
  end
  local right = vec3(-forward.y, forward.x, 0):normalized()

  -- Grid: 2 columns, offset back and sideways
  local rowSpacing = 10  -- meters between rows
  local colSpacing = 5   -- meters between columns

  for i = 1, count do
    local row = math.floor((i - 1) / 2)
    local col = (i - 1) % 2

    local offset = forward * (-row * rowSpacing) + right * ((col - 0.5) * colSpacing)
    local gridPos = pos + offset

    table.insert(positions, {
      name = "Racer Start " .. i,
      oldId = i + 1,
      pos = {gridPos.x, gridPos.y, gridPos.z},
      rot = rot
    })
  end

  return positions
end

-- Export race to native BeamNG .race.json format
local function exportToNativeFormat(raceName)
  local race = savedRaces[raceName]
  if not race then
    log("E", "mysummerRaceEditor", "Race not found: " .. tostring(raceName))
    return nil
  end

  local checkpoints = race.checkpoints
  if not checkpoints or #checkpoints < 2 then
    log("E", "mysummerRaceEditor", "Race has insufficient checkpoints")
    return nil
  end

  -- Build pathnodes
  local pathnodes = {}
  local baseId = 12  -- BeamNG convention starts at 12

  for i, cp in ipairs(checkpoints) do
    local nextCp = checkpoints[i + 1] or checkpoints[1]  -- Loop back for closed circuits
    local normal = calculateNormal(cp.pos, nextCp.pos)

    table.insert(pathnodes, {
      customFields = { names = {}, tags = {}, types = {}, values = {} },
      mode = "manual",
      name = "Pathnode " .. i,
      navRadiusScale = 1,
      normal = normal,
      oldId = baseId + i - 1,
      pos = cp.pos,
      radius = cp.radius or 15,
      recovery = -1,
      reverseRecovery = -1,
      sidePadding = {1, 3},
      visible = true
    })
  end

  -- Build segments
  local segments = {}
  for i = 1, #checkpoints do
    local fromId = baseId + i - 1
    local toId
    if i == #checkpoints then
      if race.closed then
        toId = baseId  -- Loop back to start
      else
        break  -- Open track, no final segment
      end
    else
      toId = baseId + i
    end

    table.insert(segments, {
      capsules = {},
      from = fromId,
      to = toId,
      mode = "waypoint",
      name = "Segment " .. i,
      oldId = baseId + #checkpoints + i - 1
    })
  end

  -- Generate start positions
  local firstCp = checkpoints[1]
  local startRot = firstCp.rotation or {0, 0, 0, 1}
  local startPositions = generateStartPositions(firstCp.pos, startRot, 10)

  -- Build race.json structure
  local raceJson = {
    authors = race.author or "Player",
    classification = {
      allowRollingStart = false,
      branching = false,
      closed = race.closed or false,
      reversible = false
    },
    date = race.created or os.time(),
    defaultLaps = race.laps or (race.closed and 3 or 1),
    defaultStartPosition = 2,
    description = "Custom race created with MySummer Race Editor",
    difficulty = 24,
    endNode = -1,
    forwardPrefabs = {},
    hideMission = false,
    name = race.name or "Custom Race",
    pacenotes = {},
    pathnodes = pathnodes,
    prefabs = {},
    reversePrefabs = {},
    reverseStartPosition = -1,
    rollingReverseStartPosition = -1,
    rollingStartPosition = -1,
    segments = segments,
    startNode = baseId,
    startPositions = startPositions
  }

  log("I", "mysummerRaceEditor", string.format(
    "Exported race '%s': %d pathnodes, %d segments, %d start positions",
    raceName, #pathnodes, #segments, #startPositions
  ))

  return raceJson
end

-- Generate complete mission structure (info.json + race.race.json)
local function generateMission(raceName, missionId)
  local race = savedRaces[raceName]
  if not race then
    log("E", "mysummerRaceEditor", "Race not found: " .. tostring(raceName))
    return nil
  end

  -- Generate race.json first
  local raceJson = exportToNativeFormat(raceName)
  if not raceJson then
    return nil
  end

  -- Create mission folder name
  missionId = missionId or string.format("%03d-CUSTOM-%s", os.time() % 1000, raceName:gsub("[^%w]", ""):sub(1, 10))
  local missionFolder = getMissionsFolder() .. missionId .. "/"

  -- Ensure folder exists
  if not FS:directoryExists(missionFolder) then
    FS:directoryCreate(missionFolder, true)
  end

  -- Get start position for trigger
  local firstCp = race.checkpoints[1]
  local startPos = firstCp.pos
  local startRot = firstCp.rotation or {0, 0, 0, 1}

  -- Build info.json
  local infoJson = {
    additionalAttributes = {
      difficulty = "medium"
    },
    author = race.author or "Player",
    careerSetup = {
      defaultStarKeys = {"justFinish", "finishSilver", "finishGold"},
      showInCareer = false,
      showInFreeroam = true,
      skill = "(none)",
      starOutroTexts = {
        cleanGoldRace = "Way to go!",
        noStarUnlocked = "Tough luck. Want to try again?"
      },
      starRewards = {
        finishGold = {
          { attributeKey = "money", rewardAmount = 3000 },
          { attributeKey = "beamXP", rewardAmount = 15 }
        },
        finishSilver = {
          { attributeKey = "money", rewardAmount = 1500 },
          { attributeKey = "beamXP", rewardAmount = 10 }
        },
        justFinish = {
          { attributeKey = "beamXP", rewardAmount = 5 }
        }
      },
      starsActive = {
        finishBronze = false,
        finishGold = true,
        finishSilver = true,
        justFinish = true
      }
    },
    customAdditionalAttributes = {},
    date = os.time(),
    description = "Custom race: " .. (race.name or raceName),
    devMission = true,  -- Mark as dev mission for testing
    grouping = {
      id = "CUSTOMRACE",
      label = "Custom Races"
    },
    isAvailableAsScenario = true,
    layers = {
      {
        dir = "/" .. missionFolder,
        fixed = true,
        isMissionFolderDir = true,
        isMissionTypeDir = false
      },
      {
        dir = "/gameplay/missionTypes/aiRace/",
        fixed = true,
        isMissionFolderDir = false,
        isMissionTypeDir = true
      }
    },
    missionType = "aiRace",
    missionTypeData = {
      allowFlip = true,
      allowRecover = true,
      camPathActive = true,
      damageFailActive = false,
      damageLimit = 10000,
      flipLimit = -1,
      goalLaps = race.laps or (race.closed and 3 or 1),
      goalTime = 300,  -- 5 minutes default
      lapCount = race.laps or (race.closed and 3 or 1),
      mapPreviewMode = "navgraph",
      maxRacerCount = 9,
      minRacerCount = 1,
      prefabActive = false,
      raceFile = "/" .. missionFolder .. "race.race.json",
      racerAggression = 1.0,
      racerAwareness = true,
      racerCount = 5,  -- Default 5 AI
      racerRandomnessScale = 1,
      racerRough = false,
      racerRubberbandMode = false,
      racerSkill = 0.8,
      recoverLimit = -1,
      shuffleGroup = true,
      smartStartPlace = true,
      startTitle = race.name or "Custom Race",
      startText = "Custom race created with MySummer Race Editor. Good luck!",
      stoppedLimit = 0,
      useGroundmarkers = false,
      vehicleGroupActive = true
    },
    name = race.name or "Custom Race",
    retryBehaviour = "infiniteRetries",
    setupModules = {
      environment = { enabled = false },
      traffic = {
        activeAmount = 0,
        amount = 0,
        enabled = false,
        useTraffic = false
      },
      vehicles = {
        enabled = true,
        includePlayerVehicle = true,
        prioritizePlayerVehicle = true,
        vehicles = {}
      }
    },
    startCondition = { type = "always" },
    startTrigger = {
      level = getCurrentLevel(),
      pos = startPos,
      radius = 10,
      rot = startRot,
      type = "coordinates"
    },
    visibleCondition = { type = "always" }
  }

  -- Write files
  local raceFilePath = missionFolder .. "race.race.json"
  local infoFilePath = missionFolder .. "info.json"

  jsonWriteFile(raceFilePath, raceJson, true)
  jsonWriteFile(infoFilePath, infoJson, true)

  log("I", "mysummerRaceEditor", "Generated mission at: " .. missionFolder)
  guihooks.trigger("toastrMsg", {
    type = "success",
    title = "Mission Generated",
    msg = "Mission created at: " .. missionFolder
  })

  return {
    missionId = missionId,
    folder = missionFolder,
    raceFile = raceFilePath,
    infoFile = infoFilePath
  }
end

-- Test mission ID (000-TEST template)
local testMissionId = "west_coast_usa/aiRace/000-TEST"
local testRaceFilePath = "/gameplay/missions/west_coast_usa/aiRace/000-TEST/race.race.json"

-- Test race with AI - writes to 000-TEST template and starts it
local function testRace(raceName)
  local race = savedRaces[raceName]
  if not race then
    log("E", "mysummerRaceEditor", "Race not found: " .. tostring(raceName))
    guihooks.trigger("toastrMsg", {
      type = "error",
      title = "Test Failed",
      msg = "Race '" .. tostring(raceName) .. "' not found. Use listRaces() to see available."
    })
    return false
  end

  -- Export our race to native format
  local raceJson = exportToNativeFormat(raceName)
  if not raceJson then
    guihooks.trigger("toastrMsg", {
      type = "error",
      title = "Test Failed",
      msg = "Failed to export race to native format"
    })
    return false
  end

  -- Write to the test mission's race file
  jsonWriteFile(testRaceFilePath, raceJson, true)
  log("I", "mysummerRaceEditor", "Wrote race to: " .. testRaceFilePath)

  guihooks.trigger("toastrMsg", {
    type = "info",
    title = "Starting Test Race",
    msg = "Loading: " .. raceName
  })

  -- Start the test mission
  if gameplay_missions_missionScreen then
    gameplay_missions_missionScreen.startMissionById(testMissionId, {}, {})
    log("I", "mysummerRaceEditor", "Test mission started: " .. testMissionId)
  else
    log("E", "mysummerRaceEditor", "Mission screen not available")
    return false
  end

  return true
end

-- List available races for testing
local function listRaces()
  local races = {}
  for name, race in pairs(savedRaces) do
    table.insert(races, {
      name = name,
      checkpoints = #(race.checkpoints or {}),
      closed = race.closed,
      level = race.level
    })
  end

  if #races == 0 then
    log("I", "mysummerRaceEditor", "No races saved. Use enableEditor() and drive to record a race.")
  else
    log("I", "mysummerRaceEditor", "Available races:")
    for _, r in ipairs(races) do
      log("I", "mysummerRaceEditor", string.format("  - %s (%d checkpoints, %s, %s)",
        r.name, r.checkpoints, r.closed and "circuit" or "sprint", r.level))
    end
  end

  return races
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

-- Native format export & testing
M.exportToNativeFormat = exportToNativeFormat
M.generateMission = generateMission
M.testRace = testRace
M.listRaces = listRaces

-- Lifecycle hooks
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onUpdate = onUpdate

-- Input hooks
M.filterDirectInput = filterDirectInput
M.onFilteredInputBegin = onFilteredInputBegin

return M
