-- MySummer Missions System
-- Handles contact missions (delivery, find part, race, etc.)

local M = {}
M.moduleName = "career_modules_mysummerMissions"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerCareer",
}

local logTag = "mysummerMissions"
local saveFile = "mysummer_missions.json"

-- Forward declarations
local saveState
local resetTimeWarnings
local cleanupChaseTarget
local startMission
local cleanupSurveillanceTarget
local cleanupEscortMission

-- Helper functions
local function tableSize(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

-- Convert position to vec3 (handles tables and vec3)
local function toVec3(pos)
  if not pos then return nil end
  if type(pos) == "cdata" then return pos end -- already vec3
  if pos.x then return vec3(pos.x, pos.y, pos.z) end
  if pos[1] then return vec3(pos[1], pos[2], pos[3]) end
  return nil
end

-- ============================================================================
-- MISSION DEFINITIONS
-- ============================================================================

-- Mission types
local MISSION_TYPES = {
  DELIVERY = "delivery",      -- Transport item from A to B
  FIND_PART = "find_part",    -- Acquire specific part for contact
  RACE = "race",              -- Challenge race (already implemented separately)
  SURVEILLANCE = "surveillance", -- Follow target without being detected
  ESCORT = "escort",          -- Protect contact's vehicle during transport
  CHASE = "chase",            -- Chase and stop a fleeing target
}

-- Vehicle configs for chase targets by difficulty (from BeamNG base game)
local CHASE_VEHICLES = {
  easy = {
    { model = "covet", config = "DX_M" },
    { model = "covet", config = "13s_M" },
    { model = "midsize", config = "DX_M" },
    { model = "midsize", config = "LX_M" },
    { model = "etki", config = "2400_M" },
    { model = "etki", config = "2400i_M" },
  },
  medium = {
    { model = "covet", config = "sport" },
    { model = "covet", config = "turbo" },
    { model = "midsize", config = "LX_V6_sport_M" },
    { model = "etki", config = "2400ti_sport_M" },
    { model = "etki", config = "3000i_M" },
    { model = "etk800", config = "846_340_M" },
    { model = "sunburst2", config = "sport_RS_M" },
    { model = "vivace", config = "vivace_230S_DCT" },
    { model = "bastion", config = "sport_M" },
  },
  hard = {
    { model = "scintilla", config = "gts" },
    { model = "scintilla", config = "gtx" },
    { model = "sbr", config = "S_RWD_M" },
    { model = "sbr", config = "TT_AWD_S_M" },
    { model = "vivace", config = "vivace_S_350q_M" },
    { model = "vivace", config = "vivace_S_410q_M" },
    { model = "etki", config = "2400ti_sport_evo_M" },
    { model = "etki", config = "race" },
    { model = "bastion", config = "battlehawk_M" },
    { model = "sunburst2", config = "trackday_M" },
  },
}

-- Chase state tracking
local chaseState = {
  targetVehicleId = nil,      -- ID of the spawned target vehicle
  targetSpawned = false,      -- Whether target is currently spawned
  targetFleeing = false,      -- Whether target has started fleeing
  fleeDistance = 50,          -- Distance at which target starts fleeing
  catchDistance = 12,         -- Must get within 12m to "catch"
  stoppedSpeed = 3,           -- Target must be < 3 m/s (~10 km/h) to count as stopped
  escapeDistance = 800,       -- Target escapes if > 800m away
  stoppedTimer = 0,           -- Accumulator for how long target has been stopped near player
  requiredStopTime = 2.0,     -- Must be stopped for 2 seconds to complete
}

-- Surveillance state tracking
local surveillanceState = {
  targetVehicleId = nil,      -- ID of the target vehicle to follow
  targetSpawned = false,      -- Whether target is spawned
  detectionMeter = 0,         -- 0-100, if reaches 100 = detected (mission fails)
  followTimer = 0,            -- Time successfully following
  requiredFollowTime = 180,   -- 3 minutes required to complete (legacy, now using minFollowTime)
  -- Distance thresholds
  tooCloseDistance = 25,      -- < 25m = high detection rate
  optimalMinDistance = 40,    -- 40-80m = safe following distance
  optimalMaxDistance = 80,
  tooFarDistance = 150,       -- > 150m = losing target
  lostDistance = 200,         -- > 200m = target lost, mission fails
  -- Warning flags (to avoid repeating messages)
  warnedTooClose = false,
  warnedTooFar = false,
  warnedDetection50 = false,
  warnedDetection75 = false,
  warnedOncoming = false,          -- Warned about being in oncoming traffic
  -- Advanced detection state
  targetFound = false,             -- Player has reached target once (within 25m)
  targetFoundDistance = 25,        -- Distance at which target is "found" and detection starts
  initialWaypointCleared = false,  -- Waypoint cleared after finding target
  -- Destination + Quiz system (DYNAMIC: picks destination based on where target stops)
  destination = nil,               -- { pos = vec3, name = string }
  destinationReached = false,      -- Target arrived at destination
  quizPhase = false,               -- Currently in quiz phase
  quizOptions = {},                -- 3 location options
  correctAnswer = nil,             -- The correct location name
  arrivalDistance = 25,            -- Distance to consider "arrived" at facility (generous for AI tolerance)
  vehicleDesc = nil,               -- Description of target vehicle (for quiz message)
  -- Dynamic destination timing
  minFollowTime = 60,              -- Must follow for at least 60 seconds before destination check
  targetStoppedTime = 0,           -- How long target has been stopped
  targetStoppedThreshold = 5,      -- Target must be stopped 5 seconds to trigger arrival
  allDestinations = {},            -- All possible destinations (cached)
  currentDestination = nil,        -- Where target is currently heading (set at start)
  -- Startup delay (target waits before starting to drive)
  startupDelay = 3,                -- Wait 3 seconds before starting to drive
  startupTimer = 0,                -- Timer for startup delay
  targetStarted = false,           -- Whether target has started driving
  -- Collision detection
  lastTargetDamage = 0,            -- Track target's damage to detect hits
  collisionDetected = false,       -- If player hit the target
  -- Flee chase mode (when detected, sometimes target flees)
  fleeChaseActive = false,         -- Target is fleeing, player must stop them
  fleeChaseTimer = 0,              -- Time in flee chase
  fleeChaseMaxTime = 60,           -- Max 60 seconds to catch them
  fleeChaseStoppedTimer = 0,       -- Time target has been stopped
  fleeChaseRequiredStopTime = 2.0, -- Must be stopped 2 seconds to "catch"
}

-- Escort state tracking (survival mode - waves of enemies OR police pursuit)
local escortState = {
  playerVehicleId = nil,        -- The resistant vehicle player is teleported to
  originalVehicleId = nil,      -- Player's original vehicle to restore after
  enemyVehicleIds = {},         -- Array of active enemy vehicle IDs (non-police mode)
  enemyDisabledTimers = {},     -- Track how long each enemy has been disabled
  destination = nil,            -- Destination position
  destinationName = "",         -- Destination name for UI
  -- Mode selection (true = police pursuit, false = spawned enemies)
  usePoliceMode = false,        -- Using spawned enemies (police mode disabled)
  policeActive = false,         -- Whether police pursuit is currently active
  -- Spawned police tracking (for police mode with manual spawns)
  spawnedPoliceIds = {},        -- Array of spawned police vehicle IDs
  policeSpawnTimer = 0,         -- Timer for spawning police
  policeSpawnInterval = 5,      -- Seconds between police spawns (fast reinforcements)
  maxSpawnedPolice = 8,         -- Max police to spawn manually
  policeInitialDelay = 2,       -- Delay before spawning first police (quick start)
  -- Wave system (for non-police mode)
  currentWave = 0,              -- Current wave number
  maxWaves = 5,                 -- Total waves to survive
  enemiesThisWave = 0,          -- Enemies spawned in current wave
  waveTimer = 0,                -- Timer for wave spawning
  waveInterval = 20,            -- Seconds between waves
  initialDelay = 8,             -- Delay before first wave
  -- Enemy tracking (for non-police mode)
  maxActiveEnemies = 5,         -- Max enemies at once
  enemySpawnDistance = 150,     -- How far ahead/behind to spawn
  enemyDisableThreshold = 12000, -- Damage threshold to consider "disabled"
  enemyDisableTime = 5,         -- Seconds immobile before despawn
  -- Player disable tracking (damaged + can't move)
  playerStartDamage = 0,        -- Player's damage at mission start
  playerDamageThreshold = 8000, -- Damage threshold to start checking if disabled
  playerDisabledTimer = 0,      -- How long player has been disabled
  playerDisabledTime = 8,       -- Seconds disabled before mission fails
  playerMinSpeed = 3,           -- Speed below this = "not moving" (m/s, ~10 km/h)
  -- Mission state
  missionStarted = false,       -- Whether mission has fully started
  reachedDestination = false,   -- Whether player reached destination
  arrivalDistance = 2,          -- Distance to destination to "arrive" (2m for precision)
  -- End mission state
  missionEnding = false,        -- Mission is in ending sequence
  endingTimer = 0,              -- Timer for ending sequence
  endingSuccess = false,        -- Whether ending is success or fail
  -- Pending vehicle delete (to avoid quickAccess errors)
  pendingVehicleDelete = nil,   -- Vehicle ID to delete after switch
  pendingDeleteTimer = 0,       -- Timer before deleting
}

-- Vehicles for escort player (resistant/heavy vehicles)
local ESCORT_PLAYER_VEHICLES = {
  -- Heavy duty pickups (D35/D45 series)
  { model = "pickup", config = "d35_crew_4wd_beast_A", desc = "D35 Beast" },
  { model = "pickup", config = "d35_4wd_pig_M", desc = "D35 Pig" },
  { model = "pickup", config = "d45_diesel_4wd_ambulance_A", desc = "D45 Ambulance" },
  -- Desert trucks (extremely tough)
  { model = "pickup", config = "deserttruck_prerunner_A", desc = "Desert Prerunner" },
  { model = "pickup", config = "deserttruck_crawler_A", desc = "Desert Crawler" },
  { model = "pickup", config = "deserttruck_rockracer_A", desc = "Rock Racer" },
  -- Military-style trucks (6x6)
  { model = "midtruck", config = "6x6_carrier_diesel", desc = "6x6 Military Truck" },
  { model = "midtruck", config = "6x6_rally_diesel", desc = "6x6 Rally Truck" },
  { model = "midtruck", config = "6x6_pickup_diesel", desc = "6x6 Pickup" },
  -- Rock bouncer (super tough suspension)
  { model = "rockbouncer", config = "rock_bouncer_n2o", desc = "Rock Bouncer" },
  { model = "rockbouncer", config = "rock_crawler", desc = "Rock Crawler" },
  -- Heavy vans (H35 series)
  { model = "van", config = "h35_vanster_4wd", desc = "H35 4WD Van" },
  { model = "van", config = "offroad", desc = "Offroad Van" },
  -- Semi trucks (massive)
  { model = "us_semi", config = "t83_custom", desc = "Custom Semi" },
  { model = "us_semi", config = "t83_longhaul", desc = "Longhaul Semi" },
  -- Roamer offroad
  { model = "roamer", config = "offroad", desc = "Roamer Offroad" },
  { model = "roamer", config = "v8_4wd_lxt", desc = "Roamer V8 LXT" },
}

-- Vehicles for escort enemies (fast/aggressive)
local ESCORT_ENEMY_VEHICLES = {
  { model = "covet", config = "turbo" },
  { model = "etki", config = "2400ti_sport_M" },
  { model = "sunburst2", config = "sport_RS_M" },
  { model = "vivace", config = "vivace_230S_DCT" },
  { model = "bastion", config = "sport_M" },
  { model = "midsize", config = "LX_V6_sport_M" },
  { model = "scintilla", config = "gts" },
  { model = "sbr", config = "S_RWD_M" },
}

-- Vehicles for spawned police (fast interceptors) - used in police escort mode
local ESCORT_POLICE_VEHICLES = {
  { model = "fullsize", config = "base_M" },      -- Classic police cruiser
  { model = "roamer", config = "v8_4wd_base" },   -- Police SUV
  { model = "wendover", config = "base_M" },      -- Highway patrol
  { model = "bastion", config = "sport_M" },      -- Fast pursuit
  { model = "vivace", config = "vivace_230S_DCT" }, -- Quick interceptor
  { model = "etk800", config = "846_340_M" },     -- Euro pursuit
}

-- Vehicles for surveillance targets with descriptions and aggression levels
-- aggression: 0.3 = calm driver, 0.6 = normal, 1.0 = aggressive/fast
local SURVEILLANCE_VEHICLES = {
  { model = "midsize", config = "DX_M", desc = "gray sedan", aggression = 0.4 },
  { model = "midsize", config = "LX_M", desc = "dark sedan", aggression = 0.5 },
  { model = "covet", config = "DX_M", desc = "small hatchback", aggression = 0.6 },
  { model = "fullsize", config = "base_M", desc = "large sedan", aggression = 0.3 },
  { model = "van", config = "base_M", desc = "white van", aggression = 0.3 },
  { model = "bluebuck", config = "base_M", desc = "classic coupe", aggression = 0.5 },
  { model = "moonhawk", config = "base_M", desc = "old muscle car", aggression = 0.8 }, -- Fast!
}

-- Time transition state (visible timelapse)
local timeTransitionState = {
  active = false,
  startTime = 0,              -- Starting time of day (0-1)
  targetTime = 0,             -- Target time of day (0-1)
  duration = 4.0,             -- Duration of timelapse in seconds
  elapsed = 0,                -- Time elapsed in transition
  pendingMissionId = nil,     -- Mission to start after transition completes
  originalTime = nil,         -- Time before mission started (to restore after)
}

-- Time condition values for tod.time
-- BeamNG uses: actual_seconds = ((tod.time + 0.5) % 1) * 86400
-- So: tod.time = (desired_hour/24 - 0.5 + 1) % 1
local TIME_CONDITIONS = {
  midnight = 0.5,    -- 00:00 (12:00 AM)
  dawn = 0.75,       -- 06:00 (6:00 AM)
  morning = 0.875,   -- 09:00 (9:00 AM)
  noon = 0.0,        -- 12:00 (12:00 PM) - also works as 1.0
  afternoon = 0.125, -- 15:00 (3:00 PM)
  dusk = 0.25,       -- 18:00 (6:00 PM)
  evening = 0.333,   -- 20:00 (8:00 PM)
  night = 0.375,     -- 21:00 (9:00 PM)
}

-- Convert hour (0-24) to tod.time value
local function hourToTodTime(hour)
  return ((hour / 24) - 0.5 + 1) % 1
end

-- Convert tod.time to hour (0-24)
local function todTimeToHour(todTime)
  return ((todTime + 0.5) % 1) * 24
end

-- Mission templates by contact
local missionTemplates = {
  ghost = {
    {
      type = MISSION_TYPES.DELIVERY,
      id = "ghost_delivery_1",
      title = "Midnight Run",
      description = "I need a package moved. No questions. Pick it up at the old gas station, bring it to the warehouse by the docks. Don't get stopped.",
      pickupHint = "Old gas station on the highway",
      dropoffHint = "Warehouse near the docks",
      timeLimit = 300, -- 5 minutes
      reward = { money = 500, xp = 25 },
      requiredLevel = 1,
      heat = 1, -- Police attention level
      requiresCargo = true, -- Needs 1 cargo slot
      cargoSlots = 3, -- Small package
      timeCondition = "night", -- Must happen at night
    },
    {
      type = MISSION_TYPES.DELIVERY,
      id = "ghost_delivery_2",
      title = "Hot Cargo",
      description = "This one's risky. The heat is real. Get the goods from the auto shop on the east side, deliver to the abandoned lot. Fast.",
      pickupHint = "Auto shop on the east side",
      dropoffHint = "Abandoned lot in industrial area",
      timeLimit = 240,
      reward = { money = 800, xp = 40 },
      requiredLevel = 2,
      heat = 2,
      requiresCargo = true,
      cargoSlots = 6, -- Larger package
    },
    {
      type = MISSION_TYPES.SURVEILLANCE,
      id = "ghost_surveillance_1",
      title = "Eyes On",
      description = "There's a guy I need watched. Follow the black sedan, stay back, report where he goes. Don't let him see you.",
      targetDescription = "Black sedan",
      followTime = 180, -- 3 minutes
      maxDistance = 100, -- meters
      minDistance = 20,
      reward = { money = 400, xp = 30 },
      requiredLevel = 2,
      requiresCargo = false, -- No cargo needed
      timeCondition = "dusk", -- Easier to follow in twilight
    },
    -- Chase missions for Ghost
    {
      type = MISSION_TYPES.CHASE,
      id = "ghost_chase_1",
      title = "Debt Collection",
      description = "Someone owes me money and they're trying to skip town. Find them, stop them, make them reconsider. They're driving a small hatchback.",
      targetHint = "Small hatchback heading out of town",
      difficulty = "easy",
      timeLimit = 300, -- 5 minutes
      reward = { money = 600, xp = 35 },
      requiredLevel = 1,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "ghost_chase_2",
      title = "Loose End",
      description = "There's a rat in a sports car trying to reach the highway. Don't let him. You know what to do.",
      targetHint = "Sports car heading to highway",
      difficulty = "medium",
      timeLimit = 240,
      reward = { money = 900, xp = 50 },
      requiredLevel = 2,
      heat = 1,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "ghost_chase_3",
      title = "No Witnesses",
      description = "Someone saw something they shouldn't have. They're in a fast car and they're scared. Good. Stop them before they talk.",
      targetHint = "Fast sedan fleeing the city",
      difficulty = "hard",
      timeLimit = 180,
      reward = { money = 1500, xp = 75 },
      requiredLevel = 3,
      heat = 2,
      requiresCargo = false,
      timeCondition = "night", -- Cover of darkness
    },
    -- Escort missions for Ghost
    {
      type = MISSION_TYPES.ESCORT,
      id = "ghost_escort_1",
      title = "Running The Gauntlet",
      description = "Someone put a price on my head. I need my truck delivered across town but everyone wants to collect. Get in, drive, survive. The truck can take a beating.",
      maxWaves = 3,
      enemiesPerWave = { 1, 2, 2 }, -- Starter escort mission
      waveInterval = 30,
      reward = { money = 1000, xp = 50 },
      requiredLevel = 2,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.ESCORT,
      id = "ghost_escort_2",
      title = "Death Race",
      description = "Every crew in the city wants my blood tonight. You're driving my armored rig through all of them. Don't stop. Don't look back.",
      maxWaves = 5,
      enemiesPerWave = { 2, 2, 3, 4, 5 }, -- Escalating intensity
      waveInterval = 18,
      reward = { money = 2500, xp = 100 },
      requiredLevel = 3,
      requiresCargo = false,
      timeCondition = "night",
    },
  },

  techie = {
    {
      type = MISSION_TYPES.FIND_PART,
      id = "techie_findpart_1",
      title = "Component Hunt",
      description = "I need an ECU from a specific batch. Check the junkyards, find one with serial starting 'EK4'. Don't ask why.",
      partCategory = "electronics",
      partHint = "ECU with serial EK4-xxx",
      timeLimit = 600, -- 10 minutes to find
      reward = { money = 300, xp = 20 },
      requiredLevel = 1,
      requiresCargo = false, -- Just finding, not transporting
    },
    {
      type = MISSION_TYPES.DELIVERY,
      id = "techie_delivery_1",
      title = "Precision Timing",
      description = "This ECU needs to get to my associate exactly on time. Not early, not late. Leave at the marked spot between 2:00 and 2:05.",
      pickupHint = "Tech warehouse",
      dropoffHint = "Parking lot behind tech store",
      timeWindow = { min = 120, max = 125 }, -- delivery window in seconds from start
      timeLimit = 300,
      reward = { money = 450, xp = 35 },
      requiredLevel = 2,
      requiresCargo = true,
      cargoSlots = 2, -- Small ECU package
    },
    -- Chase missions for Techie
    {
      type = MISSION_TYPES.CHASE,
      id = "techie_chase_1",
      title = "Data Courier",
      description = "Someone's running with prototype ECU maps. They're in a tuned hatchback. Catch them before they upload the data.",
      targetHint = "Tuned hatchback with stolen data",
      difficulty = "easy",
      timeLimit = 300,
      reward = { money = 500, xp = 30 },
      requiredLevel = 1,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "techie_chase_2",
      title = "Corporate Spy",
      description = "A competitor sent someone to steal our diagnostic software. They're in a fast sedan. Don't let them reach the highway.",
      targetHint = "Fast sedan heading to highway",
      difficulty = "medium",
      timeLimit = 240,
      reward = { money = 850, xp = 45 },
      requiredLevel = 2,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "techie_chase_3",
      title = "The Hacker",
      description = "This guy cracked our security and downloaded everything. He's good at driving too. Sports car, modified. End this.",
      targetHint = "Modified sports car with hacker",
      difficulty = "hard",
      timeLimit = 180,
      reward = { money = 1300, xp = 65 },
      requiredLevel = 3,
      requiresCargo = false,
    },
  },

  muscle = {
    {
      type = MISSION_TYPES.DELIVERY,
      id = "muscle_delivery_1",
      title = "Parts Run",
      description = "Got some manifolds that need moving. Nothing fancy, just get 'em to the shop before the day's out.",
      pickupHint = "Garage behind the diner",
      dropoffHint = "Performance shop downtown",
      timeLimit = 420, -- 7 minutes
      reward = { money = 350, xp = 20 },
      requiredLevel = 1,
      heat = 0,
      requiresCargo = true,
      cargoSlots = 8, -- Manifolds are medium sized
    },
    {
      type = MISSION_TYPES.ESCORT,
      id = "muscle_escort_1",
      title = "Gauntlet Run",
      description = "Some people want me dead. I need you to drive my truck through their territory while they try to stop you. You'll be in an armored vehicle. Survive the run and there's good money in it.",
      maxWaves = 4,
      enemiesPerWave = { 1, 2, 2, 3 }, -- Escalating waves
      waveInterval = 25,
      reward = { money = 1200, xp = 60 },
      requiredLevel = 2,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.ESCORT,
      id = "muscle_escort_2",
      title = "Highway To Hell",
      description = "There's a bounty on my head and every punk with a car is coming for it. Get in my truck, drive to the safe house, don't stop for nothing.",
      maxWaves = 5,
      enemiesPerWave = { 2, 2, 3, 3, 4 }, -- More intense
      waveInterval = 20,
      reward = { money = 1800, xp = 80 },
      requiredLevel = 3,
      requiresCargo = false,
      timeCondition = "night",
    },
    -- Chase missions for Muscle
    {
      type = MISSION_TYPES.CHASE,
      id = "muscle_chase_1",
      title = "Snitch Hunt",
      description = "Word is there's a snitch heading to the cops. He's in some economy car thinking he's clever. Show him he's not.",
      targetHint = "Economy car heading to police station",
      difficulty = "easy",
      timeLimit = 300,
      reward = { money = 550, xp = 30 },
      requiredLevel = 1,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "muscle_chase_2",
      title = "Repo Man",
      description = "Some punk stole a car from a friend of mine. Sedan, silver, headed downtown. Get it back. By any means.",
      targetHint = "Silver sedan heading downtown",
      difficulty = "medium",
      timeLimit = 240,
      reward = { money = 800, xp = 45 },
      requiredLevel = 2,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "muscle_chase_3",
      title = "Highway Intercept",
      description = "There's a muscle car making a run for the state line. Driver owes big money to big people. Stop him. Hard.",
      targetHint = "Muscle car fleeing on highway",
      difficulty = "hard",
      timeLimit = 180,
      reward = { money = 1400, xp = 70 },
      requiredLevel = 3,
      heat = 1,
      requiresCargo = false,
    },
  },

  import = {
    {
      type = MISSION_TYPES.FIND_PART,
      id = "import_findpart_1",
      title = "Rare Find",
      description = "There's a specific body kit I'm looking for. Check the import shops, see if anyone has an authentic one. No replicas.",
      partCategory = "body",
      partHint = "Authentic JDM body kit",
      timeLimit = 600,
      reward = { money = 400, xp = 25, part = "etki_bumper_F_kit" },
      requiredLevel = 1,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.DELIVERY,
      id = "import_delivery_1",
      title = "Show Car Transit",
      description = "A client's show car needs transport. Drive carefully - any damage comes out of your pocket. Deliver to the show grounds.",
      pickupHint = "Import warehouse",
      dropoffHint = "Car show grounds",
      timeLimit = 480,
      noDamage = true, -- Fail if vehicle takes damage
      reward = { money = 700, xp = 40 },
      requiredLevel = 2,
      requiresCargo = true,
      cargoSlots = 10, -- Car parts are bulky
    },
    -- Chase missions for Import
    {
      type = MISSION_TYPES.CHASE,
      id = "import_chase_1",
      title = "Illegal Racer",
      description = "Some kid thinks he can race on our streets without paying tribute. He's in a riced-out compact. Teach him respect.",
      targetHint = "Tuned compact car",
      difficulty = "easy",
      timeLimit = 300,
      reward = { money = 550, xp = 30 },
      requiredLevel = 1,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "import_chase_2",
      title = "Parts Runner",
      description = "Someone's smuggling counterfeit parts through our territory. Sport sedan, probably boosted. Intercept before they cross the bridge.",
      targetHint = "Sport sedan with counterfeit parts",
      difficulty = "medium",
      timeLimit = 240,
      reward = { money = 900, xp = 50 },
      requiredLevel = 2,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "import_chase_3",
      title = "The Betrayer",
      description = "Former associate. Took our best client list and is selling to competitors. High-performance coupe. Make an example.",
      targetHint = "High-performance coupe fleeing city",
      difficulty = "hard",
      timeLimit = 180,
      reward = { money = 1400, xp = 70 },
      requiredLevel = 3,
      heat = 1,
      requiresCargo = false,
    },
  },

  shadow = {
    {
      type = MISSION_TYPES.DELIVERY,
      id = "shadow_delivery_1",
      title = "No Questions",
      description = "...",
      pickupHint = "You know where",
      dropoffHint = "The usual place",
      timeLimit = 180, -- 3 minutes - very tight
      reward = { money = 1000, xp = 50 },
      requiredLevel = 2,
      heat = 3, -- Maximum heat
      requiresCargo = true,
      cargoSlots = 4, -- Mystery package
      timeCondition = "midnight", -- Darkest hour
    },
    -- Chase missions for Shadow (hardest, most mysterious)
    {
      type = MISSION_TYPES.CHASE,
      id = "shadow_chase_1",
      title = "The Witness",
      description = "Someone saw something. They're running. Sedan heading east. Stop them. Permanently.",
      targetHint = "Sedan heading east",
      difficulty = "medium",
      timeLimit = 240,
      reward = { money = 900, xp = 50 },
      requiredLevel = 2,
      heat = 1,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "shadow_chase_2",
      title = "Loose Thread",
      description = "...",
      targetHint = "You know who",
      difficulty = "hard",
      timeLimit = 180,
      reward = { money = 1500, xp = 75 },
      requiredLevel = 3,
      heat = 2,
      requiresCargo = false,
    },
    {
      type = MISSION_TYPES.CHASE,
      id = "shadow_chase_3",
      title = "Final Solution",
      description = "High priority. Fast car. Dangerous driver. This ends tonight. No mistakes.",
      targetHint = "Unknown vehicle, extremely dangerous",
      difficulty = "hard",
      timeLimit = 150, -- Very tight
      reward = { money = 2000, xp = 100 },
      requiredLevel = 4,
      heat = 3,
      requiresCargo = false,
      timeCondition = "night", -- "This ends tonight"
    },
    {
      type = MISSION_TYPES.SURVEILLANCE,
      id = "shadow_surveillance_1",
      title = "Information Gathering",
      description = "Someone's been asking questions. Find out who. Follow the white van, don't get made.",
      targetDescription = "White van",
      followTime = 240,
      maxDistance = 80,
      minDistance = 30,
      reward = { money = 800, xp = 45 },
      requiredLevel = 3,
      requiresCargo = false,
    },
  },
}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  activeMission = nil, -- Current active mission
  completedMissions = {}, -- { [missionId] = { completedAt, success } }
  missionCooldowns = {}, -- { [contactId] = lastMissionTime }
  availableMissions = {}, -- Currently offered missions
}

-- Cooldown between missions (seconds)
local MISSION_COOLDOWN_BASE = 1800 -- 30 minutes
local MISSION_COOLDOWN_MIN = 600 -- 10 minutes minimum

-- ============================================================================
-- PICKUP LOCATIONS (reuse from parts system)
-- ============================================================================

local pickupLocations = {}
local dropoffLocations = {}

local function buildLocations()
  if #pickupLocations > 0 then return end

  -- Try to get locations from facilities
  local facilities = nil
  if freeroam_facilities and freeroam_facilities.getFacilities then
    facilities = freeroam_facilities.getFacilities()
  end

  if facilities then
    -- Gas stations for pickups
    if facilities.gasStations then
      for _, station in pairs(facilities.gasStations) do
        if station.pos then
          table.insert(pickupLocations, {
            name = "Gas Station",
            pos = vec3(station.pos),
            type = "gas_station"
          })
        end
      end
    end

    -- Garages for dropoffs
    if facilities.garages then
      for _, garage in pairs(facilities.garages) do
        if garage.pos then
          table.insert(dropoffLocations, {
            name = garage.name or "Garage",
            pos = vec3(garage.pos),
            type = "garage"
          })
        end
      end
    end

    -- Dealers can be either
    if facilities.dealerships then
      for _, dealer in pairs(facilities.dealerships) do
        if dealer.pos then
          table.insert(pickupLocations, {
            name = dealer.name or "Dealer",
            pos = vec3(dealer.pos),
            type = "dealer"
          })
          table.insert(dropoffLocations, {
            name = dealer.name or "Dealer",
            pos = vec3(dealer.pos),
            type = "dealer"
          })
        end
      end
    end
  end

  -- Fallback if no facilities found
  if #pickupLocations == 0 then
    -- Add some default positions for west_coast_usa
    table.insert(pickupLocations, {
      name = "Highway Gas Station",
      pos = vec3(-700, 150, 75),
      type = "gas_station"
    })
    table.insert(pickupLocations, {
      name = "Downtown Shop",
      pos = vec3(-780, 440, 102),
      type = "shop"
    })
  end

  if #dropoffLocations == 0 then
    table.insert(dropoffLocations, {
      name = "Industrial Warehouse",
      pos = vec3(-650, 680, 75),
      type = "warehouse"
    })
    table.insert(dropoffLocations, {
      name = "Docks Area",
      pos = vec3(-400, 200, 75),
      type = "docks"
    })
  end

  log("I", logTag, "Built " .. #pickupLocations .. " pickup and " .. #dropoffLocations .. " dropoff locations")
end

local function getRandomLocation(locationList)
  if #locationList == 0 then
    buildLocations()
  end
  if #locationList == 0 then return nil end
  return locationList[math.random(#locationList)]
end

-- ============================================================================
-- TIME TRANSITION (Timelapse)
-- ============================================================================

-- Get the TOD (Time of Day) object from scene
local function getTODObject()
  -- Method 1: Direct access via scenetree.tod
  if scenetree and scenetree.tod then
    return scenetree.tod
  end

  -- Method 2: Find by object name
  if scenetree and scenetree.findObject then
    local tod = scenetree.findObject("tod")
    if tod then return tod end

    -- Try alternative names
    tod = scenetree.findObject("theTOD")
    if tod then return tod end

    tod = scenetree.findObject("TimeOfDay")
    if tod then return tod end
  end

  return nil
end

-- Get current time of day from scenetree
local function getCurrentTimeOfDay()
  -- Try TOD object first
  local tod = getTODObject()
  if tod and tod.time then
    return tod.time
  end

  -- Fallback to core_environment
  if core_environment and core_environment.getTimeOfDay then
    local todData = core_environment.getTimeOfDay()
    if todData and todData.time then
      return todData.time
    end
  end

  log("W", logTag, "Could not get time of day from any source")
  return 0.5 -- default to noon
end

-- Set time of day (uses core_environment.setTimeOfDay for visual update)
local function setTimeOfDay(time)
  -- Wrap time to 0-1 range
  while time < 0 do time = time + 1 end
  while time > 1 do time = time - 1 end

  local success = false

  -- The correct method: Get full TOD object, modify time, then set it back
  -- This triggers the visual refresh (just setting scenetree.tod.time doesn't!)
  if core_environment and core_environment.getTimeOfDay and core_environment.setTimeOfDay then
    local todData = core_environment.getTimeOfDay()
    if todData then
      -- Create a copy and modify time
      local newTod = deepcopy(todData)
      newTod.time = time

      -- Apply the change (this triggers visual update)
      core_environment.setTimeOfDay(newTod)
      success = true
      log("D", logTag, "Set time via core_environment.setTimeOfDay, time = " .. string.format("%.3f", time))
    else
      log("W", logTag, "core_environment.getTimeOfDay() returned nil")
    end
  else
    log("W", logTag, "core_environment not available, trying fallback")

    -- Fallback: try direct scenetree access (may not update visuals)
    local tod = getTODObject()
    if tod then
      tod.time = time
      success = true
      log("D", logTag, "Set time via scenetree.tod.time (fallback, may not update visuals)")
    end
  end

  if not success then
    log("E", logTag, "Failed to set time of day - no valid method available")
  end

  return success
end

-- Start a time transition (visible timelapse)
local function startTimeTransition(targetCondition, pendingMissionId)
  local targetTime = TIME_CONDITIONS[targetCondition]
  if not targetTime then
    log("W", logTag, "Unknown time condition: " .. tostring(targetCondition))
    return false
  end

  local currentTime = getCurrentTimeOfDay()

  -- Check if we're already at the target time (within tolerance)
  local tolerance = 0.02 -- ~30 minutes game time
  local diff = math.abs(currentTime - targetTime)
  -- Handle wrap-around (e.g., 0.95 to 0.05)
  if diff > 0.5 then diff = 1 - diff end

  if diff <= tolerance then
    log("I", logTag, "Already at target time, no transition needed")
    return false -- No transition needed
  end

  -- Calculate shortest path (forward or backward in time)
  local forwardDist = targetTime - currentTime
  if forwardDist < 0 then forwardDist = forwardDist + 1 end
  local backwardDist = currentTime - targetTime
  if backwardDist < 0 then backwardDist = backwardDist + 1 end

  -- Save original time to restore after mission
  if not timeTransitionState.originalTime then
    timeTransitionState.originalTime = currentTime
    log("I", logTag, "Saved original time: " .. string.format("%.3f", currentTime) ..
      " (" .. string.format("%02d:%02d", math.floor(todTimeToHour(currentTime)),
      math.floor((todTimeToHour(currentTime) % 1) * 60)) .. ")")
  end

  -- Always go forward in time (more natural)
  timeTransitionState.active = true
  timeTransitionState.startTime = currentTime
  timeTransitionState.targetTime = targetTime
  timeTransitionState.elapsed = 0
  timeTransitionState.pendingMissionId = pendingMissionId

  -- Duration based on how much time we're skipping
  local timeToSkip = forwardDist
  timeTransitionState.duration = math.max(2.0, math.min(5.0, timeToSkip * 8)) -- 2-5 seconds

  -- Get time name for display
  local timeNames = {
    night = "nighttime",
    midnight = "midnight",
    dawn = "dawn",
    morning = "morning",
    noon = "noon",
    afternoon = "afternoon",
    dusk = "dusk",
    evening = "evening",
  }
  local timeName = timeNames[targetCondition] or targetCondition

  log("I", logTag, string.format("Starting time transition: %.2f -> %.2f (%s), duration: %.1fs",
    currentTime, targetTime, timeName, timeTransitionState.duration))

  -- Show notification
  if guihooks then
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = "Time Passing...",
      msg = "Waiting for " .. timeName,
    })
    -- Notify UI about timelapse
    guihooks.trigger("mysummerTimeTransition", {
      active = true,
      targetCondition = targetCondition,
      duration = timeTransitionState.duration,
    })
  end

  return true
end

-- Update time transition (called in onUpdate)
local function updateTimeTransition(dtReal)
  if not timeTransitionState.active then return false end

  timeTransitionState.elapsed = timeTransitionState.elapsed + dtReal
  local progress = timeTransitionState.elapsed / timeTransitionState.duration

  if progress < 1 then
    -- Calculate current time during transition
    local startT = timeTransitionState.startTime
    local targetT = timeTransitionState.targetTime

    -- Handle wrap-around (going from night to morning crosses midnight)
    local diff = targetT - startT
    if diff < -0.5 then diff = diff + 1 end
    if diff > 0.5 then diff = diff - 1 end

    -- Use easeInOutCubic for smooth transition
    local t
    if progress < 0.5 then
      t = 4 * progress * progress * progress
    else
      t = 1 - math.pow(-2 * progress + 2, 3) / 2
    end

    local currentT = startT + diff * t
    -- Wrap to 0-1
    while currentT < 0 do currentT = currentT + 1 end
    while currentT > 1 do currentT = currentT - 1 end

    -- Log every ~0.5 seconds to avoid spam
    if math.floor(timeTransitionState.elapsed * 2) ~= math.floor((timeTransitionState.elapsed - dtReal) * 2) then
      log("D", logTag, string.format("Time transition: progress=%.1f%%, time=%.3f -> %.3f",
        progress * 100, getCurrentTimeOfDay(), currentT))
    end

    setTimeOfDay(currentT)
    return true -- Still transitioning
  else
    -- Transition complete
    setTimeOfDay(timeTransitionState.targetTime)
    timeTransitionState.active = false

    log("I", logTag, "Time transition complete, target was: " .. string.format("%.3f", timeTransitionState.targetTime))
    log("I", logTag, "Actual time now: " .. string.format("%.3f", getCurrentTimeOfDay()))

    -- Notify UI
    if guihooks then
      guihooks.trigger("mysummerTimeTransition", {
        active = false,
      })
    end

    -- Start pending mission if any
    if timeTransitionState.pendingMissionId then
      local missionId = timeTransitionState.pendingMissionId
      timeTransitionState.pendingMissionId = nil
      -- Actually start the mission now
      startMission(missionId)
    end

    return false -- Transition done
  end
end

-- Restore original time after mission ends (with timelapse)
local function restoreOriginalTime()
  if not timeTransitionState.originalTime then
    return false
  end

  local originalTime = timeTransitionState.originalTime
  local originalHour = todTimeToHour(originalTime)
  log("I", logTag, "Restoring original time: " .. string.format("%02d:%02d",
    math.floor(originalHour), math.floor((originalHour % 1) * 60)))

  -- Clear the saved original time
  timeTransitionState.originalTime = nil

  -- Start transition back to original time
  timeTransitionState.active = true
  timeTransitionState.startTime = getCurrentTimeOfDay()
  timeTransitionState.targetTime = originalTime
  timeTransitionState.elapsed = 0
  timeTransitionState.pendingMissionId = nil
  timeTransitionState.duration = 3.0 -- Faster return transition

  if guihooks then
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = "Time Restoring...",
      msg = "Returning to normal time",
    })
    guihooks.trigger("mysummerTimeTransition", {
      active = true,
      targetCondition = "restore",
      duration = timeTransitionState.duration,
    })
  end

  return true
end

-- Check if a time condition is currently met
local function isTimeConditionMet(condition)
  if not condition then return true end

  local targetTime = TIME_CONDITIONS[condition]
  if not targetTime then return true end

  local currentTime = getCurrentTimeOfDay()
  local tolerance = 0.04 -- ~1 hour game time

  local diff = math.abs(currentTime - targetTime)
  if diff > 0.5 then diff = 1 - diff end

  return diff <= tolerance
end

-- ============================================================================
-- MISSION AVAILABILITY
-- ============================================================================

local function getContactLevel(contactId)
  if not career_modules_playerAttributes then return 1 end

  local attKey = "mysummer-" .. contactId
  local xp = career_modules_playerAttributes.getAttributeValue(attKey) or 0

  if xp >= 600 then return 5
  elseif xp >= 350 then return 4
  elseif xp >= 150 then return 3
  elseif xp >= 50 then return 2
  else return 1
  end
end

local function isContactOnMissionCooldown(contactId)
  local lastTime = state.missionCooldowns[contactId]
  if not lastTime then return false, 0 end

  local now = os.time()
  local level = getContactLevel(contactId)
  local cooldown = math.max(MISSION_COOLDOWN_MIN, MISSION_COOLDOWN_BASE - (level - 1) * 300)
  local elapsed = now - lastTime

  if elapsed < cooldown then
    return true, cooldown - elapsed
  end

  return false, 0
end

local function getAvailableMissionsForContact(contactId)
  local templates = missionTemplates[contactId]
  if not templates then return {} end

  local level = getContactLevel(contactId)
  local available = {}

  for _, template in ipairs(templates) do
    -- Check level requirement
    if level >= (template.requiredLevel or 1) then
      -- Check if not completed recently (or at all for unique missions)
      local completed = state.completedMissions[template.id]
      if not completed or (os.time() - (completed.completedAt or 0)) > 86400 then -- 24 hour cooldown per mission
        table.insert(available, template)
      end
    end
  end

  return available
end

-- ============================================================================
-- MISSION LIFECYCLE
-- ============================================================================

local function generateMission(contactId, templateId)
  local templates = missionTemplates[contactId]
  if not templates then
    log("W", logTag, "No mission templates for contact: " .. tostring(contactId))
    return nil
  end

  -- Find template
  local template = nil
  for _, t in ipairs(templates) do
    if t.id == templateId then
      template = t
      break
    end
  end

  if not template then
    log("W", logTag, "Mission template not found: " .. tostring(templateId))
    return nil
  end

  buildLocations()

  -- Generate mission instance
  local mission = {
    id = template.id .. "_" .. os.time(),
    templateId = template.id,
    contactId = contactId,
    type = template.type,
    title = template.title,
    description = template.description,
    reward = deepcopy(template.reward),
    timeLimit = template.timeLimit,
    heat = template.heat or 0,
    status = "offered", -- offered, active, completed, failed
    createdAt = os.time(),
    timeCondition = template.timeCondition, -- Optional: night, dawn, dusk, etc.
  }

  -- Type-specific setup
  if template.type == MISSION_TYPES.DELIVERY then
    mission.pickupLocation = getRandomLocation(pickupLocations)
    mission.dropoffLocation = getRandomLocation(dropoffLocations)
    mission.pickupHint = template.pickupHint
    mission.dropoffHint = template.dropoffHint
    mission.noDamage = template.noDamage
    mission.pickedUp = false
    mission.requiresCargo = template.requiresCargo ~= false -- default true for delivery
    mission.cargoSlots = template.cargoSlots or 3
  elseif template.type == MISSION_TYPES.FIND_PART then
    mission.partCategory = template.partCategory
    mission.partHint = template.partHint
  elseif template.type == MISSION_TYPES.SURVEILLANCE then
    mission.targetDescription = template.targetDescription
    mission.followTime = template.followTime
    mission.maxDistance = template.maxDistance
    mission.minDistance = template.minDistance
  elseif template.type == MISSION_TYPES.ESCORT then
    mission.maxWaves = template.maxWaves or 5
    mission.enemiesPerWave = template.enemiesPerWave or { 1, 2, 2, 3, 3 }
    mission.waveInterval = template.waveInterval or 25
    mission.requiresCargo = false
    -- Destination will be picked from POIs at mission start
  elseif template.type == MISSION_TYPES.CHASE then
    mission.difficulty = template.difficulty or "medium"
    mission.targetHint = template.targetHint
    mission.requiresCargo = false
  end

  return mission
end

-- Uses forward-declared variable
startMission = function(missionId)
  -- Find mission in available missions
  local mission = nil
  for _, m in ipairs(state.availableMissions) do
    if m.id == missionId then
      mission = m
      break
    end
  end

  if not mission then
    log("W", logTag, "Mission not found: " .. tostring(missionId))
    return false
  end

  if state.activeMission then
    log("W", logTag, "Already have an active mission")
    return false
  end

  -- Check if mission has a time condition
  if mission.timeCondition then
    if not isTimeConditionMet(mission.timeCondition) then
      -- Need to transition time first
      log("I", logTag, "Mission requires time condition: " .. mission.timeCondition .. ", starting transition")
      if startTimeTransition(mission.timeCondition, missionId) then
        -- Transition started, mission will be started when complete
        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "info",
            title = "Time Required",
            msg = "This job needs to happen at " .. mission.timeCondition .. "...",
          })
        end
        return true -- Return true since we're handling it
      end
      -- If transition failed (already at time), continue with mission start
    end
  end

  -- Activate mission
  mission.status = "active"
  mission.startedAt = os.time()
  state.activeMission = mission

  -- Reset time warnings
  resetTimeWarnings()

  -- Remove from available
  for i, m in ipairs(state.availableMissions) do
    if m.id == missionId then
      table.remove(state.availableMissions, i)
      break
    end
  end

  -- Set waypoint to first objective
  if mission.type == MISSION_TYPES.DELIVERY and mission.pickupLocation then
    if core_groundMarkers then
      core_groundMarkers.setPath(mission.pickupLocation.pos, { clearPathOnReachingTarget = true })
    end
  end

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerMissionStarted", {
      id = mission.id,
      title = mission.title,
      type = mission.type,
      timeLimit = mission.timeLimit,
    })
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = "Mission Started",
      msg = mission.title,
    })
  end

  log("I", logTag, "Mission started: " .. mission.title)
  saveState()
  return true
