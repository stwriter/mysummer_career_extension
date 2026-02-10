-- MySummer Narrative Events System
-- Handles story-critical events based on player progress and choices

local M = {}
M.moduleName = "career_modules_mysummerNarrative"

-- Note: mysummerChat is used but not listed as hard dependency to avoid cycles
M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_branches",
  "career_modules_playerAttributes",
  -- NOTE: We don't declare mysummerMonologues, mysummerCalls, mysummerChat as dependencies
  -- to avoid circular dependency issues. We access them dynamically via extensions table.
}

local logTag = "mysummerNarrative"
local saveFile = "mysummer_narrative.json"

-- Forward declarations
local saveState
local loadState

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  -- Triggered narrative events (prevents re-triggering)
  triggeredEvents = {},

  -- Current narrative phase (synced from streetracing skill)
  currentPhase = 0,

  -- Story flags set by events
  storyFlags = {},

  -- Pending events to trigger
  pendingEvents = {},

  -- Cooldown for event checks
  lastEventCheck = 0,
}

-- ============================================================================
-- NARRATIVE EVENTS DEFINITIONS
-- ============================================================================

-- Helper to get chat module (loaded dynamically to avoid cycles)
local function getChat()
  return extensions.career_modules_mysummerChat
end

-- Helper to show a fullscreen scene sequence (loaded dynamically to avoid cycles)
local function showScene(sequenceId)
  local career = extensions.career_modules_mysummerCareer
  if career and career.showSceneSequence then
    career.showSceneSequence(sequenceId)
    return true
  end
  log("W", logTag, "Could not show scene: mysummerCareer not available")
  return false
end

-- Each event has:
--   id: unique identifier
--   phase: minimum narrative phase required
--   conditions: function that returns true if event can trigger
--   onTrigger: function called when event triggers
--   priority: higher = checked first
--   unique: if true, only triggers once ever

