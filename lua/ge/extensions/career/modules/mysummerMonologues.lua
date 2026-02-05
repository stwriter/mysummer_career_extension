-- MySummer Monologues System
-- Internal thoughts displayed on screen as reactions to narrative events

local M = {}
M.moduleName = "career_modules_mysummerMonologues"

M.dependencies = {
  "career_career",
}

local logTag = "mysummerMonologues"

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  -- Currently displaying monologue
  activeMonologue = nil,
  currentLineIndex = 0,
  lineTimer = 0,

  -- Pending monologue (waiting to show after delay)
  pendingMonologue = nil,
  pendingTimer = 0,

  -- Track which monologues have been shown (unique ones)
  triggeredMonologues = {},

  -- Settings
  enabled = true,
}

-- Display settings
local DISPLAY_TIME = 4.0        -- Seconds per line
local FADE_TIME = 0.5           -- Fade in/out duration
local REACTION_DELAY_MIN = 20   -- Min seconds after event to show monologue
local REACTION_DELAY_MAX = 45   -- Max seconds after event

-- ============================================================================
-- MONOLOGUE DEFINITIONS
-- ============================================================================

-- Monologues triggered by specific narrative events
-- Key = event ID from mysummerNarrative.lua
local eventMonologues = {
  -- ========================================================================
  -- PHASE 0: PROLOGUE
  -- ========================================================================

  -- Phase 0: After inheriting the garage
  inherited_garage = {
    id = "react_inherited_garage",
    lines = {
      {es = "El garaje del abuelo... ahora es mío.", en = "Grandfather's garage... now it's mine."},
      {es = "El Miramar. El ETK-I desnudo. Esta carta.", en = "The Miramar. The naked ETK-I. This letter."},
      {es = "\"Termina lo que yo no pude.\"", en = "\"Finish what I couldn't.\""},
      {es = "Pero... ¿qué era lo que no pudo?", en = "But... what couldn't he do?"},
    }
  },

  -- ========================================================================
  -- PHASE 1: CHAPTER I
  -- ========================================================================

  -- Phase 1: After meeting teammates
  meet_teammates = {
    id = "react_meet_teammates",
    lines = {
      {es = "Rook y Nova. Mis nuevos compañeros de equipo.", en = "Rook and Nova. My new teammates."},
      {es = "Rook parece... cauteloso. Nova, todo lo contrario.", en = "Rook seems... cautious. Nova, quite the opposite."},
      {es = "¿Puedo confiar en ellos?", en = "Can I trust them?"},
    }
  },

  -- Phase 1: After Ghost's first message
  ghost_first_message = {
    id = "react_ghost_first",
    lines = {
      {es = "Ese mensaje... \"Me recuerdas a alguien.\"", en = "That message... \"You remind me of someone.\""},
      {es = "¿Quién es Ghost? ¿Cómo sabe cómo conduzco?", en = "Who is Ghost? How does he know how I drive?"},
    }
  },

  -- ========================================================================
  -- PHASE 2: CHAPTER II
  -- ========================================================================

  -- Phase 2: After Ghost mentions grandfather
  ghost_grandfather_warning = {
    id = "react_ghost_grandfather",
    lines = {
      {es = "Ghost conocía al abuelo.", en = "Ghost knew grandfather."},
      {es = "Algo pasó. Algo malo.", en = "Something happened. Something bad."},
      {es = "¿Por qué nadie quiere contármelo?", en = "Why won't anyone tell me about it?"},
    }
  },

  -- ========================================================================
  -- PHASE 3: CHAPTER III
  -- ========================================================================

  -- Phase 3: After finding the newspaper
  newspaper_found = {
    id = "react_newspaper",
    lines = {
      {es = "Un accidente... el padre de Muscle.", en = "An accident... Muscle's father."},
      {es = "Murió en una carrera ilegal.", en = "He died in an illegal race."},
      {es = "Por eso el abuelo nunca corrió.", en = "That's why grandfather never raced."},
      {es = "Perdió a su mejor amigo.", en = "He lost his best friend."},
    }
  },

  -- Phase 3: After Muscle recognizes the ETK-I
  muscle_first_contact = {
    id = "react_muscle_contact",
    lines = {
      {es = "Muscle reconoció el ETK-I.", en = "Muscle recognized the ETK-I."},
      {es = "Dice que el abuelo lo estaba construyendo hace años.", en = "Says grandfather was building it years ago."},
      {es = "¿Por qué lo dejó sin terminar?", en = "Why did he leave it unfinished?"},
    }
  },

  -- Phase 3: After Rook shows stress
  rook_stress_signs = {
    id = "react_rook_stress",
    lines = {
      {es = "Rook está raro últimamente. Tenso.", en = "Rook's been weird lately. Tense."},
      {es = "Las carreras le están pasando factura.", en = "The races are taking their toll on him."},
      {es = "¿O es por Nova?", en = "Or is it because of Nova?"},
    }
  },

  -- Phase 3: After Nova reveals ambition
  nova_ambition_reveal = {
    id = "react_nova_ambition",
    lines = {
      {es = "The Big One... Nova no para de hablar de eso.", en = "The Big One... Nova won't stop talking about it."},
      {es = "¿Realmente podemos llegar tan lejos?", en = "Can we really go that far?"},
      {es = "Ella lo ve claro. Yo... no tanto.", en = "She sees it clearly. I... not so much."},
    }
  },

  -- ========================================================================
  -- PHASE 4: CHAPTER IV
  -- ========================================================================

  -- Phase 4: After Rook/Nova fight
  rook_nova_argument = {
    id = "react_rook_nova_fight",
    lines = {
      {es = "Rook y Nova han discutido.", en = "Rook and Nova had a fight."},
      {es = "Algo se ha roto entre ellos.", en = "Something broke between them."},
      {es = "Y yo estoy en medio de todo.", en = "And I'm right in the middle of it all."},
    }
  },

  -- Phase 4: After Nova asks opinion
  nova_frustration = {
    id = "react_nova_asks",
    lines = {
      {es = "Nova quiere que elija.", en = "Nova wants me to choose."},
      {es = "Ella o Rook. Arriesgar o frenar.", en = "Her or Rook. Risk or brake."},
      {es = "¿Qué habría hecho el abuelo?", en = "What would grandfather have done?"},
    }
  },

  -- ========================================================================
  -- PHASE 5: CHAPTER V
  -- ========================================================================

  -- Phase 5: After ETK-I is ready
  etki_ready = {
    id = "react_etki_ready",
    lines = {
      {es = "Está terminado. El ETK-I está terminado.", en = "It's finished. The ETK-I is finished."},
      {es = "El sueño del abuelo. Su proyecto.", en = "Grandfather's dream. His project."},
      {es = "Ahora es mi turno de llevarlo a la meta.", en = "Now it's my turn to take it to the finish line."},
    }
  },

  -- Phase 5: After Ghost's final warning
  ghost_final_warning = {
    id = "react_ghost_warning",
    lines = {
      {es = "\"Vigila tu espalda.\" Eso dijo Ghost.", en = "\"Watch your back.\" That's what Ghost said."},
      {es = "¿Qué sabe que yo no sé?", en = "What does he know that I don't?"},
      {es = "Algo va a pasar. Lo presiento.", en = "Something's going to happen. I can feel it."},
    }
  },

  -- Phase 5: After car is stolen
  car_stolen = {
    id = "react_car_stolen",
    lines = {
      {es = "El coche... no está.", en = "The car... it's gone."},
      {es = "¿Quién haría esto? ¿Por qué?", en = "Who would do this? Why?"},
      {es = "\"Lo hice por nosotros.\" Alguien cercano.", en = "\"I did it for us.\" Someone close."},
      {es = "Alguien en quien confiaba.", en = "Someone I trusted."},
    }
  },

  -- ========================================================================
  -- PHASE 6: CHAPTER VI
  -- ========================================================================

  -- Phase 6: After car is recovered
  car_recovered = {
    id = "react_car_recovered",
    lines = {
      {es = "Ghost tenía el coche todo este tiempo.", en = "Ghost had the car all along."},
      {es = "Lo salvó de quien intentó robarlo.", en = "He saved it from whoever tried to steal it."},
      {es = "Ahora puedo terminar esto.", en = "Now I can finish this."},
    }
  },

  -- Phase 6: After Ghost reveals truth
  ghost_truth_reveal = {
    id = "react_ghost_truth",
    lines = {
      {es = "Ghost no robó el coche. Lo salvó.", en = "Ghost didn't steal the car. He saved it."},
      {es = "Alguien quería usarlo sin mí.", en = "Someone wanted to use it without me."},
      {es = "¿Rook? ¿Nova? ¿Quién fue?", en = "Rook? Nova? Who was it?"},
    }
  },

  -- Phase 6: After traitor is revealed
  traitor_reveal = {
    id = "react_traitor",
    lines = {
      {es = "Ahora lo sé todo.", en = "Now I know everything."},
      {es = "El abuelo. El accidente. La traición.", en = "Grandfather. The accident. The betrayal."},
      {es = "Es hora de terminar lo que él empezó.", en = "It's time to finish what he started."},
      {es = "The Big One me espera.", en = "The Big One awaits."},
    }
  },
}