end

local function completeMission(success)
  if not state.activeMission then
    log("W", logTag, "No active mission to complete")
    return false
  end

  local mission = state.activeMission
  -- CRITICAL: Clear activeMission FIRST to prevent respawn race condition
  state.activeMission = nil

  log("I", logTag, "====== COMPLETING MISSION ======")
  log("I", logTag, "Mission: " .. mission.title .. " | Success: " .. tostring(success))
  log("I", logTag, "Type: " .. mission.type .. " | ID: " .. mission.id)

  mission.status = success and "completed" or "failed"
  mission.completedAt = os.time()

  -- Record completion
  state.completedMissions[mission.templateId] = {
    completedAt = mission.completedAt,
    success = success,
  }

  -- Set cooldown for contact
  state.missionCooldowns[mission.contactId] = os.time()

  -- Award rewards if successful
  if success and mission.reward then
    if mission.reward.money and career_modules_payment then
      career_modules_payment.reward({ money = { amount = mission.reward.money, reason = "Mission: " .. mission.title } })
      log("I", logTag, "Awarded $" .. mission.reward.money .. " for mission")
    end

    -- Award reputation points via mysummerCareer
    if mission.reward.xp and career_modules_mysummerCareer and career_modules_mysummerCareer.addReputationPoints then
      career_modules_mysummerCareer.addReputationPoints(mission.reward.xp, "Mission: " .. mission.title)
      log("I", logTag, "Awarded " .. mission.reward.xp .. " reputation for mission")
    end
  end

  -- Cleanup mission-specific state
  if mission.type == MISSION_TYPES.CHASE then
    cleanupChaseTarget()
  elseif mission.type == MISSION_TYPES.SURVEILLANCE then
    cleanupSurveillanceTarget()
  elseif mission.type == MISSION_TYPES.ESCORT then
    cleanupEscortMission()
  end

  -- Restore original time if mission had a time condition
  if mission.timeCondition then
    restoreOriginalTime()
  end

  -- Clear navigation
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerMissionCompleted", {
      id = mission.id,
      title = mission.title,
      success = success,
      reward = success and mission.reward or nil,
    })
    guihooks.trigger("toastrMsg", {
      type = success and "success" or "error",
      title = success and "Mission Complete" or "Mission Failed",
      msg = mission.title,
    })
  end

  log("I", logTag, "Mission " .. (success and "completed" or "failed") .. ": " .. mission.title)

  -- state.activeMission already cleared at start of function
  saveState()
  return true