local narrativeEvents = {
  -- ========================================================================
  -- PHASE 0: EL PESO DEL SILENCIO (The Weight of Silence)
  -- ========================================================================
  -- Prologue: Grandfather's letter, first races, Ghost introduction

  {
    id = "inherited_garage",
    phase = 0,
    priority = 200,
    unique = true,
    conditions = function()
      -- Only trigger when explicitly queued
      return state.storyFlags.career_started == true
    end,
    onTrigger = function()
      local monologues = extensions.career_modules_mysummerMonologues
      if monologues and monologues.onNarrativeEvent then
        monologues.onNarrativeEvent("inherited_garage")
      end

      state.storyFlags.inherited_garage = true
      state.storyFlags.has_miramar = true
      state.storyFlags.has_etki_chassis = true
      log("I", logTag, "Phase 0: Grandfather's letter, garage inherited")
    end
  },

  {
    id = "ghost_race1_call",
    phase = 0,
    priority = 190,
    unique = true,
    conditions = function()
      -- Triggered by race completion, no additional conditions needed
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.unlockContact("ghost")

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "No ha estado mal, Miller.", en = "Not bad, Miller."} },
        { speaker = "ghost", text = {es = "Tienes ese tic en las curvas que tenía tu abuelo... entras demasiado rápido.", en = "You have that cornering tic your grandfather had... you go in too fast."} },
        { speaker = "ghost", text = {es = "Vigila la temperatura del aceite, no queremos incendios tan pronto.", en = "Watch the oil temperature, we don't want fires this soon."} },
      }, 2000)

      state.storyFlags.ghost_first_call = true
      log("I", logTag, "Phase 0: Ghost first call after Race 1")

      -- Chain: Introduce Rook and Nova immediately after Ghost's call
      -- This ensures they are known BEFORE Race 2 events fire
      chat.unlockContact("rook")
      chat.unlockContact("nova")
      showScene("rook_nova_introduction")
      state.storyFlags.met_rook_and_nova = true
      log("I", logTag, "Phase 0: Rook and Nova introduced (chained with Ghost call)")
    end
  },

  -- Race 2: Nova's message AFTER race (they've already been introduced above)
  {
    id = "ghost_race2_rook_nova_intro",
    phase = 0,
    priority = 180,
    unique = true,
    conditions = function()
      -- Only trigger if player has already met Rook and Nova
      return state.storyFlags.met_rook_and_nova == true
    end,
    onTrigger = function()
      -- No longer unlocks contacts (already done in rook_nova_introduction)
      -- This event now just triggers the race 2 SMS from Nova
      log("I", logTag, "Phase 0: Race 2 post-event (Rook/Nova already known)")
    end
  },

  -- Contact Mission Gate (after Race 3)
  {
    id = "ghost_legacy_mechanic_mission_gate",
    phase = 0,
    priority = 170,
    unique = true,
    conditions = function()
      -- Triggered by race completion, no additional conditions needed
      return true
    end,
    onTrigger = function()
      -- Show fullscreen scene: Ghost reveals grandfather's past
      showScene("ghost_legacy_mechanic")

      -- Also offer the story mission via mysummerMissions
      local missions = extensions.career_modules_mysummerMissions
      if missions then
        missions.offerMissionViaEmail("ghost", "ghost_legacy_mechanic")
      end

      state.storyFlags.ghost_mission_ready = true
      log("I", logTag, "Phase 0: Ghost contact mission 'El Legado del Mecánico' (fullscreen scene)")
    end
  },

  -- ========================================================================
  -- PHASE 1: ORIGINS
  -- ========================================================================
  -- Philosophy clash between Rook and Nova, Techie introduction

  {
    id = "phase1_triangle_begins",
    phase = 1,
    priority = 160,
    unique = true,
    conditions = function()
      -- Triggered by race completion, no dependencies
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      -- Nova and Rook's conflicting messages about racing philosophy
      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Buena carrera, de verdad.", en = "Good race, really."} },
        { speaker = "rook", text = {es = "Me gusta que no hayas entrado en las provocaciones de Nova.", en = "I like that you didn't fall for Nova's provocations."} },
        { speaker = "rook", text = {es = "La técnica gana carreras, no solo la suerte.", en = "Technique wins races, not just luck."} },
      }, 2000)

      state.storyFlags.philosophy_clash_started = true
      log("I", logTag, "Phase 1: Philosophy clash begins")
    end
  },

  {
    id = "rook_technical_lecture",
    phase = 1,
    priority = 150,
    unique = true,
    conditions = function()
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Escuchad el motor, no solo el viento.", en = "Listen to the engine, not just the wind."} },
        { speaker = "rook", text = {es = "Miller, fíjate en cómo reacciona tu chasis en las transiciones de peso.", en = "Miller, notice how your chassis reacts in weight transitions."} },
        { speaker = "rook", text = {es = "La velocidad es un lenguaje.", en = "Speed is a language."} },
      }, 2500)

      state.storyFlags.rook_philosophy_shared = true
      log("I", logTag, "Phase 1: Rook shares technical philosophy")
    end
  },

  {
    id = "nova_pushes_aggression",
    phase = 1,
    priority = 140,
    unique = true,
    conditions = function()
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "Rook se está volviendo un blando, Miller.", en = "Rook is getting soft, Miller."} },
        { speaker = "nova", text = {es = "Esa 'charla técnica' casi me duerme en la recta.", en = "That 'technical talk' almost puts me to sleep on the straight."} },
        { speaker = "nova", text = {es = "Tú tienes esa chispa de Miller. No dejes que él te la apague.", en = "You have that Miller spark. Don't let him extinguish it."} },
      }, 3000)

      state.storyFlags.nova_philosophy_shared = true
      log("I", logTag, "Phase 1: Nova pushes aggressive philosophy")
    end
  },

  -- Techie contact mission gate
  {
    id = "techie_mission_gate",
    phase = 1,
    priority = 130,
    unique = true,
    conditions = function()
      return state.storyFlags.nova_philosophy_shared
    end,
    onTrigger = function()
      local chat = getChat()
      if chat then
        chat.unlockContact("techie")
      end

      -- Show fullscreen scene: Techie introduction
      showScene("techie_hardware_souls")

      -- Also offer Techie story mission
      local missions = extensions.career_modules_mysummerMissions
      if missions then
        missions.offerMissionViaEmail("techie", "techie_hardware_souls")
      end

      state.storyFlags.techie_mission_ready = true
      log("I", logTag, "Phase 1: Techie contact mission 'Hardware y Almas' (fullscreen scene)")
    end
  },

  -- ========================================================================
  -- PHASE 2: THE SPLIT
  -- ========================================================================
  -- Tension escalation, Muscle introduction, grandfather's past revealed

  {
    id = "tension_escalates",
    phase = 2,
    priority = 120,
    unique = true,
    conditions = function()
      -- Phase condition removed: race sequencing guarantees correct phase
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "Rook me está asfixiando, Miller.", en = "Rook is suffocating me, Miller."} },
        { speaker = "nova", text = {es = "Cree que soy una aprendiz que necesita que le miren la presión de los neumáticos cada cinco minutos.", en = "He thinks I'm an apprentice who needs tire pressure checked every five minutes."} },
        { speaker = "nova", text = {es = "Tú entiendes que esto va de adrenalina, no de libros de mantenimiento.", en = "You understand this is about adrenaline, not maintenance books."} },
      }, 2500)

      state.storyFlags.tension_visible = true
      log("I", logTag, "Phase 2: Tension escalates visibly")
    end
  },

  {
    id = "muscle_observes_race",
    phase = 2,
    priority = 110,
    unique = true,
    conditions = function()
      return state.storyFlags.tension_visible
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "¿Has visto el muscle car que se ha unido a esta carrera?", en = "Did you see the muscle car that joined this race?"} },
        { speaker = "ghost", text = {es = "Es Muscle. Su padre murió en el accidente que hizo que tu abuelo dejara las llaves inglesas.", en = "It's Muscle. Her father died in the accident that made your grandfather put down the wrenches."} },
        { speaker = "ghost", text = {es = "Ella no guarda rencor, pero tampoco regala respeto.", en = "She doesn't hold grudges, but she doesn't give respect easily."} },
      }, 3000)

      state.storyFlags.muscle_appeared = true
      log("I", logTag, "Phase 2: Muscle observes a race")
    end
  },

  {
    id = "rook_nova_ultimatum",
    phase = 2,
    priority = 100,
    unique = true,
    conditions = function()
      return state.storyFlags.muscle_appeared
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Miller, escúchame bien.", en = "Miller, listen to me carefully."} },
        { speaker = "rook", text = {es = "He intentado hablar con Nova, pero ya no me escucha.", en = "I've tried talking to Nova, but she doesn't listen anymore."} },
        { speaker = "rook", text = {es = "Cree que puede saltarse las fases de preparación y entrar directa en las grandes ligas.", en = "She thinks she can skip preparation phases and go straight to the big leagues."} },
      }, 3000)

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "¡Deja de hablar por él, Rook!", en = "Stop speaking for him, Rook!"} },
        { speaker = "nova", text = {es = "Si nos quedamos aquí, acabaremos siendo como el abuelo de Miller: leyendas de un garaje que nadie visita.", en = "If we stay here, we'll end up like Miller's grandfather: legends of a garage nobody visits."} },
        { speaker = "nova", text = {es = "Yo me voy, con o sin vosotros.", en = "I'm leaving, with or without you."} },
      }, 6500)

      state.storyFlags.ultimatum_delivered = true
      log("I", logTag, "Phase 2: Rook and Nova's ultimatum")
    end
  },

  -- Muscle contact mission gate
  {
    id = "muscle_mission_gate",
    phase = 2,
    priority = 90,
    unique = true,
    conditions = function()
      return state.storyFlags.ultimatum_delivered
    end,
    onTrigger = function()
      local chat = getChat()
      if chat then
        chat.unlockContact("muscle")
      end

      -- Show fullscreen scene: Muscle reveals grandfather's past
      showScene("muscle_old_wounds")

      -- Also offer Muscle story mission
      local missions = extensions.career_modules_mysummerMissions
      if missions then
        missions.offerMissionViaEmail("muscle", "muscle_old_wounds")
      end

      state.storyFlags.muscle_mission_ready = true
      log("I", logTag, "Phase 2: Muscle contact mission 'Viejas Heridas' (fullscreen scene)")
    end
  },

  -- ========================================================================
  -- PHASE 3: THE CRISIS
  -- ========================================================================
  -- Player becomes tiebreaker, Nova proposes leaving, Shadow introduction

  {
    id = "player_becomes_mediator",
    phase = 3,
    priority = 85,
    unique = true,
    conditions = function()
      -- Phase condition removed: race sequencing guarantees correct phase
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "¡Miller, mira cómo entra Rook en la curva!", en = "Miller, look how Rook enters the corner!"} },
        { speaker = "nova", text = {es = "Está frenando demasiado pronto, tiene miedo de que las ruedas sufran.", en = "He's braking too early, afraid the tires will suffer."} },
        { speaker = "nova", text = {es = "¡Sígueme a mí, olvida su manual de seguridad!", en = "Follow me, forget his safety manual!"} },
      }, 2500)

      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "¡No es miedo, Nova, es gestión!", en = "It's not fear, Nova, it's management!"} },
        { speaker = "rook", text = {es = "Miller, si entras como ella, acabarás con los neumáticos achicharrados en una vuelta.", en = "Miller, if you go in like her, you'll end up with fried tires in one lap."} },
        { speaker = "rook", text = {es = "¡Mantén tu trazada y no dejes que su agresividad te desubique!", en = "Hold your line and don't let her aggression throw you off!"} },
      }, 5500)

      state.storyFlags.player_is_tiebreaker = true
      log("I", logTag, "Phase 3: Player becomes the tiebreaker")
    end
  },

  {
    id = "ghost_viper_philosophy",
    phase = 3,
    priority = 80,
    unique = true,
    conditions = function()
      return state.storyFlags.player_is_tiebreaker
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Miller, escucha el motor.", en = "Miller, listen to the engine."} },
        { speaker = "ghost", text = {es = "Tu abuelo y Viper eran el equipo perfecto porque él ponía la lógica y ella ponía la rabia.", en = "Your grandfather and Viper were the perfect team because he provided logic and she provided rage."} },
        { speaker = "ghost", text = {es = "Pero Rook y Nova... ellos no encajan.", en = "But Rook and Nova... they don't fit."} },
        { speaker = "ghost", text = {es = "Estás viendo un desastre anunciado.", en = "You're watching a disaster waiting to happen."} },
      }, 3000)

      state.storyFlags.ghost_explained_viper = true
      log("I", logTag, "Phase 3: Ghost explains Viper/grandfather dynamic")
    end
  },

  {
    id = "nova_private_proposal",
    phase = 3,
    priority = 75,
    unique = true,
    conditions = function()
      return state.storyFlags.ghost_explained_viper
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "Rook se ha quedado atrás gestionando neumáticos... siempre igual.", en = "Rook stayed behind managing tires... always the same."} },
        { speaker = "nova", text = {es = "Ahora estamos fuera del alcance de su radio, escucha Miller.", en = "Now we're out of his radio range, listen Miller."} },
        { speaker = "nova", text = {es = "He estado hablando con gente de la capital. Dicen que allí buscan pilotos con tu perfil.", en = "I've been talking to people in the capital. They say they're looking for drivers with your profile."} },
        { speaker = "nova", text = {es = "Piénsalo: tú, yo, y un circuito de verdad. Sin sermones sobre la temperatura del aceite.", en = "Think about it: you, me, and a real circuit. No lectures about oil temperature."} },
      }, 3500)

      state.storyFlags.nova_proposed_leaving = true
      log("I", logTag, "Phase 3: Nova proposes leaving town together")
    end
  },

  -- Shadow contact mission gate
  {
    id = "shadow_mission_gate",
    phase = 3,
    priority = 70,
    unique = true,
    conditions = function()
      return state.storyFlags.nova_proposed_leaving
    end,
    onTrigger = function()
      local chat = getChat()
      if chat then
        chat.unlockContact("shadow")
      end

      -- Show fullscreen scene: Shadow offers black market parts
      showScene("shadow_black_market")

      -- Also offer Shadow story mission
      local missions = extensions.career_modules_mysummerMissions
      if missions then
        missions.offerMissionViaEmail("shadow", "shadow_black_market_threshold")
      end

      state.storyFlags.shadow_mission_ready = true
      log("I", logTag, "Phase 3: Shadow contact mission 'El Umbral del Mercado Negro' (fullscreen scene)")
    end
  },

  -- ========================================================================
  -- PHASE 4: THE SPLIT (Final Rupture)
  -- ========================================================================
  -- Public breakup via radio, debt missions, REPEAT system

  {
    id = "nova_turbo_failure",
    phase = 4,
    priority = 65,
    unique = true,
    conditions = function()
      -- Phase condition removed: race sequencing guarantees correct phase
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "¡Maldita sea! Miller, algo le pasa al turbo.", en = "Damn it! Miller, something's wrong with the turbo."} },
        { speaker = "nova", text = {es = "El coche empuja como un demonio pero suena como si fuera a desintegrarse.", en = "The car pushes like a demon but sounds like it's going to disintegrate."} },
        { speaker = "nova", text = {es = "¡Rook, no te acerques, voy a intentar una maniobra por el exterior!", en = "Rook, don't get close, I'm going to try an outside maneuver!"} },
      }, 2500)

      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "¡Nova, frena! Estás echando fuego por el escape.", en = "Nova, brake! You're shooting fire from the exhaust."} },
        { speaker = "rook", text = {es = "Eso no es un ajuste estándar, ¿qué le has hecho al motor?", en = "That's not a standard adjustment, what did you do to the engine?"} },
        { speaker = "rook", text = {es = "Miller, ¿tú sabes algo de esto?", en = "Miller, do you know anything about this?"} },
      }, 6000)

      state.storyFlags.shadow_parts_revealed = true
      log("I", logTag, "Phase 4: Shadow parts cause Nova's turbo issues")
    end
  },

  {
    id = "rook_interrogation",
    phase = 4,
    priority = 60,
    unique = true,
    conditions = function()
      return state.storyFlags.shadow_parts_revealed
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Miller, escúchame bien.", en = "Miller, listen to me carefully."} },
        { speaker = "rook", text = {es = "He revisado el registro de telemetría de Nova.", en = "I've reviewed Nova's telemetry logs."} },
        { speaker = "rook", text = {es = "Esos picos de potencia no son de Techie, ni de Muscle. Son de Shadow, ¿verdad?", en = "Those power spikes aren't from Techie or Muscle. They're from Shadow, right?"} },
        { speaker = "rook", text = {es = "Si ella se mete en el mercado negro, no hay vuelta atrás.", en = "If she gets into the black market, there's no turning back."} },
      }, 3000)

      state.storyFlags.rook_knows_shadow = true
      log("I", logTag, "Phase 4: Rook discovers Shadow connection")
    end
  },

  {
    id = "public_breakup",
    phase = 4,
    priority = 55,
    unique = true,
    conditions = function()
      return state.storyFlags.rook_knows_shadow
    end,
    onTrigger = function()
      -- Show fullscreen scene: The public breakup
      showScene("public_breakup")

      state.storyFlags.team_broken = true
      state.storyFlags.rook_hostile = true
      log("I", logTag, "Phase 4: PUBLIC BREAKUP - Team destroyed (fullscreen scene)")
    end
  },

  -- Ghost/Shadow debt mission gate
  {
    id = "debt_mission_gate",
    phase = 4,
    priority = 50,
    unique = true,
    conditions = function()
      return state.storyFlags.team_broken
    end,
    onTrigger = function()
      -- Show fullscreen scene: Ghost warns about debt, Shadow offers deal
      showScene("debt_price_of_ambition")

      -- Offer debt payment mission
      local missions = extensions.career_modules_mysummerMissions
      if missions then
        missions.offerMissionViaEmail("ghost", "ghost_shadow_debt_payment")
      end

      state.storyFlags.debt_mission_ready = true
      log("I", logTag, "Phase 4: Debt mission 'El Precio de la Ambición' (fullscreen scene)")
    end
  },

  -- ========================================================================
  -- PHASE 5: POLVO Y TRAICIÓN (Rally Regional)
  -- ========================================================================
  -- Rally arc, romance choice, car theft

  {
    id = "rally_etki_sounds_perfect",
    phase = 5,
    priority = 45,
    unique = true,
    conditions = function()
      -- Phase condition removed: race sequencing guarantees correct phase
      return true
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Miller, el ETK-I suena exactamente como lo planeó tu abuelo hace treinta años.", en = "Miller, the ETK-I sounds exactly like your grandfather planned thirty years ago."} },
        { speaker = "ghost", text = {es = "Es estremecedor.", en = "It's breathtaking."} },
        { speaker = "ghost", text = {es = "No dejes que el éxito se te suba a la cabeza; la tierra perdona menos que el asfalto.", en = "Don't let success go to your head; dirt forgives less than asphalt."} },
      }, 3000)

      state.storyFlags.rally_started = true
      log("I", logTag, "Phase 5: Rally arc begins - ETK-I in its element")
    end
  },

  {
    id = "rally_nova_rook_money_talk",
    phase = 5,
    priority = 40,
    unique = true,
    conditions = function()
      return state.storyFlags.rally_started
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "¡Ese tiempo ha sido increíble, Miller!", en = "That time was incredible, Miller!"} },
        { speaker = "nova", text = {es = "Shadow dice que si ganas este rally, el ETK-I valdrá el triple en la capital.", en = "Shadow says if you win this rally, the ETK-I will be worth triple in the capital."} },
        { speaker = "nova", text = {es = "Podríamos largarnos de aquí mañana mismo.", en = "We could get out of here tomorrow."} },
      }, 2500)

      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "¡Para ya, Nova!", en = "Stop it, Nova!"} },
        { speaker = "rook", text = {es = "Miller no está corriendo por el dinero de Shadow.", en = "Miller isn't racing for Shadow's money."} },
        { speaker = "rook", text = {es = "Está corriendo por su abuelo.", en = "He's racing for his grandfather."} },
        { speaker = "rook", text = {es = "Ese coche es una pieza de historia, no una moneda de cambio.", en = "That car is a piece of history, not a bargaining chip."} },
      }, 6000)

      state.storyFlags.rally_tension = true
      log("I", logTag, "Phase 5: Nova and Rook fight over ETK-I's future")
    end
  },

  -- ROMANCE CHOICE EVENT (before Rally Race 3)
  {
    id = "romance_choice_trigger",
    phase = 5,
    priority = 35,
    unique = true,
    conditions = function()
      return state.storyFlags.rally_tension
    end,
    onTrigger = function()
      state.storyFlags.romance_choice_ready = true
      log("I", logTag, "Phase 5: ROMANCE CHOICE READY - Showing fullscreen scene")

      -- Show fullscreen scene: Rook and Nova plead their cases
      showScene("romance_choice")
    end
  },

  -- CAR THEFT EVENT (after Rally Race 4)
  {
    id = "etki_stolen_rally",
    phase = 5,
    priority = 30,
    unique = true,
    conditions = function()
      -- Check if romance choice was made
      return state.storyFlags.chosen_partner ~= nil
    end,
    onTrigger = function()
      -- TODO: Remove ETK-I from inventory
      state.storyFlags.car_stolen = true
      state.storyFlags.etki_location = "unknown"

      log("I", logTag, "Phase 5: CAR STOLEN - ETK-I taken after rally victory")

      -- Show fullscreen scene: The theft
      showScene("etki_theft")

      -- Ghost's follow-up messages about the theft (chat after scene closes)
      local chat = getChat()
      if chat then
        chat.queueDialogue("ghost", {
          { speaker = "ghost", text = "..." },
          { speaker = "ghost", text = {es = "Revisa tu garaje. Ahora.", en = "Check your garage. Now."} },
        }, 5000)

        chat.queueDialogue("ghost", {
          { speaker = "ghost", text = {es = "Lo sé.", en = "I know."} },
          { speaker = "ghost", text = {es = "La puerta fue forzada. Trabajo limpio. Demasiado limpio.", en = "The door was forced. Clean job. Too clean."} },
          { speaker = "ghost", text = {es = "Esto no fue aleatorio.", en = "This wasn't random."} },
        }, 10000)
      end
    end
  },

  -- ========================================================================
  -- PHASE 6: EL FONDO DEL POZO (Copa Covet)
  -- ========================================================================
  -- False evidence arc, partner disappears, humiliation

  -- GHOST GIVES MONEY FOR COVET PURCHASE
  {
    id = "ghost_covet_fund",
    phase = 6,
    priority = 30,
    unique = true,
    conditions = function()
      return state.storyFlags.car_stolen
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      -- Give player $5000 for Covet purchase
      local payment = extensions.career_modules_payment
      if payment then
        payment.pay(5000, { label = {es = "Ghost - Fondo para Covet", en = "Ghost - Covet Fund"} })
      end

      -- Ghost's message
      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Transferencia enviada. $5000.", en = "Transfer sent. $5000."} },
        { speaker = "ghost", text = {es = "Suficiente para un Covet de desguace.", en = "Enough for a junkyard Covet."} },
        { speaker = "ghost", text = {es = "Ve al concesionario. Compra lo que puedas permitirte.", en = "Go to the dealership. Buy what you can afford."} },
        { speaker = "ghost", text = {es = "La Copa Covet empieza pronto. Es tu única entrada de vuelta al circuito.", en = "The Covet Cup starts soon. It's your only way back into the circuit."} },
        { speaker = "ghost", text = {es = "No lo desperdicies.", en = "Don't waste it."} },
      }, 3000)

      state.storyFlags.covet_fund_received = true
      log("I", logTag, "Phase 6: Ghost sends $5000 for Covet purchase")
    end
  },

  {
    id = "covet_humiliation",
    phase = 6,
    priority = 25,
    unique = true,
    conditions = function()
      return state.storyFlags.covet_fund_received
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Deja de mirar el retrovisor buscando culpables, Miller.", en = "Stop looking in the rearview for culprits, Miller."} },
        { speaker = "ghost", text = {es = "Ahora mismo eres un don nadie en un coche de 80 caballos.", en = "Right now you're a nobody in an 80-horsepower car."} },
        { speaker = "ghost", text = {es = "Si no ganas esta copa, no habrá Big One, ni ETK-I, ni respuestas.", en = "If you don't win this cup, there will be no Big One, no ETK-I, no answers."} },
        { speaker = "ghost", text = {es = "Concéntrate en el Covet. Es un coche honesto, no como la gente con la que te juntas.", en = "Focus on the Covet. It's an honest car, not like the people you hang out with."} },
      }, 3000)

      state.storyFlags.covet_arc_started = true
      log("I", logTag, "Phase 6: Copa Covet arc begins - humiliation and rebuilding")
    end
  },

  -- FALSE EVIDENCE EVENT
  {
    id = "false_evidence_techie",
    phase = 6,
    priority = 20,
    unique = true,
    conditions = function()
      return state.storyFlags.covet_arc_started
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      local chosenPartner = state.storyFlags.chosen_partner or "rook"

      chat.queueDialogue("techie", {
        { speaker = "techie", text = {es = "Miller, he estado rastreando la señal del GPS que instalé en el ETK-I antes del rally.", en = "Miller, I've been tracking the GPS signal I installed in the ETK-I before the rally."} },
        { speaker = "techie", text = {es = "Se apagó justo después del golpe.", en = "It shut off right after the hit."} },
        { speaker = "techie", text = {es = "Pero he detectado actividad inusual en la cuenta de Shadow vinculada a " .. chosenPartner .. ".", en = "But I've detected unusual activity in Shadow's account linked to " .. chosenPartner .. "."} },
        { speaker = "techie", text = {es = "Alguien ha recibido un pago grande en cripto. No quiero sacar conclusiones, pero los datos son... feos.", en = "Someone received a large crypto payment. I don't want to jump to conclusions, but the data is... ugly."} },
      }, 3500)

      -- Send fake evidence document
      local messages = extensions.career_modules_mysummerMessages
      if messages then
        messages.sendMessage("fake_transaction", {
          subject = {es = "Análisis de Blockchain - CONFIDENCIAL", en = "Blockchain Analysis - CONFIDENTIAL"},
          body = {
            es = "TRANSACCIÓN DETECTADA:\n\nOrigen: Shadow_Markets_0x8f42a\nDestino: " .. chosenPartner .. "_wallet_0x71b9c\nMonto: $45,000 USD (BTC)\nFecha: " .. os.date("%Y-%m-%d") .. "\n\nNOTA: Coincide con fecha del robo del ETK-I.\n\n- Techie",
            en = "TRANSACTION DETECTED:\n\nSource: Shadow_Markets_0x8f42a\nDestination: " .. chosenPartner .. "_wallet_0x71b9c\nAmount: $45,000 USD (BTC)\nDate: " .. os.date("%Y-%m-%d") .. "\n\nNOTE: Matches date of ETK-I theft.\n\n- Techie"
          }
        })
      end

      state.storyFlags.false_evidence_received = true
      state.storyFlags.believes_partner_traitor = true
      log("I", logTag, "Phase 6: FALSE EVIDENCE delivered - player believes partner betrayed them")
    end
  },

  -- PARTNER DISAPPEARS
  {
    id = "partner_disappears",
    phase = 6,
    priority = 15,
    unique = true,
    conditions = function()
      return state.storyFlags.false_evidence_received
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      local chosenPartner = state.storyFlags.chosen_partner or "rook"
      local otherPartner = (chosenPartner == "rook") and "nova" or "rook"

      -- Disable chat for chosen partner (they "disappeared")
      if chat.disableContact then
        chat.disableContact(chosenPartner)
      end

      -- Other partner mocks or pities
      if chosenPartner == "rook" then
        chat.queueDialogue("nova", {
          { speaker = "nova", text = {es = "Vaya, vaya.", en = "Well, well."} },
          { speaker = "nova", text = {es = "El caballero andante te dejó tirado en la cuneta, ¿eh?", en = "The knight in shining armor left you stranded, huh?"} },
          { speaker = "nova", text = {es = "Te dije que Rook haría cualquier cosa por 'proteger' su visión del mundo.", en = "I told you Rook would do anything to 'protect' his worldview."} },
          { speaker = "nova", text = {es = "Espero que ese Covet sea cómodo, porque es lo único que vas a conducir en mucho tiempo.", en = "I hope that Covet is comfortable, because it's all you'll be driving for a long time."} },
        }, 3000)
      else
        chat.queueDialogue("rook", {
          { speaker = "rook", text = {es = "Te lo advertí, Miller.", en = "I warned you, Miller."} },
          { speaker = "rook", text = {es = "La ambición de Nova no tiene fondo.", en = "Nova's ambition has no bottom."} },
          { speaker = "rook", text = {es = "Te usó para ganar el rally y luego te vendió a Shadow para saldar sus deudas.", en = "She used you to win the rally and then sold you to Shadow to settle her debts."} },
          { speaker = "rook", text = {es = "Lo siento por el coche del abuelo... no merecía terminar así.", en = "I'm sorry about grandfather's car... it didn't deserve to end like this."} },
        }, 3000)
      end

      state.storyFlags.partner_disappeared = true
      log("I", logTag, "Phase 6: Chosen partner disappeared - other partner reacts")
    end
  },

  -- SHADOW TAUNTS
  {
    id = "shadow_taunts_covet",
    phase = 6,
    priority = 10,
    unique = true,
    conditions = function()
      return state.storyFlags.partner_disappeared
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      local chosenPartner = state.storyFlags.chosen_partner or "rook"

      chat.queueDialogue("shadow", {
        { speaker = "shadow", text = {es = "Miller, felicidades por el progreso con esa cafetera japonesa.", en = "Miller, congratulations on the progress with that Japanese coffee maker."} },
        { speaker = "shadow", text = {es = "Me sorprende tu resiliencia.", en = "Your resilience surprises me."} },
        { speaker = "shadow", text = {es = chosenPartner .. " me dio algo muy valioso a cambio de tu 'libertad' de deudas.", en = chosenPartner .. " gave me something very valuable in exchange for your 'freedom' from debts."} },
        { speaker = "shadow", text = {es = "Parece que no puedes estar lejos del asfalto.", en = "Seems you can't stay away from the asphalt."} },
        { speaker = "shadow", text = {es = "Si ganas esto, te veré en los circuitos oficiales.", en = "If you win this, I'll see you at the official circuits."} },
        { speaker = "shadow", text = {es = "Tengo un mensaje para ti de parte de tu 'amigo/a': 'No es personal, es supervivencia'.", en = "I have a message for you from your 'friend': 'It's not personal, it's survival'."} },
      }, 4000)

      state.storyFlags.shadow_taunted = true
      log("I", logTag, "Phase 6: Shadow taunts about the 'deal'")
    end
  },

  -- ========================================================================
  -- PHASE 7: EL RASTRO DEL HIERRO (Clasificatorias)
  -- ========================================================================
  -- Finding ETK-I parts, anonymous hints, truth reveal, Shadow challenge

  {
    id = "etki_parts_on_rivals",
    phase = 7,
    priority = 5,
    unique = true,
    conditions = function()
      -- Phase condition removed: race sequencing guarantees correct phase
      return true
    end,
    onTrigger = function()
      local monologues = extensions.career_modules_mysummerMonologues
      if monologues and monologues.onNarrativeEvent then
        monologues.onNarrativeEvent("etki_parts_sighted")
      end

      local chat = getChat()
      if chat then
        chat.queueDialogue("techie", {
          { speaker = "techie", text = {es = "Miller, he analizado la transacción.", en = "Miller, I analyzed the transaction."} },
          { speaker = "techie", text = {es = "El dinero salió de una cuenta de Shadow y terminó en un fondo a nombre de tu pareja.", en = "The money came from a Shadow account and ended up in a fund under your partner's name."} },
          { speaker = "techie", text = {es = "No hay duda. Lo vendieron por piezas para que fuera imposible de rastrear.", en = "No doubt. They sold it in parts to make it untraceable."} },
          { speaker = "techie", text = {es = "Lo siento, de verdad.", en = "I'm truly sorry."} },
        }, 3000)
      end

      state.storyFlags.parts_sighted = true
      log("I", logTag, "Phase 7: ETK-I parts spotted on rival cars")
    end
  },

  -- ANONYMOUS HINTS
  {
    id = "anonymous_shadow_hints",
    phase = 7,
    priority = 4,
    unique = true,
    conditions = function()
      return state.storyFlags.parts_sighted
    end,
    onTrigger = function()
      local chat = getChat()
      if chat then
        chat.queueDialogue("unknown", {
          { speaker = "unknown", text = {es = "No todo lo que brilla es oro, ni todo lo que Techie ve en su pantalla es verdad.", en = "Not all that glitters is gold, nor is everything Techie sees on his screen true."} },
          { speaker = "unknown", text = {es = "Shadow es un maestro de los espejismos digitales.", en = "Shadow is a master of digital mirages."} },
          { speaker = "unknown", text = {es = "Si quieres encontrar tu coche, busca en el contenedor 402 del puerto, no en las cuentas bancarias de quien te quiere.", en = "If you want to find your car, look in container 402 at the port, not in the bank accounts of who loves you."} },
        }, 3000)
      end

      state.storyFlags.received_anonymous_hints = true
      log("I", logTag, "Phase 7: Anonymous hints about Shadow's manipulation")
    end
  },

  -- TRUTH REVEAL - PARTNER RETURNS
  {
    id = "partner_truth_reveal",
    phase = 7,
    priority = 3,
    unique = true,
    conditions = function()
      return state.storyFlags.received_anonymous_hints
    end,
    onTrigger = function()
      local chat = getChat()
      local chosenPartner = state.storyFlags.chosen_partner or "rook"

      -- Re-enable chosen partner chat
      if chat and chat.enableContact then
        chat.enableContact(chosenPartner)
      end

      -- Show fullscreen scene: Partner returns + Shadow challenge
      showScene("partner_truth_reveal")

      state.storyFlags.truth_revealed = true
      state.storyFlags.knows_shadow_is_traitor = true
      state.storyFlags.believes_partner_traitor = false
      log("I", logTag, "Phase 7: TRUTH REVEALED (fullscreen scene) - Partner was innocent")
    end
  },

  -- SHADOW CHALLENGE
  {
    id = "shadow_challenge_duelo",
    phase = 7,
    priority = 2,
    unique = true,
    conditions = function()
      return state.storyFlags.truth_revealed
    end,
    onTrigger = function()
      -- Shadow challenge is now part of the partner_truth_reveal scene
      -- This event just sets the flag
      state.storyFlags.shadow_challenge_issued = true
      log("I", logTag, "Phase 7: Shadow challenge issued (via truth reveal scene)")
    end
  },

  -- ========================================================================
  -- PHASE 8: RECLAMACIÓN Y GLORIA (The Big One)
  -- ========================================================================
  -- Duelo with Shadow, car recovery, The Big One vs Viper, epilogue

  {
    id = "duelo_pre_race",
    phase = 8,
    priority = 1,
    unique = true,
    conditions = function()
      return state.storyFlags.shadow_challenge_issued
    end,
    onTrigger = function()
      -- Show fullscreen scene: Shadow taunts before duel
      showScene("shadow_duel")

      state.storyFlags.duelo_started = true
      log("I", logTag, "Phase 8: Duelo with Shadow begins (fullscreen scene)")
    end
  },

  -- CAR RECOVERY (after Duelo win)
  {
    id = "etki_recovered",
    phase = 8,
    priority = 1,
    unique = true,
    conditions = function()
      -- TODO: Check if Duelo race was won
      return state.storyFlags.duelo_started
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      local chosenPartner = state.storyFlags.chosen_partner or "rook"

      chat.queueDialogue(chosenPartner, {
        { speaker = chosenPartner, text = {es = "Lo hiciste, Miller.", en = "You did it, Miller."}, emotion = "happy" },
        { speaker = chosenPartner, text = {es = "Aquí están las llaves. El coche es tuyo otra vez.", en = "Here are the keys. The car is yours again."}, emotion = "content" },
        { speaker = chosenPartner, text = {es = "Ahora... termina lo que empezaste. The Big One te espera.", en = "Now... finish what you started. The Big One awaits."}, emotion = "standard" },
      }, 3000)

      state.storyFlags.car_recovered = true
      state.storyFlags.etki_location = "player_garage"
      log("I", logTag, "Phase 8: ETK-I RECOVERED - Ready for The Big One")
    end
  },

  -- VIPER RECOGNITION
  {
    id = "viper_pre_big_one",
    phase = 8,
    priority = 1,
    unique = true,
    conditions = function()
      return state.storyFlags.car_recovered
    end,
    onTrigger = function()
      local chat = getChat()
      if chat then
        chat.unlockContact("viper")
      end

      -- Show fullscreen scene: Viper recognition
      showScene("viper_recognition")

      state.storyFlags.viper_contacted = true
      state.storyFlags.ready_for_big_one = true
      log("I", logTag, "Phase 8: Viper recognition (fullscreen scene)")
    end
  },

  -- THE BIG ONE RACE
  {
    id = "the_big_one_viper_race",
    phase = 8,
    priority = 1,
    unique = true,
    conditions = function()
      return state.storyFlags.ready_for_big_one
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      local chosenPartner = state.storyFlags.chosen_partner or "rook"

      chat.queueDialogue("viper", {
        { speaker = "viper", text = {es = "¡Muéstrame esa rabia, Miller!", en = "Show me that rage, Miller!"} },
        { speaker = "viper", text = {es = "El ETK-I fue diseñado para este momento.", en = "The ETK-I was designed for this moment."} },
        { speaker = "viper", text = {es = "Tu abuelo nunca tuvo el valor de meter la quinta marcha en esta recta.", en = "Your grandfather never had the courage to shift into fifth on this straight."} },
        { speaker = "viper", text = {es = "¡No frenes ahora! ¡Si quieres respeto, tienes que quitármelo de las manos!", en = "Don't brake now! If you want respect, you have to take it from my hands!"} },
      }, 2500)

      chat.queueDialogue(chosenPartner, {
        { speaker = chosenPartner, text = {es = "¡Vamos, Miller!", en = "Let's go, Miller!"}, emotion = "happy" },
        { speaker = chosenPartner, text = {es = "Todo este camino... el robo, la traición, el Covet... todo era para llegar aquí.", en = "This whole journey... the theft, the betrayal, the Covet... it was all to get here."}, emotion = "standard" },
        { speaker = chosenPartner, text = {es = "¡Demuéstrales a todos que tenías razón!", en = "Show everyone you were right!"}, emotion = "happy" },
      }, 6000)

      state.storyFlags.big_one_started = true
      log("I", logTag, "Phase 8: THE BIG ONE - Final race against Viper")
    end
  },

  -- EPILOGUE
  {
    id = "epilogue_garage_peace",
    phase = 8,
    priority = 1,
    unique = true,
    conditions = function()
      -- TODO: Check if The Big One was completed
      return state.storyFlags.big_one_started
    end,
    onTrigger = function()
      -- Show fullscreen epilogue scene: Viper + Muscle
      showScene("epilogue_garage_peace")

      state.storyFlags.story_complete = true
      log("I", logTag, "Phase 8: EPILOGUE (fullscreen scene) - The garage is finally at peace")
    end
  },
}

