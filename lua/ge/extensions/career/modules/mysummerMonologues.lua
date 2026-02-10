-- MySummer Monologues System
-- Internal thoughts displayed on screen as reactions to narrative events
-- REBUILT FROM NARRATIVA_REEDIT.md (8-PHASE SYSTEM)

local M = {}
M.moduleName = "career_modules_mysummerMonologues"

M.dependencies = {
  "career_career",
  "career_saveSystem",
}

local logTag = "mysummerMonologues"
local saveFile = "mysummer_monologues.json"

-- Forward declarations
local saveState
local loadState

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
-- MONOLOGUE DEFINITIONS (FROM NARRATIVA_REEDIT.md)
-- ============================================================================

-- Event-triggered monologues (reactions to specific narrative events)
local eventMonologues = {
  -- ========================================================================
  -- PHASE 0: EL PESO DEL SILENCIO
  -- ========================================================================

  phase0_race1 = {
    id = "mono_phase0_race1",
    lines = {
      {es = "El abuelo preparaba estos motores para ganar.", en = "Grandfather prepared these engines to win."},
      {es = "Yo solo espero que este no reviente en la primera curva.", en = "I just hope this one doesn't blow up on the first turn."},
      {es = "Vamos allá.", en = "Let's go."},
    }
  },

  phase0_race2 = {
    id = "mono_phase0_race2",
    lines = {
      {es = "Nova conduce como si no tuviera nada que perder...", en = "Nova drives like she has nothing to lose..."},
      {es = "... y Rook parece que tiene miedo de romper algo.", en = "... and Rook seems afraid of breaking something."},
      {es = "Menudo par.", en = "What a pair."},
    }
  },

  phase0_race3 = {
    id = "mono_phase0_race3",
    lines = {
      {es = "Viper... Ghost no deja de mencionar ese nombre.", en = "Viper... Ghost keeps mentioning that name."},
      {es = "Dicen que el abuelo era su sombra.", en = "They say grandfather was her shadow."},
      {es = "Si gano esto, quizá empiece a entender por qué.", en = "If I win this, maybe I'll start to understand why."},
    }
  },

  -- ========================================================================
  -- PHASE 1: ORIGINS
  -- ========================================================================

  phase1_race1 = {
    id = "mono_phase1_race1",
    lines = {
      {es = "Nova tiene fuego en los ojos, pero Rook...", en = "Nova has fire in her eyes, but Rook..."},
      {es = "Hay algo en su forma de trazar que es casi matemática.", en = "There's something in his driving that's almost mathematical."},
      {es = "No es miedo, es respeto por la máquina.", en = "It's not fear, it's respect for the machine."},
      {es = "El abuelo decía que el taller es el alma del coche, pero la pista es su juicio final.", en = "Grandfather said the workshop is the car's soul, but the track is its final judgment."},
      {es = "Me pregunto cuál de los dos tiene razón.", en = "I wonder which of them is right."},
    }
  },

  phase1_race2 = {
    id = "mono_phase1_race2",
    lines = {
      {es = "Hoy es el turno de Rook.", en = "Today is Rook's turn."},
      {es = "Ha diseñado un trazado que premia la precisión, no solo la potencia.", en = "He's designed a layout that rewards precision, not just power."},
      {es = "Nova está de un humor de perros porque no puede simplemente pisar a fondo y olvidarse del freno.", en = "Nova's in a foul mood because she can't just floor it and forget the brake."},
    }
  },

  phase1_race3 = {
    id = "mono_phase1_race3",
    lines = {
      {es = "Ghost tiene razón.", en = "Ghost is right."},
      {es = "Puedo ver cómo se cruzan entre ellos.", en = "I can see how they cross each other."},
      {es = "Nova empuja, Rook protege.", en = "Nova pushes, Rook protects."},
      {es = "Es como ver un accidente a cámara lenta.", en = "It's like watching an accident in slow motion."},
      {es = "¿Qué pasará cuando uno de los dos decida que ya no quiere seguir ese baile?", en = "What will happen when one of them decides they don't want to dance anymore?"},
      {es = "¿Y dónde me deja eso a mí?", en = "And where does that leave me?"},
    }
  },

  -- ========================================================================
  -- PHASE 2: THE SPLIT
  -- ========================================================================

  phase2_race1 = {
    id = "mono_phase2_race1",
    lines = {
      {es = "Se están despedazando en directo.", en = "They're tearing each other apart live."},
      {es = "Nova está dispuesta a quemar el coche con tal de no perder...", en = "Nova is willing to burn the car just to not lose..."},
      {es = "... y Rook está empezando a perder los papeles intentando salvarla.", en = "... and Rook is starting to lose it trying to save her."},
      {es = "Es agotador, pero me da el espacio que necesito para ganar.", en = "It's exhausting, but it gives me the space I need to win."},
    }
  },

  phase2_race2 = {
    id = "mono_phase2_race2",
    lines = {
      {es = "Muscle... la hija de Viper.", en = "Muscle... Viper's daughter."},
      {es = "Ghost dice que su padre murió en un coche que mi abuelo no preparó...", en = "Ghost says her father died in a car my grandfather didn't prepare..."},
      {es = "... pero él se culpó igual.", en = "... but he blamed himself anyway."},
      {es = "Siento que sus ojos me siguen en cada curva.", en = "I feel her eyes following me in every turn."},
      {es = "No es presión de carrera, es presión de historia.", en = "It's not race pressure, it's history pressure."},
    }
  },

  phase2_race3 = {
    id = "mono_phase2_race3",
    lines = {
      {es = "El equipo se rompe.", en = "The team is breaking."},
      {es = "Rook me pide ayuda para frenarla...", en = "Rook asks me for help to stop her..."},
      {es = "... y Nova me pide que sea su cómplice para escapar.", en = "... and Nova asks me to be her accomplice to escape."},
      {es = "Y mientras tanto, el ETK-I sigue ahí en el garaje...", en = "And meanwhile, the ETK-I is still there in the garage..."},
      {es = "... esperando a que yo decida quién soy realmente.", en = "... waiting for me to decide who I really am."},
    }
  },

  -- ========================================================================
  -- PHASE 3: THE CRISIS
  -- ========================================================================

  phase3_race1 = {
    id = "mono_phase3_race1",
    lines = {
      {es = "Discuten por el walkie-talkie como si yo no estuviera ahí.", en = "They argue over the walkie-talkie as if I weren't there."},
      {es = "Nova quiere quemar el mundo y Rook quiere remodelarlo.", en = "Nova wants to burn the world and Rook wants to remodel it."},
      {es = "Me pregunto cuánto tiempo más podrán seguir fingiendo que son un equipo.", en = "I wonder how much longer they can keep pretending they're a team."},
    }
  },

  phase3_race2 = {
    id = "mono_phase3_race2",
    lines = {
      {es = "Ghost siempre habla de ellos como si fueran piezas defectuosas.", en = "Ghost always talks about them like they're defective parts."},
      {es = "Quizá por eso me ayuda a mí...", en = "Maybe that's why he helps me..."},
      {es = "... espera que yo sea la pieza que falta para que el ETK-I no sea solo un recuerdo.", en = "... he expects me to be the missing piece so the ETK-I isn't just a memory."},
    }
  },

  phase3_race3_shadow = {
    id = "mono_phase3_shadow_aftermath",
    lines = {
      {es = "El secreto de Shadow nos está quemando a todos...", en = "Shadow's secret is burning us all..."},
      {es = "... pero no puedo negar que esa potencia extra la hacía casi inalcanzable.", en = "... but I can't deny that extra power made her almost unreachable."},
    }
  },

  -- ========================================================================
  -- PHASE 4: THE SPLIT (RUPTURA FINAL)
  -- ========================================================================

  phase4_race1 = {
    id = "mono_phase4_race1",
    lines = {
      {es = "El coche de Nova olía a metal quemado al terminar.", en = "Nova's car smelled like burnt metal at the finish."},
      {es = "Rook la miraba como si fuera una desconocida.", en = "Rook looked at her like she was a stranger."},
      {es = "El secreto de Shadow nos está quemando a todos...", en = "Shadow's secret is burning us all..."},
      {es = "... pero no puedo negar que esa potencia extra la hacía casi inalcanzable.", en = "... but I can't deny that extra power made her almost unreachable."},
    }
  },

  phase4_race2 = {
    id = "mono_phase4_race2",
    lines = {
      {es = "Rook está desesperado por salvar algo que ya está roto.", en = "Rook is desperate to save something that's already broken."},
      {es = "Y Ghost... Ghost parece que está disfrutando viendo cómo repetimos la historia.", en = "And Ghost... Ghost seems to be enjoying watching us repeat history."},
    }
  },

  -- ========================================================================
  -- PHASE 5: RALLY REGIONAL (POLVO Y TRAICIÓN)
  -- ========================================================================

  phase5_rally1 = {
    id = "mono_phase5_rally1",
    lines = {
      {es = "Siento que el abuelo está sentado en el asiento del copiloto.", en = "I feel like grandfather is sitting in the co-driver's seat."},
      {es = "El coche responde a cada milímetro. Es perfecto.", en = "The car responds to every millimeter. It's perfect."},
      {es = "Pero ver a Rook y Nova ahí parados, cada uno en una punta del parque cerrado...", en = "But seeing Rook and Nova standing there, each at one end of the paddock..."},
      {es = "... me quita las ganas de celebrar.", en = "... takes away my will to celebrate."},
    }
  },

  phase5_rally2 = {
    id = "mono_phase5_rally2",
    lines = {
      {es = "Nova solo ve billetes y Rook solo ve fantasmas.", en = "Nova only sees bills and Rook only sees ghosts."},
      {es = "El ETK-I es lo único real en medio de este drama.", en = "The ETK-I is the only real thing in the middle of this drama."},
    }
  },

  phase5_rally4_victory = {
    id = "mono_phase5_rally4_victory",
    lines = {
      {es = "Lo hemos conseguido.", en = "We did it."},
      {es = "El ETK-I ha ganado su primer rally.", en = "The ETK-I has won its first rally."},
      {es = "El nombre de Miller vuelve a estar en lo más alto.", en = "The Miller name is back on top."},
      {es = "Ahora solo queda cargar el coche y preparar la inscripción para la Big One.", en = "Now all that's left is to load the car and prepare the entry for the Big One."},
    }
  },

  -- ========================================================================
  -- PHASE 6: EL FONDO DEL POZO (COPA COVET)
  -- ========================================================================

  phase6_covet1 = {
    id = "mono_phase6_covet1",
    lines = {
      {es = "De ganar un Rally con un ETK-I a pelear por la décima posición en un Covet de desguace.", en = "From winning a Rally with an ETK-I to fighting for tenth place in a junkyard Covet."},
      {es = "Me duele la cabeza por el golpe, pero me duele más el pecho.", en = "My head hurts from the blow, but my chest hurts more."},
      {es = "Esa voz... juraría que era la suya.", en = "That voice... I swear it was theirs."},
      {es = "¿Cómo pudo hacerme esto después de lo que le dije?", en = "How could they do this to me after what I said?"},
    }
  },

  phase6_covet2_techie = {
    id = "mono_phase6_techie_data",
    lines = {
      {es = "Techie no miente.", en = "Techie doesn't lie."},
      {es = "Si (Rook/Nova) recibió ese dinero...", en = "If (Rook/Nova) received that money..."},
      {es = "... el ETK-I ya debe estar camino de un desguace o de una colección privada en la capital.", en = "... the ETK-I must already be on its way to a junkyard or a private collection in the capital."},
      {es = "Me vendieron por un puñado de monedas.", en = "They sold me out for a handful of coins."},
    }
  },

  phase6_covet4_victory = {
    id = "mono_phase6_covet4_victory",
    lines = {
      {es = "He ganado. Tengo el pase.", en = "I won. I have the pass."},
      {es = "Pero no tengo el ETK-I.", en = "But I don't have the ETK-I."},
      {es = "Shadow dice que fue un trato por mi 'libertad'...", en = "Shadow says it was a deal for my 'freedom'..."},
      {es = "... pero yo no pedí que me salvaran traicionándome.", en = "... but I didn't ask to be saved by betraying me."},
      {es = "Voy a ir a esas clasificatorias y voy a encontrar ese coche...", en = "I'm going to those qualifiers and I'm going to find that car..."},
      {es = "... aunque tenga que desguazar cada box del circuito.", en = "... even if I have to scrap every pit box on the circuit."},
    }
  },

  -- ========================================================================
  -- PHASE 7: EL RASTRO DEL HIERRO (CLASIFICATORIAS)
  -- ========================================================================

  phase7_clasif1_parts = {
    id = "mono_phase7_parts_sighting",
    lines = {
      {es = "Ese alerón... tiene la marca de la soldadura que le hizo el abuelo.", en = "That spoiler... has the mark of grandfather's weld."},
      {es = "¡Es mi coche!", en = "It's my car!"},
      {es = "Shadow lo está desguazando y vendiéndolo por piezas en el paddock oficial.", en = "Shadow is scrapping it and selling it in parts at the official paddock."},
      {es = "¿Cómo pudo (Rook/Nova) permitir esto?", en = "How could (Rook/Nova) allow this?"},
      {es = "Cada vez que acelero, siento que estoy pisando sus mentiras.", en = "Every time I accelerate, I feel like I'm stepping on their lies."},
    }
  },

  phase7_clasif2_anon = {
    id = "mono_phase7_anonymous",
    lines = {
      {es = "¿Y si Shadow hackeó a Techie para incriminarlos?", en = "What if Shadow hacked Techie to frame them?"},
      {es = "Si (Rook/Nova) no me traicionó... ¿dónde están?", en = "If (Rook/Nova) didn't betray me... where are they?"},
      {es = "¿Por qué no dan la cara?", en = "Why don't they show their face?"},
    }
  },

  phase7_clasif3_threat = {
    id = "mono_phase7_shadow_threat",
    lines = {
      {es = "Shadow está intentando asustarme.", en = "Shadow is trying to scare me."},
      {es = "Eso significa que el ETK-I todavía existe.", en = "That means the ETK-I still exists."},
      {es = "No lo han desguazado... lo están usando como cebo.", en = "They haven't scrapped it... they're using it as bait."},
    }
  },

  -- ========================================================================
  -- PHASE 8: RECLAMACIÓN Y GLORIA (THE BIG ONE)
  -- ========================================================================

  phase8_duelo_mid = {
    id = "mono_phase8_duelo",
    lines = {
      {es = "Shadow no entiende nada.", en = "Shadow doesn't understand anything."},
      {es = "El ETK-I no es solo potencia...", en = "The ETK-I isn't just power..."},
      {es = "... es la promesa que el abuelo me hizo.", en = "... it's the promise grandfather made me."},
      {es = "Estoy viendo mi propio coche alejarse de mí...", en = "I'm watching my own car pull away from me..."},
      {es = "No voy a dejar que se lo lleve.", en = "I'm not going to let him take it."},
    }
  },

  phase8_bigone_finalvuelta = {
    id = "mono_phase8_bigone_final",
    lines = {
      {es = "El mundo se vuelve borroso.", en = "The world becomes blurry."},
      {es = "El abuelo tenía razón: llega un momento en el que solo puedes frenar o seguir adelante.", en = "Grandfather was right: there comes a time when you can only brake or keep going."},
      {es = "Él frenó.", en = "He braked."},
      {es = "Yo... no voy a frenar.", en = "I... am not going to brake."},
    }
  },

  phase8_epilogue = {
    id = "mono_phase8_epilogue",
    lines = {
      {es = "El silencio del garaje ya no se siente pesado.", en = "The silence of the garage no longer feels heavy."},
      {es = "La carta del abuelo sigue en el banco de trabajo...", en = "Grandfather's letter is still on the workbench..."},
      {es = "... pero ya no parece un reproche.", en = "... but it no longer seems like a reproach."},
      {es = "He corrido su carrera. He vencido a sus miedos.", en = "I've run his race. I've conquered his fears."},
      {es = "Y ahora... el asfalto es mío.", en = "And now... the asphalt is mine."},
    }
  },
}