end

local function abandonMission()
  if not state.activeMission then return false end

  local mission = state.activeMission
  -- CRITICAL: Clear activeMission FIRST to prevent respawn race condition
  state.activeMission = nil

  log("I", logTag, "Mission abandoned: " .. mission.title)

  -- Cleanup mission-specific state
  if mission.type == MISSION_TYPES.CHASE then
    cleanupChaseTarget()
  elseif mission.type == MISSION_TYPES.SURVEILLANCE then
    cleanupSurveillanceTarget()
  elseif mission.type == MISSION_TYPES.ESCORT then
    cleanupEscortMission()
  end

  -- Restore original time if mission had a time condition
  if mission.timeCondition then
    restoreOriginalTime()
  end

  -- Clear navigation
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerMissionAbandoned", { id = mission.id })
    guihooks.trigger("toastrMsg", {
      type = "warning",
      title = "Mission Abandoned",
      msg = mission.title,
    })
  end

  -- state.activeMission already cleared at start of function
  saveState()
  return true
end

-- Answer the surveillance quiz
-- answer can be either:
--   - An index (1, 2, 3) from the UI buttons
--   - A string (location name) for direct testing
local function answerSurveillanceQuiz(answer)
  if not state.activeMission then
    log("W", logTag, "No active mission for quiz answer")
    return false
  end

  if state.activeMission.type ~= MISSION_TYPES.SURVEILLANCE then
    log("W", logTag, "Active mission is not surveillance")
    return false
  end

  if not surveillanceState.quizPhase then
    log("W", logTag, "Not in quiz phase")
    return false
  end

  -- Convert index to location name if needed
  local selectedOption = answer
  if type(answer) == "number" then
    -- UI sends 1-indexed selection
    selectedOption = surveillanceState.quizOptions[answer]
    if not selectedOption then
      log("W", logTag, "Invalid quiz answer index: " .. tostring(answer))
      return false
    end
    log("I", logTag, "Quiz answer index: " .. tostring(answer) .. " -> " .. selectedOption)
  end

  log("I", logTag, "Selected option: " .. tostring(selectedOption))
  log("I", logTag, "Correct answer: " .. tostring(surveillanceState.correctAnswer))

  local isCorrect = (selectedOption == surveillanceState.correctAnswer)

  if isCorrect then
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "success",
        title = "Correct!",
        msg = "You tracked them to " .. surveillanceState.correctAnswer,
      })
    end
    completeMission(true)
  else
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "error",
        title = "Wrong Location!",
        msg = "They actually went to " .. surveillanceState.correctAnswer,
      })
    end
    completeMission(false)
  end

  return isCorrect
end

-- ============================================================================
-- MISSION UPDATES
-- ============================================================================

-- Attempt to pick up mission cargo (requires cargo space if requiresCargo=true)
local function attemptMissionPickup()
  local mission = state.activeMission
  if not mission or mission.type ~= MISSION_TYPES.DELIVERY then return end
  if mission.pickedUp then return end

  -- Check if this mission requires cargo
  if not mission.requiresCargo then
    -- No cargo needed, just mark as picked up
    mission.pickedUp = true

    -- Set waypoint to dropoff
    if mission.dropoffLocation and core_groundMarkers then
      core_groundMarkers.setPath(mission.dropoffLocation.pos, { clearPathOnReachingTarget = true })
    end

    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "info",
        title = "Location Confirmed",
        msg = "Now head to the destination.",
      })
    end

    log("I", logTag, "Mission pickup (no cargo) complete")
    saveState()
    return
  end

  -- Mission requires cargo - check cargo module
  local cargoModule = career_modules_mysummerCargo
  if not cargoModule then
    log("W", logTag, "Cargo module not available, allowing pickup anyway")
    mission.pickedUp = true
    saveState()
    return
  end

  -- Check cargo space first (use cargoSlots from mission or default to 3)
  local slotsNeeded = mission.cargoSlots or 3
  cargoModule.checkCargoSpace({{ partName = "parcel", slots = slotsNeeded }}, function(result)
    if not result.canLoad then
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "error",
          title = "No Cargo Space",
          msg = "You need " .. slotsNeeded .. " cargo slots to pick up this package!",
        })
      end
      return
    end

    -- Load cargo into vehicle
    local cargoData = {
      partName = "mission_cargo",
      partNiceName = "Mission Package: " .. mission.title,
      slots = slotsNeeded,
    }

    -- Destination is the dropoff location
    local destData = nil
    if mission.dropoffLocation then
      destData = { pos = mission.dropoffLocation.pos }
    end

    cargoModule.loadPartIntoCargo(cargoData, function(success, cargoId)
      if success then
        mission.pickedUp = true
        mission.cargoId = cargoId

        -- Set waypoint to dropoff
        if mission.dropoffLocation and core_groundMarkers then
          core_groundMarkers.setPath(mission.dropoffLocation.pos, { clearPathOnReachingTarget = true })
        end

        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "info",
            title = "Package Loaded",
            msg = "Deliver to destination. Time is ticking!",
          })
          -- Update mission UI with new state
          guihooks.trigger("mysummerMissionUpdate", {
            id = mission.id,
            pickedUp = true,
            dropoffHint = mission.dropoffHint,
          })
        end

        log("I", logTag, "Mission cargo loaded, cargoId: " .. tostring(cargoId))
        saveState()
      else
        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "error",
            title = "Pickup Failed",
            msg = tostring(cargoId) or "Could not load cargo",
          })
        end
      end
    end, destData)
  end)
end

-- Attempt to deliver mission cargo
local function attemptMissionDelivery()
  local mission = state.activeMission
  if not mission or mission.type ~= MISSION_TYPES.DELIVERY then return end
  if not mission.pickedUp then return end

  -- Unload cargo if we have a cargo ID
  if mission.cargoId then
    local cargoModule = career_modules_mysummerCargo
    if cargoModule and cargoModule.unloadCargoItem then
      cargoModule.unloadCargoItem(mission.cargoId)
      log("I", logTag, "Mission cargo unloaded: " .. tostring(mission.cargoId))
    end
  end

  completeMission(true)
end

-- Calculate 2D distance (ignoring Z height)
local function distance2D(pos1, pos2)
  local dx = pos1.x - pos2.x
  local dy = pos1.y - pos2.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Get surveillance destinations from map facilities
local cachedDestinations = nil
local cachedDestinationsLevel = nil

