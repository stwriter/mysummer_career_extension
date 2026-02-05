-- MySummer Story Races
-- Manages chapter-based races with progression
-- Sends player to location, triggers race on arrival

local M = {}
M.moduleName = "career_modules_mysummerStoryRaces"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerRaceManager",
  "career_modules_mysummerMissions",
  "career_modules_mysummerChat",
}

local logTag = "mysummerStoryRaces"
local saveFile = "mysummer_story_races.json"

-- Forward declarations
local saveState
local loadState
local completeMission

-- ============================================================================
-- LOCALIZATION
-- ============================================================================

local function tr(key, default)
  return translateLanguage(key, default or key)
end

-- ============================================================================
-- RACE DEFINITIONS BY CHAPTER
-- ============================================================================

-- Story contact missions (1 per chapter, mandatory)
-- Each chapter introduces a new mechanic using real missions from mysummerMissions.lua:
-- Prologue: No mission (just races)
-- Ch1: delivery (simple intro) - Basic delivery tutorial
-- Ch2: delivery (with heat) - Delivery under pressure
-- Ch3: surveillance - Stealth mechanic
-- Ch4: chase - Action mechanic
-- Ch5: escort - Combat/survival mechanic
-- Ch6: escort (final) - Ultimate test
local storyMissions = {
  {
    id = "ch1_mission",
    chapter = 1,
    requiredLevel = 1, -- Chapter 1 unlocked at 300 XP
    requiresProjectCar = false,
    missionRef = "ghost_delivery_1", -- Reference to mission in mysummerMissions
    contact = "ghost",
    name = { en = "The Message", es = "El Mensaje" },
    description = {
      en = "A mysterious message from an unknown number. Ghost needs a package moved.",
      es = "Un mensaje misterioso de un numero desconocido. Ghost necesita mover un paquete."
    },
    tutorialHint = {
      en = "Delivery missions: Pick up at one location, deliver to another. Watch the timer.",
      es = "Misiones de entrega: Recoge en un sitio, entrega en otro. Vigila el tiempo."
    },
    xpReward = 100,
    moneyReward = 0,
    introDialogue = {
      { en = "You don't know me. But I know you.", es = "No me conoces. Pero yo a ti si." },
      { en = "That ETK project you're working on... it has potential.", es = "Ese proyecto ETK en el que trabajas... tiene potencial." },
      { en = "I need a favor. Move a package for me. Don't ask questions.", es = "Necesito un favor. Mueve un paquete para mi. No hagas preguntas." },
    },
    duringDialogues = {
      { afterSeconds = 30, messages = {
        { en = "Keep moving. Time is money.", es = "Sigue moviendote. El tiempo es dinero." },
      }},
      { afterSeconds = 90, messages = {
        { en = "You're doing good. Don't slow down.", es = "Lo estas haciendo bien. No reduzcas." },
      }},
    },
    completionDialogue = {
      { en = "Welcome to the scene. I'm Ghost. I'll be in touch.", es = "Bienvenido a la escena. Soy Ghost. Estare en contacto." },
      { en = "There are races happening. Small ones, for now. I'll send you the details.", es = "Hay carreras. Pequenas, por ahora. Te enviare los detalles." },
    },
  },
  {
    id = "ch2_mission",
    chapter = 2,
    requiredLevel = 1,
    requiresProjectCar = false,
    missionRef = "ghost_delivery_2", -- Hot Cargo - delivery with heat
    contact = "ghost",
    name = { en = "Hot Cargo", es = "Carga Caliente" },
    description = {
      en = "This delivery is risky. The heat is real. Don't get stopped.",
      es = "Esta entrega es arriesgada. El calor es real. No te paren."
    },
    tutorialHint = {
      en = "Some deliveries have 'heat' - police will be looking for you.",
      es = "Algunas entregas tienen 'calor' - la policia te buscara."
    },
    xpReward = 150,
    moneyReward = 0,
    introDialogue = {
      { en = "This one's different. The cops are sniffing around.", es = "Esta es diferente. Los polis estan husmeando." },
      { en = "Get the goods from the auto shop, deliver to the lot. Fast.", es = "Recoge la mercancia del taller, entregala en el parking. Rapido." },
    },
    duringDialogues = {
      { afterSeconds = 20, messages = {
        { en = "Eyes on the road. Eyes on the mirrors.", es = "Ojos en la carretera. Ojos en los espejos." },
      }},
      { afterSeconds = 60, messages = {
        { en = "If you see blue lights, lose them. Don't lead them to the drop.", es = "Si ves luces azules, pierdalos. No los lleves a la entrega." },
      }},
      { afterSeconds = 120, messages = {
        { en = "Almost there. Stay calm.", es = "Casi llegas. Mantén la calma." },
      }},
    },
    completionDialogue = {
      { en = "Not bad for a rookie. You can handle pressure.", es = "No esta mal para un novato. Aguantas la presion." },
      { en = "I've got more work coming. Stay ready.", es = "Tengo mas trabajo. Estate listo." },
    },
  },
  {
    id = "ch3_mission",
    chapter = 3,
    requiredLevel = 2,
    requiresProjectCar = false,
    missionRef = "ghost_surveillance_1", -- Eyes On
    contact = "ghost",
    name = { en = "Eyes On", es = "Vigilancia" },
    description = {
      en = "Ghost needs someone followed. Keep your distance, don't get spotted.",
      es = "Ghost necesita que sigas a alguien. Manten la distancia, no te dejes ver."
    },
    tutorialHint = {
      en = "Surveillance: Follow the target. Too close = detected. Too far = lost. Watch the meter.",
      es = "Vigilancia: Sigue al objetivo. Muy cerca = detectado. Muy lejos = perdido. Vigila el indicador."
    },
    xpReward = 200,
    moneyReward = 0,
    introDialogue = {
      { en = "There's someone I need watched. A rat, maybe.", es = "Hay alguien a quien necesito vigilar. Una rata, quizas." },
      { en = "Follow him. Stay back. Report where he goes.", es = "Siguelo. Mantente atras. Dime a donde va." },
    },
    duringDialogues = {
      { afterSeconds = 15, messages = {
        { en = "Not too close. Let him breathe.", es = "No demasiado cerca. Dejale respirar." },
      }},
      { afterSeconds = 45, messages = {
        { en = "He's nervous. Stay in the traffic flow.", es = "Esta nervioso. Mantente en el trafico." },
      }},
      { afterSeconds = 90, messages = {
        { en = "Interesting... he's heading somewhere specific.", es = "Interesante... va a algun sitio especifico." },
      }},
    },
    completionDialogue = {
      { en = "Good intel. Now I know where to find him.", es = "Buena informacion. Ahora se donde encontrarlo." },
      { en = "You've got a steady hand. Techie wants to meet you.", es = "Tienes mano firme. Techie quiere conocerte." },
    },
    unlockContact = "techie",
  },
  {
    id = "ch4_mission",
    chapter = 4,
    requiredLevel = 3,
    requiresProjectCar = false,
    missionRef = "shadow_chase_1", -- First chase mission
    contact = "shadow",
    name = { en = "Dirty Work", es = "Trabajo Sucio" },
    description = {
      en = "Shadow needs someone stopped. No questions, no witnesses.",
      es = "Shadow necesita que detengas a alguien. Sin preguntas, sin testigos."
    },
    tutorialHint = {
      en = "Chase missions: Pursue the target and force them to stop. Ram them if needed.",
      es = "Misiones de persecucion: Persigue al objetivo y obligalo a parar. Embistelo si es necesario."
    },
    xpReward = 300,
    moneyReward = 0,
    introDialogue = {
      { en = "...", es = "..." },
      { en = "Someone's been talking. That stops tonight.", es = "Alguien ha estado hablando. Eso termina esta noche." },
    },
    duringDialogues = {
      { afterSeconds = 10, messages = {
        { en = "Don't let them reach the highway.", es = "No les dejes llegar a la autopista." },
      }},
      { afterSeconds = 40, messages = {
        { en = "Pin them down. Use your car.", es = "Acorraladlos. Usa tu coche." },
      }},
    },
    completionDialogue = {
      { en = "Clean work. You're crossing lines now. No going back.", es = "Trabajo limpio. Estas cruzando lineas. No hay vuelta atras." },
    },
    unlockContact = "shadow",
  },
  {
    id = "ch5_mission",
    chapter = 5,
    requiredLevel = 4,
    requiresProjectCar = true,
    missionRef = "ghost_escort_1", -- Running the Gauntlet
    contact = "ghost",
    name = { en = "The Return", es = "El Retorno" },
    description = {
      en = "Ghost resurfaces with an urgent request. His enemies are closing in.",
      es = "Ghost reaparece con una peticion urgente. Sus enemigos se acercan."
    },
    tutorialHint = {
      en = "Escort missions: Survive enemy waves while reaching the destination.",
      es = "Misiones de escolta: Sobrevive oleadas de enemigos mientras llegas al destino."
    },
    xpReward = 400,
    moneyReward = 0,
    introDialogue = {
      { en = "It's been a while. I went quiet for a reason.", es = "Ha pasado tiempo. Me calle por una razon." },
      { en = "They're hunting me now. I need you to drive my truck through their blockade.", es = "Me estan cazando. Necesito que conduzcas mi camion a traves de su bloqueo." },
    },
    duringDialogues = {
      { afterSeconds = 5, messages = {
        { en = "Here they come. Don't stop!", es = "Aqui vienen. No pares!" },
      }},
      { afterSeconds = 30, messages = {
        { en = "More incoming. Push through!", es = "Vienen mas. Atraviesalos!" },
      }},
      { afterSeconds = 60, messages = {
        { en = "You're doing it. Keep going!", es = "Lo estas logrando. Sigue adelante!" },
      }},
    },
    completionDialogue = {
      { en = "The Big One is real. It's happening. Your grandfather knew about it.", es = "The Big One es real. Esta pasando. Tu abuelo lo sabia." },
      { en = "You need to qualify. Official rallies. Then we'll talk about the race.", es = "Necesitas clasificar. Rallys oficiales. Luego hablaremos de la carrera." },
    },
  },
  {
    id = "ch6_mission",
    chapter = 6,
    requiredLevel = 5,
    requiresProjectCar = true,
    missionRef = "ghost_escort_2", -- Death Race - hardest escort
    contact = "ghost",
    name = { en = "The Legacy", es = "El Legado" },
    description = {
      en = "Everyone wants Ghost dead. You're driving through all of them.",
      es = "Todos quieren a Ghost muerto. Vas a atravesarlos a todos."
    },
    tutorialHint = {
      en = "Final test: Multiple waves, high intensity. Prove you're ready for The Big One.",
      es = "Prueba final: Multiples oleadas, alta intensidad. Demuestra que estas listo para The Big One."
    },
    xpReward = 500,
    moneyReward = 0,
    introDialogue = {
      { en = "Every crew in the city wants my blood tonight.", es = "Cada banda de la ciudad quiere mi sangre esta noche." },
      { en = "You're driving my armored rig through all of them. Don't stop. Don't look back.", es = "Vas a conducir mi camion blindado a traves de todos ellos. No pares. No mires atras." },
    },
    duringDialogues = {
      { afterSeconds = 5, messages = {
        { en = "They're everywhere. MOVE!", es = "Estan por todos lados. MUEVETE!" },
      }},
      { afterSeconds = 25, messages = {
        { en = "That was wave one. More coming.", es = "Esa fue la primera oleada. Vienen mas." },
      }},
      { afterSeconds = 50, messages = {
        { en = "They're throwing everything at us!", es = "Nos estan tirando todo lo que tienen!" },
      }},
      { afterSeconds = 80, messages = {
        { en = "Almost there. Don't give up now!", es = "Casi llegamos. No te rindas ahora!" },
      }},
    },
    completionDialogue = {
      { en = "He never got to race it. An accident, the night before. Some say sabotage.", es = "Nunca pudo correrla. Un accidente, la noche anterior. Algunos dicen sabotaje." },
      { en = "That ETK you're building... it was his dream. Now it's yours.", es = "Ese ETK que estas construyendo... era su sueno. Ahora es tuyo." },
      { en = "Do it for both of you.", es = "Hazlo por los dos." },
    },
  },
}