-- ============================================================================
-- SYSTEM FUNCTIONS (KEEP EXISTING ARCHITECTURE)
-- ============================================================================

-- Replace placeholders in monologue text
local function replaceMonologuePlaceholders(text)
  local narrative = extensions.career_modules_mysummerNarrative
  if narrative and narrative.getNarrativeProgress then
    local progress = narrative.getNarrativeProgress()
    local chosenPartner = progress.storyFlags.chosen_partner or "rook"

    -- Replace (Rook/Nova) with the chosen partner name
    local partnerName = chosenPartner == "rook" and "Rook" or "Nova"
    local replaced = text:gsub("%(Rook/Nova%)", partnerName)
    return replaced
  end
  return text
end

-- Show a monologue on screen
local function showMonologue(monologue)
  if not monologue or not monologue.lines or #monologue.lines == 0 then
    return
  end

  state.activeMonologue = monologue
  state.currentLineIndex = 1
  state.lineTimer = 0

  -- Track as triggered if it has an ID
  if monologue.id then
    state.triggeredMonologues[monologue.id] = true
    saveState()
  end

  -- Send to UI
  local line = monologue.lines[1]
  local lang = Steam and Steam.language or "en"

  -- Debug language detection
  log("D", logTag, string.format("Language detection: Steam=%s, Steam.language=%s, lang=%s",
    tostring(Steam ~= nil), tostring(Steam and Steam.language or "nil"), tostring(lang)))

  -- Debug line content
  log("D", logTag, string.format("Line content: es='%s', en='%s'", tostring(line.es), tostring(line.en)))
  log("D", logTag, string.format("lang:find('es') = %s", tostring(lang:find("es"))))

  -- Fix language selection - check if lang contains "es" or "spanish"
  local isSpanish = (lang == "spanish" or lang:find("es") ~= nil or lang:find("spa") ~= nil)
  local rawText = isSpanish and line.es or line.en

  log("D", logTag, string.format("Selected text (isSpanish=%s): %s", tostring(isSpanish), rawText))

  local text = replaceMonologuePlaceholders(rawText)

  if guihooks and guihooks.trigger then
    guihooks.trigger("mysummerShowMonologue", {
      text = text,
      duration = DISPLAY_TIME,
    })
  end

  log("I", logTag, string.format("Showing monologue (lang=%s): %s", lang, text))
