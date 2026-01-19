-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.moduleName = "career_modules_mysummerDeepWeb"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerCore",
  "career_modules_playerAttributes",
  "career_branches",
}

local logTag = "mysummerDeepWeb"

-- ============================================================================
-- CONVERSATION COOLDOWN SYSTEM
-- ============================================================================

-- Cooldown settings (in seconds)
local COOLDOWN_BASE = 300  -- 5 minutes base cooldown
local COOLDOWN_PER_LEVEL = 60  -- Reduced by 1 minute per trust level
local COOLDOWN_MIN = 60  -- Minimum 1 minute cooldown

-- Track last conversation time per contact
local conversationCooldowns = {}  -- { [contactId] = timestamp }

-- Get cooldown duration for a contact based on trust level
local function getCooldownDuration(contactId)
  local level = 1  -- Will be replaced with actual level check later
  if career_modules_playerAttributes then
    local attKey = "mysummer-" .. contactId
    local xp = career_modules_playerAttributes.getAttributeValue(attKey) or 0
    -- Calculate level from XP (0-49=1, 50-149=2, 150-349=3, 350-599=4, 600+=5)
    if xp >= 600 then level = 5
    elseif xp >= 350 then level = 4
    elseif xp >= 150 then level = 3
    elseif xp >= 50 then level = 2
    else level = 1
    end
  end

  local cooldown = COOLDOWN_BASE - ((level - 1) * COOLDOWN_PER_LEVEL)
  return math.max(COOLDOWN_MIN, cooldown)
end

-- Check if a contact is on cooldown
local function isContactOnCooldown(contactId)
  local lastTime = conversationCooldowns[contactId]
  if not lastTime then
    return false, 0
  end

  local now = os.time()
  local cooldownDuration = getCooldownDuration(contactId)
  local elapsed = now - lastTime

  if elapsed < cooldownDuration then
    return true, cooldownDuration - elapsed
  end

  return false, 0
end

-- Set cooldown for a contact (call after conversation ends)
local function setContactCooldown(contactId)
  conversationCooldowns[contactId] = os.time()
end

-- Clear cooldown for a contact (for debugging)
local function clearContactCooldown(contactId)
  conversationCooldowns[contactId] = nil
end

-- ============================================================================
-- CONVERSATION DATA LOADING FROM JSON FILES
-- ============================================================================

local contactsJsonPath = "lua/ge/extensions/career/modules/deepweb_contacts/"
local loadedContactData = {}

-- Load a contact's conversation data from JSON file
local function loadContactFromJson(contactId)
  if loadedContactData[contactId] then
    return loadedContactData[contactId]
  end

  local filePath = contactsJsonPath .. contactId .. ".json"
  local data = jsonReadFile(filePath)

  if data then
    loadedContactData[contactId] = data
    log("I", logTag, "Loaded contact data from JSON: " .. contactId)
    return data
  else
    log("E", logTag, "Failed to load contact JSON: " .. filePath)
    return nil
  end
end

-- Get question pools for a contact
local function getContactQuestionPools(contactId)
  local data = loadContactFromJson(contactId)
  if data and data.questionPools then
    return data.questionPools
  end
  return nil
end

-- Get traits for a contact
local function getContactTraits(contactId)
  local data = loadContactFromJson(contactId)
  if data and data.traits then
    return data.traits
  end
  return nil
end

-- Get confrontations for a contact
local function getContactConfrontations(contactId)
  local data = loadContactFromJson(contactId)
  if data and data.confrontations then
    return data.confrontations
  end
  return nil
end

-- Get relationships for a contact
local function getContactRelationships(contactId)
  local data = loadContactFromJson(contactId)
  if data then
    return {
      rivals = data.rivals or {},
      allies = data.allies or {},
      neutral = data.neutral or {},
    }
  end
  return { rivals = {}, allies = {}, neutral = {} }
end

-- Check if a contact is the AI pilot (always unlocked)
local function isAIPilotContact(contactId)
  local data = loadContactFromJson(contactId)
  return data and data.isAIPilot == true
end

-- Check if a contact should always be unlocked (AI pilot or other special contacts)
local function isAlwaysUnlocked(contactId)
  local data = loadContactFromJson(contactId)
  return data and data.alwaysUnlocked == true
end

-- ============================================================================
-- CONFRONTATION SYSTEM
-- ============================================================================

-- Check if a confrontation should trigger based on its conditions
local function shouldTriggerConfrontation(confrontation, contactId, memory, level)
  -- Check minimum trust level
  if confrontation.minTrust and level < confrontation.minTrust then
    return false
  end

  -- Check trigger type
  if confrontation.trigger == "memory" then
    -- Memory-based confrontation: requires specific memory flag
    if confrontation.condition and not memory[confrontation.condition] then
      return false
    end
  end

  -- Check random chance
  if confrontation.chance then
    local roll = math.random()
    if roll > confrontation.chance then
      return false
    end
  end

  return true
end

