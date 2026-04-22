--[[
levelup_reward.lua
AzerothCore + ELA

Features
- Bei jedem Level-Up: 1 zufälliges passendes equipbares Item
- 85% Green / 15% Blue
- Falls kein grünes/blaues Item für genau das neue Level existiert:
    -> 1 weißes passendes Item
- Falls gar nichts existiert:
    -> nur Nachricht
- Beim ERSTEN Level-Up (1 -> 2):
    -> lernt der Spieler alle klassenpassenden Weapon Trainer Skills
- Blacklist gegen Test-/Placeholder-/Dev-Items

Hinweis:
- "Erster Level-Up" = oldLevel == 1 und newLevel == 2
]]

if _G.LevelRewardLoaded then
    return
end
_G.LevelRewardLoaded = true

math.randomseed(os.time())

local PLAYER_EVENT_ON_LEVEL_CHANGE = 13

-- WoW Class IDs (WotLK)
local CLASS_WARRIOR      = 1
local CLASS_PALADIN      = 2
local CLASS_HUNTER       = 3
local CLASS_ROGUE        = 4
local CLASS_PRIEST       = 5
local CLASS_DEATH_KNIGHT = 6
local CLASS_SHAMAN       = 7
local CLASS_MAGE         = 8
local CLASS_WARLOCK      = 9
local CLASS_DRUID        = 11

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
local WEP_AXE_1H    = 0
local WEP_AXE_2H    = 1
local WEP_BOW       = 2
local WEP_GUN       = 3
local WEP_MACE_1H   = 4
local WEP_MACE_2H   = 5
local WEP_POLEARM   = 6
local WEP_SWORD_1H  = 7
local WEP_SWORD_2H  = 8
local WEP_STAFF     = 10
local WEP_FIST      = 13
local WEP_DAGGER    = 15
local WEP_THROWN    = 16
local WEP_SPEAR     = 17
local WEP_CROSSBOW  = 18
local WEP_WAND      = 19

local EQUIPPABLE_INVENTORY_TYPES = {
    1,  -- HEAD
    2,  -- NECK
    3,  -- SHOULDERS
    5,  -- CHEST
    6,  -- WAIST
    7,  -- LEGS
    8,  -- FEET
    9,  -- WRISTS
    10, -- HANDS
    11, -- FINGER
    12, -- TRINKET
    13, -- WEAPON
    14, -- SHIELD
    15, -- RANGED
    16, -- BACK
    17, -- 2H WEAPON
    20, -- ROBE
    21, -- MAIN HAND
    22, -- OFF HAND
    26  -- RANGED RIGHT
}

-- Weapon proficiency spell IDs
local SPELL_AXES_1H        = 196
local SPELL_AXES_2H        = 197
local SPELL_MACES_1H       = 198
local SPELL_MACES_2H       = 199
local SPELL_POLEARMS       = 200
local SPELL_SWORDS_1H      = 201
local SPELL_SWORDS_2H      = 202
local SPELL_STAVES         = 227
local SPELL_BOWS           = 264
local SPELL_GUNS           = 266
local SPELL_DAGGERS        = 1180
local SPELL_THROWN         = 2567
local SPELL_CROSSBOWS      = 5011
local SPELL_WANDS          = 5009
local SPELL_FIST_WEAPONS   = 15590

-- Item stat types (WotLK)
local STAT_STRENGTH  = 3
local STAT_AGILITY   = 4
local STAT_STAMINA   = 5
local STAT_INTELLECT = 6
local STAT_SPIRIT    = 7

-- Itemnamen, die nicht als Reward auftauchen sollen
local NAME_BLACKLIST = {
    "TEST",
    "Test",
    "test",
    "Placeholder",
    "PLACEHOLDER",
    "NYI",
    "Deprecated",
    "Monster - ",
    "DEBUG"
}