-- ============================================================================
-- EVENT PROCESSING
-- ============================================================================

local function getCurrentPhase()
  if not career_branches or not career_modules_playerAttributes then
    return 0
  end

  local skillId = "mysummer-streetracing"
  local totalXP = career_modules_playerAttributes.getAttributeValue(skillId) or 0
  local level = career_branches.calcBranchLevelFromValue(totalXP, skillId)

  -- Branch levels are 1-indexed (level 1 = phase 0), convert to 0-indexed narrative phases
  return math.max(0, (level or 1) - 1)
end

local function canTriggerEvent(event)
  -- Check if already triggered (for unique events)
  if event.unique and state.triggeredEvents[event.id] then
    log("D", logTag, "Event " .. event.id .. " already triggered")
    return false
  end

  -- Check phase requirement (DISABLED - races can be done in any order)
  -- local currentPhase = getCurrentPhase()
  -- if currentPhase < event.phase then
  --   return false
  -- end

  -- Check custom conditions
  if event.conditions and not event.conditions() then
    log("D", logTag, "Event " .. event.id .. " conditions not met")
    return false
  end

  return true
end

local function triggerEvent(event)
  log("I", logTag, "Triggering narrative event: " .. event.id)

  -- Mark as triggered BEFORE executing (prevents re-fire during same frame)
  state.triggeredEvents[event.id] = true

  -- Execute the event in pcall - revert triggered flag if onTrigger crashes
  if event.onTrigger then
    local ok, err = pcall(event.onTrigger)
    if not ok then
      log("E", logTag, "Event '" .. event.id .. "' onTrigger CRASHED: " .. tostring(err))
      log("E", logTag, "Reverting triggered flag so event can re-fire next time")
      state.triggeredEvents[event.id] = nil
      return
    end
  end

  -- Notify monologues system
  local monologues = extensions.career_modules_mysummerMonologues
  if monologues and monologues.onNarrativeEvent then
    monologues.onNarrativeEvent(event.id)
  end

  -- Notify calls system
  local calls = extensions.career_modules_mysummerCalls
  if calls and calls.onNarrativeEvent then
    calls.onNarrativeEvent(event.id)
  end

  -- Save state
  saveState()
