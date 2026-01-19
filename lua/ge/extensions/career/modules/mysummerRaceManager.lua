-- MySummer Race Manager
-- Handles native street race missions integration
-- Rewards are handled by BeamNG's native star system (mysummer-streetracing attribute)

local M = {}
M.dependencies = {
  "career_career",
}

-- ============================================================================
-- State
-- ============================================================================

local state = {
  -- Native Street Race Mission Tracking
  nativeMissionActive = false,
  nativeMissionId = nil,
  nativeMissionName = nil,
  nativeMissionStartTime = 0,
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function formatTime(seconds)
  if not seconds or seconds < 0 then return "DNF" end
  local mins = math.floor(seconds / 60)
  local secs = seconds % 60
  return string.format("%d:%05.2f", mins, secs)
end

-- Helper to get table keys for logging
local function getTableKeys(t)
  local keys = {}
  if type(t) == "table" then
    for k, _ in pairs(t) do
      table.insert(keys, tostring(k))
    end
  end
  return table.concat(keys, ", ")
end

-- ============================================================================
-- Native Mission System Integration
-- ============================================================================

-- Get available aiRace missions from BeamNG's mission system
local function getAiRaceMissions()
  local missions = {}

  if gameplay_missions_missions then
    local allMissions = gameplay_missions_missions.getMissionsByMissionType("aiRace")
    if allMissions then
      for _, mission in pairs(allMissions) do
        -- Filter to street race missions (by grouping)
        if mission.grouping and mission.grouping.id == "STREETRACE" then
          table.insert(missions, {
            id = mission.id,
            name = mission.name,
            description = mission.description,
            difficulty = mission.additionalAttributes and mission.additionalAttributes.difficulty or "medium",
            missionType = "aiRace",
            isNative = true
          })
        end
      end
    end
  end

  return missions
end

-- Start a native BeamNG mission by ID
local function startNativeMission(missionId)
  if not gameplay_missions_missionScreen then
    log("E", "mysummerRaceManager", "gameplay_missions_missionScreen not available")
    return false
  end

  -- Get mission info before starting
  local missionName = missionId
  if gameplay_missions_missions then
    local mission = gameplay_missions_missions.getMissionById(missionId)
    if mission then
      missionName = mission.name or missionId
    end
  end

  -- Track the native mission
  state.nativeMissionActive = true
  state.nativeMissionId = missionId
  state.nativeMissionName = missionName
  state.nativeMissionStartTime = os.clock()

  -- Start the mission
  gameplay_missions_missionScreen.startMissionById(missionId, {}, {})
  return true
end

-- Get all available races (native missions)
local function getAvailableRaces()
  local allRaces = {}

  local nativeMissions = getAiRaceMissions()
  for _, mission in ipairs(nativeMissions) do
    allRaces[mission.id] = {
      id = mission.id,
      name = mission.name,
      description = mission.description,
      difficulty = mission.difficulty,
      source = "bundled",
      isNative = true
    }
  end

  return allRaces
end

-- ============================================================================
-- Position Detection (for UI display only)
-- ============================================================================

-- Get player's final position from mission attempt data
local function getPlayerRacePosition(mission)
  -- Try currentAttemptData first (most reliable during mission)
  if mission.currentAttemptData then
    local attemptData = mission.currentAttemptData
    if attemptData.placement then return attemptData.placement end
    if attemptData.playerFinishPosition then return attemptData.playerFinishPosition end
    if attemptData.position then return attemptData.position end
  end

  -- Try autoUiAttemptProgress (used by aiRace missions) - it's an array
  if mission.autoUiAttemptProgress then
    local progress = mission.autoUiAttemptProgress
    if progress[1] and progress[1].placement then
      return progress[1].placement
    end
    if progress.placement then return progress.placement end
  end

  -- Try autoUiAggregateProgress
  if mission.autoUiAggregateProgress then
    local agg = mission.autoUiAggregateProgress
    if agg.placement then return agg.placement end
  end

  return nil
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

-- Called when any mission changes state
local function onAnyMissionChanged(missionState, mission)
  if not career_career or not career_career.isActive() then return end
  if not mission then return end

  -- Check if this is a street race mission
  local isStreetRaceMission = mission.grouping and mission.grouping.id == "STREETRACE"
  if not isStreetRaceMission then return end

  if missionState == "started" then
    state.nativeMissionActive = true
    state.nativeMissionId = mission.id
    state.nativeMissionName = mission.name
    state.nativeMissionStartTime = os.clock()
    log("I", "mysummerRaceManager", "Street race started: " .. (mission.name or mission.id))

  elseif missionState == "stopped" then
    if not state.nativeMissionActive then return end

    local elapsedTime = os.clock() - state.nativeMissionStartTime
    local position = getPlayerRacePosition(mission)

    log("I", "mysummerRaceManager", "Street race finished - Position: " .. tostring(position))

    -- Send results to UI for display (rewards are handled by BeamNG's native star system)
    guihooks.trigger("mysummerStreetRaceResults", {
      raceName = mission.name or state.nativeMissionName,
      position = position,
      formattedTime = formatTime(elapsedTime),
    })

    -- Clear tracking state
    state.nativeMissionActive = false
    state.nativeMissionId = nil
    state.nativeMissionName = nil
  end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

local function onExtensionLoaded()
  log("I", "mysummerRaceManager", "MySummer Race Manager loaded (native rewards mode)")
end

local function onCareerActive(active)
  if not active then
    state.nativeMissionActive = false
    state.nativeMissionId = nil
    state.nativeMissionName = nil
  end
end

-- ============================================================================
-- Module Interface
-- ============================================================================

M.startNativeMission = startNativeMission
M.getAvailableRaces = getAvailableRaces
M.getAiRaceMissions = getAiRaceMissions

-- Hooks
M.onAnyMissionChanged = onAnyMissionChanged
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive

return M