local function tableToCsv(tbl)
    local out = {}
    for i = 1, #tbl do
        out[#out + 1] = tostring(tbl[i])
    end
    return table.concat(out, ",")
end

local function getClassMask(classId)
    return 2 ^ (classId - 1)
end

local function rollPrimaryQuality()
    local r = math.random(1, 100)
    if r <= 85 then
        return 2 -- green
    end
    return 3 -- blue
end

local function qualityText(quality)
    if quality == 1 then
        return "|cffffffff[White]|r"
    elseif quality == 2 then
        return "|cff1eff00[Green]|r"
    elseif quality == 3 then
        return "|cff0070dd[Blue]|r"
    end
    return "|cff9d9d9d[Unknown]|r"
end

local function buildNameBlacklistSql()
    local parts = {}
    for i = 1, #NAME_BLACKLIST do
        parts[#parts + 1] = "AND name NOT LIKE '%%" .. NAME_BLACKLIST[i] .. "%%'"
    end
    return table.concat(parts, "\n            ")
end

local function getArmorSubclassesForPlayer(classId, level)
    if classId == CLASS_WARRIOR then
        if level >= 40 then
            return { ARMOR_MISC, ARMOR_PLATE, ARMOR_SHIELD }
        else
            return { ARMOR_MISC, ARMOR_MAIL, ARMOR_SHIELD }
        end

    elseif classId == CLASS_PALADIN then
        if level >= 40 then
            return { ARMOR_MISC, ARMOR_PLATE, ARMOR_SHIELD }
        else
            return { ARMOR_MISC, ARMOR_MAIL, ARMOR_SHIELD }
        end

    elseif classId == CLASS_HUNTER then
        if level >= 40 then
            return { ARMOR_MISC, ARMOR_MAIL }
        else
            return { ARMOR_MISC, ARMOR_LEATHER }
        end

    elseif classId == CLASS_ROGUE then
        return { ARMOR_MISC, ARMOR_LEATHER }

    elseif classId == CLASS_PRIEST then
        return { ARMOR_MISC, ARMOR_CLOTH }

    elseif classId == CLASS_DEATH_KNIGHT then
        return { ARMOR_MISC, ARMOR_PLATE }

    elseif classId == CLASS_SHAMAN then
        if level >= 40 then
            return { ARMOR_MISC, ARMOR_MAIL, ARMOR_SHIELD }
        else
            return { ARMOR_MISC, ARMOR_LEATHER, ARMOR_SHIELD }
        end

    elseif classId == CLASS_MAGE then
        return { ARMOR_MISC, ARMOR_CLOTH }

    elseif classId == CLASS_WARLOCK then
        return { ARMOR_MISC, ARMOR_CLOTH }

    elseif classId == CLASS_DRUID then
        return { ARMOR_MISC, ARMOR_LEATHER }
    end

    return { ARMOR_MISC }
end

local function getWeaponSubclassesForPlayer(classId)
    if classId == CLASS_WARRIOR then
        return {
            WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H,
            WEP_POLEARM, WEP_SWORD_1H, WEP_SWORD_2H, WEP_STAFF,
            WEP_FIST, WEP_DAGGER, WEP_THROWN, WEP_SPEAR,
            WEP_BOW, WEP_GUN, WEP_CROSSBOW
        }

    elseif classId == CLASS_PALADIN then
        return {
            WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H,
            WEP_POLEARM, WEP_SWORD_1H, WEP_SWORD_2H, WEP_STAFF
        }

    elseif classId == CLASS_HUNTER then
        return {
            WEP_AXE_1H, WEP_AXE_2H, WEP_BOW, WEP_GUN, WEP_POLEARM,
            WEP_SWORD_1H, WEP_SWORD_2H, WEP_STAFF, WEP_FIST,
            WEP_DAGGER, WEP_THROWN, WEP_SPEAR, WEP_CROSSBOW
        }

    elseif classId == CLASS_ROGUE then
        return {
            WEP_AXE_1H, WEP_MACE_1H, WEP_SWORD_1H, WEP_FIST,
            WEP_DAGGER, WEP_THROWN, WEP_BOW, WEP_GUN, WEP_CROSSBOW
        }

    elseif classId == CLASS_PRIEST then
        return {
            WEP_MACE_1H, WEP_STAFF, WEP_DAGGER, WEP_WAND
        }

    elseif classId == CLASS_DEATH_KNIGHT then
        return {
            WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H,
            WEP_POLEARM, WEP_SWORD_1H, WEP_SWORD_2H, WEP_DAGGER
        }

    elseif classId == CLASS_SHAMAN then
        return {
            WEP_AXE_1H, WEP_AXE_2H, WEP_MACE_1H, WEP_MACE_2H,
            WEP_STAFF, WEP_FIST, WEP_DAGGER
        }

    elseif classId == CLASS_MAGE then
        return {
            WEP_STAFF, WEP_DAGGER, WEP_WAND
        }

    elseif classId == CLASS_WARLOCK then
        return {
            WEP_STAFF, WEP_DAGGER, WEP_WAND
        }

    elseif classId == CLASS_DRUID then
        return {
            WEP_MACE_1H, WEP_MACE_2H, WEP_POLEARM, WEP_STAFF,
            WEP_FIST, WEP_DAGGER
        }
    end

    return {}
end

local function getWeaponTrainerSpellsForClass(classId)
    if classId == CLASS_WARRIOR then
        return {
            SPELL_AXES_1H, SPELL_AXES_2H,
            SPELL_MACES_1H, SPELL_MACES_2H,
            SPELL_POLEARMS,
            SPELL_SWORDS_1H, SPELL_SWORDS_2H,
            SPELL_STAVES,
            SPELL_FIST_WEAPONS,
            SPELL_DAGGERS,
            SPELL_THROWN,
            SPELL_BOWS,
            SPELL_GUNS,
            SPELL_CROSSBOWS
        }

    elseif classId == CLASS_PALADIN then
        return {
            SPELL_AXES_1H, SPELL_AXES_2H,
            SPELL_MACES_1H, SPELL_MACES_2H,
            SPELL_POLEARMS,
            SPELL_SWORDS_1H, SPELL_SWORDS_2H
        }

    elseif classId == CLASS_HUNTER then
        return {
            SPELL_AXES_1H, SPELL_AXES_2H,
            SPELL_SWORDS_1H, SPELL_SWORDS_2H,
            SPELL_POLEARMS,
            SPELL_STAVES,
            SPELL_FIST_WEAPONS,
            SPELL_DAGGERS,
            SPELL_THROWN,
            SPELL_BOWS,
            SPELL_GUNS,
            SPELL_CROSSBOWS
        }

    elseif classId == CLASS_ROGUE then
        return {
            SPELL_AXES_1H,
            SPELL_MACES_1H,
            SPELL_SWORDS_1H,
            SPELL_FIST_WEAPONS,
            SPELL_DAGGERS,
            SPELL_THROWN,
            SPELL_BOWS,
            SPELL_GUNS,
            SPELL_CROSSBOWS
        }

    elseif classId == CLASS_PRIEST then
        return {
            SPELL_MACES_1H,
            SPELL_STAVES,
            SPELL_DAGGERS,
            SPELL_WANDS
        }

    elseif classId == CLASS_DEATH_KNIGHT then
        return {
            SPELL_AXES_1H, SPELL_AXES_2H,
            SPELL_MACES_1H, SPELL_MACES_2H,
            SPELL_POLEARMS,
            SPELL_SWORDS_1H, SPELL_SWORDS_2H
        }

    elseif classId == CLASS_SHAMAN then
        return {
            SPELL_AXES_1H, SPELL_AXES_2H,
            SPELL_MACES_1H, SPELL_MACES_2H,
            SPELL_STAVES,
            SPELL_FIST_WEAPONS,
            SPELL_DAGGERS
        }

    elseif classId == CLASS_MAGE then
        return {
            SPELL_STAVES,
            SPELL_DAGGERS,
            SPELL_WANDS
        }

    elseif classId == CLASS_WARLOCK then
        return {
            SPELL_STAVES,
            SPELL_DAGGERS,
            SPELL_WANDS
        }

    elseif classId == CLASS_DRUID then
        return {
            SPELL_MACES_1H, SPELL_MACES_2H,
            SPELL_POLEARMS,
            SPELL_STAVES,
            SPELL_FIST_WEAPONS,
            SPELL_DAGGERS
        }
    end

    return {}
end

local function teachFirstLevelupWeaponSkills(player)
    local classId = player:GetClass()
    local spells = getWeaponTrainerSpellsForClass(classId)

    local learnedAny = false

    for i = 1, #spells do
        local spellId = spells[i]
        if not player:HasSpell(spellId) then
            player:LearnSpell(spellId)
            learnedAny = true
        end
    end

    if learnedAny then
        player:SendBroadcastMessage("|cffFFD700You learned all available weapon trainer proficiencies for your class.|r")
    end
end

local function buildRewardQuery(classId, level, quality)
    local classMask = getClassMask(classId)
    local armorCsv = tableToCsv(getArmorSubclassesForPlayer(classId, level))
    local weaponCsv = tableToCsv(getWeaponSubclassesForPlayer(classId))
    local invCsv = tableToCsv(EQUIPPABLE_INVENTORY_TYPES)
    local blacklistSql = buildNameBlacklistSql()

    local sql = string.format([[
        SELECT entry, name, Quality
        FROM item_template
        WHERE
            Quality = %d
            AND RequiredLevel = %d
            AND InventoryType IN (%s)
            AND (
                (class = %d AND subclass IN (%s))
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
        ORDER BY RAND()
        LIMIT 1;
    ]],
        quality,
        level,
        invCsv,
        ITEM_CLASS_ARMOR, armorCsv,
        ITEM_CLASS_WEAPON, weaponCsv,
        classMask,
        blacklistSql
    )

    return sql
end

local function querySingleItem(classId, level, quality)
    local result = WorldDBQuery(buildRewardQuery(classId, level, quality))
    if not result then
        return nil
    end

    return {
        entry = result:GetUInt32(0),
        name = result:GetString(1),
        quality = result:GetUInt32(2)
    }
end

local function getRewardForPlayer(player)
    local classId = player:GetClass()
    local level = player:GetLevel()

    local primaryQuality = rollPrimaryQuality()

    local item = querySingleItem(classId, level, primaryQuality)
    if item then
        return item
    end

    local secondaryQuality = (primaryQuality == 2) and 3 or 2
    item = querySingleItem(classId, level, secondaryQuality)
    if item then
        return item
    end

    item = querySingleItem(classId, level, 1)
    if item then
        return item
    end

    return nil
end

local function addRewardItem(player, reward)
    if not reward then
        return false, nil
    end

    local item = player:AddItem(reward.entry, 1)
    if not item then
        return false, nil
    end

    local link = item:GetItemLink()
    if not link then
        link = reward.name or ("Item #" .. tostring(reward.entry))
    end

    return true, link
end

local function OnLevelChange(event, player, oldLevel)
    if not player then
        return
    end

    local newLevel = player:GetLevel()
    if newLevel <= oldLevel then
        return
    end

    -- Erstes Level-Up: Weapon Trainer Skills lernen
    if oldLevel == 1 and newLevel == 2 then
        teachFirstLevelupWeaponSkills(player)
    end

    local reward = getRewardForPlayer(player)

    if reward then
        local ok, link = addRewardItem(player, reward)

        if ok then
            player:SendBroadcastMessage(
                "|cffFFD700Level-Up Reward:|r " ..
                qualityText(reward.quality) .. " " .. link
            )
        else
            player:SendBroadcastMessage(
                "|cffff0000No free bag space for your level-up reward.|r"
            )
        end
        return
    end

    player:SendBroadcastMessage(
        "|cffff0000No suitable level-up reward found for your class and level.|r"
    )
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LEVEL_CHANGE, OnLevelChange)

print("[LevelReward] Loaded")