-- Monologues that can appear while driving (based on phase and flags)
-- These are more ambient/reflective, not direct reactions
local drivingMonologues = {
  -- Phase 0-1: Early game
  {
    id = "driving_early_car",
    phase = {0, 1},
    cooldown = 600,
    requiredVehicle = "miramar",  -- Only when driving the starter Miramar
    lines = {
      {es = "Este coche ha visto mejores días...", en = "This car has seen better days..."},
      {es = "Pero todavía tiene algo. Lo noto.", en = "But it still has something. I can feel it."},
    }
  },
  {
    id = "driving_garage_memories",
    phase = {0, 1},
    cooldown = 900,
    lines = {
      {es = "El garaje del abuelo. Tantos recuerdos.", en = "Grandfather's garage. So many memories."},
      {es = "¿Qué intentaba decirme en esa carta?", en = "What was he trying to tell me in that letter?"},
    }
  },

  -- Phase 2-3: Middle game - Ghost mystery
  {
    id = "driving_ghost_who",
    phase = {2, 3},
    requiredFlag = "ghost_contacted",
    cooldown = 600,
    lines = {
      {es = "Ghost... ¿Quién es realmente?", en = "Ghost... Who is he really?"},
      {es = "Siempre observando. Siempre en las sombras.", en = "Always watching. Always in the shadows."},
    }
  },
  {
    id = "driving_grandfather_what",
    phase = {2, 3},
    requiredFlag = "grandfather_mentioned",
    cooldown = 600,
    lines = {
      {es = "El abuelo nunca corrió. ¿Por qué?", en = "Grandfather never raced. Why?"},
      {es = "Algo pasó. Algo que nadie quiere contarme.", en = "Something happened. Something no one wants to tell me."},
    }
  },
  {
    id = "driving_underground",
    phase = {2, 3},
    cooldown = 900,
    lines = {
      {es = "Esto ya no son carreras de amigos.", en = "These aren't friendly races anymore."},
      {es = "Aquí perder empieza a doler de verdad.", en = "Losing starts to really hurt here."},
    }
  },

  -- Phase 3-4: Team tension
  {
    id = "driving_team_thoughts",
    phase = {3, 4},
    cooldown = 600,
    lines = {
      {es = "Rook, Nova y yo... ¿somos un equipo?", en = "Rook, Nova and I... are we a team?"},
      {es = "O solo tres personas que corren juntas.", en = "Or just three people racing together."},
    }
  },
  {
    id = "driving_rook_worry",
    phase = {3, 4},
    requiredFlag = "rook_stressed",
    cooldown = 600,
    lines = {
      {es = "Rook no es el mismo.", en = "Rook isn't the same."},
      {es = "Las carreras le están pasando factura.", en = "The races are taking their toll on him."},
    }
  },
  {
    id = "driving_nova_push",
    phase = {3, 4},
    requiredFlag = "nova_revealed_ambition",
    cooldown = 600,
    lines = {
      {es = "Nova siempre empujando. Siempre más.", en = "Nova always pushing. Always more."},
      {es = "¿Es ambición o desesperación?", en = "Is it ambition or desperation?"},
    }
  },

  -- Phase 4-5: Danger zone
  {
    id = "driving_trust",
    phase = {4, 5},
    requiredFlag = "rook_nova_fought",
    cooldown = 600,
    lines = {
      {es = "¿En quién puedo confiar?", en = "Who can I trust?"},
      {es = "Las cosas ya no son como antes.", en = "Things aren't like they used to be."},
    }
  },
  {
    id = "driving_so_close",
    phase = {5},
    cooldown = 600,
    lines = {
      {es = "The Big One está tan cerca...", en = "The Big One is so close..."},
      {es = "El sueño del abuelo. Mi sueño.", en = "Grandfather's dream. My dream."},
    }
  },
  {
    id = "driving_etki_project",
    phase = {4, 5},
    cooldown = 900,
    requiredVehicle = "etki",  -- Only when driving the project ETK-I
    lines = {
      {es = "El ETK-I... cada día más cerca de estar listo.", en = "The ETK-I... getting closer to being ready every day."},
      {es = "El coche que el abuelo nunca terminó.", en = "The car grandfather never finished."},
    }
  },

  -- Phase 6: Endgame
  {
    id = "driving_betrayal",
    phase = {6},
    requiredFlag = "car_stolen",
    cooldown = 600,
    lines = {
      {es = "Alguien me traicionó.", en = "Someone betrayed me."},
      {es = "Alguien en quien confiaba.", en = "Someone I trusted."},
    }
  },
  {
    id = "driving_finish_it",
    phase = {6},
    requiredFlag = "traitor_revealed",
    cooldown = 600,
    lines = {
      {es = "Ya no hay vuelta atrás.", en = "There's no turning back now."},
      {es = "Es hora de terminar esto.", en = "It's time to finish this."},
    }
  },
}

