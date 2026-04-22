--[[
levelup_reward.lua
AzerothCore + ELA

Features
- On every level-up: 1 random equippable item matching the player's class
- 65% Green / 25% Blue / 10% Purple (Epic)
- Fallback chain: Purple -> Blue -> Green -> White
- If no green/blue/purple item exists for exactly the new level:
    -> 1 white item matching the player's class
- If nothing exists at all:
    -> message only
- On the FIRST level-up (1 -> 2):
    -> player learns all class-appropriate weapon trainer proficiencies
- Blacklist filters out test/placeholder/dev items

Note:
- "First level-up" = oldLevel == 1 and newLevel == 2
]]

if _G.LevelRewardLoaded then
    return
end
_G.LevelRewardLoaded = true

-- ============================================================
--  CONFIGURATION
-- ============================================================
LevelReward_Enable        = 1   -- 1 = enabled, 0 = disabled

LevelReward_Chance_Purple = 10  -- % chance for Epic   (purple)
LevelReward_Chance_Blue   = 25  -- % chance for Rare   (blue)
                                -- Uncommon (green) fills the rest automatically
-- ============================================================

math.randomseed(os.time())

local PLAYER_EVENT_ON_LEVEL_CHANGE = 13

-- item_template.class
local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR  = 4

-- Armor subclasses
local ARMOR_MISC    = 0
local ARMOR_CLOTH   = 1
local ARMOR_LEATHER = 2
local ARMOR_MAIL    = 3
local ARMOR_PLATE   = 4
local ARMOR_SHIELD  = 6

-- Weapon subclasses
local WEP_AXE_1H   = 0
local WEP_AXE_2H   = 1
local WEP_BOW      = 2
local WEP_GUN      = 3
local WEP_MACE_1H  = 4
local WEP_MACE_2H  = 5
local WEP_POLEARM  = 6
local WEP_SWORD_1H = 7
local WEP_SWORD_2H = 8
local WEP_STAFF    = 10
local WEP_FIST     = 13
local WEP_DAGGER   = 15
local WEP_THROWN   = 16
local WEP_SPEAR    = 17
local WEP_CROSSBOW = 18
local WEP_WAND     = 19

-- Weapon proficiency spell IDs
local SPELL_AXES_1H      = 196
local SPELL_AXES_2H      = 197
local SPELL_MACES_1H     = 198
local SPELL_MACES_2H     = 199
local SPELL_POLEARMS     = 200
local SPELL_SWORDS_1H    = 201
local SPELL_SWORDS_2H    = 202
local SPELL_STAVES       = 227
local SPELL_BOWS         = 264
local SPELL_GUNS         = 266
local SPELL_DAGGERS      = 1180
local SPELL_THROWN       = 2567
local SPELL_CROSSBOWS    = 5011
local SPELL_WANDS        = 5009
local SPELL_FIST_WEAPONS = 15590

-- Item stat types (WotLK)
local STAT_STRENGTH  = 3
local STAT_AGILITY   = 4
local STAT_STAMINA   = 5
local STAT_INTELLECT = 6
local STAT_SPIRIT    = 7

-- ============================================================
--  DATA TABLES  (replace large if-elseif chains with O(1) lookups)
-- ============================================================

-- AllowableClass bitmask per class ID (2 ^ (classId - 1))
local CLASS_MASK = {
    [1]  = 1,    [2]  = 2,    [3]  = 4,    [4]  = 8,
    [5]  = 16,   [6]  = 32,   [7]  = 64,   [8]  = 128,
    [9]  = 256,  [11] = 1024,
}

-- Armor subclasses per class. `hi` is used at level >= 40; falls back to `lo`.
local ARMOR_BY_CLASS = {
    [1]  = { lo = { ARMOR_MISC, ARMOR_MAIL,    ARMOR_SHIELD },
             hi = { ARMOR_MISC, ARMOR_PLATE,   ARMOR_SHIELD } }, -- Warrior
    [2]  = { lo = { ARMOR_MISC, ARMOR_MAIL,    ARMOR_SHIELD },
             hi = { ARMOR_MISC, ARMOR_PLATE,   ARMOR_SHIELD } }, -- Paladin
    [3]  = { lo = { ARMOR_MISC, ARMOR_LEATHER },
             hi = { ARMOR_MISC, ARMOR_MAIL    } },               -- Hunter
    [4]  = { lo = { ARMOR_MISC, ARMOR_LEATHER } },               -- Rogue
    [5]  = { lo = { ARMOR_MISC, ARMOR_CLOTH   } },               -- Priest
    [6]  = { lo = { ARMOR_MISC, ARMOR_PLATE   } },               -- Death Knight
    [7]  = { lo = { ARMOR_MISC, ARMOR_LEATHER, ARMOR_SHIELD },
             hi = { ARMOR_MISC, ARMOR_MAIL,    ARMOR_SHIELD } }, -- Shaman
    [8]  = { lo = { ARMOR_MISC, ARMOR_CLOTH   } },               -- Mage
    [9]  = { lo = { ARMOR_MISC, ARMOR_CLOTH   } },               -- Warlock
    [11] = { lo = { ARMOR_MISC, ARMOR_LEATHER } },               -- Druid
}

