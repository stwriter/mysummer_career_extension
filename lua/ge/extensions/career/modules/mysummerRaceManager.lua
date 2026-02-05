-- MySummer Race Manager
-- Handles native street race missions integration
-- Rewards are applied manually since skipUnlockCheck bypasses native rewards

local M = {}
M.dependencies = {
  "career_career",
  "career_modules_playerAttributes",
  "career_modules_inventory",
  -- Note: mysummerStoryRaces is accessed dynamically
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

  -- AI Stuck Detection & Reset System
  aiStuckTimers = {},      -- {[vehId] = {time = secondsStuck, baseDamage = initialDamage}}
  aiLastGoodDir = {},      -- {[vehId] = vec3} - velocity direction when moving well
  aiRespawnQueue = {},     -- Queue of {vehId} to reset
  aiResetCounts = {},      -- {[vehId] = numberOfResets} - counter per vehicle
  aiAbandoned = {},        -- {[vehId] = true} - vehicles we gave up on (don't delete, just ignore)
  respawnCooldown = 0,     -- Cooldown between resets
  raceReallyStarted = false, -- True when player exceeds speed threshold
}

-- AI Reset Configuration
local AI_CONFIG = {
  playerSpeedEnableThreshold = 16,  -- m/s (~58 km/h) - player must exceed this to ENABLE detection
  playerSpeedDisableThreshold = 10, -- m/s (~36 km/h) - player must drop below this to DISABLE (hysteresis)
  stuckSpeedThreshold = 2,          -- m/s - below this is considered stuck
  movingSpeedThreshold = 5,         -- m/s - above this is considered "moving normally"
  stuckTimeThreshold = 10,          -- seconds before push (just stuck, no damage)
  stuckDamagedTimeThreshold = 2,    -- seconds before push if also damaged
  damageThreshold = 15000,          -- damage increase to consider "newly damaged"
  resetCooldown = 1.0,              -- seconds between actions
  maxResets = 3,                    -- maximum resets per vehicle before giving up
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
-- AI Stuck Detection & Respawn System
-- ============================================================================

-- Reset AI tracking state (called when race ends or restarts)
local function resetAITracking()
  state.aiStuckTimers = {}
  state.aiLastGoodDir = {}
  state.aiRespawnQueue = {}
  state.aiResetCounts = {}
  state.aiAbandoned = {}
  state.respawnCooldown = 0
  state.raceReallyStarted = false
  log("I", "mysummerRaceManager", "AI tracking reset")
end

-- Unstick an AI vehicle by teleporting to the side and giving it a push
-- @param vehId: vehicle ID
-- @param savedDir: saved velocity direction when vehicle was moving (optional)
local function respawnAIVehicle(vehId, savedDir)
  if not map or not map.objects or not map.objects[vehId] then
    log("W", "mysummerRaceManager", "Cannot unstick AI " .. tostring(vehId) .. " - no map data")
    return false
  end

  local data = map.objects[vehId]
  local veh = be:getObjectByID(vehId)
  if not veh then
    log("W", "mysummerRaceManager", "Cannot unstick AI " .. tostring(vehId) .. " - vehicle not found")
    return false
  end

  -- Check reset counter - if exceeded max, abandon vehicle (don't delete - needed for race restart)
  local resetCount = state.aiResetCounts[vehId] or 0
  if resetCount >= AI_CONFIG.maxResets then
    log("I", "mysummerRaceManager", string.format("AI %d exceeded max resets (%d), moving aside and abandoning", vehId, AI_CONFIG.maxResets))
    -- Move vehicle to the side before abandoning (so it doesn't block the track)
    local sideDir = state.aiLastGoodDir[vehId]
    if sideDir then
      -- Calculate perpendicular direction (to the right of travel direction)
      local perpDir = vec3(sideDir.y, -sideDir.x, 0)
      perpDir:normalize()
      local newPos = data.pos + (perpDir * 8) + vec3(0, 0, 0.5) -- 8m to the side
      veh:setPosRot(newPos.x, newPos.y, newPos.z, 0, 0, 0, 1)
    end
    state.aiAbandoned[vehId] = true
    state.aiStuckTimers[vehId] = nil
    return true
  end

  -- Get direction from saved velocity when vehicle was moving normally
  local moveDir = savedDir or state.aiLastGoodDir[vehId]
  if moveDir then
    if type(moveDir) == "table" and not moveDir.normalize then
      moveDir = vec3(moveDir.x or moveDir[1] or 0, moveDir.y or moveDir[2] or 0, moveDir.z or moveDir[3] or 0)
    end
    moveDir = vec3(moveDir.x, moveDir.y, 0) -- Flatten to horizontal
    if moveDir:length() > 0.01 then
      moveDir:normalize()
    else
      moveDir = nil
    end
  end

  -- Fallback: use current velocity if it has any magnitude
  if not moveDir and data.vel then
    local vel = data.vel
    if vel:length() > 0.5 then
      moveDir = vec3(vel.x, vel.y, 0)
      moveDir:normalize()
    end
  end

  -- Last resort fallback
  if not moveDir then
    moveDir = vec3(1, 0, 0)
    log("W", "mysummerRaceManager", "No direction data for AI " .. vehId .. ", using fallback")
  end

  local damage = data.damage or 0

  -- If heavily damaged (>50000), move aside and abandon (don't delete - needed for race restart)
  if damage > 50000 then
    log("I", "mysummerRaceManager", string.format("AI %d wrecked (damage %.0f), moving aside and abandoning", vehId, damage))
    -- Move vehicle to the side before abandoning
    if moveDir then
      local perpDir = vec3(moveDir.y, -moveDir.x, 0)
      perpDir:normalize()
      local newPos = data.pos + (perpDir * 8) + vec3(0, 0, 0.5)
      veh:setPosRot(newPos.x, newPos.y, newPos.z, 0, 0, 0, 1)
    end
    state.aiAbandoned[vehId] = true
    state.aiStuckTimers[vehId] = nil
    return true
  end

  -- Increment reset counter
  state.aiResetCounts[vehId] = resetCount + 1
  log("I", "mysummerRaceManager", string.format("Unsticking AI %d (reset %d/%d) - damage %.0f, dir=(%.2f,%.2f)",
      vehId, state.aiResetCounts[vehId], AI_CONFIG.maxResets, damage, moveDir.x, moveDir.y))

  -- Calculate rotation - negate direction because BeamNG vehicles face -Y by default
  local rot = quatFromDir(-moveDir, vec3(0, 0, 1))

  -- Teleport slightly forward and up to unstick
  -- Use setPosRot instead of safeTeleport to avoid interfering with race state tracking
  local newPos = data.pos + (moveDir * 3) + vec3(0, 0, 0.5)
  veh:setPosRot(newPos.x, newPos.y, newPos.z, rot.x, rot.y, rot.z, rot.w)

  -- Repair visual damage (broken mesh)
  veh:resetBrokenFlexMesh()

  -- Give an initial velocity push to get moving again
  local pushSpeed = 10  -- m/s (~36 km/h)
  veh:applyClusterVelocityScaleAdd(veh:getRefNodeId(), 0, moveDir.x * pushSpeed, moveDir.y * pushSpeed, 0)

  -- Clear stuck timer (but NOT reset count or direction)
  state.aiStuckTimers[vehId] = nil

  return true
end

-- Detect stuck or heavily damaged AI vehicles and queue them for respawn
-- Hybrid system: 2s stuck + damaged = respawn, 10s stuck = respawn
local function detectStuckAI(dt)
  if not map or not map.objects then return end

  local playerVehId = be:getPlayerVehicleID(0)
  local playerData = map.objects[playerVehId]

  -- Check player speed with hysteresis to avoid toggling
  local playerSpeed = (playerData and playerData.vel) and playerData.vel:length() or 0

  -- Hysteresis: need to go above 16 m/s to enable, below 10 m/s to disable
  if not state.raceReallyStarted and playerSpeed > AI_CONFIG.playerSpeedEnableThreshold then
    state.raceReallyStarted = true
    -- Reset all timers and queues when detection activates
    state.aiStuckTimers = {}
    state.aiLastGoodDir = {}
    state.aiRespawnQueue = {}
    log("I", "mysummerRaceManager", "AI detection ENABLED - player speed: " .. string.format("%.1f", playerSpeed) .. " m/s")
  elseif state.raceReallyStarted and playerSpeed < AI_CONFIG.playerSpeedDisableThreshold then
    state.raceReallyStarted = false
    log("I", "mysummerRaceManager", "AI detection DISABLED - player speed: " .. string.format("%.1f", playerSpeed) .. " m/s")
  end

  -- Don't detect if not in "racing" state
  if not state.raceReallyStarted then return end

  for vehId, data in pairs(map.objects) do
    -- Skip player vehicle and abandoned vehicles
    if vehId ~= playerVehId and not state.aiAbandoned[vehId] then
      local speed = data.vel and data.vel:length() or 0
      local damage = data.damage or 0

      -- If vehicle is moving normally, save its velocity direction (for later respawn)
      -- We use vel (velocity) not dirVec, because vel is the actual direction of travel
      if speed > AI_CONFIG.movingSpeedThreshold then
        if data.vel and data.vel:length() > 0.1 then
          state.aiLastGoodDir[vehId] = vec3(data.vel.x, data.vel.y, data.vel.z)
        end
        -- Clear stuck timer if vehicle is moving well
        state.aiStuckTimers[vehId] = nil
      -- Check if stuck (low speed)
      elseif speed < AI_CONFIG.stuckSpeedThreshold then
        -- Initialize stuck timer
        if not state.aiStuckTimers[vehId] then
          state.aiStuckTimers[vehId] = {
            time = 0,
            baseDamage = damage  -- Track initial damage when first detected as stuck
          }
        end
        state.aiStuckTimers[vehId].time = state.aiStuckTimers[vehId].time + dt

        -- Calculate new damage since getting stuck
        local newDamage = damage - (state.aiStuckTimers[vehId].baseDamage or 0)
        local isDamaged = newDamage > AI_CONFIG.damageThreshold

        -- Hybrid thresholds: 2s if damaged, 10s if just stuck
        local threshold = isDamaged and AI_CONFIG.stuckDamagedTimeThreshold or AI_CONFIG.stuckTimeThreshold
        local stuckLongEnough = state.aiStuckTimers[vehId].time >= threshold

        if stuckLongEnough then
          -- Check if not already in queue
          local alreadyQueued = false
          for _, queued in ipairs(state.aiRespawnQueue) do
            if queued.vehId == vehId then
              alreadyQueued = true
              break
            end
          end

          if not alreadyQueued then
            -- Use saved "good" direction (from when moving normally), not current direction
            local savedDir = state.aiLastGoodDir[vehId]
            table.insert(state.aiRespawnQueue, {
              vehId = vehId,
              dir = savedDir
            })
            local reason = isDamaged and string.format("stuck+damaged %.0f", newDamage) or "stuck 10s"
            log("I", "mysummerRaceManager", string.format("AI %d queued for respawn (%s, speed=%.1f, savedDir=%s)",
                vehId, reason, speed, savedDir and "yes" or "no"))
          end
        end
      end
    end
  end
end

-- Process reset queue (one vehicle per cooldown period)
local function processRespawnQueue(dt)
  state.respawnCooldown = state.respawnCooldown - dt

  if #state.aiRespawnQueue > 0 and state.respawnCooldown <= 0 then
    local queued = table.remove(state.aiRespawnQueue, 1)

    if respawnAIVehicle(queued.vehId, queued.dir) then
      state.respawnCooldown = AI_CONFIG.resetCooldown
    end
  end
end

-- ============================================================================
-- Native Mission System Integration
-- ============================================================================

-- Get available aiRace missions from BeamNG's mission system
-- Now includes ALL aiRace missions (vanilla + STREETRACE) for current map only
local function getAiRaceMissions()
  local missions = {}
  local currentLevel = getCurrentLevelIdentifier()

  if not currentLevel then
    log("W", "mysummerRaceManager", "No level loaded, cannot get missions")
    return missions
  end

  if gameplay_missions_missions then
    local allMissions = gameplay_missions_missions.getMissionsByMissionType("aiRace")
    if allMissions then
      for _, mission in pairs(allMissions) do
        -- Filter by current map (level is in startTrigger.level)
        local missionLevel = mission.startTrigger and mission.startTrigger.level

        if missionLevel == currentLevel then
          -- Include all aiRace missions, differentiate by source
          local isStreetRace = mission.grouping and mission.grouping.id == "STREETRACE"
          table.insert(missions, {
            id = mission.id,
            name = mission.name,
            description = mission.description,
            difficulty = mission.additionalAttributes and mission.additionalAttributes.difficulty or "medium",
            missionType = "aiRace",
            isNative = true,
            source = isStreetRace and "street" or "vanilla"
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

  log("I", "mysummerRaceManager", "Attempting to start mission: " .. tostring(missionId))

  -- Get mission info before starting
  local missionName = missionId
  local missionFound = false
  if gameplay_missions_missions then
    local mission = gameplay_missions_missions.getMissionById(missionId)
    if mission then
      missionName = mission.name or missionId
      missionFound = true
      log("I", "mysummerRaceManager", "Mission found: " .. missionName)
    else
      log("W", "mysummerRaceManager", "Mission NOT found with ID: " .. tostring(missionId))
      -- List available aiRace missions for debugging
      local available = getAiRaceMissions()
      log("I", "mysummerRaceManager", "Available aiRace missions (" .. #available .. "):")
      for i, m in ipairs(available) do
        if i <= 15 then -- Only show first 15
          log("I", "mysummerRaceManager", "  - " .. m.id .. " (" .. (m.name or "unnamed") .. ")")
        end
      end
      if #available > 15 then
        log("I", "mysummerRaceManager", "  ... and " .. (#available - 15) .. " more")
      end
    end
  end

  -- Track the native mission
  state.nativeMissionActive = true
  state.nativeMissionId = missionId
  state.nativeMissionName = missionName
  state.nativeMissionStartTime = os.clock()

  -- Start the mission (vehicle will be repaired by taskStartStartingOptionRepairStep)
  log("I", "mysummerRaceManager", "Calling startMissionById...")
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
      source = mission.source or "vanilla",  -- street or vanilla
      isNative = true
    }
  end

  return allRaces
end

-- ============================================================================
-- Reward System (manual application since skipUnlockCheck bypasses native)
-- ============================================================================

-- Reward definitions for street races (mirrors info.json starRewards)
local RACE_REWARDS = {
  finishGold = {   -- 1st place
    money = 3000,
    beamXP = 15,
    ["mysummer-streetracing"] = 200
  },
  finishSilver = { -- 2nd-3rd place
    money = 1500,
    beamXP = 10,
    ["mysummer-streetracing"] = 100
  },
  finishBronze = { -- 4th-6th place
    money = 100,
    beamXP = 50,
    ["mysummer-streetracing"] = 0
  }
}

-- Apply rewards based on position
local function applyRaceRewards(position, raceName)
  if not position then
    log("W", "mysummerRaceManager", "Cannot apply rewards - position unknown")
    return false
  end

  local rewardKey = nil
  if position == 1 then
    rewardKey = "finishGold"
  elseif position <= 3 then
    rewardKey = "finishSilver"
  elseif position <= 6 then
    rewardKey = "finishBronze"
  end

  if not rewardKey then
    log("I", "mysummerRaceManager", "Position " .. position .. " - no rewards (below bronze)")
    return false
  end

  local rewards = RACE_REWARDS[rewardKey]
  if not rewards then return false end

  log("I", "mysummerRaceManager", "Applying " .. rewardKey .. " rewards for position " .. position)

  -- Apply money reward
  if rewards.money and rewards.money > 0 then
    if career_modules_playerAttributes then
      career_modules_playerAttributes.addAttributes({money = rewards.money}, {tags = {"gameplay", "reward", "mission"}, label = "Race reward: " .. (raceName or "Street Race")})
      log("I", "mysummerRaceManager", "  +$" .. rewards.money)
    end
  end

  -- Apply beamXP reward
  if rewards.beamXP and rewards.beamXP > 0 then
    if career_modules_playerAttributes then
      career_modules_playerAttributes.addAttributes({beamXP = rewards.beamXP}, {tags = {"gameplay", "reward", "mission"}, label = "Race XP: " .. (raceName or "Street Race")})
      log("I", "mysummerRaceManager", "  +" .. rewards.beamXP .. " beamXP")
    end
  end

  -- Apply mysummer-streetracing XP
  if rewards["mysummer-streetracing"] and rewards["mysummer-streetracing"] > 0 then
    if career_modules_playerAttributes then
      career_modules_playerAttributes.addAttributes({["mysummer-streetracing"] = rewards["mysummer-streetracing"]}, {tags = {"gameplay", "reward", "mission"}, label = "Street Racing XP"})
      log("I", "mysummerRaceManager", "  +" .. rewards["mysummer-streetracing"] .. " street racing XP")
    end
  end

  return true
end

-- ============================================================================
-- Position Detection (for UI display only)
-- ============================================================================

-- Get player's final position from mission attempt data
local function getPlayerRacePosition(mission)
  -- Log available data for debugging
  log("D", "mysummerRaceManager", "Looking for position in mission object...")

  -- Try progress field - this stores highscores including placement
  if mission.progress then
    log("D", "mysummerRaceManager", "progress keys: " .. getTableKeys(mission.progress))
    -- Check for place in aggregate data
    if mission.progress.aggregate then
      log("D", "mysummerRaceManager", "progress.aggregate keys: " .. getTableKeys(mission.progress.aggregate))
      if mission.progress.aggregate.place then
        log("I", "mysummerRaceManager", "Found place in progress.aggregate: " .. tostring(mission.progress.aggregate.place))
        return mission.progress.aggregate.place
      end
    end
    -- Check for place directly
    if mission.progress.place then
      return mission.progress.place
    end
  end

  -- Try saveData which might have the latest attempt results
  if mission.saveData then
    log("D", "mysummerRaceManager", "saveData keys: " .. getTableKeys(mission.saveData))
    if mission.saveData.aggregate and mission.saveData.aggregate.place then
      return mission.saveData.aggregate.place
    end
    -- Check default progress key
    if mission.saveData.progress and mission.saveData.progress.default then
      local defaultProgress = mission.saveData.progress.default
      if defaultProgress.aggregate and defaultProgress.aggregate.place then
        log("I", "mysummerRaceManager", "Found place in saveData.progress.default.aggregate: " .. tostring(defaultProgress.aggregate.place))
        return defaultProgress.aggregate.place
      end
      -- Check latest attempt
      if defaultProgress.attempts and #defaultProgress.attempts > 0 then
        local latestAttempt = defaultProgress.attempts[#defaultProgress.attempts]
        if latestAttempt.data and latestAttempt.data.place then
          log("I", "mysummerRaceManager", "Found place in latest attempt: " .. tostring(latestAttempt.data.place))
          return latestAttempt.data.place
        end
      end
    end
  end

  -- Try autoUiAttemptProgress - check for placement in nested data
  if mission.autoUiAttemptProgress then
    local progress = mission.autoUiAttemptProgress
    log("D", "mysummerRaceManager", "autoUiAttemptProgress type: " .. type(progress))
    if type(progress) == "table" and progress[1] then
      log("D", "mysummerRaceManager", "autoUiAttemptProgress[1] keys: " .. getTableKeys(progress[1]))
      if progress[1].placement then return progress[1].placement end
      -- Check mainResult as number or string
      if progress[1].mainResult then
        local mainResult = progress[1].mainResult
        log("D", "mysummerRaceManager", "mainResult: " .. tostring(mainResult) .. " type: " .. type(mainResult))
        if type(mainResult) == "number" then return mainResult end
        local posNum = tonumber(string.match(tostring(mainResult), "(%d+)"))
        if posNum then return posNum end
      end
    end
  end

  -- Try currentAttemptData
  if mission.currentAttemptData then
    local attemptData = mission.currentAttemptData
    log("D", "mysummerRaceManager", "currentAttemptData keys: " .. getTableKeys(attemptData))
    if attemptData.placement then return attemptData.placement end
    if attemptData.place then return attemptData.place end
    -- Check nested data
    if attemptData.data then
      log("D", "mysummerRaceManager", "currentAttemptData.data keys: " .. getTableKeys(attemptData.data))
      if attemptData.data.place then return attemptData.data.place end
      if attemptData.data.placement then return attemptData.data.placement end
    end
  end

  -- Try autoUiAggregateProgress
  if mission.autoUiAggregateProgress then
    local agg = mission.autoUiAggregateProgress
    log("D", "mysummerRaceManager", "autoUiAggregateProgress keys: " .. getTableKeys(agg))
    if agg[1] then
      log("D", "mysummerRaceManager", "autoUiAggregateProgress[1] keys: " .. getTableKeys(agg[1]))
      if agg[1].value then
        log("D", "mysummerRaceManager", "autoUiAggregateProgress[1].value: " .. tostring(agg[1].value))
        local posNum = tonumber(agg[1].value)
        if posNum then return posNum end
      end
    end
  end

  -- Try extraRaceMission module (from extra_ai_races)
  if mathkuro_extraRaceMission and mathkuro_extraRaceMission.getCurrentRacePosition then
    local pos = mathkuro_extraRaceMission.getCurrentRacePosition()
    if pos and pos > 0 then
      log("I", "mysummerRaceManager", "Found position from extraRaceMission: " .. tostring(pos))
      return pos
    end
  end

  -- Last resort
  log("D", "mysummerRaceManager", "Mission top-level keys: " .. getTableKeys(mission))
  return nil
end

-- Determine race outcome from mission result
local function determineRaceOutcome(mission)
  -- Check if race was completed (mainResult = true means finished)
  local completed = false

  if mission.autoUiAttemptProgress and mission.autoUiAttemptProgress[1] then
    local mainResult = mission.autoUiAttemptProgress[1].mainResult
    completed = (mainResult == true) or (mainResult == "passed") or (mainResult == "completed")
  end

  if mission.currentAttemptData then
    if mission.currentAttemptData.type == "passed" or mission.currentAttemptData.type == "completed" then
      completed = true
    end
  end

  return completed
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

-- Called when any mission changes state
local function onAnyMissionChanged(missionState, mission)
  if not career_career or not career_career.isActive() then return end
  if not mission then return end

  -- Check if this is an aiRace mission (street race or vanilla)
  local isAiRaceMission = mission.missionType == "aiRace"
  if not isAiRaceMission then return end

  local isStreetRace = mission.grouping and mission.grouping.id == "STREETRACE"
  local raceType = isStreetRace and "street" or "vanilla"

  if missionState == "started" then
    state.nativeMissionActive = true
    state.nativeMissionId = mission.id
    state.nativeMissionName = mission.name
    state.nativeMissionStartTime = os.clock()

    -- Reset AI tracking for new race
    resetAITracking()

    log("I", "mysummerRaceManager", "Race started (" .. raceType .. "): " .. (mission.name or mission.id))

  elseif missionState == "stopped" then
    if not state.nativeMissionActive then return end

    local elapsedTime = os.clock() - state.nativeMissionStartTime
    local position = getPlayerRacePosition(mission)

    log("I", "mysummerRaceManager", "Race finished (" .. raceType .. ") - Position: " .. tostring(position))

    -- Log stars unlocked (this is what triggers rewards)
    if mission.currentAttemptData and mission.currentAttemptData.starsUnlocked then
      local stars = {}
      for star, unlocked in pairs(mission.currentAttemptData.starsUnlocked) do
        if unlocked then table.insert(stars, star) end
      end
      log("I", "mysummerRaceManager", "Stars unlocked: " .. table.concat(stars, ", "))
    end

    -- Log if this is a career mission
    log("I", "mysummerRaceManager", "showInCareer: " .. tostring(mission.careerSetup and mission.careerSetup.showInCareer))

    -- Debug: Log careerSetup starRewards
    if mission.careerSetup and mission.careerSetup.starRewards then
      log("I", "mysummerRaceManager", "starRewards keys: " .. getTableKeys(mission.careerSetup.starRewards))
      for starKey, rewards in pairs(mission.careerSetup.starRewards) do
        if type(rewards) == "table" and #rewards > 0 then
          log("I", "mysummerRaceManager", "  " .. starKey .. ": " .. #rewards .. " rewards defined")
        end
      end
    else
      log("W", "mysummerRaceManager", "No starRewards in careerSetup!")
    end

    -- Debug: Log unlockedStars from saveData
    if mission.saveData and mission.saveData.unlockedStars then
      local unlocked = {}
      for star, count in pairs(mission.saveData.unlockedStars) do
        if count and count > 0 then
          table.insert(unlocked, star .. "=" .. count)
        end
      end
      if #unlocked > 0 then
        log("I", "mysummerRaceManager", "unlockedStars: " .. table.concat(unlocked, ", "))
      else
        log("W", "mysummerRaceManager", "No stars unlocked in saveData!")
      end
    end

    -- Native BeamNG career system should handle rewards and post-race screen
    -- If stars are configured correctly in info.json

    -- Record race win for chapter progression (first place = win)
    if position == 1 then
      if career_modules_mysummerCareer and career_modules_mysummerCareer.recordRaceWin then
        career_modules_mysummerCareer.recordRaceWin(mission.id)
        log("I", "mysummerRaceManager", "Race win recorded for chapter progression")
      end
    end

    -- Notify story races system of race completion
    if career_modules_mysummerStoryRaces then
      -- Try to find the story race ID that matches this mission
      local storyRaceId = career_modules_mysummerStoryRaces.findRaceIdByMission(mission.id)
      if storyRaceId then
        career_modules_mysummerStoryRaces.completeRace(storyRaceId, position, elapsedTime)
        log("I", "mysummerRaceManager", "Story race completed: " .. storyRaceId)
      end
    end

    -- Clear tracking state
    state.nativeMissionActive = false
    state.nativeMissionId = nil
    state.nativeMissionName = nil

    -- Reset AI tracking
    resetAITracking()
  end
end

-- ============================================================================
-- Update Loop
-- ============================================================================

-- Debug: log counter to avoid spam
local debugLogCounter = 0

local function onUpdate(dt)
  -- Only process during active races
  if not state.nativeMissionActive then return end
  if not career_career or not career_career.isActive() then return end

  -- Debug log every 5 seconds
  debugLogCounter = debugLogCounter + dt
  if debugLogCounter >= 5 then
    debugLogCounter = 0
    local playerVehId = be:getPlayerVehicleID(0)
    local playerData = map and map.objects and map.objects[playerVehId]
    local playerSpeed = (playerData and playerData.vel) and playerData.vel:length() or 0
    local aiCount = 0
    if map and map.objects then
      for vehId, _ in pairs(map.objects) do
        if vehId ~= playerVehId then aiCount = aiCount + 1 end
      end
    end
    log("I", "mysummerRaceManager", string.format("DEBUG: raceActive=%s, playerSpeed=%.1f, aiVehicles=%d, raceStarted=%s, queueSize=%d",
        tostring(state.nativeMissionActive), playerSpeed, aiCount, tostring(state.raceReallyStarted), #state.aiRespawnQueue))
  end

  -- Detect stuck/damaged AI vehicles
  detectStuckAI(dt)

  -- Process respawn queue
  processRespawnQueue(dt)
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
    resetAITracking()
  end
end

-- ============================================================================
-- Manual Commands (for testing/debugging)
-- ============================================================================

-- Force unstick all AI vehicles (ignores all validations)
-- Usage: career_modules_mysummerRaceManager.forceUnstickAll()
local function forceUnstickAll()
  if not map or not map.objects then
    log("W", "mysummerRaceManager", "forceUnstickAll: no map data")
    return
  end

  local playerVehId = be:getPlayerVehicleID(0)
  local count = 0

  for vehId, data in pairs(map.objects) do
    if vehId ~= playerVehId then
      local veh = be:getObjectByID(vehId)
      if veh then
        -- Get direction from velocity (actual movement direction)
        local moveDir = nil

        -- First try saved good direction
        if state.aiLastGoodDir[vehId] then
          moveDir = state.aiLastGoodDir[vehId]
        -- Then try current velocity
        elseif data.vel and data.vel:length() > 0.5 then
          moveDir = vec3(data.vel.x, data.vel.y, 0)
        end

        -- Convert and normalize
        if moveDir then
          if type(moveDir) == "table" and not moveDir.normalize then
            moveDir = vec3(moveDir.x or 0, moveDir.y or 0, moveDir.z or 0)
          end
          moveDir = vec3(moveDir.x, moveDir.y, 0)
          if moveDir:length() > 0.01 then
            moveDir:normalize()
          else
            moveDir = vec3(1, 0, 0)
          end
        else
          moveDir = vec3(1, 0, 0)
        end

        -- Negate direction because BeamNG vehicles face -Y by default
        local rot = quatFromDir(-moveDir, vec3(0, 0, 1))

        -- Teleport slightly forward and up to unstick
        local newPos = data.pos + (moveDir * 3) + vec3(0, 0, 0.5)

        log("I", "mysummerRaceManager", string.format("forceUnstickAll: AI %d dir=(%.2f,%.2f)", vehId, moveDir.x, moveDir.y))

        -- Teleport WITHOUT full reset to preserve AI racing state
        spawn.safeTeleport(veh, newPos, rot, nil, nil, nil, nil, false)

        -- Repair visual damage (broken mesh)
        veh:resetBrokenFlexMesh()

        -- Give an initial velocity push
        local pushSpeed = 10  -- m/s (~36 km/h)
        veh:applyClusterVelocityScaleAdd(veh:getRefNodeId(), 0, moveDir.x * pushSpeed, moveDir.y * pushSpeed, 0)

        count = count + 1
      end
    end
  end

  log("I", "mysummerRaceManager", "forceUnstickAll: unstuck " .. count .. " AI vehicles")
  return count
end

-- ============================================================================
-- Module Interface
-- ============================================================================

M.startNativeMission = startNativeMission
M.getAvailableRaces = getAvailableRaces
M.getAiRaceMissions = getAiRaceMissions
M.forceUnstickAll = forceUnstickAll

-- Hooks
M.onUpdate = onUpdate
M.onAnyMissionChanged = onAnyMissionChanged
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive

return M
