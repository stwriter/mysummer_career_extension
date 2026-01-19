-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.moduleName = "career_modules_mysummerCareer"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerCore",
  -- Note: mysummerParts and mysummerChecklist are checked at runtime to avoid circular deps
  "career_modules_inventory",
  "career_modules_garageManager",
  "career_modules_vehicleShopping",
}

local logTag = "mysummerCareer"
local cachedParkingSites = nil  -- Cache for parking sites

-- Helper function to check if a table contains a value
local function tableContains(tbl, value)
  if not tbl then return false end
  for _, v in ipairs(tbl) do
    if v == value then return true end
  end
  return false
end

-- ============================================================================
-- PHASE DEFINITIONS
-- ============================================================================

local phaseDefinitions = {
  [1] = {
    name = "Street Rookie",
    description = "Prove yourself in basic street races",
    requiredRaces = { "street_circuit_01", "industrial_loop_01" },
    requiredWins = 2,
    reputationReward = 500,
    partRewards = {}, -- TODO: Define specific parts
    cashReward = 2000,
    storyText = {
      intro = "You've inherited your grandfather's old Miramar and a half-built ETK-I project car. Time to prove you're worthy of his legacy.",
      completion = "Not bad for a first timer. The street is taking notice.",
    },
  },
  [2] = {
    name = "Rally Initiate",
    description = "Take on dirt and gravel courses",
    prerequisites = { phase = 1, reputationLevel = 5 },
    requiredRaces = { "rally_forest_01", "rally_mountain_01", "rally_stage_01" },
    requiredWins = 2,
    reputationReward = 750,
    partRewards = {},
    cashReward = 3500,
    storyText = {
      intro = "The tarmac crowd respects you. Now let's see how you handle loose surfaces.",
      completion = "Impressive. You're not just a street racer anymore.",
    },
  },
  [3] = {
    name = "Circuit Contender",
    description = "Master technical circuit racing",
    prerequisites = { phase = 2, reputationLevel = 15 },
    requiredRaces = { "circuit_technical_01", "circuit_fast_01" },
    requiredWins = 3,
    reputationReward = 1000,
    partRewards = {},
    cashReward = 5000,
    storyText = {
      intro = "Time to take it to the track. Real racing, real competition.",
      completion = "You're getting faster. But there's still a long way to go.",
    },
  },
  [4] = {
    name = "Performance Specialist",
    description = "Win races with specific performance requirements",
    prerequisites = { phase = 3, reputationLevel = 25 },
    requiredRaces = { "performance_challenge_01", "performance_challenge_02" },
    requiredWins = 4,
    reputationReward = 1500,
    partRewards = {},
    cashReward = 7500,
    storyText = {
      intro = "Your skills are solid. Now let's see if you can tune a car to match.",
      completion = "You understand what makes a car fast. That's rare.",
    },
  },
  [5] = {
    name = "Underground Legend",
    description = "Dominate the underground racing scene",
    prerequisites = { phase = 4, reputationLevel = 40 },
    requiredRaces = { "underground_01", "underground_02", "underground_03" },
    requiredWins = 5,
    reputationReward = 2000,
    partRewards = {},
    cashReward = 10000,
    storyText = {
      intro = "The underground calls. This is where legends are made.",
      completion = "They're talking about you in every garage and back alley. You're a legend.",
    },
  },
  [6] = {
    name = "Endurance Racer",
    description = "Prove your consistency over long races",
    prerequisites = { phase = 5, reputationLevel = 50 },
    requiredRaces = { "endurance_01", "endurance_02" },
    requiredWins = 2,
    reputationReward = 2500,
    partRewards = {},
    cashReward = 15000,
    storyText = {
      intro = "Speed is one thing. But can you maintain it for hours?",
      completion = "Your consistency is unmatched. The car is an extension of you.",
    },
  },
  [7] = {
    name = "International Challenge",
    description = "Compete against international drivers",
    prerequisites = { phase = 6, reputationLevel = 60 },
    requiredRaces = { "international_01", "international_02", "international_03" },
    requiredWins = 5,
    reputationReward = 3000,
    partRewards = {},
    cashReward = 20000,
    storyText = {
      intro = "Your reputation has spread beyond borders. They're flying in to race you.",
      completion = "You've beaten the best from around the world. Impressive doesn't cover it.",
    },
  },
  [8] = {
    name = "Championship Qualifier",
    description = "Qualify for the final championship",
    prerequisites = { phase = 7, reputationLevel = 70 },
    requiredRaces = { "qualifier_01", "qualifier_02", "qualifier_03" },
    requiredWins = 6,
    reputationReward = 4000,
    partRewards = {},
    cashReward = 30000,
    storyText = {
      intro = "This is it. Win these qualifiers and you're in the championship.",
      completion = "You're in. The championship awaits.",
    },
  },
  [9] = {
    name = "Semi-Finals",
    description = "The penultimate challenge",
    prerequisites = { phase = 8, reputationLevel = 80 },
    requiredRaces = { "semifinal_01", "semifinal_02" },
    requiredWins = 2,
    reputationReward = 5000,
    partRewards = {},
    cashReward = 50000,
    storyText = {
      intro = "Two races stand between you and the final. Everything you've built leads to this.",
      completion = "One race left. One chance at greatness.",
    },
  },
  [10] = {
    name = "Championship Final",
    description = "The ultimate test",
    prerequisites = {
      phase = 9,
      reputationLevel = 90,
      checklistCompletion = 90,  -- Must have 90% of build complete
    },
    requiredRaces = { "championship_final" },
    requiredWins = 1,
    reputationReward = 10000,
    partRewards = {},
    cashReward = 100000,
    unlocksFreePlay = true,  -- Remove all restrictions after
    storyText = {
      intro = "Your grandfather would be proud. The final race. Win this, and the legend is complete.",
      completion = "CHAMPION. You did it. The car, the build, the journey - all worth it. You're free to race however you want now.",
    },
  },
}

-- ============================================================================
-- RACE LOCATIONS
-- ============================================================================

