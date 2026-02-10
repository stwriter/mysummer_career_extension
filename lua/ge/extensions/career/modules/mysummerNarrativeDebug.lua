-- MySummer Narrative Debug System
-- Tools for testing the complete narrative without playing

local M = {}
M.moduleName = "career_modules_mysummerNarrativeDebug"

M.dependencies = {
  "career_career",
  "career_modules_playerAttributes",
}

local logTag = "mysummerNarrativeDebug"

-- Forward declarations
local getNarrative
local getChat

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

getNarrative = function()
  return extensions.career_modules_mysummerNarrative
end

getChat = function()
  return extensions.career_modules_mysummerChat
end

-- Phase thresholds (must match mysummerNarrative and streetracing skill)
local phaseThresholds = {
  [0] = 0,
  [1] = 350,
  [2] = 850,
  [3] = 1600,
  [4] = 2400,
  [5] = 3300,
  [6] = 4500,
  [7] = 6000,
  [8] = 7800,
}

local phaseNames = {
  [0] = "Phase 0 - El Peso del Silencio (Prologue)",
  [1] = "Phase 1 - Origins",
  [2] = "Phase 2 - The Split",
  [3] = "Phase 3 - The Crisis",
  [4] = "Phase 4 - Ruptura Final",
  [5] = "Phase 5 - Rally Regional",
  [6] = "Phase 6 - Copa Covet",
  [7] = "Phase 7 - Clasificatorias",
  [8] = "Phase 8 - The Big One",
}

-- All narrative events in order
local allEvents = {
  { id = "ghost_first_message", phase = 1, description = "Ghost: 'Reminds me of someone'" },
  { id = "ghost_grandfather_warning", phase = 2, description = "Ghost hints at grandfather's past" },
  { id = "rook_stress_signs", phase = 3, description = "Rook shows stress" },
  { id = "nova_ambition_reveal", phase = 3, description = "Nova talks about The Big One" },
  { id = "rook_nova_argument", phase = 4, description = "Rook/Nova fight" },
  { id = "nova_frustration", phase = 4, description = "Nova asks your opinion" },
  { id = "ghost_final_warning", phase = 5, description = "Ghost: 'Watch your back'" },
  { id = "car_stolen", phase = 5, description = "CAR STOLEN - Major event" },
  { id = "ghost_truth_reveal", phase = 6, description = "Ghost reveals innocence" },
  { id = "traitor_reveal", phase = 6, description = "Traitor revealed based on alignment" },
}

-- ============================================================================
-- DEBUG STATUS
-- ============================================================================