end

-- Queue a monologue with delay (reaction time)
local function queueMonologue(monologue, delay)
  delay = delay or math.random(REACTION_DELAY_MIN, REACTION_DELAY_MAX)

  state.pendingMonologue = monologue
  state.pendingTimer = delay

  log("D", logTag, "Queued monologue: " .. tostring(monologue.id) .. " (delay: " .. delay .. "s)")
end

-- Update active monologue display
local function updateMonologue(dtReal)
  if not state.activeMonologue then return end

  state.lineTimer = state.lineTimer + dtReal

  -- Check if current line is done
  if state.lineTimer >= DISPLAY_TIME then
    state.currentLineIndex = state.currentLineIndex + 1

    -- Check if we have more lines
    if state.currentLineIndex <= #state.activeMonologue.lines then
      -- Show next line
      state.lineTimer = 0
      local line = state.activeMonologue.lines[state.currentLineIndex]
      local lang = Steam and Steam.language or "en"

      -- Fix language selection - same as in showMonologue
      local isSpanish = (lang == "spanish" or lang:find("es") ~= nil or lang:find("spa") ~= nil)
      local rawText = isSpanish and line.es or line.en
      local text = replaceMonologuePlaceholders(rawText)

      if guihooks and guihooks.trigger then
        guihooks.trigger("mysummerShowMonologue", {
          text = text,
          duration = DISPLAY_TIME,
        })
      end
    else
      -- Monologue complete
      state.activeMonologue = nil
      state.currentLineIndex = 0
      state.lineTimer = 0

      if guihooks and guihooks.trigger then
        guihooks.trigger("mysummerHideMonologue", {})
      end
    end
  end
