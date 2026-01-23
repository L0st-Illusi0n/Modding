-- teleport.lua
-- Teleport helpers (logic lives here so console commands + future GUI can call the same functions)

local Teleport = {}

local U = nil
local P = nil
local UEH = nil

-- simple caches (keep tiny for now)
local CACHED_MAP = "Unknown"
local CACHED_MAP_TIME = 0
local MAP_CACHE_TTL = 0.50

local CACHED_PC = nil
local CACHED_PC_TIME = 0
local PC_CACHE_TTL = 0.50

local CACHED_PAWN = nil
local CACHED_PAWN_TIME = 0
local PAWN_CACHE_TTL = 0.25

local RETURN_POSITIONS = {}

local function now_time()
    return (U and U.now_time and U.now_time()) or os.clock()
end

local function is_valid(obj)
    if not obj then return false end
    if obj.IsValid then
        local ok, v = pcall(obj.IsValid, obj)
        return ok and v
    end
    return true
end

local function is_world_actor(actor)
    if not is_valid(actor) then return false end
    if actor.GetWorld then
        local ok, world = pcall(actor.GetWorld, actor)
        if ok and world == nil then
            return false
        end
    end
    return true
end

local function find_all(class_name)
    if not class_name or class_name == "" then return nil end

    if _G.FindAllOf then
        local ok, res = pcall(_G.FindAllOf, class_name)
        if ok then return res end
    end
    if _G.UE and UE.FindAllOf then
        local ok, res = pcall(UE.FindAllOf, class_name)
        if ok then return res end
    end
    return nil
end

local function get_local_controller()
    local now = now_time()
    if CACHED_PC and (now - CACHED_PC_TIME) < PC_CACHE_TTL and is_valid(CACHED_PC) then
        return CACHED_PC
    end

    -- If UE4SS exposes a helper, prefer it.
    if _G.UE and UE.GetLocalPlayerController then
        local ok, pc = pcall(UE.GetLocalPlayerController)
        if ok and is_valid(pc) then
            CACHED_PC = pc
            CACHED_PC_TIME = now
            return pc
        end
    end

    local cls = (P and (P.CLASSES and P.CLASSES.PlayerController)) or "BP_MyPlayerController_C"
    local controllers = find_all(cls)
    if controllers then
        for _, pc in ipairs(controllers) do
            if is_valid(pc) and (pc.NetTag or 0) == 0 then
                CACHED_PC = pc
                CACHED_PC_TIME = now
                return pc
            end
        end
    end
    return nil
end

function Teleport.get_current_map()
    local now = now_time()
    if (now - CACHED_MAP_TIME) < MAP_CACHE_TTL then
        return CACHED_MAP
    end

    local pc = get_local_controller()
    local new_map = "Unknown"
    if pc and pc.GetFullName then
        local ok, full = pcall(pc.GetFullName, pc)
        if ok and full then
            local low = tostring(full):lower()
            local markers = (P and P.MAPS and P.MAPS.PackageMarkers) or {}
            for map_name, list in pairs(markers) do
                if type(list) == "table" then
                    for _, mk in ipairs(list) do
                        mk = tostring(mk)
                        if mk ~= "" then
                            if tostring(full):find(mk, 1, true) or low:find(mk:lower(), 1, true) then
                                new_map = tostring(map_name)
                                break
                            end
                        end
                    end
                end
                if new_map ~= "Unknown" then break end
            end
        end
    end

    if new_map == "Unknown" and UEH and UEH.GetWorld then
        local world = UEH.GetWorld()
        if world and world.IsValid and world:IsValid() then
            local name = nil
            if world.GetMapName then
                local ok, n = pcall(world.GetMapName, world)
                if ok then name = n end
            end
            if (not name or name == "") and world.GetName then
                local ok, n = pcall(world.GetName, world)
                if ok then name = n end
            end
            if (not name or name == "") and world.GetFullName then
                local ok, n = pcall(world.GetFullName, world)
                if ok then name = n end
            end
            if name then
                local low = tostring(name):lower()
                local markers = (P and P.MAPS and P.MAPS.PackageMarkers) or {}
                for map_name, list in pairs(markers) do
                    if type(list) == "table" then
                        for _, mk in ipairs(list) do
                            mk = tostring(mk)
                            if mk ~= "" and (tostring(name):find(mk, 1, true) or low:find(mk:lower(), 1, true)) then
                                new_map = tostring(map_name)
                                break
                            end
                        end
                    end
                    if new_map ~= "Unknown" then break end
                end
            end
        end
    end

    CACHED_MAP = new_map
    CACHED_MAP_TIME = now
    return CACHED_MAP