-- Race locations mapped to RLS freeroam events
-- rlsRace = name of the race in RLS race_data.json (trigger: fre_staging_<rlsRace>)
local raceLocations = {
  -- Phase 1: Street Rookie (easy street races)
  street_circuit_01 = { name = "Beach Circuit", description = "Offroad circuit by the beach", rlsRace = "beachCircuit" },
  industrial_loop_01 = { name = "Quarry Circuit", description = "Race through the quarry", rlsRace = "quarryCircuit" },

  -- Phase 2: Rally Initiate (dirt/offroad)
  rally_forest_01 = { name = "Dirt Circuit", description = "Dirt rally circuit", rlsRace = "dirtCircuit" },
  rally_mountain_01 = { name = "Dirt Oval", description = "Fast dirt oval track", rlsRace = "dirtOval" },
  rally_stage_01 = { name = "Rally Stage 1", description = "Rally stage through countryside", rlsRace = "rally1" },

  -- Phase 3: Circuit Contender (track racing)
  circuit_technical_01 = { name = "Race Track", description = "Professional race track", rlsRace = "track" },
  circuit_fast_01 = { name = "Rubber Band", description = "High speed circuit", rlsRace = "rubberBand" },

  -- Phase 4: Performance Specialist (drag/speed)
  performance_challenge_01 = { name = "Drag Strip", description = "Quarter mile drag race", rlsRace = "drag" },
  performance_challenge_02 = { name = "Highway Drag", description = "Highway drag racing", rlsRace = "dragHighway" },

  -- Phase 5: Underground Legend (drift/touge)
  underground_01 = { name = "Island Touge", description = "Mountain pass racing", rlsRace = "islandTouge" },
  underground_02 = { name = "Drift Loop", description = "Drift competition", rlsRace = "driftLoopRemaster" },
  underground_03 = { name = "Hot Rolled Drift", description = "Industrial drift zone", rlsRace = "hotrolledDrift" },

  -- Phase 6: Endurance (longer races)
  endurance_01 = { name = "Redwood Drift", description = "Forest drift run", rlsRace = "redwoodDrift" },
  endurance_02 = { name = "Sealbrik Drift", description = "Technical drift course", rlsRace = "sealbrikDrift" },

  -- Phase 7: International (track variants)
  international_01 = { name = "Race Track Alt", description = "Alternative track layout", rlsRace = "track" },
  international_02 = { name = "Rock Climb Long", description = "Long rock climb", rlsRace = "rockClimbL" },
  international_03 = { name = "Rock Climb Short", description = "Short rock climb sprint", rlsRace = "rockClimbS" },

  -- Phase 8: Championship Qualifier
  qualifier_01 = { name = "Track Qualifier", description = "Track qualification", rlsRace = "track" },
  qualifier_02 = { name = "Drag Qualifier", description = "Drag qualification", rlsRace = "drag" },
  qualifier_03 = { name = "Drift Qualifier", description = "Drift qualification", rlsRace = "raceTrackDrift" },

  -- Phase 9: Semi-Finals
  semifinal_01 = { name = "Semi-Final Circuit", description = "Circuit semi-final", rlsRace = "track" },
  semifinal_02 = { name = "Semi-Final Touge", description = "Touge semi-final", rlsRace = "islandTouge" },

  -- Phase 10: Championship Final
  championship_final = { name = "CHAMPIONSHIP FINAL", description = "The ultimate race at the track", rlsRace = "track" },
}

-- ============================================================================
-- RLS RACE MAPPING (for reputation rewards when completing RLS freeroam events)
-- ============================================================================

local rlsRaceMapping = {
  -- Offroad/Circuit races
  beachCircuit = { reputationReward = 150, type = "circuit", label = "Beach Circuit" },
  quarryCircuit = { reputationReward = 150, type = "circuit", label = "Quarry Circuit" },
  dirtCircuit = { reputationReward = 200, type = "rally", label = "Dirt Circuit" },
  dirtOval = { reputationReward = 180, type = "rally", label = "Dirt Oval" },

  -- Rally stages (from RLS race_data.json)
  rally1 = { reputationReward = 250, type = "rally", label = "Rally Stage 1" },
  rally2 = { reputationReward = 300, type = "rally", label = "Rally Stage 2" },
  rally3 = { reputationReward = 300, type = "rally", label = "Rally Stage 3" },
  rally4 = { reputationReward = 300, type = "rally", label = "Rally Stage 4 - Final" },

  -- Drag races
  drag = { reputationReward = 100, type = "drag", label = "Drag Strip" },
  dragHighway = { reputationReward = 120, type = "drag", label = "Highway Drag" },

  -- Drift races
  driftLoopRemaster = { reputationReward = 250, type = "drift", label = "Drift Loop" },
  hotrolledDrift = { reputationReward = 220, type = "drift", label = "Hot Rolled Drift" },
  redwoodDrift = { reputationReward = 230, type = "drift", label = "Redwood Drift" },
  sealbrikDrift = { reputationReward = 240, type = "drift", label = "Sealbrik Drift" },
  raceTrackDrift = { reputationReward = 260, type = "drift", label = "Race Track Drift" },

  -- Touge/Mountain races
  islandTouge = { reputationReward = 300, type = "touge", label = "Island Touge" },

  -- Track races
  track = { reputationReward = 350, type = "circuit", label = "Race Track" },
  rubberBand = { reputationReward = 280, type = "circuit", label = "Rubber Band" },

  -- Rock climb
  rockClimbL = { reputationReward = 200, type = "offroad", label = "Rock Climb Long" },
  rockClimbS = { reputationReward = 150, type = "offroad", label = "Rock Climb Short" },
}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  -- Reputation system (separate from RLS)
  reputation = {
    level = 0,        -- 0-100 scale
    tier = 1,         -- 1-5 (derived from level)
    points = 0,       -- Raw points (100 points = 1 level)
    tierThresholds = { 0, 20, 40, 60, 80 },  -- Level thresholds for tiers
  },

  -- Phase progression
  currentPhase = 0,   -- 0-10 (0 = not started)
  phaseProgress = {}, -- { [phaseId] = { wins, completedRaces = {}, completed, completedAt } }

  -- Race tracking
  raceHistory = {},   -- { [raceId] = { wins, attempts, bestTime, lastAttempt } }

  -- Initial vehicles
  hasInitialVehicles = false,
  projectInventoryId = nil,  -- ETK-I project car
  starterInventoryId = nil,  -- Miramar starter

  -- Custom race tracking
  activeCustomRace = nil,  -- { raceId, startTime, checkpointsHit, splitTimes, aiVehicleId, triggers }

  -- Pending AI configurations (processed in onUpdate)
  pendingAIConfigs = {},  -- { { vehId, config, delay } }
}

-- Custom race definitions (MySummer original races with AI)
local customRaces = {
  -- Will be populated with custom race configurations
  -- Example structure:
  -- my_circuit = {
  --   name = "My Circuit",
  --   checkpoints = { { pos = {x, y, z}, radius = 30 }, ... },
  --   startPos = { pos = {x, y, z}, rot = {0, 0, 1, 0} },
  --   aiOpponent = { model = "etki", config = "sport", aggression = 0.7 },
  --   targetTime = 60,
  --   reputationReward = 200
  -- }
}

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

local function getSaveFilePath()
  local savePath = career_saveSystem.getSaveRootDirectory()
  if not savePath then
    return nil
  end
  return savePath .. "/career/rls_career/mysummer/career.json"
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

  jsonWriteFile(saveFile, state, true)
  log("I", logTag, "State saved")
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
    log("E", logTag, "Failed to load save file")
    return
  end

  -- Restore state
  state.reputation = data.reputation or state.reputation
  state.currentPhase = data.currentPhase or 0
  state.phaseProgress = data.phaseProgress or {}
  state.raceHistory = data.raceHistory or {}
  state.hasInitialVehicles = data.hasInitialVehicles or false
  state.projectInventoryId = data.projectInventoryId
  state.starterInventoryId = data.starterInventoryId

  log("I", logTag, "State loaded - Phase: " .. state.currentPhase .. ", Level: " .. state.reputation.level)
end