-- Story races organized by chapter, matching branch level requirements from info.json
local storyRaces = {
  -- Prologue (Level 0): 3 races - Street Racing Begins
  {
    chapter = 0,
    chapterName = "prologue",
    requiredLevel = 0, -- Available from start
    requiresProjectCar = false,
    races = {
      {
        id = "prologue_race1",
        missionId = "west_coast_usa/aiRace/001-STREET/info.json",
        name = { en = "Downtown Dash", es = "Carrera Centro" },
        description = { en = "The classic downtown circuit where legends are made", es = "El circuito clasico del centro donde nacen las leyendas" },
        contact = "ghost",
        xpReward = 200,
        moneyReward = 500,
      },
      {
        id = "prologue_race2",
        missionId = "west_coast_usa/aiRace/002-STREET/info.json",
        name = { en = "Industrial Loop", es = "Circuito Industrial" },
        description = { en = "Quick sprint through the industrial district", es = "Sprint rapido por el distrito industrial" },
        contact = "ghost",
        xpReward = 200,
        moneyReward = 500,
      },
      {
        id = "prologue_race3",
        missionId = "west_coast_usa/aiRace/003-STREET/info.json",
        name = { en = "Harbor Run", es = "Carrera del Puerto" },
        description = { en = "Late night race near the docks", es = "Carrera nocturna cerca de los muelles" },
        contact = "ghost",
        xpReward = 220,
        moneyReward = 700,
      },
    },
  },
  -- Chapter 1 (Level 1): 3 races - Racing Among Friends
  {
    chapter = 1,
    chapterName = "chapter1",
    requiredLevel = 1, -- Requires 300 XP
    requiresProjectCar = false,
    races = {
      {
        id = "ch1_race1",
        missionId = "west_coast_usa/aiRace/004-STREET/info.json",
        name = { en = "Parking Night", es = "Noche en el Parking" },
        description = { en = "Informal race at the old parking lot", es = "Carrera informal en el viejo parking" },
        contact = "ghost",
        xpReward = 250,
        moneyReward = 1000,
      },
      {
        id = "ch1_race2",
        missionId = "west_coast_usa/aiRace/005-STREET/info.json",
        name = { en = "Backroad Sprint", es = "Sprint Rural" },
        description = { en = "Country roads with friends", es = "Carreteras rurales con amigos" },
        contact = "ghost",
        xpReward = 250,
        moneyReward = 1200,
      },
      {
        id = "ch1_race3",
        missionId = "west_coast_usa/aiRace/006-STREET/info.json",
        name = { en = "Highway Challenge", es = "Desafio en Autopista" },
        description = { en = "Late night highway race", es = "Carrera nocturna en autopista" },
        contact = "ghost",
        xpReward = 280,
        moneyReward = 1500,
      },
    },
  },
  -- Chapter 2 (Level 2): 2 races - Low Underground
  {
    chapter = 2,
    chapterName = "chapter2",
    requiredLevel = 2, -- Requires 800 XP
    requiresProjectCar = false,
    races = {
      {
        id = "ch2_race1",
        missionId = "west_coast_usa/aiRace/007-STREET/info.json",
        name = { en = "Midnight Street", es = "Calle de Medianoche" },
        description = { en = "First taste of the underground", es = "Primer contacto con el underground" },
        contact = "ghost",
        xpReward = 300,
        moneyReward = 2000,
      },
      {
        id = "ch2_race2",
        missionId = "west_coast_usa/aiRace/008-STREET/info.json",
        name = { en = "Industrial Gauntlet", es = "Reto Industrial" },
        description = { en = "High stakes in the industrial zone", es = "Grandes apuestas en la zona industrial" },
        contact = "ghost",
        xpReward = 320,
        moneyReward = 2500,
      },
    },
  },
  -- Chapter 3 (Level 3): Rally content - Regional Rallies (PLACEHOLDER - to be added)
  {
    chapter = 3,
    chapterName = "chapter3",
    requiredLevel = 3, -- Requires 1500 XP
    requiresProjectCar = false,
    races = {
      -- PLACEHOLDER RACES - Repeat early races until rally content is added
      {
        id = "ch3_placeholder1",
        missionId = "west_coast_usa/aiRace/001-STREET/info.json",
        name = { en = "[PLACEHOLDER] Downtown Dash", es = "[PLACEHOLDER] Carrera Centro" },
        description = { en = "Placeholder - Rally content coming soon", es = "Placeholder - Contenido rally proximamente" },
        contact = "ghost",
        xpReward = 200,
        moneyReward = 500,
      },
      {
        id = "ch3_placeholder2",
        missionId = "west_coast_usa/aiRace/002-STREET/info.json",
        name = { en = "[PLACEHOLDER] Industrial Loop", es = "[PLACEHOLDER] Circuito Industrial" },
        description = { en = "Placeholder - Rally content coming soon", es = "Placeholder - Contenido rally proximamente" },
        contact = "ghost",
        xpReward = 200,
        moneyReward = 500,
      },
      {
        id = "ch3_placeholder3",
        missionId = "west_coast_usa/aiRace/003-STREET/info.json",
        name = { en = "[PLACEHOLDER] Harbor Run", es = "[PLACEHOLDER] Carrera del Puerto" },
        description = { en = "Placeholder - Rally content coming soon", es = "Placeholder - Contenido rally proximamente" },
        contact = "ghost",
        xpReward = 220,
        moneyReward = 700,
      },
    },
  },
  -- Chapter 4 (Level 4): 2 races - High Underground
  {
    chapter = 4,
    chapterName = "chapter4",
    requiredLevel = 4, -- Requires 2500 XP
    requiresProjectCar = false,
    races = {
      {
        id = "ch4_race1",
        missionId = "west_coast_usa/aiRace/009-STREET/info.json",
        name = { en = "Night Kings", es = "Reyes de la Noche" },
        description = { en = "Only the best race here", es = "Solo los mejores corren aqui" },
        contact = "shadow",
        xpReward = 350,
        moneyReward = 5000,
      },
      {
        id = "ch4_race2",
        missionId = "west_coast_usa/aiRace/010-STREET/info.json",
        name = { en = "Shadow's Test", es = "Prueba de Shadow" },
        description = { en = "High heat, high stakes", es = "Mucho calor, grandes apuestas" },
        contact = "shadow",
        xpReward = 400,
        moneyReward = 6000,
      },
    },
  },
  -- Chapter 5 (Level 5): Circuit/Rally content - Official Rallies (PLACEHOLDER - to be added)
  {
    chapter = 5,
    chapterName = "chapter5",
    requiredLevel = 5, -- Requires 4000 XP
    requiresProjectCar = true,
    races = {
      -- PLACEHOLDER RACES - Repeat races until circuit/rally content is added
      {
        id = "ch5_placeholder1",
        missionId = "west_coast_usa/aiRace/004-STREET/info.json",
        name = { en = "[PLACEHOLDER] Parking Night", es = "[PLACEHOLDER] Noche en el Parking" },
        description = { en = "Placeholder - Circuit content coming soon", es = "Placeholder - Contenido circuito proximamente" },
        contact = "ghost",
        xpReward = 250,
        moneyReward = 1000,
      },
      {
        id = "ch5_placeholder2",
        missionId = "west_coast_usa/aiRace/005-STREET/info.json",
        name = { en = "[PLACEHOLDER] Backroad Sprint", es = "[PLACEHOLDER] Sprint Rural" },
        description = { en = "Placeholder - Circuit content coming soon", es = "Placeholder - Contenido circuito proximamente" },
        contact = "ghost",
        xpReward = 250,
        moneyReward = 1200,
      },
      {
        id = "ch5_placeholder3",
        missionId = "west_coast_usa/aiRace/006-STREET/info.json",
        name = { en = "[PLACEHOLDER] Highway Challenge", es = "[PLACEHOLDER] Desafio en Autopista" },
        description = { en = "Placeholder - Circuit content coming soon", es = "Placeholder - Contenido circuito proximamente" },
        contact = "ghost",
        xpReward = 280,
        moneyReward = 1500,
      },
    },
  },
  -- Chapter 6 (Level 6): The Big One (PLACEHOLDER - to be added)
  {
    chapter = 6,
    chapterName = "chapter6",
    requiredLevel = 6, -- Requires 6000 XP
    requiresProjectCar = true,
    races = {
      -- PLACEHOLDER RACES - Repeat races until The Big One is created
      {
        id = "ch6_placeholder1",
        missionId = "west_coast_usa/aiRace/007-STREET/info.json",
        name = { en = "[PLACEHOLDER] Midnight Street", es = "[PLACEHOLDER] Calle de Medianoche" },
        description = { en = "Placeholder - The Big One coming soon", es = "Placeholder - La Gran Carrera proximamente" },
        contact = "ghost",
        xpReward = 300,
        moneyReward = 2000,
      },
      {
        id = "ch6_placeholder2",
        missionId = "west_coast_usa/aiRace/008-STREET/info.json",
        name = { en = "[PLACEHOLDER] Industrial Gauntlet", es = "[PLACEHOLDER] Reto Industrial" },
        description = { en = "Placeholder - The Big One coming soon", es = "Placeholder - La Gran Carrera proximamente" },
        contact = "ghost",
        xpReward = 320,
        moneyReward = 2500,
      },
    },
  },
}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  completedRaces = {}, -- { raceId = { completed = true, bestTime = 123, wins = 1 } }
  completedMissions = {}, -- { missionId = true }
  activeRace = nil,    -- Currently selected race (waiting for player to arrive, then starts correct version)
  activeMission = nil, -- Currently active story mission
  currentChapter = 0,  -- Current story chapter (0 = prologue)
  -- Story dialogue state
  drivingDialogueTriggered = {}, -- Which dialogues have been shown
  missionElapsedTime = 0, -- Time elapsed since story mission started (for timed dialogues)
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get player's current streetracing level
local function getPlayerLevel()
  if career_modules_playerAttributes then
    local attr = career_modules_playerAttributes.getAttributeValue("mysummer-streetracing")
    if attr then
      -- Convert XP to level
      local xp = attr or 0
      if xp >= 6000 then return 6
      elseif xp >= 4000 then return 5
      elseif xp >= 2500 then return 4
      elseif xp >= 1500 then return 3
      elseif xp >= 800 then return 2
      elseif xp >= 300 then return 1
      else return 0
      end
    end
  end
  return 0
