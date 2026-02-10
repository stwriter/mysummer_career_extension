-- MySummer Chat System
-- Unified chat replacing email and DeepWeb conversations
-- WhatsApp-style messaging with contacts

local M = {}
M.moduleName = "career_modules_mysummerChat"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_branches",
  "career_modules_playerAttributes",
}

local logTag = "mysummerChat"
local saveFile = "mysummer_chat.json"
local contactsDir = "/lua/ge/extensions/career/modules/deepweb_contacts/"

-- Conversation cooldowns (indexed by contactId)
local conversationCooldowns = {}
local DEFAULT_COOLDOWN = 60  -- seconds between conversations

-- ============================================================================
-- LOCALIZATION HELPER
-- ============================================================================

local function tr(key, default)
  return translateLanguage(key, default or key)
end

-- Resolve bilingual text to current language
-- Accepts: string, or {es="...", en="..."}, or table with .es/.en fields
-- Returns: string in current language
local function resolveBilingualText(text)
  if type(text) ~= "table" then
    return tostring(text)  -- Already a string
  end

  -- Check if it's a bilingual object
  if text.es or text.en then
    -- Get current language (BeamNG uses locale codes like "en_US", "es_ES")
    local lang = Steam and Steam.language or "en_US"
    local langCode = string.sub(lang, 1, 2)  -- Extract "en" from "en_US"

    -- Select language (prefer current, fallback to Spanish, then English, then first available)
    if langCode == "es" and text.es then
      return text.es
    elseif langCode == "en" and text.en then
      return text.en
    elseif text.es then
      return text.es  -- Default to Spanish (primary language)
    elseif text.en then
      return text.en
    else
      return tostring(text)  -- Fallback
    end
  end

  -- Not a bilingual object, return as string
  return tostring(text)
end

-- ============================================================================
-- CONTACT DEFINITIONS
-- ============================================================================

-- Contact IDs and avatars (non-localized)
-- Teammates (rook, nova) + Underground contacts + system + player (for internal thoughts)
local contactIds = { "rook", "nova", "ghost", "techie", "muscle", "import", "shadow", "viper", "system", "player" }

-- Returns localized contact definition
local function getContactDefinition(contactId)
  local prefix = "mysummer.chat.contacts." .. contactId .. "."
  local def = {
    id = contactId,
    displayName = tr(prefix .. "displayName", contactId),
    unknownName = tr(prefix .. "unknownName", "???"),
    avatar = contactId,
    specialty = tr(prefix .. "specialty", ""),
  }
  if contactId == "system" then
    def.isSystem = true
  end
  -- Player contact is for internal thoughts/monologues
  if contactId == "player" then
    def.displayName = "..."  -- Ellipsis for thoughts
    def.unknownName = "..."
    def.isSystem = true  -- Don't show in contact list
  end
  return def
end

-- Build contact definitions table (called when needed)
local function getContactDefinitions()
  local defs = {}
  for _, id in ipairs(contactIds) do
    defs[id] = getContactDefinition(id)
  end
  return defs
end

-- Cache for contact definitions (refreshed on language change)
local contactDefinitions = nil

local function ensureContactDefinitions()
  if not contactDefinitions then
    contactDefinitions = getContactDefinitions()
  end
  return contactDefinitions
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  -- Conversations indexed by contactId
  conversations = {},

  -- Contact states (unlocked, trust level, etc.)
  contacts = {},

  -- Global counters
  nextMessageId = 1,
  nextConversationId = 1,

  -- Unread tracking
  unreadByContact = {},
  totalUnread = 0,

  -- Active dialogue state (for scripted conversations)
  activeDialogue = nil,

  -- Pending choices waiting for player
  pendingChoices = nil,

  -- Typing indicator state
  typingContacts = {},

  -- Affinity/Effects tracking for narrative system
  -- Keys: rook_affinity, nova_affinity, ambition, caution, loyalty, etc.
  affinityEffects = {},

  -- Recent events for context reactions
  -- Keys: policeEscape, policeCaught, raceWin, purchase
  recentEvents = {},

  -- SMS trigger tracking (prevent duplicate sends)
  triggeredSMS = {},

  -- Loading flag (prevent message spam during save load)
  isLoading = false,
}

-- Forward declarations for functions used before definition
local saveState
local loadState
local processDialogueQueue

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function getTimestamp()
  return os.time()
end

local function formatTimestamp(timestamp)
  return os.date("%H:%M", timestamp)
end

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

-- Get localized text from a value that can be:
--   - A simple string: "Hello"
--   - A bilingual table: { es = "Hola", en = "Hello" }
local function getLocalizedText(textValue)
  if type(textValue) == "string" then
    return textValue
  elseif type(textValue) == "table" then
    -- Get current language from BeamNG settings
    local lang = Steam and Steam.language or "en_US"
    local langCode = string.sub(lang, 1, 2) -- "en_US" -> "en", "es_ES" -> "es"

    -- Try exact match, then fallback
    if textValue[langCode] then
      return textValue[langCode]
    elseif textValue.en then
      return textValue.en
    elseif textValue.es then
      return textValue.es
    else
      -- Return first available value
      for _, v in pairs(textValue) do
        if type(v) == "string" then return v end
      end
    end
  end
  return ""
end

-- ============================================================================
-- AFFINITY/EFFECTS SYSTEM
-- ============================================================================

-- Apply effects from a conversation choice
-- effects: table of { effectName = delta } e.g. { rook_affinity = 10, ambition = 5 }
local function applyEffects(effects)
  if not effects then return end

  for effectName, delta in pairs(effects) do
    local currentValue = state.affinityEffects[effectName] or 0
    state.affinityEffects[effectName] = currentValue + delta
    log("I", logTag, string.format("Effect applied: %s %+d (now %d)",
        effectName, delta, state.affinityEffects[effectName]))
  end

  -- Trigger UI update
  guihooks.trigger("mysummerAffinityUpdated", deepcopy(state.affinityEffects))
  saveState()
end

-- Get current value of an effect
local function getEffectValue(effectName)
  return state.affinityEffects[effectName] or 0
end

-- Get all effects
local function getAllEffects()
  return deepcopy(state.affinityEffects)
end

-- Check if player is aligned more with Rook or Nova
-- Returns: "rook", "nova", or "neutral"
local function getTeammateAlignment()
  local rookAffinity = state.affinityEffects.rook_affinity or 0
  local novaAffinity = state.affinityEffects.nova_affinity or 0

  if rookAffinity > novaAffinity + 20 then
    return "rook"
  elseif novaAffinity > rookAffinity + 20 then
    return "nova"
  else
    return "neutral"
  end
end

-- Check player's general approach (cautious vs ambitious)
-- Returns: "cautious", "ambitious", or "balanced"
local function getPlayerApproach()
  local caution = state.affinityEffects.caution or 0
  local ambition = state.affinityEffects.ambition or 0

  if caution > ambition + 15 then
    return "cautious"
  elseif ambition > caution + 15 then
    return "ambitious"
  else
    return "balanced"
  end
end

-- Get chosen partner from romance choice in Phase 5
-- Returns: "rook", "nova", or nil
local function getChosenPartner()
  local narrative = extensions.career_modules_mysummerNarrative
  if narrative and narrative.getStoryFlags then
    local flags = narrative.getStoryFlags()
    return flags.chosen_partner
  end
  return nil
end

-- ============================================================================
-- V3 CONTACT DATA LOADING
-- ============================================================================

-- Cache for loaded contact JSON data
local contactDataCache = {}

local function loadContactFromJson(contactId)
  if contactDataCache[contactId] then
    return contactDataCache[contactId]
  end

  local filePath = contactsDir .. contactId .. "_v3.json"
  local data = jsonReadFile(filePath)

  if data then
    contactDataCache[contactId] = data
    log("I", logTag, "Loaded V3 data for contact: " .. contactId)
  else
    log("W", logTag, "No V3 data found for contact: " .. contactId)
  end

  return data
end

local function isV3Contact(contactId)
  local data = loadContactFromJson(contactId)
  return data and data.isV3Format == true
end

-- ============================================================================
-- V3 CONVERSATION HELPERS
-- ============================================================================

-- Get conversation level based on contact XP
local function getContactLevel(contactId)
  -- Integrate with DeepWeb XP system if available
  if career_modules_mysummerDeepWeb and career_modules_mysummerDeepWeb.getContactLevel then
    return career_modules_mysummerDeepWeb.getContactLevel(contactId)
  end
  return 1
end

-- Get current narrative phase from streetracing skill level
-- This controls which conversations are available based on story progression
local function getCurrentNarrativePhase()
  -- Get the current narrative phase from mysummerCareer (phase0, phase1, etc.)
  -- This is different from skill level - phases advance based on story progression
  if career_modules_mysummerCareer and career_modules_mysummerCareer.getCurrentPhase then
    return career_modules_mysummerCareer.getCurrentPhase()
  end
  return 0
end