-- Monologues triggered by player actions/context
local contextMonologues = {
  -- First time entering a race
  first_race_start = {
    id = "first_race",
    unique = true,
    lines = {
      {es = "Primera carrera de verdad...", en = "First real race..."},
      {es = "El Miramar aguantará. Tiene que aguantar.", en = "The Miramar will hold up. It has to."},
    }
  },

  -- After winning a race
  race_win = {
    id = "race_win",
    cooldown = 300, -- 5 minutes between these
    variants = {
      {
        lines = {
          {es = "Esa sensación al cruzar primero...", en = "That feeling of crossing first..."},
          {es = "El abuelo habría querido ver esto.", en = "Grandfather would have wanted to see this."},
        }
      },
      {
        lines = {
          {es = "Otra victoria.", en = "Another victory."},
          {es = "Cada vez más cerca de The Big One.", en = "Getting closer to The Big One."},
        }
      },
    }
  },

  -- After escaping police
  police_escape = {
    id = "police_escape",
    cooldown = 600, -- 10 minutes
    variants = {
      {
        lines = {
          {es = "Eso estuvo cerca.", en = "That was close."},
          {es = "La policía ya me tiene fichado.", en = "The police already have me marked."},
        }
      },
      {
        lines = {
          {es = "Los perdí. Por ahora.", en = "I lost them. For now."},
          {es = "Este camino tiene un precio.", en = "This path has a price."},
        }
      },
    }
  },

  -- First time driving the ETK-I project
  first_etki_drive = {
    id = "first_etki",
    unique = true,
    lines = {
      {es = "El ETK-I... el proyecto del abuelo.", en = "The ETK-I... grandfather's project."},
      {es = "Tantos años esperando en el garaje.", en = "So many years waiting in the garage."},
      {es = "Es hora de terminarlo.", en = "It's time to finish it."},
    }
  },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function getRandomDelay()
  return REACTION_DELAY_MIN + math.random() * (REACTION_DELAY_MAX - REACTION_DELAY_MIN)
end

local function getCurrentPhase()
  local narrative = extensions.career_modules_mysummerNarrative
  if narrative and narrative.getCurrentPhase then
    return narrative.getCurrentPhase()
  end
  return 0
end

local function getStoryFlag(flag)
  local narrative = extensions.career_modules_mysummerNarrative
  if narrative and narrative.getStoryFlag then
    return narrative.getStoryFlag(flag)
  end
  return false
end

local function isPlayerDriving()
  local playerVehicle = be:getPlayerVehicle(0)
  if playerVehicle then
    local vel = playerVehicle:getVelocity()
    if vel then
      return vel:length() > 5  -- More than 5 m/s (~18 km/h)
    end
  end
  return false
end

-- Check which vehicle model the player is currently driving
local function getPlayerVehicleModel()
  local playerVehicle = be:getPlayerVehicle(0)
  if playerVehicle then
    return playerVehicle:getJBeamFilename()
  end
  return nil
end

-- Check if player is driving the Miramar
local function isPlayerInMiramar()
  local model = getPlayerVehicleModel()
  return model == "miramar"
end

-- Check if player is driving the ETK-I project car
local function isPlayerInEtkiProject()
  local model = getPlayerVehicleModel()
  return model == "etki"
end

local function phaseMatches(phaseList, currentPhase)
  for _, p in ipairs(phaseList) do
    if p == currentPhase then
      return true
    end
  end
  return false
end

-- ============================================================================
-- DISPLAY SYSTEM (using DialogueOverlay via mysummerChat.showDialogue)
-- ============================================================================

local function getChat()
  return extensions.career_modules_mysummerChat
end

local function showMonologue(monologue)
  if not monologue or not monologue.lines or #monologue.lines == 0 then
    return
  end

  state.activeMonologue = monologue
  state.currentLineIndex = 1
  state.lineTimer = DISPLAY_TIME

  -- Mark as triggered
  if monologue.id then
    state.triggeredMonologues[monologue.id] = os.time()
  end

  -- Show all lines as a dialogue using the existing DialogueOverlay
  -- Use "player" as contactId for internal thoughts
  local chat = getChat()
  if chat and chat.showDialogue then
    -- Format lines with italic quotes for thoughts
    -- Lines can be either strings (old format) or bilingual tables {es="", en=""}
    local formattedLines = {}
    for _, line in ipairs(monologue.lines) do
      if type(line) == "table" and (line.es or line.en) then
        -- Bilingual format: wrap with quotes
        table.insert(formattedLines, {
          es = "\"" .. (line.es or ""),
          en = "\"" .. (line.en or "")
        })
      else
        -- String format (legacy): wrap with quotes
        table.insert(formattedLines, "\"" .. tostring(line) .. "\"")
      end
    end
    chat.showDialogue("player", formattedLines)
  end

  -- Log first line (handle both formats)
  local firstLine = monologue.lines[1]
  local logText = ""
  if type(firstLine) == "table" then
    logText = firstLine.es or firstLine.en or "unknown"
  else
    logText = tostring(firstLine)
  end
  log("I", logTag, "Showing monologue: " .. (monologue.id or "unknown") .. " - " .. logText)
end

local function advanceMonologue(dt)
  -- Monologues now use DialogueOverlay which handles its own timing
  -- Just track completion
  if not state.activeMonologue then
    return
  end

  state.lineTimer = state.lineTimer - dt

  -- Give enough time for DialogueOverlay to show all lines
  local totalTime = #state.activeMonologue.lines * DISPLAY_TIME
  if state.lineTimer <= -totalTime then
    -- Monologue complete
    local completedId = state.activeMonologue.id
    state.activeMonologue = nil
    state.currentLineIndex = 0
    log("I", logTag, "Monologue complete: " .. (completedId or "unknown"))
  end
end

local function processPendingMonologue(dt)
  if not state.pendingMonologue then
    return
  end

  -- Don't show if another is active
  if state.activeMonologue then
    return
  end

  state.pendingTimer = state.pendingTimer - dt

  if state.pendingTimer <= 0 then
    showMonologue(state.pendingMonologue)
    state.pendingMonologue = nil
    state.pendingTimer = 0
  end
end

-- ============================================================================
-- TRIGGER FUNCTIONS
-- ============================================================================

-- Called when a narrative event triggers (from mysummerNarrative)
local function onNarrativeEvent(eventId)
  if not state.enabled then return end

  local monologue = eventMonologues[eventId]
  if not monologue then
    log("D", logTag, "No monologue for event: " .. eventId)
    return
  end

  -- Check if already shown (for unique monologues)
  if state.triggeredMonologues[monologue.id] then
    log("D", logTag, "Monologue already shown: " .. monologue.id)
    return
  end

  -- Queue with delay (reaction time)
  state.pendingMonologue = monologue
  state.pendingTimer = getRandomDelay()

  log("I", logTag, "Queued monologue for event " .. eventId .. " in " .. string.format("%.1f", state.pendingTimer) .. "s")
end

-- Called on context events (race win, police escape, etc.)
local function onContextEvent(contextType)
  if not state.enabled then return end

  local monologueDef = contextMonologues[contextType]
  if not monologueDef then
    return
  end

  -- Check unique
  if monologueDef.unique and state.triggeredMonologues[monologueDef.id] then
    return
  end

  -- Check cooldown
  if monologueDef.cooldown then
    local lastTime = state.triggeredMonologues[monologueDef.id] or 0
    if os.time() - lastTime < monologueDef.cooldown then
      return
    end
  end

  -- Select variant if available
  local monologue
  if monologueDef.variants then
    local variant = monologueDef.variants[math.random(#monologueDef.variants)]
    monologue = {
      id = monologueDef.id,
      lines = variant.lines
    }
  else
    monologue = monologueDef
  end

  -- Queue with short delay
  state.pendingMonologue = monologue
  state.pendingTimer = 3 + math.random() * 5  -- 3-8 seconds for context events

  log("I", logTag, "Queued context monologue: " .. monologueDef.id)
end

-- Convenience functions for specific contexts
local function onRaceWin()
  onContextEvent("race_win")
end

local function onFirstRace()
  onContextEvent("first_race_start")
end

local function onPoliceEscape()
  onContextEvent("police_escape")
end

local function onFirstEtkiDrive()
  onContextEvent("first_etki_drive")
end

-- Get current vehicle model
local function getCurrentVehicleModel()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return nil end
  local veh = scenetree.findObjectById(playerVehicle:getId())
  if not veh then return nil end
  return veh.JBeam or nil
end

-- Check for driving monologues (called periodically while driving)
local function tryDrivingMonologue()
  if not state.enabled then return false end
  if state.activeMonologue then return false end
  if state.pendingMonologue then return false end
  if not isPlayerDriving() then return false end

  local currentPhase = getCurrentPhase()
  local currentVehicle = getCurrentVehicleModel()
  local now = os.time()

  -- Find eligible monologues
  local candidates = {}
  for _, mono in ipairs(drivingMonologues) do
    -- Check phase
    if phaseMatches(mono.phase, currentPhase) then
      -- Check required flag
      local flagOk = true
      if mono.requiredFlag then
        flagOk = getStoryFlag(mono.requiredFlag)
      end

      -- Check required vehicle
      local vehicleOk = true
      if mono.requiredVehicle and currentVehicle then
        vehicleOk = currentVehicle == mono.requiredVehicle
      end

      if flagOk and vehicleOk then
        -- Check cooldown
        local lastTime = state.triggeredMonologues[mono.id] or 0
        local cooldown = mono.cooldown or 600
        if now - lastTime >= cooldown then
          table.insert(candidates, mono)
        end
      end
    end
  end

  if #candidates == 0 then
    return false
  end

  -- Select random from candidates
  local selected = candidates[math.random(#candidates)]

  -- Queue with small delay
  state.pendingMonologue = selected
  state.pendingTimer = 2 + math.random() * 3  -- 2-5 seconds

  log("I", logTag, "Queued driving monologue: " .. selected.id)
  return true
end

-- ============================================================================
-- DEBUG
-- ============================================================================

local function debugForceMonologue(eventId)
  local monologue = eventMonologues[eventId]
  if monologue then
    showMonologue(monologue)
    return true
  end

  -- Try context monologues
  local contextMono = contextMonologues[eventId]
  if contextMono then
    if contextMono.variants then
      showMonologue({
        id = contextMono.id,
        lines = contextMono.variants[1].lines
      })
    else
      showMonologue(contextMono)
    end
    return true
  end

  log("W", logTag, "Monologue not found: " .. eventId)
  return false
end

local function debugListMonologues()
  print("\n========== EVENT MONOLOGUES ==========")
  for eventId, mono in pairs(eventMonologues) do
    local triggered = state.triggeredMonologues[mono.id] and "[X]" or "[ ]"
    print(string.format("  %s %s (event: %s)", triggered, mono.id, eventId))
    for i, line in ipairs(mono.lines) do
      print(string.format("      \"%s\"", line))
    end
  end

  print("\n========== CONTEXT MONOLOGUES ==========")
  for contextType, mono in pairs(contextMonologues) do
    local triggered = state.triggeredMonologues[mono.id] and "[X]" or "[ ]"
    print(string.format("  %s %s (context: %s)", triggered, mono.id, contextType))
    if mono.variants then
      for vi, variant in ipairs(mono.variants) do
        print(string.format("    Variant %d:", vi))
        for _, line in ipairs(variant.lines) do
          print(string.format("      \"%s\"", line))
        end
      end
    else
      for _, line in ipairs(mono.lines) do
        print(string.format("      \"%s\"", line))
      end
    end
  end
  print("========================================\n")
end

local function debugStatus()
  print("\n========== MONOLOGUE STATUS ==========")
  print(string.format("Enabled: %s", state.enabled and "yes" or "no"))
  print(string.format("Active: %s", state.activeMonologue and state.activeMonologue.id or "none"))
  print(string.format("Pending: %s (%.1fs)",
    state.pendingMonologue and state.pendingMonologue.id or "none",
    state.pendingTimer))
  print("\nTriggered monologues:")
  for id, time in pairs(state.triggeredMonologues) do
    print(string.format("  - %s (at %s)", id, os.date("%H:%M:%S", time)))
  end
  print("======================================\n")
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local drivingCheckTimer = 0
local DRIVING_CHECK_INTERVAL = 30  -- Check every 30 seconds while driving

local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Process pending monologue (delayed reaction)
  processPendingMonologue(dtReal)

  -- Advance active monologue display
  advanceMonologue(dtReal)

  -- Periodic check for driving monologues
  drivingCheckTimer = drivingCheckTimer + dtReal
  if drivingCheckTimer >= DRIVING_CHECK_INTERVAL then
    drivingCheckTimer = 0
    tryDrivingMonologue()
  end
end

local function onExtensionLoaded()
  log("I", logTag, "Monologues system loaded")
end

local function onCareerActive()
  -- Don't reset triggered - we want persistence
  -- But clear any active/pending state
  state.activeMonologue = nil
  state.pendingMonologue = nil
  state.pendingTimer = 0
  log("I", logTag, "Monologues system active")
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- Main trigger (called by mysummerNarrative when events fire)
M.onNarrativeEvent = onNarrativeEvent

-- Context triggers (called by other systems)
M.onContextEvent = onContextEvent
M.onRaceWin = onRaceWin
M.onFirstRace = onFirstRace
M.onPoliceEscape = onPoliceEscape
M.onFirstEtkiDrive = onFirstEtkiDrive

-- Settings
M.setEnabled = function(enabled) state.enabled = enabled end
M.isEnabled = function() return state.enabled end

-- Debug
M.debugForceMonologue = debugForceMonologue
M.debugListMonologues = debugListMonologues
M.debugStatus = debugStatus

-- Lifecycle
M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive

return M