end

-- Check if player is driving the project car (ETK-I)
local function isPlayerInProjectCar()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return false end

  local model = playerVehicle:getJBeamFilename()
  return model == "etki"
end

-- Get localized text
local function getLocalizedText(textTable)
  if not textTable then return "" end
  local lang = Lua and Lua.language or "en"
  if lang:find("es") then
    return textTable.es or textTable.en or ""
  end
  return textTable.en or ""
end

-- Get mission start position from info.json
local function getMissionStartPosition(missionPath)
  -- missionPath is like "west_coast_usa/aiRace/001-STREET/info.json"
  local fullPath = "/gameplay/missions/" .. missionPath
  local infoData = jsonReadFile(fullPath)

  if infoData and infoData.startTrigger and infoData.startTrigger.pos then
    local pos = infoData.startTrigger.pos
    if pos[1] and pos[2] and pos[3] then
      return vec3(pos[1], pos[2], pos[3])
    end
  end

  log("W", logTag, "Could not get start position for mission: " .. tostring(missionPath))
  return nil
end

-- Get player vehicle position
local function getPlayerPosition()
  local playerVehicle = be:getPlayerVehicle(0)
  if playerVehicle then
    return playerVehicle:getPosition()
  end
  return nil
end

-- ============================================================================
-- RACE ACCESS
-- ============================================================================