end

-- Event queue with cooldown system
local eventQueue = {}
local EVENT_COOLDOWN = 45  -- Seconds between events
local lastEventTime = 0

-- Event mapping tables - Maps trigger keys to actual event IDs
-- Format: ["phase{N}_race{N}_{type}"] = "actual_event_id"
-- Where:
--   - phase = chapter/phase number (0-8)
--   - race = sequential race number within that phase (1, 2, 3...)
--   - type = selected/start/mid/end
-- Keys must match event definitions in mysummerMonologues.lua, mysummerCalls.lua, mysummerChat.lua
local raceEventMap = {
  -- Prologue (Phase 0) - Events trigger by order, not specific race
  -- Race 1: "El Primer Pulso"
  ["phase0_race1_start"] = "phase0_race1",        -- Monologue: "El abuelo preparaba estos motores..."
  ["phase0_race1_end"] = "phase0_race1_post",     -- SMS: Ghost's first advice after race
  -- Note: ghost_race1_call + rook_nova_introduction fire via narrativeEventTriggerMap on this same key
  -- No mid event for race 1

  -- Race 2: "Sombras en el Retrovisor"
  ["phase0_race2_selected"] = "phase0_race2_pre", -- Call: Rook/Nova intro on selection
  ["phase0_race2_mid"] = "phase0_race2",          -- Monologue: "Nova conduce como si no tuviera nada que perder..."
  ["phase0_race2_end"] = "phase0_race2_post",     -- SMS: After race
  -- No start event for race 2

  -- Race 3: "La Huella de Viper"
  ["phase0_race3_start"] = "phase0_race3",        -- Monologue: "Viper... Ghost no deja de mencionar ese nombre..."
  ["phase0_race3_mid"] = "phase0_race3_intercept", -- Walkie: Ghost intercepts during race
  ["phase0_race3_end"] = "phase0_race3_post",     -- SMS: Mission unlocked


  -- Phase 1: ORIGINS - "La Danza de los Tres"
  -- Race 1: "La Danza de los Tres"
  ["phase1_race1_mid"] = "phase1_race1_during",   -- Call: Nova vs Rook philosophy debate during race
  ["phase1_race1_end"] = "phase1_race1",          -- SMS: Rook praises Miller (with choices)
  -- No start event for race 1

  -- Race 2: "El Ritmo del Asfalto"
  ["phase1_race2_start"] = "phase1_race2",        -- Monologue: "Hoy es el turno de Rook..."
  ["phase1_race2_mid"] = "phase1_race2_during",   -- Call: Rook vs Nova technical debate
  ["phase1_race2_end"] = "phase1_race2",          -- SMS: Nova complains about Rook

  -- Race 3: "La Grieta"
  ["phase1_race3_selected"] = "phase1_race3_pre", -- Call: Ghost warns about Rook/Nova rift
  ["phase1_race3_mid"] = "phase1_race3",          -- Monologue: "Ghost tiene razón..."
  ["phase1_race3_end"] = "phase1_race3",          -- SMS: Rook introduces Techie

  -- Phase 2: THE SPLIT
  -- Race 1: "Punto de Fricción"
  ["phase2_race1_mid"] = "phase2_race1_during",   -- Call: Nova vs Rook argue during race
  ["phase2_race1_end"] = "phase2_race1",          -- SMS: Nova says Rook is suffocating (with choices)
  -- No start event for race 1

  -- Race 2: "El Peso del Acero"
  ["phase2_race2_mid"] = "phase2_race2_during",   -- Call: Ghost introduces Muscle during race
  ["phase2_race2_end"] = "phase2_race2",          -- SMS: Ghost says Muscle liked you
  -- No start event for race 2

  -- Race 3: "Ultimátum"
  ["phase2_race3_mid"] = "phase2_race3_during",   -- Call: Rook begs Miller to reason with Nova
  ["phase2_race3_end"] = "phase2_race3",          -- Monologue: "El equipo se rompe..."

  -- Phase 3: THE CRISIS
  -- Race 1: "Tensión de Materiales"
  ["phase3_race1_mid"] = "phase3_race1_during",   -- Call: Nova vs Rook teaching styles clash
  ["phase3_race1_end"] = "phase3_race1",          -- Monologue: "Discuten por el walkie-talkie..."
  -- No start event for race 1

  -- Race 2: "El Murmullo de Viper"
  ["phase3_race2_mid"] = "phase3_race2_during",   -- Call: Ghost explains Viper/grandfather
  ["phase3_race2_end"] = "phase3_race2",          -- Monologue: "Ghost siempre habla de ellos..."
  -- No start event for race 2

  -- Race 3: "La Propuesta de Nova"
  ["phase3_race3_mid"] = "phase3_race3_during",   -- Call: Nova proposes leaving, Rook interrupts
  ["phase3_race3_end"] = "phase3_race3",          -- SMS: Nova says don't tell Rook about Shadow

  -- Phase 4: THE SPLIT (Ruptura Final)
  -- Race 1: "Fallo de Encendido"
  ["phase4_race1_mid"] = "phase4_race1_during",   -- Call: Nova's turbo fails, Rook confronts
  ["phase4_race1_end"] = "phase4_race1",          -- Monologue: "El coche de Nova olía a metal quemado..."
  -- No start event for race 1

  -- Race 2: "El Interrogatorio"
  ["phase4_race2_mid"] = "phase4_race2_during",   -- Call: Rook questions Miller about Shadow
  ["phase4_race2_end"] = "phase4_race2",          -- Monologue: "Rook está desesperado..."
  -- No start event for race 2

  -- Race 3: "La Explosión"
  ["phase4_race3_mid"] = "phase4_race3_explosion", -- Call: Public breakup during race
  ["phase4_race3_end"] = "phase4_race3",          -- SMS: Rook says it's over

  -- Phase 5: RALLY REGIONAL (Polvo y Traición)
  ["phase5_race1_mid"] = "phase5_rally1_during",  -- Call: Ghost marvels at ETK-I
  ["phase5_race1_end"] = "phase5_rally1",         -- Monologue: After first rally
  ["phase5_race2_mid"] = "phase5_rally2_during",  -- Call: Nova/Rook fight over ETK-I future
  ["phase5_race2_end"] = "phase5_rally2",         -- Monologue: After second rally
  ["phase5_race4_end"] = "phase5_rally4_victory", -- Monologue: Victory and preparing for Big One

  -- Phase 6: EL FONDO DEL POZO (Copa Covet)
  ["phase6_race1_start"] = "phase6_covet1",       -- Monologue: From Rally ETK-I to junkyard Covet
  ["phase6_race1_end"] = "phase6_covet1_post",    -- Call: Ghost says focus on Covet
  ["phase6_race2_mid"] = "phase6_covet2_intercept", -- Call: Techie reveals data about betrayal
  ["phase6_race4_mid"] = "phase6_covet4_during",  -- Call: Shadow taunts about the deal
  ["phase6_race4_end"] = "phase6_covet4_victory", -- Monologue: Won pass but lost ETK-I

  -- Phase 7: EL RASTRO DEL HIERRO (Clasificatorias)
  ["phase7_race1_start"] = "phase7_clasif1_parts", -- Monologue: Spotting ETK-I parts being sold
  ["phase7_race1_end"] = "phase7_clasif1_post",   -- Call: Techie confirms transaction evidence
  ["phase7_race2_end"] = "phase7_clasif2",        -- SMS: Anonymous message doubts
  ["phase7_race3_mid"] = "phase7_clasif3_intercept", -- Call: Shadow threatens during race
  ["phase7_race3_end"] = "phase7_clasif3_threat", -- Monologue: Shadow's threat reflection

  -- Phase 8: RECLAMACIÓN Y GLORIA (The Big One)
  ["phase8_race1_mid"] = "phase8_duelo_during",   -- Call: Shadow taunts during duel
  ["phase8_race1_end"] = "phase8_duelo_mid",      -- Monologue: Reflection after duel
  ["phase8_race2_mid"] = "phase8_bigone_during",  -- Call: Viper + Partner cheer during Big One
  ["phase8_race2_end"] = "phase8_bigone_finalvuelta", -- Monologue: Final lap reflection + epilogue
}

