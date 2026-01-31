-- util.lua - tiny helpers shared by modules

local Util = {}

-- Internal caches for common lookups
local _CACHED_MAP = "Unknown"
local _CACHED_MAP_TIME = 0
local _MAP_CACHE_TTL = 0.50
local _CACHED_PC = nil
local _CACHED_PC_TIME = 0
local _PC_CACHE_TTL = 0.50
local _CACHED_PAWN = nil
local _CACHED_PAWN_TIME = 0
local _PAWN_CACHE_TTL = 0.25
local _UEH = nil

function Util.trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.split_ws(s)
    s = tostring(s or "")
    local out = {}
    for part in s:gmatch("%S+") do
        out[#out + 1] = part
    end
    return out
end

-- Monotonic-ish timer (good enough for caches)
function Util.now_time()
    return os.clock()
end

function Util.log(...)
    print(...)
end

function Util.warn(...)
    print("[WARN]", ...)
end

function Util.err(...)
    print("[ERROR]", ...)
end

-- Null-pointer detection WITHOUT dereferencing the UObject.
-- Some UE4SS functions can return a userdata wrapper around nullptr.
function Util.is_null(obj)
    if obj == nil then return true end
    if type(obj) ~= "userdata" then return false end

    -- tostring(obj) is usually safe and does NOT require HasAnyInternalFlags.
    local ok, s = pcall(function() return tostring(obj) end)
    if not ok or type(s) ~= "string" then
        return true -- if tostring fails, treat as unsafe/null
    end

    s = s:lower()
    return s:find("0000000000000000", 1, true) ~= nil
        or s:find("nullptr", 1, true) ~= nil
        or s == "null"
end

function Util.is_valid(obj)
    if obj == nil then return false end
    if Util.is_null(obj) then return false end

    -- Try IsValid / IsValidLowLevel only AFTER we know it's not nullptr-wrapped.
    local ok, res = pcall(function()
        if type(obj) == "userdata" and obj.IsValid then
            return obj:IsValid()
        end
        if type(obj) == "userdata" and obj.IsValidLowLevel then
            return obj:IsValidLowLevel()
        end
        return nil
    end)

    if ok and type(res) == "boolean" then
        return res
    end

    -- Fallback: try GetFullName without hard-validating flags.
    local okn, full = pcall(function()
        if type(obj) == "userdata" and obj.GetFullName then
            return obj:GetFullName()
        end
        return nil
    end)

    return okn and type(full) == "string" and full ~= ""
end

function Util.safe_get_field(obj, field)
    if obj == nil or Util.is_null(obj) then
        return nil, false
    end
    local ok, val = pcall(function()
        return obj[field]
    end)
    if ok then
        return val, true
    end
    return nil, false
end

local function _is_ufunction(obj)
    if obj == nil or type(obj) ~= "userdata" then
        return false
    end
    if obj.type then
        local ok, t = pcall(obj.type, obj)
        if ok and t == "UFunction" then
            return true
        end
    end
    return false
end

local function _call_ufunction_on(obj, ufn, ...)
    if not Util.is_valid(obj) then
        return false, "invalid_obj"
    end
    if not _is_ufunction(ufn) then
        return false, "invalid_ufunction"
    end
    local last_err = nil

    local cf = Util.safe_get_field(obj, "CallFunction")
    if type(cf) == "function" then
        local ok, res = pcall(cf, obj, ufn, ...)
        if ok then
            return true, res
        end
        last_err = res
    elseif type(cf) == "userdata" and _is_ufunction(cf) then
        local ok, res = pcall(cf, obj, ufn, ...)
        if ok then
            return true, res
        end
        last_err = res
        ok, res = pcall(cf, ufn, ...)
        if ok then
            return true, res
        end
        last_err = res
    end

    local ok, res = pcall(ufn, obj, ...)
    if ok then
        return true, res
    end
    last_err = res

    ok, res = pcall(ufn, ...)
    if ok then
        return true, res
    end
    last_err = res

    return false, last_err or "call failed"
end

function Util.safe_call(obj, field, ...)
    if not Util.is_valid(obj) then
        return false, nil
    end
    local fn = Util.safe_get_field(obj, field)
    if type(fn) == "function" then
        local ok, res = pcall(fn, obj, ...)
        if ok then
            return true, res
        end
        return false, nil
    end
    if type(fn) == "userdata" and _is_ufunction(fn) then
        local ok, res = _call_ufunction_on(obj, fn, ...)
        if ok then
            return true, res
        end
    end
    return false, nil
end

function Util.safe_call_err(obj, field, ...)
    if obj == nil or Util.is_null(obj) then
        return false, nil, "invalid_obj"
    end

    local fn, okf = Util.safe_get_field(obj, field)
    if not okf or type(fn) ~= "function" then
        return false, nil, "missing"
    end

    local ok, res = pcall(fn, obj, ...)
    if ok then
        return true, res, nil
    end
    return false, nil, res
end

local function _safe_get_name(o)
    if o == nil then return "<nil>" end
    local ok, v = pcall(function() return o:GetName() end)
    if ok and v then return v end
    local ok2, fn = pcall(function() return o.GetFName end)
    if ok2 and type(fn) == "function" then
        local ok3, f = pcall(fn, o)
        if ok3 and f and f.ToString then
            local ok4, s = pcall(f.ToString, f)
            if ok4 and s then return s end
        end
    end
    local ok3, s = pcall(function() return tostring(o) end)
    return (ok3 and s) or "<no name>"
end

function _G.safe_is_uobject(o)
  if o == nil then return false end
  if type(o) ~= "userdata" then return false end
  if type(o.IsValid) ~= "function" then return false end
  local ok, res = pcall(o.IsValid, o)
  return ok and res == true
end

local function safe_fullname(o)
  if o == nil then return "<nil>" end
  if type(o) ~= "userdata" then return "<" .. type(o) .. ">" end
  if type(o.GetFullName) == "function" then
    local ok, name = pcall(o.GetFullName, o)
    if ok and type(name) == "string" then return name end
  end
  if type(o.GetName) == "function" then
    local ok, name = pcall(o.GetName, o)
    if ok and type(name) == "string" then return name end
  end
  return "<userdata>"
end

local function _safe_is_valid(obj)
    if obj == nil or type(obj) ~= "userdata" then return false end
    local ok, fn = pcall(function() return obj.IsValid end)
    if ok and type(fn) == "function" then
        local ok2, v = pcall(fn, obj)
        if ok2 then return v == true end
    end
    local ok2, fn2 = pcall(function() return obj.IsValidLowLevel end)
    if ok2 and type(fn2) == "function" then
        local ok3, v2 = pcall(fn2, obj)
        if ok3 then return v2 == true end
    end
    return true
end

function _G.dump_ufunction_safe(fn)
  print("=== dumpfn (safe) ===")
  print("fn:", safe_fullname(fn))
  if not _G.safe_is_uobject(fn) then
    print("NOT a valid UObject (or not safe to validate). Aborting.")
    return
  end

  if type(fn.GetOuter) == "function" then
    local ok, outer = pcall(fn.GetOuter, fn)
    if ok then print("outer:", safe_fullname(outer)) end
  end

  if type(fn.GetClass) == "function" then
    local ok, cls = pcall(fn.GetClass, fn)
    if ok then print("class:", safe_fullname(cls)) end
  end

  print("UE5 note: param walking via GetChildren/GetNext is unsafe (FField/FProperty).")
  print("Use EventViewer callstacks to extract the exact param list/types.")
end

local function _get_next_any(child)
    if not child then return nil, "nil" end
    if child.GetNext then
        local ok, nxt = pcall(child.GetNext, child)
        if ok then return nxt, nil end
        return nil, nxt
    end
    local ok, v = pcall(function() return child.Next end)
    if ok and v ~= nil then
        return v, nil
    end
    return nil, "no GetNext/Next"
end

function Util.dump_ufunction_params(fn)
    if fn == nil then
        print("[UFnDump] fn=nil")
        return
    end

    if type(fn) ~= "userdata" then
        print("[UFnDump] fn is not userdata:", type(fn))
        return
    end

    if not fn.GetFullName then
        print("[UFnDump] fn has no GetFullName (not a UE object?)")
        return
    end

    if not _safe_is_valid(fn) then
        print("[UFnDump] fn is not valid (nullptr or destroyed)")
        return
    end

    print("[UFnDump] Function:", _safe_get_fullname(fn))

    local child, err = _get_children_any(fn)
    if not child then
        if err then
            print("[UFnDump] GetChildren failed:", tostring(err))
        end
        print("[UFnDump] No children available (no params or reflection blocked).")
        print("[UFnDump] Try EventViewer signature display if available.")
        return
    end

    local i = 0
    local seen = {}
    local guard = 0
    while child do
        i = i + 1
        print(string.format("[UFnDump]  #%d %s | %s", i, _safe_get_name(child), _safe_get_fullname(child)))

        local key = tostring(child)
        if seen[key] then
            print("[UFnDump] Loop detected; stopping.")
            break
        end
        seen[key] = true

        local nxt, nerr = _get_next_any(child)
        if nerr then
            if nerr ~= "no GetNext/Next" then
                print("[UFnDump] GetNext failed:", tostring(nerr))
            end
            break
        end
        child = nxt

        guard = guard + 1
        if guard > 256 then
            print("[UFnDump] Guard hit; stopping.")
            break
        end
    end

    if i == 0 then
        print("[UFnDump] (no children found; either no params or UE4SS can't traverse)")
    end
end

function Util.find_all(class_name)
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

function Util.find_first(class_name)
    if not class_name or class_name == "" then return nil end
    if _G.FindFirstOf then
        local ok, res = pcall(_G.FindFirstOf, class_name)
        if ok then return res end
    end
    if _G.UE and UE.FindFirstOf then
        local ok, res = pcall(UE.FindFirstOf, class_name)
        if ok then return res end
    end
    local all = Util.find_all(class_name)
    if all and #all > 0 then
        return all[1]
    end
    return nil
end

function Util.is_world_actor(actor)
    if not Util.is_valid(actor) then return false end
    if actor.GetWorld then
        local ok, world = pcall(actor.GetWorld, actor)
        if ok and world == nil then
            return false
        end
    end
    return true
end

local function _get_uehelpers()
    if _UEH == false then return nil end
    if _UEH == nil then
        local ok, mod = pcall(require, "UEHelpers")
        if ok then _UEH = mod else _UEH = false end
    end
    return _UEH or nil
end

local function _get_pointers()
    if _G.BlackboxRecode and _G.BlackboxRecode.Pointers then
        return _G.BlackboxRecode.Pointers
    end
    if _G.Pointers then
        return _G.Pointers
    end
    return nil
end

function Util.get_local_controller(opts)
    local now = Util.now_time()
    local ttl = (opts and opts.ttl) or _PC_CACHE_TTL
    if _CACHED_PC and (now - _CACHED_PC_TIME) < ttl and Util.is_valid(_CACHED_PC) then
        return _CACHED_PC
    end

    local UEH = _get_uehelpers()
    if UEH and UEH.GetPlayerController then
        local ok, pc = pcall(UEH.GetPlayerController)
        if ok and Util.is_valid(pc) then
            local flag = Util.safe_get_field(pc, "bIsLocalPlayerController")
            if flag == true then
                _CACHED_PC = pc
                _CACHED_PC_TIME = now
                return pc
            end
        end
    end

    local P = _get_pointers()
    local cls = (opts and opts.class_name) or (P and P.CLASSES and P.CLASSES.PlayerController) or "BP_MyPlayerController_C"
    local controllers = Util.find_all(cls) or {}
    for _, pc in ipairs(controllers) do
        if Util.is_valid(pc) then
            local flag = Util.safe_get_field(pc, "bIsLocalPlayerController")
            if flag == true then
                _CACHED_PC = pc
                _CACHED_PC_TIME = now
                return pc
            end
        end
    end
    return nil
end

function Util.get_current_map(opts)
    local now = Util.now_time()
    local ttl = (opts and opts.ttl) or _MAP_CACHE_TTL
    if _CACHED_MAP and (now - _CACHED_MAP_TIME) < ttl then
        return _CACHED_MAP
    end

    local pc = Util.get_local_controller(opts)
    local new_map = "Unknown"
    local P = _get_pointers()
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

    if new_map == "Unknown" then
        local UEH = _get_uehelpers()
        if UEH and UEH.GetWorld then
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
    end

    _CACHED_MAP = new_map
    _CACHED_MAP_TIME = now
    return _CACHED_MAP
end

function Util.get_local_pawn(opts)
    local now = Util.now_time()
    local ttl = (opts and opts.ttl) or _PAWN_CACHE_TTL
    if _CACHED_PAWN and (now - _CACHED_PAWN_TIME) < ttl and Util.is_world_actor(_CACHED_PAWN) then
        return _CACHED_PAWN
    end

    local pc = Util.get_local_controller(opts)
    if not pc then return nil end

    local pawn = nil
    if pc.K2_GetPawn then
        local ok, pwn = pcall(pc.K2_GetPawn, pc)
        if ok then pawn = pwn end
    end
    if pawn and Util.is_world_actor(pawn) then
        _CACHED_PAWN = pawn
        _CACHED_PAWN_TIME = now
        return pawn
    end

    local P = _get_pointers()
    local function find_local_character(class_name)
        if not class_name or class_name == "" then return nil end
        local chars = Util.find_all(class_name)
        if not chars then return nil end
        for _, ch in ipairs(chars) do
            if Util.is_world_actor(ch) then
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

    local map = Util.get_current_map(opts)
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
        _CACHED_PAWN = pawn
        _CACHED_PAWN_TIME = now
        return pawn
    end
    return nil
end

function Util.get_my_gamestate()
    local gs = Util.find_first("BP_MyGameState_C")
    if gs then return gs end
    local ok, world = pcall(function()
        return UEHelpers and UEHelpers.GetWorld and UEHelpers.GetWorld() or nil
    end)
    if ok and world and world.GetGameState then
        local ok2, g = pcall(world.GetGameState, world)
        if ok2 and g then return g end
    end
    return nil
end

Util._ufn_cache = Util._ufn_cache or {}
function Util.get_ufunction(path)
    -- path example:
    -- "Function /Game/Blueprints/Core/BP_MyGameState.BP_MyGameState_C:ChangeLightStatut"
    if not path or path == "" then return nil end
    if Util._ufn_cache[path] then return Util._ufn_cache[path] end

    if not _G.StaticFindObject then return nil end
    local ok, ufn = pcall(_G.StaticFindObject, path)
    if ok and ufn then
        Util._ufn_cache[path] = ufn
        return ufn
    end
    return nil
end

-- Export commonly used helpers globally for other modules.
_G.BlackboxRecode = _G.BlackboxRecode or {}
_G.BlackboxRecode.Util = Util
_G.trim = _G.trim or Util.trim
_G.split_ws = _G.split_ws or Util.split_ws
_G.now_time = _G.now_time or Util.now_time
_G.is_valid = _G.is_valid or Util.is_valid
_G.safe_get_field = _G.safe_get_field or Util.safe_get_field
_G.safe_call = _G.safe_call or Util.safe_call
_G.safe_call_err = _G.safe_call_err or Util.safe_call_err
_G.find_all = _G.find_all or Util.find_all
_G.find_first = _G.find_first or Util.find_first
_G.is_world_actor = _G.is_world_actor or Util.is_world_actor
_G.get_local_controller = _G.get_local_controller or Util.get_local_controller
_G.get_current_map = _G.get_current_map or Util.get_current_map
_G.get_local_pawn = _G.get_local_pawn or Util.get_local_pawn
_G.dump_ufunction_params = _G.dump_ufunction_params or Util.dump_ufunction_params

return Util