-- Get all races available for a chapter
local function getChapterRaces(chapter)
  for _, chapterData in ipairs(storyRaces) do
    if chapterData.chapter == chapter then
      return chapterData
    end
  end
  return nil
end

-- Find story race ID by BeamNG mission ID
-- The missionId from BeamNG is like "west_coast_usa-aiRace-001-STREET" or similar
local function findRaceIdByMission(beamngMissionId)
  -- First check if there's an active race - that's likely the one that just finished
  if state.activeRace and state.activeRace.raceId then
    return state.activeRace.raceId
  end

  -- Otherwise search through all races to find matching missionId
  -- BeamNG mission IDs are formatted like "west_coast_usa-aiRace-001-STREET"
  -- Our missionId is like "west_coast_usa/aiRace/001-STREET/info.json"
  for _, chapterData in ipairs(storyRaces) do
    for _, race in ipairs(chapterData.races) do
      -- Convert our path format to BeamNG format for comparison
      local ourPath = race.missionId:gsub("/info%.json$", ""):gsub("/", "-")
      -- Also try with REPEAT suffix
      local ourPathRepeat = ourPath:gsub("%-STREET$", "-STREET-REPEAT")

      if beamngMissionId == ourPath or beamngMissionId == ourPathRepeat then
        return race.id
      end

      -- Also try direct substring match
      if beamngMissionId:find(race.id, 1, true) then
        return race.id
      end
    end
  end

  log("D", logTag, "No story race found for BeamNG mission: " .. tostring(beamngMissionId))
  return nil
