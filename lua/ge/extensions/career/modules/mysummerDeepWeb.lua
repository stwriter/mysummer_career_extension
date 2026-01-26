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
local COOLDOWN_BASE = 180  -- 3 minutes base cooldown
local COOLDOWN_PER_LEVEL = 30  -- Reduced by 30 seconds per trust level
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

  -- Try V3 format first (with phases: intro/nudo/desenlace)
  local v3Path = contactsJsonPath .. contactId .. "_v3.json"
  local data = jsonReadFile(v3Path)

  if data and data.conversations then
    loadedContactData[contactId] = data
    loadedContactData[contactId].isV3Format = true
    log("I", logTag, "Loaded V3 contact data from JSON: " .. contactId)
    return data
  end

  -- Try V2 format (with storyArcs)
  local v2Path = contactsJsonPath .. contactId .. "_v2.json"
  data = jsonReadFile(v2Path)

  if data and data.storyArcs then
    loadedContactData[contactId] = data
    loadedContactData[contactId].isV2Format = true
    log("I", logTag, "Loaded V2 contact data from JSON: " .. contactId)
    return data
  end

  -- Fall back to v1 format
  local filePath = contactsJsonPath .. contactId .. ".json"
  data = jsonReadFile(filePath)

  if data then
    loadedContactData[contactId] = data
    log("I", logTag, "Loaded contact data from JSON: " .. contactId)
    return data
  else
    log("E", logTag, "Failed to load contact JSON: " .. filePath)
    return nil
  end
end

-- ============================================================================
-- FORWARD DECLARATIONS (needed by V2/V3 conversation system)
-- ============================================================================

-- These functions are defined later but needed by getCurrentChapter
local getContactXP
local getContactLevel
local isContactAvailable

-- ============================================================================
-- PLAYER CONTEXT TRACKING (for V3 contextReactions)
-- ============================================================================

-- Track recent player events for context-aware dialogue
local playerContext = {
  recentPoliceEscape = false,    -- Escaped police recently
  recentPoliceCaught = false,    -- Got caught by police recently
  recentPurchase = false,        -- Made a purchase recently
  recentRaceWin = false,         -- Won a race recently
  lastContact = nil,             -- Last contact talked to
  lastContactTime = 0,           -- Timestamp of last conversation
}

-- Context expiration time (in seconds)
local CONTEXT_EXPIRATION = 1800  -- 30 minutes

-- Update player context (called from external events)
local function setPlayerContext(contextKey, value)
  if playerContext[contextKey] ~= nil then
    playerContext[contextKey] = value
    playerContext.lastUpdate = os.time()
  end
end

-- Clear expired context
local function clearExpiredContext()
  local now = os.time()
  if playerContext.lastUpdate and (now - playerContext.lastUpdate) > CONTEXT_EXPIRATION then
    playerContext.recentPoliceEscape = false
    playerContext.recentPoliceCaught = false
    playerContext.recentPurchase = false
    playerContext.recentRaceWin = false
  end
end

-- Check if player has been absent for a while (for "longAbsence" context)
-- Note: vendorState passed directly because state is defined later in file
local function hasLongAbsence(vendorState)
  
  if not vendorState or not vendorState.lastConversationTime then
    return false
  end
  local timeSince = os.time() - vendorState.lastConversationTime
  return timeSince > 86400  -- More than 24 hours
end

-- Get active context for a contact conversation
-- Note: vendorState passed because state is defined later in file
local function getActiveContext(contactId, vendorState)
  clearExpiredContext()

  local contexts = {}
  if playerContext.recentPoliceEscape then
    table.insert(contexts, "recentPoliceEscape")
  end
  if playerContext.recentPoliceCaught then
    table.insert(contexts, "recentPoliceCaught")
  end
  if playerContext.recentPurchase then
    table.insert(contexts, "recentPurchase")
  end
  if playerContext.recentRaceWin then
    table.insert(contexts, "recentRaceWin")
  end
  if hasLongAbsence(vendorState) then
    table.insert(contexts, "longAbsence")
  end

  return contexts
end

