-- pointers.lua
-- Central place for class names, map markers, teleport points, etc.
-- This file MUST return a table.

local P = {}

-- -----------------------------------------
-- Blueprint/Class names (what we know so far)
-- -----------------------------------------
P.CLASSES = {
    PlayerController = "BP_MyPlayerController_C",
    LobbyCharacter   = "BP_Character_Lobby_C",
    MainCharacter    = "BP_Character_C",
}

-- Back-compat aliases (so old code can do P.Classes, etc.)
P.Classes = P.CLASSES

-- -----------------------------------------
-- Map detection hints (simple string markers)
-- -----------------------------------------
P.MAPS = {
    -- If the local controller's GetFullName contains any of these markers, we treat it as that map.
    PackageMarkers = {
        Lobby = {
            "/Game/Maps/Lobby",
            "lobby", -- fallback
        },
        Main = {
            "/Game/Maps/SpaceShip",
            "spaceship", -- fallback
        },
    }
}

P.MONSTERS = {
    Eye = "BP_Monster_Eye_C",
    Michel = "BP_Monster_Michel_C",
    Ghost = "BP_Monster_Ghost_C",
    Poulpi = "BP_Monster_Poulpi_C",
    ZombieMaster = "BP_Monster_ZombieMaster_C",
}

P.MONSTER_ALIASES = {
    eye = P.MONSTERS.Eye,
    michel = P.MONSTERS.Michel,
    ghost = P.MONSTERS.Ghost,
    poulpi = P.MONSTERS.Poulpi,
    zombiemaster = P.MONSTERS.ZombieMaster,
}

P.ITEMS = {
    Credit1 = "BP_Item_Credit_1_C",
    Credit2 = "BP_Item_Credit_2_C",
    Credit3 = "BP_Item_Credit_3_C",
    DataDisk = "BP_Item_DataDisk_C",
    Keycard = "BP_Item_Keycard_Child_C",
    BlackBox = "BP_HoldItem_BlackBox_C",
}

P.ITEM_ALIASES = {
    credit1 = P.ITEMS.Credit1,
    credit2 = P.ITEMS.Credit2,
    credit3 = P.ITEMS.Credit3,
    credits = "BP_Item_Credit_",
    datadisk = P.ITEMS.DataDisk,
    keycard = P.ITEMS.KeycardChild,
    blackbox = P.ITEMS.BlackBoxHoldItem,
}

P.WEAPONS = {
    Rifle = {class="Weapon_Rifle_Grabbable_C", code="RIFLE"},
    SMG = {class="Weapon_SMG_Grabbable_C", code="SMG"},
    Shotgun = {class="Weapon_ShotgunSM12_Grabbable_C", code="SHOTGUN"},
    FrostGun = {class="BP_FrostGun_C", code="FROST"},
    LaserGun = {class="BP_LaserGun_C", code="LASER"},
    LightningGun = {class="BP_LightningGun_C", code = "LIGHTNING"},
    FlameThrower = {class="BP_Weapon_FlameThrower_C", code="FLAME"},
}

P.SPECIAL_WEAPON_CODES = {
    FROST = true,
    LASER = true,
    LIGHTNING = true,
    FLAME = true,
}

P.WEAPON_CODE_TO_CLASS = {
    RIFLE = P.WEAPONS.Rifle.class,
    SMG = P.WEAPONS.SMG.class,
    SHOTGUN = P.WEAPONS.Shotgun.class,
    FROST = P.WEAPONS.FrostGun.class,
    LASER = P.WEAPONS.LaserGun.class,
    LIGHTNING = P.WEAPONS.LightningGun.class,
    FLAME = P.WEAPONS.FlameThrower.class,
}

P.PIPES = {
    ValvePipe = "BP_ValvePipe_C",
    ReactorTerminal = "BP_ReactorControl_Terminal_REFACT_C",
}

P.TAGS = {
    MONEY = "MONEY",
    DATA = "DATA",
    OBJECTIVE = "OBJECTIVE",
    BLACKBOX = "BLACKBOX",
    WEAPON = "WEAPON",
    PIPE = "PIPE",
    MONSTER = "MONSTER",
    StaticTagOrder = {"MONEY", "DATA", "OBJECTIVE", "BLACKBOX"},
}

P.CLASS_RULES = {
    {short=P.MONSTERS.Eye, tag="MONSTER"},
    {short=P.MONSTERS.Michel, tag="MONSTER"},
    {short=P.MONSTERS.Ghost, tag="MONSTER"},
    {short=P.MONSTERS.Poulpi, tag="MONSTER"},
    {short=P.MONSTERS.ZombieMaster, tag="MONSTER"},
    {short=P.ITEMS.Credit1, tag="MONEY"},
    {short=P.ITEMS.Credit2, tag="MONEY"},
    {short=P.ITEMS.Credit3, tag="MONEY"},
    {short=P.ITEMS.DataDisk, tag = "DATA"},
    {short=P.ITEMS.KeycardChild, tag="OBJECTIVE"},
    {short=P.WEAPONS.Rifle.class, tag="WEAPON", code=P.WEAPONS.Rifle.code},
    {short=P.WEAPONS.SMG.class, tag="WEAPON", code=P.WEAPONS.SMG.code},
    {short=P.WEAPONS.Shotgun.class, tag="WEAPON", code=P.WEAPONS.Shotgun.code},
    {short=P.WEAPONS.FrostGun.class, tag="WEAPON", code=P.WEAPONS.FrostGun.code},
    {short=P.WEAPONS.LaserGun.class, tag="WEAPON", code=P.WEAPONS.LaserGun.code},
    {short=P.WEAPONS.LightningGun.class, tag="WEAPON", code=P.WEAPONS.LightningGun.code},
    {short=P.WEAPONS.FlameThrower.class, tag="WEAPON", code=P.WEAPONS.FlameThrower.code},
    {short=P.PIPES.ValvePipe, tag="PIPE"},
    {short=P.ITEMS.BlackBoxHoldItem, tag="BLACKBOX"},
}

-- -----------------------------------------
-- Teleport points (from main-OLDREF.lua)
-- Keys are lowercase for easier command usage.
-- -----------------------------------------
P.TELEPORTS = {
    Lobby = (function()
        local TP_LOBBY = {
    contracts   = { name = "Contracts",   pos = { x = 4050,    y = -3730,  z = -295 } },
    ship        = { name = "Ship",        pos = { x = 3780,    y = -6960,  z = -400 } },
    containment = { name = "Containment", pos = { x = 8305,    y = 252,    z = -1200 } },
    mike        = { name = "Mike",        pos = { x = 9419.7,  y = 2704.8, z = -1105.7 } },
    ghost       = { name = "Ghost",       pos = { x = 10819.7, y = 2706.5, z = -1105.7 } },
}
        -- convert to lowercase keys table
        local out = {}
        for k, v in pairs(TP_LOBBY) do
            out[tostring(k):lower()] = v
        end
        return out
    end)(),
    Main = (function()
        local TP_MAIN = {
    ship = {name="Ship", pos={x=10625, y=6000, z=-350}},
    command = {name="Command Deck", pos={x=7540, y=-0.4, z=1300}},
    crewserver = {name="Crew Server Room", pos={x=-3300, y=6420, z=-200}},
    engines = {name="Engines Terminal", pos={x=-14730, y=2, z=200}},
    reactor = {name="Reactor Terminal", pos={x=-9200, y=1468, z=97.15}},
}
        local out = {}
        for k, v in pairs(TP_MAIN) do
            out[tostring(k):lower()] = v
        end
        return out
    end)(),
}

-- Back-compat alias
P.Teleports = P.TELEPORTS

return P