end

-- Check if a race is accessible
local function isRaceAccessible(raceId)
  local playerLevel = getPlayerLevel()

  for _, chapterData in ipairs(storyRaces) do
    for _, race in ipairs(chapterData.races) do
      if race.id == raceId then
        -- Check level requirement
        if playerLevel < chapterData.requiredLevel then
          return false, "level", chapterData.requiredLevel
        end
        -- Check project car requirement
        if chapterData.requiresProjectCar and not isPlayerInProjectCar() then
          return false, "projectcar", nil
        end
        return true, nil, nil
      end
    end
  end
  return false, "notfound", nil
end

-- Check if race is completed
local function isRaceCompleted(raceId)
  return state.completedRaces[raceId] and state.completedRaces[raceId].completed
end

-- Check if story mission is completed
local function isMissionCompleted(missionId)
  return state.completedMissions[missionId] == true
end

-- Get story mission by ID
local function getStoryMission(missionId)
  for _, mission in ipairs(storyMissions) do
    if mission.id == missionId then
      return mission
    end
  end
  return nil
end

-- Check if story mission is accessible
local function isMissionAccessible(missionId)
  local mission = getStoryMission(missionId)
  if not mission then return false, "notfound" end

  local playerLevel = getPlayerLevel()

  -- Check level requirement
  if playerLevel < mission.requiredLevel then
    return false, "level", mission.requiredLevel
  end

  -- Check project car requirement
  if mission.requiresProjectCar and not isPlayerInProjectCar() then
    return false, "projectcar"
  end

  return true
end

-- ============================================================================
-- STORY DIALOGUE SYSTEM
-- Mission mechanics are handled by mysummerMissions.lua.
-- Story missions add a narrative layer with timed dialogues.
-- ============================================================================

-- Show story dialogue via chat overlay
local function showStoryDialogue(contactId, messageTable)
  local content = getLocalizedText(messageTable)
  if career_modules_mysummerChat then
    career_modules_mysummerChat.showDialogueMessage(contactId, content)
  end
  log("I", logTag, "Story dialogue: " .. content)
end

-- Check and trigger time-based story dialogues during mission
local function checkStoryDialogues(dtSim)
  if not state.activeMission then return end

  local mission = getStoryMission(state.activeMission.missionId)
  if not mission or not mission.duringDialogues then return end

  -- Update mission elapsed time
  state.missionElapsedTime = (state.missionElapsedTime or 0) + dtSim

  -- Check time-based dialogues
  for i, dialogue in ipairs(mission.duringDialogues) do
    local dialogueKey = state.activeMission.missionId .. "_during_" .. i

    -- Skip already triggered
    if state.drivingDialogueTriggered[dialogueKey] then
      goto continue
    end

    -- Trigger based on elapsed time
    if dialogue.afterSeconds and state.missionElapsedTime >= dialogue.afterSeconds then
      state.drivingDialogueTriggered[dialogueKey] = true
      for _, msg in ipairs(dialogue.messages) do
        showStoryDialogue(mission.contact, msg)
      end
    end

    ::continue::
  end
end