-- Maps contact work IDs to narrative events
-- NOTE: We use "contact_work" instead of "mission" to avoid confusion with BeamNG's native missions (which are races)
local contactWorkEventMap = {
  ["ghost_legacy_mechanic"] = "ghost_legacy_complete",
  ["techie_hardware_souls"] = "techie_contact_work_complete",
  ["muscle_old_wounds"] = "muscle_contact_work_complete",
  ["shadow_black_market_threshold"] = "shadow_contact_work_complete",
  ["ghost_shadow_debt_payment"] = "debt_paid",
}

-- Maps race trigger keys to narrativeEvent IDs for story logic (flags, contacts, scenes)
-- These fire ALONGSIDE content module dispatch (monologues/calls/SMS)
-- Array values are processed in order, enabling flag chaining (earlier events set flags for later ones)
local narrativeEventTriggerMap = {
  -- Phase 0: EL PESO DEL SILENCIO
  ["phase0_race1_end"] = {"ghost_race1_call"},                       -- Ghost call + Rook/Nova intro after Race 1
  ["phase0_race3_end"] = {"ghost_legacy_mechanic_mission_gate"},     -- Mission gate after Race 3

  -- Phase 1: ORIGINS
  ["phase1_race1_end"] = {"phase1_triangle_begins"},                 -- Philosophy clash begins
  ["phase1_race2_end"] = {"nova_pushes_aggression"},                 -- Nova pushes aggression, sets flag for techie gate
  ["phase1_race3_end"] = {"techie_mission_gate"},                    -- Techie contact unlocked

  -- Phase 2: THE SPLIT
  ["phase2_race1_end"] = {"tension_escalates"},                      -- Tension visible
  ["phase2_race2_end"] = {"muscle_observes_race"},                   -- Muscle appears
  ["phase2_race3_end"] = {"rook_nova_ultimatum", "muscle_mission_gate"}, -- Ultimatum → mission gate chain

  -- Phase 3: THE CRISIS
  ["phase3_race1_end"] = {"player_becomes_mediator"},                -- Player becomes tiebreaker
  ["phase3_race2_end"] = {"ghost_viper_philosophy"},                 -- Ghost explains Viper dynamic
  ["phase3_race3_end"] = {"nova_private_proposal", "shadow_mission_gate"}, -- Nova proposes → Shadow unlocked

  -- Phase 4: THE SPLIT (Final Rupture)
  ["phase4_race1_end"] = {"nova_turbo_failure"},                     -- Shadow parts cause turbo failure
  ["phase4_race2_end"] = {"rook_interrogation"},                     -- Rook discovers Shadow connection
  ["phase4_race3_end"] = {"public_breakup", "debt_mission_gate"},    -- Public breakup → debt mission

  -- Phase 5: POLVO Y TRAICIÓN (Rally)
  ["phase5_race1_end"] = {"rally_etki_sounds_perfect"},              -- ETK-I in its element
  ["phase5_race2_end"] = {"rally_nova_rook_money_talk"},             -- Nova/Rook fight over future
  ["phase5_race3_start"] = {"romance_choice_trigger"},               -- Romance choice before Race 3
  ["phase5_race4_end"] = {"etki_stolen_rally"},                      -- Car theft after Rally

  -- Phase 6: EL FONDO DEL POZO (Copa Covet)
  ["phase6_race1_start"] = {"ghost_covet_fund"},                     -- Ghost sends $5000 for Covet
  ["phase6_race1_end"] = {"covet_humiliation"},                      -- Ghost tough love speech
  ["phase6_race2_end"] = {"false_evidence_techie"},                  -- Techie delivers false evidence
  ["phase6_race3_end"] = {"partner_disappears"},                     -- Partner goes missing
  ["phase6_race4_end"] = {"shadow_taunts_covet"},                    -- Shadow taunts about the deal

  -- Phase 7: EL RASTRO DEL HIERRO (Clasificatorias)
  ["phase7_race1_end"] = {"etki_parts_on_rivals"},                   -- ETK-I parts on rival cars
  ["phase7_race2_end"] = {"anonymous_shadow_hints"},                 -- Anonymous hints about Shadow
  ["phase7_race3_end"] = {"partner_truth_reveal", "shadow_challenge_duelo"}, -- Truth + Shadow challenge

  -- Phase 8: RECLAMACIÓN Y GLORIA (The Big One)
  ["phase8_race1_start"] = {"duelo_pre_race"},                       -- Shadow duel scene
  ["phase8_race1_end"] = {"etki_recovered", "viper_pre_big_one"},    -- ETK-I recovered → Viper recognition
  ["phase8_race2_end"] = {"the_big_one_viper_race", "epilogue_garage_peace"}, -- Big One → Epilogue
}