-- Select a context reaction from available options
local function selectContextReaction(contactData, contextType)
  if not contactData or not contactData.contextReactions then
    return nil
  end

  local reactions = contactData.contextReactions[contextType]
  if reactions and #reactions > 0 then
    return reactions[math.random(#reactions)]
  end
  return nil
end

-- ============================================================================
-- V3 CONVERSATION SYSTEM - Phase-based narrative (intro/nudo/desenlace)
-- ============================================================================

-- Check if contact uses V3 conversation format
local function isV3Contact(contactId)
  local data = loadContactFromJson(contactId)
  return data and data.isV3Format == true
end

-- Get V3 conversation for a contact based on their level
local function getV3Conversation(contactId, vendorState)
  local data = loadContactFromJson(contactId)
  if not data or not data.conversations then return nil end

  local level = getContactLevel(contactId)
  local memory = vendorState.conversationMemory or {}
  local progress = vendorState.conversationProgress or {}

  -- Try to find conversation for current level (level1, level2, level3, etc.)
  local levelKey = "level" .. level
  local conversation = data.conversations[levelKey]

  -- Check if this level's conversation is already completed
  local convId = levelKey
  if progress.completedConversations and progress.completedConversations[convId] then
    -- Try next level if available
    levelKey = "level" .. (level + 1)
    conversation = data.conversations[levelKey]
    convId = levelKey
  end

  -- If still no conversation, look for any uncompleted one
  if not conversation then
    for i = 1, 5 do
      levelKey = "level" .. i
      convId = levelKey
      if data.conversations[levelKey] then
        if not progress.completedConversations or not progress.completedConversations[convId] then
          conversation = data.conversations[levelKey]
          break
        end
      end
    end
  end

  if not conversation then
    return nil
  end

  -- Check required memory for this conversation
  if conversation.requiredMemory then
    for _, memKey in ipairs(conversation.requiredMemory) do
      if not memory[memKey] then
        log("I", logTag, "V3 conversation " .. convId .. " requires memory: " .. memKey)
        return nil
      end
    end
  end

  return conversation, convId
end

-- Select a random nexo (transition) for a phase transition
local function selectNexo(conversation, transitionType)
  if not conversation or not conversation.nexos then return nil end

  local nexos = conversation.nexos[transitionType]
  if nexos and #nexos > 0 then
    return nexos[math.random(#nexos)]
  end
  return nil
end

-- Select an exit line based on conversation outcome
local function selectExitLine(contactData, outcome)
  if not contactData or not contactData.exitLines then return nil end

  local lines = contactData.exitLines[outcome] or contactData.exitLines.normal
  if lines and #lines > 0 then
    return lines[math.random(#lines)]
  end
  return nil
end

-- Process context transition text ({{contextTransition}} placeholder)
local function processContextTransition(text, phase, vendorState)
  if not text or not string.find(text, "{{contextTransition}}") then
    return text
  end

  local contextTransition = phase.contextTransition
  if not contextTransition then
    return string.gsub(text, "{{contextTransition}}", "")
  end

  local memory = vendorState.conversationMemory or {}

  -- Check for memory-based transitions first
  for memKey, transitionText in pairs(contextTransition) do
    if memKey ~= "default" and memory[memKey] then
      return string.gsub(text, "{{contextTransition}}", transitionText)
    end
  end

  -- Fall back to default
  local defaultText = contextTransition.default or ""
  return string.gsub(text, "{{contextTransition}}", defaultText)
end

-- Process context reaction placeholder ({{contextReaction}})
local function processContextReaction(text, contactData, contactId, vendorState)
  if not text or not string.find(text, "{{contextReaction}}") then
    return text
  end

  local contexts = getActiveContext(contactId, vendorState)
  local reaction = nil

  -- Pick the first matching context reaction
  for _, ctx in ipairs(contexts) do
    reaction = selectContextReaction(contactData, ctx)
    if reaction then break end
  end

  if reaction then
    return string.gsub(text, "{{contextReaction}}", reaction)
  else
    -- Remove the placeholder if no context applies
    return string.gsub(text, "{{contextReaction}}", "")
  end
end

-- Build V3 conversation state
local function buildV3ConversationState(contactId, vendorState, conversation, convId, contactData)
  return {
    vendorId = contactId,
    isV3 = true,
    conversationId = convId,
    conversationTitle = conversation.title,
    phases = conversation.phases,
    currentPhase = "intro",  -- Start at intro
    currentExchangeIndex = 1,
    currentBranch = nil,
    sessionPoints = 0,
    pendingMemory = {},
    messagesShown = {},
    contactData = contactData,
    nexos = conversation.nexos,
  }
end

-- Process a V3 exchange and return messages + choices
local function processV3Exchange(exchange, vendorState, conv)
  local messages = {}
  local choices = nil
  local endConversation = false
  local result = nil
  local rewards = nil
  local setsMemory = nil
  local continueToPhase = nil
  local leadsTo = nil
  local cooldown = nil
  local teaser = nil

  if exchange.speaker then
    -- Simple message
    local sender = exchange.speaker
    if sender ~= "player" and sender ~= "system" then
      sender = "vendor"
    end

    -- Process placeholders in text
    local text = exchange.text
    text = processContextTransition(text, conv.phases[conv.currentPhase], vendorState)
    text = processContextReaction(text, conv.contactData, conv.vendorId, vendorState)

    -- Skip empty messages (from removed placeholders)
    if text and text ~= "" then
      table.insert(messages, {
        sender = sender,
        text = text,
        pause = exchange.pause
      })
    end
  elseif exchange.type == "choice" then
    -- Player choice
    choices = {}
    for _, choice in ipairs(exchange.choices) do
      table.insert(choices, {
        id = choice.id,
        text = choice.text,
        traits = choice.traits,
        points = choice.points or 0,
        setsMemory = choice.setsMemory,
        leadsTo = choice.leadsTo,
        continueToPhase = choice.continueToPhase,
        endConversation = choice.endConversation,
        result = choice.result,
        cooldown = choice.cooldown,
      })
    end
  elseif exchange.type == "end" or exchange.result then
    endConversation = true
    result = exchange.result
    rewards = exchange.rewards
    setsMemory = exchange.setsMemory
    cooldown = exchange.cooldown
    teaser = exchange.teaser
  end

  return {
    messages = messages,
    choices = choices,
    endConversation = endConversation,
    result = result,
    rewards = rewards,
    setsMemory = setsMemory,
    continueToPhase = continueToPhase,
    leadsTo = leadsTo,
    cooldown = cooldown,
    teaser = teaser,
  }
end

-- ============================================================================
-- V2 CONVERSATION SYSTEM - Sequential narratives with chapters
-- ============================================================================

-- Check if contact uses V2 conversation format
local function isV2Contact(contactId)
  local data = loadContactFromJson(contactId)
  return data and data.isV2Format == true
end

-- Check if a condition is met based on conversation state
local function checkConversationCondition(condition, vendorState, contactId)
  if not condition then return true end

  local memory = vendorState.conversationMemory or {}
  local progress = vendorState.conversationProgress or {}

  -- Check memory condition (single memory key required)
  if condition.memory then
    if not memory[condition.memory] then return false end
  end

  -- Check anyMemory condition (at least one of the listed keys must exist)
  if condition.anyMemory then
    local hasAny = false
    for _, memKey in ipairs(condition.anyMemory) do
      if memory[memKey] then
        hasAny = true
        break
      end
    end
    if not hasAny then return false end
  end

  -- Check allMemory condition (all listed keys must exist)
  if condition.allMemory then
    for _, memKey in ipairs(condition.allMemory) do
      if not memory[memKey] then return false end
    end
  end

  -- Check NOT condition
  if condition["not"] then
    if condition["not"].result then
      if progress.lastResult == condition["not"].result then return false end
    end
    if condition["not"].memory then
      if memory[condition["not"].memory] then return false end
    end
  end

  -- Check completedConversation condition
  if condition.completedConversation then
    local convId = condition.completedConversation
    if not progress.completedConversations or not progress.completedConversations[convId] then
      return false
    end
  end

  return true
end

-- Get current chapter for a contact based on level and progress
local function getCurrentChapter(contactId, vendorState)
  local data = loadContactFromJson(contactId)
  if not data or not data.storyArcs then return nil end

  local level = getContactLevel(contactId)
  local memory = vendorState.conversationMemory or {}
  local progress = vendorState.conversationProgress or {}

  -- Check main arc first
  local mainArc = data.storyArcs.main
  if mainArc and mainArc.chapters then
    for _, chapter in ipairs(mainArc.chapters) do
      local skipChapter = false

      -- Check level requirement
      if chapter.requiredLevel and level < chapter.requiredLevel then
        skipChapter = true
      end

      -- Check memory requirements
      if not skipChapter and chapter.requiredMemory then
        for _, memKey in ipairs(chapter.requiredMemory) do
          if not memory[memKey] then
            skipChapter = true
            break
          end
        end
      end

      -- Check if chapter is already completed
      if not skipChapter and progress.completedChapters and progress.completedChapters[chapter.id] then
        skipChapter = true
      end

      -- This chapter is available
      if not skipChapter then
        return chapter, "main"
      end
    end
  end

  -- Check side arcs
  local sideArc = data.storyArcs.side
  if sideArc and sideArc.chapters then
    for _, chapter in ipairs(sideArc.chapters) do
      local skipChapter = false

      if chapter.requiredLevel and level < chapter.requiredLevel then
        skipChapter = true
      end

      if not skipChapter and progress.completedChapters and progress.completedChapters[chapter.id] then
        skipChapter = true
      end

      if not skipChapter then
        return chapter, "side"
      end
    end
  end

  return nil, nil
end

-- Get next conversation in current chapter
local function getNextConversation(chapter, vendorState, contactId)
  if not chapter or not chapter.conversations then return nil end

  local progress = vendorState.conversationProgress or {}

  for _, conv in ipairs(chapter.conversations) do
    local skipConv = false

    -- Check if already completed
    if progress.completedConversations and progress.completedConversations[conv.id] then
      skipConv = true
    end

    -- Check condition
    if not skipConv and not checkConversationCondition(conv.condition, vendorState, contactId) then
      skipConv = true
    end

    -- Check random chance for random-type conversations
    if not skipConv and conv.type == "random" and conv.chance then
      if math.random() > conv.chance then
        skipConv = true
      end
    end

    if not skipConv then
      return conv
    end
  end

  return nil
end

-- Process a V2 conversation exchange and return messages + choices
local function processV2Exchange(exchange, vendorState, currentBranch)
  local messages = {}
  local choices = nil
  local nextBranch = nil
  local endConversation = false
  local result = nil
  local rewards = nil
  local setsMemory = nil

  if exchange.speaker then
    -- Simple message - map contact names to "vendor" for UI
    local sender = exchange.speaker
    if sender ~= "player" then
      sender = "vendor"  -- All non-player speakers show as vendor in UI
    end
    table.insert(messages, {
      sender = sender,
      text = exchange.text,
      pause = exchange.pause
    })
  elseif exchange.type == "choice" then
    -- Player choice
    choices = {}
    for _, choice in ipairs(exchange.choices) do
      table.insert(choices, {
        id = choice.id,
        text = choice.text,
        traits = choice.traits,
        points = choice.points,
        setsMemory = choice.setsMemory,
        next = choice.next
      })
    end
  elseif exchange.type == "end" then
    endConversation = true
    result = exchange.result
    rewards = exchange.rewards
    setsMemory = exchange.setsMemory
  end

  return {
    messages = messages,
    choices = choices,
    endConversation = endConversation,
    result = result,
    rewards = rewards,
    setsMemory = setsMemory
  }
end

-- Build full conversation state for V2 format
local function buildV2ConversationState(contactId, vendorState, conversation)
  return {
    vendorId = contactId,
    isV2 = true,
    conversationId = conversation.id,
    conversationType = conversation.type,
    exchanges = conversation.exchanges,
    branches = conversation.branches or {},
    currentExchangeIndex = 1,
    currentBranch = nil,
    sessionPoints = 0,
    pendingMemory = {},
    messagesShown = {}
  }
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

  viper = {
    id = "viper",
    name = "Viper",
    personality = "cold",
    description = "Legendary street racer. Extremely hard to impress. Prove yourself or leave.",
    trustThreshold = 80,
    unlockedBy = "ghost",  -- Must earn Ghost's trust first
    partsInventory = {
      "etki_engine_race",
      "etki_turbo_stage3",
      "etki_differential_R_lsd",
      "etki_coilover_R_track",
      "etki_brake_F_carbon",
      "etki_brake_R_carbon",
    },
    -- questionPools loaded dynamically from JSON
  },

  -- AI Pilot Contact - DISABLED (BeamNG CEF blocks external HTTP requests)
  -- To re-enable: uncomment and run ai-proxy server locally
  --[[
  oracle = {
    id = "oracle",
    name = "Oracle",
    personality = "enigmatic",
    description = "A mysterious digital entity that tests your thinking and adapts to your responses.",
    trustThreshold = 0,
    isAIPilot = true,
    partsInventory = {},
  },
  --]]
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
    unknown = "So you're the one someone's been talking about. Question is - can I trust their judgment?",
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

-- Forward declaration for heat system (others already declared above)
local canClearHeatWithShadow

-- Vehicles used by each contact for races
local contactVehicles = {
  ghost = { model = "covet", config = "ghost_base" },         -- Ex-racer, discrete tuner
  techie = { model = "covet", config = "base" },              -- Compact tuner project
  muscle = { model = "moonhawk", config = "muscle_base" },    -- Old-school muscle
  import = { model = "bx", config = "import_base" },          -- JDM style
  shadow = { model = "sunburst2", config = "shadow_base" },   -- Fast and invisible
  viper = { model = "sbr", config = "viper_base" },           -- Legendary racer, SBR beast
}

-- Race challenge messages
local raceChallengeMessages = {
  ghost = "Think you're fast? Let's see what you've got. First one to the destination wins.",
  techie = "I've been tuning my ECU all week. Want to test it against your build?",
  muscle = "Back in my day, we settled things on the road. You game?",
  import = "Touge style - first to the bottom of the mountain. No excuses.",
  shadow = "Midnight run. No lights, no rules. You in?",
  viper = "You want my respect? Earn it. One race. No excuses. Winner takes all.",
}

-- Race result messages
local raceResultMessages = {
  win = {
    ghost = "Damn. You're faster than I thought. Respect.",
    techie = "Your setup must be dialed in perfectly. Impressive.",
    muscle = "Kid, you've got some real talent. Reminds me of myself.",
    import = "Clean run. You understand the spirit of racing.",
    shadow = "... You're good. Very good.",
    viper = "... Not bad. You might actually have what it takes.",
  },
  lose = {
    ghost = "Not bad, but you need more seat time. Keep practicing.",
    techie = "Close, but my data doesn't lie. Better luck next time.",
    muscle = "Experience beats youth, kid. Come back when you're ready.",
    import = "The mountain doesn't forgive mistakes. Learn from this.",
    shadow = "Slow. But at least you showed up.",
    viper = "That's it? I expected more. Come back when you're serious.",
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

  -- Set V3 context for race result
  if playerWon then
    setPlayerContext("recentRaceWin", true)
  end

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
  -- Ghost requires first purchase to unlock
  if contactId == "ghost" then
    if career_modules_mysummerParts and career_modules_mysummerParts.hasFirstPurchase then
      return career_modules_mysummerParts.hasFirstPurchase()
    end
    return false
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

-- Called when player makes their first part purchase (unlocks Ghost)
local function onFirstPurchase()
  log("I", logTag, "First purchase detected! Ghost contact is now available.")

  -- Send Ghost's intro message via the messages system
  if career_modules_mysummerMessages and career_modules_mysummerMessages.onGhostUnlocked then
    career_modules_mysummerMessages.onGhostUnlocked()
  end

  if guihooks then
    guihooks.trigger("mysummerContactUnlocked", { contactId = "ghost", name = "Ghost" })
  end
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  vendors = {},  -- { [vendorId] = { met, trustPoints (legacy), unlocked, blacklisted, strikes, redemptionType, purchaseHistory = [], usedQuestions = {}, conversationMemory = {}, conversationProgress = {} } }
  currentConversation = nil,  -- { vendorId, questions = [{question, responses}], currentIndex, sessionPoints, phase }
}

-- Strike system constants
local MAX_STRIKES = 3  -- Number of strikes before blacklist

-- Redemption types (for future implementation)
local REDEMPTION_TYPES = {
  RACE = "race",           -- Win a race against the contact
  FAVOR = "favor",         -- Do a favor (pickup/delivery mission)
  POLICE_ESCAPE = "escape" -- Escape police while carrying their goods
}

-- Add a strike to a contact (returns true if now blacklisted)
local function addStrike(contactId)
  local vendorState = state.vendors[contactId]
  if not vendorState then return false end

  vendorState.strikes = (vendorState.strikes or 0) + 1
  log("W", logTag, string.format("Contact %s received strike %d/%d", contactId, vendorState.strikes, MAX_STRIKES))

  if vendorState.strikes >= MAX_STRIKES then
    vendorState.blacklisted = true
    vendorState.redemptionType = REDEMPTION_TYPES.RACE  -- Default: win a race to redeem
    log("W", logTag, string.format("Contact %s is now BLACKLISTED (requires %s to redeem)", contactId, vendorState.redemptionType))
    return true
  end

  return false
end

-- Get current strikes for a contact
local function getStrikes(contactId)
  local vendorState = state.vendors[contactId]
  if not vendorState then return 0 end
  return vendorState.strikes or 0
end

-- Check if contact can be redeemed and how
local function getRedemptionInfo(contactId)
  local vendorState = state.vendors[contactId]
  if not vendorState or not vendorState.blacklisted then return nil end

  return {
    type = vendorState.redemptionType or REDEMPTION_TYPES.RACE,
    strikes = vendorState.strikes or MAX_STRIKES
  }
end

-- Redeem a blacklisted contact (called when player completes redemption task)
local function redeemContact(contactId)
  local vendorState = state.vendors[contactId]
  if not vendorState or not vendorState.blacklisted then return false end

  vendorState.blacklisted = false
  vendorState.strikes = 1  -- Reset to 1 strike (they're on thin ice)
  vendorState.redemptionType = nil

  -- Reset conversation progress to give them another chance
  vendorState.conversationProgress = vendorState.conversationProgress or {}
  vendorState.conversationProgress.lastResult = nil

  log("I", logTag, string.format("Contact %s has been REDEEMED", contactId))
  saveState()

  return true
end

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

-- Start a V3 conversation with phase-based narrative (intro/nudo/desenlace)
local function startV3Conversation(vendorId)
  log("I", logTag, "Starting V3 conversation with: " .. tostring(vendorId))

  local vendorDef = vendorDefinitions[vendorId]
  local vendorState = state.vendors[vendorId]

  if not vendorState then
    vendorState = { met = false, blacklisted = false, conversationProgress = {}, conversationMemory = {} }
    state.vendors[vendorId] = vendorState
  end

  -- Initialize progress if needed
  vendorState.conversationProgress = vendorState.conversationProgress or {}
  vendorState.conversationMemory = vendorState.conversationMemory or {}

  -- Mark as met
  vendorState.met = true

  -- Get contact data
  local contactData = loadContactFromJson(vendorId)
  if not contactData then
    return nil, "Contact data not found"
  end

  -- Get conversation for current level
  local conversation, convId = getV3Conversation(vendorId, vendorState)
  if not conversation then
    log("W", logTag, "No available V3 conversation for " .. vendorId)
    return nil, "fallback_to_v2"
  end

  -- Build conversation state
  state.currentConversation = buildV3ConversationState(vendorId, vendorState, conversation, convId, contactData)
  local conv = state.currentConversation

  -- Process intro phase exchanges until we hit a choice or end
  local allMessages = {}
  local choices = nil
  local ended = false

  -- Add unlock message if this is a new level
  if conversation.unlockMessage then
    table.insert(allMessages, {
      sender = "system",
      text = conversation.unlockMessage,
      isSystemMessage = true,
      isUnlockMessage = true,
    })
  end

  -- Get intro phase exchanges
  local introPhase = conv.phases.intro
  if not introPhase or not introPhase.exchanges then
    return nil, "Invalid conversation structure: missing intro phase"
  end

  conv.currentExchanges = introPhase.exchanges
  conv.currentBranches = introPhase.branches or {}

  while conv.currentExchangeIndex <= #conv.currentExchanges do
    local exchange = conv.currentExchanges[conv.currentExchangeIndex]
    local result = processV3Exchange(exchange, vendorState, conv)

    -- Add messages
    for _, msg in ipairs(result.messages) do
      table.insert(allMessages, msg)
    end

    -- Store shown messages
    table.insert(conv.messagesShown, exchange)

    if result.choices then
      choices = result.choices
      break  -- Stop at choice point
    elseif result.endConversation then
      ended = true
      -- Handle early end (rejection, etc.)
      if result.setsMemory then
        for k, v in pairs(result.setsMemory) do
          vendorState.conversationMemory[k] = v
        end
      end
      if result.rewards and result.rewards.xp then
        addContactXP(vendorId, result.rewards.xp)
        conv.sessionPoints = conv.sessionPoints + result.rewards.xp
      end
      -- Mark conversation complete
      vendorState.conversationProgress.completedConversations = vendorState.conversationProgress.completedConversations or {}
      vendorState.conversationProgress.completedConversations[convId] = true
      vendorState.conversationProgress.lastResult = result.result

      if result.cooldown then
        conversationCooldowns[vendorId] = os.time()
      end
      break
    end

    conv.currentExchangeIndex = conv.currentExchangeIndex + 1
  end

  -- Update last conversation time
  vendorState.lastConversationTime = os.time()

  if ended then
    state.currentConversation = nil
  end

  saveState()

  local currentXP = getContactXP(vendorId)
  local currentLevel = getContactLevel(vendorId)

  return {
    vendor = {
      id = vendorId,
      name = contactData.name or vendorDef.name or vendorId,
      color = vendorDef.color or "#8B5CF6",
      specialty = contactData.specialty or vendorDef.specialty or "Unknown",
      description = contactData.description or vendorDef.description or "",
    },
    messages = allMessages,
    choices = choices or {},
    ended = ended,
    trustXP = currentXP,
    trustLevel = currentLevel,
    trustPoints = currentXP,
    trustThreshold = vendorDef.trustThreshold,
    phase = conv.currentPhase,
    conversationTitle = conversation.title,
    isV3 = true,
    sessionPoints = conv.sessionPoints,
    strikes = getStrikes(vendorId),
    maxStrikes = MAX_STRIKES,
  }
end

-- Respond to V3 conversation choice
local function respondToV3Vendor(responseId)
  log("I", logTag, "respondToV3Vendor called with: " .. tostring(responseId))

  if not state.currentConversation or not state.currentConversation.isV3 then
    return nil, "No active V3 conversation"
  end

  local conv = state.currentConversation
  local vendorId = conv.vendorId
  local vendorDef = vendorDefinitions[vendorId]
  local vendorState = state.vendors[vendorId]

  if not vendorDef or not vendorState then
    return nil, "Invalid conversation state"
  end

  -- Get current exchange (should be a choice)
  local currentExchange = conv.currentExchanges[conv.currentExchangeIndex]
  if not currentExchange or currentExchange.type ~= "choice" then
    return nil, "No choice expected at this point"
  end

  -- Find selected choice
  local selectedChoice = nil
  for _, choice in ipairs(currentExchange.choices) do
    if choice.id == responseId then
      selectedChoice = choice
      break
    end
  end

  if not selectedChoice then
    return nil, "Invalid choice: " .. tostring(responseId)
  end

  -- Award points
  local points = selectedChoice.points or 0
  conv.sessionPoints = conv.sessionPoints + points
  addContactXP(vendorId, points)

  -- Store memory
  if selectedChoice.setsMemory then
    for k, v in pairs(selectedChoice.setsMemory) do
      vendorState.conversationMemory[k] = v
      conv.pendingMemory[k] = v
    end
  end

  -- Build player response message (feedback is natural through contact's response)
  local allMessages = {
    { sender = "player", text = selectedChoice.text }
  }

  -- Handle choice result
  local choices = nil
  local ended = false

  -- Check if choice ends conversation early (rejection)
  if selectedChoice.endConversation then
    ended = true

    -- Handle rejection with strike system
    if selectedChoice.result == "rejected" then
      local nowBlacklisted = addStrike(vendorId)
      if nowBlacklisted then
        table.insert(allMessages, {
          sender = "vendor",
          text = "We're done. Don't contact me again.",
          isSystemMessage = true
        })
        table.insert(allMessages, {
          sender = "system",
          text = "This contact has blacklisted you. Win a race against them or do them a favor to earn back their trust.",
          isSystemMessage = true
        })
      else
        local strikesLeft = MAX_STRIKES - getStrikes(vendorId)
        table.insert(allMessages, {
          sender = "system",
          text = string.format("Strike received. %d more mistake%s and you'll be blacklisted.", strikesLeft, strikesLeft == 1 and "" or "s"),
          isSystemMessage = true
        })
      end
    end

    if selectedChoice.cooldown then
      conversationCooldowns[vendorId] = os.time()
    end
  -- Check if choice leads to a branch
  elseif selectedChoice.leadsTo and conv.currentBranches[selectedChoice.leadsTo] then
    -- Switch to branch
    conv.currentExchanges = conv.currentBranches[selectedChoice.leadsTo]
    conv.currentExchangeIndex = 1
    conv.currentBranch = selectedChoice.leadsTo
  -- Check if choice transitions to next phase
  elseif selectedChoice.continueToPhase then
    local nextPhase = selectedChoice.continueToPhase

    -- Add nexo (transition) if available
    local nexoType = "before" .. nextPhase:gsub("^%l", string.upper)  -- "beforeNudo", "beforeDesenlace"
    local nexo = selectNexo(conv, nexoType)
    if nexo then
      table.insert(allMessages, {
        sender = "vendor",
        text = nexo,
        isNexo = true
      })
    end

    -- Switch to next phase
    local phaseData = conv.phases[nextPhase]
    if phaseData and phaseData.exchanges then
      conv.currentPhase = nextPhase
      conv.currentExchanges = phaseData.exchanges
      conv.currentBranches = phaseData.branches or {}
      conv.currentExchangeIndex = 1
      conv.currentBranch = nil
    else
      log("E", logTag, "Invalid next phase: " .. tostring(nextPhase))
    end
  else
    -- Continue to next exchange
    conv.currentExchangeIndex = conv.currentExchangeIndex + 1
  end

  -- Process exchanges until next choice or end
  if not ended then
    while conv.currentExchangeIndex <= #conv.currentExchanges do
      local exchange = conv.currentExchanges[conv.currentExchangeIndex]
      local result = processV3Exchange(exchange, vendorState, conv)

      for _, msg in ipairs(result.messages) do
        table.insert(allMessages, msg)
      end

      if result.choices then
        choices = result.choices
        break
      elseif result.endConversation then
        ended = true

        -- Handle end
        if result.setsMemory then
          for k, v in pairs(result.setsMemory) do
            vendorState.conversationMemory[k] = v
          end
        end
        if result.rewards then
          if result.rewards.xp then
            addContactXP(vendorId, result.rewards.xp)
            conv.sessionPoints = conv.sessionPoints + result.rewards.xp
          end
          if result.rewards.unlocks then
            -- Store unlocks in memory for later use
            for _, unlock in ipairs(result.rewards.unlocks) do
              vendorState.conversationMemory["unlock_" .. unlock] = true
            end
          end
        end

        -- Mark conversation complete
        vendorState.conversationProgress.completedConversations = vendorState.conversationProgress.completedConversations or {}
        vendorState.conversationProgress.completedConversations[conv.conversationId] = true
        vendorState.conversationProgress.lastResult = result.result

        -- Add teaser for next conversation
        if result.teaser then
          table.insert(allMessages, {
            sender = "vendor",
            text = result.teaser,
            isTeaser = true
          })
        end

        -- Add exit line
        local contactData = conv.contactData
        local exitOutcome = "normal"
        if result.result == "success" then
          exitOutcome = conv.sessionPoints >= 50 and "positive" or "normal"
        elseif result.result == "rejected" or result.result == "failure" then
          exitOutcome = "negative"
        end
        local exitLine = selectExitLine(contactData, exitOutcome)
        if exitLine then
          table.insert(allMessages, {
            sender = "vendor",
            text = exitLine,
            isExitLine = true
          })
        end

        if result.cooldown then
          conversationCooldowns[vendorId] = os.time()
        end
        break
      end

      conv.currentExchangeIndex = conv.currentExchangeIndex + 1
    end
  end

  -- Check if we've run out of exchanges without an explicit end
  if conv.currentExchangeIndex > #conv.currentExchanges and not ended and not choices then
    -- Check if there are more phases to go through
    local phaseOrder = { "intro", "nudo", "desenlace" }
    local currentPhaseIndex = 1
    for i, p in ipairs(phaseOrder) do
      if p == conv.currentPhase then
        currentPhaseIndex = i
        break
      end
    end

    if currentPhaseIndex < #phaseOrder then
      -- Move to next phase automatically
      local nextPhase = phaseOrder[currentPhaseIndex + 1]
      local nexoType = "before" .. nextPhase:gsub("^%l", string.upper)
      local nexo = selectNexo(conv, nexoType)
      if nexo then
        table.insert(allMessages, {
          sender = "vendor",
          text = nexo,
          isNexo = true
        })
      end

      local phaseData = conv.phases[nextPhase]
      if phaseData and phaseData.exchanges then
        conv.currentPhase = nextPhase
        conv.currentExchanges = phaseData.exchanges
        conv.currentBranches = phaseData.branches or {}
        conv.currentExchangeIndex = 1
        conv.currentBranch = nil

        -- Process the new phase until choice
        while conv.currentExchangeIndex <= #conv.currentExchanges do
          local exchange = conv.currentExchanges[conv.currentExchangeIndex]
          local result = processV3Exchange(exchange, vendorState, conv)

          for _, msg in ipairs(result.messages) do
            table.insert(allMessages, msg)
          end

          if result.choices then
            choices = result.choices
            break
          elseif result.endConversation then
            ended = true
            -- Same end handling as above
            if result.setsMemory then
              for k, v in pairs(result.setsMemory) do
                vendorState.conversationMemory[k] = v
              end
            end
            if result.rewards and result.rewards.xp then
              addContactXP(vendorId, result.rewards.xp)
              conv.sessionPoints = conv.sessionPoints + result.rewards.xp
            end
            vendorState.conversationProgress.completedConversations = vendorState.conversationProgress.completedConversations or {}
            vendorState.conversationProgress.completedConversations[conv.conversationId] = true
            vendorState.conversationProgress.lastResult = result.result

            if result.teaser then
              table.insert(allMessages, { sender = "vendor", text = result.teaser, isTeaser = true })
            end

            local exitLine = selectExitLine(conv.contactData, conv.sessionPoints >= 50 and "positive" or "normal")
            if exitLine then
              table.insert(allMessages, { sender = "vendor", text = exitLine, isExitLine = true })
            end

            if result.cooldown then
              conversationCooldowns[vendorId] = os.time()
            end
            break
          end

          conv.currentExchangeIndex = conv.currentExchangeIndex + 1
        end
      end
    else
      -- No more phases, end naturally
      ended = true
      vendorState.conversationProgress.completedConversations = vendorState.conversationProgress.completedConversations or {}
      vendorState.conversationProgress.completedConversations[conv.conversationId] = true
    end
  end

  local sessionPoints = conv.sessionPoints
  local currentStrikes = getStrikes(vendorId)

  if ended then
    setContactCooldown(vendorId)
    state.currentConversation = nil
  end

  saveState()

  local currentXP = getContactXP(vendorId)
  local currentLevel = getContactLevel(vendorId)
  local contactData = conv.contactData or loadContactFromJson(vendorId)

  return {
    vendor = {
      id = vendorId,
      name = contactData.name or vendorDef.name or vendorId,
    },
    messages = allMessages,
    choices = choices or {},
    ended = ended,
    trustXP = currentXP,
    trustLevel = currentLevel,
    trustPoints = currentXP,
    trustThreshold = vendorDef.trustThreshold,
    sessionPoints = sessionPoints,
    strikes = currentStrikes,
    maxStrikes = MAX_STRIKES,
    blacklisted = vendorState.blacklisted,
    redemptionType = vendorState.redemptionType,
    phase = conv and conv.currentPhase or nil,
    isV3 = true,
  }
end

-- Start a V2 conversation with sequential narrative
local function startV2Conversation(vendorId)
  log("I", logTag, "Starting V2 conversation with: " .. tostring(vendorId))

  local vendorDef = vendorDefinitions[vendorId]
  local vendorState = state.vendors[vendorId]

  if not vendorState then
    vendorState = { met = false, blacklisted = false, conversationProgress = {}, conversationMemory = {} }
    state.vendors[vendorId] = vendorState
  end

  -- Initialize progress if needed
  vendorState.conversationProgress = vendorState.conversationProgress or {}
  vendorState.conversationMemory = vendorState.conversationMemory or {}

  -- Mark as met
  vendorState.met = true

  -- Get current chapter and conversation
  local chapter, arcType = getCurrentChapter(vendorId, vendorState)
  if not chapter then
    log("W", logTag, "No available chapter for " .. vendorId)
    -- Fall back to legacy system if no V2 content available
    return nil, "fallback_to_legacy"
  end

  local conversation = getNextConversation(chapter, vendorState, vendorId)
  if not conversation then
    log("W", logTag, "No available conversation in chapter " .. chapter.id)
    -- Mark chapter as complete if no more conversations
    vendorState.conversationProgress.completedChapters = vendorState.conversationProgress.completedChapters or {}
    vendorState.conversationProgress.completedChapters[chapter.id] = true
    saveState()
    return nil, "No new conversations available right now."
  end

  -- Build conversation state
  state.currentConversation = buildV2ConversationState(vendorId, vendorState, conversation)
  state.currentConversation.chapterId = chapter.id
  state.currentConversation.arcType = arcType

  -- Process initial exchanges until we hit a choice or end
  local allMessages = {}
  local choices = nil
  local ended = false
  local conv = state.currentConversation

  while conv.currentExchangeIndex <= #conv.exchanges do
    local exchange = conv.exchanges[conv.currentExchangeIndex]
    local result = processV2Exchange(exchange, vendorState, conv.currentBranch)

    -- Add messages
    for _, msg in ipairs(result.messages) do
      table.insert(allMessages, msg)
    end

    -- Store shown messages
    table.insert(conv.messagesShown, exchange)

    if result.choices then
      choices = result.choices
      break  -- Stop at choice point
    elseif result.endConversation then
      ended = true
      -- Handle end rewards and memory
      if result.setsMemory then
        for k, v in pairs(result.setsMemory) do
          vendorState.conversationMemory[k] = v
        end
      end
      if result.rewards and result.rewards.xp then
        addContactXP(vendorId, result.rewards.xp)
        conv.sessionPoints = conv.sessionPoints + result.rewards.xp
      end
      -- Mark conversation complete
      vendorState.conversationProgress.completedConversations = vendorState.conversationProgress.completedConversations or {}
      vendorState.conversationProgress.completedConversations[conversation.id] = true
      vendorState.conversationProgress.lastResult = result.result

      -- Check if chapter is complete
      local nextConv = getNextConversation(chapter, vendorState, vendorId)
      if not nextConv then
        vendorState.conversationProgress.completedChapters = vendorState.conversationProgress.completedChapters or {}
        vendorState.conversationProgress.completedChapters[chapter.id] = true
      end
      break
    end

    conv.currentExchangeIndex = conv.currentExchangeIndex + 1
  end

  if ended then
    state.currentConversation = nil
  end

  saveState()

  local currentXP = getContactXP(vendorId)
  local currentLevel = getContactLevel(vendorId)
  local contactData = loadContactFromJson(vendorId)

  return {
    vendor = {
      id = vendorId,
      name = contactData.name or vendorDef.name or vendorId,
      color = vendorDef.color or "#8B5CF6",
      specialty = contactData.specialty or vendorDef.specialty or "Unknown",
      description = contactData.description or vendorDef.description or "",
    },
    messages = allMessages,
    choices = choices or {},
    ended = ended,
    trustXP = currentXP,
    trustLevel = currentLevel,
    trustPoints = currentXP,
    trustThreshold = vendorDef.trustThreshold,
    phase = chapter.title,
    chapterId = chapter.id,
    isV2 = true,
  }
end

-- Respond to V2 conversation choice
local function respondToV2Vendor(responseId)
  log("I", logTag, "respondToV2Vendor called with: " .. tostring(responseId))

  if not state.currentConversation or not state.currentConversation.isV2 then
    return nil, "No active V2 conversation"
  end

  local conv = state.currentConversation
  local vendorId = conv.vendorId
  local vendorDef = vendorDefinitions[vendorId]
  local vendorState = state.vendors[vendorId]

  if not vendorDef or not vendorState then
    return nil, "Invalid conversation state"
  end

  -- Get current exchange (should be a choice)
  local currentExchange = conv.exchanges[conv.currentExchangeIndex]
  if not currentExchange or currentExchange.type ~= "choice" then
    return nil, "No choice expected at this point"
  end

  -- Find selected choice
  local selectedChoice = nil
  for _, choice in ipairs(currentExchange.choices) do
    if choice.id == responseId then
      selectedChoice = choice
      break
    end
  end

  if not selectedChoice then
    return nil, "Invalid choice: " .. tostring(responseId)
  end

  -- Award points
  local points = selectedChoice.points or 0
  conv.sessionPoints = conv.sessionPoints + points
  addContactXP(vendorId, points)

  -- Store memory
  if selectedChoice.setsMemory then
    for k, v in pairs(selectedChoice.setsMemory) do
      vendorState.conversationMemory[k] = v
      conv.pendingMemory[k] = v
    end
  end

  -- Build player response message (feedback is natural through contact's response)
  local allMessages = {
    { sender = "player", text = selectedChoice.text }
  }

  -- Check if we branch to a different path
  local choices = nil
  local ended = false

  if selectedChoice.next and conv.branches[selectedChoice.next] then
    -- Switch to branch
    conv.exchanges = conv.branches[selectedChoice.next]
    conv.currentExchangeIndex = 1
    conv.currentBranch = selectedChoice.next
  else
    -- Continue to next exchange
    conv.currentExchangeIndex = conv.currentExchangeIndex + 1
  end

  -- Process exchanges until next choice or end
  while conv.currentExchangeIndex <= #conv.exchanges do
    local exchange = conv.exchanges[conv.currentExchangeIndex]
    local result = processV2Exchange(exchange, vendorState, conv.currentBranch)

    for _, msg in ipairs(result.messages) do
      table.insert(allMessages, msg)
    end

    if result.choices then
      choices = result.choices
      break
    elseif result.endConversation then
      ended = true
      -- Handle end
      if result.setsMemory then
        for k, v in pairs(result.setsMemory) do
          vendorState.conversationMemory[k] = v
        end
      end
      if result.rewards and result.rewards.xp then
        addContactXP(vendorId, result.rewards.xp)
        conv.sessionPoints = conv.sessionPoints + result.rewards.xp
      end

      -- Mark conversation complete
      vendorState.conversationProgress.completedConversations = vendorState.conversationProgress.completedConversations or {}
      vendorState.conversationProgress.completedConversations[conv.conversationId] = true
      vendorState.conversationProgress.lastResult = result.result

      -- Handle rejection with strike system
      if result.result == "rejected" then
        local nowBlacklisted = addStrike(vendorId)
        if nowBlacklisted then
          -- Add blacklist message
          table.insert(allMessages, {
            sender = "vendor",
            text = "We're done. Don't contact me again.",
            isSystemMessage = true
          })
          table.insert(allMessages, {
            sender = "system",
            text = "This contact has blacklisted you. Win a race against them or do them a favor to earn back their trust.",
            isSystemMessage = true
          })
        else
          -- Add strike warning
          local strikesLeft = MAX_STRIKES - getStrikes(vendorId)
          table.insert(allMessages, {
            sender = "system",
            text = string.format("Strike received. %d more mistake%s and you'll be blacklisted.", strikesLeft, strikesLeft == 1 and "" or "s"),
            isSystemMessage = true
          })
        end
      end

      -- Set cooldown if specified (explicit cooldown ends the session)
      if result.cooldown then
        conversationCooldowns[vendorId] = os.time()
        break
      end

      -- Check if there's another conversation available in this chapter
      -- If so, continue automatically (makes conversations flow naturally)
      local shouldContinue = false
      if result.result == "success" or result.result == "partial" then
        local chapter = nil
        local contactData = loadContactFromJson(vendorId)
        if contactData and contactData.storyArcs then
          -- Find current chapter
          local mainArc = contactData.storyArcs.main
          if mainArc and mainArc.chapters then
            for _, ch in ipairs(mainArc.chapters) do
              if ch.id == conv.chapterId then
                chapter = ch
                break
              end
            end
          end
        end

        if chapter then
          local nextConv = getNextConversation(chapter, vendorState, vendorId)
          if nextConv then
            -- Continue with next conversation in the same session
            log("I", logTag, "Continuing to next conversation: " .. nextConv.id)

            -- Add a pause/transition message
            table.insert(allMessages, {
              sender = "system",
              text = "...",
              isPause = true
            })

            -- Load next conversation
            conv.conversationId = nextConv.id
            conv.exchanges = nextConv.exchanges
            conv.branches = nextConv.branches or {}
            conv.currentExchangeIndex = 1
            conv.currentBranch = nil
            ended = false  -- Not ended yet, continuing
            shouldContinue = true
          end
        end
      end

      if not shouldContinue then
        break
      end
      -- When continuing to next conversation, don't increment - we already reset to 1
    else
      -- Only increment when not ending a conversation
      conv.currentExchangeIndex = conv.currentExchangeIndex + 1
    end
  end

  -- Check if we've run out of exchanges without an explicit end
  if conv.currentExchangeIndex > #conv.exchanges and not ended and not choices then
    ended = true
    vendorState.conversationProgress.completedConversations = vendorState.conversationProgress.completedConversations or {}
    vendorState.conversationProgress.completedConversations[conv.conversationId] = true
  end

  local sessionPoints = conv.sessionPoints
  local currentStrikes = getStrikes(vendorId)

  if ended then
    setContactCooldown(vendorId)
    state.currentConversation = nil
  end

  saveState()

  local currentXP = getContactXP(vendorId)
  local currentLevel = getContactLevel(vendorId)
  local contactData = loadContactFromJson(vendorId)

  return {
    vendor = {
      id = vendorId,
      name = contactData.name or vendorDef.name or vendorId,
    },
    messages = allMessages,
    choices = choices or {},
    ended = ended,
    trustXP = currentXP,
    trustLevel = currentLevel,
    trustPoints = currentXP,
    trustThreshold = vendorDef.trustThreshold,
    sessionPoints = sessionPoints,
    strikes = currentStrikes,
    maxStrikes = MAX_STRIKES,
    blacklisted = vendorState.blacklisted,
    redemptionType = vendorState.redemptionType,
    isV2 = true,
  }
end

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

  -- Check if this contact uses V3 conversation system (phase-based: intro/nudo/desenlace)
  if isV3Contact(vendorId) then
    local result, err = startV3Conversation(vendorId)
    if result then
      return result
    elseif err ~= "fallback_to_v2" then
      return nil, err
    end
    -- Fall through to V2 if V3 returned fallback
    log("I", logTag, "Falling back to V2 conversation for " .. vendorId)
  end

  -- Check if this contact uses V2 conversation system
  if isV2Contact(vendorId) then
    local result, err = startV2Conversation(vendorId)
    if result then
      return result
    elseif err ~= "fallback_to_legacy" then
      return nil, err
    end
    -- Fall through to legacy system if V2 returned fallback
    log("I", logTag, "Falling back to legacy conversation for " .. vendorId)
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

  -- Check if this is a V3 conversation (phase-based)
  if state.currentConversation.isV3 then
    return respondToV3Vendor(responseId)
  end

  -- Check if this is a V2 conversation
  if state.currentConversation.isV2 then
    return respondToV2Vendor(responseId)
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
      strikes = vendorState.strikes or 0,
      maxStrikes = MAX_STRIKES,
      redemptionType = vendorState.redemptionType,
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

  -- Only handle player vehicle events
  local playerVehId = be:getPlayerVehicleID(0)
  if vehId ~= playerVehId then
    return
  end

  -- Check if player is a cop (cops don't affect context)
  if career_modules_playerDriving and career_modules_playerDriving.getPlayerIsCop and career_modules_playerDriving.getPlayerIsCop() then
    return
  end

  -- Handle different pursuit actions for V3 context system
  if action == "arrest" then
    log("I", logTag, "Player arrested by police - applying contact trust penalty and setting context")
    setPlayerContext("recentPoliceCaught", true)
    setPlayerContext("recentPoliceEscape", false)  -- Clear escape if they got caught
    onPlayerArrested()
  elseif action == "evade" or action == "escaped" then
    log("I", logTag, "Player escaped police pursuit - setting context")
    setPlayerContext("recentPoliceEscape", true)
    setPlayerContext("recentPoliceCaught", false)  -- Clear caught if they escaped
  end
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

-- First purchase callback (Ghost unlock)
M.onFirstPurchase = onFirstPurchase

-- Shadow heat services
M.getPlayerHeatInfo = getPlayerHeatInfo
M.clearHeatWithShadow = clearHeatWithShadow
M.canClearHeatWithShadow = canClearHeatWithShadow

-- Cooldown system API
M.isContactOnCooldown = isContactOnCooldown
M.getCooldownDuration = getCooldownDuration
M.clearContactCooldown = clearContactCooldown  -- Debug function

-- Strike/Blacklist system API
M.getStrikes = getStrikes
M.addStrike = addStrike  -- For external systems to add strikes
M.getRedemptionInfo = getRedemptionInfo
M.redeemContact = redeemContact  -- Call when player completes redemption task (race win, favor, etc.)
M.MAX_STRIKES = MAX_STRIKES
M.REDEMPTION_TYPES = REDEMPTION_TYPES

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

-- V3 Context System API (for external events to set player context)
M.setPlayerContext = setPlayerContext
M.getActiveContext = getActiveContext

-- Debug: verify exports
log("D", logTag, "Export check - startContactRace type: " .. type(startContactRace))
log("D", logTag, "Export check - M.startContactRace type: " .. type(M.startContactRace))

return M