end

-- Update pending monologue timer
local function updatePending(dtReal)
  if not state.pendingMonologue then return end

  state.pendingTimer = state.pendingTimer - dtReal

  if state.pendingTimer <= 0 then
    showMonologue(state.pendingMonologue)
    state.pendingMonologue = nil
    state.pendingTimer = 0
  end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Called by narrative system when events occur
function M.onNarrativeEvent(eventId)
  if not state.enabled then
    log("D", logTag, "Monologue system disabled, skipping: " .. tostring(eventId))
    return false
  end

  local monologue = eventMonologues[eventId]
  if not monologue then
    log("D", logTag, "No monologue for event: " .. tostring(eventId))
    return false
  end

  -- Check if already triggered (unique monologues only)
  if monologue.id and state.triggeredMonologues[monologue.id] then
    log("D", logTag, "Monologue already triggered: " .. monologue.id)
    return false
  end

  -- Queue with reaction delay
  log("I", logTag, "Queuing monologue for event: " .. tostring(eventId))
  queueMonologue(monologue)
  return true
end

-- Force show monologue (for debugging)
function M.debugForceMonologue(eventId)
  local monologue = eventMonologues[eventId]
  if not monologue then
    print("ERROR: Monologue not found: " .. tostring(eventId))
    return
  end

  showMonologue(monologue)
