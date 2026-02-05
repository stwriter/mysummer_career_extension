-- MySummer Calls System
-- Phone calls during gameplay - more immersive than chat

local M = {}
M.moduleName = "career_modules_mysummerCalls"

M.dependencies = {
  "career_career",
}

local logTag = "mysummerCalls"

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  -- Incoming call waiting to be answered
  incomingCall = nil,
  incomingTimer = 0,

  -- Active call in progress
  activeCall = nil,
  currentExchangeIndex = 0,
  waitingForChoice = false,

  -- Call history
  completedCalls = {},

  -- Settings
  enabled = true,
}

-- Timing
local RING_DURATION = 15        -- Seconds before missed call
local LINE_DISPLAY_TIME = 4.0   -- Seconds per dialogue line
local CALL_DELAY_MIN = 5        -- Min delay before call after trigger (reduced for testing)
local CALL_DELAY_MAX = 10       -- Max delay (reduced for testing)

-- ============================================================================
-- CALL DEFINITIONS
-- ============================================================================

-- Contact display info
local contactInfo = {
  ghost = { name = "Ghost", icon = "ghost" },
  rook = { name = "Rook", icon = "rook" },
  nova = { name = "Nova", icon = "nova" },
  muscle = { name = "Muscle", icon = "muscle" },
  viper = { name = "Viper", icon = "viper" },
}