local function queueEvent(eventId, delay)
  delay = delay or 0
  table.insert(eventQueue, {
    eventId = eventId,
    triggerTime = os.time() + delay
  })
  log("I", logTag, string.format("Queued event '%s' with %ds delay", eventId, delay))
end

local function processEventQueue()
  if #eventQueue == 0 then return end

  local now = os.time()

  -- Check cooldown
  if now - lastEventTime < EVENT_COOLDOWN then
    return
  end

  -- Find next ready event
  for i, queuedEvent in ipairs(eventQueue) do
    if now >= queuedEvent.triggerTime then
      -- Translate event key to actual event ID using maps
      local actualEventId = queuedEvent.eventId

      -- Check if this is a race event key that needs mapping
      if raceEventMap[queuedEvent.eventId] then
        actualEventId = raceEventMap[queuedEvent.eventId]
        log("D", logTag, string.format("Mapped event key '%s' -> '%s'", queuedEvent.eventId, actualEventId))
      elseif contactWorkEventMap[queuedEvent.eventId] then
        actualEventId = contactWorkEventMap[queuedEvent.eventId]
        log("D", logTag, string.format("Mapped contact work key '%s' -> '%s'", queuedEvent.eventId, actualEventId))
      end

      -- STEP 1: Fire narrativeEvents via narrativeEventTriggerMap
      -- Maps the ORIGINAL trigger key to narrativeEvent IDs for story logic (flags, contacts, scenes)
      -- Array values are processed in order so earlier events can set flags for later ones
      local narrativeEventTriggered = false
      local neIds = narrativeEventTriggerMap[queuedEvent.eventId]
      if neIds then
        for _, neId in ipairs(neIds) do
          for _, event in ipairs(narrativeEvents) do
            if event.id == neId then
              if canTriggerEvent(event) then
                triggerEvent(event)
                narrativeEventTriggered = true
                log("I", logTag, string.format("  → NarrativeEvent triggered via map: '%s' (from key '%s')", neId, queuedEvent.eventId))
              else
                log("D", logTag, string.format("  → NarrativeEvent '%s' conditions not met or already triggered", neId))
              end
              break
            end
          end
        end
      end

      -- Also check direct ID match (for events queued by exact narrativeEvent ID, e.g. inherited_garage)
      if not narrativeEventTriggered then
        for _, event in ipairs(narrativeEvents) do
          if event.id == actualEventId then
            if canTriggerEvent(event) then
              triggerEvent(event)
              narrativeEventTriggered = true
              log("I", logTag, string.format("  → NarrativeEvent onTrigger fired for '%s' (direct ID match)", actualEventId))
            else
              log("D", logTag, string.format("  → NarrativeEvent '%s' exists but canTrigger=false", actualEventId))
            end
            break
          end
        end
      end

      -- STEP 2: Trigger through module handlers (monologues, calls, chat)
      -- Each module may have different content for the same event
      local monologueTriggered = false
      local callTriggered = false
      local smsTriggered = false

      -- Try monologues (access only via extensions table)
      if extensions.career_modules_mysummerMonologues and
         extensions.career_modules_mysummerMonologues.onNarrativeEvent then
        local success, result = pcall(extensions.career_modules_mysummerMonologues.onNarrativeEvent, actualEventId)
        if success then
          monologueTriggered = result
          if monologueTriggered then
            log("I", logTag, string.format("  → Monologue triggered for '%s'", actualEventId))
          else
            log("D", logTag, string.format("  → Monologue returned false for '%s'", actualEventId))
          end
        else
          log("E", logTag, string.format("  → Monologue error for '%s': %s", actualEventId, tostring(result)))
        end
      end

      -- Try calls
      if extensions.career_modules_mysummerCalls and
         extensions.career_modules_mysummerCalls.onNarrativeEvent then
        local success, result = pcall(extensions.career_modules_mysummerCalls.onNarrativeEvent, actualEventId)
        if success then
          callTriggered = result
          if callTriggered then
            log("I", logTag, string.format("  → Call triggered for '%s'", actualEventId))
          else
            log("D", logTag, string.format("  → Call returned false for '%s'", actualEventId))
          end
        else
          log("E", logTag, string.format("  → Call error for '%s': %s", actualEventId, tostring(result)))
        end
      end

      -- Try chat/SMS
      if extensions.career_modules_mysummerChat and
         extensions.career_modules_mysummerChat.onNarrativeEvent then
        local success, result = pcall(extensions.career_modules_mysummerChat.onNarrativeEvent, actualEventId)
        if success then
          smsTriggered = result
          if smsTriggered then
            log("I", logTag, string.format("  → SMS triggered for '%s'", actualEventId))
          else
            log("D", logTag, string.format("  → SMS returned false for '%s'", actualEventId))
          end
        else
          log("E", logTag, string.format("  → SMS error for '%s': %s", actualEventId, tostring(result)))
        end
      end

      local anyTriggered = narrativeEventTriggered or monologueTriggered or callTriggered or smsTriggered

      if anyTriggered then
        log("I", logTag, string.format("Successfully triggered narrative event: %s (from key: %s) [N:%s M:%s C:%s S:%s]",
          actualEventId, queuedEvent.eventId,
          narrativeEventTriggered and "Y" or "N",
          monologueTriggered and "Y" or "N",
          callTriggered and "Y" or "N",
          smsTriggered and "Y" or "N"))
        lastEventTime = now
        table.remove(eventQueue, i)
        return
      else
        -- Event not found in any module, remove from queue
        log("W", logTag, string.format("Event '%s' (mapped from '%s') not found in any handler",
          actualEventId, queuedEvent.eventId))
        table.remove(eventQueue, i)
        return
      end
    end
  end