-- Get contact XP
local function getContactXP(contactId)
  if career_modules_mysummerDeepWeb and career_modules_mysummerDeepWeb.getContactXP then
    return career_modules_mysummerDeepWeb.getContactXP(contactId)
  end
  return 0
end

-- Add contact XP
local function addContactXP(contactId, amount)
  if career_modules_mysummerDeepWeb and career_modules_mysummerDeepWeb.addContactXP then
    career_modules_mysummerDeepWeb.addContactXP(contactId, amount)
  end
end

-- Get V3 conversation for contact's current level
local function getV3Conversation(contactId, scriptState)
  local data = loadContactFromJson(contactId)
  if not data or not data.conversations then return nil end

  local level = getContactLevel(contactId)
  local narrativePhase = getCurrentNarrativePhase()
  local memory = scriptState.memory or {}
  local completed = scriptState.completed or {}

  -- Try conversation for current level
  local levelKey = "level" .. level
  local conversation = data.conversations[levelKey]
  local convId = levelKey

  -- Check if already completed
  if completed[convId] then
    levelKey = "level" .. (level + 1)
    conversation = data.conversations[levelKey]
    convId = levelKey
  end

  -- Look for any uncompleted conversation
  if not conversation then
    for i = 1, 5 do
      levelKey = "level" .. i
      convId = levelKey
      if data.conversations[levelKey] then
        if not completed[convId] then
          conversation = data.conversations[levelKey]
          break
        end
      end
    end
  end

  if not conversation then
    return nil
  end

  -- Check required narrative phase (story progression)
  if conversation.requiredPhase then
    if narrativePhase < conversation.requiredPhase then
      log("I", logTag, string.format("V3 conversation %s requires narrative phase %d (current: %d)",
          convId, conversation.requiredPhase, narrativePhase))
      return nil
    end
  end

  -- Check required memory (AND logic - all must be present)
  if conversation.requiredMemory then
    for _, memKey in ipairs(conversation.requiredMemory) do
      if not memory[memKey] then
        log("I", logTag, "V3 conversation " .. convId .. " requires memory: " .. memKey)
        return nil
      end
    end
  end

  -- Check required memory ANY (OR logic - at least one must be present)
  if conversation.requiredMemoryAny then
    local anyFound = false
    for _, memKey in ipairs(conversation.requiredMemoryAny) do
      if memory[memKey] then
        anyFound = true
        break
      end
    end
    if not anyFound then
      log("I", logTag, "V3 conversation " .. convId .. " requires any of: " .. table.concat(conversation.requiredMemoryAny, ", "))
      return nil
    end
  end

  return conversation, convId
end