-- Calls triggered by narrative events
local eventCalls = {
  -- ========================================================================
  -- PHASE 2: CHAPTER II
  -- ========================================================================

  -- Phase 2: Ghost's cryptic call after first contact
  ghost_grandfather_warning = {
    id = "call_ghost_cryptic",
    caller = "ghost",
    priority = "normal",  -- normal = can ignore, urgent = keeps ringing
    dialogue = {
      { speaker = "ghost", text = "..." },
      { speaker = "ghost", text = {es = "Tenemos que hablar.", en = "We need to talk."} },
      { speaker = "ghost", text = {es = "No por mensaje. Así.", en = "Not by text. Like this."} },
      {
        type = "choice",
        choices = {
          {
            id = "listening",
            text = {es = "Te escucho.", en = "I'm listening."},
            response = {
              { speaker = "ghost", text = {es = "Tu abuelo... él nunca corrió.", en = "Your grandfather... he never raced."} },
              { speaker = "ghost", text = {es = "Pero eso ya lo sabes, ¿no?", en = "But you already know that, don't you?"} },
              { speaker = "ghost", text = {es = "Lo que no sabes es por qué.", en = "What you don't know is why."} },
              { speaker = "ghost", text = {es = "Pregúntate quién más perdió esa noche.", en = "Ask yourself who else lost that night."} },
            },
            effects = { ghost_trust = 10 }
          },
          {
            id = "busy",
            text = {es = "Estoy conduciendo. ¿Es urgente?", en = "I'm driving. Is it urgent?"},
            response = {
              { speaker = "ghost", text = {es = "Siempre estás conduciendo.", en = "You're always driving."} },
              { speaker = "ghost", text = {es = "Igual que él.", en = "Just like him."} },
              { speaker = "ghost", text = {es = "Solo... ten cuidado con quién confías.", en = "Just... be careful who you trust."} },
            },
            effects = { ghost_trust = 5 }
          }
        }
      },
      { speaker = "ghost", text = {es = "Tengo que colgar.", en = "I have to hang up."} },
    }
  },

  -- ========================================================================
  -- PHASE 4: CHAPTER IV
  -- ========================================================================

  -- Phase 4: Rook's nervous call
  rook_nova_argument = {
    id = "call_rook_nervous",
    caller = "rook",
    priority = "normal",
    dialogue = {
      { speaker = "rook", text = {es = "Oye... ¿tienes un momento?", en = "Hey... do you have a moment?"} },
      { speaker = "rook", text = {es = "Es sobre Nova.", en = "It's about Nova."} },
      {
        type = "choice",
        choices = {
          {
            id = "whats_wrong",
            text = {es = "¿Qué pasa con Nova?", en = "What's wrong with Nova?"},
            response = {
              { speaker = "rook", text = {es = "Hemos discutido. Fuerte.", en = "We had a fight. A bad one."} },
              { speaker = "rook", text = {es = "Ella quiere ir a por todas. The Big One.", en = "She wants to go all in. The Big One."} },
              { speaker = "rook", text = {es = "Y yo... no sé si estoy listo.", en = "And I... don't know if I'm ready."} },
              { speaker = "rook", text = {es = "¿Crees que me estoy quedando atrás?", en = "Do you think I'm falling behind?"} },
            },
            effects = { rook_trust = 10 },
            followUp = {
              type = "choice",
              choices = {
                {
                  id = "support_rook",
                  text = {es = "Cada uno tiene su ritmo. No te presiones.", en = "Everyone has their own pace. Don't pressure yourself."},
                  response = {
                    { speaker = "rook", text = "..." },
                    { speaker = "rook", text = {es = "Gracias. De verdad.", en = "Thanks. Really."} },
                    { speaker = "rook", text = {es = "A veces siento que soy el único que frena.", en = "Sometimes I feel like I'm the only one holding back."} },
                  },
                  effects = { rook_affinity = 15, nova_affinity = -5 }
                },
                {
                  id = "push_rook",
                  text = {es = "Nova tiene razón. Hay que arriesgar.", en = "Nova's right. We have to take risks."},
                  response = {
                    { speaker = "rook", text = "..." },
                    { speaker = "rook", text = {es = "Ya. Supongo que tienes razón.", en = "Yeah. I guess you're right."} },
                    { speaker = "rook", text = {es = "Todos tenéis razón menos yo.", en = "Everyone's right except me."} },
                  },
                  effects = { rook_affinity = -10, nova_affinity = 10, rook_confidence = -10 }
                },
                {
                  id = "neutral",
                  text = {es = "Es complicado. No sé qué decirte.", en = "It's complicated. I don't know what to say."},
                  response = {
                    { speaker = "rook", text = {es = "Sí... es complicado.", en = "Yeah... it's complicated."} },
                    { speaker = "rook", text = {es = "Perdona por llamar así.", en = "Sorry for calling like this."} },
                  },
                  effects = {}
                }
              }
            }
          },
          {
            id = "bad_timing",
            text = {es = "Ahora no puedo, Rook.", en = "I can't right now, Rook."},
            response = {
              { speaker = "rook", text = {es = "Claro... claro.", en = "Sure... sure."} },
              { speaker = "rook", text = {es = "Perdona.", en = "Sorry."} },
            },
            effects = { rook_trust = -5 }
          }
        }
      }
    }
  },

  -- Phase 4: Nova's frustrated call
  nova_frustration = {
    id = "call_nova_frustrated",
    caller = "nova",
    priority = "normal",
    dialogue = {
      { speaker = "nova", text = {es = "¿Puedes hablar?", en = "Can you talk?"} },
      { speaker = "nova", text = {es = "Necesito una opinión objetiva.", en = "I need an objective opinion."} },
      {
        type = "choice",
        choices = {
          {
            id = "go_ahead",
            text = {es = "Claro. ¿Qué pasa?", en = "Sure. What's up?"},
            response = {
              { speaker = "nova", text = {es = "Es Rook.", en = "It's Rook."} },
              { speaker = "nova", text = {es = "Tiene miedo. De todo.", en = "He's scared. Of everything."} },
              { speaker = "nova", text = {es = "The Big One está ahí. AL ALCANCE.", en = "The Big One is right there. WITHIN REACH."} },
              { speaker = "nova", text = {es = "Y él quiere quedarse donde estamos.", en = "And he wants to stay where we are."} },
            },
            effects = { nova_trust = 10 },
            followUp = {
              type = "choice",
              choices = {
                {
                  id = "support_nova",
                  text = {es = "Tienes razón. Hay que ir a por todas.", en = "You're right. We have to go all in."},
                  response = {
                    { speaker = "nova", text = {es = "¿Ves? Tú lo entiendes.", en = "See? You get it."} },
                    { speaker = "nova", text = {es = "No podemos quedarnos aquí para siempre.", en = "We can't stay here forever."} },
                    { speaker = "nova", text = {es = "Gracias. Necesitaba oír eso.", en = "Thanks. I needed to hear that."} },
                  },
                  effects = { nova_affinity = 15, rook_affinity = -5 }
                },
                {
                  id = "defend_rook",
                  text = {es = "Rook tiene sus razones. No lo presiones tanto.", en = "Rook has his reasons. Don't pressure him so much."},
                  response = {
                    { speaker = "nova", text = "..." },
                    { speaker = "nova", text = {es = "Pensé que lo entenderías.", en = "I thought you'd understand."} },
                    { speaker = "nova", text = {es = "Da igual.", en = "Whatever."} },
                  },
                  effects = { nova_affinity = -10, rook_affinity = 10 }
                },
                {
                  id = "stay_neutral",
                  text = {es = "Es difícil. Los dos tenéis razón.", en = "It's difficult. You're both right."},
                  response = {
                    { speaker = "nova", text = {es = "No se puede tener razón los dos.", en = "We can't both be right."} },
                    { speaker = "nova", text = {es = "Alguien tiene que ceder.", en = "Someone has to give in."} },
                    { speaker = "nova", text = {es = "Y no voy a ser yo.", en = "And it's not going to be me."} },
                  },
                  effects = {}
                }
              }
            }
          },
          {
            id = "not_now",
            text = {es = "No es buen momento.", en = "Not a good time."},
            response = {
              { speaker = "nova", text = {es = "Nunca es buen momento.", en = "It's never a good time."} },
              { speaker = "nova", text = {es = "Da igual. Hablamos luego.", en = "Whatever. Talk later."} },
            },
            effects = { nova_trust = -5 }
          }
        }
      }
    }
  },

  -- ========================================================================
  -- PHASE 5: CHAPTER V
  -- ========================================================================

  -- Phase 5: Ghost's urgent warning
  ghost_final_warning = {
    id = "call_ghost_warning",
    caller = "ghost",
    priority = "urgent",
    dialogue = {
      { speaker = "ghost", text = {es = "Escucha.", en = "Listen."} },
      { speaker = "ghost", text = {es = "No tengo mucho tiempo.", en = "I don't have much time."} },
      { speaker = "ghost", text = {es = "Algo va a pasar. Pronto.", en = "Something's going to happen. Soon."} },
      {
        type = "choice",
        choices = {
          {
            id = "what_happening",
            text = {es = "¿Qué va a pasar?", en = "What's going to happen?"},
            response = {
              { speaker = "ghost", text = {es = "No puedo decirte más.", en = "I can't tell you more."} },
              { speaker = "ghost", text = {es = "Solo... vigila tu garaje.", en = "Just... watch your garage."} },
              { speaker = "ghost", text = {es = "Y a tus amigos.", en = "And your friends."} },
              { speaker = "ghost", text = {es = "No todo el mundo quiere lo mismo que tú.", en = "Not everyone wants the same thing as you."} },
            },
            effects = { ghost_trust = 15 }
          },
          {
            id = "trust_issues",
            text = {es = "¿Por qué debería creerte?", en = "Why should I believe you?"},
            response = {
              { speaker = "ghost", text = {es = "No tienes que creerme.", en = "You don't have to believe me."} },
              { speaker = "ghost", text = {es = "Solo recuerda esta llamada.", en = "Just remember this call."} },
              { speaker = "ghost", text = {es = "Cuando pase... recuérdala.", en = "When it happens... remember it."} },
            },
            effects = {}
          }
        }
      },
      { speaker = "ghost", text = {es = "Cuídate.", en = "Take care."} },
    }
  },

  -- Phase 5: Betrayal aftermath - Rook or Nova's panicked call after the theft
  car_stolen = {
    id = "call_betrayal_aftermath",
    caller = "rook",  -- Could be either based on who didn't betray
    priority = "urgent",
    dialogue = {
      { speaker = "rook", text = {es = "¿DÓNDE ESTÁS?", en = "WHERE ARE YOU?"} },
      { speaker = "rook", text = {es = "Tu garaje... alguien entró.", en = "Your garage... someone broke in."} },
      { speaker = "rook", text = {es = "El ETK-I... NO ESTÁ.", en = "The ETK-I... IT'S GONE."} },
      {
        type = "choice",
        choices = {
          {
            id = "what",
            text = {es = "¿QUÉ?", en = "WHAT?"},
            response = {
              { speaker = "rook", text = {es = "Lo siento... estoy aquí. Vine a comprobar el setup.", en = "I'm sorry... I'm here. I came to check the setup."} },
              { speaker = "rook", text = {es = "Y la puerta... estaba abierta.", en = "And the door... was open."} },
              { speaker = "rook", text = {es = "Llamé a Nova. No responde.", en = "I called Nova. She's not answering."} },
              { speaker = "rook", text = {es = "¿Dónde está Nova?", en = "Where is Nova?"} },
            },
            effects = { rook_trust = 20 }
          },
          {
            id = "are_you_sure",
            text = {es = "¿Estás seguro?", en = "Are you sure?"},
            response = {
              { speaker = "rook", text = {es = "¡SOY MECÁNICO! ¡SÉ CUANDO NO HAY UN PUTO COCHE!", en = "I'M A MECHANIC! I KNOW WHEN THERE'S NO DAMN CAR!"} },
              { speaker = "rook", text = {es = "Perdona... perdona. Es que...", en = "Sorry... sorry. It's just..."} },
              { speaker = "rook", text = {es = "Esto no debería haber pasado.", en = "This shouldn't have happened."} },
            },
            effects = { rook_trust = 5 }
          }
        }
      },
      { speaker = "rook", text = {es = "Voy a seguir buscando. Llamaré si encuentro algo.", en = "I'll keep looking. I'll call if I find anything."} },
    }
  },

  -- ========================================================================
  -- PHASE 6: CHAPTER VI
  -- ========================================================================

  -- Phase 6: Ghost's revelation call
  ghost_truth_reveal = {
    id = "call_ghost_truth",
    caller = "ghost",
    priority = "urgent",
    dialogue = {
      { speaker = "ghost", text = {es = "Soy yo.", en = "It's me."} },
      { speaker = "ghost", text = {es = "Sé quién lo hizo.", en = "I know who did it."} },
      { speaker = "ghost", text = {es = "Y sé por qué.", en = "And I know why."} },
      {
        type = "choice",
        choices = {
          {
            id = "tell_me",
            text = {es = "Dime.", en = "Tell me."},
            response = {
              { speaker = "ghost", text = {es = "No fue un robo.", en = "It wasn't a theft."} },
              { speaker = "ghost", text = {es = "Fue alguien cercano a ti.", en = "It was someone close to you."} },
              { speaker = "ghost", text = {es = "Alguien que quería tu coche para The Big One.", en = "Someone who wanted your car for The Big One."} },
              { speaker = "ghost", text = {es = "Sin ti.", en = "Without you."} },
            },
            effects = { ghost_trust = 20 },
            followUp = {
              type = "choice",
              choices = {
                {
                  id = "who",
                  text = {es = "¿Quién fue?", en = "Who was it?"},
                  response = {
                    { speaker = "ghost", text = {es = "Eso tienes que descubrirlo tú.", en = "You have to figure that out yourself."} },
                    { speaker = "ghost", text = {es = "Pero piensa... ¿quién tenía más que ganar?", en = "But think... who had the most to gain?"} },
                    { speaker = "ghost", text = {es = "¿Quién estaba más desesperado?", en = "Who was most desperate?"} },
                  },
                  effects = {}
                },
                {
                  id = "why_help",
                  text = {es = "¿Por qué me ayudas?", en = "Why are you helping me?"},
                  response = {
                    { speaker = "ghost", text = {es = "Porque tu abuelo era buena gente.", en = "Because your grandfather was good people."} },
                    { speaker = "ghost", text = {es = "Y porque Muscle me lo pidió.", en = "And because Muscle asked me to."} },
                    { speaker = "ghost", text = {es = "Ella no quería que esto terminara así.", en = "She didn't want it to end like this."} },
                  },
                  effects = { ghost_trust = 10 }
                }
              }
            }
          }
        }
      },
      { speaker = "ghost", text = {es = "El coche está a salvo. Yo lo tengo.", en = "The car is safe. I have it."} },
      { speaker = "ghost", text = {es = "Cuando estés listo... ven a buscarlo.", en = "When you're ready... come get it."} },
    }
  },

  -- Phase 6: Viper's invitation to The Big One
  viper_contact = {
    id = "call_viper_invitation",
    caller = "viper",
    priority = "urgent",
    dialogue = {
      { speaker = "viper", text = "..." },
      { speaker = "viper", text = {es = "Ese ETK-I.", en = "That ETK-I."} },
      { speaker = "viper", text = {es = "Lo reconocería en cualquier sitio.", en = "I'd recognize it anywhere."} },
      {
        type = "choice",
        choices = {
          {
            id = "you_knew_him",
            text = {es = "¿Conocías a mi abuelo?", en = "Did you know my grandfather?"},
            response = {
              { speaker = "viper", text = {es = "Él construyó ese coche para mi pareja.", en = "He built that car for my partner."} },
              { speaker = "viper", text = {es = "Para la carrera que nunca corrió.", en = "For the race he never ran."} },
              { speaker = "viper", text = "..." },
              { speaker = "viper", text = {es = "Murió la noche antes.", en = "He died the night before."} },
              { speaker = "viper", text = {es = "Y tu abuelo... nunca lo terminó.", en = "And your grandfather... never finished it."} },
            },
            effects = { viper_trust = 15 }
          },
          {
            id = "the_car",
            text = {es = "¿El coche?", en = "The car?"},
            response = {
              { speaker = "viper", text = {es = "Ese coche debería haber corrido hace 20 años.", en = "That car should have raced 20 years ago."} },
              { speaker = "viper", text = {es = "Pero tú lo terminaste.", en = "But you finished it."} },
              { speaker = "viper", text = {es = "Hiciste lo que él no pudo.", en = "You did what he couldn't."} },
            },
            effects = { viper_trust = 10 }
          }
        }
      },
      { speaker = "viper", text = {es = "The Big One. Este sábado.", en = "The Big One. This Saturday."} },
      { speaker = "viper", text = {es = "Llega más lejos de lo que él llegó.", en = "Go further than he ever did."} },
      { speaker = "viper", text = {es = "Conduce por los que ya no pueden.", en = "Drive for those who no longer can."} },
    }
  },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function getChat()
  return extensions.career_modules_mysummerChat
end

local function applyEffects(effects)
  if not effects then return end

  local chat = getChat()
  if chat and chat.applyEffects then
    chat.applyEffects(effects)
  end
end

-- ============================================================================
-- CALL FLOW (Simplified - uses existing dialogue system)
-- ============================================================================

-- Forward declaration
local processNextExchange

local function startRinging(callDef)
  state.incomingCall = callDef
  state.incomingTimer = RING_DURATION

  local contact = contactInfo[callDef.caller] or { name = callDef.caller, icon = "unknown" }

  -- Show toast notification for incoming call
  guihooks.trigger("toastrMsg", {
    type = "info",
    title = "Incoming Call",
    msg = contact.name .. " is calling...",
    config = { timeOut = RING_DURATION * 1000 }
  })

  log("I", logTag, "Incoming call from " .. callDef.caller)
end

local function answerCall()
  if not state.incomingCall then return end

  state.activeCall = state.incomingCall
  state.incomingCall = nil
  state.incomingTimer = 0
  state.currentExchangeIndex = 1
  state.waitingForChoice = false

  local contact = contactInfo[state.activeCall.caller] or { name = state.activeCall.caller }

  log("I", logTag, "Call answered: " .. state.activeCall.id)

  -- Start dialogue using existing system
  processNextExchange()
end

local function declineCall()
  if not state.incomingCall then return end

  local callId = state.incomingCall.id
  state.incomingCall = nil
  state.incomingTimer = 0

  log("I", logTag, "Call declined: " .. callId)
end

local function missedCall()
  if not state.incomingCall then return end

  local callDef = state.incomingCall
  local contact = contactInfo[callDef.caller] or { name = callDef.caller }

  state.incomingCall = nil
  state.incomingTimer = 0

  log("I", logTag, "Missed call from " .. callDef.caller)

  -- Send a follow-up message via chat
  local chat = getChat()
  if chat then
    chat.queueMessage(callDef.caller, {
      content = "(Missed call)",
      sender = callDef.caller,
      senderType = "contact",
    }, 2000)
  end
end

local function endCall()
  if not state.activeCall then return end

  local callId = state.activeCall.id
  state.completedCalls[callId] = os.time()

  state.activeCall = nil
  state.currentExchangeIndex = 0
  state.waitingForChoice = false

  log("I", logTag, "Call ended: " .. callId)
end

-- ============================================================================
-- DIALOGUE PROCESSING (Simplified - uses existing showDialogue system)
-- ============================================================================

local currentDialogueQueue = {}
local currentFollowUp = nil

processNextExchange = function()
  if not state.activeCall then return end

  local dialogue = state.activeCall.dialogue
  if not dialogue then
    endCall()
    return
  end

  -- Check follow-up first
  if currentFollowUp then
    local followUp = currentFollowUp
    currentFollowUp = nil

    if followUp.type == "choice" then
      -- For now, skip choices and continue (UI not ready for interactive choices)
      state.waitingForChoice = false
      processNextExchange()
      return
    end
  end

  -- Process normal dialogue
  if state.currentExchangeIndex > #dialogue then
    endCall()
    return
  end

  local exchange = dialogue[state.currentExchangeIndex]
  state.currentExchangeIndex = state.currentExchangeIndex + 1

  if exchange.type == "choice" then
    -- For calls, auto-select first choice (simplified for now)
    -- Full interactive choices would require more UI work
    local firstChoice = exchange.choices[1]
    if firstChoice then
      log("I", logTag, "Auto-selecting choice: " .. firstChoice.id)

      -- Apply effects
      applyEffects(firstChoice.effects)

      -- Queue response lines using existing dialogue system
      if firstChoice.response then
        local chat = getChat()
        if chat and chat.showDialogue then
          local messages = {}
          for _, line in ipairs(firstChoice.response) do
            table.insert(messages, line.text)
          end
          chat.showDialogue(state.activeCall.caller, messages)
        end
      end

      -- Check for follow-up
      if firstChoice.followUp then
        currentFollowUp = firstChoice.followUp
      end
    end

    -- Continue after a delay
    state.waitingForChoice = false
  else
    -- Regular line - show using existing dialogue system
    local chat = getChat()
    if chat and chat.showDialogueMessage then
      chat.showDialogueMessage(state.activeCall.caller, exchange.text)
    end
  end
end

-- Called by UI when a choice is made (kept for future use)
local function onChoiceSelected(choiceId)
  if not state.activeCall or not state.waitingForChoice then return end

  state.waitingForChoice = false

  -- Find the choice in current context
  local dialogue = state.activeCall.dialogue
  local currentExchange = dialogue[state.currentExchangeIndex - 1]

  local selectedChoice = nil

  -- Check if it's a regular choice or followUp
  if currentExchange and currentExchange.type == "choice" then
    for _, choice in ipairs(currentExchange.choices) do
      if choice.id == choiceId then
        selectedChoice = choice
        break
      end
    end
  end

  if not selectedChoice then
    log("W", logTag, "Choice not found: " .. choiceId)
    processNextExchange()
    return
  end

  log("I", logTag, "Choice selected: " .. choiceId)

  -- Apply effects
  applyEffects(selectedChoice.effects)

  -- Queue response lines using existing dialogue system
  if selectedChoice.response then
    local chat = getChat()
    if chat and chat.showDialogue then
      local messages = {}
      for _, line in ipairs(selectedChoice.response) do
        table.insert(messages, line.text)
      end
      chat.showDialogue(state.activeCall.caller, messages)
    end
  end

  -- Check for follow-up
  if selectedChoice.followUp then
    currentFollowUp = selectedChoice.followUp
  end

  -- Continue after response
  processNextExchange()
end

-- Called by UI when a line finishes displaying
local function onLineComplete()
  if state.waitingForChoice then return end
  if not state.activeCall then return end

  processNextExchange()
end

-- ============================================================================
-- TRIGGER SYSTEM
-- ============================================================================

local pendingCall = nil
local pendingTimer = 0

local function onNarrativeEvent(eventId)
  if not state.enabled then return end

  local callDef = eventCalls[eventId]
  if not callDef then return end

  -- Check if already completed
  if state.completedCalls[callDef.id] then
    log("D", logTag, "Call already completed: " .. callDef.id)
    return
  end

  -- Queue call (replaces any pending call - most recent event takes priority)
  -- Calls will wait until no other call is active
  pendingCall = callDef
  pendingTimer = CALL_DELAY_MIN + math.random() * (CALL_DELAY_MAX - CALL_DELAY_MIN)

  log("I", logTag, "Call queued: " .. callDef.id .. " in " .. string.format("%.1f", pendingTimer) .. "s")
end

-- ============================================================================
-- DEBUG
-- ============================================================================

local function debugForceCall(eventId)
  local callDef = eventCalls[eventId]
  if callDef then
    startRinging(callDef)
    return true
  end
  log("W", logTag, "Call not found for event: " .. eventId)
  return false
end

local function debugListCalls()
  print("\n========== AVAILABLE CALLS ==========")
  for eventId, callDef in pairs(eventCalls) do
    local completed = state.completedCalls[callDef.id] and "[X]" or "[ ]"
    print(string.format("  %s %s (event: %s, caller: %s)",
      completed, callDef.id, eventId, callDef.caller))
  end
  print("======================================\n")
end

local function debugStatus()
  print("\n========== CALL STATUS ==========")
  print(string.format("Enabled: %s", state.enabled and "yes" or "no"))
  print(string.format("Incoming: %s (%.1fs)",
    state.incomingCall and state.incomingCall.id or "none",
    state.incomingTimer))
  print(string.format("Active: %s (exchange %d, waiting: %s)",
    state.activeCall and state.activeCall.id or "none",
    state.currentExchangeIndex,
    state.waitingForChoice and "yes" or "no"))
  print(string.format("Pending: %s (%.1fs)",
    pendingCall and pendingCall.id or "none",
    pendingTimer))
  print("\nCompleted calls:")
  for id, time in pairs(state.completedCalls) do
    print(string.format("  - %s (at %s)", id, os.date("%H:%M:%S", time)))
  end
  print("=================================\n")
end

local function debugAnswerCall()
  answerCall()
end

local function debugSelectChoice(choiceId)
  onChoiceSelected(choiceId)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local AUTO_ANSWER_DELAY = 3  -- Auto-answer after 3 seconds

local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Process pending call
  if pendingCall and not state.incomingCall and not state.activeCall then
    pendingTimer = pendingTimer - dtReal
    if pendingTimer <= 0 then
      startRinging(pendingCall)
      pendingCall = nil
      pendingTimer = 0
    end
  end

  -- Auto-answer incoming call after delay (simplified UX - no manual answer needed)
  if state.incomingCall then
    state.incomingTimer = state.incomingTimer - dtReal
    if state.incomingTimer <= (RING_DURATION - AUTO_ANSWER_DELAY) then
      -- Auto-answer the call
      answerCall()
    end
  end
end

local function onExtensionLoaded()
  log("I", logTag, "Calls system loaded")
end

local function onCareerActive()
  state.incomingCall = nil
  state.activeCall = nil
  state.currentExchangeIndex = 0
  state.waitingForChoice = false
  pendingCall = nil
  pendingTimer = 0
  log("I", logTag, "Calls system active")
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- Trigger (called by mysummerNarrative)
M.onNarrativeEvent = onNarrativeEvent

-- UI callbacks
M.answerCall = answerCall
M.declineCall = declineCall
M.onChoiceSelected = onChoiceSelected
M.onLineComplete = onLineComplete

-- Settings
M.setEnabled = function(enabled) state.enabled = enabled end
M.isEnabled = function() return state.enabled end

-- Debug
M.debugForceCall = debugForceCall
M.debugListCalls = debugListCalls
M.debugStatus = debugStatus
M.debugAnswerCall = debugAnswerCall
M.debugSelectChoice = debugSelectChoice

-- Lifecycle
M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive

return M