end

-- Get list of all monologue IDs
function M.getAllMonologueIds()
  local ids = {}
  for eventId, mono in pairs(eventMonologues) do
    table.insert(ids, eventId)
  end
  return ids
end

-- Reset triggered state for a specific event (for race replay)
function M.resetTriggered(eventId)
  local monologue = eventMonologues[eventId]
  if monologue and monologue.id then
    state.triggeredMonologues[monologue.id] = nil
    log("D", logTag, "Reset triggered state for monologue: " .. monologue.id)
  end
end

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

loadState = function()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath)

  if data then
    state.triggeredMonologues = data.triggeredMonologues or {}
    log("I", logTag, "Loaded monologue state")
  else
    log("D", logTag, "No saved monologue state found")
  end
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
    triggeredMonologues = state.triggeredMonologues,
  }

  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("D", logTag, "Saved monologue state")
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onUpdate(dtReal, dtSim, dtRaw)
  updateMonologue(dtReal)
  updatePending(dtReal)
end

local function onExtensionLoaded()
  log("I", logTag, "Monologue system loaded (8-phase narrative)")
end

local function onCareerActive()
  loadState()
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
-- M.onNarrativeEvent is already defined above as function M.onNarrativeEvent()
-- M.debugForceMonologue is already defined above as function M.debugForceMonologue()
-- M.getAllMonologueIds is already defined above as function M.getAllMonologueIds()

return M