end

local function get_tp_table(map_name)
    local tp = (P and (P.TELEPORTS or P.Teleports)) or {}
    return tp[map_name] or {}
end

local function get_local_pawn()
    local now = now_time()
    if CACHED_PAWN and (now - CACHED_PAWN_TIME) < PAWN_CACHE_TTL and is_world_actor(CACHED_PAWN) then
        return CACHED_PAWN
    end

    local pc = get_local_controller()
    if not pc then return nil end

    local pawn = nil
    if pc.K2_GetPawn then
        local ok, pwn = pcall(pc.K2_GetPawn, pc)
        if ok then pawn = pwn end
    end
    if pawn and is_world_actor(pawn) then
        CACHED_PAWN = pawn
        CACHED_PAWN_TIME = now
        return pawn
    end

    -- Fallback: detect local character by class (Lobby/Main), when controller pawn is unset.
    local function find_local_character(class_name)
        if not class_name or class_name == "" then return nil end
        local chars = find_all(class_name)
        if not chars then return nil end
        for _, ch in ipairs(chars) do
            if is_world_actor(ch) then
                local ok_full, full = true, nil
                if ch.GetFullName then
                    ok_full, full = pcall(ch.GetFullName, ch)
                end
                if (not ok_full) or (full == nil) or tostring(full):find("PersistentLevel", 1, true) then
                    if (ch.NetTag or 0) == 0 then
                        return ch
                    end
                end
            end
        end
        return nil
    end

    local map = Teleport.get_current_map()
    local lobby_cls = (P and P.CLASSES and P.CLASSES.LobbyCharacter) or "BP_Character_Lobby_C"
    local main_cls = (P and P.CLASSES and P.CLASSES.MainCharacter) or "BP_Character_C"
    if map == "Lobby" then
        pawn = find_local_character(lobby_cls)
    elseif map == "Main" then
        pawn = find_local_character(main_cls)
    else
        pawn = find_local_character(lobby_cls) or find_local_character(main_cls)
    end
    if pawn then
        CACHED_PAWN = pawn
        CACHED_PAWN_TIME = now
        return pawn
    end
    return nil
end

function Teleport.get_local_pawn()
    return get_local_pawn()
end

local function pawn_key(pawn)
    if not pawn then return nil end
    if pawn.GetFullName then
        local ok, full = pcall(pawn.GetFullName, pawn)
        if ok and full and full ~= "" then
            return tostring(full)
        end
    end
    return tostring(pawn)
end

local function save_return_position(pawn)
    if not pawn or not pawn.K2_GetActorLocation then return false end
    local ok, loc = pcall(pawn.K2_GetActorLocation, pawn)
    if not ok or not loc then return false end
    local rot = nil
    if pawn.K2_GetActorRotation then
        local okr, r = pcall(pawn.K2_GetActorRotation, pawn)
        if okr and r then
            rot = { pitch = r.Pitch or 0, yaw = r.Yaw or 0, roll = r.Roll or 0 }
        end
    end
    local key = pawn_key(pawn)
    if not key then return false end
    RETURN_POSITIONS[key] = {
        x = loc.X or 0,
        y = loc.Y or 0,
        z = loc.Z or 0,
        map = Teleport.get_current_map(),
        rot = rot,
    }
    return true
end

local function do_teleport_pos(pos, pawn_override, save_return)
    local pawn = pawn_override or get_local_pawn()
    if not pawn then
        return false, "no local pawn"
    end
    if not pos or pos.x == nil or pos.y == nil or pos.z == nil then
        return false, "bad pos"
    end
    if not pawn.K2_SetActorLocation then
        return false, "pawn missing K2_SetActorLocation"
    end

    if save_return == nil then
        save_return = true
    end
    if save_return then
        save_return_position(pawn)
    end

    local sweep = {} -- out param
    local ok, res = pcall(function()
        if pos.rot and pawn.K2_SetActorLocationAndRotation then
            return pawn:K2_SetActorLocationAndRotation(
                { X = pos.x, Y = pos.y, Z = pos.z },
                { Pitch = pos.rot.pitch or 0, Yaw = pos.rot.yaw or 0, Roll = pos.rot.roll or 0 },
                false, sweep, true
            )
        end
        return pawn:K2_SetActorLocation({ X = pos.x, Y = pos.y, Z = pos.z }, false, sweep, true)
    end)
    if not ok then
        return false, tostring(res)
    end
    if pos.rot and pawn.K2_SetActorRotation then
        pcall(pawn.K2_SetActorRotation, pawn,
            { Pitch = pos.rot.pitch or 0, Yaw = pos.rot.yaw or 0, Roll = pos.rot.roll or 0 }, false)
    end
    return true, "ok"
