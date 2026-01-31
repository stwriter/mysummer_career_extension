-- MySummer Career - Dialogue Overlay Test Module
-- Test module for DialogueOverlay with contact avatars and emotions
--
-- Usage from console:
--   career_modules_mysummerDialogueTest.testBasicDialogue()
--   career_modules_mysummerDialogueTest.testEmotions()
--   career_modules_mysummerDialogueTest.testAllContacts()

local M = {}
M.dependencies = {
  "career_career",
  "career_modules_mysummerChat",
}

local logTag = "mysummerDialogueTest"

-- ============================================================================
-- TEST FUNCTIONS
-- ============================================================================

-- Test 1: Basic dialogue with default emotion
local function testBasicDialogue()
  log("I", logTag, "Testing basic dialogue...")

  local chat = extensions.career_modules_mysummerChat
  if not chat then
    log("E", logTag, "mysummerChat module not loaded!")
    return
  end

  -- Unlock contact first
  chat.unlockContact("ghost")

  chat.showDialogue("ghost", {
    "Hola, soy Ghost.",
    "Tengo un trabajo para ti."
  })
end

-- Test 2: Dialogue with emotions
local function testEmotions()
  log("I", logTag, "Testing dialogue with emotions...")

  local chat = extensions.career_modules_mysummerChat
  if not chat then
    log("E", logTag, "mysummerChat module not loaded!")
    return
  end

  -- Unlock contact first
  chat.unlockContact("techie")

  chat.showDialogue("techie", {
    { content = "Hola, ¿cómo estás?", emotion = "happy" },
    { content = "Tengo malas noticias...", emotion = "sad" },
    { content = "¡Pero también tengo buenas noticias!", emotion = "happy" },
    { content = "El motor está destrozado.", emotion = "angry" },
    { content = "Pero puedo arreglarlo por buen precio.", emotion = "content" }
  })
end

-- Test 3: Nova/Rook seductive emotion
local function testSeductive()
  log("I", logTag, "Testing seductive emotion...")

  local chat = extensions.career_modules_mysummerChat
  if not chat then
    log("E", logTag, "mysummerChat module not loaded!")
    return
  end

  -- Unlock contact first
  chat.unlockContact("nova")

  chat.showDialogue("nova", {
    { content = "Hola...", emotion = "standard" },
    { content = "Necesito que me consigas unas piezas.", emotion = "seductive" },
    { content = "Te haré un descuento especial.", emotion = "seductive" },
    { content = "¿Trato?", emotion = "happy" }
  })
end

-- Test 4: All contacts showcase
local function testAllContacts()
  log("I", logTag, "Testing all contacts (one by one with 8s delay)...")

  local chat = extensions.career_modules_mysummerChat
  if not chat then
    log("E", logTag, "mysummerChat module not loaded!")
    return
  end

  local contacts = {
    { id = "grandfather", name = "Abuelo", message = "Te he dejado mi legado.", emotion = "content" },
    { id = "ghost", name = "Ghost", message = "Trabajo en las sombras.", emotion = "standard" },
    { id = "import", name = "Import", message = "Tengo las mejores piezas JDM.", emotion = "happy" },
    { id = "muscle", name = "Muscle", message = "V8 es la única verdad.", emotion = "content" },
    { id = "nova", name = "Nova", message = "Podríamos hacer un trato...", emotion = "seductive" },
    { id = "rook", name = "Rook", message = "¿Quieres algo especial?", emotion = "seductive" },
    { id = "shadow", name = "Shadow", message = "Nadie sabe quién soy.", emotion = "standard" },
    { id = "techie", name = "Techie", message = "¡Puedo arreglar cualquier cosa!", emotion = "happy" },
    { id = "viper", name = "Viper", message = "¿Crees que puedes ganarme?", emotion = "angry" },
  }

  -- Unlock all contacts first
  for _, contact in ipairs(contacts) do
    chat.unlockContact(contact.id)
  end

  local delay = 0
  for _, contact in ipairs(contacts) do
    extensions.core_jobsystem.create(function(job)
      job.sleep(delay)
      log("I", logTag, "Showing contact: " .. contact.id)
      chat.showDialogue(contact.id, {
        {
          content = contact.name .. ": \"" .. contact.message .. "\"",
          emotion = contact.emotion
        }
      })
    end)
    delay = delay + 8 -- 8 seconds between each contact
  end

  log("I", logTag, "All contacts test scheduled (will take ~" .. (delay) .. " seconds)")
end

-- Test 5: Emotion progression (same contact, changing emotions)
local function testEmotionProgression()
  log("I", logTag, "Testing emotion progression...")

  local chat = extensions.career_modules_mysummerChat
  if not chat then
    log("E", logTag, "mysummerChat module not loaded!")
    return
  end

  -- Unlock contact first
  chat.unlockContact("viper")

  chat.showDialogue("viper", {
    { content = "Así que quieres correr contra mí.", emotion = "standard" },
    { content = "¿Sabes lo que pasó con el último?", emotion = "angry" },
    { content = "Lo destruí completamente.", emotion = "angry" },
    { content = "Pero hey, quizás tú seas diferente...", emotion = "content" },
    { content = "¡Nos vemos en la línea de salida!", emotion = "happy" }
  })
end

-- Test 6: Monologue (player internal thoughts)
local function testMonologue()
  log("I", logTag, "Testing monologue...")

  local chat = extensions.career_modules_mysummerChat
  if not chat then
    log("E", logTag, "mysummerChat module not loaded!")
    return
  end

  chat.showDialogue("player", {
    "\"¿Qué voy a hacer ahora?\"",
    "\"El abuelo me dejó este desastre...\"",
    "\"Pero quizás pueda hacerlo funcionar.\""
  })
end

-- Test 7: Mixed emotions conversation (realistic scenario)
local function testRealisticConversation()
  log("I", logTag, "Testing realistic conversation...")

  local chat = extensions.career_modules_mysummerChat
  if not chat then
    log("E", logTag, "mysummerChat module not loaded!")
    return
  end

  -- Unlock contact first
  chat.unlockContact("muscle")

  chat.showDialogue("muscle", {
    { content = "Oye, ¿viste mi nuevo Challenger?", emotion = "happy" },
    { content = "Costó una fortuna pero vale cada centavo.", emotion = "content" },
    { content = "¿Sabes qué? Necesito un favor.", emotion = "standard" },
    { content = "Tengo que mover unas piezas... discretamente.", emotion = "sad" },
    { content = "Si me ayudas, te doy un buen corte.", emotion = "happy" }
  })
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

M.testBasicDialogue = testBasicDialogue
M.testEmotions = testEmotions
M.testSeductive = testSeductive
M.testAllContacts = testAllContacts
M.testEmotionProgression = testEmotionProgression
M.testMonologue = testMonologue
M.testRealisticConversation = testRealisticConversation

-- Expose all tests in a menu
M.getAllTests = function()
  return {
    { name = "Basic Dialogue", fn = testBasicDialogue },
    { name = "Emotions Test", fn = testEmotions },
    { name = "Seductive Emotion (Nova)", fn = testSeductive },
    { name = "All Contacts Showcase", fn = testAllContacts },
    { name = "Emotion Progression", fn = testEmotionProgression },
    { name = "Monologue (Player)", fn = testMonologue },
    { name = "Realistic Conversation", fn = testRealisticConversation },
  }
end

log("I", logTag, "Test module loaded. Use career_modules_mysummerDialogueTest.testXXX() to run tests")

return M