end

local function checkEvents()
  -- DEPRECATED: This function no longer auto-triggers events
  -- Events are now triggered manually via queueEvent() from race/mission completion
  processEventQueue()
end

-- Called when player completes a race (BeamNG calls these "missions" internally)
-- NOTE: This function is no longer needed as events are triggered by mysummerStoryRaces
-- based on race count, not race ID. Kept for backwards compatibility.
local function onRaceCompleted(raceId)
  if not career_career or not career_career.isActive() then
    return
  end

  log("D", logTag, "Race completed (legacy call): " .. tostring(raceId))
  -- Events are now triggered by mysummerStoryRaces using queueEvent() directly
end

-- Called when player completes a contact work (delivery, surveillance, etc.)
-- NOTE: We use "contact_work" instead of "mission" to avoid confusion with BeamNG races
local function onContactWorkCompleted(contactWorkId)
  if not career_career or not career_career.isActive() then
    return
  end

  log("I", logTag, "Contact work completed: " .. tostring(contactWorkId))

  -- Check if this contact work triggers a narrative event
  local eventId = contactWorkEventMap[contactWorkId]
  if eventId then
    queueEvent(eventId, 5)
    log("I", logTag, string.format("Contact work '%s' will trigger event '%s' in 5s", contactWorkId, eventId))
  end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

local function getStoryFlag(flag)
  return state.storyFlags[flag]
end

local function setStoryFlag(flag, value)
  state.storyFlags[flag] = value
  saveState()
end

local function isEventTriggered(eventId)
  return state.triggeredEvents[eventId] == true
end

local function getTraitor()
  return state.storyFlags.traitor
end

local function getTraitorMotivation()
  return state.storyFlags.traitor_motivation
end

local function getNarrativeProgress()
  return {
    phase = getCurrentPhase(),
    triggeredEvents = deepcopy(state.triggeredEvents),
    storyFlags = deepcopy(state.storyFlags),
  }
end

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================
--
-- Usage from BeamNG console:
--
-- List all events:
--   career_modules_mysummerNarrative.debugListEvents()
--
-- Set narrative phase:
--   career_modules_mysummerNarrative.debugSetPhase(3)  -- Sets to Phase 3
--
-- Trigger specific event:
--   career_modules_mysummerNarrative.forceTriggerEvent("newspaper_found")
--
-- Set affinity value:
--   career_modules_mysummerNarrative.debugSetAffinity("rook_affinity", 50)
--   career_modules_mysummerNarrative.debugSetAffinity("nova_affinity", -20)
--
-- View all affinities:
--   dump(career_modules_mysummerNarrative.debugGetAffinities())
--
-- View progress:
--   dump(career_modules_mysummerNarrative.debugGetProgress())
--
-- Reset all narrative state:
--   career_modules_mysummerNarrative.debugReset()
--
-- ============================================================================