-- Equippable weapon subclasses per class
local WEAPONS_BY_CLASS = {
    [1]  = { WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H, WEP_POLEARM,
             WEP_SWORD_1H, WEP_SWORD_2H, WEP_STAFF, WEP_FIST, WEP_DAGGER,
             WEP_THROWN, WEP_SPEAR, WEP_BOW, WEP_GUN, WEP_CROSSBOW },  -- Warrior
    [2]  = { WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H,
             WEP_POLEARM, WEP_SWORD_1H, WEP_SWORD_2H },                -- Paladin
    [3]  = { WEP_AXE_1H, WEP_AXE_2H, WEP_BOW, WEP_GUN, WEP_POLEARM,
             WEP_SWORD_1H, WEP_SWORD_2H, WEP_STAFF, WEP_FIST, WEP_DAGGER,
             WEP_THROWN, WEP_SPEAR, WEP_CROSSBOW },                    -- Hunter
    [4]  = { WEP_AXE_1H, WEP_MACE_1H, WEP_SWORD_1H, WEP_FIST,
             WEP_DAGGER, WEP_THROWN, WEP_BOW, WEP_GUN, WEP_CROSSBOW }, -- Rogue
    [5]  = { WEP_MACE_1H, WEP_STAFF, WEP_DAGGER, WEP_WAND },          -- Priest
    [6]  = { WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H,
             WEP_POLEARM, WEP_SWORD_1H, WEP_SWORD_2H, WEP_DAGGER },   -- Death Knight
    [7]  = { WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H,
             WEP_STAFF, WEP_FIST, WEP_DAGGER },                        -- Shaman
    [8]  = { WEP_STAFF, WEP_DAGGER, WEP_WAND },                        -- Mage
    [9]  = { WEP_STAFF, WEP_DAGGER, WEP_WAND },                        -- Warlock
    [11] = { WEP_MACE_1H, WEP_MACE_2H, WEP_POLEARM, WEP_STAFF,
             WEP_FIST, WEP_DAGGER },                                   -- Druid
}

-- Weapon trainer proficiency spell IDs per class
local TRAINER_SPELLS_BY_CLASS = {
    [1]  = { SPELL_AXES_1H, SPELL_AXES_2H, SPELL_MACES_1H, SPELL_MACES_2H,
             SPELL_POLEARMS, SPELL_SWORDS_1H, SPELL_SWORDS_2H, SPELL_STAVES,
             SPELL_FIST_WEAPONS, SPELL_DAGGERS, SPELL_THROWN,
             SPELL_BOWS, SPELL_GUNS, SPELL_CROSSBOWS },                -- Warrior
    [2]  = { SPELL_AXES_1H, SPELL_AXES_2H, SPELL_MACES_1H, SPELL_MACES_2H,
             SPELL_POLEARMS, SPELL_SWORDS_1H, SPELL_SWORDS_2H },       -- Paladin
    [3]  = { SPELL_AXES_1H, SPELL_AXES_2H, SPELL_SWORDS_1H, SPELL_SWORDS_2H,
             SPELL_POLEARMS, SPELL_STAVES, SPELL_FIST_WEAPONS, SPELL_DAGGERS,
             SPELL_THROWN, SPELL_BOWS, SPELL_GUNS, SPELL_CROSSBOWS },  -- Hunter
    [4]  = { SPELL_AXES_1H, SPELL_MACES_1H, SPELL_SWORDS_1H,
             SPELL_FIST_WEAPONS, SPELL_DAGGERS, SPELL_THROWN,
             SPELL_BOWS, SPELL_GUNS, SPELL_CROSSBOWS },                -- Rogue
    [5]  = { SPELL_MACES_1H, SPELL_STAVES, SPELL_DAGGERS, SPELL_WANDS }, -- Priest
    [6]  = { SPELL_AXES_1H, SPELL_AXES_2H, SPELL_MACES_1H, SPELL_MACES_2H,
             SPELL_POLEARMS, SPELL_SWORDS_1H, SPELL_SWORDS_2H },       -- Death Knight
    [7]  = { SPELL_AXES_1H, SPELL_AXES_2H, SPELL_MACES_1H, SPELL_MACES_2H,
             SPELL_STAVES, SPELL_FIST_WEAPONS, SPELL_DAGGERS },        -- Shaman
    [8]  = { SPELL_STAVES, SPELL_DAGGERS, SPELL_WANDS },               -- Mage
    [9]  = { SPELL_STAVES, SPELL_DAGGERS, SPELL_WANDS },               -- Warlock
    [11] = { SPELL_MACES_1H, SPELL_MACES_2H, SPELL_POLEARMS, SPELL_STAVES,
             SPELL_FIST_WEAPONS, SPELL_DAGGERS },                      -- Druid
}