-- Select a confrontation for a contact if conditions are met
local function selectConfrontation(contactId, memory, level)
  local confrontations = getContactConfrontations(contactId)
  if not confrontations or #confrontations == 0 then
    return nil
  end

  -- Filter confrontations that pass their conditions
  local eligible = {}
  for _, conf in ipairs(confrontations) do
    if shouldTriggerConfrontation(conf, contactId, memory, level) then
      table.insert(eligible, conf)
    end
  end

  -- Pick a random eligible confrontation
  if #eligible > 0 then
    return eligible[math.random(#eligible)]
  end

  return nil
end

-- Calculate points for a response using trait-based scoring
local function calculateTraitPoints(response, contactTraits)
  if not response.traits or not contactTraits or not contactTraits.scoring then
    -- Fall back to simple points if no traits
    return response.points or 0
  end

  local total = 0
  for _, trait in ipairs(response.traits) do
    local score = contactTraits.scoring[trait]
    if score then
      total = total + score
    end
  end

  -- If response has base points, add them too (allows hybrid scoring)
  if response.points then
    total = total + response.points
  end

  return total
end

-- ============================================================================
-- LEGACY FALLBACK QUESTION POOLS (minimal, used only if JSON fails)
-- ============================================================================

-- Minimal fallback pools (used only if JSON loading fails)
local fallbackQuestionPools = {
  unknown = {
    { text = "Who sent you?", best = "b", responses = {
      { id = "a", text = "Found you online", points = -5 },
      { id = "b", text = "Someone who trusts you", points = 10 },
      { id = "c", text = "Does it matter?", points = 0 },
    }},
  },
  acquaintance = {
    { text = "What do you know about cars?", best = "a", responses = {
      { id = "a", text = "I've been building for years", points = 15 },
      { id = "b", text = "Enough to get by", points = 5 },
      { id = "c", text = "Not much", points = -5 },
    }},
  },
  associate = {
    { text = "Can I trust you?", best = "b", responses = {
      { id = "a", text = "Yes", points = 5 },
      { id = "b", text = "Actions speak louder than words", points = 15 },
      { id = "c", text = "I don't know", points = 0 },
    }},
  },
  trusted = {
    { text = "What are your goals?", best = "a", responses = {
      { id = "a", text = "Build something great", points = 15 },
      { id = "b", text = "Make money", points = 5 },
      { id = "c", text = "Just having fun", points = 10 },
    }},
  },
  innerCircle = {
    { text = "Welcome to the inner circle.", best = "a", responses = {
      { id = "a", text = "It's an honor", points = 20 },
      { id = "b", text = "Thanks", points = 10 },
      { id = "c", text = "About time", points = 5 },
    }},
  },
  intro = {
    { text = "State your business.", best = "a", responses = {
      { id = "a", text = "Looking for parts", points = 10 },
      { id = "b", text = "Just browsing", points = 0 },
      { id = "c", text = "None of your business", points = -10 },
    }},
  },
  questions = {
    { text = "Why should I deal with you?", best = "b", responses = {
      { id = "a", text = "I have money", points = 5 },
      { id = "b", text = "I'm serious about my build", points = 15 },
      { id = "c", text = "Why not?", points = 0 },
    }},
  },
  final = {
    { text = "Last question - are you in?", best = "a", responses = {
      { id = "a", text = "Absolutely", points = 20 },
      { id = "b", text = "I think so", points = 10 },
      { id = "c", text = "Maybe", points = 0 },
    }},
  },
}
-- ============================================================================
-- VENDOR DEFINITIONS
-- ============================================================================

local vendorDefinitions = {
  ghost = {
    id = "ghost",
    name = "Ghost",
    personality = "paranoid",
    description = "Former racer, extremely careful. One wrong move and you're out.",
    trustThreshold = 50,
    partsInventory = {
      "etki_engine_2.4",
      "etki_turbo_stage2",
      "etki_differential_R_race",
      "etki_coilover_R_race",
      "etki_brake_F_race",
      "etki_brake_R_race",
    },
    -- questionPools loaded dynamically from JSON
  },

  techie = {
    id = "techie",
    name = "Techie",
    personality = "technical",
    description = "Knows every spec, every number. Talk tech or don't talk at all.",
    trustThreshold = 60,
    partsInventory = {
      "etki_oilpan_race",
      "etki_radiator_race",
      "etki_steeringbox_race",
      "etki_transmission_6M_race",
      "etki_swaybar_F_race",
      "etki_swaybar_R_race",
    },
    -- questionPools loaded dynamically from JSON
  },

  muscle = {
    id = "muscle",
    name = "Muscle",
    personality = "oldschool",
    description = "Old-school performance enthusiast. No computers, no electronics, just raw power.",
    trustThreshold = 45,
    partsInventory = {
      "etki_engine_internals_heavy",
      "etki_exhaust_wide",
      "etki_strut_F_race",
      "etki_strut_bar",
      "brakepad_F_semi_race",
      "brakepad_R_semi_race",
    },
    -- questionPools loaded dynamically from JSON
  },

  import = {
    id = "import",
    name = "Import",
    personality = "jdm_specialist",
    description = "JDM specialist. If it's not Japanese tuner culture, not interested.",
    trustThreshold = 55,
    partsInventory = {
      "etki_bumper_F_kit",
      "etki_bumper_R_kit",
      "etki_fenderflare_FL_kit",
      "etki_fenderflare_FR_kit",
      "etki_fenderflare_R_kit",
      "etki_spoiler_kit",
      "etki_sideskirt_kit",
    },
    -- questionPools loaded dynamically from JSON
  },

  shadow = {
    id = "shadow",
    name = "Shadow",
    personality = "black_market",
    description = "Black market connections. Ask no questions, tell no lies.",
    trustThreshold = 70,
    partsInventory = {
      "etki_rollcage",
      "etki_hood_vents",
      "etki_chinspoiler_kit",
      "etki_window_spoiler",
      "etki_trim_kit",
    },
    -- questionPools loaded dynamically from JSON
  },

  -- AI Pilot Contact - always unlocked for testing AI conversations
  oracle = {
    id = "oracle",
    name = "Oracle",
    personality = "enigmatic",
    description = "A mysterious digital entity that tests your thinking and adapts to your responses.",
    trustThreshold = 0,  -- No threshold needed - always available
    isAIPilot = true,
    partsInventory = {},  -- Oracle doesn't sell parts - it's for AI conversation testing
    -- questionPools loaded dynamically from JSON
  },
}

-- ============================================================================
-- CONVERSATION PHASES BY TRUST LEVEL
-- ============================================================================

-- Phase definitions based on trust level
-- Level 1 (0-49 XP): Unknown - basic interrogation
-- Level 2 (50-149 XP): Acquaintance - testing knowledge
-- Level 3 (150-349 XP): Associate - business talk
-- Level 4 (350-599 XP): Trusted - personal stories
-- Level 5 (600+ XP): Inner Circle - secrets and plans

local conversationPhases = {
  unknown = { minLevel = 1, maxLevel = 1, questionCount = 3, style = "interrogation" },
  acquaintance = { minLevel = 2, maxLevel = 2, questionCount = 4, style = "testing" },
  associate = { minLevel = 3, maxLevel = 3, questionCount = 5, style = "business" },
  trusted = { minLevel = 4, maxLevel = 4, questionCount = 4, style = "personal" },
  innerCircle = { minLevel = 5, maxLevel = 5, questionCount = 3, style = "secrets" },
}

-- Map level number to phase name
local function getLevelPhase(level)
  if level >= 5 then return "innerCircle"
  elseif level >= 4 then return "trusted"
  elseif level >= 3 then return "associate"
  elseif level >= 2 then return "acquaintance"
  else return "unknown"
  end
end

-- Phase-specific intro messages
local phaseIntroMessages = {
  ghost = {
    unknown = "Who the hell are you? How did you get this number?",
    acquaintance = "Oh, it's you again. What do you want?",
    associate = "Alright, you've proven yourself. Talk to me.",
    trusted = "Good to see you. Things have been... interesting lately.",
    innerCircle = "My friend. I've been meaning to tell you something important.",
  },
  techie = {
    unknown = "State your technical credentials. Now.",
    acquaintance = "Back again? Let's see if you've learned anything.",
    associate = "I've been working on something interesting. Want to hear about it?",
    trusted = "You know, you're one of the few who actually understands this stuff.",
    innerCircle = "I've cracked something big. You're the only one I'm telling.",
  },
  muscle = {
    unknown = "Who sent you? Talk fast, I'm busy.",
    acquaintance = "You again. Still trying to prove yourself?",
    associate = "Kid, you're starting to remind me of someone I used to know.",
    trusted = "Pull up a chair. Let me tell you about the old days.",
    innerCircle = "There's something I've never told anyone. But you've earned it.",
  },
  import = {
    unknown = "This scene isn't for tourists. What do you want?",
    acquaintance = "Saw your build the other day. Not bad. Not good either.",
    associate = "You're starting to get it. The culture, I mean.",
    trusted = "You know what makes this scene special? The people. Like you.",
    innerCircle = "I'm planning something big. A meet like the old days. You're invited.",
  },
  shadow = {
    unknown = "...",
    acquaintance = "You're still alive. That's... unexpected.",
    associate = "You've proven you can keep your mouth shut. Good.",
    trusted = "In this business, trust is everything. You've earned mine.",
    innerCircle = "There are things in motion. Big things. You should know.",
  },
}

-- ============================================================================
-- CONTACT UNLOCK CHAIN
-- ============================================================================

-- Chain of contact introductions (Ghost -> Techie -> Muscle -> Import -> Shadow)
local contactChain = {
  ghost = "techie",   -- Ghost introduces Techie at level 3
  techie = "muscle",  -- Techie introduces Muscle at level 3
  muscle = "import",  -- Muscle introduces Import at level 3
  import = "shadow",  -- Import introduces Shadow at level 3
  shadow = nil,       -- Shadow is the end of the chain
}

-- Which contact unlocks each contact (reverse lookup)
local contactUnlockedBy = {
  ghost = nil,       -- Ghost is available from the start
  techie = "ghost",  -- Techie is unlocked by Ghost
  muscle = "techie", -- Muscle is unlocked by Techie
  import = "muscle", -- Import is unlocked by Muscle
  shadow = "import", -- Shadow is unlocked by Import
}

-- Messages when a contact introduces another
local introductionMessages = {
  ghost = "You've proven yourself. There's someone you should meet - goes by 'Techie'. Knows more about ECUs than anyone. Tell him Ghost sent you.",
  techie = "Your knowledge is solid. I know a guy, old-school guy. They call him 'Muscle'. He's got connections for serious hardware. Use my name.",
  muscle = "Kid, you've got potential. There's this JDM specialist, 'Import'. Tell him I vouched for you. He's got the good stuff.",
  import = "You're deep in the culture now. Time you met 'Shadow'. Black market connections. Careful though - he doesn't trust easy. I'll put in a word.",
}

-- Level thresholds for introductions (XP values from info.json)
local INTRODUCTION_LEVEL = 3  -- Associate level (150 XP)
local INTRODUCTION_XP_THRESHOLD = 150

-- ============================================================================
-- CONTACT RACE SYSTEM
-- ============================================================================

-- Forward declarations for functions used by race system and heat system
local getContactXP
local getContactLevel
local isContactAvailable
local canClearHeatWithShadow

-- Vehicles used by each contact for races
local contactVehicles = {
  ghost = { model = "sunburst2", config = "sport_RS_M" },     -- Ex-racer, fast hatch
  techie = { model = "covet", config = "base" },              -- Compact tuner
  muscle = { model = "moonhawk", config = "base" },           -- Old-school muscle
  import = { model = "vivace", config = "base" },             -- JDM style
  shadow = { model = "fullsize", config = "base" },           -- Sleeper sedan
}

-- Race challenge messages
local raceChallengeMessages = {
  ghost = "Think you're fast? Let's see what you've got. First one to the destination wins.",
  techie = "I've been tuning my ECU all week. Want to test it against your build?",
  muscle = "Back in my day, we settled things on the road. You game?",
  import = "Touge style - first to the bottom of the mountain. No excuses.",
  shadow = "Midnight run. No lights, no rules. You in?",
}

-- Race result messages
local raceResultMessages = {
  win = {
    ghost = "Damn. You're faster than I thought. Respect.",
    techie = "Your setup must be dialed in perfectly. Impressive.",
    muscle = "Kid, you've got some real talent. Reminds me of myself.",
    import = "Clean run. You understand the spirit of racing.",
    shadow = "... You're good. Very good.",
  },
  lose = {
    ghost = "Not bad, but you need more seat time. Keep practicing.",
    techie = "Close, but my data doesn't lie. Better luck next time.",
    muscle = "Experience beats youth, kid. Come back when you're ready.",
    import = "The mountain doesn't forgive mistakes. Learn from this.",
    shadow = "Slow. But at least you showed up.",
  },
}

-- XP rewards for races
local RACE_WIN_XP = 25
local RACE_LOSE_XP = 7

-- Race state
local activeContactRace = nil  -- { contactId, contactVehId, destination, startTime, checkInterval }
local previousTrafficAmount = nil  -- Store traffic amount before race

-- Race cooldowns (prevent spam)
local raceCooldowns = {}  -- { [contactId] = lastRaceTime }
local RACE_COOLDOWN = 300  -- 5 minutes between races with same contact
local RACE_TRAFFIC_AMOUNT = 3  -- Reduced traffic during race

-- Pickup locations for race destinations (reuse from mysummerParts)
local raceDestinations = nil

-- Forward declarations for functions used before definition
local finishContactRace
local addContactXP
local cancelContactRace

-- Pending AI setup (processed in onUpdate)
local pendingAISetup = nil  -- { vehId, destination, timeLeft }

-- Hardcoded race destinations for West Coast USA (fallback when facilities fail)
local westCoastDestinations = {
  { name = "Downtown Parking", pos = vec3(-778, 241, 118) },
  { name = "Industrial Zone", pos = vec3(-651, 639, 115) },
  { name = "Highway Rest Stop", pos = vec3(340, -580, 140) },
  { name = "Coastal Overlook", pos = vec3(-220, -980, 95) },
  { name = "Mountain Pass", pos = vec3(580, 450, 185) },
  { name = "Port District", pos = vec3(-890, 150, 115) },
  { name = "Racetrack Entrance", pos = vec3(-320, 850, 112) },
  { name = "Mall Parking", pos = vec3(-580, 380, 116) },
  { name = "Gas Station North", pos = vec3(120, 720, 145) },
  { name = "Warehouse District", pos = vec3(-720, 520, 115) },
}

-- Initialize race destinations from road network
local function initRaceDestinations()
  if raceDestinations then return raceDestinations end

  raceDestinations = {}

  -- Get road nodes from the map
  local mapData = map.getMap()
  if mapData and mapData.nodes then
    -- Collect all road nodes
    local allNodes = {}
    for nodeId, node in pairs(mapData.nodes) do
      if node.pos then
        table.insert(allNodes, {
          id = nodeId,
          pos = vec3(node.pos),
          radius = node.radius or 5,
        })
      end
    end

    -- Pick random nodes as destinations (spread out across the map)
    if #allNodes > 0 then
      -- Shuffle and pick up to 20 destinations
      local numDestinations = math.min(20, #allNodes)
      local step = math.floor(#allNodes / numDestinations)

      for i = 1, numDestinations do
        local idx = ((i - 1) * step) + math.random(1, math.max(1, step))
        idx = math.min(idx, #allNodes)
        local node = allNodes[idx]
        if node then
          table.insert(raceDestinations, {
            name = "Road Point " .. i,
            pos = node.pos,
          })
        end
      end
    end

    log("I", logTag, string.format("Initialized %d race destinations from %d road nodes", #raceDestinations, #allNodes))
  end

  -- Fallback if no road nodes found
  if #raceDestinations == 0 then
    log("W", logTag, "No road nodes found, race destinations unavailable")
  end

  return raceDestinations
end

-- Reset destinations when map changes
local function onClientStartMission()
  raceDestinations = nil
  log("D", logTag, "Race destinations reset for new map")
end

-- Check if player can challenge a contact to a race
local function canChallengeToRace(contactId)
  -- Must be available (unlocked through chain)
  if not isContactAvailable(contactId) then
    return false, "Contact not available"
  end

  -- Must be at least level 2 (Acquaintance)
  local level = getContactLevel(contactId)
  if level < 2 then
    return false, "Build more trust first (need level 2)"
  end

  -- Check cooldown
  local now = os.time()
  if raceCooldowns[contactId] and (now - raceCooldowns[contactId]) < RACE_COOLDOWN then
    local remaining = RACE_COOLDOWN - (now - raceCooldowns[contactId])
    return false, string.format("Wait %d minutes before racing again", math.ceil(remaining / 60))
  end

  -- Can't race if already in a race
  if activeContactRace then
    return false, "Already in a race"
  end

  return true, nil
end

-- Helper function to find a valid spawn position near player vehicle
-- Tries to place opponent ~4m to the side (right, left, behind) in same orientation as player
local function findSafeSpawnPosition(playerVeh)
  local playerPos = playerVeh:getPosition()
  local playerDir = playerVeh:getDirectionVector():normalized()
  local rightVector = playerDir:cross(vec3(0, 0, 1)):normalized()
  local leftVector = -rightVector
  local backVector = -playerDir

  -- Distance to place opponent (car width + small gap)
  local sideDistance = 4  -- meters to the side
  local backDistance = 6  -- meters behind

  -- Try positions: right, left, behind
  local candidates = {
    { offset = rightVector * sideDistance, name = "right" },
    { offset = leftVector * sideDistance, name = "left" },
    { offset = backVector * backDistance, name = "behind" },
    { offset = backVector * backDistance + rightVector * sideDistance, name = "back-right" },
    { offset = backVector * backDistance + leftVector * sideDistance, name = "back-left" },
  }

  for _, candidate in ipairs(candidates) do
    local testPos = playerPos + candidate.offset
    local probePos = vec3(testPos.x, testPos.y, playerPos.z + 20)
    local groundZ = be:getSurfaceHeightBelow(probePos)

    if groundZ and groundZ > -1000 and groundZ < 10000 then
      local heightDiff = math.abs(groundZ - playerPos.z)
      if heightDiff < 2 then  -- Max 2m height difference (same road level)
        local finalPos = vec3(testPos.x, testPos.y, groundZ + 0.5)
        log("D", logTag, string.format("Found safe spawn at %s: %s (heightDiff=%.2f)",
          candidate.name, tostring(finalPos), heightDiff))
        return finalPos
      end
    end
  end

  -- Fallback: directly behind player
  log("W", logTag, "No safe spawn found, using fallback behind player")
  return playerPos + backVector * backDistance
end

-- Helper to complete race setup after player vehicle is ready
local function completeRaceSetup(contactId, vehicleData, destination, startPos, startRot, playerVehId)
  -- Get player vehicle for direction reference
  local playerVeh = be:getObjectByID(playerVehId)
  if not playerVeh then
    log("E", logTag, "Player vehicle not found")
    return
  end

  -- Get player's current rotation (opponent faces same direction as player)
  local playerDir = playerVeh:getDirectionVector():normalized()
  local spawnRot = quatFromDir(playerDir)

  -- Find a safe spawn position for the contact vehicle (beside player)
  local spawnPos = findSafeSpawnPosition(playerVeh)

  -- Spawn the contact's vehicle (as AI, not player controlled)
  local options = {
    config = vehicleData.config,
    pos = spawnPos,
    rot = spawnRot,  -- Same direction as player
    autoEnterVehicle = false,  -- Don't automatically enter this vehicle
  }

  log("I", logTag, string.format("Spawning contact vehicle: %s/%s at %s",
    vehicleData.model, vehicleData.config, tostring(spawnPos)))

  local contactVeh = core_vehicles.spawnNewVehicle(vehicleData.model, options)
  if not contactVeh then
    log("E", logTag, "Failed to spawn contact vehicle")
    return
  end

  -- Get the numeric vehicle ID
  local contactVehId = contactVeh:getID()
  log("I", logTag, string.format("Contact vehicle spawned with ID: %d", contactVehId))

  -- Re-enter the player's vehicle to ensure we're not in the contact's vehicle
  local playerVeh = be:getPlayerVehicle(0)
  if playerVeh and playerVeh:getID() ~= contactVehId then
    be:enterVehicle(0, playerVeh)
  end

  -- Queue AI setup to be processed in onUpdate (vehicle needs time to initialize)
  pendingAISetup = {
    vehId = contactVehId,
    destination = destination,
    timeLeft = 1.0,  -- Give more time for vehicle to stabilize
  }

  -- Reduce traffic during race
  if gameplay_traffic then
    previousTrafficAmount = gameplay_traffic.getNumOfTraffic()
    gameplay_traffic.setActiveAmount(RACE_TRAFFIC_AMOUNT)
    log("I", logTag, string.format("Reduced traffic from %d to %d for race", previousTrafficAmount or 0, RACE_TRAFFIC_AMOUNT))
  end

  -- Set waypoint for player
  if core_groundMarkers then
    core_groundMarkers.setPath(destination.pos, { clearPathOnReachingTarget = true })
  end

  -- Store race state
  activeContactRace = {
    contactId = contactId,
    contactVehId = contactVehId,
    destination = destination,
    startTime = os.time(),
    checkInterval = 0,
    playerFinished = false,
    contactFinished = false,
  }

  -- Set cooldown
  raceCooldowns[contactId] = os.time()

  log("I", logTag, string.format("Started race against %s to %s", contactId, destination.name))

  -- Notify UI
  guihooks.trigger("mysummerContactRaceStarted", {
    success = true,
    contactId = contactId,
    destination = destination.name,
    message = raceChallengeMessages[contactId] or "Let's race!",
  })
end

-- Start a race against a contact
local function startContactRace(contactId)
  log("I", logTag, "startContactRace called with contactId: " .. tostring(contactId))
  local canRace, reason = canChallengeToRace(contactId)
  if not canRace then
    return { success = false, message = reason }
  end

  local vehicleData = contactVehicles[contactId]
  if not vehicleData then
    return { success = false, message = "Contact doesn't have a vehicle configured" }
  end

  -- Initialize destinations if needed
  initRaceDestinations()
  if #raceDestinations == 0 then
    return { success = false, message = "No race destinations available" }
  end

  -- Get player's current vehicle and position - race starts from HERE
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then
    return { success = false, message = "No vehicle - get in a car first!" }
  end

  local startPos = playerVeh:getPosition()
  local playerDir = playerVeh:getDirectionVector()

  log("I", logTag, string.format("Race starting from player position: %s", tostring(startPos)))

  -- Pick a random destination that's far enough away (at least 200m)
  local validDestinations = {}
  for _, dest in ipairs(raceDestinations) do
    local dist = startPos:distance(dest.pos)
    if dist > 200 then
      table.insert(validDestinations, { dest = dest, dist = dist })
    end
  end

  -- If no destinations are far enough, use all of them
  if #validDestinations == 0 then
    for _, dest in ipairs(raceDestinations) do
      table.insert(validDestinations, { dest = dest, dist = startPos:distance(dest.pos) })
    end
  end

  if #validDestinations == 0 then
    return { success = false, message = "No race destinations available" }
  end

  -- Pick random destination from valid ones
  local destIdx = math.random(1, #validDestinations)
  local destination = validDestinations[destIdx].dest

  log("I", logTag, string.format("Race destination: %s (%.0fm away)", destination.name, validDestinations[destIdx].dist))

  -- Calculate rotation to face destination
  local dirToDestination = (destination.pos - startPos):normalized()
  local startRot = quatFromDir(dirToDestination)

  -- Player is already in their vehicle at the current position
  -- Just spawn the contact vehicle and start the race
  local playerVehId = playerVeh:getID()
  log("I", logTag, string.format("Player already in vehicle ID %d, starting race setup", playerVehId))

  -- Complete the race setup (spawn contact vehicle, set destination, etc.)
  completeRaceSetup(contactId, vehicleData, destination, startPos, startRot, playerVehId)

  return {
    success = true,
    contactId = contactId,
    destination = destination.name,
    message = string.format("Race to %s!", destination.name),
  }
end

-- Check race progress (called from onUpdate)
local function updateContactRace(dt)
  if not activeContactRace then return end

  activeContactRace.checkInterval = (activeContactRace.checkInterval or 0) + dt
  if activeContactRace.checkInterval < 0.5 then return end  -- Check every 0.5 seconds
  activeContactRace.checkInterval = 0

  local destPos = activeContactRace.destination.pos
  local finishRadius = 15  -- meters

  -- Check player distance
  local playerVeh = be:getPlayerVehicle(0)
  if playerVeh then
    local playerPos = playerVeh:getPosition()
    local playerDist = playerPos:distance(destPos)
    if playerDist < finishRadius and not activeContactRace.playerFinished then
      activeContactRace.playerFinished = true
      activeContactRace.playerFinishTime = os.time()
      log("I", logTag, "Player finished the race!")
    end
  end

  -- Check contact vehicle distance
  local contactVeh = be:getObjectByID(activeContactRace.contactVehId)
  if contactVeh then
    local contactPos = contactVeh:getPosition()
    local contactDist = contactPos:distance(destPos)
    if contactDist < finishRadius and not activeContactRace.contactFinished then
      activeContactRace.contactFinished = true
      activeContactRace.contactFinishTime = os.time()
      log("I", logTag, "Contact finished the race!")
    end
  end

  -- Check if race is over
  if activeContactRace.playerFinished or activeContactRace.contactFinished then
    -- Wait a moment for both to potentially finish
    if not activeContactRace.graceStarted then
      activeContactRace.graceStarted = true
      activeContactRace.graceTime = 0
    end

    activeContactRace.graceTime = activeContactRace.graceTime + 0.5
    if activeContactRace.graceTime >= 3 or (activeContactRace.playerFinished and activeContactRace.contactFinished) then
      finishContactRace()
      return  -- Race ended, don't continue processing
    end
  end

  -- Timeout after 10 minutes
  if not activeContactRace or (os.time() - activeContactRace.startTime) > 600 then
    log("W", logTag, "Race timed out")
    cancelContactRace("Race timed out")
  end
end

-- Finish the race and award XP
finishContactRace = function()
  if not activeContactRace then return end

  local contactId = activeContactRace.contactId
  local playerWon = activeContactRace.playerFinished and
    (not activeContactRace.contactFinished or
     activeContactRace.playerFinishTime <= activeContactRace.contactFinishTime)

  -- Award XP
  local xpAmount = playerWon and RACE_WIN_XP or RACE_LOSE_XP
  addContactXP(contactId, xpAmount)

  -- Get result message
  local resultType = playerWon and "win" or "lose"
  local message = raceResultMessages[resultType][contactId] or
    (playerWon and "You win!" or "Better luck next time.")

  -- Cleanup contact vehicle
  if activeContactRace.contactVehId then
    local veh = be:getObjectByID(activeContactRace.contactVehId)
    if veh then
      veh:delete()
    end
  end

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end

  -- Restore traffic
  if gameplay_traffic and previousTrafficAmount then
    gameplay_traffic.setActiveAmount(previousTrafficAmount)
    log("I", logTag, string.format("Restored traffic to %d", previousTrafficAmount))
    previousTrafficAmount = nil
  end

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerContactRaceFinished", {
      contactId = contactId,
      playerWon = playerWon,
      xpAwarded = xpAmount,
      message = message,
    })

    guihooks.trigger("toastrMsg", {
      type = playerWon and "success" or "info",
      title = playerWon and "Race Won!" or "Race Lost",
      msg = message .. " (+" .. xpAmount .. " XP)",
    })
  end

  log("I", logTag, string.format("Race finished: %s %s (+%d XP)",
    contactId, playerWon and "PLAYER WON" or "CONTACT WON", xpAmount))

  activeContactRace = nil
end

-- Cancel an active race
cancelContactRace = function(reason)
  if not activeContactRace then return end

  -- Cleanup contact vehicle
  if activeContactRace.contactVehId then
    local veh = be:getObjectByID(activeContactRace.contactVehId)
    if veh then
      veh:delete()
    end
  end

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end

  -- Restore traffic
  if gameplay_traffic and previousTrafficAmount then
    gameplay_traffic.setActiveAmount(previousTrafficAmount)
    log("I", logTag, string.format("Restored traffic to %d", previousTrafficAmount))
    previousTrafficAmount = nil
  end

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerContactRaceCancelled", {
      reason = reason or "Race cancelled",
    })
  end

  log("I", logTag, "Race cancelled: " .. (reason or "unknown reason"))
  activeContactRace = nil
end

-- Get current race state for UI
local function getActiveRaceState()
  if not activeContactRace then return nil end

  local state = {
    contactId = activeContactRace.contactId,
    destination = activeContactRace.destination.name,
    startTime = activeContactRace.startTime,
    elapsed = os.time() - activeContactRace.startTime,
  }

  -- Calculate distances
  local destPos = activeContactRace.destination.pos

  local playerVeh = be:getPlayerVehicle(0)
  if playerVeh then
    state.playerDistance = playerVeh:getPosition():distance(destPos)
  end

  local contactVeh = be:getObjectByID(activeContactRace.contactVehId)
  if contactVeh then
    state.contactDistance = contactVeh:getPosition():distance(destPos)
  end

  return state
end

-- ============================================================================
-- NATIVE SKILLS INTEGRATION
-- ============================================================================

-- Add XP to a contact using native playerAttributes
addContactXP = function(contactId, amount)
  if not career_modules_playerAttributes then
    log("W", logTag, "playerAttributes module not available")
    return
  end

  local attKey = "mysummer-" .. contactId
  log("D", logTag, string.format("Adding %d XP to attribute key: %s", amount, attKey))

  career_modules_playerAttributes.addAttributes(
    { [attKey] = amount },
    { label = "DeepWeb Contact: " .. contactId, tags = {"gameplay", "mysummer"} }
  )

  -- Debug: verify the value was added
  local newValue = career_modules_playerAttributes.getAttributeValue(attKey)
  log("I", logTag, string.format("Added %d XP to contact %s (total: %s)", amount, contactId, tostring(newValue)))
end

-- Get the current XP for a contact
-- Note: getContactXP is forward declared at the top of CONTACT RACE SYSTEM section
getContactXP = function(contactId)
  if not career_modules_playerAttributes then
    return 0
  end

  local attKey = "mysummer-" .. contactId
  return career_modules_playerAttributes.getAttributeValue(attKey) or 0
end

-- Get the current level for a contact (1-5)
-- Note: getContactLevel is forward declared at the top of CONTACT RACE SYSTEM section
getContactLevel = function(contactId)
  if not career_branches then
    return 1
  end

  local skillId = "mysummer-" .. contactId
  local totalXP = getContactXP(contactId)

  -- Debug: check if the branch exists
  local branch = career_branches.getBranchById(skillId)
  if branch then
    log("D", logTag, string.format("Branch %s found, attributeKey: %s", skillId, tostring(branch.attributeKey)))
  else
    log("W", logTag, string.format("Branch %s NOT FOUND in career_branches", skillId))
  end

  local level = career_branches.calcBranchLevelFromValue(totalXP, skillId)
  return level or 1
end

-- Check if a contact is available (unlocked)
-- Note: isContactAvailable is forward declared at the top of CONTACT RACE SYSTEM section
isContactAvailable = function(contactId)
  -- Ghost is always available
  if contactId == "ghost" then
    return true
  end

  -- Oracle (AI pilot) is always available for testing
  if isAlwaysUnlocked(contactId) then
    return true
  end

  -- Check if the unlocking contact has reached level 3
  local unlockedBy = contactUnlockedBy[contactId]
  if not unlockedBy then
    return false
  end

  local unlockerLevel = getContactLevel(unlockedBy)
  return unlockerLevel >= INTRODUCTION_LEVEL
end

-- Check if a contact has just been introduced (for showing introduction message)
local function checkForIntroduction(contactId)
  local level = getContactLevel(contactId)
  local nextContact = contactChain[contactId]

  if level >= INTRODUCTION_LEVEL and nextContact then
    -- Check if next contact is now available
    if isContactAvailable(nextContact) then
      return nextContact
    end
  end

  return nil
end

-- ============================================================================
-- ARREST PENALTY SYSTEM
-- ============================================================================

-- Called when the player is arrested by police
local function onPlayerArrested()
  log("I", logTag, "Player arrested - applying trust penalty to all contacts")

  local contacts = {"ghost", "techie", "muscle", "import", "shadow"}
  for _, contactId in ipairs(contacts) do
    -- Only penalize contacts that are available
    if isContactAvailable(contactId) then
      addContactXP(contactId, -30)
    end
  end

  -- Notify the player
  if guihooks then
    guihooks.trigger("toastrMsg", {
      type = "warning",
      title = "Trust Lost",
      msg = "Your contacts don't trust people who get caught..."
    })
  end
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  vendors = {},  -- { [vendorId] = { met, trustPoints (legacy), unlocked, blacklisted, purchaseHistory = [], usedQuestions = {}, conversationMemory = {} } }
  currentConversation = nil,  -- { vendorId, questions = [{question, responses}], currentIndex, sessionPoints, phase }
}

-- ============================================================================
-- CONVERSATION MEMORY SYSTEM
-- ============================================================================

-- Memory tags that can be stored during conversations
-- These are used to track player responses and personalize future conversations
local memoryTags = {
  -- Technical preferences
  "prefersTurbo",       -- Player prefers forced induction
  "prefersNA",          -- Player prefers naturally aspirated
  "knowsSuspension",    -- Player demonstrated suspension knowledge
  "knowsEngine",        -- Player demonstrated engine knowledge
  "knowsECU",           -- Player demonstrated ECU tuning knowledge

  -- Personal info shared
  "mentionedETKI",      -- Player mentioned working on ETK-I
  "mentionedProject",   -- Player mentioned having a project car
  "claimedExperience",  -- Player claimed to have experience
  "isHonest",           -- Player has been honest in conversations

  -- Relationship markers
  "helpedContact",      -- Player helped this contact
  "sharedInfo",         -- Player shared useful info
  "keptSecret",         -- Player kept a secret for the contact
  "failedTest",         -- Player failed a trust test
}

-- Store a memory for a contact
local function setContactMemory(contactId, key, value)
  local vendorState = state.vendors[contactId]
  if not vendorState then return end

  vendorState.conversationMemory = vendorState.conversationMemory or {}
  vendorState.conversationMemory[key] = value

  log("I", logTag, string.format("Memory stored for %s: %s = %s", contactId, key, tostring(value)))
end

-- Get a memory value for a contact
local function getContactMemory(contactId, key)
  local vendorState = state.vendors[contactId]
  if not vendorState or not vendorState.conversationMemory then
    return nil
  end
  return vendorState.conversationMemory[key]
end

-- Check if a contact has a specific memory
local function hasContactMemory(contactId, key)
  return getContactMemory(contactId, key) ~= nil
end

-- Get all memories for a contact
local function getAllContactMemories(contactId)
  local vendorState = state.vendors[contactId]
  if not vendorState then return {} end
  return vendorState.conversationMemory or {}
end

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

local function getSaveFilePath()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then
    return nil
  end
  return savePath .. "/career/rls_career/mysummer/deepweb.json"
end

local function initializeVendors()
  for vendorId, _ in pairs(vendorDefinitions) do
    if not state.vendors[vendorId] then
      state.vendors[vendorId] = {
        met = false,
        trustPoints = 0,
        unlocked = false,
        blacklisted = false,
        purchaseHistory = {},
        usedQuestions = {},
      }
    end
  end
end

local function saveState()
  local saveFile = getSaveFilePath()
  if not saveFile then
    log("W", logTag, "Cannot save - no save path available")
    return
  end

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
    log("I", logTag, "No save file found, initializing vendors")
    initializeVendors()
    return
  end

  local data = jsonReadFile(saveFile)
  if not data then
    log("E", logTag, "Failed to load save file")
    initializeVendors()
    return
  end

  state.vendors = data.vendors or {}
  state.currentConversation = data.currentConversation

  -- Ensure all vendors have usedQuestions
  for vendorId, vendorState in pairs(state.vendors) do
    if not vendorState.usedQuestions then
      vendorState.usedQuestions = {}
    end
  end

  initializeVendors()
  log("I", logTag, "State loaded")
end

-- ============================================================================
-- CONVERSATION GENERATION
-- ============================================================================

-- Pick a random question from pool, avoiding recently used ones
local function pickRandomQuestion(pool, usedIndices)
  if not pool or #pool == 0 then return nil, 1 end

  -- If all questions used, reset
  if #usedIndices >= #pool then
    usedIndices = {}
  end

  local attempts = 0
  local maxAttempts = #pool * 2
  local idx

  repeat
    idx = math.random(#pool)
    attempts = attempts + 1
  until not usedIndices[idx] or attempts >= maxAttempts

  return pool[idx], idx
end

-- Check if a question passes its condition based on memory
local function checkQuestionCondition(question, memory)
  if not question.condition then
    return true  -- No condition = always available
  end

  -- Check if the condition key exists and is truthy in memory
  return memory[question.condition] == true
end

-- Generate a full conversation for a vendor based on trust level/phase
local function generateConversation(vendorId)
  local vendorDef = vendorDefinitions[vendorId]
  local vendorState = state.vendors[vendorId]

  if not vendorDef then
    return nil
  end

  -- Load question pools from JSON (with fallback)
  local pools = getContactQuestionPools(vendorId)
  if not pools then
    log("W", logTag, "Using fallback question pools for: " .. vendorId)
    pools = fallbackQuestionPools
  end
  local usedQuestions = vendorState.usedQuestions or {}
  local memory = vendorState.conversationMemory or {}

  -- Get current level and phase
  local currentLevel = getContactLevel(vendorId)
  local currentPhase = getLevelPhase(currentLevel)
  local phaseConfig = conversationPhases[currentPhase]

  log("I", logTag, string.format("Generating conversation for %s at level %d (phase: %s, questions: %d)",
    vendorId, currentLevel, currentPhase, phaseConfig.questionCount))

  -- Get phase-specific intro message
  local phaseIntro = phaseIntroMessages[vendorId] and phaseIntroMessages[vendorId][currentPhase]

  -- Check for confrontation event (can override intro)
  local confrontation = selectConfrontation(vendorId, memory, currentLevel)
  local hasConfrontation = confrontation ~= nil

  if hasConfrontation then
    log("I", logTag, string.format("Confrontation triggered for %s: %s", vendorId, confrontation.text))
  end

  -- Select questions based on phase
  local questions = {}

  -- Determine which pool to use: phase-specific or legacy fallback
  local phasePool = pools[currentPhase]
  local hasPhasePool = phasePool and #phasePool > 0

  -- If confrontation triggered, insert it as the first question
  if hasConfrontation then
    local confrontQuestion = {
      text = confrontation.text,
      isConfrontation = true,
      responses = confrontation.responses,
    }
    table.insert(questions, confrontQuestion)
    log("I", logTag, string.format("Confrontation added as first question for %s", vendorId))
  -- Otherwise, create phase-specific intro if available
  elseif phaseIntro then
    -- Insert a synthetic intro question with the phase greeting
    local introQuestion = {
      text = phaseIntro,
      isPhaseIntro = true,
      responses = {
        { id = "a", text = "I'm ready to talk.", points = 5 },
        { id = "b", text = "Let's get down to business.", points = 5 },
        { id = "c", text = "Good to see you too.", points = 5 },
      }
    }
    table.insert(questions, introQuestion)
  elseif not hasPhasePool then
    -- Fallback to legacy intro question only if no phase pool
    local intro, introIdx = pickRandomQuestion(pools.intro or {}, usedQuestions.intro or {})
    if intro then
      table.insert(questions, intro)
      usedQuestions.intro = usedQuestions.intro or {}
      usedQuestions.intro[introIdx] = true
    end
  end

  -- Number of questions depends on phase
  local targetCount = phaseConfig.questionCount
  if hasConfrontation then
    targetCount = targetCount - 1  -- Confrontation counts as one question
  elseif phaseIntro then
    targetCount = targetCount - 1  -- Intro counts as one question
  end

  -- Use phase-specific pool if available
  if hasPhasePool then
    -- Initialize used questions for this phase
    usedQuestions[currentPhase] = usedQuestions[currentPhase] or {}

    -- Filter questions by condition
    local availableQuestions = {}
    for idx, q in ipairs(phasePool) do
      if not usedQuestions[currentPhase][idx] and checkQuestionCondition(q, memory) then
        table.insert(availableQuestions, { question = q, idx = idx })
      end
    end

    -- Pick random questions from available pool
    for i = 1, targetCount do
      if #availableQuestions == 0 then break end

      local pickIdx = math.random(#availableQuestions)
      local pick = availableQuestions[pickIdx]

      table.insert(questions, pick.question)
      usedQuestions[currentPhase][pick.idx] = true

      table.remove(availableQuestions, pickIdx)
    end

    log("D", logTag, string.format("  Used %d questions from phase '%s' pool (%d available)",
      #questions - (phaseIntro and 1 or 0), currentPhase, #phasePool))
  else
    -- Fallback to legacy pools (intro, questions, final)
    usedQuestions.questions = usedQuestions.questions or {}
    for i = 1, targetCount do
      local q, qIdx = pickRandomQuestion(pools.questions or {}, usedQuestions.questions)
      if q and checkQuestionCondition(q, memory) then
        table.insert(questions, q)
        usedQuestions.questions[qIdx] = true
      end
    end

    -- Final question (only for levels 2+ in legacy mode)
    if currentLevel >= 2 then
      local final, finalIdx = pickRandomQuestion(pools.final or {}, usedQuestions.final or {})
      if final then
        table.insert(questions, final)
        usedQuestions.final = usedQuestions.final or {}
        usedQuestions.final[finalIdx] = true
      end
    end
  end

  vendorState.usedQuestions = usedQuestions

  -- Store the phase in state for later reference
  vendorState.currentPhase = currentPhase

  return questions, currentPhase
end

-- ============================================================================
-- AI CONVERSATION SYSTEM
-- ============================================================================

-- Check if a contact uses AI for conversations
local function isAIContact(contactId)
  local data = loadContactFromJson(contactId)
  return data and data.useAI == true
end

-- Get AI config for a contact
local function getAIConfig(contactId)
  local data = loadContactFromJson(contactId)
  if data then
    return data.aiConfig, data.fallbackResponses
  end
  return nil, nil
end

-- Start an AI-powered conversation
local function startAIConversation(vendorId, callback)
  log("I", logTag, "Starting AI conversation with: " .. tostring(vendorId))

  local vendorDef = vendorDefinitions[vendorId]
  if not vendorDef then
    callback(nil, "Vendor not found")
    return
  end

  local vendorState = state.vendors[vendorId]
  if not vendorState then
    vendorState = { met = false, blacklisted = false }
    state.vendors[vendorId] = vendorState
  end

  -- Mark as met
  vendorState.met = true

  -- Load contact data with AI config
  local contactData = loadContactFromJson(vendorId)
  if not contactData then
    callback(nil, "Contact data not found")
    return
  end

  -- Check if AI module is available
  local aiModule = career_modules_mysummerAI
  if not aiModule then
    log("W", logTag, "AI module not available, using fallback")
    local fallback = contactData.fallbackResponses and contactData.fallbackResponses.greeting or "..."
    callback({
      vendor = {
        id = vendorId,
        name = vendorDef.name or vendorId,
        color = vendorDef.color or "#BF00FF",
        specialty = vendorDef.specialty or "Unknown",
        description = vendorDef.description or "",
      },
      messages = { { sender = "vendor", text = fallback } },
      isAI = true,
      waitingForInput = true,
      ended = false,
    })
    return
  end

  -- Check if AI is configured
  if not aiModule.isAIAvailable() then
    log("W", logTag, "AI not configured, using fallback")
    local fallback = contactData.fallbackResponses and contactData.fallbackResponses.offline or "AI not configured. Set up API key in settings."
    callback({
      vendor = {
        id = vendorId,
        name = vendorDef.name or vendorId,
        color = vendorDef.color or "#BF00FF",
        specialty = vendorDef.specialty or "Unknown",
        description = vendorDef.description or "",
      },
      messages = { { sender = "vendor", text = fallback } },
      isAI = true,
      aiNotConfigured = true,
      waitingForInput = false,
      ended = true,
    })
    return
  end

  -- Initialize AI conversation state
  state.currentConversation = {
    vendorId = vendorId,
    isAI = true,
    sessionPoints = 0,
    messageCount = 0,
  }

  -- Request AI greeting
  aiModule.startAIConversation(contactData, function(success, response)
    if success then
      local currentXP = getContactXP(vendorId)
      local currentLevel = getContactLevel(vendorId)

      callback({
        vendor = {
          id = vendorId,
          name = vendorDef.name or vendorId,
          color = vendorDef.color or "#BF00FF",
          specialty = vendorDef.specialty or "Unknown",
          description = vendorDef.description or "",
        },
        messages = { { sender = "vendor", text = response } },
        isAI = true,
        waitingForInput = true,
        ended = false,
        trustXP = currentXP,
        trustLevel = currentLevel,
      })
    else
      local fallback = contactData.fallbackResponses and contactData.fallbackResponses.error or "Connection failed."
      callback({
        vendor = {
          id = vendorId,
          name = vendorDef.name or vendorId,
          color = vendorDef.color or "#BF00FF",
        },
        messages = { { sender = "vendor", text = fallback } },
        isAI = true,
        waitingForInput = true,
        ended = false,
        error = response,
      })
    end
  end)
end

-- Send a free-text message to an AI contact
local function sendAIMessage(message, callback)
  if not state.currentConversation or not state.currentConversation.isAI then
    callback(nil, "No active AI conversation")
    return
  end

  local vendorId = state.currentConversation.vendorId
  local vendorDef = vendorDefinitions[vendorId]
  local contactData = loadContactFromJson(vendorId)

  if not contactData then
    callback(nil, "Contact data not found")
    return
  end

  local aiModule = career_modules_mysummerAI
  if not aiModule or not aiModule.isAIAvailable() then
    callback(nil, "AI not available")
    return
  end

  state.currentConversation.messageCount = (state.currentConversation.messageCount or 0) + 1

  -- Send message to AI
  aiModule.continueAIConversation(contactData, message, function(success, response)
    if success then
      -- Award some XP for engaging in conversation (small amount)
      local xpGain = 2  -- Small XP per message exchange
      addContactXP(vendorId, xpGain)
      state.currentConversation.sessionPoints = (state.currentConversation.sessionPoints or 0) + xpGain

      local currentXP = getContactXP(vendorId)
      local currentLevel = getContactLevel(vendorId)

      callback({
        vendor = {
          id = vendorId,
          name = vendorDef.name or vendorId,
        },
        messages = {
          { sender = "player", text = message },
          { sender = "vendor", text = response },
        },
        isAI = true,
        waitingForInput = true,
        ended = false,
        trustXP = currentXP,
        trustLevel = currentLevel,
        sessionPoints = state.currentConversation.sessionPoints,
      })
    else
      local fallback = contactData.fallbackResponses and contactData.fallbackResponses.error or "Connection lost."
      callback({
        vendor = { id = vendorId, name = vendorDef.name },
        messages = {
          { sender = "player", text = message },
          { sender = "vendor", text = fallback },
        },
        isAI = true,
        waitingForInput = true,
        ended = false,
        error = response,
      })
    end
  end)
end

-- End AI conversation
local function endAIConversation()
  if state.currentConversation and state.currentConversation.isAI then
    local vendorId = state.currentConversation.vendorId
    local sessionPoints = state.currentConversation.sessionPoints or 0

    -- Set cooldown if not always-unlocked
    if not isAlwaysUnlocked(vendorId) then
      setContactCooldown(vendorId)
    end

    log("I", logTag, string.format("AI conversation ended with %s, session XP: %d", vendorId, sessionPoints))

    state.currentConversation = nil
    saveState()

    return {
      ended = true,
      sessionPoints = sessionPoints,
    }
  end
  return nil
end

-- ============================================================================
-- CONVERSATION SYSTEM
-- ============================================================================

local function startConversation(vendorId)
  log("I", logTag, "startConversation called for vendor: " .. tostring(vendorId))

  local vendorDef = vendorDefinitions[vendorId]
  if not vendorDef then
    log("E", logTag, "Invalid vendor: " .. tostring(vendorId))
    return nil, "Vendor not found"
  end

  -- Check if contact is available (unlocked through chain)
  if not isContactAvailable(vendorId) then
    local unlockedBy = contactUnlockedBy[vendorId]
    local unlockerName = unlockedBy and vendorDefinitions[unlockedBy] and vendorDefinitions[unlockedBy].name or "another contact"
    log("W", logTag, "Contact not available: " .. vendorId .. " (needs " .. tostring(unlockerName) .. " at level 3)")
    return nil, "Build trust with " .. unlockerName .. " first to meet this contact"
  end

  -- Check cooldown (skip for AI pilot contacts)
  if not isAlwaysUnlocked(vendorId) then
    local onCooldown, remaining = isContactOnCooldown(vendorId)
    if onCooldown then
      local minutes = math.ceil(remaining / 60)
      log("I", logTag, string.format("Contact %s is on cooldown for %d more seconds", vendorId, remaining))
      return nil, string.format("%s is busy. Try again in %d minute%s.", vendorDef.name, minutes, minutes == 1 and "" or "s")
    end
  end

  local vendorState = state.vendors[vendorId]
  if not vendorState then
    log("E", logTag, "Vendor state not initialized: " .. vendorId)
    return nil, "Vendor not available"
  end

  if vendorState.blacklisted then
    return nil, "You've been blocked by this vendor"
  end

  -- Mark as met
  vendorState.met = true

  -- Generate new conversation (returns questions and current phase)
  local questions, currentPhase = generateConversation(vendorId)
  if not questions or #questions == 0 then
    return nil, "No questions available"
  end

  -- Initialize conversation with phase info
  state.currentConversation = {
    vendorId = vendorId,
    questions = questions,
    currentIndex = 1,
    sessionPoints = 0,
    phase = currentPhase,
  }

  saveState()

  -- Get first question
  local firstQuestion = questions[1]

  -- Build messages array
  local messages = {}
  if firstQuestion and firstQuestion.text then
    table.insert(messages, { sender = "vendor", text = firstQuestion.text })
  end

  -- Build choices array
  local choices = {}
  if firstQuestion and firstQuestion.responses then
    for _, response in ipairs(firstQuestion.responses) do
      table.insert(choices, { id = response.id, text = response.text })
    end
  end

  -- Get current XP and level using native system
  local currentXP = getContactXP(vendorId)
  local currentLevel = getContactLevel(vendorId)

  log("I", logTag, "Started conversation with " .. #questions .. " questions (Level: " .. currentLevel .. ", XP: " .. currentXP .. ", Phase: " .. currentPhase .. ")")

  return {
    vendor = {
      id = vendorId,
      name = vendorDef.name or vendorId,
      color = vendorDef.color or "#8B5CF6",
      specialty = vendorDef.specialty or "Unknown",
      description = vendorDef.description or "",
    },
    messages = messages,
    choices = choices,
    ended = false,
    trustXP = currentXP,
    trustLevel = currentLevel,
    trustPoints = currentXP,  -- Legacy compatibility
    trustThreshold = vendorDef.trustThreshold,
    phase = currentPhase,
  }
end

local function unlockVendorParts(vendorId)
  local vendorDef = vendorDefinitions[vendorId]
  if not vendorDef or not vendorDef.partsInventory then
    return
  end

  if not career_modules_mysummerParts then
    log("W", logTag, "mysummerParts module not available")
    return
  end

  if career_modules_mysummerParts.addVendorParts then
    career_modules_mysummerParts.addVendorParts(vendorId, vendorDef.partsInventory)
    log("I", logTag, "Added " .. #vendorDef.partsInventory .. " parts from vendor: " .. vendorId)
  end

  if career_modules_mysummerCareer then
    career_modules_mysummerCareer.addReputationPoints(50, "Unlocked vendor: " .. vendorDef.name)
  end
end

local function respondToVendor(responseId)
  log("I", logTag, "respondToVendor called with: " .. tostring(responseId))

  if not state.currentConversation then
    log("E", logTag, "No active conversation")
    return nil, "No active conversation"
  end

  local conv = state.currentConversation
  local vendorId = conv.vendorId
  local currentIdx = conv.currentIndex
  local questions = conv.questions

  local vendorDef = vendorDefinitions[vendorId]
  local vendorState = state.vendors[vendorId]

  if not vendorDef or not vendorState or not questions then
    log("E", logTag, "Invalid conversation state")
    return nil, "Invalid conversation state"
  end

  local currentQuestion = questions[currentIdx]
  if not currentQuestion then
    log("E", logTag, "No current question")
    return nil, "No current question"
  end

  -- Find selected response
  local selectedResponse = nil
  for _, response in ipairs(currentQuestion.responses) do
    if response.id == responseId then
      selectedResponse = response
      break
    end
  end

  if not selectedResponse then
    log("E", logTag, "Invalid response: " .. tostring(responseId))
    return nil, "Invalid response"
  end

  -- Get level BEFORE awarding points
  local levelBefore = getContactLevel(vendorId)

  -- Calculate points using trait system if this is a confrontation, otherwise use simple points
  local contactTraits = getContactTraits(vendorId)
  local pointsToAward = selectedResponse.points or 0

  -- If response has traits and contact has trait scoring, use trait-based calculation
  if selectedResponse.traits and contactTraits and contactTraits.scoring then
    pointsToAward = calculateTraitPoints(selectedResponse, contactTraits)
    log("D", logTag, string.format("Trait-based scoring for %s: %d points (traits: %s)",
      vendorId, pointsToAward, table.concat(selectedResponse.traits, ", ")))
  end

  -- Award points using native playerAttributes system
  conv.sessionPoints = conv.sessionPoints + pointsToAward
  addContactXP(vendorId, pointsToAward)

  -- Also update legacy trustPoints for backwards compatibility
  vendorState.trustPoints = (vendorState.trustPoints or 0) + selectedResponse.points

  -- Store conversation memories if the response has setsMemory
  if selectedResponse.setsMemory then
    for memKey, memValue in pairs(selectedResponse.setsMemory) do
      setContactMemory(vendorId, memKey, memValue)
    end
  end

  -- Get current XP and level
  local currentXP = getContactXP(vendorId)
  local currentLevel = getContactLevel(vendorId)

  log("I", logTag, string.format("%s: Response '%s' -> %+d points (XP: %d, Level: %d)",
    vendorId, responseId, selectedResponse.points, currentXP, currentLevel))

  -- Check for immediate rejection/blacklist
  if selectedResponse.next == "reject" then
    state.currentConversation = nil
    saveState()
    return {
      vendor = { id = vendorId, name = vendorDef.name },
      messages = {
        { sender = "player", text = selectedResponse.text },
        { sender = "vendor", text = "This conversation never happened. Lose this number." },
      },
      choices = {},
      ended = true,
      trustPoints = vendorState.trustPoints,
      trustThreshold = vendorDef.trustThreshold,
    }
  end

  if selectedResponse.next == "angry" then
    vendorState.blacklisted = true
    state.currentConversation = nil
    saveState()
    return {
      vendor = { id = vendorId, name = vendorDef.name },
      messages = {
        { sender = "player", text = selectedResponse.text },
        { sender = "vendor", text = "Wrong answer. You're blacklisted. Don't contact me again." },
      },
      choices = {},
      ended = true,
      trustPoints = vendorState.trustPoints,
      trustThreshold = vendorDef.trustThreshold,
    }
  end

  -- Move to next question
  conv.currentIndex = currentIdx + 1

  -- Check if conversation is complete
  if conv.currentIndex > #questions then
    -- Conversation complete - check if level increased and if we should introduce a new contact
    local levelAfter = getContactLevel(vendorId)
    local introducedContact = nil
    local introMessage = nil

    -- Check if we just reached level 3 (Associate) and should introduce next contact
    if levelBefore < INTRODUCTION_LEVEL and levelAfter >= INTRODUCTION_LEVEL then
      local nextContact = contactChain[vendorId]
      if nextContact and introductionMessages[vendorId] then
        introducedContact = nextContact
        introMessage = introductionMessages[vendorId]
        log("I", logTag, string.format("%s introduces %s at level %d", vendorId, nextContact, levelAfter))
      end
    end

    -- Always unlock vendor parts when conversation completes successfully (level 2+)
    if levelAfter >= 2 and not vendorState.unlocked then
      unlockVendorParts(vendorId)
      vendorState.unlocked = true
    end

    -- Set cooldown for this contact (skip for always-unlocked contacts like Oracle)
    if not isAlwaysUnlocked(vendorId) then
      setContactCooldown(vendorId)
      log("I", logTag, string.format("Set cooldown for %s", vendorId))
    end

    state.currentConversation = nil
    saveState()

    -- Build response messages
    local messages = {
      { sender = "player", text = selectedResponse.text },
    }

    -- Different messages based on level
    if levelAfter >= 5 then
      table.insert(messages, { sender = "vendor", text = "You're family now. Whatever you need, I got you." })
    elseif levelAfter >= 4 then
      table.insert(messages, { sender = "vendor", text = "You've earned my trust. I'll share my best contacts with you." })
    elseif levelAfter >= 3 then
      table.insert(messages, { sender = "vendor", text = "Alright. You're in. My parts are quality - don't waste them." })
    elseif levelAfter >= 2 then
      table.insert(messages, { sender = "vendor", text = "Not bad. Keep proving yourself and we'll talk again." })
    else
      table.insert(messages, { sender = "vendor", text = "Come back when you've proven yourself more." })
    end

    -- Add introduction message if we're introducing a new contact
    if introMessage then
      table.insert(messages, { sender = "vendor", text = introMessage })
    end

    return {
      vendor = { id = vendorId, name = vendorDef.name },
      messages = messages,
      choices = {},
      ended = true,
      trustPoints = currentXP,
      trustLevel = levelAfter,
      trustThreshold = vendorDef.trustThreshold,
      introducedContact = introducedContact,
    }
  end

  -- Continue conversation
  local nextQuestion = questions[conv.currentIndex]
  saveState()

  local choices = {}
  if nextQuestion and nextQuestion.responses then
    for _, resp in ipairs(nextQuestion.responses) do
      table.insert(choices, { id = resp.id, text = resp.text })
    end
  end

  return {
    vendor = { id = vendorId, name = vendorDef.name },
    messages = {
      { sender = "player", text = selectedResponse.text },
      { sender = "vendor", text = nextQuestion.text },
    },
    choices = choices,
    ended = false,
    trustPoints = vendorState.trustPoints,
    trustThreshold = vendorDef.trustThreshold,
  }
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

local function getVendorData()
  local vendors = {}
  for vendorId, vendorDef in pairs(vendorDefinitions) do
    local vendorState = state.vendors[vendorId] or {
      met = false,
      trustPoints = 0,
      unlocked = false,
      blacklisted = false,
    }

    -- Use native XP system
    local currentXP = getContactXP(vendorId)
    local currentLevel = getContactLevel(vendorId)
    local available = isContactAvailable(vendorId)

    -- Get who unlocks this contact
    local unlockedByName = nil
    local unlockedBy = contactUnlockedBy[vendorId]
    if unlockedBy and vendorDefinitions[unlockedBy] then
      unlockedByName = vendorDefinitions[unlockedBy].name
    end

    -- Check if can challenge to race
    local canRace, raceReason = canChallengeToRace(vendorId)

    -- Check cooldown status
    local onCooldown, cooldownRemaining = isContactOnCooldown(vendorId)
    local cooldownTotal = getCooldownDuration(vendorId)

    -- Check if this is an AI pilot contact
    local isAI = isAIPilotContact(vendorId)
    local alwaysAvailable = isAlwaysUnlocked(vendorId)

    -- Get traits for UI display
    local traits = getContactTraits(vendorId)

    table.insert(vendors, {
      id = vendorId,
      name = vendorDef.name or vendorId,
      description = vendorDef.description or "",
      personality = vendorDef.personality or "unknown",
      specialty = vendorDef.specialty or "Unknown",
      color = vendorDef.color or "#8B5CF6",
      -- Lock status based on unlock chain
      locked = not available,
      unlockedBy = unlockedByName,
      unlockedById = unlockedBy,
      -- Native XP/Level system
      trustXP = currentXP,
      trustLevel = currentLevel,
      -- Legacy compatibility
      trustPoints = currentXP,
      trustThreshold = vendorDef.trustThreshold,
      -- State
      met = vendorState.met,
      blacklisted = vendorState.blacklisted,
      partsUnlocked = vendorState.unlocked or false,
      -- Race challenge
      canRace = canRace,
      raceReason = raceReason,
      -- Cooldown info
      onCooldown = onCooldown and not alwaysAvailable,
      cooldownRemaining = onCooldown and cooldownRemaining or 0,
      cooldownTotal = cooldownTotal,
      -- Special contact flags
      isAIPilot = isAI,
      alwaysUnlocked = alwaysAvailable,
      -- Traits (for UI to show what contact values)
      traits = traits,
    })
  end

  log("I", logTag, "getVendorData returning " .. #vendors .. " vendors")

  -- Also trigger heat update so UI gets current heat info
  local partsModule = career_modules_mysummerParts
  if partsModule and partsModule.getPlayerHeat then
    local heat = partsModule.getPlayerHeat()
    local canClear, _ = canClearHeatWithShadow()
    guihooks.trigger("mysummerHeatUpdated", {
      heat = heat,
      maxHeat = 100,
      canClear = canClear,
      clearPrice = SHADOW_HEAT_CLEAR_PRICE,
    })
  end

  return vendors
end

local function getCurrentConversation()
  return state.currentConversation
end

-- ============================================================================
-- UI COMMUNICATION
-- ============================================================================

local function sendDeepWebUpdate()
  if not guihooks then
    return
  end
  guihooks.trigger("mysummerDeepWebUpdated", getVendorData())
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer DeepWeb module loaded")
end

local function onCareerActive(enabled)
  if not enabled then
    -- Cancel any active race when career deactivates
    if activeContactRace then
      cancelContactRace("Career deactivated")
    end
    return
  end

  log("I", logTag, "Initializing MySummer DeepWeb...")
  loadState()
  log("I", logTag, "MySummer DeepWeb initialized with " .. tableSize(vendorDefinitions) .. " vendors")
end

-- Called every frame
local function onUpdate(dt)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Process pending AI setup for contact vehicle
  if pendingAISetup then
    pendingAISetup.timeLeft = pendingAISetup.timeLeft - dt
    if pendingAISetup.timeLeft <= 0 then
      local veh = be:getObjectByID(pendingAISetup.vehId)
      if veh then
        local dest = pendingAISetup.destination
        log("I", logTag, string.format("Setting up AI to drive to: %s at pos %s", dest.name, tostring(dest.pos)))

        -- Configure AI for aggressive racing but smart driving
        veh:queueLuaCommand("ai.setMode('disabled')")  -- Reset first
        veh:queueLuaCommand("ai.stateChanged()")
        veh:queueLuaCommand("ai.setAggression(0.9)")  -- High aggression but not suicidal
        veh:queueLuaCommand("ai.setAvoidCars('on')")  -- Avoid crashes
        veh:queueLuaCommand("ai.setSpeedMode('off')")  -- No speed limits
        veh:queueLuaCommand("ai.driveInLane('off')")  -- Can overtake, cut corners

        -- Set target position (same as player's waypoint)
        veh:queueLuaCommand(string.format(
          "ai.setTarget(vec3(%f, %f, %f))",
          dest.pos.x, dest.pos.y, dest.pos.z
        ))

        -- Use 'span' mode - drives to target ignoring traffic rules
        veh:queueLuaCommand("ai.setMode('span')")

        log("I", logTag, string.format("AI setup complete - racing to %s", dest.name))
      else
        log("E", logTag, "Could not find contact vehicle for AI setup")
      end
      pendingAISetup = nil
    end
  end

  -- Update contact race system
  updateContactRace(dt)
end

-- ============================================================================
-- COMPUTER INTEGRATION
-- ============================================================================

local originComputerId = nil

local function openMenuFromComputer(computerId)
  originComputerId = computerId
  log("I", logTag, "Opening Deep Web menu from computer: " .. tostring(computerId))
  if guihooks then
    guihooks.trigger("ChangeState", { state = "mysummer-deepweb" })
  end
end

local function closeMenu()
  if originComputerId then
    local freeroam_facilities = require("freeroam/facilities")
    local computer = freeroam_facilities.getFacility("computer", originComputerId)
    if computer and career_modules_computer then
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

local function onComputerAddFunctions(menuData, computerFunctions)
  -- NOTE: Deep Web (SilkRoad) is now accessed via Internet Browser (mysummerInternet module)
  -- No separate menu entry needed - user navigates to SilkRoad from the browser
end

-- ============================================================================
-- POLICE PURSUIT INTEGRATION
-- ============================================================================

-- Hook into BeamNG's pursuit system to detect when player is arrested
local function onPursuitAction(vehId, action, data)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Only handle arrests
  if action ~= "arrest" then
    return
  end

  -- Only apply penalty if the player (not cop) was arrested
  local playerVehId = be:getPlayerVehicleID(0)
  if vehId ~= playerVehId then
    return
  end

  -- Check if player is a cop (cops don't lose trust)
  if career_modules_playerDriving and career_modules_playerDriving.getPlayerIsCop and career_modules_playerDriving.getPlayerIsCop() then
    return
  end

  log("I", logTag, "Player arrested by police - applying contact trust penalty")
  onPlayerArrested()
end

-- ============================================================================
-- SHADOW SPECIAL SERVICES
-- ============================================================================

local SHADOW_HEAT_CLEAR_PRICE = 5000  -- $5000 to clear heat

-- Check if player can afford to clear heat with Shadow
-- Note: canClearHeatWithShadow is forward declared at the top of CONTACT RACE SYSTEM section
canClearHeatWithShadow = function()
  -- Must have Shadow unlocked (level 2+)
  local level = getContactLevel("shadow")
  if level < 2 then
    return false, "You don't know Shadow well enough yet."
  end

  -- Must have heat to clear
  local partsModule = career_modules_mysummerParts
  if not partsModule or not partsModule.getPlayerHeat then
    return false, "Heat system not available."
  end

  local heat = partsModule.getPlayerHeat()
  if heat <= 0 then
    return false, "You don't have any heat to clear."
  end

  -- Must be able to afford it
  local priceData = { money = { amount = SHADOW_HEAT_CLEAR_PRICE, canBeNegative = false } }
  if not career_modules_payment.canPay(priceData) then
    return false, string.format("Not enough money. Shadow charges $%d.", SHADOW_HEAT_CLEAR_PRICE)
  end

  return true, nil
end

-- Clear heat with Shadow (costs money)
local function clearHeatWithShadow()
  local canClear, errorMsg = canClearHeatWithShadow()
  if not canClear then
    return { success = false, message = errorMsg }
  end

  -- Pay Shadow
  local priceData = { money = { amount = SHADOW_HEAT_CLEAR_PRICE, canBeNegative = false } }
  career_modules_payment.pay(priceData, { label = "Shadow - Heat cleanup", tags = { "services" } })

  -- Clear heat
  local partsModule = career_modules_mysummerParts
  partsModule.clearPlayerHeat()

  -- Add a bit of XP with Shadow for using his services
  addContactXP("shadow", 5)

  ui_message("Shadow cleaned your records. You're a ghost again.", 4, "DeepWeb")
  log("I", logTag, "Player cleared heat with Shadow for $" .. SHADOW_HEAT_CLEAR_PRICE)

  return { success = true, message = "Heat cleared." }
end

-- Get current heat info for UI
local function getPlayerHeatInfo()
  local partsModule = career_modules_mysummerParts
  if not partsModule or not partsModule.getPlayerHeat then
    return { heat = 0, maxHeat = 100, canClear = false }
  end

  local heat = partsModule.getPlayerHeat()
  local canClear, _ = canClearHeatWithShadow()

  return {
    heat = heat,
    maxHeat = 100,
    canClear = canClear,
    clearPrice = SHADOW_HEAT_CLEAR_PRICE,
  }
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onUpdate = onUpdate  -- Frame update for race system
M.onComputerAddFunctions = onComputerAddFunctions
M.onPursuitAction = onPursuitAction  -- Hook into police pursuit system
M.onClientStartMission = onClientStartMission  -- Reset destinations on map change

M.getVendorData = getVendorData
M.getCurrentConversation = getCurrentConversation
M.startConversation = startConversation
M.respondToVendor = respondToVendor
M.openMenuFromComputer = openMenuFromComputer
M.closeMenu = closeMenu
M.closeAllMenus = closeAllMenus

-- Native skills API
M.addContactXP = addContactXP
M.getContactXP = getContactXP
M.getContactLevel = getContactLevel
M.isContactAvailable = isContactAvailable

-- Conversation memory API
M.setContactMemory = setContactMemory
M.getContactMemory = getContactMemory
M.hasContactMemory = hasContactMemory
M.getAllContactMemories = getAllContactMemories

-- Contact race API
M.canChallengeToRace = canChallengeToRace
M.startContactRace = startContactRace
M.cancelContactRace = cancelContactRace
M.getActiveRaceState = getActiveRaceState

-- Arrest penalty system
M.onPlayerArrested = onPlayerArrested

-- Shadow heat services
M.getPlayerHeatInfo = getPlayerHeatInfo
M.clearHeatWithShadow = clearHeatWithShadow
M.canClearHeatWithShadow = canClearHeatWithShadow

-- Cooldown system API
M.isContactOnCooldown = isContactOnCooldown
M.getCooldownDuration = getCooldownDuration
M.clearContactCooldown = clearContactCooldown  -- Debug function

-- Traits and confrontation API
M.getContactTraits = getContactTraits
M.getContactConfrontations = getContactConfrontations
M.getContactRelationships = getContactRelationships
M.isAIPilotContact = isAIPilotContact
M.isAlwaysUnlocked = isAlwaysUnlocked

-- AI Conversation API
M.isAIContact = isAIContact
M.startAIConversation = startAIConversation
M.sendAIMessage = sendAIMessage
M.endAIConversation = endAIConversation

-- Debug: verify exports
log("D", logTag, "Export check - startContactRace type: " .. type(startContactRace))
log("D", logTag, "Export check - M.startContactRace type: " .. type(M.startContactRace))

return M