-- ============================================================================
-- STORY MISSION MANAGEMENT
-- ============================================================================

-- Start a story mission
local function selectMission(missionId)
  local accessible, reason, value = isMissionAccessible(missionId)
  if not accessible then
    log("W", logTag, "Mission not accessible: " .. missionId .. " reason: " .. tostring(reason))
    return { success = false, reason = reason, value = value }
  end

  local mission = getStoryMission(missionId)
  if not mission then
    return { success = false, reason = "notfound" }
  end

  -- Check if there's already an active mission in mysummerMissions
  if career_modules_mysummerMissions then
    local activeMission = career_modules_mysummerMissions.getActiveMission()
    if activeMission then
      log("W", logTag, "Cannot start story mission - there's an active mission")
      return { success = false, reason = "active_mission" }
    end
  end

  -- Show intro dialogue if exists
  if mission.introDialogue and career_modules_mysummerChat then
    local messages = {}
    for _, msg in ipairs(mission.introDialogue) do
      table.insert(messages, getLocalizedText(msg))
    end
    career_modules_mysummerChat.showDialogue(mission.contact, messages)
  end

  -- Show tutorial hint
  if mission.tutorialHint and guihooks then
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = getLocalizedText(mission.name),
      msg = getLocalizedText(mission.tutorialHint),
    })
  end

  -- Set tracking state
  state.activeMission = {
    missionId = missionId,
    name = getLocalizedText(mission.name),
    contact = mission.contact,
    xpReward = mission.xpReward,
    moneyReward = mission.moneyReward,
    chapter = mission.chapter,
    startTime = os.time(),
    missionRef = mission.missionRef,
  }

  -- Reset dialogue state for story dialogues
  state.drivingDialogueTriggered = {}
  state.missionElapsedTime = 0

  saveState()

  -- Start the actual mission from mysummerMissions
  if mission.missionRef and career_modules_mysummerMissions then
    -- Extract contact from missionRef (e.g., "ghost_delivery_1" -> "ghost")
    local refContact = mission.missionRef:match("^(%w+)_")
    if refContact then
      local success = career_modules_mysummerMissions.startMissionFromTemplate(refContact, mission.missionRef, missionId)
      if not success then
        log("E", logTag, "Failed to start mission from template: " .. mission.missionRef)
        state.activeMission = nil
        saveState()
        return { success = false, reason = "mission_start_failed" }
      end
    end
  end

  log("I", logTag, "Story mission selected: " .. missionId)

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerStoryMissionSelected", {
      missionId = missionId,
      name = state.activeMission.name,
      contact = state.activeMission.contact,
    })
  end

  return { success = true }
end

-- Cancel active mission
local function cancelMission()
  if not state.activeMission then return end

  log("I", logTag, "Story mission cancelled: " .. state.activeMission.missionId)

  state.activeMission = nil
  state.missionPhase = nil
  state.drivingDialogueTriggered = {}

  saveState()

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end
end

-- Called by mysummerMissions when a story mission completes
local function onMissionCompleted(storyMissionId, success)
  if not state.activeMission or state.activeMission.missionId ~= storyMissionId then
    log("W", logTag, "onMissionCompleted called but no matching active story mission")
    return
  end

  local mission = getStoryMission(storyMissionId)
  if not mission then return end

  if success then
    -- Mark as completed
    state.completedMissions[storyMissionId] = true

    -- Award story XP (additional to mission rewards)
    local xpGained = mission.xpReward or 0

    if career_modules_playerAttributes and xpGained > 0 then
      career_modules_playerAttributes.addAttributes(
        { ["mysummer-streetracing"] = xpGained },
        { label = "Story Mission: " .. getLocalizedText(mission.name), tags = {"gameplay", "mysummer"} }
      )
    end

    log("I", logTag, "Story mission completed: " .. storyMissionId .. " XP: " .. xpGained)

    -- Show completion dialogue (after a short delay to let mission toast show first)
    if mission.completionDialogue and career_modules_mysummerChat then
      local messages = {}
      for _, msg in ipairs(mission.completionDialogue) do
        table.insert(messages, getLocalizedText(msg))
      end
      -- Show dialogue directly - mysummerChat will queue messages
      career_modules_mysummerChat.showDialogue(mission.contact, messages)
    end

    -- Unlock contact if specified
    if mission.unlockContact and career_modules_mysummerCareer then
      if career_modules_mysummerCareer.unlockContact then
        career_modules_mysummerCareer.unlockContact(mission.unlockContact)
        log("I", logTag, "Unlocked contact: " .. mission.unlockContact)
      end
    end

    -- Notify UI
    if guihooks then
      guihooks.trigger("mysummerStoryMissionCompleted", {
        missionId = storyMissionId,
        xpGained = xpGained,
        success = true,
      })
    end
  else
    -- Mission failed
    log("I", logTag, "Story mission failed: " .. storyMissionId)

    -- Notify UI
    if guihooks then
      guihooks.trigger("mysummerStoryMissionCompleted", {
        missionId = storyMissionId,
        success = false,
      })
    end
  end

  -- Clear active mission
  state.activeMission = nil
  state.missionPhase = nil
  state.drivingDialogueTriggered = {}

  saveState()
end

-- Legacy function - kept for backwards compatibility
completeMission = function(missionId)
  onMissionCompleted(missionId, true)
end

-- ============================================================================
-- RACE MANAGEMENT
-- ============================================================================