-- Primary stat types used for armor item filtering per class
local STATS_BY_CLASS = {
    [1]  = { STAT_STRENGTH, STAT_STAMINA },                            -- Warrior
    [2]  = { STAT_STRENGTH, STAT_INTELLECT, STAT_STAMINA },            -- Paladin
    [3]  = { STAT_AGILITY, STAT_INTELLECT, STAT_SPIRIT, STAT_STAMINA}, -- Hunter
    [4]  = { STAT_AGILITY, STAT_STAMINA },                             -- Rogue
    [5]  = { STAT_INTELLECT, STAT_SPIRIT, STAT_STAMINA },              -- Priest
    [6]  = { STAT_STRENGTH, STAT_STAMINA },                            -- Death Knight
    [7]  = { STAT_AGILITY, STAT_INTELLECT, STAT_SPIRIT, STAT_STAMINA}, -- Shaman
    [8]  = { STAT_INTELLECT, STAT_SPIRIT },                            -- Mage
    [9]  = { STAT_INTELLECT, STAT_SPIRIT },                            -- Warlock
    [11] = { STAT_AGILITY, STAT_INTELLECT, STAT_SPIRIT, STAT_STAMINA}, -- Druid
}

-- Chat color codes per item quality
local QUALITY_COLOR = {
    [1] = "|cffffffff[White]|r",
    [2] = "|cff1eff00[Green]|r",
    [3] = "|cff0070dd[Blue]|r",
    [4] = "|cffa335ee[Purple]|r",
}

local EQUIPPABLE_INVENTORY_TYPES = {
    1,  -- HEAD        2,  -- NECK        3,  -- SHOULDERS
    5,  -- CHEST       6,  -- WAIST       7,  -- LEGS
    8,  -- FEET        9,  -- WRISTS      10, -- HANDS
    11, -- FINGER      12, -- TRINKET     13, -- WEAPON
    14, -- SHIELD      15, -- RANGED      16, -- BACK
    17, -- 2H WEAPON   20, -- ROBE        21, -- MAIN HAND
    22, -- OFF HAND    26, -- RANGED RIGHT
}

-- Item names that must never appear as rewards
local NAME_BLACKLIST = {
    "TEST", "Test", "test", "Placeholder", "PLACEHOLDER",
    "NYI", "Deprecated", "Monster - ", "DEBUG",
}

-- ============================================================
--  PRE-COMPUTED CONSTANTS  (built once at load, never rebuilt)
-- ============================================================

local function tableToCsv(tbl)
    if #tbl == 0 then return "NULL" end
    local out = {}
    for i = 1, #tbl do out[i] = tostring(tbl[i]) end
    return table.concat(out, ",")
end

local INV_CSV = tableToCsv(EQUIPPABLE_INVENTORY_TYPES)

local NAME_BLACKLIST_SQL = (function()
    local parts = {}
    for i = 1, #NAME_BLACKLIST do
        parts[i] = "AND name NOT LIKE '%%" .. NAME_BLACKLIST[i] .. "%%'"
    end
    return table.concat(parts, "\n        ")
end)()

-- ============================================================
--  CORE LOGIC
-- ============================================================

local function rollPrimaryQuality()
    local r = math.random(1, 100)
    if r <= LevelReward_Chance_Purple then
        return 4 -- purple (epic)
    elseif r <= LevelReward_Chance_Purple + LevelReward_Chance_Blue then
        return 3 -- blue (rare)
    end
    return 2 -- green (uncommon)
end

local function teachFirstLevelupWeaponSkills(player)
    local spells = TRAINER_SPELLS_BY_CLASS[player:GetClass()] or {}
    local learnedAny = false
    for i = 1, #spells do
        if not player:HasSpell(spells[i]) then
            player:LearnSpell(spells[i])
            learnedAny = true
        end
    end
    if learnedAny then
        player:SendBroadcastMessage("|cffFFD700You learned all available weapon trainer proficiencies for your class.|r")
    end
end

