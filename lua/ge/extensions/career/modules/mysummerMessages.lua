-- MySummer Messages System
-- Handles email/message communication from contacts
-- Provides missions and story content

local M = {}
M.moduleName = "career_modules_mysummerMessages"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerChat",
}

local logTag = "mysummerMessages"
local saveFile = "mysummer_messages.json"

-- ============================================================================
-- LOCALIZATION
-- ============================================================================

local function tr(key, default)
  return translateLanguage(key, default or key)
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  messages = {},  -- Array of message objects
  nextMessageId = 1,
  unreadCount = 0,
}

-- ============================================================================
-- MESSAGE DEFINITIONS
-- ============================================================================

-- Message templates that can be triggered by events
local messageTemplates = {
  -- Anonymous tip about the deep web (sent on first purchase)
  ghost_intro = {
    from = "unknown",
    fromName = "???",
    subject = "Someone's watching...",
    body = [[You don't know me. But I know you.

Saw you picking up parts for that ETK project. Word travels fast in certain circles.

If you want the REAL parts - the ones that actually make a difference - you're shopping at the wrong places. SpeedParts is for amateurs.

There's a place on the deep web. Silk Road. That's where the serious builders go.

Look for someone called "Ghost". Tell him I sent you. Or don't. He already knows.

This message will not appear in your sent folder. Don't try to reply.

- A friend]],
    icon = "[?]",
    priority = "high",
  },

  -- Welcome message from the system
  welcome = {
    from = "system",
    fromName = "MySummer Career",
    subject = "Welcome to West Coast",
    body = [[Welcome to West Coast USA!

Your ETK I-Series project car is waiting at your garage. It's a bit of a fixer-upper, but with the right parts and some work, it could be something special.

Here's what you need to know:
- SpeedParts.com sells new OEM and performance parts
- PartsBay has used parts from local sellers
- Check your computer regularly for updates

Good luck with your build!

- The MySummer Team]],
    icon = "[i]",
    priority = "normal",
  },
}

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

local function loadState()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath) or {}

  state.messages = data.messages or {}
  state.nextMessageId = data.nextMessageId or 1
  state.unreadCount = data.unreadCount or 0

  -- Recalculate unread count
  state.unreadCount = 0
  for _, msg in ipairs(state.messages) do
    if not msg.read then
      state.unreadCount = state.unreadCount + 1
    end
  end

  log("I", logTag, "Loaded " .. #state.messages .. " messages (" .. state.unreadCount .. " unread)")
end

local function saveState(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  savePath = currentSavePath or savePath
  if not savePath then return end

  -- Ensure directory exists
  local dirPath = savePath .. "/career/mysummer"
  if not FS:directoryExists(dirPath) then
    FS:directoryCreate(dirPath, true)
  end

  local filePath = dirPath .. "/" .. saveFile
  local data = {
    messages = state.messages,
    nextMessageId = state.nextMessageId,
    unreadCount = state.unreadCount,
  }
  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("I", logTag, "Saved " .. #state.messages .. " messages")
end

-- ============================================================================
-- MESSAGE FUNCTIONS
-- ============================================================================

-- Send a new message from a template
local function sendMessage(templateId, customData)
  local template = messageTemplates[templateId]
  if not template then
    log("W", logTag, "Unknown message template: " .. tostring(templateId))
    return nil
  end

  local message = {
    id = state.nextMessageId,
    templateId = templateId,
    from = template.from,
    fromName = template.fromName,
    subject = template.subject,
    body = template.body,
    icon = template.icon or "[*]",
    priority = template.priority or "normal",
    timestamp = os.time(),
    read = false,
    -- Custom data can override template fields
    customData = customData,
  }

  -- Apply custom data
  if customData then
    if customData.subject then message.subject = customData.subject end
    if customData.body then message.body = customData.body end
  end

  state.nextMessageId = state.nextMessageId + 1
  state.unreadCount = state.unreadCount + 1

  -- Insert at beginning (newest first)
  table.insert(state.messages, 1, message)

  log("I", logTag, "Sent message: " .. message.subject .. " from " .. message.fromName)

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerNewMessage", {
      id = message.id,
      from = message.fromName,
      subject = message.subject,
      priority = message.priority,
    })
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = tr("mysummer.notifications.newMessage", "New Message"),
      msg = tr("mysummer.notifications.from", "From") .. ": " .. message.fromName,
    })
  end

  saveState()
  return message.id
end

-- Mark a message as read
local function markAsRead(messageId)
  for _, msg in ipairs(state.messages) do
    if msg.id == messageId and not msg.read then
      msg.read = true
      state.unreadCount = math.max(0, state.unreadCount - 1)
      saveState()
      return true
    end
  end
  return false
end

-- Mark all messages as read
local function markAllAsRead()
  for _, msg in ipairs(state.messages) do
    msg.read = true
  end
  state.unreadCount = 0
  saveState()
  return true
end

-- Delete a message
local function deleteMessage(messageId)
  for i, msg in ipairs(state.messages) do
    if msg.id == messageId then
      if not msg.read then
        state.unreadCount = math.max(0, state.unreadCount - 1)
      end
      table.remove(state.messages, i)
      saveState()
      return true
    end
  end
  return false
end

-- Get all messages for UI
local function getMessages()
  return deepcopy(state.messages)
end

-- Get unread count
local function getUnreadCount()
  return state.unreadCount
end

-- Get a specific message by ID
local function getMessage(messageId)
  for _, msg in ipairs(state.messages) do
    if msg.id == messageId then
      return deepcopy(msg)
    end
  end
  return nil
end