local function getSurveillanceDestinations()
  local levelName = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or "unknown"

  -- Use cache if available for this level
  if cachedDestinations and cachedDestinationsLevel == levelName then
    return cachedDestinations
  end

  cachedDestinations = {}
  cachedDestinationsLevel = levelName

  -- Get facilities from freeroam_facilities
  local freeroam_facilities = require("freeroam/facilities")
  if not freeroam_facilities then
    log("W", logTag, "freeroam_facilities not available for destinations")
    return cachedDestinations
  end

  local facilities = freeroam_facilities.getFacilities(levelName)
  if not facilities then
    log("W", logTag, "No facilities found for level: " .. levelName)
    return cachedDestinations
  end

  -- Collect all facilities with valid positions and names
  for groupName, group in pairs(facilities) do
    if type(group) == "table" then
      for facilityId, facility in pairs(group) do
        if type(facility) == "table" and facility.name then
          local pos = nil

          -- Try getAverageDoorPositionForFacility first
          if freeroam_facilities.getAverageDoorPositionForFacility then
            pos = freeroam_facilities.getAverageDoorPositionForFacility(facility)
          end

          -- Fallback to facility.pos
          if not pos and facility.pos then
            pos = vec3(facility.pos.x or facility.pos[1], facility.pos.y or facility.pos[2], facility.pos.z or facility.pos[3])
          end

          -- Fallback to parking spots
          if not pos and freeroam_facilities.getParkingSpotsForFacility then
            local spots = freeroam_facilities.getParkingSpotsForFacility(facility)
            if spots and #spots > 0 and spots[1] and spots[1].pos then
              local sp = spots[1].pos
              pos = vec3(sp.x or sp[1], sp.y or sp[2], sp.z or sp[3])
            end
          end

          if pos and pos.x and pos.y then
            table.insert(cachedDestinations, {
              name = facility.name,
              pos = pos,
              type = groupName,
            })
          end
        end
      end
    end
  end

  log("I", logTag, "Found " .. #cachedDestinations .. " surveillance destinations")
  return cachedDestinations
end

-- Pick a random destination and generate quiz options
local function pickSurveillanceDestination()
  local destinations = getSurveillanceDestinations()
  if #destinations < 3 then
    log("W", logTag, "Not enough destinations for quiz (need 3, have " .. #destinations .. ")")
    return nil, {}
  end

  -- Shuffle and pick random destination
  local shuffled = {}
  for i, dest in ipairs(destinations) do
    shuffled[i] = dest
  end
  for i = #shuffled, 2, -1 do
    local j = math.random(i)
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end

  local correctDest = shuffled[1]

  -- Pick 2 other random destinations as wrong answers
  local options = { correctDest.name }
  for i = 2, #shuffled do
    if #options >= 3 then break end
    -- Avoid duplicates
    local isDupe = false
    for _, opt in ipairs(options) do
      if opt == shuffled[i].name then
        isDupe = true
        break
      end
    end
    if not isDupe then
      table.insert(options, shuffled[i].name)
    end
  end

  -- Shuffle the options so correct isn't always first
  for i = #options, 2, -1 do
    local j = math.random(i)
    options[i], options[j] = options[j], options[i]
  end

  log("I", logTag, "Surveillance destination: " .. correctDest.name)
  log("I", logTag, "Quiz options: " .. table.concat(options, ", "))

  return correctDest, options
end

local function checkDeliveryProgress()
  local mission = state.activeMission
  if not mission or mission.type ~= MISSION_TYPES.DELIVERY then return end

  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return end

  local playerPos = playerVehicle:getPosition()

  -- Check pickup (use 2D distance to ignore terrain height differences)
  if not mission.pickedUp and mission.pickupLocation then
    local targetPos = toVec3(mission.pickupLocation.pos)
    if targetPos then
      local dist = distance2D(playerPos, targetPos)
      if dist < 25 then
        log("I", logTag, "Near pickup! Distance: " .. string.format("%.1f", dist) .. "m")
        attemptMissionPickup()
      end
    else
      log("E", logTag, "Invalid pickup position!")
    end
  end

  -- Check dropoff (use 2D distance)
  if mission.pickedUp and mission.dropoffLocation then
    local targetPos = toVec3(mission.dropoffLocation.pos)
    if targetPos then
      local dist = distance2D(playerPos, targetPos)
      if dist < 25 then
        log("I", logTag, "Near dropoff! Distance: " .. string.format("%.1f", dist) .. "m")
        attemptMissionDelivery()
      end
    else
      log("E", logTag, "Invalid dropoff position!")
    end
  end
end

-- ============================================================================
-- CHASE MISSION FUNCTIONS
-- ============================================================================

-- Get a random spawn point for chase target ON A ROAD (away from player but not too far)
local function getChaseSpawnPoint()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return nil, nil end

  local playerPos = playerVehicle:getPosition()

  -- Load traffic utils if not loaded
  if not gameplay_traffic_trafficUtils then
    extensions.load('gameplay_traffic_trafficUtils')
  end

  -- Try to find a road spawn point using traffic utils
  if gameplay_traffic_trafficUtils and gameplay_traffic_trafficUtils.findSpawnPointRadial then
    local options = {
      gap = 20,
      usePrivateRoads = false,
      minDrivability = 0.5,
      minRadius = 1.0,
      pathRandomization = 0.1
    }

    -- Try multiple random directions to find a valid road spawn
    -- Spawn closer so target is visible and "waiting"
    for i = 1, 5 do
      local randomAngle = math.random() * math.pi * 2
      local searchDir = vec3(math.cos(randomAngle), math.sin(randomAngle), 0)
      local minDist = 80
      local maxDist = 150

      local spawnData, isValid = gameplay_traffic_trafficUtils.findSpawnPointRadial(
        playerPos, searchDir, minDist, maxDist, minDist * 1.2, options)

      if isValid and spawnData and spawnData.pos then
        local finalPos, finalDir = gameplay_traffic_trafficUtils.finalizeSpawnPoint(
          spawnData.pos, spawnData.dir, spawnData.n1, spawnData.n2,
          { legalDirection = true, dirRandomization = 0.3 })

        if finalPos then
          log("I", logTag, "Found road spawn point at attempt " .. i)
          return finalPos, finalDir
        end
      end
    end

    log("W", logTag, "Could not find road spawn via traffic utils, using fallback")
  end

  -- Fallback: use map.findClosestRoad if available
  if map and map.findClosestRoad and map.getMap then
    local mapData = map.getMap()
    local angle = math.random() * 2 * math.pi
    local distance = 80 + math.random() * 70  -- 80-150m

    local targetX = playerPos.x + math.cos(angle) * distance
    local targetY = playerPos.y + math.sin(angle) * distance
    local targetPos = vec3(targetX, targetY, playerPos.z)

    local roadName, nodeIdx, roadDist = map.findClosestRoad(targetPos)
    if roadName and mapData.nodes then
      -- Get the actual road node position
      local nodeData = mapData.nodes[nodeIdx]
      if nodeData and nodeData.pos then
        local roadPos = vec3(nodeData.pos)
        -- Get proper ground height
        local groundZ = be:getSurfaceHeightBelow(vec3(roadPos.x, roadPos.y, roadPos.z + 50))
        if groundZ then
          roadPos.z = groundZ + 0.5
        end
        log("I", logTag, "Found road spawn via map.findClosestRoad")
        return roadPos, nil
      end
    end
  end

  -- Last resort fallback
  log("W", logTag, "Using last resort spawn fallback")
  local angle = math.random() * 2 * math.pi
  local distance = 200
  local targetX = playerPos.x + math.cos(angle) * distance
  local targetY = playerPos.y + math.sin(angle) * distance
  local groundZ = be:getSurfaceHeightBelow(vec3(targetX, targetY, playerPos.z + 100))
  return vec3(targetX, targetY, groundZ or playerPos.z), nil
end

-- Spawn chase target vehicle
local function spawnChaseTarget(mission)
  if chaseState.targetSpawned then
    log("W", logTag, "Chase target already spawned!")
    return false
  end

  local difficulty = mission.difficulty or "medium"
  local vehicleList = CHASE_VEHICLES[difficulty] or CHASE_VEHICLES.medium

  if #vehicleList == 0 then
    log("E", logTag, "No vehicles defined for difficulty: " .. difficulty)
    return false
  end

  -- Pick random vehicle from list
  local vehicleInfo = vehicleList[math.random(#vehicleList)]
  local spawnPos, spawnDir = getChaseSpawnPoint()

  if not spawnPos then
    log("E", logTag, "Could not find spawn point for chase target")
    return false
  end

  -- Calculate rotation from road direction, or use random if no direction
  local rot
  if spawnDir then
    -- Create rotation from direction vector
    local up = vec3(0, 0, 1)
    rot = quatFromDir(spawnDir, up)
  else
    -- Random rotation as fallback
    rot = quat(0, 0, math.sin(math.random() * math.pi), math.cos(math.random() * math.pi))
  end

  -- Spawn the vehicle
  local spawnOptions = {
    config = vehicleInfo.config,
    pos = spawnPos,
    rot = rot,
    autoEnterVehicle = false,
  }

  log("I", logTag, "Spawning chase target: " .. vehicleInfo.model .. " / " .. vehicleInfo.config)

  local vehicle = core_vehicles.spawnNewVehicle(vehicleInfo.model, spawnOptions)

  if vehicle then
    local vehId = vehicle:getID()
    chaseState.targetVehicleId = vehId
    chaseState.targetSpawned = true
    chaseState.targetFleeing = false  -- Target starts waiting, not fleeing
    chaseState.stoppedTimer = 0

    -- Start AI in STOP mode - waiting for player to approach
    -- Will switch to FLEE mode when player gets within fleeDistance
    vehicle:queueLuaCommand('ai.setMode("stop")')

    -- Set waypoint to chase target
    if core_groundMarkers then
      core_groundMarkers.setPath(spawnPos, { clearPathOnReachingTarget = false })
    end

    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "info",
        title = "Target Located",
        msg = mission.targetHint or "Approach to start the chase!",
      })
    end

    log("I", logTag, "Chase target spawned at " .. tostring(spawnPos) .. ", ID: " .. vehId)
    return true
  else
    log("E", logTag, "Failed to spawn chase target vehicle")
    return false
  end
end

-- Cleanup chase target vehicle
cleanupChaseTarget = function()
  if chaseState.targetVehicleId then
    local vehicle = be:getObjectByID(chaseState.targetVehicleId)
    if vehicle then
      vehicle:delete()
      log("I", logTag, "Chase target vehicle deleted")
    end
  end

  chaseState.targetVehicleId = nil
  chaseState.targetSpawned = false
  chaseState.targetFleeing = false
  chaseState.stoppedTimer = 0

  -- Clear chase UI
  if guihooks then
    guihooks.trigger("mysummerChaseUpdate", nil)
  end
end

-- Check chase mission progress
local function checkChaseProgress(dtReal)
  local mission = state.activeMission
  if not mission or mission.type ~= MISSION_TYPES.CHASE then return end

  -- Spawn target if not yet spawned
  if not chaseState.targetSpawned then
    if not spawnChaseTarget(mission) then
      -- Failed to spawn, abort mission
      log("E", logTag, "Failed to spawn chase target, aborting mission")
      completeMission(false)
      return
    end
  end

  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return end

  local targetVehicle = be:getObjectByID(chaseState.targetVehicleId)
  if not targetVehicle then
    log("W", logTag, "Chase target vehicle not found!")
    return
  end

  local playerPos = playerVehicle:getPosition()
  local targetPos = targetVehicle:getPosition()
  local distance = distance2D(playerPos, targetPos)

  -- Update waypoint to target position
  if core_groundMarkers then
    core_groundMarkers.setPath(targetPos, { clearPathOnReachingTarget = false })
  end

  -- Get target speed
  local targetVel = targetVehicle:getVelocity()
  local targetSpeed = targetVel:length() -- m/s

  -- Check if player is close enough to trigger flee mode
  if not chaseState.targetFleeing and distance < chaseState.fleeDistance then
    chaseState.targetFleeing = true
    local playerVehId = be:getPlayerVehicleID(0)

    -- Activate flee mode!
    targetVehicle:queueLuaCommand('ai.setMode("flee")')
    targetVehicle:queueLuaCommand('ai.setTargetObjectID(' .. playerVehId .. ')')
    targetVehicle:queueLuaCommand('ai.setAggression(0.8)')
    targetVehicle:queueLuaCommand('ai.setSpeedMode("off")')
    targetVehicle:queueLuaCommand('ai.driveInLane("off")')

    log("I", logTag, "Target spotted player! Fleeing!")
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "warning",
        title = "They're running!",
        msg = "Chase them down!",
      })
    end
  end

  -- Check if target escaped
  if distance > chaseState.escapeDistance then
    log("I", logTag, "Target escaped! Distance: " .. string.format("%.1f", distance) .. "m")
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "error",
        title = "Target Escaped!",
        msg = "They got too far away!",
      })
    end
    cleanupChaseTarget()
    completeMission(false)
    return
  end

  -- Determine chase state for UI
  local isInCatchRange = distance < chaseState.catchDistance
  local isTargetStopped = targetSpeed < chaseState.stoppedSpeed

  -- Check if player is close enough and target is stopped
  if isInCatchRange and isTargetStopped then
    chaseState.stoppedTimer = chaseState.stoppedTimer + dtReal

    if chaseState.stoppedTimer >= chaseState.requiredStopTime then
      log("I", logTag, "Target stopped! Chase complete!")
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "success",
          title = "Target Stopped!",
          msg = "You caught them!",
        })
      end
      cleanupChaseTarget()
      completeMission(true)
      return
    end
  else
    -- Reset timer if not close or target moving
    chaseState.stoppedTimer = 0
  end

  -- Send chase update to UI (every frame for smooth updates)
  if guihooks then
    guihooks.trigger("mysummerChaseUpdate", {
      distance = math.floor(distance),                    -- meters
      targetSpeed = math.floor(targetSpeed * 3.6),        -- km/h
      maxDistance = chaseState.escapeDistance,            -- for progress bar
      catchDistance = chaseState.catchDistance,           -- for UI indicator
      fleeDistance = chaseState.fleeDistance,             -- distance to trigger flee
      isTargetFleeing = chaseState.targetFleeing,         -- is target running?
      isInCatchRange = isInCatchRange,                    -- close enough to catch
      isTargetStopped = isTargetStopped,                  -- target not moving
      stoppedProgress = chaseState.stoppedTimer / chaseState.requiredStopTime, -- 0-1
      missionTitle = mission.title,
    })
  end

  -- Periodic log update (every ~2 seconds via random chance to avoid spam)
  if math.random() < 0.02 then
    log("I", logTag, string.format("Chase: distance=%.1fm, targetSpeed=%.1fm/s", distance, targetSpeed))
  end
end

-- ============================================================================
-- SURVEILLANCE MISSION FUNCTIONS
-- ============================================================================