-- Returns the quality-independent WHERE clause for item_template lookups.
-- Quality is intentionally excluded so one call serves both the GROUP BY and SELECT queries.
local function buildBaseWhereClause(classId, level)
    local armorEntry = ARMOR_BY_CLASS[classId] or { lo = { ARMOR_MISC } }
    local armorCsv   = tableToCsv((level >= 40 and armorEntry.hi) or armorEntry.lo)
    local weaponCsv  = tableToCsv(WEAPONS_BY_CLASS[classId] or {})
    local statsCsv   = tableToCsv(STATS_BY_CLASS[classId]   or { STAT_STAMINA })
    local classMask  = CLASS_MASK[classId] or 0

    -- Armor requires at least one matching stat; weapons match on subclass alone
    -- so damage-only weapons without bonus stats are not incorrectly excluded.
    return string.format([[
        RequiredLevel = %d
        AND InventoryType IN (%s)
        AND (
            (class = %d AND subclass IN (%s)
             AND (stat_type1 IN (%s) OR stat_type2 IN (%s) OR stat_type3 IN (%s) OR stat_type4 IN (%s) OR stat_type5 IN (%s) OR stat_type6 IN (%s) OR stat_type7 IN (%s) OR stat_type8 IN (%s) OR stat_type9 IN (%s) OR stat_type10 IN (%s)))
            OR
            (class = %d AND subclass IN (%s))
        )
        AND (AllowableClass = -1 OR AllowableClass = 32767 OR (AllowableClass & %d) <> 0)
        AND requiredspell = 0
        AND RequiredSkill = 0
        AND RequiredSkillRank = 0
        AND requiredhonorrank = 0
        AND RequiredReputationFaction = 0
        AND RequiredReputationRank = 0
        %s
    ]],
        level, INV_CSV,
        ITEM_CLASS_ARMOR, armorCsv,
        statsCsv, statsCsv, statsCsv, statsCsv, statsCsv,
        statsCsv, statsCsv, statsCsv, statsCsv, statsCsv,
        ITEM_CLASS_WEAPON, weaponCsv,
        classMask, NAME_BLACKLIST_SQL
    )
end

local function getRewardForPlayer(player)
    local baseWhere = buildBaseWhereClause(player:GetClass(), player:GetLevel())

    -- One GROUP BY query to get item counts for all quality tiers at once
    local countResult = WorldDBQuery(string.format(
        "SELECT Quality, COUNT(*) FROM item_template WHERE %s AND Quality IN (1,2,3,4) GROUP BY Quality",
        baseWhere
    ))

    local counts = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    if countResult then
        repeat
            local q = countResult:GetUInt32(0)
            if counts[q] then counts[q] = countResult:GetUInt32(1) end
        until not countResult:NextRow()
    end

    -- Pick quality: prefer rolled tier, fall back downward only (never upgrade)
    -- Chain: purple -> blue -> green -> white
    local rolled = rollPrimaryQuality()
    local target
    if     counts[rolled] > 0              then target = rolled
    elseif rolled >= 3 and counts[3] > 0  then target = 3
    elseif counts[2] > 0                  then target = 2
    elseif counts[1] > 0                  then target = 1
    end

    if not target then return nil end

    local result = WorldDBQuery(string.format(
        "SELECT entry, name, Quality FROM item_template WHERE %s AND Quality = %d LIMIT 1 OFFSET %d",
        baseWhere, target, math.random(0, counts[target] - 1)
    ))
    if not result then return nil end

    return { entry = result:GetUInt32(0), name = result:GetString(1), quality = result:GetUInt32(2) }
end

local function addRewardItem(player, reward)
    local item = player:AddItem(reward.entry, 1)
    if not item then return false end
    local link = item:GetItemLink() or reward.name or ("Item #" .. tostring(reward.entry))
    return true, link
end

local function OnLevelChange(event, player, oldLevel)
    if LevelReward_Enable ~= 1 then return end
    if not player then return end

    local newLevel = player:GetLevel()
    if newLevel <= oldLevel then return end

    if oldLevel == 1 and newLevel == 2 then
        teachFirstLevelupWeaponSkills(player)
    end

    local reward = getRewardForPlayer(player)
    if not reward then
        player:SendBroadcastMessage("|cffff0000No suitable level-up reward found for your class and level.|r")
        return
    end

    local ok, link = addRewardItem(player, reward)
    if ok then
        player:SendBroadcastMessage(
            "|cffFFD700Level-Up Reward:|r " .. (QUALITY_COLOR[reward.quality] or "|cff9d9d9d[Unknown]|r") .. " " .. link
        )
    else
        player:SendBroadcastMessage("|cffff0000No free bag space for your level-up reward.|r")
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LEVEL_CHANGE, OnLevelChange)

print("[LevelReward] Loaded")
