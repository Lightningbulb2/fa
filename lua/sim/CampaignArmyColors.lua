--------------------------------------------------------------------------------
-- Keeps the lobby colors of human players in campaign / co-op missions.
--
-- Mission scripts (and the scenario's per-army `color` field) recolor every
-- army, including the players, which throws away the color picked in the
-- lobby. This module wraps the engine's `SetArmyColor` and
-- `SetArmyColorIndex` so that:
--
-- * NPC armies are colored exactly as the mission asks.
-- * Human armies keep their lobby color and the mission's request is only
--   remembered.
-- * If a player's lobby color is too close to a color one of the mission's
--   NPC armies uses, that player gets the mission's color for their army
--   instead (or a free palette color if the mission never set one), so allies
--   and enemies stay easy to tell apart.
--
-- Only colors change here. Army indices, alliances, unit ownership, objectives
-- and difficulty are untouched, so scripted unit handoffs (`GiveUnitToArmy`),
-- map expansion and the rest of the mission flow behave as before.
--------------------------------------------------------------------------------

local NpcColors = import("/lua/shared/npccolors.lua")
local GameColors = import("/lua/gamecolors.lua").GameColors
local IsClose = NpcColors.IsClose
local IndexToRGB = NpcColors.PaletteToRGB

local Installed = false

-- engine functions, captured before wrapping
local EngineSetArmyColor
local EngineSetArmyColorIndex

---@type table<integer, number[]> army index -> lobby {r, g, b}
local LobbyColor = {}
---@type table<integer, number[]> army index -> color the mission asked for
local MissionColor = {}
---@type table<integer, number[]> NPC army index -> current {r, g, b}
local NpcColor = {}
---@type table<integer, boolean> human armies that gave up their lobby color
local Clashed = {}




---@param army Army
---@return integer | nil
local function ToArmyIndex(army)
    if type(army) == 'number' then
        return army
    end
    for index, name in ListArmies() do
        if name == army then
            return index
        end
    end
    return nil
end

---@param rgb number[]
---@param ignoreArmy integer
---@return boolean
local function ClashesWithOthers(rgb, ignoreArmy)
    for army, npc in NpcColor do
        if army ~= ignoreArmy and IsClose(rgb, npc) then
            return true
        end
    end
    return false
end

--- Picks a palette color that is not close to any NPC color or to another
--- player's current color.
---@param army integer
---@return number[] | nil
local function FindFreeColor(army)
    for _, index in GameColors.LobbyColorOrder do
        local rgb = IndexToRGB(index)
        if rgb and not ClashesWithOthers(rgb, army) then
            local free = true
            for other, lobby in LobbyColor do
                if other ~= army then
                    local current = Clashed[other] and MissionColor[other] or lobby
                    if current and IsClose(rgb, current) then
                        free = false
                        break
                    end
                end
            end
            if free then
                return rgb
            end
        end
    end
    return nil
end

--- Re-applies the color of a human army after its clash state may have changed.
---@param army integer
local function ApplyHumanColor(army)
    if Clashed[army] then
        local rgb = MissionColor[army]
        if not rgb or ClashesWithOthers(rgb, army) then
            rgb = FindFreeColor(army) or rgb
        end
        if rgb then
            EngineSetArmyColor(army, rgb[1], rgb[2], rgb[3])
        end
    else
        local rgb = LobbyColor[army]
        EngineSetArmyColor(army, rgb[1], rgb[2], rgb[3])
    end
end

--- Checks every human army against the NPC colors seen so far.
local function UpdateClashes()
    for army, lobby in LobbyColor do
        if not Clashed[army] and ClashesWithOthers(lobby, army) then
            Clashed[army] = true
            ApplyHumanColor(army)
        end
    end
end

---@param army integer
---@param rgb number[] | nil
---@param apply fun()
local function OnColorRequest(army, rgb, apply)
    if LobbyColor[army] then
        -- human army: remember what the mission wanted, keep the lobby color
        -- unless it clashes with an NPC
        if rgb then
            MissionColor[army] = rgb
        end
        if Clashed[army] then
            ApplyHumanColor(army)
        end
        return
    end

    apply()
    if rgb then
        NpcColor[army] = rgb
        UpdateClashes()
    end
end

--- Installs the color wrappers. Safe to call more than once; only takes effect
--- for campaign / co-op sessions (called from `InitializeScenarioArmies`).
function Install()
    if Installed then
        return
    end
    Installed = true

    EngineSetArmyColor = _G.SetArmyColor
    EngineSetArmyColorIndex = _G.SetArmyColorIndex

    local armySetups = ScenarioInfo.ArmySetup or {}
    for index, name in ListArmies() do
        local setup = armySetups[name]
        if setup and setup.Human then
            local rgb = IndexToRGB(setup.ArmyColor or setup.PlayerColor)
            if rgb then
                LobbyColor[index] = rgb
            end
        end
    end

    _G.SetArmyColor = function(army, r, g, b)
        local index = ToArmyIndex(army)
        if not index then
            return EngineSetArmyColor(army, r, g, b)
        end
        OnColorRequest(index, { r, g, b }, function()
            EngineSetArmyColor(army, r, g, b)
        end)
    end

    _G.SetArmyColorIndex = function(army, color)
        local index = ToArmyIndex(army)
        if not index then
            return EngineSetArmyColorIndex(army, color)
        end
        OnColorRequest(index, IndexToRGB(color), function()
            EngineSetArmyColorIndex(army, color)
        end)
    end
end
