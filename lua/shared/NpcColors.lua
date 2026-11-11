--------------------------------------------------------------------------------
-- Shared helpers for keeping player colors distinct from the colors that a
-- mission gives its NPC armies. Used by the lobby (to grey out palette colors)
-- and by `/lua/sim/campaignarmycolors.lua` (as an in-game fallback).
--------------------------------------------------------------------------------

local GameColors = import("/lua/gamecolors.lua").GameColors

--- Squared RGB distance below which two army colors are considered a clash.
ClashDistanceSq = 70 * 70

---@param hex string # "AARRGGBB" or "RRGGBB"
---@return number[] | nil
function HexToRGB(hex)
    if type(hex) ~= 'string' then
        return nil
    end
    local len = string.len(hex)
    if len == 8 then
        hex = string.sub(hex, 3)
    elseif len ~= 6 then
        return nil
    end
    local r = tonumber(string.sub(hex, 1, 2), 16)
    local g = tonumber(string.sub(hex, 3, 4), 16)
    local b = tonumber(string.sub(hex, 5, 6), 16)
    if not (r and g and b) then
        return nil
    end
    return { r, g, b }
end

--- RGB of a lobby palette color index.
---@param index number
---@return number[] | nil
function PaletteToRGB(index)
    return HexToRGB(GameColors.ArmyColors[index])
end

---@param a number[]
---@param b number[]
---@return boolean
function IsClose(a, b)
    local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return dr * dr + dg * dg + db * db < ClashDistanceSq
end

--- Map folder of a scenario file without the vault's `.vXXXX` suffix, lower case.
---@param scenarioFile string
---@return string | nil
function GetMapKey(scenarioFile)
    if type(scenarioFile) ~= 'string' then
        return nil
    end
    local _, _, folder = string.find(string.lower(scenarioFile), "^/maps/([^/]+)/")
    if not folder then
        return nil
    end
    folder = string.gsub(folder, "%.v%d+$", "")
    return folder
end

--- Colors the mission uses for its NPC armies. A map can declare them itself as
--- `Configurations.standard.npcColors = { 'ff5f01a5', {231, 3, 3}, ... }` in its
--- scenario file; otherwise the generated co-op table is used.
---@param scenarioFile? string
---@param scenarioInfo? table
---@return number[][]
function GetNpcColors(scenarioFile, scenarioInfo)
    local declared = scenarioInfo and scenarioInfo.Configurations
        and scenarioInfo.Configurations.standard
        and scenarioInfo.Configurations.standard.npcColors
    local source = declared
    if not source then
        local key = GetMapKey(scenarioFile)
        source = key and import("/lua/ui/lobby/data/coopnpccolors.lua").NpcColors[key]
    end

    local colors = {}
    if source then
        for _, color in source do
            local rgb = color
            if type(color) == 'string' then
                rgb = HexToRGB(color)
            end
            if type(rgb) == 'table' and rgb[1] and rgb[2] and rgb[3] then
                table.insert(colors, rgb)
            end
        end
    end
    return colors
end

--- Palette indices that are too close to one of the mission's NPC colors.
---@param scenarioFile? string
---@param scenarioInfo? table
---@return table<number, boolean>
function GetReservedPaletteIndices(scenarioFile, scenarioInfo)
    local reserved = {}
    local npcColors = GetNpcColors(scenarioFile, scenarioInfo)
    if table.empty(npcColors) then
        return reserved
    end
    for index, _ in GameColors.PlayerColors do
        local rgb = PaletteToRGB(index)
        if rgb then
            for _, npc in npcColors do
                if IsClose(rgb, npc) then
                    reserved[index] = true
                    break
                end
            end
        end
    end
    return reserved
end