end

local function resolve_spec(spec)
    spec = tostring(spec or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if spec == "" then return nil, "no spec" end

    -- allow MAP:KEY (ex: LOBBY:ship)
    local map_part, key_part = spec:match("^(%a+)%s*:%s*(.+)$")
    if map_part and key_part then
        map_part = tostring(map_part):upper()
        key_part = tostring(key_part):lower()
        if map_part == "LOBBY" then
            return get_tp_table("Lobby")[key_part], nil
        end
        if map_part == "MAIN" then
            return get_tp_table("Main")[key_part], nil
        end
        return nil, "unknown map part"
    end

    local map = Teleport.get_current_map()
    local key = tostring(spec):lower()
    local entry = get_tp_table(map)[key]
    if not entry then
        -- fallback: if we're Unknown, try both
        if map == "Unknown" then
            entry = get_tp_table("Lobby")[key] or get_tp_table("Main")[key]
        end
    end
    return entry, nil
end

function Teleport.list(map_name)
    map_name = map_name or Teleport.get_current_map()
    local tp_table = get_tp_table(map_name)
    local keys = {}
    for k in pairs(tp_table) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys, map_name, tp_table
end

function Teleport.teleport(spec, pawn_override, save_return)
    local entry, err = resolve_spec(spec)
    if not entry then
        return false, err or "unknown teleport"
    end
    if type(entry) == "table" and entry.pos then
        return do_teleport_pos(entry.pos, pawn_override, save_return)
    end
    return false, "bad entry"
end

function Teleport.teleport_to_location(pos, pawn_override, save_return)
    return do_teleport_pos(pos, pawn_override, save_return)
end

function Teleport.get_return_position(pawn)
    local key = pawn_key(pawn)
    if not key then return nil end
    return RETURN_POSITIONS[key], key
end

function Teleport.clear_return_position(pawn)
    local key = pawn_key(pawn)
    if key then
        RETURN_POSITIONS[key] = nil
    end
end

function Teleport.set_return_point(pawn_override)
    local pawn = pawn_override or get_local_pawn()
    if not pawn then
        return false, "no local pawn"
    end
    local ok = save_return_position(pawn)
    return ok, ok and "saved" or "failed"
end

function Teleport.save_local_return()
    local pawn = get_local_pawn()
    if not pawn then
        return false, "no local pawn"
    end
    local ok = save_return_position(pawn)
    return ok, ok and "saved" or "failed"
end

function Teleport.has_return_point(pawn_override)
    local pawn = pawn_override or get_local_pawn()
    if not pawn then return false end
    local pos = Teleport.get_return_position(pawn)
    return pos ~= nil
end

local function get_all_player_pawns()
    local pawns = {}
    local seen = {}
    local cls = (P and (P.CLASSES and P.CLASSES.PlayerController)) or "BP_MyPlayerController_C"
    local controllers = find_all(cls)
    if controllers then
        for _, pc in ipairs(controllers) do
            if is_world_actor(pc) and pc.K2_GetPawn then
                local ok, pawn = pcall(pc.K2_GetPawn, pc)
                if ok and is_world_actor(pawn) and not seen[pawn] then
                    seen[pawn] = true
                    pawns[#pawns + 1] = pawn
                end
            end
        end
    end
    if #pawns == 0 then
        local pawn = get_local_pawn()
        if pawn then
            pawns[1] = pawn
        end
    end
    return pawns
end

function Teleport.get_all_player_pawns()
    return get_all_player_pawns()
end

function Teleport.return_self()
    local pawn = get_local_pawn()
    if not pawn then
        return false, "no local pawn"
    end
    local pos, key = Teleport.get_return_position(pawn)
    if not pos then
        return false, "no saved return position"
    end
    local ok, msg = do_teleport_pos(pos, pawn, false)
    return ok, msg
end

function Teleport.return_all()
    local pawns = get_all_player_pawns()
    local count = 0
    for _, pawn in ipairs(pawns or {}) do
        local pos, key = Teleport.get_return_position(pawn)
        if pos then
            local ok = do_teleport_pos(pos, pawn, false)
            if ok then
                count = count + 1
            end
        end
    end
    return true, count
end

function Teleport.list_returns()
    local keys = {}
    for k in pairs(RETURN_POSITIONS) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys, RETURN_POSITIONS
end

function Teleport.init(Util, Pointers)
    U = Util
    P = Pointers
    if UEH == nil then
        local ok, mod = pcall(require, "UEHelpers")
        if ok then UEH = mod else UEH = false end
    end
    return true
end

return Teleport