-- Select random nexo (transition text)
local function selectNexo(conversationData, transitionType)
  if not conversationData or not conversationData.nexos then return nil end

  local nexos = conversationData.nexos[transitionType]
  if nexos and #nexos > 0 then
    return nexos[math.random(#nexos)]
  end
  return nil
end

-- Select exit line based on outcome
local function selectExitLine(contactData, outcome)
  if not contactData or not contactData.exitLines then return nil end

  local lines = contactData.exitLines[outcome] or contactData.exitLines.normal
  if lines and #lines > 0 then
    return lines[math.random(#lines)]
  end
  return nil
end

-- Process context transition placeholder
local function processContextTransition(text, phase, memory)
  if not text or not string.find(text, "{{contextTransition}}") then
    return text
  end

  local contextTransition = phase and phase.contextTransition
  if not contextTransition then
    return string.gsub(text, "{{contextTransition}}", "")
  end

  -- Check memory-based transitions
  for memKey, transitionText in pairs(contextTransition) do
    if memKey ~= "default" and memory[memKey] then
      return string.gsub(text, "{{contextTransition}}", transitionText)
    end
  end

  local defaultText = contextTransition.default or ""
  return string.gsub(text, "{{contextTransition}}", defaultText)
end

-- Process context reaction placeholder (based on recent player events)
local function processContextReaction(text, contactData)
  if not text or not string.find(text, "{{contextReaction}}") then
    return text
  end

  local contextReactions = contactData and contactData.contextReactions
  if not contextReactions then
    return string.gsub(text, "{{contextReaction}}", "")
  end

  -- Check recent events (priority order)
  local selectedReaction = nil

  -- Check for recent police escape (example - would need real game state)
  if contextReactions.recentPoliceEscape and state.recentEvents and state.recentEvents.policeEscape then
    local reactions = contextReactions.recentPoliceEscape
    selectedReaction = reactions[math.random(#reactions)]
  -- Check for recent race win
  elseif contextReactions.recentRaceWin and state.recentEvents and state.recentEvents.raceWin then
    local reactions = contextReactions.recentRaceWin
    selectedReaction = reactions[math.random(#reactions)]
  -- Check for recent purchase from this contact
  elseif contextReactions.recentPurchase and state.recentEvents and state.recentEvents.purchase then
    local reactions = contextReactions.recentPurchase
    selectedReaction = reactions[math.random(#reactions)]
  -- Default: long absence or generic
  elseif contextReactions.longAbsence then
    local reactions = contextReactions.longAbsence
    selectedReaction = reactions[math.random(#reactions)]
  end

  -- Fallback to empty string if nothing matches
  if not selectedReaction then
    selectedReaction = ""
  end

  return string.gsub(text, "{{contextReaction}}", selectedReaction)
end

-- Process V3 exchange and return messages + choices
local function processV3Exchange(exchange, scriptState, currentPhase, contactData)
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
  local memory = scriptState.memory or {}

  if exchange.speaker then
    -- Simple message from speaker
    local sender = exchange.speaker
    local senderType = "contact"
    if sender == "player" then
      senderType = "player"
    elseif sender == "system" then
      senderType = "system"
    end

    -- Process placeholders and localization
    local text = getLocalizedText(exchange.text)
    text = processContextTransition(text, currentPhase, memory)
    text = processContextReaction(text, contactData)

    -- Skip empty messages
    if text and text ~= "" then
      table.insert(messages, {
        sender = sender,
        senderType = senderType,
        content = text,
        pause = exchange.pause or 0,
        typingDelay = exchange.typingDelay or (string.len(text) * 30 + 500), -- ms based on text length
      })
    end
  elseif exchange.type == "choice" then
    -- Player choice point
    choices = {}
    for _, choice in ipairs(exchange.choices) do
      table.insert(choices, {
        id = choice.id,
        text = getLocalizedText(choice.text),
        traits = choice.traits,
        points = choice.points or 0,
        effects = choice.effects,
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
-- CONTACT MANAGEMENT
-- ============================================================================

local function initializeContact(contactId)
  if state.contacts[contactId] then return end

  local defs = ensureContactDefinitions()
  local def = defs[contactId]
  if not def then
    log("W", logTag, "Unknown contact: " .. tostring(contactId))
    return
  end

  state.contacts[contactId] = {
    id = contactId,
    displayName = def.displayName,
    unknownName = def.unknownName,
    avatar = def.avatar,
    specialty = def.specialty,
    isUnlocked = def.isSystem or false,
    isSystem = def.isSystem or false,
    trustLevel = 1,
    lastMessageTime = 0,
    isTyping = false,
  }
end

local function getContact(contactId)
  initializeContact(contactId)
  return deepcopy(state.contacts[contactId])
end

local function getAllContacts()
  local contacts = {}
  for contactId, _ in pairs(contactDefinitions) do
    initializeContact(contactId)
    table.insert(contacts, deepcopy(state.contacts[contactId]))
  end
  return contacts
end

local function unlockContact(contactId)
  initializeContact(contactId)
  if state.contacts[contactId] then
    state.contacts[contactId].isUnlocked = true
    log("I", logTag, "Contact unlocked: " .. contactId)

    guihooks.trigger("mysummerChatContactUnlocked", {
      contactId = contactId,
      displayName = state.contacts[contactId].displayName,
    })
    saveState()
  end
end

local function isContactUnlocked(contactId)
  initializeContact(contactId)
  return state.contacts[contactId] and state.contacts[contactId].isUnlocked
end

-- Disable a contact (they appear in the list but never respond to messages)
-- Used when a romance partner "disappears" after the ETK-I theft (phase 5-6)
local function disableContact(contactId)
  initializeContact(contactId)
  if state.contacts[contactId] then
    state.contacts[contactId].isDisabled = true
    log("I", logTag, "Contact disabled (will not respond): " .. contactId)
    guihooks.trigger("mysummerChatContactUpdated", {
      contactId = contactId,
      isDisabled = true,
    })
    saveState()
  end
end

-- Re-enable a contact so they respond again
-- Used when the romance partner reappears in phase 7
local function enableContact(contactId)
  initializeContact(contactId)
  if state.contacts[contactId] then
    state.contacts[contactId].isDisabled = false
    log("I", logTag, "Contact re-enabled: " .. contactId)
    guihooks.trigger("mysummerChatContactUpdated", {
      contactId = contactId,
      isDisabled = false,
    })
    saveState()
  end
end

-- Check if a contact is disabled (won't respond)
local function isContactDisabled(contactId)
  initializeContact(contactId)
  return state.contacts[contactId] and state.contacts[contactId].isDisabled == true
end

local function getContactDisplayName(contactId)
  initializeContact(contactId)
  local contact = state.contacts[contactId]
  if not contact then return "Unknown" end

  if contact.isUnlocked then
    return contact.displayName
  else
    return contact.unknownName
  end
end

-- ============================================================================
-- CONVERSATION MANAGEMENT
-- ============================================================================

local function getOrCreateConversation(contactId)
  if not state.conversations[contactId] then
    initializeContact(contactId)

    state.conversations[contactId] = {
      id = state.nextConversationId,
      contactId = contactId,
      messages = {},
      lastActivity = getTimestamp(),
      scriptState = {
        activeScript = nil,
        currentPhase = nil,
        exchangeIndex = 1,
        sessionPoints = 0,
        memory = {},
        completed = {},
      },
    }
    state.nextConversationId = state.nextConversationId + 1
    state.unreadByContact[contactId] = 0
  end
  return state.conversations[contactId]
end

local function getConversation(contactId)
  local conv = getOrCreateConversation(contactId)
  local contact = getContact(contactId)

  return {
    conversation = deepcopy(conv),
    contact = contact,
    pendingChoices = state.pendingChoices and state.pendingChoices.contactId == contactId
      and state.pendingChoices.choices or nil,
  }
end

local function getConversations()
  local result = {}

  -- Include all conversations that have messages
  for contactId, conv in pairs(state.conversations) do
    if #conv.messages > 0 then
      local contact = getContact(contactId)
      table.insert(result, {
        contactId = contactId,
        displayName = getContactDisplayName(contactId),
        avatar = contact.avatar,
        isUnlocked = contact.isUnlocked,
        isSystem = contact.isSystem,
        lastMessage = conv.messages[#conv.messages],
        lastActivity = conv.lastActivity,
        unreadCount = state.unreadByContact[contactId] or 0,
      })
    end
  end

  -- Sort by lastActivity (most recent first)
  table.sort(result, function(a, b)
    return a.lastActivity > b.lastActivity
  end)

  return result
end

-- ============================================================================
-- MESSAGE MANAGEMENT
-- ============================================================================

local function addMessage(contactId, messageData)
  local conv = getOrCreateConversation(contactId)

  local message = {
    id = state.nextMessageId,
    conversationId = conv.id,
    sender = messageData.sender or contactId,
    senderType = messageData.senderType or "contact",
    content = messageData.content or "",
    contentType = messageData.contentType or "text",
    timestamp = getTimestamp(),
    read = messageData.read or false,
    choices = messageData.choices,
    selectedChoice = nil,
    actionType = messageData.actionType,
    actionData = messageData.actionData,
    actionCompleted = false,
  }

  state.nextMessageId = state.nextMessageId + 1
  table.insert(conv.messages, message)
  conv.lastActivity = message.timestamp

  -- Update contact's last message time
  if state.contacts[contactId] then
    state.contacts[contactId].lastMessageTime = message.timestamp
  end

  -- Track unread (only for non-player messages)
  if message.senderType ~= "player" and not message.read then
    state.unreadByContact[contactId] = (state.unreadByContact[contactId] or 0) + 1
    state.totalUnread = state.totalUnread + 1
  end

  return message
end

local function sendContactMessage(contactId, content, options)
  options = options or {}

  local message = addMessage(contactId, {
    sender = contactId,
    senderType = "contact",
    content = content,
    contentType = options.contentType or "text",
    choices = options.choices,
    actionType = options.actionType,
    actionData = options.actionData,
  })

  -- Notify UI
  guihooks.trigger("mysummerChatNewMessage", {
    contactId = contactId,
    contactName = getContactDisplayName(contactId),
    preview = string.sub(content, 1, 50),
    messageId = message.id,
  })

  guihooks.trigger("mysummerChatConversationUpdated", {
    contactId = contactId,
    conversation = deepcopy(getOrCreateConversation(contactId)),
    newMessages = { deepcopy(message) },
  })

  -- Show toast notification (unless silent mode)
  if not options.silent then
    -- Ensure content is a string for display
    local displayContent = type(content) == "string" and content or (content.es or content.en or "")
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = tr("mysummer.notifications.newMessage", "New Message"),
      msg = getContactDisplayName(contactId) .. ": " .. string.sub(displayContent, 1, 30),
    })
  end

  -- Safe log (content should be string, but handle tables just in case)
  local logContent = type(content) == "string" and content or (content.es or content.en or "")
  log("I", logTag, "Contact message from " .. contactId .. ": " .. string.sub(logContent, 1, 30))

  saveState()
  return message
end

local function sendPlayerMessage(contactId, content, options)
  options = options or {}

  local message = addMessage(contactId, {
    sender = "player",
    senderType = "player",
    content = content,
    contentType = "text",
    read = true,
  })

  -- Notify UI
  guihooks.trigger("mysummerChatConversationUpdated", {
    contactId = contactId,
    conversation = deepcopy(getOrCreateConversation(contactId)),
    newMessages = { deepcopy(message) },
  })

  -- Safe log (content should always be a string now, but handle tables just in case)
  local logContent = type(content) == "string" and content or tostring(content)
  log("I", logTag, "Player message to " .. contactId .. ": " .. string.sub(logContent, 1, 30))

  saveState()
  return message
end

local function sendSystemMessage(content, options)
  options = options or {}

  local message = addMessage("system", {
    sender = "system",
    senderType = "system",
    content = content,
    contentType = options.contentType or "text",
    actionType = options.actionType,
    actionData = options.actionData,
  })

  -- Notify UI
  guihooks.trigger("mysummerChatNewMessage", {
    contactId = "system",
    contactName = "System",
    preview = string.sub(content, 1, 50),
    messageId = message.id,
  })

  log("I", logTag, "System message: " .. string.sub(content, 1, 30))

  saveState()
  return message
end

-- ============================================================================
-- READ STATUS
-- ============================================================================

local function markAsRead(contactId, messageIds)
  local conv = state.conversations[contactId]
  if not conv then return end

  local markedCount = 0

  if messageIds then
    -- Mark specific messages
    for _, msgId in ipairs(messageIds) do
      for _, msg in ipairs(conv.messages) do
        if msg.id == msgId and not msg.read then
          msg.read = true
          markedCount = markedCount + 1
        end
      end
    end
  else
    -- Mark all messages in conversation
    for _, msg in ipairs(conv.messages) do
      if not msg.read then
        msg.read = true
        markedCount = markedCount + 1
      end
    end
  end

  -- Update unread counts
  if markedCount > 0 then
    state.unreadByContact[contactId] = math.max(0, (state.unreadByContact[contactId] or 0) - markedCount)
    state.totalUnread = math.max(0, state.totalUnread - markedCount)

    guihooks.trigger("mysummerChatReadStatusUpdated", {
      contactId = contactId,
      unreadCount = state.unreadByContact[contactId],
      totalUnread = state.totalUnread,
    })
    saveState()
  end
end

local function getUnreadCounts()
  return {
    total = state.totalUnread,
    byContact = deepcopy(state.unreadByContact),
  }
end

-- ============================================================================
-- TYPING INDICATORS
-- ============================================================================

local typingTimers = {}

local function setContactTyping(contactId, isTyping, duration)
  if state.contacts[contactId] then
    state.contacts[contactId].isTyping = isTyping
    state.typingContacts[contactId] = isTyping

    guihooks.trigger("mysummerChatTyping", {
      contactId = contactId,
      isTyping = isTyping,
    })

    -- Auto-clear typing after duration
    if isTyping and duration then
      if typingTimers[contactId] then
        -- Cancel existing timer (simplified - in real impl use proper timer)
      end
      -- Note: In actual implementation, use BeamNG timer system
    end
  end
end

-- Get typing state for a contact (used by UI polling)
local function isContactTyping(contactId)
  return state.typingContacts[contactId] == true
end

-- ============================================================================
-- CHOICES / DIALOGUE
-- ============================================================================

-- Pending choices queue (for delayed choice display)
-- IMPORTANT: Choices are NOT stored in state.pendingChoices until delay expires
-- This prevents UI from showing choices too early when calling getConversation()
local pendingChoicesQueue = {}

local function setPendingChoices(contactId, choices, timeout, delay, smsId)
  -- If delay specified, queue EVERYTHING for later (don't save to state yet)
  if delay and delay > 0 then
    table.insert(pendingChoicesQueue, {
      contactId = contactId,
      choices = choices,
      timeout = timeout,
      smsId = smsId,
      triggerAt = getTimestamp() + delay / 1000,  -- Convert ms to seconds
    })
    log("I", logTag, string.format("Choices queued with %dms delay for %s (smsId: %s)", delay, contactId, tostring(smsId)))
  else
    -- No delay: save to state and trigger immediately
    state.pendingChoices = {
      contactId = contactId,
      choices = choices,
      timeout = timeout,
      smsId = smsId,
      setAt = getTimestamp(),
    }
    guihooks.trigger("mysummerChatChoices", {
      contactId = contactId,
      choices = choices,
      timeout = timeout,
      smsId = smsId,  -- Include smsId for UI to determine response type
    })
  end
end

-- Process pending choices (called from onUpdate)
local function processPendingChoices()
  if #pendingChoicesQueue == 0 then return end

  local now = getTimestamp()
  local toRemove = {}

  for i, pending in ipairs(pendingChoicesQueue) do
    if now >= pending.triggerAt then
      -- NOW save to state (so getConversation returns them)
      state.pendingChoices = {
        contactId = pending.contactId,
        choices = pending.choices,
        timeout = pending.timeout,
        smsId = pending.smsId,
        setAt = now,
      }
      -- And trigger UI (include smsId so UI knows if it's SMS or V3 dialogue)
      guihooks.trigger("mysummerChatChoices", {
        contactId = pending.contactId,
        choices = pending.choices,
        timeout = pending.timeout,
        smsId = pending.smsId,  -- Include smsId for UI to determine response type
      })
      log("I", logTag, string.format("Choices now active for %s (smsId: %s)", pending.contactId, tostring(pending.smsId)))
      table.insert(toRemove, i)
    end
  end

  -- Remove processed (in reverse order)
  for i = #toRemove, 1, -1 do
    table.remove(pendingChoicesQueue, toRemove[i])
  end
end

local function clearPendingChoices()
  state.pendingChoices = nil
end

local function getPendingChoices(contactId)
  if state.pendingChoices and state.pendingChoices.contactId == contactId then
    return state.pendingChoices.choices
  end
  return nil
end

-- ============================================================================
-- SCRIPTED DIALOGUE INTEGRATION (V3)
-- ============================================================================

-- Queue messages to send with typing delays
local pendingMessages = {}
local messageProcessingActive = false

local function queueMessage(contactId, messageData, delay)
  local sendAt = getTimestamp() + (delay or 0) / 1000
  table.insert(pendingMessages, {
    contactId = contactId,
    messageData = messageData,
    sendAt = sendAt,
  })
  -- Safe log (content might be bilingual table)
  local logContent = messageData.content
  if type(logContent) == "table" then
    logContent = logContent.es or logContent.en or "(empty)"
  end
  log("I", logTag, string.format("Message queued for %s, delay=%dms, content=%s",
      contactId, delay or 0, string.sub(logContent or "", 1, 30)))
end

-- Process pending messages (called from onUpdate)
local function processPendingMessages()
  if #pendingMessages == 0 then return end

  local now = getTimestamp()
  local toRemove = {}

  for i, pending in ipairs(pendingMessages) do
    if now >= pending.sendAt then
      -- Send the message
      local contactId = pending.contactId
      local msgData = pending.messageData

      -- Safe log (content might be bilingual table or string)
      local logContent = msgData.content
      if type(logContent) == "table" then
        logContent = logContent.es or logContent.en or "(empty)"
      end
      log("I", logTag, string.format("Processing message for %s: %s",
          contactId, string.sub(logContent or "", 1, 30)))

      -- Clear typing indicator
      setContactTyping(contactId, false)

      -- Localize content if it's bilingual
      local content = msgData.content
      if type(content) == "table" then
        content = resolveBilingualText(content)
      end

      -- Add the message
      addMessage(contactId, {
        sender = msgData.sender or contactId,
        senderType = msgData.senderType or "contact",
        content = content,
        contentType = "text",
      })

      -- Notify UI
      guihooks.trigger("mysummerChatConversationUpdated", {
        contactId = contactId,
        conversation = deepcopy(getOrCreateConversation(contactId)),
      })

      table.insert(toRemove, i)
    end
  end

  -- Remove processed messages (in reverse order to preserve indices)
  for i = #toRemove, 1, -1 do
    table.remove(pendingMessages, toRemove[i])
  end
end

-- Start a scripted V3 dialogue with a contact
local function startDialogue(contactId)
  log("I", logTag, "Starting V3 dialogue with: " .. tostring(contactId))

  -- Check if contact is disabled (disappeared / won't respond)
  if isContactDisabled(contactId) then
    log("I", logTag, "Contact " .. contactId .. " is disabled (will not respond)")
    return {
      success = false,
      error = "contact_disabled",
    }
  end

  local conv = getOrCreateConversation(contactId)
  local scriptState = conv.scriptState

  -- Check cooldown
  local lastCooldown = conversationCooldowns[contactId]
  if lastCooldown then
    local elapsed = getTimestamp() - lastCooldown
    if elapsed < DEFAULT_COOLDOWN then
      return {
        success = false,
        error = "cooldown",
        remainingTime = DEFAULT_COOLDOWN - elapsed,
      }
    end
  end

  -- Load contact data
  local contactData = loadContactFromJson(contactId)
  if not contactData then
    return {
      success = false,
      error = "no_contact_data",
    }
  end

  -- Get conversation for current level
  local conversationData, convId = getV3Conversation(contactId, scriptState)
  if not conversationData then
    log("W", logTag, "No available V3 conversation for " .. contactId)
    return {
      success = false,
      error = "no_conversation",
    }
  end

  -- Initialize script state for this conversation
  scriptState.activeScript = convId
  scriptState.currentPhase = "intro"
  scriptState.exchangeIndex = 1
  scriptState.sessionPoints = 0
  scriptState.currentExchanges = nil
  scriptState.currentBranches = nil
  scriptState.conversationData = conversationData
  scriptState.contactData = contactData

  -- Set active dialogue
  state.activeDialogue = {
    contactId = contactId,
    startedAt = getTimestamp(),
    conversationId = convId,
  }

  -- Unlock contact identity if first time
  unlockContact(contactId)

  -- Process intro phase
  local introPhase = conversationData.phases.intro
  if not introPhase or not introPhase.exchanges then
    return {
      success = false,
      error = "invalid_conversation",
    }
  end

  scriptState.currentExchanges = introPhase.exchanges
  scriptState.currentBranches = introPhase.branches or {}

  -- Add unlock message if this conversation has one
  if conversationData.unlockMessage then
    sendSystemMessage(conversationData.unlockMessage)
  end

  -- Process exchanges until we hit a choice
  local allMessages = {}
  local choices = nil
  local ended = false
  local cumulativeDelay = 0

  while scriptState.exchangeIndex <= #scriptState.currentExchanges do
    local exchange = scriptState.currentExchanges[scriptState.exchangeIndex]
    local result = processV3Exchange(exchange, scriptState, introPhase, contactData)

    -- Queue messages with typing delays
    for _, msg in ipairs(result.messages) do
      if msg.senderType == "contact" then
        -- Set typing indicator for contact messages
        local typingDelay = msg.typingDelay or 1000
        cumulativeDelay = cumulativeDelay + typingDelay

        -- Queue the message
        queueMessage(contactId, msg, cumulativeDelay)

        -- Show typing indicator (will be cleared when message sent)
        setContactTyping(contactId, true)

        -- Add small gap between messages
        cumulativeDelay = cumulativeDelay + 300
      end

      table.insert(allMessages, msg)
    end

    -- Handle memory from exchanges
    if result.setsMemory then
      for k, v in pairs(result.setsMemory) do
        scriptState.memory[k] = v
      end
    end

    if result.choices then
      -- Store choices for player to respond (with delay so they appear after messages)
      choices = result.choices
      setPendingChoices(contactId, choices, nil, cumulativeDelay + 500)
      break
    elseif result.endConversation then
      ended = true
      -- Handle end
      if result.rewards and result.rewards.xp then
        addContactXP(contactId, result.rewards.xp)
        scriptState.sessionPoints = scriptState.sessionPoints + result.rewards.xp
      end
      scriptState.completed[convId] = true
      if result.cooldown then
        conversationCooldowns[contactId] = getTimestamp()
      end
      break
    end

    scriptState.exchangeIndex = scriptState.exchangeIndex + 1
  end

  if ended then
    state.activeDialogue = nil
    scriptState.activeScript = nil
  end

  saveState()

  return {
    success = true,
    conversation = deepcopy(conv),
    contact = getContact(contactId),
    messages = allMessages,
    choices = choices,
    ended = ended,
    phase = scriptState.currentPhase,
    sessionPoints = scriptState.sessionPoints,
    isV3 = true,
  }
end

-- Continue dialogue after player choice
local function continueDialogue(contactId, choiceId)
  log("I", logTag, "Continue dialogue with " .. contactId .. ", choice: " .. tostring(choiceId))

  if not state.activeDialogue or state.activeDialogue.contactId ~= contactId then
    return {
      success = false,
      error = "no_active_dialogue",
    }
  end

  local conv = getOrCreateConversation(contactId)
  local scriptState = conv.scriptState

  if not scriptState.currentExchanges then
    return {
      success = false,
      error = "invalid_state",
    }
  end

  -- Get current exchange (should be a choice)
  local currentExchange = scriptState.currentExchanges[scriptState.exchangeIndex]
  if not currentExchange or currentExchange.type ~= "choice" then
    return {
      success = false,
      error = "no_choice_expected",
    }
  end

  -- Find selected choice
  local selectedChoice = nil
  for _, choice in ipairs(currentExchange.choices) do
    if choice.id == choiceId then
      selectedChoice = choice
      break
    end
  end

  if not selectedChoice then
    return {
      success = false,
      error = "invalid_choice",
    }
  end

  -- Clear pending choices
  clearPendingChoices()

  -- Award points
  local points = selectedChoice.points or 0
  scriptState.sessionPoints = scriptState.sessionPoints + points
  addContactXP(contactId, points)

  -- Apply narrative effects (affinity, ambition, caution, etc.)
  if selectedChoice.effects then
    applyEffects(selectedChoice.effects)
  end

  -- Auto-apply affinity based on points for teammates (rook, nova)
  -- This ensures relationship tracking even without explicit effects
  if points ~= 0 and (contactId == "rook" or contactId == "nova") then
    local affinityKey = contactId .. "_affinity"
    local autoEffects = { [affinityKey] = points }
    applyEffects(autoEffects)
  end

  -- Track player traits from choices
  if selectedChoice.traits then
    for _, trait in ipairs(selectedChoice.traits) do
      local traitKey = "trait_" .. trait
      local currentCount = state.affinityEffects[traitKey] or 0
      state.affinityEffects[traitKey] = currentCount + 1
    end
  end

  -- Store memory
  if selectedChoice.setsMemory then
    for k, v in pairs(selectedChoice.setsMemory) do
      scriptState.memory[k] = v
    end
  end

  -- Add player's response as a message
  local playerResponseText = getLocalizedText(selectedChoice.text)
  sendPlayerMessage(contactId, playerResponseText)

  local allMessages = {}
  local choices = nil
  local ended = false
  local cumulativeDelay = 500  -- Start with small delay after player message

  -- Handle choice result
  if selectedChoice.endConversation then
    ended = true
    if selectedChoice.result == "rejected" then
      -- Queue rejection response
      queueMessage(contactId, {
        sender = contactId,
        senderType = "contact",
        content = "...",
      }, cumulativeDelay)
    end
    if selectedChoice.cooldown then
      conversationCooldowns[contactId] = getTimestamp()
    end
  elseif selectedChoice.leadsTo and scriptState.currentBranches[selectedChoice.leadsTo] then
    -- Switch to branch
    scriptState.currentExchanges = scriptState.currentBranches[selectedChoice.leadsTo]
    scriptState.exchangeIndex = 1
  elseif selectedChoice.continueToPhase then
    -- Switch to next phase
    local nextPhase = selectedChoice.continueToPhase
    local conversationData = scriptState.conversationData
    local contactData = scriptState.contactData

    -- Add nexo (transition) if available
    local nexoType = "before" .. nextPhase:gsub("^%l", string.upper)
    local nexo = selectNexo(conversationData, nexoType)
    if nexo then
      queueMessage(contactId, {
        sender = contactId,
        senderType = "contact",
        content = nexo,
      }, cumulativeDelay)
      cumulativeDelay = cumulativeDelay + 1500
    end

    -- Switch phase
    local phaseData = conversationData.phases[nextPhase]
    if phaseData and phaseData.exchanges then
      scriptState.currentPhase = nextPhase
      scriptState.currentExchanges = phaseData.exchanges
      scriptState.currentBranches = phaseData.branches or {}
      scriptState.exchangeIndex = 1
    end
  else
    -- Continue to next exchange
    scriptState.exchangeIndex = scriptState.exchangeIndex + 1
  end

  -- Process exchanges until next choice or end
  if not ended then
    local contactData = scriptState.contactData
    local currentPhase = scriptState.conversationData.phases[scriptState.currentPhase]

    while scriptState.exchangeIndex <= #scriptState.currentExchanges do
      local exchange = scriptState.currentExchanges[scriptState.exchangeIndex]
      local result = processV3Exchange(exchange, scriptState, currentPhase, contactData)

      -- Queue messages with typing delays
      for _, msg in ipairs(result.messages) do
        if msg.senderType == "contact" then
          local typingDelay = msg.typingDelay or 1000
          cumulativeDelay = cumulativeDelay + typingDelay

          queueMessage(contactId, msg, cumulativeDelay)
          setContactTyping(contactId, true)

          cumulativeDelay = cumulativeDelay + 300
        end

        table.insert(allMessages, msg)
      end

      -- Handle memory
      if result.setsMemory then
        for k, v in pairs(result.setsMemory) do
          scriptState.memory[k] = v
        end
      end

      if result.choices then
        -- Store choices for player to respond (with delay so they appear after messages)
        choices = result.choices
        setPendingChoices(contactId, choices, nil, cumulativeDelay + 500)
        break
      elseif result.endConversation then
        ended = true

        -- Handle rewards
        if result.rewards and result.rewards.xp then
          addContactXP(contactId, result.rewards.xp)
          scriptState.sessionPoints = scriptState.sessionPoints + result.rewards.xp
        end

        -- Mark completed
        scriptState.completed[scriptState.activeScript] = true

        -- Add teaser
        if result.teaser then
          cumulativeDelay = cumulativeDelay + 500
          queueMessage(contactId, {
            sender = contactId,
            senderType = "contact",
            content = result.teaser,
          }, cumulativeDelay)
        end

        -- Add exit line
        local exitOutcome = "normal"
        if result.result == "success" then
          exitOutcome = scriptState.sessionPoints >= 50 and "positive" or "normal"
        elseif result.result == "rejected" or result.result == "failure" then
          exitOutcome = "negative"
        end
        local exitLine = selectExitLine(contactData, exitOutcome)
        if exitLine then
          cumulativeDelay = cumulativeDelay + 800
          queueMessage(contactId, {
            sender = contactId,
            senderType = "contact",
            content = exitLine,
          }, cumulativeDelay)
        end

        if result.cooldown then
          conversationCooldowns[contactId] = getTimestamp()
        end
        break
      end

      scriptState.exchangeIndex = scriptState.exchangeIndex + 1
    end

    -- Check if we ran out of exchanges without explicit end
    if scriptState.exchangeIndex > #scriptState.currentExchanges and not ended and not choices then
      -- Try moving to next phase automatically
      local phaseOrder = { "intro", "nudo", "desenlace" }
      local currentPhaseIndex = 1
      for i, p in ipairs(phaseOrder) do
        if p == scriptState.currentPhase then
          currentPhaseIndex = i
          break
        end
      end

      if currentPhaseIndex < #phaseOrder then
        local nextPhase = phaseOrder[currentPhaseIndex + 1]
        local conversationData = scriptState.conversationData

        local nexo = selectNexo(conversationData, "before" .. nextPhase:gsub("^%l", string.upper))
        if nexo then
          queueMessage(contactId, {
            sender = contactId,
            senderType = "contact",
            content = nexo,
          }, cumulativeDelay)
          cumulativeDelay = cumulativeDelay + 1500
        end

        local phaseData = conversationData.phases[nextPhase]
        if phaseData and phaseData.exchanges then
          scriptState.currentPhase = nextPhase
          scriptState.currentExchanges = phaseData.exchanges
          scriptState.currentBranches = phaseData.branches or {}
          scriptState.exchangeIndex = 1

          -- Continue processing recursively (simplified - in production use iteration)
          return continueDialogue(contactId, nil)
        end
      else
        -- No more phases, end naturally
        ended = true
        scriptState.completed[scriptState.activeScript] = true
      end
    end
  end

  if ended then
    state.activeDialogue = nil
    scriptState.activeScript = nil
  end

  saveState()

  return {
    success = true,
    messages = allMessages,
    choices = choices,
    ended = ended,
    phase = scriptState.currentPhase,
    sessionPoints = scriptState.sessionPoints,
  }
end

-- Get current dialogue state
local function getDialogueState(contactId)
  local conv = state.conversations[contactId]
  if not conv then return nil end

  return {
    scriptState = deepcopy(conv.scriptState),
    isActive = state.activeDialogue and state.activeDialogue.contactId == contactId,
    pendingChoices = getPendingChoices(contactId),
    isV3 = conv.scriptState.activeScript ~= nil,
  }
end

-- Check if contact has available conversation
local function hasAvailableDialogue(contactId)
  local conv = getOrCreateConversation(contactId)
  local scriptState = conv.scriptState

  -- Check cooldown
  local lastCooldown = conversationCooldowns[contactId]
  if lastCooldown then
    local elapsed = getTimestamp() - lastCooldown
    if elapsed < DEFAULT_COOLDOWN then
      return false
    end
  end

  -- Check for available V3 conversation
  local conversationData = getV3Conversation(contactId, scriptState)
  return conversationData ~= nil
end

-- ============================================================================
-- AVAILABILITY CHECK (integrates with DeepWeb)
-- ============================================================================

local function isContactAvailable(contactId)
  -- Check if contact is unlocked via DeepWeb system
  if career_modules_mysummerDeepWeb then
    return career_modules_mysummerDeepWeb.isContactAvailable(contactId)
  end

  -- Fallback: system contact always available
  local contact = state.contacts[contactId]
  return contact and contact.isSystem
end

-- ============================================================================
-- SMS EVENT SYSTEM (NEW - NARRATIVE SMS MESSAGES)
-- ============================================================================

-- SMS message definitions triggered by narrative events
-- Extracted from NARRATIVA_REEDIT.md
local eventSMS = {
  -- FASE 0: El Peso del Silencio
  phase0_race1_post = {
    id = "sms_phase0_race1_post",
    contactId = "ghost",
    message = {
      es = "No ha estado mal, Miller. Tienes ese tic en las curvas que tenía tu abuelo... entras demasiado rápido. Vigila la temperatura del aceite, no queremos incendios tan pronto.",
      en = "Not bad, Miller. You have that tic in corners that your grandfather had... you enter too fast. Watch the oil temperature, we don't want fires so soon.",
    },
    choices = {
      {
        id = "who_are_you",
        text = {es = "¿Quién eres?", en = "Who are you?"},
        effects = {ghost_trust = 5},
        response = {
          es = "Eso no importa ahora. Solo llámame Ghost. He oído que quieres correr en serio. Pero para eso, vas a necesitar algo más que un coche viejo y unas ganas enormes.",
          en = "That doesn't matter now. Just call me Ghost. I heard you want to race seriously. But for that, you'll need more than an old car and huge desire.",
        },
      },
    },
  },

  phase0_race2_post = {
    id = "sms_phase0_race2_post",
    contactId = "nova",
    message = {
      es = "Tienes manos, Miller. Pero ese coche es un ancla. Si quieres subir de nivel, deja de jugar con chatarra de museo.",
      en = "You've got hands, Miller. But that car is an anchor. If you want to level up, stop playing with museum scrap.",
    },
  },

  phase0_race3_post = {
    id = "sms_phase0_race3_post",
    contactId = "rook",
    message = {
      es = "Eh, lo de antes ha sido un poco sucio, ¿no? Nova dice que tienes potencial, pero a mí me pareces un peligro público. Ven a los muelles, Ghost tiene algo que proponerte.",
      en = "Hey, that was a bit dirty back there, wasn't it? Nova says you have potential, but you seem like a public hazard to me. Come to the docks, Ghost has something to propose.",
    },
  },

  -- FASE 1: Origins
  phase1_race1 = {
    id = "sms_phase1_race1",
    contactId = "rook",
    message = {
      es = "Buena carrera, de verdad. Me gusta que no hayas entrado en las provocaciones de Nova. Ella es... intensa. Cree que todo es una película de acción, pero yo valoro a alguien que sabe cuándo soltar el acelerador para no perder el control. Si algún día quieres que te enseñe cómo ajustar la caída de las ruedas para este tipo de asfalto, pásate por mi garaje. Me vendría bien hablar con alguien que no intente batir un récord cada cinco minutos.",
      en = "Good race, really. I like that you didn't fall for Nova's provocations. She's... intense. Thinks everything is an action movie, but I value someone who knows when to ease off the throttle to avoid losing control. If you ever want me to teach you how to adjust wheel camber for this kind of asphalt, stop by my garage. I could use talking to someone who doesn't try to break a record every five minutes.",
    },
    choices = {
      {
        id = "support_rook",
        text = {es = "Me gusta tu estilo, Rook. La técnica gana carreras, no solo la suerte.", en = "I like your style, Rook. Technique wins races, not just luck."},
        effects = {rook_affinity = 10, loyalty = 5},
        response = {
          es = "Exacto. Me alegra que alguien lo entienda. Estamos en contacto.",
          en = "Exactly. I'm glad someone gets it. We'll be in touch.",
        },
      },
      {
        id = "neutral",
        text = {es = "Solo intento no destrozar el coche del abuelo.", en = "Just trying not to wreck grandpa's car."},
        effects = {caution = 5},
        response = {
          es = "Lo entiendo. Es una responsabilidad. Nos vemos en la próxima.",
          en = "I understand. It's a responsibility. See you at the next one.",
        },
      },
    },
  },

  phase1_race2 = {
    id = "sms_phase1_race2",
    contactId = "nova",
    message = {
      es = "Rook se está volviendo un blando, Miller. Esa 'charla técnica' casi me duerme en la recta. Tiene un talento increíble, pero se autoimpone tantas reglas que se frena a sí mismo. Y lo peor es que intenta frenarme a mí también. Tú tienes algo que él no tiene... esa chispa de Miller. No dejes que él te la apague con sus manuales de taller. Mañana vamos a correr de verdad, sin sermones.",
      en = "Rook's going soft, Miller. That 'technical talk' almost put me to sleep on the straight. He's got incredible talent, but he imposes so many rules on himself that he holds himself back. And the worst part is he tries to hold me back too. You have something he doesn't... that Miller spark. Don't let him snuff it out with his workshop manuals. Tomorrow we're racing for real, no sermons.",
    },
  },

  phase1_race3 = {
    id = "sms_phase1_race3",
    contactId = "rook",
    message = {
      es = "Siento si te hemos molestado hoy con nuestras discusiones. Las cosas están... complicadas. Nova quiere ir más rápido de lo que nuestro equipo puede permitirnos, y yo solo intento que no nos estrellamos contra un muro, literal o figuradamente. Eres un buen tipo, Miller. Me gustaría que nos viéramos fuera de las carreras. Ghost me ha dicho que necesitas a alguien que sepa de electrónica. Te he pasado el contacto de Techie. Es un tipo raro, pero si alguien puede hacer que ese ETK-I hable, es él.",
      en = "Sorry if we bothered you today with our arguments. Things are... complicated. Nova wants to go faster than our team can handle, and I'm just trying to keep us from crashing into a wall, literally or figuratively. You're a good guy, Miller. I'd like to see you outside of races. Ghost told me you need someone who knows electronics. I've passed you Techie's contact. He's a weird guy, but if anyone can make that ETK-I talk, it's him.",
    },
  },

  -- FASE 2: The Split
  phase2_race1 = {
    id = "sms_phase2_race1",
    contactId = "nova",
    message = {
      es = "Rook me está asfixiando, Miller. Cree que soy una aprendiz que necesita que le miren la presión de los neumáticos cada cinco minutos. Tú entiendes que esto va de adrenalina, no de libros de mantenimiento. He oído que Ghost te va a presentar a alguien de la vieja escuela. Ten cuidado, esa gente vive en el pasado.",
      en = "Rook is suffocating me, Miller. He thinks I'm an apprentice who needs her tire pressure checked every five minutes. You understand this is about adrenaline, not maintenance manuals. I heard Ghost is introducing you to someone from the old school. Be careful, those people live in the past.",
    },
    choices = {
      {
        id = "support_ambition",
        text = {es = "A veces hay que romper algo para saber dónde está el límite.", en = "Sometimes you have to break something to know where the limit is."},
        effects = {ambition = 10, nova_affinity = 5},
        response = {
          es = "Exacto. Alguien que habla mi idioma.",
          en = "Exactly. Someone who speaks my language.",
        },
      },
      {
        id = "support_rook",
        text = {es = "Rook solo se preocupa por ti, a su manera.", en = "Rook just cares about you, in his own way."},
        effects = {loyalty = 5},
        response = {
          es = "Su manera me está haciendo lenta. Y eso es lo peor que me pueden hacer.",
          en = "His way is making me slow. And that's the worst thing anyone can do to me.",
        },
      },
    },
  },

  phase2_race2 = {
    id = "sms_phase2_race2",
    contactId = "ghost",
    message = {
      es = "Le has gustado. Dice que tienes el mismo giro de muñeca que el viejo. Mañana te espero en el desguace del sur. Trae el coche, Muscle quiere ver si lo que hay bajo el capó es tan bueno como lo que hay tras el volante.",
      en = "She liked you. Says you have the same wrist turn as the old man. I'll be waiting for you tomorrow at the south scrapyard. Bring the car, Muscle wants to see if what's under the hood is as good as what's behind the wheel.",
    },
  },

  -- FASE 3: The Crisis
  phase3_race3 = {
    id = "sms_phase3_race3",
    contactId = "nova",
    message = {
      es = "No le digas nada a Rook de lo que te he dicho. Él no lo entendería. Cree que nos protege, pero solo nos está enterrando en este pueblo. Ghost me ha pasado el contacto de Shadow. Dice que tiene piezas que Rook nunca me dejaría montar. Voy a ir a verle. Deberías venir conmigo.",
      en = "Don't tell Rook what I told you. He wouldn't understand. He thinks he's protecting us, but he's just burying us in this town. Ghost gave me Shadow's contact. Says he has parts Rook would never let me install. I'm going to see him. You should come with me.",
    },
  },

  -- FASE 4: The Split (Ruptura)
  phase4_race3 = {
    id = "sms_phase4_race3",
    contactId = "rook",
    message = {
      es = "Se acabó. No puedo ayudar a alguien que no quiere ser ayudado. Si vas a seguir con ella y con Shadow, hazlo, pero no esperes que vuelva a arreglar tus desastres. Me voy a centrar en mi propio coche. Nos vemos en la pista, Miller. Y esta vez, no voy a frenar para dejarte pasar.",
      en = "It's over. I can't help someone who doesn't want to be helped. If you're going to continue with her and Shadow, do it, but don't expect me to fix your messes again. I'm going to focus on my own car. See you on the track, Miller. And this time, I'm not braking to let you pass.",
    },
  },

  -- FASE 6: Copa Covet (based on romance choice)
  phase6_covet_nova_mock = {
    id = "sms_phase6_nova_mock",
    contactId = "nova",
    message = {
      es = "Vaya, vaya. El caballero andante te dejó tirado en la cuneta, ¿eh? Te dije que Rook haría cualquier cosa por 'proteger' su visión del mundo. Espero que ese Covet sea cómodo, porque es lo único que vas a conducir en mucho tiempo.",
      en = "Well, well. The knight in shining armor left you stranded on the roadside, huh? I told you Rook would do anything to 'protect' his worldview. I hope that Covet is comfortable, because it's all you're going to drive for a long time.",
    },
  },

  phase6_covet_rook_pity = {
    id = "sms_phase6_rook_pity",
    contactId = "rook",
    message = {
      es = "Te lo advertí, Miller. La ambición de Nova no tiene fondo. Te usó para ganar el rally y luego te vendió a Shadow para saldar sus deudas. Lo siento por el coche del abuelo... no merecía terminar así.",
      en = "I warned you, Miller. Nova's ambition has no bottom. She used you to win the rally and then sold you to Shadow to settle her debts. I'm sorry about your grandfather's car... it didn't deserve to end like this.",
    },
  },

  -- FASE 7: Clasificatorias
  phase7_clasif2 = {
    id = "sms_phase7_anonymous",
    contactId = "system",  -- Anonymous sender
    message = {
      es = "No todo lo que brilla es oro, ni todo lo que Techie ve en su pantalla es verdad. Shadow es un maestro de los espejismos digitales. Si quieres encontrar tu coche, busca en el contenedor 402 del puerto, no en las cuentas bancarias de quien te quiere.",
      en = "Not everything that glitters is gold, nor everything Techie sees on his screen is true. Shadow is a master of digital mirages. If you want to find your car, look in container 402 at the port, not in the bank accounts of those who love you.",
    },
  },
}

-- Trigger SMS message based on narrative event
local function triggerSMS(eventId)
  if not career_career or not career_career.isActive() then
    log("D", logTag, "SMS skipped (career not active): " .. tostring(eventId))
    return false
  end

  -- Skip SMS sending during save load to prevent spam
  if state.isLoading then
    log("D", logTag, "SMS skipped (loading in progress): " .. tostring(eventId))
    return false
  end

  local smsData = eventSMS[eventId]
  if not smsData then
    log("D", logTag, "No SMS defined for event: " .. tostring(eventId))
    return false
  end

  -- Check if already triggered (using SMS id, not event id)
  -- This allows the same event to be called multiple times but each unique SMS only sends once
  local smsId = smsData.id or eventId
  if state.triggeredSMS[smsId] then
    log("D", logTag, "SMS already triggered: " .. tostring(smsId) .. " (event: " .. tostring(eventId) .. ")")
    return false
  end

  log("I", logTag, "Queuing SMS for event: " .. tostring(eventId) .. " (SMS id: " .. tostring(smsId) .. ")")

  -- Mark as triggered (using SMS id)
  state.triggeredSMS[smsId] = true

  -- Unlock contact (conditionally based on phase)
  -- In Phase 0: Only Ghost should be unlocked
  -- In Phase 1+: Nova, Rook, and others can be unlocked
  local currentPhase = getCurrentNarrativePhase()
  local canUnlock = true

  if currentPhase == 0 then
    -- Phase 0: Only allow Ghost to be unlocked
    if smsData.contactId ~= "ghost" then
      canUnlock = false
      log("I", logTag, "Contact " .. smsData.contactId .. " NOT unlocked (Phase 0 - only Ghost accessible)")
    end
  end

  if canUnlock then
    unlockContact(smsData.contactId)
  end

  -- Resolve bilingual message
  local messageText = resolveBilingualText(smsData.message)

  -- Check if this SMS has choices
  if smsData.choices and #smsData.choices > 0 then
    -- Send message with choices
    local choices = {}
    for _, choiceData in ipairs(smsData.choices) do
      table.insert(choices, {
        id = choiceData.id,
        text = resolveBilingualText(choiceData.text),
        effects = choiceData.effects,
        response = resolveBilingualText(choiceData.response),
      })
    end

    -- Send the initial message
    sendContactMessage(smsData.contactId, messageText, {
      choices = choices,
      silent = false,
    })

    -- Set up choices for UI
    local uiChoices = {}
    for _, choiceData in ipairs(choices) do
      table.insert(uiChoices, {
        id = choiceData.id,
        text = choiceData.text,
      })
    end
    setPendingChoices(smsData.contactId, uiChoices, nil, 1000, smsId)

  else
    -- Simple message without choices
    sendContactMessage(smsData.contactId, messageText, {
      silent = false,
    })
  end

  log("I", logTag, "Triggered SMS: " .. eventId .. " from " .. smsData.contactId)
  saveState()
  return true
end

-- Handle SMS choice response
local function respondToSMS(contactId, choiceId)
  -- Get the SMS ID from pending choices
  local smsId = state.pendingChoices and state.pendingChoices.smsId
  if not smsId then
    log("W", logTag, "No pending choices found for contact: " .. contactId)
    return
  end

  -- Find the SMS by ID
  local smsData = nil
  for _, data in pairs(eventSMS) do
    if data.id == smsId then
      smsData = data
      break
    end
  end

  if not smsData then
    log("W", logTag, "No SMS found with ID: " .. tostring(smsId))
    return
  end

  -- Verify contactId matches
  if smsData.contactId ~= contactId then
    log("W", logTag, "SMS contactId mismatch: expected " .. smsData.contactId .. ", got " .. contactId)
    return
  end

  -- Find the selected choice
  local selectedChoice = nil
  for _, choice in ipairs(smsData.choices) do
    if choice.id == choiceId then
      selectedChoice = choice
      break
    end
  end

  if not selectedChoice then
    log("W", logTag, "Invalid choice ID: " .. choiceId)
    return
  end

  -- Send player response
  local responseText = resolveBilingualText(selectedChoice.text)
  sendPlayerMessage(contactId, responseText)

  -- Apply effects
  if selectedChoice.effects then
    applyEffects(selectedChoice.effects)
  end

  -- Send contact's response
  if selectedChoice.response then
    local contactResponse = resolveBilingualText(selectedChoice.response)
    -- Queue with delay to simulate typing
    queueMessage(contactId, {
      sender = contactId,
      senderType = "contact",
      content = contactResponse,
    }, 2000)
    setContactTyping(contactId, true, 2)
  end

  -- Clear pending choices
  clearPendingChoices()

  log("I", logTag, "SMS choice selected: " .. choiceId .. " for contact " .. contactId)
  saveState()
end

-- Integration with narrative system
local function onNarrativeEvent(eventId)
  -- Map narrative events to SMS triggers
  -- This is called by mysummerNarrative.lua when events fire
  return triggerSMS(eventId)
end

-- Reset triggered state for a specific event (for race replay)
local function resetTriggered(eventId)
  local sms = eventSMS[eventId]
  if sms and sms.id then
    state.triggeredSMS[sms.id] = nil
    log("D", logTag, "Reset triggered state for SMS: " .. sms.id)
  end
end

-- ============================================================================
-- PERSISTENCE
-- ============================================================================

loadState = function()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  -- Set loading flag to prevent message spam during load
  state.isLoading = true

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath)

  if data then
    state.conversations = data.conversations or {}
    state.contacts = data.contacts or {}
    state.nextMessageId = data.nextMessageId or 1
    state.nextConversationId = data.nextConversationId or 1
    state.unreadByContact = data.unreadByContact or {}
    state.affinityEffects = data.affinityEffects or {}
    state.triggeredSMS = data.triggeredSMS or {}

    -- Recalculate total unread
    state.totalUnread = 0
    for _, count in pairs(state.unreadByContact) do
      state.totalUnread = state.totalUnread + count
    end

    log("I", logTag, "Loaded chat state with " .. state.totalUnread .. " unread messages")
  end

  -- Clear loading flag after a delay to allow narrative system to settle
  -- This prevents re-triggering of already-sent SMS during load
  state.isLoading = false
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
    conversations = state.conversations,
    contacts = state.contacts,
    nextMessageId = state.nextMessageId,
    nextConversationId = state.nextConversationId,
    unreadByContact = state.unreadByContact,
    affinityEffects = state.affinityEffects,
    triggeredSMS = state.triggeredSMS,
  }

  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("I", logTag, "Saved chat state")
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Chat system loaded")
end

-- Forward declarations for dialogue system (used in onCareerActive, defined later)
local dialogueQueue = {}
local dialogueActive = false

local function onCareerActive(active)
  if active then
    loadState()

    -- Clear message queues on load (prevent processing old queued messages)
    pendingMessages = {}
    pendingChoicesQueue = {}
    dialogueQueue = {}

    -- Initialize system contact
    initializeContact("system")
    state.contacts["system"].isUnlocked = true

    log("I", logTag, "Chat system activated")
  else
    -- Reset state
    state.conversations = {}
    state.contacts = {}
    state.nextMessageId = 1
    state.nextConversationId = 1
    state.unreadByContact = {}
    state.totalUnread = 0
    state.activeDialogue = nil
    state.pendingChoices = nil
    state.triggeredSMS = {}
    state.isLoading = false
    pendingMessages = {}
    pendingChoicesQueue = {}
    dialogueQueue = {}
    contactDataCache = {}
    conversationCooldowns = {}
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

-- Process pending messages each frame
local function onUpdate(dtReal)
  if not career_career or not career_career.isActive() then return end

  processPendingMessages()
  processPendingChoices()
  processDialogueQueue()
end

-- ============================================================================
-- ON-SCREEN DIALOGUE SYSTEM
-- ============================================================================
-- Shows narrative dialogue at the bottom of the screen (visual novel style)
-- (dialogueQueue and dialogueActive are forward-declared before onCareerActive)

-- Show dialogue messages on screen (immediate)
local function showDialogue(contactId, messages)
  if not messages or #messages == 0 then return false end

  local contact = getContact(contactId)
  local formattedMessages = {}

  -- Handle special case for internal monologues (player thoughts)
  local isMonologue = (contactId == "player" or not contact)
  local displayName = isMonologue and "" or (contact and contact.displayName or contactId)
  local isUnlocked = isMonologue and true or (contact and contact.isUnlocked or false)

  for _, msg in ipairs(messages) do
    local content = msg
    local emotion = nil
    if type(msg) == "table" then
      -- Check if it's a structured message with content/text/emotion
      if msg.content or msg.text then
        content = msg.content or msg.text
        emotion = msg.emotion
      -- Otherwise, treat the entire table as bilingual text {es="...", en="..."}
      else
        content = msg
        emotion = nil
      end
    end

    -- Resolve bilingual text to current language
    content = resolveBilingualText(content)

    table.insert(formattedMessages, {
      contactId = contactId,
      contactName = displayName,
      isUnlocked = isUnlocked,
      content = content,  -- Now a resolved string
      emotion = emotion, -- pass emotion to UI (defaults to 'standard' in Vue)
    })
  end

  dialogueActive = true

  if guihooks then
    guihooks.trigger("mysummerDialogueShow", {
      messages = formattedMessages,
    })
  end

  log("I", logTag, "Showing dialogue from " .. contactId .. " (" .. #formattedMessages .. " messages)")
  return true
end

-- Show a single dialogue message
local function showDialogueMessage(contactId, content)
  return showDialogue(contactId, { content })
end

-- Queue dialogue to show after current one finishes
-- Also adds messages to chat history so they appear in the phone app
local function queueDialogue(contactId, messages, delay)
  -- Skip during load to prevent message spam
  if state.isLoading then
    log("I", logTag, "Dialogue queuing skipped (loading in progress)")
    return
  end

  -- First, ensure contact is unlocked so messages can be received
  unlockContact(contactId)

  -- Add messages to chat with typing delays
  local baseDelay = delay or 0
  local currentDelay = baseDelay

  for i, msg in ipairs(messages) do
    local content = msg
    local speaker = contactId
    if type(msg) == "table" then
      content = msg.content or msg.text or msg[1] or ""
      speaker = msg.speaker or contactId
    end

    -- Resolve bilingual text to current language
    content = resolveBilingualText(content)

    -- Only queue messages from the contact (not player messages)
    if speaker ~= "player" and content and content ~= "" then
      -- Calculate typing delay based on content length
      local typingDelay = math.min(string.len(content) * 40 + 500, 3000)

      -- Queue the message with proper format
      queueMessage(contactId, {
        content = content,
        sender = speaker,
        senderType = "contact",
      }, currentDelay)

      -- Set typing indicator for this contact
      setContactTyping(contactId, true, typingDelay / 1000)

      -- Add delay for next message (typing + pause between messages)
      currentDelay = currentDelay + typingDelay + 800
    end
  end

  -- Also queue for screen display (overlay dialogue) - optional
  -- Only show overlay if messages array has more than 1 message (narrative scenes)
  if #messages > 1 then
    table.insert(dialogueQueue, {
      contactId = contactId,
      messages = messages,
      delay = delay or 0,
      timestamp = getTimestamp(),
    })
  end

  log("I", logTag, "Queued dialogue from " .. contactId .. " (" .. #messages .. " messages to chat)")
end

-- Hide the current dialogue
local function hideDialogue()
  dialogueActive = false
  if guihooks then
    guihooks.trigger("mysummerDialogueHide", {})
  end
end

-- Show dialogue and also add to chat history (silent - no toasts)
local function showDialogueAndChat(contactId, messages)
  -- First add to chat history (silently - no toast notifications)
  for _, msg in ipairs(messages) do
    local content = msg
    if type(msg) == "table" then
      content = msg.content or msg.text or msg[1] or ""
    end
    sendContactMessage(contactId, content, { contentType = "text", silent = true })
  end

  -- Then show on screen
  showDialogue(contactId, messages)
end

-- Process dialogue queue (called from onUpdate)
processDialogueQueue = function()
  if dialogueActive or #dialogueQueue == 0 then return end

  local next = dialogueQueue[1]
  local now = getTimestamp()

  if now >= next.timestamp + next.delay then
    table.remove(dialogueQueue, 1)
    showDialogue(next.contactId, next.messages)
  end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

-- Conversation API
M.getConversations = getConversations
M.getConversation = getConversation

-- Message API
M.sendContactMessage = sendContactMessage
M.sendPlayerMessage = sendPlayerMessage
M.sendSystemMessage = sendSystemMessage
M.markAsRead = markAsRead
M.getUnreadCounts = getUnreadCounts

-- Contact API
M.getContact = getContact
M.getAllContacts = getAllContacts
M.unlockContact = unlockContact
M.isContactUnlocked = isContactUnlocked
M.isContactAvailable = isContactAvailable
M.getContactDisplayName = getContactDisplayName
M.disableContact = disableContact
M.enableContact = enableContact
M.isContactDisabled = isContactDisabled

-- Typing indicators
M.setContactTyping = setContactTyping
M.isContactTyping = isContactTyping

-- Choices/Dialogue (V3 integration)
M.setPendingChoices = setPendingChoices
M.clearPendingChoices = clearPendingChoices
M.getPendingChoices = getPendingChoices
M.startDialogue = startDialogue
M.continueDialogue = continueDialogue
M.getDialogueState = getDialogueState
M.hasAvailableDialogue = hasAvailableDialogue

-- V3 helpers
M.isV3Contact = isV3Contact
M.getContactLevel = getContactLevel
M.getContactXP = getContactXP
M.getCurrentNarrativePhase = getCurrentNarrativePhase

-- Affinity/Effects system
M.applyEffects = applyEffects
M.getEffectValue = getEffectValue
M.getAllEffects = getAllEffects
M.getTeammateAlignment = getTeammateAlignment
M.getPlayerApproach = getPlayerApproach

-- On-screen dialogue
M.showDialogue = showDialogue
M.showDialogueMessage = showDialogueMessage
M.showDialogueAndChat = showDialogueAndChat
M.queueDialogue = queueDialogue
M.hideDialogue = hideDialogue

-- Mission status tracking
M.onMissionStatusChanged = function(data)
  if not data or not data.missionId then return end
  local found = false
  for _, conv in pairs(state.conversations) do
    for _, msg in ipairs(conv.messages or {}) do
      if msg.actionData and msg.actionData.missionId == data.missionId then
        msg.actionStatus = data.status
        if data.status == "active" then
          msg.actionCompleted = true
        end
        found = true
      end
    end
  end
  if found then
    saveState()
    -- Notify UI so open conversations refresh
    guihooks.trigger("mysummerChatMissionStatusChanged", data)
  end
end

-- SMS event system (NEW)
M.triggerSMS = triggerSMS
M.respondToSMS = respondToSMS
M.onNarrativeEvent = onNarrativeEvent
M.resetTriggered = resetTriggered

-- Lifecycle hooks
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onUpdate = onUpdate

return M
