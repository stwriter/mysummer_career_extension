-- MySummer Chat System
-- Unified chat replacing email and DeepWeb conversations
-- WhatsApp-style messaging with contacts

local M = {}
M.moduleName = "career_modules_mysummerChat"

M.dependencies = {
  "career_career",
  "career_saveSystem",
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

-- ============================================================================
-- CONTACT DEFINITIONS
-- ============================================================================

-- Contact IDs and avatars (non-localized)
local contactIds = { "ghost", "techie", "muscle", "import", "shadow", "system" }

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

  -- Check required memory
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

    -- Process placeholders
    local text = exchange.text
    text = processContextTransition(text, currentPhase, memory)

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
  end
end

local function isContactUnlocked(contactId)
  initializeContact(contactId)
  return state.contacts[contactId] and state.contacts[contactId].isUnlocked
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
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = tr("mysummer.notifications.newMessage", "New Message"),
      msg = getContactDisplayName(contactId) .. ": " .. string.sub(content, 1, 30),
    })
  end

  log("I", logTag, "Contact message from " .. contactId .. ": " .. string.sub(content, 1, 30))

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

  log("I", logTag, "Player message to " .. contactId .. ": " .. string.sub(content, 1, 30))

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

-- ============================================================================
-- CHOICES / DIALOGUE
-- ============================================================================

local function setPendingChoices(contactId, choices, timeout)
  state.pendingChoices = {
    contactId = contactId,
    choices = choices,
    timeout = timeout,
    setAt = getTimestamp(),
  }

  guihooks.trigger("mysummerChatChoices", {
    contactId = contactId,
    choices = choices,
    timeout = timeout,
  })
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
  table.insert(pendingMessages, {
    contactId = contactId,
    messageData = messageData,
    sendAt = getTimestamp() + (delay or 0) / 1000,  -- Convert ms to seconds
  })
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

      -- Clear typing indicator
      setContactTyping(contactId, false)

      -- Add the message
      addMessage(contactId, {
        sender = msgData.sender or contactId,
        senderType = msgData.senderType or "contact",
        content = msgData.content,
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
      -- Store choices for player to respond
      choices = result.choices
      setPendingChoices(contactId, choices)
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

  -- Store memory
  if selectedChoice.setsMemory then
    for k, v in pairs(selectedChoice.setsMemory) do
      scriptState.memory[k] = v
    end
  end

  -- Add player's response as a message
  sendPlayerMessage(contactId, selectedChoice.text)

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
        choices = result.choices
        setPendingChoices(contactId, choices)
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
-- PERSISTENCE
-- ============================================================================

loadState = function()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath)

  if data then
    state.conversations = data.conversations or {}
    state.contacts = data.contacts or {}
    state.nextMessageId = data.nextMessageId or 1
    state.nextConversationId = data.nextConversationId or 1
    state.unreadByContact = data.unreadByContact or {}

    -- Recalculate total unread
    state.totalUnread = 0
    for _, count in pairs(state.unreadByContact) do
      state.totalUnread = state.totalUnread + count
    end

    log("I", logTag, "Loaded chat state with " .. state.totalUnread .. " unread messages")
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
    conversations = state.conversations,
    contacts = state.contacts,
    nextMessageId = state.nextMessageId,
    nextConversationId = state.nextConversationId,
    unreadByContact = state.unreadByContact,
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

local function onCareerActive(active)
  if active then
    loadState()

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
    pendingMessages = {}
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
  processDialogueQueue()
end

-- ============================================================================
-- ON-SCREEN DIALOGUE SYSTEM
-- ============================================================================
-- Shows narrative dialogue at the bottom of the screen (visual novel style)

local dialogueQueue = {}
local dialogueActive = false

-- Show dialogue messages on screen (immediate)
local function showDialogue(contactId, messages)
  if not messages or #messages == 0 then return false end

  local contact = getContact(contactId)
  local formattedMessages = {}

  for _, msg in ipairs(messages) do
    local content = msg
    if type(msg) == "table" then
      content = msg.content or msg.text or msg[1] or ""
    end

    table.insert(formattedMessages, {
      contactId = contactId,
      contactName = contact.displayName or contactId,
      isUnlocked = contact.isUnlocked,
      content = content,
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
local function queueDialogue(contactId, messages, delay)
  table.insert(dialogueQueue, {
    contactId = contactId,
    messages = messages,
    delay = delay or 0,
    timestamp = getTimestamp(),
  })
  log("I", logTag, "Queued dialogue from " .. contactId)
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

-- Typing indicators
M.setContactTyping = setContactTyping

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

-- On-screen dialogue
M.showDialogue = showDialogue
M.showDialogueMessage = showDialogueMessage
M.showDialogueAndChat = showDialogueAndChat
M.queueDialogue = queueDialogue
M.hideDialogue = hideDialogue

-- Lifecycle hooks
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onUpdate = onUpdate

return M