-- ============================================================================
-- UI COMMUNICATION (defined early because it's called by reputation/phase functions)
-- ============================================================================

local function sendCareerUpdate()
  if not guihooks then
    return
  end

  local data = {
    reputation = state.reputation,
    currentPhase = state.currentPhase,
    phaseProgress = state.phaseProgress,
    phases = phaseDefinitions,
    projectInventoryId = state.projectInventoryId,
  }

  guihooks.trigger("mysummerCareerUpdated", data)
end

-- ============================================================================
-- REPUTATION SYSTEM
-- ============================================================================

-- Calculate tier from level
local function calculateTier(level)
  local thresholds = state.reputation.tierThresholds
  for tier = #thresholds, 1, -1 do
    if level >= thresholds[tier] then
      return tier
    end
  end
  return 1
end

-- Update reputation after tier calculation
local function updateReputationTier()
  local oldTier = state.reputation.tier
  state.reputation.tier = calculateTier(state.reputation.level)

  if state.reputation.tier > oldTier then
    log("I", logTag, "TIER UP! Now tier " .. state.reputation.tier)
    -- TODO: Show UI notification
  end
end

-- Add reputation points
-- @param points: Points to add
-- @param reason: Why points were awarded (for logging)
local function addReputationPoints(points, reason)
  local oldLevel = state.reputation.level

  state.reputation.points = state.reputation.points + points

  -- Convert points to levels (100 points = 1 level)
  local newLevels = math.floor(state.reputation.points / 100)
  state.reputation.level = math.min(100, newLevels)  -- Cap at 100
  state.reputation.points = state.reputation.points % 100  -- Keep remainder

  updateReputationTier()

  if state.reputation.level > oldLevel then
    log("I", logTag, string.format("LEVEL UP! %d -> %d (%s)", oldLevel, state.reputation.level, reason))
    -- TODO: Show UI notification
  end

  log("I", logTag, string.format("Reputation +%d (%s) - Level: %d, Tier: %d", points, reason, state.reputation.level, state.reputation.tier))

  saveState()
  sendCareerUpdate()
end

-- Get current reputation data
local function getReputation()
  return state.reputation
end

-- ============================================================================
-- PHASE PROGRESSION
-- ============================================================================

-- Check if prerequisites are met for a phase
-- @param phaseId: Phase number (1-10)
-- @return: canStart (boolean), reason (string if false)
local function checkPhasePrerequisites(phaseId)
  local phaseDef = phaseDefinitions[phaseId]
  if not phaseDef then
    return false, "Invalid phase"
  end

  -- Phase 1 has no prerequisites
  if phaseId == 1 then
    return true
  end

  local prereqs = phaseDef.prerequisites
  if not prereqs then
    return true
  end

  -- Check previous phase completion
  if prereqs.phase then
    local prevPhase = state.phaseProgress[prereqs.phase]
    if not prevPhase or not prevPhase.completed then
      return false, "Must complete Phase " .. prereqs.phase .. " first"
    end
  end

  -- Check reputation level
  if prereqs.reputationLevel and state.reputation.level < prereqs.reputationLevel then
    return false, "Requires Reputation Level " .. prereqs.reputationLevel
  end

  -- Check checklist completion (for final phase)
  if prereqs.checklistCompletion and career_modules_mysummerChecklist then
    local stats = career_modules_mysummerChecklist.getStats()
    if stats.completionPercent < prereqs.checklistCompletion then
      return false, string.format("Requires %d%% checklist completion", prereqs.checklistCompletion)
    end
  end

  return true
end

-- Start a new phase
-- @param phaseId: Phase number to start
local function startPhase(phaseId)
  local canStart, reason = checkPhasePrerequisites(phaseId)
  if not canStart then
    log("W", logTag, "Cannot start phase " .. phaseId .. ": " .. reason)
    return false, reason
  end

  -- Initialize phase progress
  if not state.phaseProgress[phaseId] then
    state.phaseProgress[phaseId] = {
      wins = 0,
      completedRaces = {},
      completed = false,
      completedAt = nil,
    }
  end

  state.currentPhase = phaseId
  saveState()
  sendCareerUpdate()

  log("I", logTag, "Started Phase " .. phaseId .. ": " .. phaseDefinitions[phaseId].name)
  return true
end

-- Check if a phase is completed
-- @param phaseId: Phase number
local function checkPhaseCompletion(phaseId)
  local phaseDef = phaseDefinitions[phaseId]
  local progress = state.phaseProgress[phaseId]

  if not phaseDef or not progress then
    return false
  end

  if progress.wins >= phaseDef.requiredWins then
    return true
  end

  return false
end

-- Complete a phase and award rewards
-- @param phaseId: Phase number
local function completePhase(phaseId)
  local phaseDef = phaseDefinitions[phaseId]
  if not phaseDef then
    return
  end

  local progress = state.phaseProgress[phaseId]
  if progress.completed then
    return  -- Already completed
  end

  -- Mark as completed
  progress.completed = true
  progress.completedAt = os.time()

  -- Award reputation
  if phaseDef.reputationReward and phaseDef.reputationReward > 0 then
    addReputationPoints(phaseDef.reputationReward, "Phase " .. phaseId .. " completion")
  end

  -- Award cash
  if phaseDef.cashReward and phaseDef.cashReward > 0 and career_modules_payment then
    career_modules_payment.reward(
      { money = { amount = phaseDef.cashReward } },
      { label = "Phase " .. phaseId .. " completion: " .. phaseDef.name, tags = { "gameplay", "reward", "phase" } },
      true
    )
  end

  -- TODO: Award part rewards

  -- Check if this unlocks free play
  if phaseDef.unlocksFreePlay then
    log("I", logTag, "FREE PLAY UNLOCKED! All restrictions removed.")
    -- TODO: Remove part tier restrictions
  end

  log("I", logTag, "PHASE COMPLETED: " .. phaseDef.name)

  saveState()
  sendCareerUpdate()

  -- Auto-start next phase if available
  if phaseDefinitions[phaseId + 1] then
    startPhase(phaseId + 1)
  end
end

-- ============================================================================
-- RACE INTEGRATION
-- ============================================================================

-- Called when a freeroam event (race) is completed
local function onFreeroamEventCompleted(eventData)
  if not eventData or eventData.eventType ~= "race" then
    return
  end

  local raceId = eventData.raceId or eventData.eventId
  local position = eventData.position or 999
  local time = eventData.time

  -- Update race history
  if not state.raceHistory[raceId] then
    state.raceHistory[raceId] = {
      wins = 0,
      attempts = 0,
      bestTime = nil,
      lastAttempt = nil,
    }
  end

  local history = state.raceHistory[raceId]
  history.attempts = history.attempts + 1
  history.lastAttempt = os.time()

  if time and (not history.bestTime or time < history.bestTime) then
    history.bestTime = time
  end

  -- Check if won (position 1)
  if position == 1 then
    history.wins = history.wins + 1

    -- Award reputation for win
    addReputationPoints(200, "Race win: " .. raceId)

    -- Check if this race is part of current phase
    if state.currentPhase > 0 and state.currentPhase <= 10 then
      local phaseDef = phaseDefinitions[state.currentPhase]
      local progress = state.phaseProgress[state.currentPhase]

      if phaseDef and progress and tableContains(phaseDef.requiredRaces, raceId) then
        -- This race counts toward phase progress
        if not tableContains(progress.completedRaces, raceId) then
          table.insert(progress.completedRaces, raceId)
          progress.wins = progress.wins + 1

          log("I", logTag, string.format("Phase %d progress: %d/%d wins",
            state.currentPhase, progress.wins, phaseDef.requiredWins))

          -- Check if phase is now complete
          if checkPhaseCompletion(state.currentPhase) then
            completePhase(state.currentPhase)
          end
        end
      end
    end
  end

  saveState()
end

-- ============================================================================
-- RLS RACE COMPLETION DETECTION
-- ============================================================================

-- Find which of our phase races maps to an RLS race
local function findMappedPhaseRace(rlsRaceName)
  for raceId, raceConfig in pairs(raceLocations) do
    if raceConfig.rlsRace == rlsRaceName then
      return raceId, raceConfig
    end
  end
  return nil, nil
end

-- Calculate reputation reward for completing an RLS race
local function calculateRLSRaceReward(rlsRaceName, isNewBest)
  local mapping = rlsRaceMapping[rlsRaceName]
  if mapping then
    local reward = mapping.reputationReward
    -- Bonus for new personal best time
    if isNewBest then
      reward = math.floor(reward * 1.25)
    end
    return reward
  end
  -- Base reward for unmapped races
  return 50
end

-- Called when player finishes an RLS freeroam race (detected via trigger)
local function onRLSRaceFinished(rlsRaceName, vehicleId)
  log("I", logTag, "RLS race finished detected: " .. tostring(rlsRaceName))

  -- Verify it's the player's vehicle (use same method as RLS freeroamEvents)
  local playerVehicleId = be:getPlayerVehicleID(0)
  if not playerVehicleId then
    log("W", logTag, "No player vehicle found")
    return
  end

  log("I", logTag, "Comparing vehicleId: " .. tostring(vehicleId) .. " vs playerVehicleId: " .. tostring(playerVehicleId))

  if playerVehicleId ~= vehicleId then
    log("I", logTag, "Race finished by non-player vehicle, ignoring")
    return
  end

  -- Get RLS race data if available
  local rlsRaceData = nil
  if gameplay_events_freeroam and gameplay_events_freeroam.getRace then
    rlsRaceData = gameplay_events_freeroam.getRace(rlsRaceName)
  end

  local raceLabel = rlsRaceName
  if rlsRaceMapping[rlsRaceName] then
    raceLabel = rlsRaceMapping[rlsRaceName].label or rlsRaceName
  elseif rlsRaceData and rlsRaceData.label then
    raceLabel = rlsRaceData.label
  end

  -- Award reputation points
  local reward = calculateRLSRaceReward(rlsRaceName, false)  -- TODO: detect new best time
  addReputationPoints(reward, "Carrera completada: " .. raceLabel)

  -- Show notification
  if ui_message then
    ui_message(string.format("+%d Reputation - %s", reward, raceLabel), 4, "Career", "success")
  end

  -- Check if this RLS race is mapped to one of our phase races
  local phaseRaceId, phaseRaceConfig = findMappedPhaseRace(rlsRaceName)
  if phaseRaceId and state.currentPhase > 0 then
    log("I", logTag, "Race maps to phase race: " .. phaseRaceId)

    -- Treat as a win for phase progress (RLS time trials = completion = win)
    local eventData = {
      eventType = "race",
      raceId = phaseRaceId,
      position = 1,  -- Completed = win
      time = nil,    -- Time not tracked here
    }
    onFreeroamEventCompleted(eventData)
  end

  -- Update race history
  if not state.raceHistory[rlsRaceName] then
    state.raceHistory[rlsRaceName] = {
      wins = 0,
      attempts = 0,
      bestTime = nil,
      lastAttempt = nil,
    }
  end
  local history = state.raceHistory[rlsRaceName]
  history.wins = history.wins + 1
  history.attempts = history.attempts + 1
  history.lastAttempt = os.time()

  saveState()
  sendCareerUpdate()
end

-- Listen for BeamNG trigger events (used by RLS freeroam races)
local function onBeamNGTrigger(data)
  if not career_career or not career_career.isActive() then
    return
  end

  -- IMPORTANT: Filter by player vehicle ID first (same as RLS does)
  local playerVehicleId = be:getPlayerVehicleID(0)
  if not playerVehicleId or playerVehicleId ~= data.subjectID then
    return  -- Ignore triggers from AI vehicles
  end

  local triggerName = data.triggerName or ""
  local event = data.event

  -- Detect RLS race finish triggers (only for player vehicle now)
  if event == "enter" and triggerName:match("^fre_finish_") then
    local rlsRaceName = triggerName:sub(12)  -- Remove "fre_finish_" prefix
    log("I", logTag, "Detected RLS finish trigger: " .. rlsRaceName .. " (player vehicle)")
    onRLSRaceFinished(rlsRaceName, data.subjectID)
  end

  -- Detect custom MySummer race checkpoints
  if event == "enter" and triggerName:match("^mysummer_cp_") then
    local parts = triggerName:sub(13)  -- Remove "mysummer_cp_" prefix
    local raceId, cpIndex = parts:match("^(.+)_(%d+)$")
    if raceId and cpIndex then
      onCustomRaceCheckpoint(raceId, tonumber(cpIndex))
    end
  end

  -- Detect custom MySummer race start
  if event == "enter" and triggerName:match("^mysummer_start_") then
    local raceId = triggerName:sub(16)  -- Remove "mysummer_start_" prefix
    onCustomRaceStart(raceId)
  end

  -- Detect custom MySummer race finish
  if event == "enter" and triggerName:match("^mysummer_finish_") then
    local raceId = triggerName:sub(17)  -- Remove "mysummer_finish_" prefix
    onCustomRaceFinish(raceId)
  end
end

-- ============================================================================
-- CUSTOM RACE SYSTEM (MySummer original races with AI opponents)
-- ============================================================================

-- Forward declarations for functions that have circular dependencies
local endCustomRace
local onCustomRaceStart
local onCustomRaceCheckpoint
local onCustomRaceFinish

-- Create checkpoint triggers for a custom race
local function createRaceCheckpoints(raceId)
  local race = customRaces[raceId]
  if not race or not race.checkpoints then
    log("W", logTag, "Cannot create checkpoints - race not found: " .. tostring(raceId))
    return nil
  end

  local triggers = {}
  log("I", logTag, "Creating " .. #race.checkpoints .. " checkpoints for race: " .. raceId)

  for i, cp in ipairs(race.checkpoints) do
    local trigger = createObject('BeamNGTrigger')
    if trigger then
      trigger:setPosition(vec3(cp.pos[1], cp.pos[2], cp.pos[3]))
      local radius = cp.radius or 30
      trigger:setScale(vec3(radius, radius, radius))
      trigger.triggerType = 0  -- Sphere type

      local triggerName = "mysummer_cp_" .. raceId .. "_" .. i
      trigger:registerObject(triggerName)
      triggers[i] = trigger
      log("I", logTag, "Created checkpoint " .. i .. " at: " .. cp.pos[1] .. ", " .. cp.pos[2] .. ", " .. cp.pos[3])
    end
  end

  -- Create start trigger
  if race.startPos then
    local startTrigger = createObject('BeamNGTrigger')
    if startTrigger then
      startTrigger:setPosition(vec3(race.startPos.pos[1], race.startPos.pos[2], race.startPos.pos[3]))
      startTrigger:setScale(vec3(20, 20, 20))
      startTrigger.triggerType = 0
      startTrigger:registerObject("mysummer_start_" .. raceId)
      triggers.start = startTrigger
    end
  end

  -- Create finish trigger (last checkpoint position or explicit finish)
  local finishPos = race.finishPos or race.checkpoints[#race.checkpoints]
  if finishPos then
    local finishTrigger = createObject('BeamNGTrigger')
    if finishTrigger then
      local pos = finishPos.pos or finishPos
      finishTrigger:setPosition(vec3(pos[1], pos[2], pos[3]))
      finishTrigger:setScale(vec3(30, 30, 30))
      finishTrigger.triggerType = 0
      finishTrigger:registerObject("mysummer_finish_" .. raceId)
      triggers.finish = finishTrigger
    end
  end

  return triggers
end

-- Cleanup race triggers
local function cleanupRaceTriggers(triggers)
  if not triggers then return end

  for key, trigger in pairs(triggers) do
    if trigger and trigger.delete then
      trigger:delete()
    end
  end
end

-- Spawn AI opponent for a race
local function spawnAIOpponent(raceConfig, raceId)
  if not raceConfig.aiOpponent then
    return nil
  end

  local ai = raceConfig.aiOpponent
  log("I", logTag, "Spawning AI opponent: " .. ai.model .. "/" .. (ai.config or "default"))

  -- Build spawn options
  local spawnPos = raceConfig.startPos and raceConfig.startPos.pos or { 0, 0, 0 }
  local spawnOptions = {
    model = ai.model,
    config = ai.config,
    pos = vec3(spawnPos[1] - 5, spawnPos[2], spawnPos[3]),  -- Offset slightly from start
    rot = raceConfig.startPos and raceConfig.startPos.rot or quat(0, 0, 1, 0),
  }

  -- Spawn vehicle
  local vehId = nil
  if core_vehicles and core_vehicles.spawnNewVehicle then
    vehId = core_vehicles.spawnNewVehicle(spawnOptions.model, spawnOptions)
  end

  if not vehId then
    log("W", logTag, "Failed to spawn AI vehicle")
    return nil
  end

  -- Queue AI configuration (processed in onUpdate after delay)
  table.insert(state.pendingAIConfigs, {
    vehId = vehId,
    config = {
      aggression = ai.aggression or 0.7,
      aiPath = raceConfig.aiPath
    },
    delay = 1.0  -- Wait 1 second before configuring
  })

  return vehId
end

-- Remove AI opponent vehicle
local function removeAIOpponent(vehId)
  if not vehId then return end

  local veh = be:getObjectByID(vehId)
  if veh then
    if core_vehicles and core_vehicles.removeVehicle then
      core_vehicles.removeVehicle(vehId)
    end
    log("I", logTag, "AI opponent removed: " .. vehId)
  end
end

-- Start a custom race
local function startCustomRace(raceId)
  local race = customRaces[raceId]
  if not race then
    log("W", logTag, "Cannot start race - not found: " .. tostring(raceId))
    return false
  end

  -- Cleanup any existing race
  if state.activeCustomRace then
    endCustomRace(false)
  end

  log("I", logTag, "Starting custom race: " .. raceId)

  -- Create triggers
  local triggers = createRaceCheckpoints(raceId)

  -- Spawn AI if configured
  local aiVehId = spawnAIOpponent(race, raceId)

  -- Initialize race state
  state.activeCustomRace = {
    raceId = raceId,
    startTime = 0,  -- Will be set when crossing start line
    checkpointsHit = 0,
    totalCheckpoints = #race.checkpoints,
    splitTimes = {},
    aiVehicleId = aiVehId,
    triggers = triggers,
    timerActive = false,
  }

  -- Show UI message
  if ui_message then
    ui_message("Race ready: " .. race.name .. " - Drive to start line!", 5, "Career")
  end

  -- Set waypoint to start
  if race.startPos and core_groundMarkers then
    core_groundMarkers.setPath(vec3(race.startPos.pos[1], race.startPos.pos[2], race.startPos.pos[3]))
  end

  return true
end

-- Called when player crosses start line
onCustomRaceStart = function(raceId)
  if not state.activeCustomRace or state.activeCustomRace.raceId ~= raceId then
    return
  end

  if state.activeCustomRace.timerActive then
    return  -- Already started
  end

  log("I", logTag, "Custom race started: " .. raceId)
  state.activeCustomRace.startTime = os.clock()
  state.activeCustomRace.timerActive = true

  -- Start AI if present
  if state.activeCustomRace.aiVehicleId then
    local veh = be:getObjectByID(state.activeCustomRace.aiVehicleId)
    if veh then
      veh:queueLuaCommand("ai.setMode('manual')")
    end
  end

  if ui_message then
    ui_message("GO!", 2, "Career")
  end
end

-- Called when player hits a checkpoint
onCustomRaceCheckpoint = function(raceId, checkpointIndex)
  if not state.activeCustomRace or state.activeCustomRace.raceId ~= raceId then
    return
  end

  if not state.activeCustomRace.timerActive then
    return  -- Race not started yet
  end

  -- Check if this is the expected next checkpoint
  local expectedIndex = state.activeCustomRace.checkpointsHit + 1
  if checkpointIndex ~= expectedIndex then
    log("W", logTag, "Wrong checkpoint order: expected " .. expectedIndex .. ", got " .. checkpointIndex)
    return
  end

  local elapsed = os.clock() - state.activeCustomRace.startTime
  state.activeCustomRace.splitTimes[checkpointIndex] = elapsed
  state.activeCustomRace.checkpointsHit = checkpointIndex

  log("I", logTag, string.format("Checkpoint %d/%d - Time: %.2fs",
    checkpointIndex, state.activeCustomRace.totalCheckpoints, elapsed))

  -- Show split time
  if ui_message then
    ui_message(string.format("Checkpoint %d - %.2fs", checkpointIndex, elapsed), 2, "Career")
  end
end

-- Called when player crosses finish line
onCustomRaceFinish = function(raceId)
  if not state.activeCustomRace or state.activeCustomRace.raceId ~= raceId then
    return
  end

  if not state.activeCustomRace.timerActive then
    return
  end

  -- Check all checkpoints were hit
  if state.activeCustomRace.checkpointsHit < state.activeCustomRace.totalCheckpoints then
    log("W", logTag, "Finish crossed but not all checkpoints hit: " ..
      state.activeCustomRace.checkpointsHit .. "/" .. state.activeCustomRace.totalCheckpoints)
    if ui_message then
      ui_message("Missed checkpoints! Race invalid.", 3, "Career", "error")
    end
    return
  end

  local finishTime = os.clock() - state.activeCustomRace.startTime
  log("I", logTag, string.format("Custom race finished: %s - Time: %.2fs", raceId, finishTime))

  local race = customRaces[raceId]

  -- Determine position (vs AI or target time)
  local position = 1
  local aiTime = nil

  -- TODO: Get AI finish time if applicable

  -- Calculate reward
  local reward = race.reputationReward or 150
  if race.targetTime and finishTime <= race.targetTime then
    reward = math.floor(reward * 1.5)  -- Bonus for beating target time
  end

  addReputationPoints(reward, "Custom race: " .. race.name)

  -- Show result
  if ui_message then
    ui_message(string.format("FINISHED! Time: %.2fs - +%d Reputation", finishTime, reward), 5, "Career", "success")
  end

  -- Update race history
  if not state.raceHistory[raceId] then
    state.raceHistory[raceId] = { wins = 0, attempts = 0, bestTime = nil, lastAttempt = nil }
  end
  local history = state.raceHistory[raceId]
  history.wins = history.wins + 1
  history.attempts = history.attempts + 1
  history.lastAttempt = os.time()
  if not history.bestTime or finishTime < history.bestTime then
    history.bestTime = finishTime
    if ui_message then
      ui_message("NEW PERSONAL BEST!", 3, "Career", "success")
    end
  end

  endCustomRace(true)
  saveState()
  sendCareerUpdate()
end

-- End/cleanup a custom race
endCustomRace = function(completed)
  if not state.activeCustomRace then
    return
  end

  local raceId = state.activeCustomRace.raceId
  log("I", logTag, "Ending custom race: " .. raceId .. " (completed: " .. tostring(completed) .. ")")

  -- Cleanup triggers
  cleanupRaceTriggers(state.activeCustomRace.triggers)

  -- Remove AI opponent
  removeAIOpponent(state.activeCustomRace.aiVehicleId)

  -- Clear waypoint
  if core_groundMarkers and core_groundMarkers.setPath then
    core_groundMarkers.setPath(nil)
  end

  state.activeCustomRace = nil
end

-- Cancel active custom race
local function cancelCustomRace()
  if state.activeCustomRace then
    if ui_message then
      ui_message("Race cancelled", 3, "Career")
    end
    endCustomRace(false)
  end
end

-- ============================================================================
-- INITIAL VEHICLES (MOVED FROM mysummerParts)
-- ============================================================================

-- Spawn the initial vehicles (Miramar starter + ETK-I project)
local function spawnInitialVehicles()
  if state.hasInitialVehicles then
    log("I", logTag, "Initial vehicles already spawned")
    return
  end

  log("I", logTag, "Spawning initial vehicles...")

  -- Check if vehicles already exist in inventory
  local existing = career_modules_inventory and career_modules_inventory.getVehicles() or {}
  for invId, veh in pairs(existing) do
    if veh and veh.model == "etki" and veh.config and veh.config.partConfigFilename and
       veh.config.partConfigFilename:find("mysummer_2400ti_ttsport_chassis") then
      state.projectInventoryId = invId
      state.hasInitialVehicles = true
      log("I", logTag, "Found existing ETK-I project car: " .. tostring(invId))
      saveState()
      return
    end
  end

  -- Ensure default garage exists
  if career_modules_garageManager and career_modules_garageManager.purchaseDefaultGarage then
    career_modules_garageManager.purchaseDefaultGarage()
  end

  local garageId = career_modules_garageManager and career_modules_garageManager.getNextAvailableSpace() or nil
  if not garageId then
    log("W", logTag, "No garage space available, skipping vehicle spawn")
    state.hasInitialVehicles = true
    saveState()
    return
  end

  -- For now, just mark as done - vehicles can be added manually or via parts market
  -- Full vehicle spawn requires more complex API calls that may not be available
  log("I", logTag, "Garage space available: " .. tostring(garageId))
  log("I", logTag, "Vehicle spawn deferred - use Parts Market to get project car")

  state.hasInitialVehicles = true
  saveState()

  log("I", logTag, "Initial setup complete")
end

-- Called after inventory is set up
local function onSetupInventoryFinished()
  -- Vehicle spawning is handled by mysummerParts module
  -- Here we just check for existing project vehicle and start phase 1

  -- Check if project vehicle exists
  if not state.projectInventoryId then
    local existing = career_modules_inventory and career_modules_inventory.getVehicles() or {}
    for invId, veh in pairs(existing) do
      if veh and veh.model == "etki" and veh.config and veh.config.partConfigFilename and
         veh.config.partConfigFilename:find("mysummer_2400ti_ttsport_chassis") then
        state.projectInventoryId = invId
        log("I", logTag, "Found project vehicle: " .. tostring(invId))
        break
      end
    end
  end

  -- Auto-start Phase 1 if not started
  if state.currentPhase == 0 then
    local phaseSuccess, phaseErr = pcall(startPhase, 1)
    if not phaseSuccess then
      log("E", logTag, "Failed to start Phase 1: " .. tostring(phaseErr))
    end
  end

  saveState()
end

-- ============================================================================
-- RACE NAVIGATION
-- ============================================================================

-- Get parking sites for race locations (uses gameplay_sites_sitesManager like taxi.lua)
local function getParkingSites()
  if cachedParkingSites then
    return cachedParkingSites
  end

  log("I", logTag, "getParkingSites: Searching for parking sites...")

  -- Method 1: Use sites manager like taxi.lua does
  if gameplay_sites_sitesManager then
    local sitePath = gameplay_sites_sitesManager.getCurrentLevelSitesFileByName('city')
    if sitePath then
      log("I", logTag, "Found city sites file: " .. tostring(sitePath))
      local siteData = gameplay_sites_sitesManager.loadSites(sitePath, true, true)
      if siteData and siteData.parkingSpots and siteData.parkingSpots.objects then
        local parkingList = {}
        for _, spot in pairs(siteData.parkingSpots.objects) do
          if spot.pos then
            table.insert(parkingList, { pos = spot.pos, name = spot.name or "parking" })
          end
        end
        if #parkingList > 0 then
          cachedParkingSites = parkingList
          log("I", logTag, "Found " .. #parkingList .. " parking spots from city sites")
          return cachedParkingSites
        end
      end
    else
      log("W", logTag, "No city sites file found for current level")
    end
  end

  -- Method 2: Fallback to freeroam_facilities
  if freeroam_facilities then
    local facilities = freeroam_facilities.getFacilities()
    if facilities then
      local parkingList = {}
      for facilityId, facility in pairs(facilities) do
        if facility.parkingSpots and facility.parkingSpots.general then
          for spotId, spot in pairs(facility.parkingSpots.general) do
            if spot.pos then
              table.insert(parkingList, { pos = spot.pos, name = spotId })
            end
          end
        end
      end
      if #parkingList > 0 then
        cachedParkingSites = parkingList
        log("I", logTag, "Found " .. #parkingList .. " parking spots from freeroam_facilities")
        return cachedParkingSites
      end
    end
  end

  log("W", logTag, "No parking sites found for current level")
  cachedParkingSites = {}
  return cachedParkingSites
end

-- Get the position for a race by finding the RLS staging trigger
local function getRacePosition(raceId)
  log("I", logTag, "getRacePosition called for: " .. tostring(raceId))

  local raceConfig = raceLocations[raceId]
  if not raceConfig then
    log("W", logTag, "Unknown race ID: " .. tostring(raceId))
    return nil
  end

  -- Try to find the RLS staging trigger for this race
  if raceConfig.rlsRace then
    local triggerName = "fre_staging_" .. raceConfig.rlsRace
    log("I", logTag, "Looking for trigger: " .. triggerName)

    local trigger = scenetree.findObject(triggerName)
    if trigger then
      local pos = trigger:getPosition()
      log("I", logTag, "Found trigger at: " .. tostring(pos.x) .. ", " .. tostring(pos.y) .. ", " .. tostring(pos.z))
      return pos
    else
      log("W", logTag, "Trigger not found: " .. triggerName)
    end
  end

  -- Fallback to predefined coordinates if available
  if raceConfig.pos then
    local pos = raceConfig.pos
    log("I", logTag, "Using fallback position: " .. pos[1] .. ", " .. pos[2] .. ", " .. pos[3])
    return vec3(pos[1], pos[2], pos[3])
  end

  log("W", logTag, "Race has no position defined: " .. tostring(raceId))
  return nil
end

-- Navigate to a race location
local function navigateToRace(raceId)
  log("I", logTag, "navigateToRace called with: " .. tostring(raceId))

  if not raceId then
    log("W", logTag, "No race ID provided")
    return { success = false, message = "No race ID provided" }
  end

  local raceConfig = raceLocations[raceId]
  if not raceConfig then
    log("W", logTag, "Unknown race: " .. tostring(raceId))
    return { success = false, message = "Unknown race" }
  end

  log("I", logTag, "Found race config: " .. raceConfig.name)

  local position = getRacePosition(raceId)
  if not position then
    log("W", logTag, "Could not find location for race: " .. tostring(raceId))
    return { success = false, message = "Race location not available" }
  end

  log("I", logTag, "Got position: " .. tostring(position.x) .. ", " .. tostring(position.y) .. ", " .. tostring(position.z))

  -- Set waypoint using core_groundMarkers (require lazily)
  local groundMarkers = core_groundMarkers or extensions.core_groundMarkers
  if not groundMarkers then
    -- Try to load it
    local success, gm = pcall(require, 'core/groundMarkers')
    if success then
      groundMarkers = gm
    end
  end

  if groundMarkers and groundMarkers.setPath then
    groundMarkers.setPath(position, { clearPathOnReachingTarget = true })
    log("I", logTag, "Set waypoint to race: " .. raceConfig.name)

    -- Show UI message
    if ui_message then
      ui_message("Navigate to: " .. raceConfig.name, 3, "Career")
    end

    return {
      success = true,
      message = "Navigate to " .. raceConfig.name,
      raceName = raceConfig.name,
      position = { x = position.x, y = position.y, z = position.z },
    }
  else
    log("W", logTag, "core_groundMarkers not available")
    return { success = false, message = "Navigation system not available" }
  end
end

-- Get available races for current phase
local function getAvailableRaces()
  local races = {}

  if state.currentPhase <= 0 then
    return races
  end

  local phaseDef = phaseDefinitions[state.currentPhase]
  if not phaseDef or not phaseDef.requiredRaces then
    return races
  end

  local progress = state.phaseProgress[state.currentPhase] or { completedRaces = {} }
  local completedRaces = progress.completedRaces or {}

  for _, raceId in ipairs(phaseDef.requiredRaces) do
    local raceConfig = raceLocations[raceId] or {}
    local isCompleted = false
    for _, completed in ipairs(completedRaces) do
      if completed == raceId then
        isCompleted = true
        break
      end
    end

    table.insert(races, {
      id = raceId,
      name = raceConfig.name or raceId,
      description = raceConfig.description or "",
      completed = isCompleted,
    })
  end

  return races
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Level names for street racing progression (matches info.json levels)
local levelNames = {
  [1] = "Rookie Racer",
  [2] = "Known Driver",
  [3] = "Street Regular",
  [4] = "Underground Star",
  [5] = "Street Legend",
}

-- Get native street racing progression from BeamNG's career_branches system
local function getNativeStreetRacingProgress()
  local result = {
    level = 1,
    levelName = "Rookie Racer",
    currentXP = 0,
    minXP = 0,
    maxXP = 250,
    totalXP = 0,
    isMaxLevel = false,
  }

  -- Try to get data from native career_branches system
  if not career_branches then
    log("W", logTag, "career_branches not available")
    return result
  end

  -- Get the streetracing skill data
  local skillId = "mysummer-streetracing"
  local skill = career_branches.getBranchById(skillId)

  if not skill then
    log("W", logTag, "Skill not found: " .. skillId)
    return result
  end

  -- Get current XP value
  local attKey = skill.attributeKey or skillId
  local totalXP = 0
  if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
    totalXP = career_modules_playerAttributes.getAttributeValue(attKey) or 0
  end

  -- Calculate level from XP
  local level, _, _, minXP, maxXP = career_branches.calcBranchLevelFromValue(totalXP, skillId)

  result.level = level or 1
  result.levelName = levelNames[result.level] or ("Level " .. result.level)
  result.totalXP = totalXP
  result.minXP = minXP or 0
  result.maxXP = maxXP or 250
  result.currentXP = totalXP - result.minXP
  result.isMaxLevel = result.level >= 5

  log("I", logTag, string.format("Native progress: Level %d (%s), XP: %d/%d",
    result.level, result.levelName, result.currentXP, result.maxXP - result.minXP))

  return result
end

-- Get career data for UI (formatted for Vue)
local function getCareerData()
  log("I", logTag, "getCareerData called")

  -- Get native street racing progression
  local nativeProgress = getNativeStreetRacingProgress()

  -- Get current phase object (from local state)
  local currentPhaseData = nil
  if state.currentPhase > 0 and phaseDefinitions[state.currentPhase] then
    local phaseDef = phaseDefinitions[state.currentPhase]
    local progress = state.phaseProgress[state.currentPhase] or { wins = 0, completedRaces = {} }
    currentPhaseData = {
      id = state.currentPhase,
      name = phaseDef.name,
      description = phaseDef.description,
      objectives = {
        { text = string.format("Win %d races", phaseDef.requiredWins), completed = progress.wins >= phaseDef.requiredWins },
      },
    }
  end

  -- Format phases as array for Vue
  local phasesArray = {}
  for phaseId, phaseDef in pairs(phaseDefinitions) do
    local progress = state.phaseProgress[phaseId] or {}
    local prereqs = phaseDef.prerequisites or {}

    table.insert(phasesArray, {
      id = phaseId,
      name = phaseDef.name,
      description = phaseDef.description,
      reputationRequired = prereqs.reputationLevel or 0,
      completed = progress.completed == true,
      locked = prereqs.phase and state.currentPhase < prereqs.phase,
    })
  end

  -- Sort by phase ID
  table.sort(phasesArray, function(a, b) return a.id < b.id end)

  -- Get available races for current phase
  local availableRaces = getAvailableRaces()

  return {
    -- Native progression data (from BeamNG's career_branches)
    nativeProgress = nativeProgress,
    -- Legacy reputation data (for backwards compatibility)
    reputation = {
      total = nativeProgress.totalXP,
      tier = nativeProgress.levelName:lower():gsub(" ", "_"),
      level = nativeProgress.level,
      points = nativeProgress.currentXP,
      breakdown = {},
    },
    currentPhase = currentPhaseData,
    phases = phasesArray,
    projectVehicle = state.projectInventoryId,
    availableRaces = availableRaces,
  }
end

-- Get project vehicle inventory ID
local function getProjectVehicleId()
  return state.projectInventoryId
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Career module loaded")
end

local function onCareerActive(enabled)
  if not enabled then
    return
  end

  log("I", logTag, "Initializing MySummer Career...")

  loadState()

  log("I", logTag, "MySummer Career initialized - Phase: " .. state.currentPhase .. ", Level: " .. state.reputation.level)
end

-- ============================================================================
-- COMPUTER INTEGRATION
-- ============================================================================

local function onComputerAddFunctions(menuData, computerFunctions)
  if menuData and menuData.computerFacility and menuData.computerFacility.garageId then
    computerFunctions.general.mysummerCareer = {
      id = "mysummerCareer",
      label = "Career Progress",
      callback = function()
        log("I", logTag, "Career Progress callback triggered, navigating to mysummer-career")
        if guihooks then
          guihooks.trigger("ChangeState", { state = "mysummer-career" })
        end
      end,
      order = 14
    }
  end
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================

local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Process pending AI configurations
  if #state.pendingAIConfigs > 0 then
    local stillPending = {}
    for _, pending in ipairs(state.pendingAIConfigs) do
      pending.delay = pending.delay - dtReal
      if pending.delay <= 0 then
        -- Configure AI now
        local veh = be:getObjectByID(pending.vehId)
        if veh then
          veh:queueLuaCommand("ai.setMode('manual')")
          veh:queueLuaCommand("ai.setAvoidCars('on')")
          veh:queueLuaCommand("ai.setSpeedMode('off')")
          veh:queueLuaCommand("ai.setAggression(" .. pending.config.aggression .. ")")

          if pending.config.aiPath then
            local pathStr = serialize(pending.config.aiPath)
            veh:queueLuaCommand("ai.setPath(" .. pathStr .. ")")
          end

          log("I", logTag, "AI opponent configured: " .. pending.vehId)
        end
      else
        table.insert(stillPending, pending)
      end
    end
    state.pendingAIConfigs = stillPending
  end
end

-- ============================================================================
-- RLS RACE COMPLETION DETECTION (via XP rewards)
-- ============================================================================

-- Race types that give XP when completing RLS races
local raceXPTypes = {
  rally = true,
  drift = true,
  motorsport = true,
  offroad = true,
  drag = true,
}

-- Track recently awarded reputation to avoid duplicates
local recentRaceRewards = {}

-- Listen for player attribute changes (XP from RLS races)
local function onPlayerAttributesChanged(change, reason)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Check if this is a race reward (has gameplay/reward/mission tags or race type XP)
  local isRaceReward = false
  local raceType = nil
  local raceLabel = reason and reason.label or ""

  -- Check for race type XP in the change
  for attrType, _ in pairs(change) do
    if raceXPTypes[attrType] then
      isRaceReward = true
      raceType = attrType
      break
    end
  end

  if not isRaceReward then
    return
  end

  -- Avoid duplicate rewards (same label within 5 seconds)
  local now = os.time()
  if recentRaceRewards[raceLabel] and (now - recentRaceRewards[raceLabel]) < 5 then
    log("I", logTag, "Skipping duplicate race reward: " .. raceLabel)
    return
  end
  recentRaceRewards[raceLabel] = now

  -- Clean up old entries
  for label, time in pairs(recentRaceRewards) do
    if (now - time) > 60 then
      recentRaceRewards[label] = nil
    end
  end

  log("I", logTag, "Detected RLS race completion via XP: " .. raceLabel .. " (type: " .. tostring(raceType) .. ")")

  -- Extract race name from label (format: "Race Label - Time: XX:XX" or "Race Label - New Best Time!")
  local raceName = raceLabel:match("^([^%-]+)") or raceLabel
  raceName = raceName:gsub("%s+$", "")  -- Trim trailing spaces

  -- Find matching race in our mapping
  local matchedRace = nil
  local matchedReward = 0

  for rlsName, raceData in pairs(rlsRaceMapping) do
    if raceData.label == raceName then
      matchedRace = rlsName
      matchedReward = raceData.reputationReward
      break
    end
  end

  -- If not found by label, try to match by type
  if not matchedRace and raceType then
    -- Give a generic reward based on type
    local typeRewards = {
      rally = 200,
      drift = 200,
      motorsport = 250,
      offroad = 150,
      drag = 100,
    }
    matchedReward = typeRewards[raceType] or 150
    log("I", logTag, "Using generic reward for race type: " .. raceType)
  end

  if matchedReward > 0 then
    -- Check for new best time bonus
    local isNewBest = raceLabel:find("New Best") ~= nil
    if isNewBest then
      matchedReward = math.floor(matchedReward * 1.25)
    end

    addReputationPoints(matchedReward, "Carrera completada: " .. raceName)

    -- Show notification
    if ui_message then
      ui_message(string.format("+%d Reputación - %s", matchedReward, raceName), 4, "Career", "success")
    end

    -- Check if this race counts toward phase progress
    if matchedRace and state.currentPhase > 0 then
      local phaseRaceId, _ = findMappedPhaseRace(matchedRace)
      if phaseRaceId then
        log("I", logTag, "Race maps to phase race: " .. phaseRaceId .. " - counting as WIN")

        -- Treat completion as a win for phase progress
        local eventData = {
          eventType = "race",
          raceId = phaseRaceId,
          position = 1,  -- Completed = win (RLS races are time trials, completion = success)
          time = nil,
        }
        onFreeroamEventCompleted(eventData)
      end
    end
  end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- Lifecycle callbacks
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSetupInventoryFinished = onSetupInventoryFinished
M.onFreeroamEventCompleted = onFreeroamEventCompleted
M.onComputerAddFunctions = onComputerAddFunctions
M.onBeamNGTrigger = onBeamNGTrigger  -- Listen for custom MySummer race triggers
M.onPlayerAttributesChanged = onPlayerAttributesChanged  -- Listen for RLS race XP rewards
M.onUpdate = onUpdate  -- Process pending AI configs and timers

-- Career data API
M.getCareerData = getCareerData
M.getReputation = getReputation
M.getProjectVehicleId = getProjectVehicleId
M.addReputationPoints = addReputationPoints
M.startPhase = startPhase
M.navigateToRace = navigateToRace
M.getAvailableRaces = getAvailableRaces

-- Custom race API
M.startCustomRace = startCustomRace
M.cancelCustomRace = cancelCustomRace
M.endCustomRace = endCustomRace

return M