-- Send a custom message (not from template)
-- Used for mission offers and dynamic content
local function sendCustomMessage(messageData)
  if not messageData then
    log("W", logTag, "sendCustomMessage called with nil data")
    return nil
  end

  -- Route to chat system if available
  if career_modules_mysummerChat then
    local contactId = messageData.from or "system"
    local content = messageData.body or ""

    -- For mission offers, format the message nicely
    if messageData.actionType == "mission_offer" then
      content = messageData.subject .. "\n\n" .. content
    end

    -- Determine if this is from a contact or system
    local isContact = contactId ~= "system" and contactId ~= "unknown"

    if isContact then
      -- Unlock contact if needed
      career_modules_mysummerChat.unlockContact(contactId)

      -- Send as contact message with mission data
      career_modules_mysummerChat.sendContactMessage(contactId, content, {
        contentType = "text",
        actionType = messageData.actionType,
        actionData = {
          missionId = messageData.missionId,
          quizOptions = messageData.quizOptions,
          quizCallback = messageData.quizCallback,
        },
      })
    else
      -- Send as system message
      career_modules_mysummerChat.sendSystemMessage(content, {
        actionType = messageData.actionType,
        actionData = {
          missionId = messageData.missionId,
        },
      })
    end

    log("I", logTag, "Custom message routed to chat: " .. (messageData.subject or "no subject"))
    return 1 -- Return dummy ID
  end

  -- Fallback to old email system
  local message = {
    id = state.nextMessageId,
    templateId = nil, -- No template
    from = messageData.from or "unknown",
    fromName = messageData.fromName or "Unknown",
    subject = messageData.subject or "No Subject",
    body = messageData.body or "",
    icon = messageData.icon or "[*]",
    priority = messageData.priority or "normal",
    timestamp = os.time(),
    read = false,
    -- Mission-specific data
    missionId = messageData.missionId,
    actionType = messageData.actionType, -- "mission_offer", "mission_update", "surveillance_quiz"
    -- Quiz data (for surveillance missions)
    quizOptions = messageData.quizOptions, -- Array of location names
    quizCallback = messageData.quizCallback, -- Lua function path to call with answer
  }

  state.nextMessageId = state.nextMessageId + 1
  state.unreadCount = state.unreadCount + 1

  -- Insert at beginning (newest first)
  table.insert(state.messages, 1, message)

  log("I", logTag, "Sent custom message: " .. message.subject .. " from " .. message.fromName)

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerNewMessage", {
      id = message.id,
      from = message.fromName,
      subject = message.subject,
      priority = message.priority,
      missionId = message.missionId,
    })
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = tr("mysummer.notifications.newMessage", "New Message"),
      msg = tr("mysummer.notifications.from", "From") .. ": " .. message.fromName,
    })
  end

  saveState()
  return message.id
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Called when Ghost is unlocked (first purchase)
local function onGhostUnlocked()
  -- Check if we already sent the intro message
  for _, msg in ipairs(state.messages) do
    if msg.templateId == "ghost_intro" then
      return  -- Already sent
    end
  end

  -- Route to chat system if available
  if career_modules_mysummerChat then
    -- Send through unified chat system
    career_modules_mysummerChat.unlockContact("ghost")
    career_modules_mysummerChat.sendContactMessage("ghost",
      tr("mysummer.messages.ghostIntro.line1", "You don't know me. But I know you."),
      { contentType = "text" }
    )
    career_modules_mysummerChat.sendContactMessage("ghost",
      tr("mysummer.messages.ghostIntro.line2", "Saw you picking up parts for that ETK project. Word travels fast in certain circles."),
      { contentType = "text" }
    )
    career_modules_mysummerChat.sendContactMessage("ghost",
      tr("mysummer.messages.ghostIntro.line3", "If you want the REAL parts - the ones that actually make a difference - you're shopping at the wrong places."),
      { contentType = "text" }
    )
    career_modules_mysummerChat.sendContactMessage("ghost",
      tr("mysummer.messages.ghostIntro.line4", "There's a place on the deep web. Silk Road. That's where the serious builders go. Look for someone called 'Ghost'."),
      { contentType = "text" }
    )
    -- Mark as sent in old system to prevent duplicate
    table.insert(state.messages, 1, { templateId = "ghost_intro", read = true, timestamp = os.time() })
    saveState()
    log("I", logTag, "Ghost intro sent via chat system")
  else
    -- Fallback to old email system
    sendMessage("ghost_intro")
  end
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onCareerActive(active)
  if active then
    loadState()

    -- Send welcome message if this is a new game (no messages yet)
    if #state.messages == 0 then
      -- Route to chat system if available
      if career_modules_mysummerChat then
        career_modules_mysummerChat.sendSystemMessage(
          tr("mysummer.messages.welcome.body1", "Welcome to West Coast USA! Your ETK I-Series project car is waiting at your garage.")
        )
        career_modules_mysummerChat.sendSystemMessage(
          tr("mysummer.messages.welcome.body2", "Check SpeedParts.com for new parts, PartsBay for used parts, and your computer for updates. Good luck!")
        )
        -- Mark as sent
        table.insert(state.messages, 1, { templateId = "welcome", read = true, timestamp = os.time() })
        saveState()
      else
        sendMessage("welcome")
      end
    end
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

local function onExtensionLoaded()
  log("I", logTag, "MySummer Messages system loaded")
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

-- Message API
M.sendMessage = sendMessage
M.sendCustomMessage = sendCustomMessage
M.markAsRead = markAsRead
M.markAllAsRead = markAllAsRead
M.deleteMessage = deleteMessage
M.getMessages = getMessages
M.getMessage = getMessage
M.getUnreadCount = getUnreadCount

-- Event handlers
M.onGhostUnlocked = onGhostUnlocked

-- Lifecycle
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onExtensionLoaded = onExtensionLoaded

return M