-- Select a story race: navigate to start, auto-start correct version (normal/REPEAT) on arrival
local function selectRace(raceId)
  local accessible, reason, value = isRaceAccessible(raceId)
  if not accessible then
    log("W", logTag, "Race not accessible: " .. raceId .. " reason: " .. tostring(reason))
    return { success = false, reason = reason, value = value }
  end

  -- Find the race
  local race = nil
  local chapterData = nil
  for _, chapter in ipairs(storyRaces) do
    for _, r in ipairs(chapter.races) do
      if r.id == raceId then
        race = r
        chapterData = chapter
        break
      end
    end
    if race then break end
  end

  if not race then
    return { success = false, reason = "notfound" }
  end

  -- Check if race has been won before - use REPEAT version to avoid duplicate XP rewards
  local raceStatus = state.completedRaces[raceId] or {}
  local missionIdToUse = race.missionId
  local isRepeat = false

  if raceStatus.wins and raceStatus.wins > 0 then
    -- Player has won this race before, use REPEAT version (no skill XP, reduced rewards)
    local repeatMissionId = race.missionId:gsub("%-STREET/", "-STREET-REPEAT/")
    if repeatMissionId ~= race.missionId then
      missionIdToUse = repeatMissionId
      isRepeat = true
      log("I", logTag, "Using REPEAT version: " .. repeatMissionId)
    end
  end

  -- Get mission start position for navigation
  local startPos = getMissionStartPosition(missionIdToUse)
  if not startPos then
    log("E", logTag, "Cannot get start position for race: " .. raceId)
    return { success = false, reason = "noposition" }
  end

  -- Track which race is selected (for controlling mission start and completion tracking)
  state.activeRace = {
    raceId = raceId,
    missionId = missionIdToUse,
    isRepeat = isRepeat,
    name = getLocalizedText(race.name) .. (isRepeat and " (Repeat)" or ""),
    contact = race.contact,
    xpReward = race.xpReward,
    moneyReward = race.moneyReward,
    chapter = chapterData.chapter,
    startPos = { x = startPos.x, y = startPos.y, z = startPos.z },
    waitingForArrival = true, -- Player needs to drive there, then we'll start the correct mission
  }

  saveState()

  -- Show dialogue from contact
  if career_modules_mysummerChat and race.contact ~= "system" then
    local messages = {
      tr("mysummer.storyRaces.goToRace." .. race.contact, "Head to the race location. I'll be watching."),
    }
    career_modules_mysummerChat.showDialogueMessage(race.contact, messages[1])
  end

  -- Navigate to the race start using BeamNG's waypoint system
  -- Don't auto-clear on arrival - we control when to start the mission
  if core_groundMarkers then
    core_groundMarkers.setPath(startPos, { clearPathOnReachingTarget = false })
    log("I", logTag, "Navigation set to race: " .. raceId .. " at " .. tostring(startPos))
  end

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerStoryRaceSelected", {
      raceId = raceId,
      name = state.activeRace.name,
      contact = state.activeRace.contact,
    })
  end

  return { success = true }
end

-- Cancel active race
local function cancelRace()
  if not state.activeRace then return end

  log("I", logTag, "Race cancelled: " .. state.activeRace.raceId)
  state.activeRace = nil
  saveState()

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end
end

-- Complete a race (called from race manager when race finishes)
local function completeRace(raceId, position, time)
  if not state.activeRace or state.activeRace.raceId ~= raceId then
    -- Check if any story race matches
    local found = false
    for _, chapter in ipairs(storyRaces) do
      for _, race in ipairs(chapter.races) do
        if race.id == raceId then
          found = true
          state.activeRace = {
            raceId = raceId,
            xpReward = race.xpReward,
            moneyReward = race.moneyReward,
            contact = race.contact,
            chapter = chapter.chapter,
          }
          break
        end
      end
      if found then break end
    end
    if not found then return end
  end

  local raceData = state.completedRaces[raceId] or { completed = false, bestTime = nil, wins = 0 }

  -- Update completion status
  raceData.completed = true
  if position and position == 1 then
    raceData.wins = (raceData.wins or 0) + 1
  end
  if time and (not raceData.bestTime or time < raceData.bestTime) then
    raceData.bestTime = time
  end

  state.completedRaces[raceId] = raceData

  -- Award XP based on position
  local xpMultiplier = 1.0
  if position == 1 then xpMultiplier = 1.0
  elseif position == 2 then xpMultiplier = 0.75
  elseif position == 3 then xpMultiplier = 0.5
  else xpMultiplier = 0.25
  end

  local xpGained = math.floor(state.activeRace.xpReward * xpMultiplier)
  local moneyGained = (position and position <= 3) and math.floor(state.activeRace.moneyReward * xpMultiplier) or 0

  -- Note: XP is handled by BeamNG's native star system (mysummer-streetracing attribute)
  -- Money is also handled natively

  log("I", logTag, "Race completed: " .. raceId .. " position: " .. tostring(position))

  -- Send completion dialogue
  if career_modules_mysummerChat and state.activeRace.contact ~= "system" then
    local message = (position and position == 1) and
      tr("mysummer.storyRaces.win", "Nice work! You're getting better.") or
      tr("mysummer.storyRaces.finish", "You finished. Keep practicing.")
    career_modules_mysummerChat.sendContactMessage(state.activeRace.contact, message, { silent = true })
  end

  state.activeRace = nil
  saveState()

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerStoryRaceCompleted", {
      raceId = raceId,
      position = position,
      xpGained = xpGained,
      moneyGained = moneyGained,
    })
  end
end

-- ============================================================================
-- API FOR UI
-- ============================================================================

