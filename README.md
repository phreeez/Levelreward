# LevelReward

A Lua script for **AzerothCore** with **Eluna Lua Engine** that rewards players with a random, class-appropriate equippable item on every level-up.

---

## Features

- Rewards 1 random equippable item on every level-up
- Items are filtered by class, armor type, weapon proficiency, and relevant stats
- Quality is rolled on each level-up:
  - **10%** Purple (Epic)
  - **25%** Blue (Rare)
  - **65%** Green (Uncommon)
- Fallback chain if no item exists for the rolled quality: **Purple → Blue → Green → White**
- White is only awarded if no green, blue, or purple item exists for that exact level
- If absolutely nothing is found, the player receives a message instead
- On the **first level-up (1 → 2)**, the player automatically learns all weapon proficiencies available to their class
- Blacklist filters out test, placeholder, and developer items
- Armor type scales with level (e.g. Warrior/Paladin switch from Mail → Plate at level 40)

---

## Requirements

- [AzerothCore](https://www.azerothcore.org/)
- [mod-ale](https://github.com/azerothcore/mod-ale) (Azerothcore Lua Engine module)

---

## Installation

1. Copy `levelreward.lua` into your Eluna scripts directory, e.g.:
   ```
   lua_scripts/levelreward/levelreward.lua
   ```
2. Restart your worldserver to load the script.
3. You should see the following message in your server console on load:
   ```
   [LevelReward] Loaded
   ```

---

## How It Works

### Item Selection

On every level-up the script:

1. Builds a query against `item_template` for the player's new level
2. Filters by:
   - Exact `RequiredLevel` matching the new level
   - Equippable `InventoryType`
   - Class-appropriate armor subclass (Cloth / Leather / Mail / Plate / Shield)
   - Class-appropriate weapon subclass
   - For armor: at least one stat matching the class's primary stats (Strength, Agility, Intellect, etc.)
   - For weapons: subclass match only (damage-only weapons with no bonus stats are included)
   - `AllowableClass` mask allows the player's class
   - No special skill, spell, honor rank, or reputation requirements
   - Name blacklist (see below)
3. Rolls a quality tier (Purple / Blue / Green), then falls back down the chain if the pool is empty
4. Picks a random item from the eligible pool using `COUNT(*) + OFFSET` (avoids `ORDER BY RAND()` for better DB performance)
5. Adds the item directly to the player's inventory and sends a chat message with the item link

### Weapon Proficiency (Level 1 → 2 only)

On the very first level-up, the script teaches the player every weapon trainer skill available to their class. This only fires once and skips skills already known.

### Armor Tier Scaling

| Class | Below Level 40 | Level 40+ |
|---|---|---|
| Warrior | Mail + Shield | Plate + Shield |
| Paladin | Mail + Shield | Plate + Shield |
| Hunter | Leather | Mail |
| Shaman | Leather + Shield | Mail + Shield |
| Rogue | Leather | Leather |
| Priest | Cloth | Cloth |
| Mage | Cloth | Cloth |
| Warlock | Cloth | Cloth |
| Druid | Leather | Leather |
| Death Knight | Plate | Plate |

---

## Configuration

### Drop Rates

Edit the two variables at the very top of the file:

```lua
LevelReward_Chance_Purple = 10  -- % chance for Epic   (purple)
LevelReward_Chance_Blue   = 25  -- % chance for Rare   (blue)
                                -- Uncommon (green) fills the rest automatically
```

Green always fills whatever percentage is left over, so the three tiers always sum to 100% automatically. Make sure `Purple + Blue` does not exceed 100.

### Item Name Blacklist

Items whose names contain any of the following strings are excluded:

```lua
local NAME_BLACKLIST = {
    "TEST", "Test", "test",
    "Placeholder", "PLACEHOLDER",
    "NYI",
    "Deprecated",
    "Monster - ",
    "DEBUG"
}
```

Add or remove entries as needed. Matching is case-sensitive and uses SQL `LIKE`.

---

## Supported Classes

All WotLK playable classes are supported:

| Class | Armor | Weapons |
|---|---|---|
| Warrior | Mail → Plate, Shield | Axes, Maces, Swords, Polearms, Staves, Fist, Daggers, Thrown, Bows, Guns, Crossbows |
| Paladin | Mail → Plate, Shield | Axes, Maces, Swords, Polearms |
| Hunter | Leather → Mail | Axes, Swords, Polearms, Staves, Fist, Daggers, Thrown, Bows, Guns, Crossbows |
| Rogue | Leather | Axes (1H), Maces (1H), Swords (1H), Fist, Daggers, Thrown, Bows, Guns, Crossbows |
| Priest | Cloth | Maces (1H), Staves, Daggers, Wands |
| Death Knight | Plate | Axes, Maces, Swords, Polearms, Daggers |
| Shaman | Leather → Mail, Shield | Axes, Maces, Staves, Fist, Daggers |
| Mage | Cloth | Staves, Daggers, Wands |
| Warlock | Cloth | Staves, Daggers, Wands |
| Druid | Leather | Maces, Polearms, Staves, Fist, Daggers |

---

## Notes

- Death Knights start at level 55 and already have their weapon proficiencies — the first level-up skill grant does not apply to them
- Items with any reputation, skill, spell, or honor rank requirements are excluded
- The script uses a double-load guard (`_G.LevelRewardLoaded`) so it is safe to hot-reload without registering duplicate event handlers