-- Get spawn point for surveillance target (AHEAD of player, closer than chase)
local function getSurveillanceSpawnPoint()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return nil, nil end

  local playerPos = playerVehicle:getPosition()
  local playerDir = playerVehicle:getDirectionVector()

  -- Load traffic utils if not loaded
  if not gameplay_traffic_trafficUtils then
    extensions.load('gameplay_traffic_trafficUtils')
  end

  -- Try to find a road spawn point AHEAD of player
  if gameplay_traffic_trafficUtils and gameplay_traffic_trafficUtils.findSpawnPointRadial then
    local options = {
      gap = 15,
      usePrivateRoads = false,
      minDrivability = 0.5,
      minRadius = 1.0,
      pathRandomization = 0.1
    }

    -- First try spawning ahead of player (where they're going)
    local searchDir = vec3(playerDir.x, playerDir.y, 0):normalized()
    local minDist = 50
    local maxDist = 100

    for i = 1, 3 do
      -- Add some randomization to the angle (±45 degrees from forward)
      local angleOffset = (math.random() - 0.5) * math.pi * 0.5
      local rotatedDir = vec3(
        searchDir.x * math.cos(angleOffset) - searchDir.y * math.sin(angleOffset),
        searchDir.x * math.sin(angleOffset) + searchDir.y * math.cos(angleOffset),
        0
      )

      local spawnData, isValid = gameplay_traffic_trafficUtils.findSpawnPointRadial(
        playerPos, rotatedDir, minDist, maxDist, minDist * 1.2, options)

      if isValid and spawnData and spawnData.pos then
        local finalPos, finalDir = gameplay_traffic_trafficUtils.finalizeSpawnPoint(
          spawnData.pos, spawnData.dir, spawnData.n1, spawnData.n2,
          { legalDirection = true, dirRandomization = 0.2 })

        if finalPos then
          log("I", logTag, "Found surveillance spawn ahead of player at attempt " .. i)
          return finalPos, finalDir
        end
      end
    end

    -- Fallback: try any direction but closer
    for i = 1, 3 do
      local randomAngle = math.random() * math.pi * 2
      searchDir = vec3(math.cos(randomAngle), math.sin(randomAngle), 0)

      local spawnData, isValid = gameplay_traffic_trafficUtils.findSpawnPointRadial(
        playerPos, searchDir, minDist, maxDist, minDist * 1.2, options)

      if isValid and spawnData and spawnData.pos then
        local finalPos, finalDir = gameplay_traffic_trafficUtils.finalizeSpawnPoint(
          spawnData.pos, spawnData.dir, spawnData.n1, spawnData.n2,
          { legalDirection = true, dirRandomization = 0.2 })

        if finalPos then
          log("I", logTag, "Found surveillance spawn (any dir) at attempt " .. (3 + i))
          return finalPos, finalDir
        end
      end
    end

    log("W", logTag, "Could not find surveillance spawn, using chase fallback")
  end

  -- Fallback to chase spawn point
  return getChaseSpawnPoint()
end

-- Spawn surveillance target vehicle
local function spawnSurveillanceTarget(mission)
  if surveillanceState.targetSpawned then
    log("W", logTag, "Surveillance target already spawned!")
    return false
  end

  -- Pick random vehicle from list
  local vehicleInfo = SURVEILLANCE_VEHICLES[math.random(#SURVEILLANCE_VEHICLES)]
  -- Use surveillance-specific spawn (closer, ahead of player)
  local spawnPos, spawnDir = getSurveillanceSpawnPoint()

  if not spawnPos then
    log("E", logTag, "Could not find spawn point for surveillance target")
    return false
  end

  -- Calculate rotation
  local rot
  if spawnDir then
    local up = vec3(0, 0, 1)
    rot = quatFromDir(spawnDir, up)
  else
    rot = quat(0, 0, math.sin(math.random() * math.pi), math.cos(math.random() * math.pi))
  end

  -- Spawn options
  local spawnOptions = {
    config = vehicleInfo.config,
    pos = spawnPos,
    rot = rot,
    autoEnterVehicle = false,
  }

  log("I", logTag, "Spawning surveillance target: " .. vehicleInfo.model .. " / " .. vehicleInfo.config)

  local vehicle = core_vehicles.spawnNewVehicle(vehicleInfo.model, spawnOptions)

  if vehicle then
    local vehId = vehicle:getID()
    surveillanceState.targetVehicleId = vehId
    surveillanceState.targetSpawned = true
    surveillanceState.detectionMeter = 0
    surveillanceState.followTimer = 0
    surveillanceState.requiredFollowTime = mission.followTime or 180
    -- Reset warning flags
    surveillanceState.warnedTooClose = false
    surveillanceState.warnedTooFar = false
    surveillanceState.warnedDetection50 = false
    surveillanceState.warnedDetection75 = false
    surveillanceState.warnedOncoming = false
    -- Reset advanced detection state
    surveillanceState.targetFound = false
    surveillanceState.initialWaypointCleared = false
    -- Set destination and quiz state (dynamic: will be updated when target stops)
    surveillanceState.destination = nil  -- Will be set dynamically
    surveillanceState.destinationReached = false
    surveillanceState.quizPhase = false
    surveillanceState.quizOptions = {}
    surveillanceState.correctAnswer = nil
    surveillanceState.vehicleDesc = vehicleInfo.desc or "vehicle"
    -- Dynamic destination tracking
    surveillanceState.targetStoppedTime = 0
    surveillanceState.minFollowTime = mission.minFollowTime or 60  -- At least 60 seconds of following
    surveillanceState.allDestinations = getSurveillanceDestinations() -- Cache all possible destinations
    surveillanceState.currentDestination = nil  -- Will be set when target starts driving
    -- Startup delay (gives player time to see the target)
    surveillanceState.startupTimer = 0
    surveillanceState.targetStarted = false
    surveillanceState.targetAggression = vehicleInfo.aggression or 0.5
    -- Reset flee chase state
    surveillanceState.fleeChaseActive = false
    surveillanceState.fleeChaseTimer = 0
    surveillanceState.fleeChaseStoppedTimer = 0
    -- Reset collision detection
    surveillanceState.lastTargetDamage = 0
    surveillanceState.collisionDetected = false

    -- Start in STOP mode - will switch to traffic mode after startup delay
    vehicle:queueLuaCommand('ai.setMode("stop")')

    -- Set waypoint to target vehicle (not destination - player doesn't know where target is going)
    if core_groundMarkers then
      core_groundMarkers.setPath(spawnPos, { clearPathOnReachingTarget = false })
    end

    -- Use actual vehicle description instead of mission template
    local vehicleDesc = vehicleInfo.desc or "vehicle"

    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "info",
        title = "Target Spotted",
        msg = "Follow the " .. vehicleDesc .. ". Find out where they're going!",
      })
    end

    log("I", logTag, "Surveillance target spawned: " .. vehicleDesc .. " at " .. tostring(spawnPos) .. ", ID: " .. vehId)
    return true
  else
    log("E", logTag, "Failed to spawn surveillance target vehicle")
    return false
  end
end

-- Cleanup surveillance target (uses forward-declared variable)
cleanupSurveillanceTarget = function()
  if surveillanceState.targetVehicleId then
    local vehicle = be:getObjectByID(surveillanceState.targetVehicleId)
    if vehicle then
      vehicle:delete()
      log("I", logTag, "Surveillance target vehicle deleted")
    end
  end

  surveillanceState.targetVehicleId = nil
  surveillanceState.targetSpawned = false
  surveillanceState.detectionMeter = 0
  surveillanceState.followTimer = 0
  surveillanceState.targetFound = false
  surveillanceState.initialWaypointCleared = false
  surveillanceState.currentDestination = nil
  -- Reset flee chase state
  surveillanceState.fleeChaseActive = false
  surveillanceState.fleeChaseTimer = 0
  surveillanceState.fleeChaseStoppedTimer = 0

  -- Clear surveillance UI
  if guihooks then
    guihooks.trigger("mysummerSurveillanceUpdate", nil)
  end
end

-- Check surveillance mission progress
local function checkSurveillanceProgress(dtReal)
  local mission = state.activeMission
  if not mission or mission.type ~= MISSION_TYPES.SURVEILLANCE then return end

  -- Spawn target if not yet spawned
  if not surveillanceState.targetSpawned then
    if not spawnSurveillanceTarget(mission) then
      log("E", logTag, "Failed to spawn surveillance target, aborting mission")
      completeMission(false)
      return
    end
  end

  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return end

  local targetVehicle = be:getObjectByID(surveillanceState.targetVehicleId)
  if not targetVehicle then
    log("W", logTag, "Surveillance target vehicle not found!")
    return
  end

  -- Handle startup delay - target waits before starting to drive
  if not surveillanceState.targetStarted then
    surveillanceState.startupTimer = surveillanceState.startupTimer + dtReal
    if surveillanceState.startupTimer >= surveillanceState.startupDelay then
      -- Start the target driving TO A SPECIFIC DESTINATION
      surveillanceState.targetStarted = true

      -- Pick a random destination from available destinations
      local destinations = surveillanceState.allDestinations or {}
      if #destinations > 0 then
        local destIndex = math.random(1, #destinations)
        surveillanceState.currentDestination = destinations[destIndex]
        local destPos = surveillanceState.currentDestination.pos
        local destName = surveillanceState.currentDestination.name or "unknown"

        log("I", logTag, "Surveillance target driving to: " .. destName .. " at " .. tostring(destPos))

        -- Calculate path on game engine side and send directly to vehicle
        local startPos = targetVehicle:getPosition()
        local path = map.getPointToPointPath(startPos, destPos, 0, 1000, 200, 10000, 1)

        if path and #path > 0 then
          log("I", logTag, "Calculated path with " .. #path .. " nodes to destination")

          -- Use driveUsingPathWithTraffic - this handles traffic avoidance properly
          -- This is what driver.lua uses
          local pathStr = serialize(path)
          targetVehicle:queueLuaCommand('ai.driveUsingPathWithTraffic({wpTargetList=' .. pathStr .. ', routeSpeedMode="legal"})')
          -- Set parameters for traffic awareness (from driver.lua)
          targetVehicle:queueLuaCommand('ai.setParameters({trafficWaitTime=0.005, lookAheadKv=0.01, awarenessForceCoef=0.02})')
          targetVehicle:queueLuaCommand('ai.setAvoidCars("on")')
          targetVehicle:queueLuaCommand('ai.driveInLane("on")')

          log("I", logTag, "Sent path to surveillance target via driveUsingPathWithTraffic")
        else
          log("W", logTag, "Could not calculate path to destination, using traffic mode")
          -- Fallback to traffic mode
          local aggression = surveillanceState.targetAggression or 0.5
          targetVehicle:queueLuaCommand('ai.setMode("traffic")')
          targetVehicle:queueLuaCommand('ai.setSpeedMode("legal")')
          targetVehicle:queueLuaCommand('ai.driveInLane("on")')
          targetVehicle:queueLuaCommand('ai.setAggression(' .. tostring(aggression) .. ')')
        end
      else
        -- Fallback to traffic mode if no destinations
        log("W", logTag, "No destinations available, using traffic mode")
        local aggression = surveillanceState.targetAggression or 0.5
        targetVehicle:queueLuaCommand('ai.setMode("traffic")')
        targetVehicle:queueLuaCommand('ai.setSpeedMode("legal")')
        targetVehicle:queueLuaCommand('ai.driveInLane("on")')
        targetVehicle:queueLuaCommand('ai.setAggression(' .. tostring(aggression) .. ')')
      end

      log("I", logTag, "Surveillance target started driving after " .. string.format("%.1f", surveillanceState.startupTimer) .. "s delay")

      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "info",
          title = "Target Moving!",
          msg = "They're on the move. Keep your distance!",
        })
      end
    end
    return -- Wait for startup to complete
  end

  local playerPos = playerVehicle:getPosition()
  local targetPos = targetVehicle:getPosition()
  local distance = distance2D(playerPos, targetPos)

  -- COLLISION DETECTION: If you hit the target, mission fails immediately!
  -- Check if player is VERY close (potential collision)
  if distance < 5 then
    -- Get damage info from target vehicle
    local damageData = nil
    pcall(function()
      -- Try to get damage tracker data
      damageData = map.objects[surveillanceState.targetVehicleId]
    end)

    if damageData and damageData.damage then
      local currentDamage = damageData.damage
      -- Initialize last damage on first check
      if surveillanceState.lastTargetDamage == 0 then
        surveillanceState.lastTargetDamage = currentDamage
      elseif currentDamage > surveillanceState.lastTargetDamage + 100 then
        -- Significant damage increase = collision!
        log("I", logTag, "Collision with target detected! Damage increased from " ..
            surveillanceState.lastTargetDamage .. " to " .. currentDamage)

        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "error",
            title = "Cover Blown!",
            msg = "You hit them! They know you're following!",
          })
        end

        completeMission(false)
        return
      end
      surveillanceState.lastTargetDamage = currentDamage
    end

    -- Alternative: simple proximity check - if you're THIS close, you probably hit them
    -- Only trigger if we've been following for a while (not at spawn)
    if surveillanceState.followTimer > 5 and distance < 3 then
      log("I", logTag, "Too close to target - likely collision at " .. string.format("%.1f", distance) .. "m")
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "error",
          title = "Cover Blown!",
          msg = "You got way too close!",
        })
      end
      completeMission(false)
      return
    end
  end

  -- Get target vehicle velocity (for stopped detection)
  local targetVel = targetVehicle:getVelocity()
  local targetSpeed = targetVel and targetVel:length() or 0

  -- Get player vehicle direction and target-to-player vector for angle calculation
  local playerDir = playerVehicle:getDirectionVector()
  local targetDir = targetVehicle:getDirectionVector()
  local toTarget = (targetPos - playerPos):normalized()

  -- Calculate angle: dot product shows if player is behind target (following) or in front
  -- dotProduct > 0.5 means player is roughly behind target (following correctly)
  -- dotProduct < -0.5 means player is in front of target (oncoming traffic)
  local followAngle = playerDir:dot(targetDir)
  local isFollowingBehind = followAngle > 0.3
  local isOncoming = followAngle < -0.3

  -- Waypoint logic: only show until target is "found" (player reaches within 10m)
  -- Detection ONLY starts after target is found - this gives player freedom to reach the target
  if not surveillanceState.targetFound then
    if distance < surveillanceState.targetFoundDistance then
      -- Target found! Clear waypoint and START detection system
      surveillanceState.targetFound = true
      surveillanceState.initialWaypointCleared = true
      if core_groundMarkers then
        core_groundMarkers.setPath(nil)
      end
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "info",
          title = "Target Located",
          msg = "Now keep your distance and follow them!",
        })
      end
    else
      -- Still searching, update waypoint to target
      if core_groundMarkers then
        core_groundMarkers.setPath(targetPos, { clearPathOnReachingTarget = false })
      end
    end

    -- While searching, send UI update showing "searching" mode
    if guihooks then
      guihooks.trigger("mysummerSurveillanceUpdate", {
        mode = "searching",
        distance = math.floor(distance),
        detectionMeter = 0,
        detectionRate = 0,
        distanceStatus = "searching",
        targetSpeed = math.floor(targetSpeed * 3.6),
      })
    end
    return -- Don't run detection logic until target is found
  end

  -- ============================================================================
  -- REALISTIC DETECTION SYSTEM (only runs AFTER target is found)
  -- ============================================================================
  -- Detection is based on what the TARGET would realistically notice:
  -- 1. They check their rear-view mirror - only see cars BEHIND them
  -- 2. Oncoming traffic = invisible to them (can't be following)
  -- 3. At traffic lights = everyone is close, totally normal
  -- 4. Highway tailgating = very suspicious
  -- 5. City traffic close = normal
  -- ============================================================================

  local detectionRate = 0
  local distanceStatus = "optimal"

  -- First: Determine if player is in target's "rear-view mirror zone"
  -- isFollowingBehind = both vehicles going same direction, player behind
  -- isOncoming = vehicles going opposite directions
  local inRearViewMirror = isFollowingBehind and distance < surveillanceState.tooFarDistance

  -- ONCOMING TRAFFIC: Target can't see you following them!
  -- You're going the opposite direction - zero detection
  if isOncoming then
    detectionRate = -5 -- Detection decays (you're "invisible")
    distanceStatus = "safe_oncoming"
    surveillanceState.warnedOncoming = false

  -- NOT IN REAR-VIEW: You're to the side or target can't see you
  elseif not inRearViewMirror then
    detectionRate = -3
    distanceStatus = "optimal"

  -- IN REAR-VIEW MIRROR: This is where detection happens
  else
    -- Determine traffic context based on TARGET's speed
    local isHighway = targetSpeed > 20  -- > 72 km/h = highway
    local isCity = targetSpeed > 8 and targetSpeed <= 20  -- 30-72 km/h = suburban/city
    local isSlowTraffic = targetSpeed > 2 and targetSpeed <= 8  -- 7-30 km/h = slow city traffic
    local isStopped = targetSpeed <= 2  -- < 7 km/h = stopped (traffic light, etc.)

    -- Base detection by distance
    if isStopped then
      -- TARGET STOPPED (traffic light, parking, etc.)
      -- Being close behind is COMPLETELY NORMAL - everyone does it
      if distance < 10 then
        detectionRate = 2 -- Very slight detection only if REALLY close
        distanceStatus = "close"
      else
        detectionRate = -2 -- Detection decays - this is normal traffic
        distanceStatus = "optimal"
      end

    elseif isSlowTraffic then
      -- SLOW CITY TRAFFIC (30 km/h or less)
      -- Being close is normal, lots of cars around
      if distance < 15 then
        detectionRate = 5 -- Slight suspicion if very close
        distanceStatus = "close"
      elseif distance < 30 then
        detectionRate = 0 -- Normal city distance
        distanceStatus = "optimal"
      else
        detectionRate = -3
        distanceStatus = "optimal"
      end

    elseif isCity then
      -- CITY/SUBURBAN TRAFFIC (30-70 km/h)
      -- Medium distances expected
      if distance < 20 then
        detectionRate = 12 -- Getting suspicious
        distanceStatus = "too_close"
      elseif distance < 40 then
        detectionRate = 3 -- Slightly suspicious
        distanceStatus = "close"
      elseif distance < 80 then
        detectionRate = -2 -- Normal
        distanceStatus = "optimal"
      else
        detectionRate = -5
        distanceStatus = "far"
      end

    else -- isHighway
      -- HIGHWAY (70+ km/h)
      -- Being close = tailgating = VERY suspicious
      if distance < 30 then
        detectionRate = 25 -- "Why is this guy tailgating me?!"
        distanceStatus = "too_close"
      elseif distance < 50 then
        detectionRate = 15 -- Suspiciously close for highway
        distanceStatus = "close"
      elseif distance < 100 then
        detectionRate = 2 -- Normal highway following distance
        distanceStatus = "optimal"
      else
        detectionRate = -3
        distanceStatus = "far"
      end
    end
  end

  -- Check if too far (losing target)
  if distance > surveillanceState.lostDistance then
    distanceStatus = "losing"
  elseif distance > surveillanceState.tooFarDistance then
    distanceStatus = "far"
  end

  -- Check if target is lost completely
  if distance > surveillanceState.lostDistance then
    log("I", logTag, "Target lost! Distance: " .. string.format("%.1f", distance) .. "m")
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "error",
        title = "Target Lost!",
        msg = "You lost sight of them!",
      })
    end
    -- completeMission will handle cleanup
    completeMission(false)
    return
  end

  -- Update detection meter
  surveillanceState.detectionMeter = surveillanceState.detectionMeter + (detectionRate * dtReal)
  surveillanceState.detectionMeter = math.max(0, math.min(100, surveillanceState.detectionMeter))

  -- Distance warnings (show once per state change)
  if distanceStatus == "too_close" and not surveillanceState.warnedTooClose then
    surveillanceState.warnedTooClose = true
    surveillanceState.warnedTooFar = false -- Reset opposite warning
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "warning",
        title = "Too Close!",
        msg = "Back off or they'll spot you!",
      })
    end
  elseif distanceStatus == "losing" and not surveillanceState.warnedTooFar then
    surveillanceState.warnedTooFar = true
    surveillanceState.warnedTooClose = false -- Reset opposite warning
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "warning",
        title = "Losing Them!",
        msg = "Get closer or you'll lose the target!",
      })
    end
  elseif distanceStatus == "optimal" then
    -- Reset warnings when back in optimal range
    surveillanceState.warnedTooClose = false
    surveillanceState.warnedTooFar = false
  end

  -- Detection level warnings (show once)
  if surveillanceState.detectionMeter >= 75 and not surveillanceState.warnedDetection75 then
    surveillanceState.warnedDetection75 = true
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "error",
        title = "Almost Spotted!",
        msg = "Back off NOW!",
      })
    end
  elseif surveillanceState.detectionMeter >= 50 and not surveillanceState.warnedDetection50 then
    surveillanceState.warnedDetection50 = true
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "warning",
        title = "Getting Suspicious",
        msg = "They're starting to notice you...",
      })
    end
  end

  -- Reset detection warnings if meter drops
  if surveillanceState.detectionMeter < 40 then
    surveillanceState.warnedDetection50 = false
  end
  if surveillanceState.detectionMeter < 65 then
    surveillanceState.warnedDetection75 = false
  end

  -- Check if detected
  if surveillanceState.detectionMeter >= 100 and not surveillanceState.fleeChaseActive then
    -- 50% chance they flee, 50% chance mission just fails
    local willFlee = math.random() < 0.5

    if willFlee then
      -- Target flees! Player must chase and immobilize them
      log("I", logTag, "Player detected! Target is fleeing!")
      surveillanceState.fleeChaseActive = true
      surveillanceState.fleeChaseTimer = 0
      surveillanceState.fleeChaseStoppedTimer = 0

      -- Set target to flee mode
      targetVehicle:queueLuaCommand('ai.setMode("flee")')
      targetVehicle:queueLuaCommand('ai.setAggression(1.0)') -- Full aggression when fleeing

      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "error",
          title = "They're Running!",
          msg = "Chase them down and stop them!",
        })
      end
      -- Don't return - continue to flee chase handling below
    else
      -- Mission just fails
      log("I", logTag, "Player detected! Mission failed.")
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "error",
          title = "Detected!",
          msg = "They spotted you! Cover blown.",
        })
      end
      -- completeMission handles cleanup internally
      completeMission(false)
      return
    end
  end

  -- FLEE CHASE HANDLING
  if surveillanceState.fleeChaseActive then
    surveillanceState.fleeChaseTimer = surveillanceState.fleeChaseTimer + dtReal

    -- Check if target is stopped (immobilized)
    if targetSpeed < 3 then -- Less than 3 m/s (~10 km/h)
      surveillanceState.fleeChaseStoppedTimer = surveillanceState.fleeChaseStoppedTimer + dtReal

      -- Check if stopped long enough
      if surveillanceState.fleeChaseStoppedTimer >= surveillanceState.fleeChaseRequiredStopTime then
        log("I", logTag, "Target immobilized! Mission complete!")
        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "success",
            title = "Target Stopped!",
            msg = "You caught them!",
          })
        end
        completeMission(true)
        return
      end
    else
      surveillanceState.fleeChaseStoppedTimer = 0
    end

    -- Check if target escaped (too far away)
    if distance > surveillanceState.lostDistance then
      log("I", logTag, "Target escaped! Mission failed.")
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "error",
          title = "Target Escaped!",
          msg = "They got away!",
        })
      end
      completeMission(false)
      return
    end

    -- Check if chase took too long
    if surveillanceState.fleeChaseTimer >= surveillanceState.fleeChaseMaxTime then
      log("I", logTag, "Flee chase timeout! Target escaped.")
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "error",
          title = "Too Slow!",
          msg = "They got away!",
        })
      end
      completeMission(false)
      return
    end

    -- Send flee chase update to UI
    if guihooks then
      guihooks.trigger("mysummerSurveillanceUpdate", {
        mode = "flee_chase",
        distance = distance,
        targetSpeed = targetSpeed,
        chaseTimer = surveillanceState.fleeChaseTimer,
        maxChaseTime = surveillanceState.fleeChaseMaxTime,
        stoppedProgress = surveillanceState.fleeChaseStoppedTimer / surveillanceState.fleeChaseRequiredStopTime,
      })
    end

    return -- Don't process normal surveillance logic during flee chase
  end

  -- Update follow timer only in optimal/close range
  if distanceStatus == "optimal" or distanceStatus == "close" then
    surveillanceState.followTimer = surveillanceState.followTimer + dtReal
  end

  -- DESTINATION CHECK: Target is heading to a known destination (set at start)
  if not surveillanceState.destinationReached then
    -- Check if target has arrived at their pre-set destination
    local currentDest = surveillanceState.currentDestination
    if currentDest and currentDest.pos then
      local distToDest = distance2D(targetPos, currentDest.pos)

      -- Track when target is stopped near destination
      if targetSpeed < 2 and distToDest < surveillanceState.arrivalDistance then
        surveillanceState.targetStoppedTime = surveillanceState.targetStoppedTime + dtReal
      else
        surveillanceState.targetStoppedTime = 0
      end

      -- Target has been stopped at destination long enough
      if surveillanceState.targetStoppedTime >= surveillanceState.targetStoppedThreshold then
        -- Target arrived at their destination!
        surveillanceState.destination = currentDest
        surveillanceState.destinationReached = true
        surveillanceState.quizPhase = true
        surveillanceState.correctAnswer = currentDest.name

        log("I", logTag, "Target arrived at destination: " .. currentDest.name)
        log("I", logTag, "Target actual position: " .. tostring(targetPos))
        log("I", logTag, "Expected destination pos: " .. tostring(currentDest.pos))
        log("I", logTag, "Distance to destination: " .. tostring(distToDest) .. "m")

        -- Generate quiz options (correct + 2 random wrong answers)
        local wrongOptions = {}
        for _, dest in ipairs(surveillanceState.allDestinations or {}) do
          if dest.name ~= currentDest.name then
            table.insert(wrongOptions, dest.name)
          end
        end
        -- Shuffle and pick 2
        for i = #wrongOptions, 2, -1 do
          local j = math.random(1, i)
          wrongOptions[i], wrongOptions[j] = wrongOptions[j], wrongOptions[i]
        end

        local quizOptions = { currentDest.name }
        if wrongOptions[1] then table.insert(quizOptions, wrongOptions[1]) end
        if wrongOptions[2] then table.insert(quizOptions, wrongOptions[2]) end
        -- Shuffle the options
        for i = #quizOptions, 2, -1 do
          local j = math.random(1, i)
          quizOptions[i], quizOptions[j] = quizOptions[j], quizOptions[i]
        end
        surveillanceState.quizOptions = quizOptions

        log("I", logTag, "Quiz options generated:")
        for i, opt in ipairs(quizOptions) do
          local isCorrect = (opt == currentDest.name) and " (CORRECT)" or ""
          log("I", logTag, "  " .. i .. ". " .. opt .. isCorrect)
        end
        log("I", logTag, "Correct answer: " .. surveillanceState.correctAnswer)

        -- Stop the target vehicle
        targetVehicle:queueLuaCommand('ai.setMode("stop")')

        -- Send quiz via EMAIL from contact
        local contactNames = {
          ghost = "Ghost",
          techie = "Techie",
          muscle = "Muscle",
          import = "Import",
          shadow = "Shadow",
        }
        local contactId = mission.contactId or "ghost"
        local contactName = contactNames[contactId] or "Contact"
        local vehicleDesc = surveillanceState.vehicleDesc or "vehicle"

        -- Build quiz body with options
        local quizBody = "The " .. vehicleDesc .. " stopped. I need to know exactly where they went.\n\n"
        quizBody = quizBody .. "Where did the target go?\n\n"
        for i, option in ipairs(quizOptions) do
          quizBody = quizBody .. "  " .. i .. ". " .. option .. "\n"
        end
        quizBody = quizBody .. "\nReply with your answer. Don't take too long."

        if career_modules_mysummerMessages then
          career_modules_mysummerMessages.sendCustomMessage({
            from = contactId,
            fromName = contactName,
            subject = "Where did they go?",
            body = quizBody,
            icon = "[?]",
            priority = "high",
            missionId = mission.id,
            actionType = "surveillance_quiz",
            quizOptions = quizOptions,
            quizCallback = "career_modules_mysummerMissions.answerSurveillanceQuiz",
          })
        end

        -- Also show toast notification
        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "info",
            title = "Target Stopped!",
            msg = "Check your messages - " .. contactName .. " wants to know where they went!",
          })
        end

        return -- Wait for player answer via email
      end
    end
  end

  -- If in quiz phase, just wait for answer (don't complete by time)
  if surveillanceState.quizPhase then
    return
  end

  -- Send surveillance update to UI
  if guihooks then
    -- Calculate distance to destination for UI progress
    local distToDestination = nil
    local destProgress = nil
    if surveillanceState.destination then
      distToDestination = math.floor(distance2D(targetPos, surveillanceState.destination.pos))
    end

    guihooks.trigger("mysummerSurveillanceUpdate", {
      distance = math.floor(distance),
      detectionMeter = math.floor(surveillanceState.detectionMeter),
      detectionRate = detectionRate, -- Positive = rising, negative = falling
      distanceStatus = distanceStatus,
      missionTitle = mission.title,
      -- Advanced detection info
      targetSpeed = math.floor(targetSpeed * 3.6), -- Convert m/s to km/h
      targetStopped = targetSpeed < 2,
      isFollowingBehind = isFollowingBehind,
      isOncoming = isOncoming,
      -- Destination/Quiz info
      hasDestination = surveillanceState.destination ~= nil,
      targetDistToDestination = distToDestination,
      quizPhase = surveillanceState.quizPhase,
      destinationReached = surveillanceState.destinationReached,
    })
  end

  -- Periodic log
  if math.random() < 0.02 then
    log("I", logTag, string.format("Surveillance: dist=%.0fm, detection=%.0f%%, progress=%.0f%%",
      distance, surveillanceState.detectionMeter, (surveillanceState.followTimer / surveillanceState.requiredFollowTime) * 100))
  end
end

-- ============================================================================
-- ESCORT MISSION FUNCTIONS
-- ============================================================================

-- Find a spawn point ON THE SAME ROAD as the player, ahead or behind
local function getEscortEnemySpawnPoint(spawnAhead)
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return nil end

  local playerPos = playerVehicle:getPosition()
  local playerDir = playerVehicle:getDirectionVector()
  local spawnDistance = escortState.enemySpawnDistance or 150

  -- Try to use the path/road system to find a point on the same road
  if map and map.getMap then
    local mapData = map.getMap()
    if mapData and mapData.nodes then
      -- Find the road node closest to player (this is their current road)
      local playerNodeId = nil
      local playerNodeDist = math.huge
      for nodeId, node in pairs(mapData.nodes) do
        if node.pos then
          local dist = distance2D(playerPos, node.pos)
          if dist < playerNodeDist then
            playerNodeDist = dist
            playerNodeId = nodeId
          end
        end
      end

      if playerNodeId then
        local playerNode = mapData.nodes[playerNodeId]

        -- Traverse the road graph to find a node at the right distance
        -- Use BFS to walk along connected nodes
        local visited = {}
        local queue = {{nodeId = playerNodeId, dist = 0, prevPos = playerPos}}
        local bestNode = nil
        local bestScore = math.huge

        while #queue > 0 do
          local current = table.remove(queue, 1)
          local nodeId = current.nodeId
          local travelDist = current.dist

          if visited[nodeId] then goto continue end
          visited[nodeId] = true

          local node = mapData.nodes[nodeId]
          if not node or not node.pos then goto continue end

          -- Check if this node is in the right direction and distance
          local nodePos = node.pos
          local dirToNode = (nodePos - playerPos):normalized()
          local dotProduct = playerDir:dot(dirToNode)

          -- For spawn ahead: positive dot product, for behind: negative
          local wantPositive = spawnAhead
          local isCorrectDir = (wantPositive and dotProduct > 0.3) or (not wantPositive and dotProduct < -0.3)

          -- Check if at good distance (100-200m from player)
          local distFromPlayer = distance2D(playerPos, nodePos)
          if isCorrectDir and distFromPlayer >= 100 and distFromPlayer <= 250 then
            -- Score by how close to ideal distance (150m)
            local score = math.abs(distFromPlayer - spawnDistance)
            if score < bestScore then
              bestScore = score
              bestNode = node
            end
          end

          -- Add connected nodes to queue (follow the road)
          if node.links and travelDist < 400 then -- Don't search too far
            for linkedId, _ in pairs(node.links) do
              if not visited[linkedId] then
                local linkedNode = mapData.nodes[linkedId]
                if linkedNode and linkedNode.pos then
                  local linkDist = distance2D(nodePos, linkedNode.pos)
                  table.insert(queue, {
                    nodeId = linkedId,
                    dist = travelDist + linkDist,
                    prevPos = nodePos
                  })
                end
              end
            end
          end

          ::continue::
        end

        if bestNode and bestNode.pos then
          local spawnPos = vec3(bestNode.pos.x, bestNode.pos.y, bestNode.pos.z + 0.5)
          local dirToPlayer = (playerPos - spawnPos):normalized()
          log("I", logTag, "Found road spawn point at " .. tostring(distance2D(playerPos, spawnPos)) .. "m " .. (spawnAhead and "ahead" or "behind"))
          return spawnPos, quatFromDir(dirToPlayer)
        end
      end
    end
  end

  -- Fallback: spawn at offset from player direction (old method)
  log("W", logTag, "Road spawn failed, using fallback")
  local dirMult = spawnAhead and 1 or -1
  local targetPos = playerPos + (playerDir * spawnDistance * dirMult)
  local groundZ = be:getSurfaceHeightBelow(vec3(targetPos.x, targetPos.y, playerPos.z + 100))
  local spawnPos = vec3(targetPos.x, targetPos.y, (groundZ or playerPos.z) + 0.5)
  local dirToPlayer = (playerPos - spawnPos):normalized()
  return spawnPos, quatFromDir(dirToPlayer)
end

-- Spawn a single enemy for escort mission
local function spawnEscortEnemy()
  -- Check max enemies
  if #escortState.enemyVehicleIds >= escortState.maxActiveEnemies then
    log("I", logTag, "Max enemies reached, not spawning more")
    return false
  end

  -- Pick random vehicle
  local vehicleInfo = ESCORT_ENEMY_VEHICLES[math.random(#ESCORT_ENEMY_VEHICLES)]

  -- Randomly spawn ahead or behind (60% behind, 40% ahead)
  local spawnAhead = math.random() > 0.6
  local spawnPos, spawnRot = getEscortEnemySpawnPoint(spawnAhead)

  if not spawnPos then
    log("W", logTag, "Could not find escort enemy spawn point")
    return false
  end

  local spawnOptions = {
    config = vehicleInfo.config,
    pos = spawnPos,
    rot = spawnRot,
    autoEnterVehicle = false,
    cling = true,
  }

  log("I", logTag, "Spawning escort enemy: " .. vehicleInfo.model .. " / " .. vehicleInfo.config .. " at " .. tostring(spawnPos))

  local vehicle = core_vehicles.spawnNewVehicle(vehicleInfo.model, spawnOptions)

  if vehicle then
    local vehId = vehicle:getID()
    table.insert(escortState.enemyVehicleIds, vehId)

    -- Set AI to chase player - queue commands directly, they execute after vehicle initializes
    local playerVehicle = be:getPlayerVehicle(0)
    if playerVehicle then
      local playerId = playerVehicle:getID()
      vehicle:queueLuaCommand('ai.setMode("chase")')
      vehicle:queueLuaCommand('ai.setTargetObjectID(' .. playerId .. ')')
      vehicle:queueLuaCommand('ai.setAggression(0.9)')
      vehicle:queueLuaCommand('ai.setSpeedMode("off")')
      log("I", logTag, "Enemy " .. vehId .. " set to chase player " .. playerId)
    end

    return true
  else
    log("E", logTag, "Failed to spawn escort enemy")
    return false
  end
end

-- Spawn a police vehicle for escort mission (police mode)
local function spawnEscortPolice()
  -- Check max police
  if #escortState.spawnedPoliceIds >= escortState.maxSpawnedPolice then
    log("I", logTag, "Max spawned police reached")
    return false
  end

  -- Pick random police vehicle
  local vehicleInfo = ESCORT_POLICE_VEHICLES[math.random(#ESCORT_POLICE_VEHICLES)]

  -- Spawn behind player (police typically come from behind)
  local spawnAhead = math.random() > 0.7 -- 30% ahead, 70% behind
  local spawnPos, spawnRot = getEscortEnemySpawnPoint(spawnAhead)

  if not spawnPos then
    log("W", logTag, "Could not find police spawn point")
    return false
  end

  local spawnOptions = {
    config = vehicleInfo.config,
    pos = spawnPos,
    rot = spawnRot,
    autoEnterVehicle = false,
    cling = true,
  }

  log("I", logTag, "Spawning police: " .. vehicleInfo.model .. " / " .. vehicleInfo.config)

  local vehicle = core_vehicles.spawnNewVehicle(vehicleInfo.model, spawnOptions)

  if vehicle then
    local vehId = vehicle:getID()
    if not vehId then
      log("E", logTag, "Vehicle spawned but getID returned nil")
      return false
    end

    table.insert(escortState.spawnedPoliceIds, vehId)

    -- Set AI to chase player directly (don't use traffic system - causes issues)
    local playerVehicle = be:getPlayerVehicle(0)
    if playerVehicle then
      local playerId = playerVehicle:getID()
      vehicle:queueLuaCommand('ai.setMode("chase")')
      vehicle:queueLuaCommand('ai.setTargetObjectID(' .. playerId .. ')')
      vehicle:queueLuaCommand('ai.setAggression(1.0)')
      vehicle:queueLuaCommand('ai.setSpeedMode("off")')
    end

    log("I", logTag, "Police " .. vehId .. " spawned and set to pursue")
    return true
  else
    log("E", logTag, "Failed to spawn police vehicle")
    return false
  end
end

-- Spawn a wave of enemies
local function spawnEscortWave()
  local mission = state.activeMission
  if not mission then return end

  escortState.currentWave = escortState.currentWave + 1
  local waveNum = escortState.currentWave

  -- Calculate how many enemies we need to reach maxActiveEnemies
  local currentEnemies = #escortState.enemyVehicleIds
  local neededEnemies = escortState.maxActiveEnemies - currentEnemies

  -- Limit spawn to at least 1, at most what's needed
  local enemiesThisWave = math.max(1, math.min(neededEnemies, 3)) -- Spawn up to 3 at a time

  -- First wave can use mission's enemiesPerWave if defined
  if waveNum == 1 and mission.enemiesPerWave and mission.enemiesPerWave[1] then
    enemiesThisWave = mission.enemiesPerWave[1]
  end

  log("I", logTag, "Spawning wave " .. waveNum .. " with " .. enemiesThisWave .. " enemies (current: " .. currentEnemies .. ", max: " .. escortState.maxActiveEnemies .. ")")

  -- Show wave notification
  if guihooks then
    guihooks.trigger("toastrMsg", {
      type = "warning",
      title = "WAVE " .. waveNum,
      msg = enemiesThisWave .. " enemies incoming!",
    })
  end

  -- Spawn enemies (all at once - staggering handled by spawn position randomness)
  for i = 1, enemiesThisWave do
    spawnEscortEnemy()
  end

  escortState.waveTimer = 0
end

-- Cleanup all escort enemies and restore player vehicle (uses forward-declared variable)
cleanupEscortMission = function()
  log("I", logTag, "Cleaning up escort mission")

  -- End official police pursuit if active
  if escortState.policeActive and gameplay_police then
    local vehId = escortState.playerVehicleId or be:getPlayerVehicleID(0)
    if vehId then
      gameplay_police.setPursuitMode(0, vehId)
      log("I", logTag, "Ended police pursuit")
    end
    escortState.policeActive = false
  end

  -- Delete all enemies (for non-police mode)
  for _, vehId in ipairs(escortState.enemyVehicleIds) do
    local vehicle = be:getObjectByID(vehId)
    if vehicle then
      vehicle:delete()
      log("I", logTag, "Deleted escort enemy: " .. vehId)
    end
  end

  -- Delete all spawned police (for police mode)
  for _, vehId in ipairs(escortState.spawnedPoliceIds) do
    local vehicle = be:getObjectByID(vehId)
    if vehicle then
      vehicle:delete()
      log("I", logTag, "Deleted spawned police: " .. vehId)
    end
  end

  -- Store escort vehicle ID to delete AFTER switching (with delay)
  local escortVehicleToDelete = escortState.playerVehicleId

  -- FIRST: Restore original vehicle if it exists and player was teleported
  -- Must do this BEFORE deleting the escort vehicle to avoid quickAccess nil error
  if escortState.originalVehicleId then
    local originalVeh = be:getObjectByID(escortState.originalVehicleId)
    if originalVeh then
      be:enterVehicle(0, originalVeh)
      log("I", logTag, "Restored player to original vehicle")
    end
  end

  -- THEN: Schedule escort vehicle for delayed deletion
  -- This will be processed in onUpdate after quickAccess has updated
  if escortVehicleToDelete then
    escortState.pendingVehicleDelete = escortVehicleToDelete
    escortState.pendingDeleteTimer = 0.5 -- Wait 0.5 seconds before delete
    log("I", logTag, "Scheduled escort player vehicle for delayed deletion")
  end

  -- Reset state
  escortState.playerVehicleId = nil
  escortState.originalVehicleId = nil
  escortState.enemyVehicleIds = {}
  escortState.enemyDisabledTimers = {}
  escortState.currentWave = 0
  escortState.waveTimer = 0
  escortState.missionStarted = false
  escortState.reachedDestination = false
  escortState.missionEnding = false
  escortState.endingTimer = 0
  escortState.endingSuccess = false
  escortState.playerStartDamage = 0
  escortState.playerDisabledTimer = 0
  escortState.policeActive = false
  escortState.spawnedPoliceIds = {}
  escortState.policeSpawnTimer = 0

  -- Clear navigation
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end
end

-- Setup escort mission (spawn player vehicle, set destination)
local function setupEscortMission(mission)
  log("I", logTag, "Setting up escort mission: " .. mission.title)

  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then
    log("E", logTag, "No player vehicle for escort mission")
    return false
  end

  -- Store original vehicle
  escortState.originalVehicleId = playerVehicle:getID()

  -- Pick random resistant vehicle
  local vehicleInfo = ESCORT_PLAYER_VEHICLES[math.random(#ESCORT_PLAYER_VEHICLES)]

  -- Get player position for spawn
  local playerPos = playerVehicle:getPosition()
  local playerDir = playerVehicle:getDirectionVector()
  local spawnPos = playerPos + (playerDir * 5) -- Spawn slightly ahead
  spawnPos.z = spawnPos.z + 0.5

  local spawnOptions = {
    config = vehicleInfo.config,
    pos = spawnPos,
    rot = quatFromDir(playerDir),
    autoEnterVehicle = true, -- Automatically put player in this vehicle
    cling = true,
  }

  log("I", logTag, "Spawning escort player vehicle: " .. vehicleInfo.model .. " / " .. vehicleInfo.config)

  local vehicle = core_vehicles.spawnNewVehicle(vehicleInfo.model, spawnOptions)

  if vehicle then
    escortState.playerVehicleId = vehicle:getID()

    -- Initial damage will be tracked on first update frame
    escortState.playerStartDamage = -1 -- Mark as not yet initialized

    -- Setup destination - ALWAYS use real POIs from the map
    local destinations = getSurveillanceDestinations()
    if #destinations > 0 then
      -- Pick a destination that's far enough from player (at least 500m)
      local playerPos = be:getPlayerVehicle(0):getPosition()
      local validDestinations = {}

      for _, dest in ipairs(destinations) do
        local destPos = toVec3(dest.pos)
        if destPos then
          local dist = distance2D(playerPos, destPos)
          if dist > 500 and dist < 3000 then -- Between 500m and 3km
            table.insert(validDestinations, dest)
          end
        end
      end

      -- Use valid destinations, or fall back to any destination
      local destList = #validDestinations > 0 and validDestinations or destinations
      local dest = destList[math.random(#destList)]

      escortState.destination = toVec3(dest.pos)
      escortState.destinationName = dest.name or "Safe House"

      log("I", logTag, "Escort destination set to POI: " .. escortState.destinationName)
      log("I", logTag, "Destination position: " .. tostring(escortState.destination))

      -- Set waypoint to destination
      if core_groundMarkers then
        core_groundMarkers.setPath(escortState.destination, {
          clearPathOnReachingTarget = false,
        })
      end
    else
      log("E", logTag, "No valid destinations found for escort mission!")
      return false
    end

    -- Initialize escort state
    escortState.enemyVehicleIds = {}
    escortState.currentWave = 0
    escortState.waveTimer = 0
    escortState.missionStarted = true
    escortState.reachedDestination = false
    escortState.maxWaves = mission.maxWaves or 5
    escortState.waveInterval = mission.waveInterval or 25
    escortState.initialDelay = 8
    escortState.policeActive = false

    -- Start police pursuit or enemy waves based on mode
    if escortState.usePoliceMode then
      -- HYBRID APPROACH:
      -- 1. Start official police pursuit (gives sirens, UI, real police experience)
      -- 2. Also spawn additional chase vehicles for more intensity
      if gameplay_police then
        -- Set VERY aggressive pursuit variables
        local pursuitVars = {
          evadeTime = 9999,        -- Never give up chase
          arrestTime = 12,         -- Fast arrest when stopped
          arrestRadius = 12,       -- Close arrest range
          evadeLimit = 8,          -- Must go very slow to evade
        }
        gameplay_police.setPursuitVars(pursuitVars)

        -- Start official pursuit on player vehicle
        gameplay_police.setPursuitMode(1, escortState.playerVehicleId)
        escortState.policeActive = true
        escortState.policeSpawnTimer = 0 -- Will spawn additional chasers

        log("I", logTag, "Started official police pursuit + additional chasers")

        -- Show police warning message
        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "warning",
            title = "POLICE PURSUIT",
            msg = "Get to " .. escortState.destinationName .. " before they catch you!",
          })
        end
      else
        log("W", logTag, "gameplay_police not available, falling back to enemy waves")
        escortState.usePoliceMode = false
      end
    end

    -- Show mission start message (for non-police mode)
    if not escortState.usePoliceMode then
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "info",
          title = "ESCORT MISSION",
          msg = "Get to " .. escortState.destinationName .. " - enemies incoming!",
        })
      end
    end

    log("I", logTag, "Escort mission setup complete. Destination: " .. escortState.destinationName .. " (Police mode: " .. tostring(escortState.usePoliceMode) .. ")")
    return true
  else
    log("E", logTag, "Failed to spawn escort player vehicle")
    return false
  end
end

-- Start the escort mission ending sequence (fade to black, then cleanup)
local function startEscortEnding(success, message)
  if escortState.missionEnding then return end -- Already ending

  escortState.missionEnding = true
  escortState.endingTimer = 0
  escortState.endingSuccess = success
  escortState.endingMessage = message

  log("I", logTag, "Starting escort ending sequence: " .. (success and "SUCCESS" or "FAILED"))

  -- Show message
  if guihooks then
    guihooks.trigger("toastrMsg", {
      type = success and "success" or "error",
      title = success and "MISSION COMPLETE" or "MISSION FAILED",
      msg = message,
    })
  end

  -- Start fade to black
  if ui_fadeScreen then
    ui_fadeScreen.start(1.5) -- 1.5 second fade to black
  end
end

-- Check escort mission progress
local function checkEscortProgress(dtReal)
  local mission = state.activeMission
  if not mission or mission.type ~= MISSION_TYPES.ESCORT then return end

  -- Handle ending sequence
  if escortState.missionEnding then
    escortState.endingTimer = escortState.endingTimer + dtReal

    -- Wait for fade, then complete
    if escortState.endingTimer >= 2.0 then
      -- Fade back in
      if ui_fadeScreen then
        ui_fadeScreen.stop(1.0) -- 1 second fade back in
      end
      completeMission(escortState.endingSuccess)
    end
    return
  end

  -- Setup mission if not started
  if not escortState.missionStarted then
    if not setupEscortMission(mission) then
      log("E", logTag, "Failed to setup escort mission")
      completeMission(false)
      return
    end
  end

  local playerVehicle = be:getObjectByID(escortState.playerVehicleId)
  if not playerVehicle then
    -- Player vehicle destroyed or missing
    log("W", logTag, "Escort player vehicle not found")
    startEscortEnding(false, "Vehicle lost!")
    return
  end

  local playerPos = playerVehicle:getPosition()

  -- Check if player reached destination
  if escortState.destination then
    local distToDestination = distance2D(playerPos, escortState.destination)

    if distToDestination < escortState.arrivalDistance then
      log("I", logTag, "Player reached destination!")
      startEscortEnding(true, "You made it to " .. escortState.destinationName .. "!")
      return
    end
  end

  -- Check if player vehicle is disabled (high damage + can't move for too long)
  local currentDamage = 0
  local playerSpeed = 0
  if map.objects and map.objects[escortState.playerVehicleId] then
    currentDamage = map.objects[escortState.playerVehicleId].damage or 0
    local vel = map.objects[escortState.playerVehicleId].vel
    if vel then
      playerSpeed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
    end
  end

  -- Initialize start damage on first valid reading
  if escortState.playerStartDamage < 0 then
    escortState.playerStartDamage = currentDamage
    log("I", logTag, "Initialized player start damage: " .. currentDamage)
  end

  local damageTaken = currentDamage - escortState.playerStartDamage

  -- Check if player is disabled (damaged AND moving slowly)
  local isPlayerDisabled = damageTaken > escortState.playerDamageThreshold and playerSpeed < escortState.playerMinSpeed

  if isPlayerDisabled then
    escortState.playerDisabledTimer = escortState.playerDisabledTimer + dtReal

    -- Show warning when close to failure
    if escortState.playerDisabledTimer > escortState.playerDisabledTime * 0.5 and
       escortState.playerDisabledTimer < escortState.playerDisabledTime * 0.5 + dtReal * 2 then
      if guihooks then
        guihooks.trigger("toastrMsg", {
          type = "warning",
          title = "Vehicle Disabled!",
          msg = "Get moving or mission fails!",
        })
      end
    end

    -- Fail if disabled too long
    if escortState.playerDisabledTimer >= escortState.playerDisabledTime then
      log("I", logTag, "Escort vehicle disabled for too long! Damage: " .. damageTaken)
      startEscortEnding(false, "Your vehicle was disabled!")
      return
    end
  else
    -- Reset timer if player is moving or not heavily damaged
    if escortState.playerDisabledTimer > 0 then
      log("I", logTag, "Player recovered - disabled timer reset")
    end
    escortState.playerDisabledTimer = 0
  end

  -- ============================================================================
  -- ENEMY SPAWNING MODE (non-police) - Only runs if usePoliceMode is false
  -- ============================================================================
  if not escortState.usePoliceMode then
    -- Clean up disabled/destroyed enemies (only after they've been immobile for a while)
    local activeEnemies = {}
    for _, vehId in ipairs(escortState.enemyVehicleIds) do
      local vehicle = be:getObjectByID(vehId)
      if vehicle then
        local enemyDamage = 0
        local enemySpeed = 0

        if map.objects and map.objects[vehId] then
          enemyDamage = map.objects[vehId].damage or 0
          local vel = map.objects[vehId].vel
          if vel then
            enemySpeed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
          end
        end

        -- Check if enemy is disabled (high damage AND not moving)
        local isDisabled = enemyDamage > escortState.enemyDisableThreshold and enemySpeed < 2

        if isDisabled then
          -- Track disabled time
          escortState.enemyDisabledTimers[vehId] = (escortState.enemyDisabledTimers[vehId] or 0) + dtReal

          -- Only despawn after being disabled for a while
          if escortState.enemyDisabledTimers[vehId] >= escortState.enemyDisableTime then
            vehicle:delete()
            escortState.enemyDisabledTimers[vehId] = nil
            log("I", logTag, "Deleted disabled enemy after " .. escortState.enemyDisableTime .. "s: " .. vehId)
          else
            -- Still tracking, keep in list
            table.insert(activeEnemies, vehId)
          end
        else
          -- Enemy still functional, reset disabled timer
          escortState.enemyDisabledTimers[vehId] = nil
          table.insert(activeEnemies, vehId)
        end
      else
        -- Vehicle doesn't exist anymore, clean up timer
        escortState.enemyDisabledTimers[vehId] = nil
      end
    end
    escortState.enemyVehicleIds = activeEnemies

    -- Wave spawning logic - maintain at least maxActiveEnemies at all times
    escortState.waveTimer = escortState.waveTimer + dtReal

    -- Initial delay before first wave
    if escortState.currentWave == 0 then
      if escortState.waveTimer >= escortState.initialDelay then
        spawnEscortWave()
      end
    else
      -- Always spawn more enemies if we have less than maxActiveEnemies
      -- Use the wave timer as a cooldown between spawns
      local activeCount = #escortState.enemyVehicleIds
      local needMoreEnemies = activeCount < escortState.maxActiveEnemies

      if needMoreEnemies and escortState.waveTimer >= escortState.waveInterval then
        spawnEscortWave()
      end
    end
  else
    -- ============================================================================
    -- POLICE MODE - Official pursuit system handles police spawning
    -- ============================================================================
    -- The official gameplay_police system spawns and manages police automatically
    -- We just need to keep the pursuit active
  end
  -- ============================================================================
  -- END ENEMY/POLICE SPAWNING MODE
  -- ============================================================================

  -- Send UI update
  if guihooks then
    local distToDestination = escortState.destination and math.floor(distance2D(playerPos, escortState.destination)) or 0
    local disabledProgress = escortState.playerDisabledTimer / escortState.playerDisabledTime -- 0-1

    guihooks.trigger("mysummerEscortUpdate", {
      wave = escortState.usePoliceMode and 0 or escortState.currentWave,
      maxWaves = escortState.usePoliceMode and 0 or escortState.maxWaves,
      activeEnemies = escortState.usePoliceMode and 0 or #escortState.enemyVehicleIds, -- Police mode uses official system
      distanceToDestination = distToDestination,
      destinationName = escortState.destinationName,
      playerSpeed = math.floor(playerSpeed * 3.6), -- km/h
      damageTaken = math.floor(damageTaken),
      isDisabled = escortState.playerDisabledTimer > 0,
      disabledProgress = disabledProgress, -- 0-1, shows how close to failure
      missionTitle = mission.title,
      isPoliceMode = escortState.usePoliceMode,
    })
  end
end

-- Track if we've shown time warnings
local timeWarnings = {
  shown60 = false,
  shown30 = false,
  shown10 = false,
}

-- ============================================================================
-- POLICE/ARREST DETECTION
-- ============================================================================

-- Check if player is being arrested - cancels mission if so
local function checkPoliceArrest()
  if not state.activeMission then return false end

  -- Check if pursuit is active
  if not gameplay_police then return false end
  local pursuitData = gameplay_police.getPursuitData and gameplay_police.getPursuitData()
  if not pursuitData then return false end

  -- Try to get player driving data for arrest timer
  if career_modules_playerDriving and career_modules_playerDriving.getPlayerData then
    local playerData = career_modules_playerDriving.getPlayerData()
    if playerData and playerData.traffic and playerData.traffic.pursuit then
      local arrestValue = playerData.traffic.pursuit.timers.arrestValue or 0

      -- If arrest is almost complete (>90%), fail the mission
      if arrestValue >= 0.9 then
        log("I", logTag, "Player arrested during mission - mission failed")
        if guihooks then
          guihooks.trigger("toastrMsg", {
            type = "error",
            title = "Mission Failed",
            msg = "You got arrested!",
          })
        end
        completeMission(false)
        return true
      end
    end
  end

  return false
end

-- Cancel mission when player uses tow/recovery
local function onVehicleRecoveryStarted()
  if not state.activeMission then return end

  log("I", logTag, "Player used recovery during mission - mission abandoned")
  if guihooks then
    guihooks.trigger("toastrMsg", {
      type = "warning",
      title = "Mission Abandoned",
      msg = "You used vehicle recovery.",
    })
  end
  abandonMission()
end

local function checkMissionTimeout()
  local mission = state.activeMission
  if not mission or not mission.timeLimit then return end

  local elapsed = os.time() - mission.startedAt
  local remaining = mission.timeLimit - elapsed

  -- Time warnings
  if remaining <= 60 and remaining > 30 and not timeWarnings.shown60 then
    timeWarnings.shown60 = true
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "warning",
        title = "1 Minute Left!",
        msg = mission.title,
      })
    end
  elseif remaining <= 30 and remaining > 10 and not timeWarnings.shown30 then
    timeWarnings.shown30 = true
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "warning",
        title = "30 Seconds!",
        msg = "Hurry up!",
      })
    end
  elseif remaining <= 10 and remaining > 0 and not timeWarnings.shown10 then
    timeWarnings.shown10 = true
    if guihooks then
      guihooks.trigger("toastrMsg", {
        type = "error",
        title = "10 Seconds!",
        msg = "Almost out of time!",
      })
    end
  end

  -- Timeout check
  if elapsed >= mission.timeLimit then
    log("I", logTag, "Mission timed out")
    completeMission(false)
  end
end

-- Reset time warnings when mission starts
resetTimeWarnings = function()
  timeWarnings.shown60 = false
  timeWarnings.shown30 = false
  timeWarnings.shown10 = false
end

-- Timer update interval
local timerUpdateAccum = 0
local TIMER_UPDATE_INTERVAL = 1.0 -- Update UI every second

local function sendTimerUpdate()
  local mission = state.activeMission
  if not mission then return end

  local remaining = 0
  if mission.timeLimit and mission.startedAt then
    remaining = math.max(0, mission.timeLimit - (os.time() - mission.startedAt))
  end

  if guihooks then
    guihooks.trigger("mysummerMissionTimer", {
      id = mission.id,
      title = mission.title,
      remaining = remaining,
      timeLimit = mission.timeLimit,
      pickedUp = mission.pickedUp,
      type = mission.type,
      hint = mission.pickedUp and mission.dropoffHint or mission.pickupHint,
    })
  end
end

local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then return end

  -- Process pending escort vehicle deletion (to avoid quickAccess errors)
  if escortState.pendingVehicleDelete then
    escortState.pendingDeleteTimer = escortState.pendingDeleteTimer - dtReal
    if escortState.pendingDeleteTimer <= 0 then
      local vehId = escortState.pendingVehicleDelete
      local veh = be:getObjectByID(vehId)
      if veh then
        veh:delete()
        log("I", logTag, "Deleted escort player vehicle (delayed)")
      end
      escortState.pendingVehicleDelete = nil
      escortState.pendingDeleteTimer = 0
    end
  end

  -- Update time transition (even if no mission active)
  if updateTimeTransition(dtReal) then
    -- During time transition, don't process mission logic
    return
  end

  if not state.activeMission then return end

  -- Check for police arrest (cancels mission if caught)
  if checkPoliceArrest() then return end

  -- Check for timeout
  checkMissionTimeout()

  -- Send timer updates periodically
  timerUpdateAccum = timerUpdateAccum + dtReal
  if timerUpdateAccum >= TIMER_UPDATE_INTERVAL then
    timerUpdateAccum = 0
    sendTimerUpdate()
  end

  -- Type-specific checks
  if state.activeMission then
    if state.activeMission.type == MISSION_TYPES.DELIVERY then
      checkDeliveryProgress()
    elseif state.activeMission.type == MISSION_TYPES.CHASE then
      checkChaseProgress(dtReal)
    elseif state.activeMission.type == MISSION_TYPES.SURVEILLANCE then
      checkSurveillanceProgress(dtReal)
    elseif state.activeMission.type == MISSION_TYPES.ESCORT then
      checkEscortProgress(dtReal)
    end
  end
end

-- ============================================================================
-- MISSION OFFERS (via email)
-- ============================================================================

local function offerMissionViaEmail(contactId)
  local available = getAvailableMissionsForContact(contactId)
  if #available == 0 then
    log("I", logTag, "No missions available for " .. contactId)
    return false
  end

  -- Pick a random mission
  local template = available[math.random(#available)]
  local mission = generateMission(contactId, template.id)

  if not mission then return false end

  -- Add to available missions
  table.insert(state.availableMissions, mission)

  -- Send email via messages system
  if career_modules_mysummerMessages then
    local contactNames = {
      ghost = "Ghost",
      techie = "Techie",
      muscle = "Muscle",
      import = "Import",
      shadow = "Shadow",
    }

    career_modules_mysummerMessages.sendCustomMessage({
      from = contactId,
      fromName = contactNames[contactId] or contactId,
      subject = "Job: " .. mission.title,
      body = mission.description .. "\n\n" ..
             "Reward: $" .. (mission.reward.money or 0) .. "\n" ..
             (mission.timeLimit and ("Time limit: " .. math.floor(mission.timeLimit / 60) .. " min\n") or "") ..
             "\nReply to accept this job.",
      icon = "[!]",
      priority = "high",
      missionId = mission.id,
      actionType = "mission_offer",
    })

    log("I", logTag, "Mission offer sent via email: " .. mission.title)
    return true
  end

  return false
end

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

local function loadState()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath) or {}

  state.activeMission = data.activeMission
  state.completedMissions = data.completedMissions or {}
  state.missionCooldowns = data.missionCooldowns or {}
  state.availableMissions = data.availableMissions or {}

  log("I", logTag, "Loaded mission state")
end

saveState = function(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  savePath = currentSavePath or savePath
  if not savePath then return end

  local dirPath = savePath .. "/career/mysummer"
  if not FS:directoryExists(dirPath) then
    FS:directoryCreate(dirPath, true)
  end

  local filePath = dirPath .. "/" .. saveFile
  local data = {
    activeMission = state.activeMission,
    completedMissions = state.completedMissions,
    missionCooldowns = state.missionCooldowns,
    availableMissions = state.availableMissions,
  }
  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("I", logTag, "Saved mission state")
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onCareerActive(active)
  if active then
    loadState()
    buildLocations()
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

local function onExtensionLoaded()
  log("I", logTag, "MySummer Missions system loaded")
end

-- ============================================================================
-- DEBUG/TEST FUNCTIONS
-- ============================================================================

-- Force send a mission offer from a specific contact
-- Usage in console: career_modules_mysummerMissions.debugOfferMission("ghost")
local function debugOfferMission(contactId)
  contactId = contactId or "ghost"
  log("I", logTag, "[DEBUG] Forcing mission offer from: " .. contactId)

  local result = offerMissionViaEmail(contactId)
  if result then
    log("I", logTag, "[DEBUG] Mission offer sent successfully!")
  else
    log("W", logTag, "[DEBUG] Failed to send mission offer - check contact has available missions")
  end
  return result
end

-- Force complete the active mission (success or fail)
-- Usage: career_modules_mysummerMissions.debugCompleteMission(true) -- success
-- Usage: career_modules_mysummerMissions.debugCompleteMission(false) -- fail
local function debugCompleteMission(success)
  if not state.activeMission then
    log("W", logTag, "[DEBUG] No active mission to complete")
    return false
  end

  success = success ~= false -- default to true
  log("I", logTag, "[DEBUG] Force completing mission: " .. (success and "SUCCESS" or "FAIL"))
  return completeMission(success)
end

-- Clear all cooldowns for testing
-- Usage: career_modules_mysummerMissions.debugClearCooldowns()
local function debugClearCooldowns()
  state.missionCooldowns = {}
  state.completedMissions = {}
  state.availableMissions = {}
  state.activeMission = nil
  log("I", logTag, "[DEBUG] All mission cooldowns and state cleared")
  saveState()

  -- Also clear navigation
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end
end

-- Start a specific mission directly by template ID
-- Usage: career_modules_mysummerMissions.debugStartMission("ghost", "ghost_chase_1")
local function debugStartMission(contactId, templateId)
  contactId = contactId or "ghost"

  -- Clear any active mission first
  if state.activeMission then
    log("I", logTag, "[DEBUG] Clearing existing active mission")
    abandonMission()
  end

  -- Generate and start the mission
  local mission = generateMission(contactId, templateId)
  if not mission then
    log("E", logTag, "[DEBUG] Failed to generate mission: " .. tostring(templateId))
    return false
  end

  -- Add to available and start it
  table.insert(state.availableMissions, mission)
  local result = startMission(mission.id)

  if result then
    log("I", logTag, "[DEBUG] Mission started: " .. mission.title .. " (" .. mission.type .. ")")
  end

  return result
end

-- Start a chase mission with specific difficulty
-- Usage: career_modules_mysummerMissions.debugChase("easy")
-- Usage: career_modules_mysummerMissions.debugChase("medium")
-- Usage: career_modules_mysummerMissions.debugChase("hard")
local function debugChase(difficulty)
  difficulty = difficulty or "medium"

  -- Find a chase mission with this difficulty
  local chaseMissions = {
    easy = { "ghost_chase_1", "muscle_chase_1", "techie_chase_1", "import_chase_1" },
    medium = { "ghost_chase_2", "muscle_chase_2", "techie_chase_2", "import_chase_2", "shadow_chase_1" },
    hard = { "ghost_chase_3", "muscle_chase_3", "techie_chase_3", "import_chase_3", "shadow_chase_2", "shadow_chase_3" },
  }

  local missionList = chaseMissions[difficulty]
  if not missionList then
    log("E", logTag, "[DEBUG] Unknown difficulty: " .. difficulty .. ". Use: easy, medium, hard")
    return false
  end

  -- Pick random mission from the list
  local templateId = missionList[math.random(#missionList)]
  local contactId = templateId:match("^(%w+)_")

  log("I", logTag, "[DEBUG] Starting chase mission: " .. templateId .. " (difficulty: " .. difficulty .. ")")
  return debugStartMission(contactId, templateId)
end

-- Start a delivery mission
-- Usage: career_modules_mysummerMissions.debugDelivery()
local function debugDelivery(contactId)
  contactId = contactId or "ghost"

  local deliveryMissions = {
    ghost = "ghost_delivery_1",
    techie = "techie_delivery_1",
    muscle = "muscle_delivery_1",
    import = "import_delivery_1",
    shadow = "shadow_delivery_1",
  }

  local templateId = deliveryMissions[contactId]
  if not templateId then
    log("E", logTag, "[DEBUG] No delivery mission for contact: " .. contactId)
    return false
  end

  log("I", logTag, "[DEBUG] Starting delivery mission for " .. contactId)
  return debugStartMission(contactId, templateId)
end

-- Start a surveillance mission
-- Usage: career_modules_mysummerMissions.debugSurveillance()
-- Usage: career_modules_mysummerMissions.debugSurveillance("shadow")
local function debugSurveillance(contactId)
  contactId = contactId or "ghost"

  -- Prevent restart if mission just ended
  if state.activeMission then
    log("W", logTag, "[DEBUG] Already have an active mission, not starting surveillance")
    return false
  end

  local surveillanceMissions = {
    ghost = "ghost_surveillance_1",
    shadow = "shadow_surveillance_1",
  }

  local templateId = surveillanceMissions[contactId]
  if not templateId then
    log("E", logTag, "[DEBUG] No surveillance mission for contact: " .. contactId)
    log("I", logTag, "[DEBUG] Available: ghost, shadow")
    return false
  end

  log("I", logTag, "[DEBUG] ====== STARTING SURVEILLANCE MISSION ======")
  log("I", logTag, "[DEBUG] Contact: " .. contactId .. ", Template: " .. templateId)
  return debugStartMission(contactId, templateId)
end

-- List all mission templates (all contacts, all types)
-- Usage: career_modules_mysummerMissions.debugListAll()
local function debugListAll()
  log("I", logTag, "[DEBUG] === ALL MISSION TEMPLATES ===")

  for contactId, templates in pairs(missionTemplates) do
    log("I", logTag, "")
    log("I", logTag, "Contact: " .. contactId:upper())
    for i, t in ipairs(templates) do
      local info = string.format("  %d. [%s] %s (lvl %d) - %s",
        i, t.type, t.id, t.requiredLevel or 1, t.title)
      log("I", logTag, info)
    end
  end

  return missionTemplates
end

-- Force time transition to a specific condition
-- Usage: career_modules_mysummerMissions.debugTimeTransition("night")
-- Usage: career_modules_mysummerMissions.debugTimeTransition("dawn")
local function debugTimeTransition(condition)
  condition = condition or "night"

  if not TIME_CONDITIONS[condition] then
    log("E", logTag, "[DEBUG] Unknown time condition: " .. condition)
    log("I", logTag, "[DEBUG] Available conditions: night, midnight, dawn, morning, noon, afternoon, dusk, evening")
    return false
  end

  log("I", logTag, "[DEBUG] Starting time transition to: " .. condition)
  return startTimeTransition(condition, nil)
end

-- Set time instantly (no transition)
-- Usage: career_modules_mysummerMissions.debugSetTime("night")    -- by condition name
-- Usage: career_modules_mysummerMissions.debugSetTime(21)         -- by hour (21:00)
-- Usage: career_modules_mysummerMissions.debugSetTime(0.375)      -- by raw tod.time (if < 1)
local function debugSetTime(input)
  local targetTodTime

  if type(input) == "string" then
    -- Named condition
    targetTodTime = TIME_CONDITIONS[input]
    if not targetTodTime then
      log("E", logTag, "[DEBUG] Unknown time condition: " .. input)
      log("I", logTag, "[DEBUG] Available: midnight, dawn, morning, noon, afternoon, dusk, evening, night")
      return false
    end
    local h = todTimeToHour(targetTodTime)
    log("I", logTag, string.format("[DEBUG] Setting time to '%s' = %02d:%02d (tod=%.3f)",
      input, math.floor(h), math.floor((h % 1) * 60), targetTodTime))
  elseif type(input) == "number" then
    if input >= 1 and input <= 24 then
      -- Treat as hour
      targetTodTime = hourToTodTime(input)
      log("I", logTag, string.format("[DEBUG] Setting time to %02d:00 (tod=%.3f)", input, targetTodTime))
    else
      -- Treat as raw tod.time
      targetTodTime = input
      local h = todTimeToHour(input)
      log("I", logTag, string.format("[DEBUG] Setting raw tod.time=%.3f = %02d:%02d",
        input, math.floor(h), math.floor((h % 1) * 60)))
    end
  else
    log("E", logTag, "[DEBUG] Invalid input type")
    return false
  end

  -- Show before
  local before = getCurrentTimeOfDay()
  local beforeHour = todTimeToHour(before)
  log("I", logTag, string.format("[DEBUG] BEFORE: %02d:%02d (tod=%.3f)",
    math.floor(beforeHour), math.floor((beforeHour % 1) * 60), before))

  setTimeOfDay(targetTodTime)

  -- Show after
  local after = getCurrentTimeOfDay()
  local afterHour = todTimeToHour(after)
  log("I", logTag, string.format("[DEBUG] AFTER: %02d:%02d (tod=%.3f)",
    math.floor(afterHour), math.floor((afterHour % 1) * 60), after))

  return true
end

-- Get current time info
-- Usage: career_modules_mysummerMissions.debugGetTime()
local function debugGetTime()
  local todTime = getCurrentTimeOfDay()
  local actualHour = todTimeToHour(todTime)
  local hours = math.floor(actualHour)
  local minutes = math.floor((actualHour - hours) * 60)

  log("I", logTag, "[DEBUG] === CURRENT TIME ===")
  log("I", logTag, string.format("[DEBUG] tod.time = %.3f", todTime))
  log("I", logTag, string.format("[DEBUG] Actual time = %02d:%02d", hours, minutes))

  -- Find closest named time
  local closestName = "unknown"
  local closestDiff = 1
  for name, time in pairs(TIME_CONDITIONS) do
    local diff = math.abs(todTime - time)
    if diff > 0.5 then diff = 1 - diff end
    if diff < closestDiff then
      closestDiff = diff
      closestName = name
    end
  end

  log("I", logTag, "[DEBUG] Closest condition: " .. closestName)

  -- Show all time conditions for reference
  log("I", logTag, "[DEBUG] Time conditions reference:")
  local sorted = {}
  for name, time in pairs(TIME_CONDITIONS) do
    local h = todTimeToHour(time)
    table.insert(sorted, { name = name, todTime = time, hour = h })
  end
  table.sort(sorted, function(a, b) return a.hour < b.hour end)
  for _, tc in ipairs(sorted) do
    local h = math.floor(tc.hour)
    local m = math.floor((tc.hour - h) * 60)
    local marker = math.abs(todTime - tc.todTime) < 0.04 and " <-- NOW" or ""
    log("I", logTag, string.format("  %s: %02d:%02d (tod=%.3f)%s", tc.name, h, m, tc.todTime, marker))
  end

  return todTime, actualHour
end

-- Diagnose TOD system
-- Usage: career_modules_mysummerMissions.debugTOD()
local function debugTOD()
  log("I", logTag, "[DEBUG] === TOD DIAGNOSIS ===")

  -- Check scenetree
  log("I", logTag, "[DEBUG] scenetree exists: " .. tostring(scenetree ~= nil))

  if scenetree then
    -- Direct tod access
    log("I", logTag, "[DEBUG] scenetree.tod exists: " .. tostring(scenetree.tod ~= nil))
    if scenetree.tod then
      log("I", logTag, "[DEBUG] scenetree.tod.time = " .. tostring(scenetree.tod.time))
      log("I", logTag, "[DEBUG] scenetree.tod.play = " .. tostring(scenetree.tod.play))
    end
  end

  -- Check core_environment (THE CORRECT WAY)
  log("I", logTag, "[DEBUG] core_environment exists: " .. tostring(core_environment ~= nil))
  if core_environment then
    if core_environment.getTimeOfDay then
      local todData = core_environment.getTimeOfDay()
      log("I", logTag, "[DEBUG] core_environment.getTimeOfDay() returned: " .. tostring(todData ~= nil))
      if todData then
        log("I", logTag, "[DEBUG]   Full TOD object contents:")
        if type(todData) == "table" then
          for k, v in pairs(todData) do
            log("I", logTag, "[DEBUG]     ." .. tostring(k) .. " = " .. tostring(v))
          end
        end
      end
    end

    log("I", logTag, "[DEBUG] core_environment.setTimeOfDay exists: " .. tostring(core_environment.setTimeOfDay ~= nil))
  end

  -- Test setting time using THE CORRECT METHOD (from BeamNG missionManager.lua)
  log("I", logTag, "[DEBUG] === TESTING TIME SET (core_environment method) ===")

  if core_environment and core_environment.getTimeOfDay and core_environment.setTimeOfDay then
    local todBefore = core_environment.getTimeOfDay()
    log("I", logTag, "[DEBUG] Before: time = " .. string.format("%.3f", todBefore.time or 0))

    -- Set to night (0.85)
    local newTod = deepcopy(todBefore)
    newTod.time = 0.85
    log("I", logTag, "[DEBUG] Setting to: 0.85 (night)")

    core_environment.setTimeOfDay(newTod)

    -- Verify
    local todAfter = core_environment.getTimeOfDay()
    log("I", logTag, "[DEBUG] After: time = " .. string.format("%.3f", todAfter.time or 0))
    log("I", logTag, "[DEBUG] SUCCESS: " .. tostring(math.abs((todAfter.time or 0) - 0.85) < 0.01))
    log("I", logTag, "[DEBUG] Check the sky! It should be dark now.")
  else
    log("E", logTag, "[DEBUG] core_environment API not available!")
  end

  return getCurrentTimeOfDay()
end

-- Test full surveillance flow: email -> follow -> quiz email -> answer
-- Usage: career_modules_mysummerMissions.debugSurveillanceFlow()
-- Usage: career_modules_mysummerMissions.debugSurveillanceFlow("quick") -- starts mission directly
local function debugSurveillanceFlow(mode)
  log("I", logTag, "")
  log("I", logTag, "=======================================================")
  log("I", logTag, "[DEBUG] SURVEILLANCE MISSION FLOW TEST")
  log("I", logTag, "=======================================================")
  log("I", logTag, "")
  log("I", logTag, "COMPLETE FLOW:")
  log("I", logTag, "  1. Receive email from contact with mission offer")
  log("I", logTag, "  2. Accept mission -> waypoint to target vehicle")
  log("I", logTag, "  3. Find and follow the target (keep distance!)")
  log("I", logTag, "  4. Target arrives at destination")
  log("I", logTag, "  5. Receive EMAIL from contact: 'Where did they go?'")
  log("I", logTag, "  6. Answer the quiz (select correct location)")
  log("I", logTag, "  7. Mission success/fail based on answer")
  log("I", logTag, "")

  if mode == "quick" then
    -- Direct start (skip email)
    log("I", logTag, "[1] QUICK MODE: Starting surveillance mission directly...")
    debugSurveillance("ghost")

    log("I", logTag, "")
    log("I", logTag, "[2] MISSION STARTED")
    log("I", logTag, "    - Target vehicle: " .. (surveillanceState.vehicleDesc or "unknown"))
    log("I", logTag, "    - Waypoint set to target location")
    log("I", logTag, "    - Follow it! Don't get too close or you'll be detected")
    log("I", logTag, "")
    log("I", logTag, "[3] DESTINATION INFO (SECRET - for testing):")
    if surveillanceState.destination then
      log("I", logTag, "    Destination: " .. surveillanceState.destination.name)
      log("I", logTag, "    Quiz options: " .. table.concat(surveillanceState.quizOptions, ", "))
    end
    log("I", logTag, "")
    log("I", logTag, "[4] WHEN TARGET ARRIVES:")
    log("I", logTag, "    - You will receive an EMAIL from the contact")
    log("I", logTag, "    - The email has 3 location options")
    log("I", logTag, "    - Answer to complete the mission")
    log("I", logTag, "")
    log("I", logTag, "[5] DEBUG COMMANDS:")
    log("I", logTag, "    career_modules_mysummerMissions.debugAnswerQuiz('correct')")
    log("I", logTag, "    career_modules_mysummerMissions.debugAnswerQuiz(1)  -- option 1")
    log("I", logTag, "    career_modules_mysummerMissions.debugCompleteMission(true)")

  else
    -- Full flow with email - FORCE surveillance mission specifically
    log("I", logTag, "[STEP 1] SENDING SURVEILLANCE MISSION EMAIL...")

    -- Clear cooldowns first to ensure we can send
    debugClearCooldowns()

    -- Generate surveillance mission specifically (not random)
    local contactId = "ghost"
    local templateId = "ghost_surveillance_1"
    local mission = generateMission(contactId, templateId)

    local result = false
    if mission then
      -- Add to available missions
      table.insert(state.availableMissions, mission)

      -- Send email via messages system
      if career_modules_mysummerMessages then
        career_modules_mysummerMessages.sendCustomMessage({
          from = contactId,
          fromName = "Ghost",
          subject = "Job: " .. mission.title,
          body = mission.description .. "\n\n" ..
                 "Reward: $" .. (mission.reward.money or 0) .. "\n" ..
                 "\nReply to accept this job.",
          icon = "[!]",
          priority = "high",
          missionId = mission.id,
          actionType = "mission_offer",
        })
        result = true
        log("I", logTag, "    Surveillance mission offer sent: " .. mission.title)
      end
    end

    if not result then
      log("E", logTag, "    Failed to generate surveillance mission!")
    end

    if result then
      log("I", logTag, "    Email sent! Check your messages (phone or computer).")
      log("I", logTag, "")
      log("I", logTag, "[STEP 2] ACCEPT THE MISSION:")
      log("I", logTag, "    - Open phone > Messages")
      log("I", logTag, "    - Read the email from Ghost")
      log("I", logTag, "    - Accept the mission")
      log("I", logTag, "")
      log("I", logTag, "[STEP 3] FOLLOW THE TARGET:")
      log("I", logTag, "    - A waypoint will appear to the target vehicle")
      log("I", logTag, "    - Find the vehicle and follow it")
      log("I", logTag, "    - Keep your distance (40-80m optimal)")
      log("I", logTag, "")
      log("I", logTag, "[STEP 4] WHEN TARGET ARRIVES:")
      log("I", logTag, "    - You will receive another EMAIL from Ghost")
      log("I", logTag, "    - 'Where did they go?' with 3 location options")
      log("I", logTag, "    - Answer correctly to complete the mission")
      log("I", logTag, "")
      log("I", logTag, "OR use quick mode: career_modules_mysummerMissions.debugSurveillanceFlow('quick')")
    else
      log("E", logTag, "    Could not send mission offer!")
    end
  end

  log("I", logTag, "")
  log("I", logTag, "=======================================================")

  return surveillanceState
end

-- Simulate quiz answer (for testing)
-- Usage: career_modules_mysummerMissions.debugAnswerQuiz(1)  -- answer option 1
-- Usage: career_modules_mysummerMissions.debugAnswerQuiz(2)  -- answer option 2
-- Usage: career_modules_mysummerMissions.debugAnswerQuiz("correct")  -- correct answer
local function debugAnswerQuiz(answer)
  if not surveillanceState.quizPhase then
    log("W", logTag, "[DEBUG] Not in quiz phase! Start a surveillance mission first.")
    return false
  end

  local actualAnswer
  if answer == "correct" then
    actualAnswer = surveillanceState.correctAnswer
    log("I", logTag, "[DEBUG] Using correct answer: " .. actualAnswer)
  elseif type(answer) == "number" and surveillanceState.quizOptions[answer] then
    actualAnswer = surveillanceState.quizOptions[answer]
    log("I", logTag, "[DEBUG] Using option " .. answer .. ": " .. actualAnswer)
  else
    log("E", logTag, "[DEBUG] Invalid answer. Use 1, 2, 3 or 'correct'")
    log("I", logTag, "[DEBUG] Options: " .. table.concat(surveillanceState.quizOptions, ", "))
    return false
  end

  return answerSurveillanceQuiz(actualAnswer)
end

-- Start an escort mission directly for testing
-- Usage: career_modules_mysummerMissions.debugEscort()
-- Usage: career_modules_mysummerMissions.debugEscort("ghost")
-- Usage: career_modules_mysummerMissions.debugEscort("muscle")
local function debugEscort(contactId)
  contactId = contactId or "ghost"

  log("I", logTag, "")
  log("I", logTag, "=======================================================")
  log("I", logTag, "[DEBUG] STARTING ESCORT MISSION FOR: " .. contactId)
  log("I", logTag, "=======================================================")

  -- Clear any active mission first
  if state.activeMission then
    log("I", logTag, "Abandoning current mission first...")
    abandonMission()
  end

  -- Find an escort mission for this contact
  local escortMission = nil
  local templates = missionTemplates[contactId]
  if templates then
    for _, template in ipairs(templates) do
      if template.type == MISSION_TYPES.ESCORT then
        escortMission = template
        break
      end
    end
  end

  if not escortMission then
    log("E", logTag, "No escort mission found for contact: " .. contactId)
    log("I", logTag, "Available contacts with escort missions: ghost, muscle")
    return false
  end

  -- Generate the mission
  local mission = generateMission(contactId, escortMission.id)
  if not mission then
    log("E", logTag, "Failed to generate escort mission")
    return false
  end

  -- Add to available and start
  table.insert(state.availableMissions, mission)
  local success = startMission(mission.id)

  if success then
    log("I", logTag, "")
    log("I", logTag, "ESCORT MISSION STARTED!")
    log("I", logTag, "  - You are now in a resistant vehicle")
    log("I", logTag, "  - Drive to the destination marked on your map")
    log("I", logTag, "  - Enemy waves will spawn and chase you")
    log("I", logTag, "  - Survive and reach the destination to complete!")
    log("I", logTag, "")
    log("I", logTag, "Mission: " .. mission.title)
    log("I", logTag, "Waves: " .. (mission.maxWaves or 5))
    log("I", logTag, "Destination: " .. (escortState.destinationName or "Unknown"))
    log("I", logTag, "")
    log("I", logTag, "DEBUG COMMANDS:")
    log("I", logTag, "  career_modules_mysummerMissions.debugCompleteMission(true)  -- win")
    log("I", logTag, "  career_modules_mysummerMissions.abandonMission()  -- abandon")
  else
    log("E", logTag, "Failed to start escort mission")
  end

  return success
end

-- List all available missions for a contact
-- Usage: career_modules_mysummerMissions.debugListMissions("ghost")
local function debugListMissions(contactId)
  contactId = contactId or "ghost"

  -- Show debug info
  local level = getContactLevel(contactId)
  log("I", logTag, "[DEBUG] Contact " .. contactId .. " level: " .. level)

  local templates = missionTemplates[contactId]
  if not templates then
    log("W", logTag, "[DEBUG] No templates found for " .. contactId)
    return {}
  end

  log("I", logTag, "[DEBUG] All templates for " .. contactId .. ":")
  for i, t in ipairs(templates) do
    local completed = state.completedMissions[t.id]
    local status = "AVAILABLE"
    if t.requiredLevel and level < t.requiredLevel then
      status = "LOCKED (need level " .. t.requiredLevel .. ")"
    elseif completed then
      local elapsed = os.time() - (completed.completedAt or 0)
      local remaining = 86400 - elapsed
      if remaining > 0 then
        status = "COOLDOWN (" .. math.floor(remaining / 60) .. " min left)"
      end
    end
    log("I", logTag, "  " .. i .. ". " .. t.title .. " - " .. status)
  end

  local missions = getAvailableMissionsForContact(contactId)
  log("I", logTag, "[DEBUG] Available now: " .. #missions)

  return missions
end

-- Show current mission status
-- Usage: career_modules_mysummerMissions.debugStatus()
local function debugStatus()
  log("I", logTag, "[DEBUG] === MISSION STATUS ===")

  if state.activeMission then
    local m = state.activeMission
    log("I", logTag, "  Active: " .. m.title .. " (" .. m.type .. ")")
    log("I", logTag, "  Status: " .. m.status)
    if m.startedAt and m.timeLimit then
      local remaining = m.timeLimit - (os.time() - m.startedAt)
      log("I", logTag, "  Time remaining: " .. remaining .. "s")
    end
    if m.pickedUp ~= nil then
      log("I", logTag, "  Picked up: " .. tostring(m.pickedUp))
    end

    -- Show location info
    if m.pickupLocation then
      local pos = m.pickupLocation.pos
      if pos then
        local posStr = type(pos) == "cdata" and string.format("vec3(%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
                      or (pos.x and string.format("table{x=%.1f, y=%.1f, z=%.1f}", pos.x, pos.y, pos.z))
                      or "unknown format"
        log("I", logTag, "  Pickup: " .. (m.pickupLocation.name or "?") .. " at " .. posStr)
      else
        log("E", logTag, "  Pickup location has no pos!")
      end
    end
    if m.dropoffLocation then
      local pos = m.dropoffLocation.pos
      if pos then
        local posStr = type(pos) == "cdata" and string.format("vec3(%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
                      or (pos.x and string.format("table{x=%.1f, y=%.1f, z=%.1f}", pos.x, pos.y, pos.z))
                      or "unknown format"
        log("I", logTag, "  Dropoff: " .. (m.dropoffLocation.name or "?") .. " at " .. posStr)
      end
    end

    -- Show player position for comparison
    local playerVehicle = be:getPlayerVehicle(0)
    if playerVehicle then
      local playerPos = playerVehicle:getPosition()
      log("I", logTag, "  Player at: " .. string.format("vec3(%.1f, %.1f, %.1f)", playerPos.x, playerPos.y, playerPos.z))

      -- Calculate distance to pickup if not picked up
      if not m.pickedUp and m.pickupLocation and m.pickupLocation.pos then
        local targetPos = toVec3(m.pickupLocation.pos)
        if targetPos then
          local dist2D = distance2D(playerPos, targetPos)
          local dist3D = (playerPos - targetPos):length()
          log("I", logTag, "  Distance to pickup: " .. string.format("%.1f", dist2D) .. "m (2D), " .. string.format("%.1f", dist3D) .. "m (3D)")
        end
      end
    end
  else
    log("I", logTag, "  No active mission")
  end

  log("I", logTag, "  Available offers: " .. #state.availableMissions)
  log("I", logTag, "  Completed missions: " .. tableSize(state.completedMissions))

  return state
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Get mission status for UI
local function getMissionStatus()
  local mission = state.activeMission
  if not mission then
    return { active = false }
  end

  local remaining = 0
  if mission.timeLimit and mission.startedAt then
    remaining = math.max(0, mission.timeLimit - (os.time() - mission.startedAt))
  end

  return {
    active = true,
    id = mission.id,
    title = mission.title,
    type = mission.type,
    remaining = remaining,
    timeLimit = mission.timeLimit,
    pickedUp = mission.pickedUp,
    pickupHint = mission.pickupHint,
    dropoffHint = mission.dropoffHint,
    requiresCargo = mission.requiresCargo,
    cargoSlots = mission.cargoSlots,
    reward = mission.reward,
  }
end

M.getAvailableMissionsForContact = getAvailableMissionsForContact
M.getActiveMission = function() return deepcopy(state.activeMission) end
M.getAvailableMissions = function() return deepcopy(state.availableMissions) end
M.getMissionStatus = getMissionStatus
M.startMission = startMission
M.completeMission = completeMission
M.abandonMission = abandonMission
M.offerMissionViaEmail = offerMissionViaEmail
M.isContactOnMissionCooldown = isContactOnMissionCooldown
M.answerSurveillanceQuiz = answerSurveillanceQuiz

-- Debug functions
M.debugOfferMission = debugOfferMission
M.debugCompleteMission = debugCompleteMission
M.debugClearCooldowns = debugClearCooldowns
M.debugListMissions = debugListMissions
M.debugStatus = debugStatus
M.debugStartMission = debugStartMission
M.debugChase = debugChase
M.debugDelivery = debugDelivery
M.debugSurveillance = debugSurveillance
M.debugListAll = debugListAll
M.debugTimeTransition = debugTimeTransition
M.debugSetTime = debugSetTime
M.debugGetTime = debugGetTime
M.debugTOD = debugTOD
M.debugSurveillanceFlow = debugSurveillanceFlow
M.debugAnswerQuiz = debugAnswerQuiz
M.debugEscort = debugEscort

-- Lifecycle
M.onUpdate = onUpdate
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onExtensionLoaded = onExtensionLoaded

-- Recovery/Tow hook - cancels mission when player uses tow
M.onVehicleRecoveryStarted = onVehicleRecoveryStarted

-- Alternative hook names that BeamNG might use
M.onTowToRoad = onVehicleRecoveryStarted
M.onRecoveryStarted = onVehicleRecoveryStarted

return M