-- Get all story races with status for UI
local function getStoryRacesForUI()
  local result = {
    currentLevel = getPlayerLevel(),
    isInProjectCar = isPlayerInProjectCar(),
    chapters = setmetatable({}, {__jsontype = "array"}), -- Force JSON array serialization
    activeRace = state.activeRace,
    activeMission = state.activeMission,
  }

  for _, chapterData in ipairs(storyRaces) do
    local chapterResult = {
      chapter = chapterData.chapter,
      chapterName = chapterData.chapterName,
      requiredLevel = chapterData.requiredLevel,
      requiresProjectCar = chapterData.requiresProjectCar,
      isAccessible = result.currentLevel >= chapterData.requiredLevel,
      races = setmetatable({}, {__jsontype = "array"}), -- Force JSON array serialization even when empty
      mission = nil, -- Story mission for this chapter
    }

    -- Add races
    for _, race in ipairs(chapterData.races) do
      local raceStatus = state.completedRaces[race.id] or {}
      local accessible, reason, _ = isRaceAccessible(race.id)

      local hasWon = (raceStatus.wins or 0) > 0
      table.insert(chapterResult.races, {
        id = race.id,
        name = getLocalizedText(race.name),
        description = getLocalizedText(race.description),
        contact = race.contact,
        xpReward = race.xpReward,
        moneyReward = race.moneyReward,
        completed = raceStatus.completed or false,
        wins = raceStatus.wins or 0,
        bestTime = raceStatus.bestTime,
        isAccessible = accessible,
        lockedReason = not accessible and reason or nil,
        willBeRepeat = hasWon, -- True if race has been won before (BeamNG handles reduced rewards automatically)
      })
    end

    -- Add story mission for this chapter
    for _, mission in ipairs(storyMissions) do
      if mission.chapter == chapterData.chapter then
        local accessible, reason = isMissionAccessible(mission.id)
        chapterResult.mission = {
          id = mission.id,
          name = getLocalizedText(mission.name),
          description = getLocalizedText(mission.description),
          contact = mission.contact,
          type = mission.type,
          xpReward = mission.xpReward,
          moneyReward = mission.moneyReward,
          completed = isMissionCompleted(mission.id),
          isAccessible = accessible,
          lockedReason = not accessible and reason or nil,
          requiresProjectCar = mission.requiresProjectCar,
        }
        break
      end
    end

    table.insert(result.chapters, chapterResult)
  end

  return result
end

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

loadState = function()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath) or {}

  state.completedRaces = data.completedRaces or {}
  state.completedMissions = data.completedMissions or {}
  state.currentChapter = data.currentChapter or 0
  state.activeMission = data.activeMission
  state.activeRace = data.activeRace -- Restore active race (may be waiting for arrival)
  state.drivingDialogueTriggered = data.drivingDialogueTriggered or {}
  state.missionElapsedTime = 0 -- Reset on load, will be tracked during gameplay

  -- If there's an active race waiting for arrival, restore the waypoint
  if state.activeRace and state.activeRace.waitingForArrival and state.activeRace.startPos then
    local startPos = vec3(state.activeRace.startPos.x, state.activeRace.startPos.y, state.activeRace.startPos.z)
    if core_groundMarkers then
      core_groundMarkers.setPath(startPos, { clearPathOnReachingTarget = false })
      log("I", logTag, "Restored waypoint to race start")
    end
  end

  log("I", logTag, "Loaded story races state")
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
    completedRaces = state.completedRaces,
    completedMissions = state.completedMissions,
    currentChapter = state.currentChapter,
    activeMission = state.activeMission,
    activeRace = state.activeRace, -- Save active race (may be waiting for arrival)
    drivingDialogueTriggered = state.drivingDialogueTriggered,
    -- missionElapsedTime not saved - resets each mission
  }
  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onCareerActive(active)
  if active then
    loadState()
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

local function onExtensionLoaded()
  log("I", logTag, "MySummer Story Races loaded")
end

-- Update hook for story dialogues during missions AND race arrival detection
local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then return end

  -- Check for race arrival (player needs to drive to race start)
  -- We control mission start to ensure REPEAT version is used if already won
  if state.activeRace and state.activeRace.waitingForArrival then
    local playerPos = getPlayerPosition()
    if playerPos and state.activeRace.startPos then
      local startPos = vec3(state.activeRace.startPos.x, state.activeRace.startPos.y, state.activeRace.startPos.z)
      local distance = playerPos:distance(startPos)

      -- Close enough to start race (15 meters)
      if distance <= 15 then
        log("I", logTag, "Player arrived at race start. Starting: " .. state.activeRace.missionId)

        -- Clear waiting flag
        state.activeRace.waitingForArrival = false
        saveState()

        -- Clear waypoint
        if core_groundMarkers then
          core_groundMarkers.setPath(nil)
        end

        -- Start the correct mission version (normal or REPEAT)
        local missionToStart = state.activeRace.missionId:gsub("/info.json", "")
        if career_modules_mysummerRaceManager then
          career_modules_mysummerRaceManager.startNativeMission(missionToStart)
        end

        -- Notify UI
        if guihooks then
          guihooks.trigger("mysummerStoryRaceStarted", {
            raceId = state.activeRace.raceId,
            name = state.activeRace.name,
          })
        end
      end
    end
  end

  -- Check story dialogues (for active missions)
  if state.activeMission then
    checkStoryDialogues(dtSim)
  end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

-- Race API
M.getStoryRacesForUI = getStoryRacesForUI
M.selectRace = selectRace
M.cancelRace = cancelRace
M.completeRace = completeRace
M.findRaceIdByMission = findRaceIdByMission
M.isRaceAccessible = isRaceAccessible
M.isRaceCompleted = isRaceCompleted
M.getPlayerLevel = getPlayerLevel
M.isPlayerInProjectCar = isPlayerInProjectCar

-- Mission API
M.selectMission = selectMission
M.cancelMission = cancelMission
M.completeMission = completeMission
M.onMissionCompleted = onMissionCompleted -- Called by mysummerMissions when mission ends
M.isMissionAccessible = isMissionAccessible
M.isMissionCompleted = isMissionCompleted
M.getStoryMission = getStoryMission

-- Lifecycle
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate -- For story dialogues during missions

return M
