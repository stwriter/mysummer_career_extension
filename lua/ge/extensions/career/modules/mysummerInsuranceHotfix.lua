-- Hotfix for RLS Career Overhaul insurance bug
-- Bug: makeRepairClaim tries to add tables instead of numbers (line 565)
-- This is a minimal patch - only replaces the broken function

local M = {}
local logTag = "insuranceHotfix"
local originalMakeRepairClaim = nil

local function patchInsurance()
  if originalMakeRepairClaim or not career_modules_insurance_insurance then
    return
  end

  -- Save original function
  originalMakeRepairClaim = career_modules_insurance_insurance.makeRepairClaim

  if not originalMakeRepairClaim then
    log("W", logTag, "makeRepairClaim not found")
    return
  end

  -- Replace with fixed version
  career_modules_insurance_insurance.makeRepairClaim = function(invVehId, costs, vehInfo)
    -- Fix 1: extract numeric values from cost tables before summing
    local fixedCosts = {}

    for key, cost in pairs(costs or {}) do
      if type(cost) == "number" then
        fixedCosts[key] = cost
      elseif type(cost) == "table" then
        -- Handle nested table: {money: {value: 123}} or {money: 123}
        local numValue = 0
        if cost.money then
          numValue = type(cost.money) == "table" and (cost.money.value or cost.money.amount or 0) or cost.money
        elseif cost.value then
          numValue = cost.value
        elseif cost.amount then
          numValue = cost.amount
        end
        fixedCosts[key] = numValue
      else
        fixedCosts[key] = 0
      end
    end

    -- Fix 2: if vehInfo is nil, try to get it from inventory
    local finalVehInfo = vehInfo
    if not finalVehInfo and career_modules_inventory then
      local vehicles = career_modules_inventory.getVehicles and career_modules_inventory.getVehicles() or {}
      finalVehInfo = vehicles[invVehId]
    end

    -- Call original with numeric costs and valid vehInfo
    return originalMakeRepairClaim(invVehId, fixedCosts, finalVehInfo)
  end

  log("I", logTag, "Patched makeRepairClaim")
end

local function onCareerActive(active)
  if active then
    patchInsurance()
  end
end

M.onCareerActive = onCareerActive

return M
