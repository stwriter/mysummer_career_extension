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

-- Each event has:
--   id: unique identifier
--   phase: minimum narrative phase required
--   conditions: function that returns true if event can trigger
--   onTrigger: function called when event triggers
--   priority: higher = checked first
--   unique: if true, only triggers once ever

local narrativeEvents = {
  -- ========================================================================
  -- PHASE 0: PROLOGUE - Inheritance
  -- ========================================================================

  -- Phase 0: Inherit the garage and the grandfather's legacy
  {
    id = "inherited_garage",
    phase = 0,
    priority = 200,
    unique = true,
    conditions = function()
      -- Triggers on first career load
      return true
    end,
    onTrigger = function()
      -- Trigger monologue system to show grandfather's letter
      local monologues = extensions.career_modules_mysummerMonologues
      if monologues and monologues.onNarrativeEvent then
        monologues.onNarrativeEvent("inherited_garage")
      end

      state.storyFlags.inherited_garage = true
      state.storyFlags.has_miramar = true
      state.storyFlags.has_etki_chassis = true
      log("I", logTag, "Prologue: Garage inherited, grandfather's legacy begins")
    end
  },

  -- ========================================================================
  -- PHASE 1: CHAPTER I - Racing Among Friends
  -- ========================================================================

  -- Phase 1: Meet your teammates (Rook and Nova)
  {
    id = "meet_teammates",
    phase = 1,
    priority = 110,
    unique = true,
    conditions = function()
      -- After first race completion (lowered threshold so it happens immediately)
      local xp = career_modules_playerAttributes.getAttributeValue("mysummer-streetracing") or 0
      return xp >= 20  -- Lowered from 50 to trigger after first race
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      -- Unlock both teammates
      chat.unlockContact("rook")
      chat.unlockContact("nova")

      -- Rook's friendly introduction
      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Oye, buen trabajo ahí fuera.", en = "Hey, nice work out there."} },
        { speaker = "rook", text = {es = "Ese Miramar... no es gran cosa, pero aguanta.", en = "That Miramar... not much to look at, but it holds up."} },
        { speaker = "rook", text = {es = "Soy Rook. Este es mi taller.", en = "I'm Rook. This is my shop."} },
      }, 2000)

      -- Nova's more direct approach
      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "Nova. Piloto.", en = "Nova. Driver."} },
        { speaker = "nova", text = {es = "Vi tu última carrera. No está mal.", en = "Saw your last race. Not bad."} },
        { speaker = "nova", text = {es = "Pero todavía conduces como aficionado.", en = "But you still drive like an amateur."} },
        { speaker = "nova", text = {es = "Eso se puede arreglar.", en = "That can be fixed."} },
      }, 6000)

      state.storyFlags.teammates_met = true
      log("I", logTag, "Chapter I: Rook and Nova introduced")
    end
  },

  -- Phase 1: First contact with Ghost (after initial races)
  {
    id = "ghost_first_message",
    phase = 1,
    priority = 100,
    unique = true,
    conditions = function()
      -- Triggers after player has done some street racing
      local xp = career_modules_playerAttributes.getAttributeValue("mysummer-streetracing") or 0
      return xp >= 100 and state.storyFlags.teammates_met
    end,
    onTrigger = function()
      -- Queue Ghost's cryptic first message
      local chat = getChat()
      if not chat then return end

      chat.unlockContact("ghost")

      -- Send the mysterious message (updated to bilingual)
      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = "..." },
        { speaker = "ghost", text = {es = "La forma en que manejas esa máquina...", en = "The way you handle that machine..."} },
        { speaker = "ghost", text = {es = "Me recuerda a alguien.", en = "Reminds me of someone."} },
      }, 2000)

      state.storyFlags.ghost_contacted = true
      log("I", logTag, "Ghost first contact triggered")
    end
  },

  -- ========================================================================
  -- PHASE 2: CHAPTER II - Regional Competition
  -- ========================================================================

  -- Phase 2: Ghost mentions the grandfather
  {
    id = "ghost_grandfather_warning",
    phase = 2,
    priority = 90,
    unique = true,
    conditions = function()
      -- Must have talked to Ghost at least once
      local chat = getChat()
      if not chat then return end
      local ghostXP = chat.getContactXP("ghost") or 0
      return ghostXP >= 50 and state.storyFlags.ghost_contacted
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Conocí a alguien que trabajaba como tú.", en = "I knew someone who worked like you."}, emotion = "standard" },
        { speaker = "ghost", text = {es = "Misma precisión. Misma obsesión con cada detalle.", en = "Same precision. Same obsession with every detail."}, emotion = "standard" },
        { speaker = "ghost", text = "..." },
        { speaker = "ghost", text = {es = "Nunca corrió. Pasó algo. Algo malo.", en = "He never raced. Something happened. Something bad."}, emotion = "sad" },
        { speaker = "ghost", text = {es = "No importa.", en = "Nevermind."}, emotion = "standard" },
      }, 3000)

      state.storyFlags.grandfather_mentioned = true
      log("I", logTag, "Ghost grandfather warning triggered")
    end
  },

  -- ========================================================================
  -- PHASE 3: CHAPTER III - Regional Rallies & Rising Tension
  -- ========================================================================

  -- Phase 3: Discover the newspaper clipping about the accident
  {
    id = "newspaper_found",
    phase = 3,
    priority = 85,
    unique = true,
    conditions = function()
      return state.storyFlags.grandfather_mentioned
    end,
    onTrigger = function()
      -- Trigger monologue about discovering the truth
      local monologues = extensions.career_modules_mysummerMonologues
      if monologues and monologues.onNarrativeEvent then
        monologues.onNarrativeEvent("newspaper_found")
      end

      -- Also send a system message with the clipping
      local messages = extensions.career_modules_mysummerMessages
      if messages then
        messages.sendMessage("newspaper_clipping", {
          subject = {es = "Recorte de periódico encontrado", en = "Newspaper clipping found"},
          body = {
            es = "\"Fatal accidente en carrera ilegal deja un muerto. La víctima: un piloto prometedor y mecánico veterano. La investigación continúa.\"",
            en = "\"Fatal accident in illegal race leaves one dead. Victim: promising driver and veteran mechanic. Investigation ongoing.\""
          }
        })
      end

      state.storyFlags.newspaper_found = true
      state.storyFlags.knows_crash_details = true
      log("I", logTag, "Chapter III: Newspaper clipping discovered")
    end
  },

  -- Phase 3: Muscle recognizes the ETK-I
  {
    id = "muscle_first_contact",
    phase = 3,
    priority = 82,
    unique = true,
    conditions = function()
      return state.storyFlags.newspaper_found
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.unlockContact("muscle")

      chat.queueDialogue("muscle", {
        { speaker = "muscle", text = {es = "Ese ETK-I...", en = "That ETK-I..."}, emotion = "standard" },
        { speaker = "muscle", text = {es = "Lo conozco. Lo he visto antes.", en = "I know it. I've seen it before."}, emotion = "standard" },
        { speaker = "muscle", text = {es = "Tu abuelo lo estaba construyendo. Hace años.", en = "Your grandfather was building it. Years ago."}, emotion = "sad" },
        { speaker = "muscle", text = {es = "...", en = "..."} },
        { speaker = "muscle", text = {es = "Conduce demasiado rápido para tu propio bien.", en = "You drive too fast for your own good."}, emotion = "standard" },
        { speaker = "muscle", text = {es = "Como él.", en = "Like him."}, emotion = "sad" },
      }, 3000)

      state.storyFlags.muscle_met = true
      state.storyFlags.knows_grandfather_was_mechanic = true
      log("I", logTag, "Chapter III: Muscle introduced, recognizes ETK-I")
    end
  },

  -- Phase 3: Rook shows first signs of stress
  {
    id = "rook_stress_signs",
    phase = 3,
    priority = 80,
    unique = true,
    conditions = function()
      return state.storyFlags.muscle_met
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Oye...", en = "Hey..."} },
        { speaker = "rook", text = {es = "Últimamente todo va muy rápido.", en = "Lately everything's moving so fast."} },
        { speaker = "rook", text = {es = "Nova quiere más. Tú quieres más.", en = "Nova wants more. You want more."} },
        { speaker = "rook", text = {es = "Y yo... no sé si puedo seguir el ritmo.", en = "And I... don't know if I can keep up."} },
      }, 2500)

      state.storyFlags.rook_stressed = true
      log("I", logTag, "Rook stress signs triggered")
    end
  },

  -- Phase 3: Nova pushes for more
  {
    id = "nova_ambition_reveal",
    phase = 3,
    priority = 75,
    unique = true,
    conditions = function()
      return state.storyFlags.rook_stressed
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "¿Has pensado en The Big One?", en = "Have you thought about The Big One?"}, emotion = "standard" },
        { speaker = "nova", text = {es = "No es solo una carrera. Es LA carrera.", en = "It's not just a race. It's THE race."}, emotion = "happy" },
        { speaker = "nova", text = {es = "Podríamos llegar. Si dejamos de jugar a ser aficionados.", en = "We could make it. If we stop playing amateur."}, emotion = "standard" },
      }, 2500)

      state.storyFlags.nova_revealed_ambition = true
      log("I", logTag, "Nova ambition reveal triggered")
    end
  },

  -- ========================================================================
  -- PHASE 4: CHAPTER IV - Underground (High Level) & Breaking Point
  -- ========================================================================

  -- Phase 4: Shadow appears (black market contact)
  {
    id = "shadow_introduction",
    phase = 4,
    priority = 75,
    unique = true,
    conditions = function()
      return state.storyFlags.nova_revealed_ambition
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.unlockContact("shadow")

      chat.queueDialogue("shadow", {
        { speaker = "shadow", text = "..." },
        { speaker = "shadow", text = {es = "Oí que necesitas piezas que no están en catálogos.", en = "Heard you need parts that aren't in catalogs."}, emotion = "standard" },
        { speaker = "shadow", text = {es = "Tengo lo que buscas.", en = "I have what you're looking for."}, emotion = "standard" },
        { speaker = "shadow", text = {es = "...", en = "..."} },
        { speaker = "shadow", text = {es = "No preguntes de dónde vienen.", en = "Don't ask where they come from."}, emotion = "standard" },
      }, 2500)

      state.storyFlags.shadow_contacted = true
      log("I", logTag, "Chapter IV: Shadow (black market) introduced")
    end
  },

  -- Phase 4: Specialists unlock (Techie and Import)
  {
    id = "specialists_unlock",
    phase = 4,
    priority = 73,
    unique = true,
    conditions = function()
      return state.storyFlags.shadow_contacted
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      -- Unlock both specialists
      chat.unlockContact("techie")
      chat.unlockContact("import")

      -- Techie's data-driven introduction
      chat.queueDialogue("techie", {
        { speaker = "techie", text = {es = "He analizado tu telemetría.", en = "I analyzed your telemetry."} },
        { speaker = "techie", text = {es = "12,4% de ineficiencia en las curvas.", en = "12.4% inefficiency in corners."} },
        { speaker = "techie", text = {es = "Puedo optimizarlo.", en = "I can optimize it."} },
      }, 2000)

      -- Import's aesthetic judgment
      chat.queueDialogue("import", {
        { speaker = "import", text = {es = "Ese coche... rápido, pero feo.", en = "That car... fast, but ugly."} },
        { speaker = "import", text = {es = "Sin alma.", en = "No soul."} },
        { speaker = "import", text = {es = "En la montaña, el estilo es respeto.", en = "On the mountain, style is respect."} },
      }, 5000)

      state.storyFlags.specialists_unlocked = true
      log("I", logTag, "Chapter IV: Techie and Import introduced")
    end
  },

  -- Phase 4: Tension between Rook and Nova (the argument)
  {
    id = "rook_nova_argument",
    phase = 4,
    priority = 70,
    unique = true,
    conditions = function()
      return state.storyFlags.rook_stressed and state.storyFlags.nova_revealed_ambition
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      -- This comes as a message from Rook
      chat.queueDialogue("rook", {
        { speaker = "rook", text = {es = "Hemos discutido.", en = "We had a fight."}, emotion = "sad" },
        { speaker = "rook", text = {es = "Nova quiere arriesgarlo todo en una carrera del underground alto.", en = "Nova wants to risk everything on a high-level underground race."}, emotion = "sad" },
        { speaker = "rook", text = {es = "Yo... no puedo.", en = "I... can't."}, emotion = "sad" },
        { speaker = "rook", text = {es = "No sé qué hacer.", en = "Don't know what to do."}, emotion = "sad" },
      }, 3000)

      state.storyFlags.rook_nova_fought = true
      log("I", logTag, "Rook/Nova argument triggered")
    end
  },

  -- Phase 4: Nova's perspective
  {
    id = "nova_frustration",
    phase = 4,
    priority = 65,
    unique = true,
    conditions = function()
      return state.storyFlags.rook_nova_fought
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("nova", {
        { speaker = "nova", text = {es = "Supongo que Rook te ha contado.", en = "I guess Rook told you."}, emotion = "standard" },
        { speaker = "nova", text = {es = "Está asustado. Como siempre.", en = "He's scared. As always."}, emotion = "angry" },
        { speaker = "nova", text = {es = "Pero no podemos quedarnos aquí para siempre.", en = "But we can't stay here forever."}, emotion = "standard" },
        { speaker = "nova", text = {es = "¿Tú qué piensas?", en = "What do you think?"}, emotion = "standard" },
      }, 3000)

      state.storyFlags.nova_asked_opinion = true
      log("I", logTag, "Nova frustration triggered")
    end
  },

  -- ========================================================================
  -- PHASE 5: CHAPTER V - The Prize (Professional) & The Betrayal
  -- ========================================================================

  -- Phase 5: ETK-I construction milestone
  {
    id = "etki_ready",
    phase = 5,
    priority = 65,
    unique = true,
    conditions = function()
      -- TODO: Check if ETK-I has all critical parts installed
      -- For now, triggers based on phase and previous progression
      return state.storyFlags.nova_asked_opinion
    end,
    onTrigger = function()
      local monologues = extensions.career_modules_mysummerMonologues
      if monologues and monologues.onNarrativeEvent then
        monologues.onNarrativeEvent("etki_ready")
      end

      local chat = getChat()
      if chat then
        chat.queueDialogue("rook", {
          { speaker = "rook", text = {es = "Está... terminado.", en = "It's... finished."}, emotion = "content" },
          { speaker = "rook", text = {es = "Tu abuelo estaría orgulloso.", en = "Your grandfather would be proud."}, emotion = "content" },
        }, 2000)

        chat.queueDialogue("nova", {
          { speaker = "nova", text = {es = "Ahora sí. Ahora estamos listos.", en = "Now we're ready. Really ready."}, emotion = "happy" },
          { speaker = "nova", text = {es = "The Big One nos espera.", en = "The Big One is waiting."}, emotion = "happy" },
        }, 6000)
      end

      state.storyFlags.etki_ready = true
      log("I", logTag, "Chapter V: ETK-I construction complete")
    end
  },

  -- Phase 5: Ghost's warning before the theft
  {
    id = "ghost_final_warning",
    phase = 5,
    priority = 60,
    unique = true,
    conditions = function()
      return state.storyFlags.etki_ready
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Aquí es donde se rompió la última vez.", en = "This is where it broke last time."}, emotion = "sad" },
        { speaker = "ghost", text = {es = "Tu abuelo llegó hasta aquí. Y entonces...", en = "Your grandfather got this far. And then..."}, emotion = "sad" },
        { speaker = "ghost", text = "..." },
        { speaker = "ghost", text = {es = "Vigila tu espalda.", en = "Watch your back."}, emotion = "standard" },
        { speaker = "ghost", text = {es = "No todos los que te rodean quieren lo mismo.", en = "Not everyone around you wants the same thing."}, emotion = "standard" },
      }, 3500)

      state.storyFlags.ghost_warned = true
      log("I", logTag, "Ghost final warning triggered")
    end
  },

  -- Phase 5: The car is stolen (MAJOR EVENT)
  {
    id = "car_stolen",
    phase = 5,
    priority = 50,
    unique = true,
    conditions = function()
      return state.storyFlags.ghost_warned
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      -- Ghost sends urgent message about the theft
      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = "..." },
        { speaker = "ghost", text = {es = "Revisa tu garaje. Ahora.", en = "Check your garage. Now."}, emotion = "angry" },
      }, 1000)

      -- Follow-up after player would have checked
      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Lo sé.", en = "I know."}, emotion = "sad" },
        { speaker = "ghost", text = {es = "La puerta fue forzada. Trabajo limpio. Demasiado limpio.", en = "The door was forced. Clean job. Too clean."}, emotion = "standard" },
        { speaker = "ghost", text = {es = "Esto no fue aleatorio.", en = "This wasn't random."}, emotion = "standard" },
      }, 5000)

      state.storyFlags.car_stolen = true
      state.storyFlags.traitor_unknown = true
      log("I", logTag, "CAR STOLEN EVENT TRIGGERED - Major story beat")
    end
  },

  -- Phase 5: The betrayal message
  {
    id = "betrayal_message",
    phase = 5,
    priority = 45,
    unique = true,
    conditions = function()
      return state.storyFlags.car_stolen
    end,
    onTrigger = function()
      local chat = getChat()
      local messages = extensions.career_modules_mysummerMessages

      -- The cryptic message from the traitor
      if messages then
        messages.sendMessage("betrayal_note", {
          subject = {es = "Lo siento", en = "I'm sorry"},
          body = {
            es = "Lo hice por nosotros.\n\nTú lo entenderás algún día.\n\nNo había otra forma.",
            en = "I did it for us.\n\nYou'll understand someday.\n\nThere was no other way."
          }
        })
      end

      -- Ghost's reaction to the message
      if chat then
        chat.queueDialogue("ghost", {
          { speaker = "ghost", text = {es = "Recibiste un mensaje, ¿verdad?", en = "You got a message, didn't you?"}, emotion = "standard" },
          { speaker = "ghost", text = {es = "\"Lo hice por nosotros.\"", en = "\"I did it for us.\""}, emotion = "sad" },
          { speaker = "ghost", text = "..." },
          { speaker = "ghost", text = {es = "Alguien cercano a ti hizo esto.", en = "Someone close to you did this."}, emotion = "angry" },
        }, 3000)
      end

      state.storyFlags.betrayal_message_received = true
      log("I", logTag, "Betrayal message received")
    end
  },

  -- ========================================================================
  -- PHASE 6: CHAPTER VI - The Truth & The Big One
  -- ========================================================================

  -- Phase 6: Ghost reveals the truth and recovers the car
  {
    id = "ghost_truth_reveal",
    phase = 6,
    priority = 40,
    unique = true,
    conditions = function()
      return state.storyFlags.betrayal_message_received
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "No robé tu coche.", en = "I didn't steal your car."}, emotion = "standard" },
        { speaker = "ghost", text = {es = "Lo salvé.", en = "I saved it."}, emotion = "content" },
        { speaker = "ghost", text = {es = "Alguien quería usarlo para entrar en The Big One sin ti.", en = "Someone wanted to use it to enter The Big One without you."}, emotion = "angry" },
        { speaker = "ghost", text = {es = "Llegué primero.", en = "I got there first."}, emotion = "standard" },
        { speaker = "ghost", text = "..." },
        { speaker = "ghost", text = {es = "Muscle me lo dijo. Lo supo antes que nadie.", en = "Muscle told me. She knew before anyone."}, emotion = "sad" },
        { speaker = "ghost", text = {es = "No podía dejar que terminara así. No ese coche.", en = "She couldn't let it end like this. Not that car."}, emotion = "sad" },
      }, 3000)

      state.storyFlags.ghost_innocent = true
      log("I", logTag, "Ghost truth reveal triggered")
    end
  },

  -- Phase 6: Car is recovered
  {
    id = "car_recovered",
    phase = 6,
    priority = 35,
    unique = true,
    conditions = function()
      return state.storyFlags.ghost_innocent
    end,
    onTrigger = function()
      local monologues = extensions.career_modules_mysummerMonologues
      if monologues and monologues.onNarrativeEvent then
        monologues.onNarrativeEvent("car_recovered")
      end

      local chat = getChat()
      if chat then
        chat.queueDialogue("ghost", {
          { speaker = "ghost", text = {es = "Tu coche está en mi almacén.", en = "Your car is in my warehouse."}, emotion = "content" },
          { speaker = "ghost", text = {es = "A salvo. Completo.", en = "Safe. Complete."}, emotion = "content" },
          { speaker = "ghost", text = {es = "Listo para The Big One.", en = "Ready for The Big One."}, emotion = "happy" },
        }, 3000)
      end

      state.storyFlags.car_recovered = true
      log("I", logTag, "Chapter VI: Car recovered from Ghost")
    end
  },

  -- Phase 6: Traitor reveal (depends on player affinity with Rook/Nova)
  {
    id = "traitor_reveal",
    phase = 6,
    priority = 30,
    unique = true,
    conditions = function()
      return state.storyFlags.car_recovered
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      -- Determine traitor based on affinity system
      local rookAff = (chat.getEffectValue and chat.getEffectValue("rook_affinity")) or 0
      local novaAff = (chat.getEffectValue and chat.getEffectValue("nova_affinity")) or 0
      local rookConf = (chat.getEffectValue and chat.getEffectValue("rook_confidence")) or 0
      local novaResp = (chat.getEffectValue and chat.getEffectValue("nova_respect")) or 0

      local traitor = "both"
      local motivationEs = ""
      local motivationEn = ""

      -- Logic: Who you supported less is who betrayed
      if rookAff > novaAff + 20 or novaResp < -30 then
        -- Player sided with Rook → Nova acts out of ambition/lack of validation
        traitor = "nova"
        motivationEs = "por convicción. Creía que era el único camino."
        motivationEn = "out of conviction. She believed it was the only way."
      elseif novaAff > rookAff + 20 or rookConf < -30 then
        -- Player sided with Nova → Rook acts out of fear/inadequacy
        traitor = "rook"
        motivationEs = "por miedo. Por no quedarse atrás. Por no perderlo todo."
        motivationEn = "out of fear. Of being left behind. Of losing everything."
      else
        -- Neutral or balanced: both contributed
        traitor = "both"
        motivationEs = "cada uno a su manera. Uno por miedo, la otra por ambición."
        motivationEn = "each in their own way. One out of fear, the other out of ambition."
      end

      state.storyFlags.traitor = traitor
      state.storyFlags.traitor_motivation_es = motivationEs
      state.storyFlags.traitor_motivation_en = motivationEn

      -- Ghost reveals the grandfather's true story
      chat.queueDialogue("ghost", {
        { speaker = "ghost", text = {es = "Tu abuelo nunca corrió. No porque no pudiera.", en = "Your grandfather never raced. Not because he couldn't."}, emotion = "sad" },
        { speaker = "ghost", text = {es = "Su mejor amigo murió. La noche antes de su primera carrera.", en = "His best friend died. The night before his first race."}, emotion = "sad" },
        { speaker = "ghost", text = "..." },
        { speaker = "ghost", text = {es = "Ese amigo era el padre de Muscle.", en = "That friend was Muscle's father."}, emotion = "sad" },
        { speaker = "ghost", text = {es = "La pareja de Viper.", en = "Viper's partner."}, emotion = "sad" },
        { speaker = "ghost", text = {es = "Esa noche... lo destruyó todo.", en = "That night... it destroyed everyone."}, emotion = "sad" },
      }, 3000)

      -- Reveal who betrayed
      if traitor == "nova" then
        chat.queueDialogue("ghost", {
          { speaker = "ghost", text = {es = "Nova actuó " .. motivationEs, en = "Nova acted " .. motivationEn}, emotion = "angry" },
        }, 9000)
      elseif traitor == "rook" then
        chat.queueDialogue("ghost", {
          { speaker = "ghost", text = {es = "Rook actuó " .. motivationEs, en = "Rook acted " .. motivationEn}, emotion = "angry" },
        }, 9000)
      else
        chat.queueDialogue("ghost", {
          { speaker = "ghost", text = {es = "Los dos fallaron, " .. motivationEs, en = "They both failed, " .. motivationEn}, emotion = "angry" },
        }, 9000)
      end

      state.storyFlags.traitor_revealed = true
      log("I", logTag, "Traitor revealed: " .. traitor .. " (rookAff=" .. rookAff .. ", novaAff=" .. novaAff .. ")")
    end
  },

  -- Phase 6: Viper contacts for The Big One
  {
    id = "viper_contact",
    phase = 6,
    priority = 20,
    unique = true,
    conditions = function()
      return state.storyFlags.traitor_revealed
    end,
    onTrigger = function()
      local chat = getChat()
      if not chat then return end

      chat.unlockContact("viper")

      chat.queueDialogue("viper", {
        { speaker = "viper", text = "..." },
        { speaker = "viper", text = {es = "Ese ETK-I.", en = "That ETK-I."}, emotion = "standard" },
        { speaker = "viper", text = {es = "Lo reconocería en cualquier sitio.", en = "I'd recognize it anywhere."}, emotion = "sad" },
        { speaker = "viper", text = "..." },
        { speaker = "viper", text = {es = "Él nunca lo terminó.", en = "He never finished it."}, emotion = "sad" },
        { speaker = "viper", text = {es = "Pero tú sí.", en = "But you did."}, emotion = "content" },
        { speaker = "viper", text = "..." },
        { speaker = "viper", text = {es = "The Big One. Este sábado.", en = "The Big One. This Saturday."}, emotion = "standard" },
        { speaker = "viper", text = {es = "Llega más lejos de lo que él llegó.", en = "Go further than he ever did."}, emotion = "happy" },
      }, 3000)

      state.storyFlags.viper_contacted = true
      state.storyFlags.ready_for_big_one = true
      log("I", logTag, "Chapter VI: Viper contacted, ready for The Big One")
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

  return level or 0
end

local function canTriggerEvent(event)
  -- Check if already triggered (for unique events)
  if event.unique and state.triggeredEvents[event.id] then
    return false
  end

  -- Check phase requirement
  local currentPhase = getCurrentPhase()
  if currentPhase < event.phase then
    return false
  end

  -- Check custom conditions
  if event.conditions and not event.conditions() then
    return false
  end

  return true
end

local function triggerEvent(event)
  log("I", logTag, "Triggering narrative event: " .. event.id)

  -- Mark as triggered
  state.triggeredEvents[event.id] = true

  -- Execute the event
  if event.onTrigger then
    event.onTrigger()
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

local function checkEvents()
  -- Rate limit event checks
  local now = os.time()
  if now - state.lastEventCheck < 5 then
    return
  end
  state.lastEventCheck = now

  -- Sort events by priority (higher first)
  local sortedEvents = {}
  for _, event in ipairs(narrativeEvents) do
    table.insert(sortedEvents, event)
  end
  table.sort(sortedEvents, function(a, b)
    return (a.priority or 0) > (b.priority or 0)
  end)

  -- Check each event
  for _, event in ipairs(sortedEvents) do
    if canTriggerEvent(event) then
      triggerEvent(event)
      -- Only trigger one event per check
      return
    end
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

  -- Calculate required XP for target phase
  -- Phase progression: 0 (0 XP), 1 (100 XP), 2 (300 XP), 3 (600 XP), 4 (1000 XP), 5 (1500 XP), 6 (2100 XP)
  local xpThresholds = {
    [0] = 0,
    [1] = 100,
    [2] = 300,
    [3] = 600,
    [4] = 1000,
    [5] = 1500,
    [6] = 2100,
  }

  local requiredXP = xpThresholds[targetPhase]
  if not requiredXP then
    log("W", logTag, "Invalid phase: " .. tostring(targetPhase) .. " (must be 0-6)")
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
-- LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Narrative system loaded")
end

local function onCareerActive()
  loadState()
  log("I", logTag, "Narrative system active, phase: " .. getCurrentPhase())
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

-- Debug commands (Sprint 1)
M.debugSetPhase = debugSetPhase
M.debugSetAffinity = debugSetAffinity
M.debugGetAffinities = debugGetAffinities
M.debugListEvents = debugListEvents
M.debugGetProgress = debugGetProgress

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

-- Lifecycle
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onUpdate = onUpdate

return M