-- Utility: count table size
local function tableSize(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

-- Force trigger an event (for testing/debugging)
local function forceTriggerEvent(eventId)
  for _, event in ipairs(narrativeEvents) do
    if event.id == eventId then
      triggerEvent(event)
      return true
    end
  end
  return false
end

-- Set narrative phase by modifying XP (for testing)
local function debugSetPhase(targetPhase)
  if not career_modules_playerAttributes then
    log("W", logTag, "Cannot set phase: playerAttributes module not available")
    return false
  end

  -- Calculate required XP for target phase (updated for 8 phases)
  -- Phase progression: 0 (0), 1 (350), 2 (850), 3 (1600), 4 (2400), 5 (3300), 6 (4500), 7 (6000), 8 (7800)
  local xpThresholds = {
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

  local requiredXP = xpThresholds[targetPhase]
  if not requiredXP then
    log("W", logTag, "Invalid phase: " .. tostring(targetPhase) .. " (must be 0-8)")
    return false
  end

  -- Set XP attribute
  career_modules_playerAttributes.addAttributes({
    {attributeKey = "mysummer-streetracing", attributeValue = requiredXP, isProgression = true}
  })

  log("I", logTag, string.format("DEBUG: Set phase to %d (XP: %d)", targetPhase, requiredXP))
  return true
end

-- Set affinity/effect value (for testing)
local function debugSetAffinity(key, value)
  local chat = getChat()
  if not chat or not chat.setEffectValue then
    log("W", logTag, "Cannot set affinity: chat module not available or missing setEffectValue")
    return false
  end

  chat.setEffectValue(key, value)
  log("I", logTag, string.format("DEBUG: Set %s = %d", key, value))
  return true
end

-- Get all current affinities (for testing)
local function debugGetAffinities()
  local chat = getChat()
  if not chat or not chat.getEffectValue then
    log("W", logTag, "Cannot get affinities: chat module not available")
    return {}
  end

  -- Common affinity keys
  local affinityKeys = {
    "rook_affinity", "rook_confidence", "rook_trust",
    "nova_affinity", "nova_respect", "nova_trust",
    "ghost_affinity", "ghost_trust",
    "muscle_affinity", "muscle_trust",
    "ambition", "caution", "loyalty",
  }

  local affinities = {}
  for _, key in ipairs(affinityKeys) do
    affinities[key] = chat.getEffectValue(key) or 0
  end

  return affinities
end

-- List all events with their status (for testing)
local function debugListEvents()
  print("\n========== NARRATIVE EVENTS ==========")
  for _, event in ipairs(narrativeEvents) do
    local triggered = state.triggeredEvents[event.id] and "[X]" or "[ ]"
    local phaseStr = string.format("Phase %d", event.phase)
    local priorityStr = string.format("Pri: %d", event.priority or 0)
    print(string.format("  %s %-25s | %s | %s", triggered, event.id, phaseStr, priorityStr))
  end
  print(string.format("\nCurrent Phase: %d", getCurrentPhase()))
  print(string.format("Total Events: %d", #narrativeEvents))
  print(string.format("Triggered: %d", tableSize(state.triggeredEvents)))
  print("======================================\n")
end

-- Get count of triggered events
local function debugGetProgress()
  return {
    currentPhase = getCurrentPhase(),
    totalEvents = #narrativeEvents,
    triggeredEvents = tableSize(state.triggeredEvents),
    storyFlags = deepcopy(state.storyFlags),
  }
end

-- ============================================================================
-- UTILITY
-- ============================================================================

local function deepcopy(orig)
  local copy
  if type(orig) == 'table' then
    copy = {}
    for k, v in pairs(orig) do
      copy[k] = deepcopy(v)
    end
  else
    copy = orig
  end
  return copy
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
    state.triggeredEvents = data.triggeredEvents or {}
    state.storyFlags = data.storyFlags or {}
    state.currentPhase = data.currentPhase or 0

    log("I", logTag, "Loaded narrative state")
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
    triggeredEvents = state.triggeredEvents,
    storyFlags = state.storyFlags,
    currentPhase = getCurrentPhase(),
  }

  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("I", logTag, "Saved narrative state")
end

-- ============================================================================
-- RESET NARRATIVE EVENTS FOR RACE REPLAY
-- ============================================================================

-- Reset narrative content for a specific race (when player restarts/retries)
-- This allows events to be seen again when replaying the same race
function M.resetRaceNarrative(phase, raceCount)
  log("I", logTag, string.format("Resetting narrative for Phase %d, Race #%d", phase, raceCount))

  -- Build list of event keys for this race
  local eventKeys = {
    string.format("phase%d_race%d_selected", phase, raceCount),
    string.format("phase%d_race%d_start", phase, raceCount),
    string.format("phase%d_race%d_mid", phase, raceCount),
    string.format("phase%d_race%d_end", phase, raceCount),
  }

  -- Get the actual event IDs from the map and reset them
  local resetCount = 0
  for _, eventKey in ipairs(eventKeys) do
    local actualEventId = raceEventMap[eventKey]
    if actualEventId then
      -- Remove from triggered events
      state.triggeredEvents[actualEventId] = nil

      -- Reset in all narrative modules
      if extensions.career_modules_mysummerMonologues then
        -- Access the module's state to reset monologues
        local mono = extensions.career_modules_mysummerMonologues
        if mono.resetTriggered then
          mono.resetTriggered(actualEventId)
        end
      end

      if extensions.career_modules_mysummerCalls then
        local calls = extensions.career_modules_mysummerCalls
        if calls.resetTriggered then
          calls.resetTriggered(actualEventId)
        end
      end

      if extensions.career_modules_mysummerChat then
        local chat = extensions.career_modules_mysummerChat
        if chat.resetTriggered then
          chat.resetTriggered(actualEventId)
        end
      end

      resetCount = resetCount + 1
      log("D", logTag, string.format("  Reset event: %s -> %s", eventKey, actualEventId))
    end
  end

  log("I", logTag, string.format("Reset %d narrative events for this race", resetCount))
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Narrative system loaded")
end

local function onCareerActive()
  loadState()
  log("I", logTag, "Narrative system active, phase: " .. getCurrentPhase())

  -- Trigger initial event if this is a new career
  if not state.storyFlags.inherited_garage then
    state.storyFlags.career_started = true
    queueEvent("inherited_garage", 2)  -- Show grandfather's letter after 2 seconds
    log("I", logTag, "New career started, queuing initial event")
  end

  -- Re-queue missed gate events (e.g. if onTrigger crashed before pcall fix)
  local phase = getCurrentPhase()
  local missedGates = {
    { minPhase = 1, eventKey = "phase0_race3_end", gateId = "ghost_legacy_mechanic_mission_gate" },
  }
  for _, g in ipairs(missedGates) do
    if phase >= g.minPhase and not state.triggeredEvents[g.gateId] then
      queueEvent(g.eventKey, 3)
      log("W", logTag, "Re-queuing missed gate: " .. g.eventKey .. " (phase=" .. phase .. ", gate " .. g.gateId .. " not triggered)")
    end
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Check for new events to trigger
  checkEvents()
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- Story flags
M.getStoryFlag = getStoryFlag
M.setStoryFlag = setStoryFlag

-- Event queries
M.isEventTriggered = isEventTriggered
M.getTraitor = getTraitor
M.getTraitorMotivation = getTraitorMotivation
M.getNarrativeProgress = getNarrativeProgress

-- Testing/debug
M.forceTriggerEvent = forceTriggerEvent
M.checkEvents = checkEvents
M.getCurrentPhase = getCurrentPhase

-- Event triggering (called from other modules)
M.onRaceCompleted = onRaceCompleted
M.onContactWorkCompleted = onContactWorkCompleted
M.queueEvent = queueEvent

-- Debug commands (Sprint 1)
M.debugSetPhase = debugSetPhase
M.debugSetAffinity = debugSetAffinity
M.debugGetAffinities = debugGetAffinities
M.debugListEvents = debugListEvents
M.debugGetProgress = debugGetProgress

-- Debug: re-trigger a specific event key (e.g. "phase0_race3_end")
M.debugTrigger = function(eventKey)
  if not eventKey then
    log("I", logTag, "Usage: career_modules_mysummerNarrative.debugTrigger('phase0_race3_end')")
    return
  end
  -- Clear the gate so it can re-fire
  local neIds = narrativeEventTriggerMap[eventKey]
  if neIds then
    for _, neId in ipairs(neIds) do
      state.triggeredEvents[neId] = nil
    end
  end
  queueEvent(eventKey, 0)
  log("I", logTag, "Debug: queued '" .. eventKey .. "'")
end

-- Debug reset
M.debugReset = function()
  state.triggeredEvents = {}
  state.storyFlags = {}
  state.currentPhase = 0
  state.pendingEvents = {}
  state.lastEventCheck = 0
  saveState()
  log("I", logTag, "Narrative state reset")
end

-- Romance Choice Callback (called from UI)
M.onRomanceChoice = function(choice)
  if not choice or (choice ~= "rook" and choice ~= "nova") then
    log("E", logTag, "Invalid romance choice: " .. tostring(choice))
    return
  end

  -- Store the chosen partner
  state.storyFlags.chosen_partner = choice
  state.storyFlags.romance_choice_made = true

  log("I", logTag, "Romance choice made: " .. choice)

  -- Apply affinity effects
  local chat = getChat()
  if chat and chat.applyEffects then
    local effects = {}

    if choice == "rook" then
      -- Chose Rook
      effects.rook_affinity = 50
      effects.loyalty = 20
      effects.nova_respect = -50

      -- Queue Rook's happy response
      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Gracias, Miller. No te arrepentirás.", en = "Thank you, Miller. You won't regret this."}, emotion = "happy" },
        { speaker = "rook", text = {es = "Terminaremos el ETK-I juntos. Con honor.", en = "We'll finish the ETK-I together. With honor."}, emotion = "content" },
      }, 2000)

      -- Queue Nova's angry response
      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "Disfruta de tu chatarra, Miller.", en = "Enjoy your scrap, Miller."}, emotion = "angry" },
        { speaker = "nova", text = {es = "Te arrepentirás de esto.", en = "You'll regret this."}, emotion = "angry" },
      }, 6000)

    else
      -- Chose Nova
      effects.nova_affinity = 50
      effects.ambition = 20
      effects.rook_confidence = -50

      -- Queue Nova's happy response
      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "Sabía que tenías agallas, Miller.", en = "I knew you had guts, Miller."}, emotion = "happy" },
        { speaker = "nova", text = {es = "Vamos a llegar lejos. Juntos.", en = "We're going far. Together."}, emotion = "happy" },
      }, 2000)

      -- Queue Rook's sad response
      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Me duele más por el coche que por ti.", en = "It hurts more for the car than for you."}, emotion = "sad" },
        { speaker = "rook", text = {es = "Que os vaya bien.", en = "Good luck to you both."}, emotion = "sad" },
      }, 6000)
    end

    -- Apply all effects
    chat.applyEffects(effects)
  end

  -- Save state
  saveState()

  -- Trigger follow-up event (Rally Race 4 can now proceed)
  log("I", logTag, "Romance choice complete, rally can continue")
end

-- Lifecycle
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onUpdate = onUpdate

return M
