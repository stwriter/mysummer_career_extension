-- MySummer Internet Browser - Hub for online services
-- Accessed from any garage computer
--
-- This is the SINGLE entry point for all MySummer online features:
--   - SilkRoad Parts (deep web leads)
--   - PartsBay (second-hand parts marketplace)
--   - SpeedParts (official parts store)
--   - Project Checklist (build progress tracker)
--
-- The UI is a retro Internet Explorer 4.0 style browser

local M = {}
M.moduleName = "career_modules_mysummerInternet"

M.dependencies = {
  "career_career",
  "career_modules_computer",
  "career_modules_mysummerParts",
}

local logTag = "mysummerInternet"

-- ============================================================================
-- BROWSER STATE
-- ============================================================================

local state = {
  isOpen = false,
  currentFacilityId = nil,
}

-- ============================================================================
-- BROWSER FUNCTIONS
-- ============================================================================

-- Open the browser (loads the retro IE4 style browser UI)
local function openBrowser(facilityId)
  log("I", logTag, "Opening Internet Browser")
  state.isOpen = true
  state.currentFacilityId = facilityId

  -- The browser UI is handled by MySummerBrowser.vue component
  -- It contains all the "websites" as internal pages:
  --   - home (welcome page with links)
  --   - deepweb (SilkRoad Parts - leads)
  --   - partsbay (PartsBay - second-hand market)
  --   - official (SpeedParts - official store)
  --   - checklist (Project - build checklist)

  if guihooks then
    -- Navigate to the browser view (uses mysummer-market state which loads MySummerBrowser)
    guihooks.trigger("ChangeState", { state = "mysummer-market" })
  end
end

-- Close the browser
local function closeBrowser()
  log("I", logTag, "Closing Internet Browser")
  state.isOpen = false
  state.currentFacilityId = nil

  if guihooks then
    guihooks.trigger("mysummerInternetClosed")
  end

  -- Return to computer menu
  if career_career and career_career.closeAllMenus then
    career_career.closeAllMenus()
  end
end

-- Check if browser is open
local function isOpen()
  return state.isOpen
end

-- ============================================================================
-- COMPUTER MENU INTEGRATION
-- ============================================================================

local function onComputerAddFunctions(menuData, computerFunctions)
  -- Add Internet option to all computers
  local computerFunctionData = {
    id = "internet",
    label = "Internet",
    callback = function()
      openBrowser(menuData.computerFacility.id)
    end,
    order = 5  -- High priority, appears near top
  }

  computerFunctions.general[computerFunctionData.id] = computerFunctionData
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Internet Browser module loaded")
end

local function onCareerActive(enabled)
  if enabled then
    log("I", logTag, "Internet Browser initialized")
  else
    state.isOpen = false
    state.currentFacilityId = nil
  end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onComputerAddFunctions = onComputerAddFunctions

-- Public API
M.openBrowser = openBrowser
M.closeBrowser = closeBrowser
M.isOpen = isOpen

return M