local function debugStatus()
  local narrative = getNarrative()
  local chat = getChat()

  if not narrative then
    log("E", logTag, "Narrative module not loaded!")
    print("ERROR: Narrative module not loaded")
    return
  end

  local progress = narrative.getNarrativeProgress()
  local xp = career_modules_playerAttributes.getAttributeValue("mysummer-streetracing") or 0

  print("\n========== MYSUMMER NARRATIVE STATUS ==========")
  print(string.format("Current Phase: %d - %s", progress.phase, phaseNames[progress.phase] or "Unknown"))
  print(string.format("Street Racing XP: %d", xp))
  local nextThreshold = phaseThresholds[progress.phase + 1]
  if nextThreshold then
    print(string.format("Next Phase at: %d XP", nextThreshold))
  else
    print("Next Phase at: MAX (final phase)")
  end

  print("\n--- Story Flags ---")
  if next(progress.storyFlags) then
    for flag, value in pairs(progress.storyFlags) do
      print(string.format("  %s = %s", flag, tostring(value)))
    end
  else
    print("  (none)")
  end

  print("\n--- Triggered Events ---")
  local triggeredCount = 0
  for _, event in ipairs(allEvents) do
    local triggered = progress.triggeredEvents[event.id]
    local status = triggered and "[X]" or "[ ]"
    local phaseOk = progress.phase >= event.phase
    local available = phaseOk and "[Phase OK]" or string.format("[Needs Phase %d]", event.phase)
    print(string.format("  %s Phase %d: %s %s", status, event.phase, event.id, triggered and "" or available))
    if triggered then triggeredCount = triggeredCount + 1 end
  end
  print(string.format("\nProgress: %d/%d events triggered", triggeredCount, #allEvents))

  if chat then
    print("\n--- Teammate Alignment ---")
    local effects = chat.getAllEffects() or {}
    print(string.format("  Rook Affinity: %d", effects.rook_affinity or 0))
    print(string.format("  Nova Affinity: %d", effects.nova_affinity or 0))
    print(string.format("  Alignment: %s", chat.getTeammateAlignment() or "neutral"))

    print("\n--- Unlocked Contacts ---")
    local conversations = chat.getConversations() or {}
    for contactId, _ in pairs(conversations) do
      print(string.format("  - %s", contactId))
    end
  end

  print("================================================\n")
end

-- ============================================================================
-- PHASE CONTROL
-- ============================================================================

local function debugSetPhase(phase)
  if not phase or phase < 0 or phase > 8 then
    print("Usage: debugSetPhase(0-8)")
    print("Phases: 0=Prologue, 1=Origins, 2=The Split, 3=The Crisis, 4=Ruptura Final, 5=Rally, 6=Covet Cup, 7=Clasificatorias, 8=The Big One")
    return
  end

  local targetXP = phaseThresholds[phase] + 50 -- Add buffer
  career_modules_playerAttributes.setAttributes({["mysummer-streetracing"] = targetXP})

  print(string.format("Set phase to %d (%s) with %d XP", phase, phaseNames[phase], targetXP))
  -- Note: removed debugStatus() call here to avoid breaking execution flow
end

local function debugNextPhase()
  local narrative = getNarrative()
  if not narrative then return end

  local progress = narrative.getNarrativeProgress()
  local nextPhase = math.min(progress.phase + 1, 8)
  debugSetPhase(nextPhase)
end

-- ============================================================================
-- EVENT CONTROL
-- ============================================================================

local function debugListEvents()
  print("\n========== ALL NARRATIVE EVENTS ==========")
  for i, event in ipairs(allEvents) do
    print(string.format("%2d. [Phase %d] %s", i, event.phase, event.id))
    print(string.format("    %s", event.description))
  end
  print("===========================================\n")
  print("Use: career_modules_mysummerNarrative.forceTriggerEvent('event_id')")
end

local function debugTriggerEvent(eventId)
  local narrative = getNarrative()
  if not narrative then
    print("ERROR: Narrative module not loaded")
    return
  end

  local success = narrative.forceTriggerEvent(eventId)
  if success then
    print(string.format("Triggered event: %s", eventId))
  else
    print(string.format("Failed to trigger event: %s (not found or already triggered)", eventId))
  end
end

local function debugTriggerAllPhaseEvents(phase)
  local narrative = getNarrative()
  if not narrative then return end

  print(string.format("\n--- Triggering all Phase %d events ---", phase))

  for _, event in ipairs(allEvents) do
    if event.phase == phase then
      local progress = narrative.getNarrativeProgress()
      if not progress.triggeredEvents[event.id] then
        print(string.format("Triggering: %s", event.id))
        narrative.forceTriggerEvent(event.id)
        -- Small delay for message processing
      else
        print(string.format("Already triggered: %s", event.id))
      end
    end
  end
end

-- ============================================================================
-- CONTACT CONTROL
-- ============================================================================

local function debugUnlockAllContacts()
  local chat = getChat()
  if not chat then
    print("ERROR: Chat module not loaded")
    return
  end

  local contacts = {"ghost", "rook", "nova", "techie", "muscle", "import", "shadow", "viper"}
  for _, contactId in ipairs(contacts) do
    chat.unlockContact(contactId)
    print(string.format("Unlocked: %s", contactId))
  end
end

local function debugSetAlignment(alignment)
  local chat = getChat()
  if not chat then
    print("ERROR: Chat module not loaded")
    return
  end

  if alignment == "rook" then
    chat.applyEffects({rook_affinity = 100, nova_affinity = 20})
    print("Alignment set to ROOK (Nova will be traitor)")
  elseif alignment == "nova" then
    chat.applyEffects({rook_affinity = 20, nova_affinity = 100})
    print("Alignment set to NOVA (Rook will be traitor)")
  elseif alignment == "neutral" then
    chat.applyEffects({rook_affinity = 50, nova_affinity = 50})
    print("Alignment set to NEUTRAL (both failed)")
  else
    print("Usage: debugSetAlignment('rook' | 'nova' | 'neutral')")
  end
end

-- ============================================================================
-- THEATER MODE
-- ============================================================================

local theaterState = {
  active = false,
  currentPhase = 0,
  currentEventIndex = 1,
  speedMultiplier = 1,
  paused = false,
}

local function debugTheaterMode(speedMultiplier)
  speedMultiplier = speedMultiplier or 1

  print("\n========== THEATER MODE ==========")
  print(string.format("Speed: %dx", speedMultiplier))
  print("Playing full narrative sequence...")
  print("===================================\n")

  theaterState.active = true
  theaterState.currentPhase = 0
  theaterState.currentEventIndex = 1
  theaterState.speedMultiplier = speedMultiplier
  theaterState.paused = false

  -- Start from phase 0
  debugSetPhase(0)

  -- Unlock essential contacts
  local chat = getChat()
  if chat then
    chat.unlockContact("rook")
    chat.unlockContact("nova")
  end

  -- Play through each phase
  local function playNextPhase()
    if not theaterState.active then return end

    local phase = theaterState.currentPhase
    print(string.format("\n>>> PHASE %d: %s <<<", phase, phaseNames[phase]))

    -- Set phase
    debugSetPhase(phase)

    -- Trigger all events for this phase
    debugTriggerAllPhaseEvents(phase)

    -- Move to next phase
    theaterState.currentPhase = phase + 1

    if theaterState.currentPhase <= 8 then
      local delay = 5000 / theaterState.speedMultiplier -- 5 seconds between phases
      if theaterState.speedMultiplier == 0 then
        delay = 100 -- Instant mode
      end
      -- Schedule next phase (would need timer system)
      print(string.format("(Next phase in %.1f seconds...)", delay / 1000))
    else
      print("\n========== THEATER MODE COMPLETE ==========")
      print("All narrative events have been triggered.")
      print("Check the phone chat for messages.")
      theaterState.active = false
    end
  end

  playNextPhase()

  -- Return instructions for manual continuation
  print("\nTo continue to next phase manually:")
  print("  career_modules_mysummerNarrativeDebug.theaterNextPhase()")
end

local function theaterNextPhase()
  if theaterState.currentPhase > 8 then
    print("Theater mode complete!")
    return
  end

  local phase = theaterState.currentPhase
  print(string.format("\n>>> PHASE %d: %s <<<", phase, phaseNames[phase]))

  debugSetPhase(phase)
  debugTriggerAllPhaseEvents(phase)

  theaterState.currentPhase = phase + 1

  if theaterState.currentPhase <= 8 then
    print(string.format("\nCall theaterNextPhase() for Phase %d", theaterState.currentPhase))
  else
    print("\n========== THEATER MODE COMPLETE ==========")
  end
end

local function debugPlayPhase(phase)
  if not phase or phase < 0 or phase > 8 then
    print("Usage: debugPlayPhase(0-8)")
    return
  end

  print(string.format("\n>>> PLAYING PHASE %d: %s <<<", phase, phaseNames[phase]))

  -- Set phase
  debugSetPhase(phase)

  -- Unlock contacts if needed based on phase
  local chat = getChat()
  if chat then
    if phase >= 0 then
      chat.unlockContact("ghost")
    end
    if phase >= 1 then
      chat.unlockContact("rook")
      chat.unlockContact("nova")
      chat.unlockContact("techie")
    end
    if phase >= 2 then
      chat.unlockContact("muscle")
    end
    if phase >= 3 then
      chat.unlockContact("shadow")
    end
    if phase >= 8 then
      chat.unlockContact("viper")
    end
  end

  -- Trigger all events for this phase
  debugTriggerAllPhaseEvents(phase)

  print("\nCheck the phone chat for messages.")
end

-- ============================================================================
-- RESET
-- ============================================================================

local function debugReset()
  print("Resetting all narrative progress...")

  -- Reset XP
  career_modules_playerAttributes.setAttributes({["mysummer-streetracing"] = 0})

  -- Reset narrative state (need to reload)
  local narrative = getNarrative()
  if narrative and narrative.debugReset then
    narrative.debugReset()
  end

  print("Narrative reset complete. You may need to reload the career.")
  print("Use: career_career.reloadCareer()")
end

-- ============================================================================
-- QUICK TEST COMMANDS
-- ============================================================================

local function debugQuickTest()
  print("\n========== QUICK TEST COMMANDS ==========")
  print("")
  print("-- PROBAR TODO DE UNA VEZ --")
  print("career_modules_mysummerNarrativeDebug.debugFullStory()")
  print("")
  print("-- STATUS --")
  print("career_modules_mysummerNarrativeDebug.debugStatus()")
  print("")
  print("-- PHASE CONTROL (0-8) --")
  print("career_modules_mysummerNarrativeDebug.debugSetPhase(3)")
  print("career_modules_mysummerNarrativeDebug.debugNextPhase()")
  print("")
  print("-- EVENTS --")
  print("career_modules_mysummerNarrativeDebug.debugListEvents()")
  print("career_modules_mysummerNarrative.forceTriggerEvent('ghost_first_message')")
  print("")
  print("-- CONTACTS --")
  print("career_modules_mysummerNarrativeDebug.debugUnlockAllContacts()")
  print("career_modules_mysummerNarrativeDebug.debugSetAlignment('rook')")
  print("")
  print("-- ROMANCE & VEHICLE (8-PHASE SYSTEM) --")
  print("career_modules_mysummerNarrativeDebug.debugTriggerRomanceChoice()")
  print("career_modules_mysummerNarrativeDebug.debugSetRomanceChoice('rook')")
  print("career_modules_mysummerNarrativeDebug.debugTriggerCarTheft()")
  print("career_modules_mysummerNarrativeDebug.debugRecoverCar()")
  print("career_modules_mysummerNarrativeDebug.debugCheckVehicle()")
  print("")
  print("-- THEATER MODE --")
  print("career_modules_mysummerNarrativeDebug.debugTheaterMode(5)  -- 5x speed")
  print("career_modules_mysummerNarrativeDebug.theaterNextPhase()   -- manual next")
  print("career_modules_mysummerNarrativeDebug.debugPlayPhase(2)    -- play single phase (0-8)")
  print("")
  print("-- RESET --")
  print("career_modules_mysummerNarrativeDebug.debugReset()")
  print("==========================================\n")
end

-- ============================================================================
-- FULL STORY MODE - Everything at once
-- ============================================================================

local fullStoryState = {
  active = false,
  currentStep = 0,
  steps = {},
  timer = 0,
  autoPlay = false,
}

-- Forward declaration
local executeFullStoryStep

local function debugFullStory()
  print("\n")
  print("╔══════════════════════════════════════════════════════════════╗")
  print("║           MYSUMMER - HISTORIA COMPLETA                       ║")
  print("║                                                              ║")
  print("║  Esto va a reproducir TODA la narrativa:                     ║")
  print("║  - Eventos de chat                                           ║")
  print("║  - Monólogos internos                                        ║")
  print("║  - Llamadas telefónicas                                      ║")
  print("║                                                              ║")
  print("║  Abre el teléfono -> Chat para ver los mensajes              ║")
  print("╚══════════════════════════════════════════════════════════════╝")
  print("\n")

  -- Reset first
  local narrative = getNarrative()
  if narrative and narrative.debugReset then
    narrative.debugReset()
  end

  -- Unlock contacts
  debugUnlockAllContacts()

  -- Build step sequence
  -- IMPORTANT: Delays must be long enough for content to display!
  -- - Events trigger chat messages (need ~8s for typing + reading)
  -- - Monologues show on DialogueOverlay (need ~12s for multiple lines)
  -- - Calls show dialogue (need ~15s for full conversation)
  -- - Phase changes just update XP (3s is enough)
  fullStoryState.steps = {
    -- Phase 1
    { type = "phase", phase = 1, name = "FASE 1: Carreras entre Conocidos", delay = 3 },
    { type = "event", id = "ghost_first_message", delay = 10 },

    -- Phase 2
    { type = "phase", phase = 2, name = "FASE 2: Underground Bajo", delay = 3 },
    { type = "event", id = "ghost_grandfather_warning", delay = 10 },

    -- Phase 3
    { type = "phase", phase = 3, name = "FASE 3: Rallys Regionales", delay = 3 },
    { type = "event", id = "rook_stress_signs", delay = 10 },
    { type = "event", id = "nova_ambition_reveal", delay = 10 },

    -- Phase 4
    { type = "phase", phase = 4, name = "FASE 4: Underground Alto", delay = 3 },
    { type = "event", id = "rook_nova_argument", delay = 10 },
    { type = "event", id = "nova_frustration", delay = 10 },

    -- Phase 5
    { type = "phase", phase = 5, name = "FASE 5: Rallys Oficiales", delay = 3 },
    { type = "event", id = "ghost_final_warning", delay = 10 },
    { type = "event", id = "car_stolen", delay = 12 },

    -- Phase 6
    { type = "phase", phase = 6, name = "FASE 6: The Big One", delay = 3 },
    { type = "alignment", alignment = "rook", delay = 2 },  -- Set alignment for traitor reveal
    { type = "event", id = "ghost_truth_reveal", delay = 12 },
    { type = "event", id = "traitor_reveal", delay = 12 },

    -- End
    { type = "end" },
  }

  fullStoryState.active = true
  fullStoryState.currentStep = 1
  fullStoryState.autoPlay = true
  fullStoryState.timer = 0

  print("Ejecutando paso 1/" .. #fullStoryState.steps .. "...")
  print("La historia avanzará automáticamente.")
  print("Usa debugStopStory() para detener.")
  print("")

  executeFullStoryStep()
end

local function debugStopStory()
  fullStoryState.active = false
  fullStoryState.autoPlay = false
  print("Historia detenida.")
end

local function executeFullStoryStep()
  if not fullStoryState.active then return end
  if fullStoryState.currentStep > #fullStoryState.steps then
    fullStoryState.active = false
    print("\n========== HISTORIA COMPLETA ===========\n")
    return
  end

  local step = fullStoryState.steps[fullStoryState.currentStep]

  if step.type == "phase" then
    print("\n>>> " .. step.name .. " <<<\n")
    debugSetPhase(step.phase)

  elseif step.type == "event" then
    print("  [Evento] " .. step.id)
    local narrative = getNarrative()
    if narrative then
      narrative.forceTriggerEvent(step.id)
    end

  elseif step.type == "monologue" then
    print("  [Monólogo] " .. step.id)
    local monologues = extensions.career_modules_mysummerMonologues
    if monologues then
      monologues.debugForceMonologue(step.id)
    end

  elseif step.type == "call" then
    print("  [Llamada] " .. step.id)
    local calls = extensions.career_modules_mysummerCalls
    if calls then
      calls.debugForceCall(step.id)
    end

  elseif step.type == "alignment" then
    print("  [Alineación] " .. step.alignment)
    debugSetAlignment(step.alignment)

  elseif step.type == "end" then
    fullStoryState.active = false
    print("\n╔══════════════════════════════════════════════════════════════╗")
    print("║                    FIN DE LA HISTORIA                        ║")
    print("║                                                              ║")
    print("║  Revisa el chat del teléfono para ver todos los mensajes    ║")
    print("╚══════════════════════════════════════════════════════════════╝\n")
    return
  end

  fullStoryState.currentStep = fullStoryState.currentStep + 1

  -- Schedule next step
  local delay = step.delay or 1
  fullStoryState.timer = delay

  if fullStoryState.autoPlay then
    print("    (siguiente paso en " .. delay .. "s...)")
  end
end

local function debugNextStep()
  if not fullStoryState.active then
    print("No hay historia en progreso. Usa debugFullStory() para empezar.")
    return
  end
  executeFullStoryStep()
end

local function debugAutoPlay()
  if not fullStoryState.active then
    debugFullStory()
  end
end

-- ============================================================================
-- NEW: ROMANCE & VEHICLE DEBUG COMMANDS (8-PHASE SYSTEM)
-- ============================================================================

-- Trigger romance choice modal (Phase 5)
local function debugTriggerRomanceChoice()
  print("Triggering romance choice modal...")

  -- Show romance choice UI
  if guihooks and guihooks.trigger then
    guihooks.trigger("mysummerShowRomanceChoice", {})
    print("Romance choice modal should appear on screen.")
    print("Choose between Rook and Nova.")
  else
    print("ERROR: guihooks not available")
  end
end

-- Set romance choice programmatically
local function debugSetRomanceChoice(choice)
  if choice ~= "rook" and choice ~= "nova" then
    print("Usage: debugSetRomanceChoice('rook' or 'nova')")
    return
  end

  local narrative = getNarrative()
  if not narrative then
    print("ERROR: Narrative module not loaded")
    return
  end

  -- Call the romance choice callback
  narrative.onRomanceChoice(choice)
  print(string.format("Romance choice set to: %s", choice))
  print("Partner affinity updated, flags set.")
end

-- Trigger car theft cutscene (Phase 5 end)
local function debugTriggerCarTheft()
  print("Triggering ETK-I theft event...")

  local narrative = getNarrative()
  if not narrative then
    print("ERROR: Narrative module not loaded")
    return
  end

  local success = narrative.forceTriggerEvent("etki_stolen_rally")
  if success then
    print("Car theft triggered - check for cutscene and Ghost messages")
  else
    print("Failed to trigger car theft event (already triggered or not found)")
  end
end

-- Instantly recover car (skip to Phase 8)
local function debugRecoverCar()
  print("Instantly recovering ETK-I...")

  local narrative = getNarrative()
  if not narrative then
    print("ERROR: Narrative module not loaded")
    return
  end

  -- Trigger recovery event
  local success = narrative.forceTriggerEvent("etki_recovered")
  if success then
    print("ETK-I recovered - check partner dialogue")
  else
    print("Failed to trigger recovery event")
  end
end

-- Check current vehicle status
local function debugCheckVehicle()
  print("\n========== VEHICLE STATUS ==========")

  -- Get player vehicle
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then
    print("No player vehicle found!")
    return
  end

  local model = playerVehicle:getJBeamFilename()
  local vehName = playerVehicle:getName() or "Unknown"

  print(string.format("Current Vehicle: %s", vehName))
  print(string.format("Model: %s", model))

  -- Check if it's the project car
  if model == "etki" then
    print("✓ This is the ETK-I project car")
  elseif model == "covet" then
    print("✓ This is an Ibishu Covet")
  else
    print("✗ This is neither ETK-I nor Covet")
  end

  -- Check story flags
  local narrative = getNarrative()
  if narrative then
    local progress = narrative.getNarrativeProgress()
    print("\n--- Car Story Status ---")
    print(string.format("Car Stolen: %s", tostring(progress.storyFlags.car_stolen or false)))
    print(string.format("Car Recovered: %s", tostring(progress.storyFlags.car_recovered or false)))
    print(string.format("ETK-I Location: %s", progress.storyFlags.etki_location or "unknown"))
    print(string.format("Covet Fund Received: %s", tostring(progress.storyFlags.covet_fund_received or false)))
  end

  print("====================================\n")
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onUpdate(dtReal, dtSim, dtRaw)
  -- Process full story auto-play
  if fullStoryState.active and fullStoryState.autoPlay then
    fullStoryState.timer = fullStoryState.timer - dtReal

    if fullStoryState.timer <= 0 then
      executeFullStoryStep()
    end
  end
end

local function onExtensionLoaded()
  log("I", logTag, "Narrative Debug system loaded")
  log("I", logTag, "Use career_modules_mysummerNarrativeDebug.debugQuickTest() for commands")
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- Status
M.debugStatus = debugStatus
M.debugQuickTest = debugQuickTest

-- Phase control
M.debugSetPhase = debugSetPhase
M.debugNextPhase = debugNextPhase

-- Events
M.debugListEvents = debugListEvents
M.debugTriggerEvent = debugTriggerEvent
M.debugTriggerAllPhaseEvents = debugTriggerAllPhaseEvents

-- Contacts
M.debugUnlockAllContacts = debugUnlockAllContacts
M.debugSetAlignment = debugSetAlignment

-- Theater mode
M.debugTheaterMode = debugTheaterMode
M.theaterNextPhase = theaterNextPhase
M.debugPlayPhase = debugPlayPhase

-- Reset
M.debugReset = debugReset

-- Full story mode
M.debugFullStory = debugFullStory
M.debugNextStep = debugNextStep
M.debugStopStory = debugStopStory
M.debugAutoPlay = debugAutoPlay

-- Romance & Vehicle debug (8-phase system)
M.debugTriggerRomanceChoice = debugTriggerRomanceChoice
M.debugSetRomanceChoice = debugSetRomanceChoice
M.debugTriggerCarTheft = debugTriggerCarTheft
M.debugRecoverCar = debugRecoverCar
M.debugCheckVehicle = debugCheckVehicle

-- Lifecycle
M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate

return M
