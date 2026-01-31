local function _script_dir()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return (src:match("^(.*[\\/])") or "")
end

local DIR = _script_dir()

local function load_local(file)
    local ok, mod = pcall(dofile, DIR .. file)
    if not ok then
        print("[BlackboxRecode] Failed loading:", file, "=>", tostring(mod))
        return nil
    end
    return mod
end

local Util     = load_local("util.lua") or {}
local Pointers = load_local("pointers.lua") or {}
local Teleport = load_local("teleport.lua") or {}
local Commands = load_local("commands.lua") or {}
local Registry = load_local("registry.lua") or {}

_G.BlackboxRecode = _G.BlackboxRecode or {}
_G.BlackboxRecode.Util     = Util
_G.BlackboxRecode.Pointers = Pointers
_G.BlackboxRecode.Teleport = Teleport
_G.BlackboxRecode.Commands = Commands
_G.BlackboxRecode.Registry = Registry
_G.BlackboxRecode.UI = _G.BlackboxRecode.UI or {}
_G.BlackboxRecode.HookWatchDeep = true
_G.BlackboxRecode.HookWatchUseToString = true

if Util.log then
    Util.log("[BlackboxRecode] Loaded. Initializing modules...")
else
    print("[BlackboxRecode] Loaded. Initializing modules...")
end

if Teleport and Teleport.init then
    Teleport.init(Util, Pointers)
end

if Commands and Commands.init then
    Commands.init(Util, Pointers, Teleport, Registry)
else
    print("[BlackboxRecode] commands.lua missing Commands.init(Util, Pointers, Teleport, Registry)")
end

if Registry and Registry.init then
    Registry.init(Util, Pointers, Teleport)
end

local function _external_dir()
    local dir = _script_dir()
    dir = dir:gsub("[\\/]+$", "")
    dir = dir:gsub("[\\/]Scripts$", "")
    return dir .. "/External/"
end

local BRIDGE_DIR = _external_dir()
local BRIDGE_CMD_PATH = BRIDGE_DIR .. "bridge_cmd.txt"
local BRIDGE_ACK_PATH = BRIDGE_DIR .. "bridge_ack.txt"
local BRIDGE_NOTICE_PATH = BRIDGE_DIR .. "bridge_notice.txt"
local BRIDGE_REGISTRY_PATH = BRIDGE_DIR .. "bridge_registry.txt"
local BRIDGE_STATE_PATH = BRIDGE_DIR .. "bridge_state.txt"

local OVERLAY_LAUNCH_GUARD_KEY = "_BLACKBOX_OVERLAY_LAUNCHED"
local EXTERNAL_OVERLAY_EXE = BRIDGE_DIR .. "BlackboxOverlay.exe"
local EXTERNAL_OVERLAY_PY = BRIDGE_DIR .. "BlackboxOverlay.py"

local function _is_windows()
    local sep = package.config and package.config:sub(1, 1)
    return sep == "\\"
end

local function _is_process_running(exe_name)
    if not _is_windows() then return false end
    local name = tostring(exe_name or "")
    if name == "" then return false end
    local cmd = string.format('cmd /c tasklist /FI "IMAGENAME eq %s" /NH', name)
    local pipe = io.popen(cmd)
    if not pipe then return false end
    local out = pipe:read("*a") or ""
    pipe:close()
    out = out:lower()
    if out:find("no tasks are running") or out:find("info:") then
        return false
    end
    return out:find(name:lower(), 1, true) ~= nil
end

local function _exec_ok(cmd)
    local ok, kind, code = os.execute(cmd)
    if type(ok) == "boolean" then
        if ok then return true end
        if type(code) == "number" then return code == 0 end
        return false
    end
    if type(ok) == "number" then
        return ok == 0
    end
    if type(code) == "number" then
        return code == 0
    end
    return false
end

local function _file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function _find_python_launcher()
    local candidates = {
        { exe = "pythonw", args = "" },
        { exe = "pyw", args = "-3" },
        { exe = "python", args = "" },
        { exe = "py", args = "-3" },
    }
    for _, c in ipairs(candidates) do
        if _exec_ok(string.format('cmd /c where %s >nul 2>nul', c.exe)) then
            return c.exe, c.args
        end
    end
    return nil, nil
end

local function _launch_overlay_py_once()
    if not _is_windows() then
        return
    end
    if _G and _G[OVERLAY_LAUNCH_GUARD_KEY] then
        return
    end
    if not os or not os.execute then
        print("[Overlay] os.execute not available; cannot launch overlay.")
        return
    end
    if _file_exists(EXTERNAL_OVERLAY_EXE) then
        if _is_process_running("BlackboxOverlay.exe") then
            if _G then
                _G[OVERLAY_LAUNCH_GUARD_KEY] = true
            end
            return
        end
        local cmd = string.format('cmd /c start "" "%s"', EXTERNAL_OVERLAY_EXE)
        local ok = _exec_ok(cmd)
        if not ok then
            print("[Overlay] Launch failed:", cmd)
            return
        end
        if _G then
            _G[OVERLAY_LAUNCH_GUARD_KEY] = true
        end
        return
    end
    if not _file_exists(EXTERNAL_OVERLAY_PY) then
        print("[Overlay] Missing overlay script:", EXTERNAL_OVERLAY_PY)
        return
    end
    local exe, args = _find_python_launcher()
    if not exe then
        print("[Overlay] Python not found on PATH; cannot launch overlay.")
        return
    end
    local cmd = string.format('cmd /c start "" "%s" %s "%s"', exe, args or "", EXTERNAL_OVERLAY_PY)
    local ok = _exec_ok(cmd)
    if not ok then
        print("[Overlay] Launch failed:", cmd)
        return
    end
    if _G then
        _G[OVERLAY_LAUNCH_GUARD_KEY] = true
    end
end

_launch_overlay_py_once()

local PANEL_OPEN = (_G.BlackboxRecode and _G.BlackboxRecode.PanelOpen) and true or false

local function _bridge_read_all(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local d = f:read("*a") or ""
    f:close()
    return d
end

local function _bridge_clear(path)
    local f = io.open(path, "w")
    if f then
        f:write("")
        f:close()
    end
end

local function _sanitize_token(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n|]", " ")
    return s
end

local function _bridge_ack(id, ok, msg)
    id = tostring(id or "")
    if id == "" then return end
    local line = string.format("ACK|%s|%s|%s\n", id, ok and "1" or "0", _sanitize_token(msg or ""))
    local f = io.open(BRIDGE_ACK_PATH, "w")
    if f then
        f:write(line)
        f:close()
    end
end

local LAST_NOTICE_TEXT = ""
local LAST_NOTICE_TIME = 0
local NOTICE_COOLDOWN = 0.15

local function _bridge_notice(text)
    text = tostring(text or "")
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if text == "" then return end
    if text == LAST_NOTICE_TEXT and (now - LAST_NOTICE_TIME) < NOTICE_COOLDOWN then
        return
    end
    LAST_NOTICE_TEXT = text
    LAST_NOTICE_TIME = now
    local f = io.open(BRIDGE_NOTICE_PATH, "w")
    if f then
        f:write(text .. "\n")
        f:close()
    end
end

local function _bridge_parse_cmd(line)
    local id, name, arg = "", "", ""

    local p1, p2, p3, p4 = line:match("^(.-)%|(.-)%|(.-)%|(.*)$")
    if p1 and p2 and p3 and tostring(p1):upper() == "CMD" then
        id = tostring(p2 or "")
        name = tostring(p3 or "")
        arg = tostring(p4 or "")
        return id, name, arg
    end

    local n, a, i = line:match("^(.-)%|(.-)%|(.*)$")
    if n then
        name = tostring(n or "")
        arg = tostring(a or "")
        id = tostring(i or "")
        return id, name, arg
    end

    local n2, a2 = line:match("^(.-)%|(.*)$")
    if n2 then
        name = tostring(n2 or "")
        arg = tostring(a2 or "")
        id = ""
        return id, name, arg
    end

    name = tostring(line or "")
    return "", name, ""
end

local _registry_tick

local function _bridge_exec_cmd(line)
    if not Commands or not Commands.run then
        return
    end
    local id, name, arg = _bridge_parse_cmd(line)
    name = tostring(name or ""):lower()
    name = (Util and Util.trim and Util.trim(name)) or name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local args = {}
    if Util and Util.split_ws then
        args = Util.split_ws(arg)
    else
        for part in tostring(arg or ""):gmatch("%S+") do
            args[#args + 1] = part
        end
    end
    local ok, res = Commands.run(name, table.unpack(args))
    _bridge_ack(id, ok, res or "")
    if name == "listplayers_gui" and _emit_tp_notice then
        _emit_tp_notice(true)
    end
    if name == "world_registry_scan" then
        _registry_tick(true)
    end
    if name == "state_snapshot" or name == "registry_clear" or name == "registry_rebuild" then
        _registry_tick(true)
    end
end

local LAST_PLAYERS_TEXT = ""
local LAST_TP_TEXT = ""

local function _emit_tp_notice(force)
    if not Commands or not Commands.run then return end
    local ok, res = Commands.run("tp_gui_state")
    if ok and type(res) == "string" and res:find("^TPSTATE=") then
        if force or res ~= LAST_TP_TEXT then
            LAST_TP_TEXT = res
            _bridge_notice(res)
            _bridge_ack("0", true, res)
        end
    end
end

local function _emit_players_notice(force)
    if not Commands or not Commands.run then return end
    local ok, res = Commands.run("listplayers_gui")
    if ok and type(res) == "string" and res:find("^PLAYERS=") then
        local changed = res ~= LAST_PLAYERS_TEXT
        if force or changed then
            LAST_PLAYERS_TEXT = res
            _bridge_notice(res)
        end
        _emit_tp_notice(true)
    end
end

local LAST_PUZZLES_TIME = 0
local LAST_PUZZLES_TEXT = ""
local PUZZLES_COOLDOWN = 0.25

local function _emit_puzzles_notice()
    if not Commands or not Commands.run then return end
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if (now - LAST_PUZZLES_TIME) < PUZZLES_COOLDOWN then
        return
    end
    LAST_PUZZLES_TIME = now
    local ok, res = Commands.run("puzzlestate")
    if ok and type(res) == "string" and res:find("^PUZZLES=") then
        if res ~= LAST_PUZZLES_TEXT then
            LAST_PUZZLES_TEXT = res
            _bridge_notice(res)
            _bridge_ack("0", true, res)
        end
    end
end

local LAST_CONTRACTS_TIME = 0
local LAST_CONTRACTS_TEXT = ""
local CONTRACTS_COOLDOWN = 0.25

local function _emit_contracts_notice(force)
    if not Commands or not Commands.run then return end
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if (not force) and (now - LAST_CONTRACTS_TIME) < CONTRACTS_COOLDOWN then
        return
    end
    local ok, res = Commands.run("contract_gui_state")
    if ok and type(res) == "string" and res:find("^CONTRACTS=") then
        if force or res ~= LAST_CONTRACTS_TEXT then
            LAST_CONTRACTS_TEXT = res
            LAST_CONTRACTS_TIME = now
            _bridge_notice(res)
            _bridge_ack("0", true, res)
        end
    end
end

local LAST_REGISTRY_TEXT = ""
local LAST_REGISTRY_TIME = 0
local REGISTRY_BRIDGE_COOLDOWN = 0.15

local function _bridge_registry(text)
    text = tostring(text or "")
    if text == "" then return end
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if text == LAST_REGISTRY_TEXT and (now - LAST_REGISTRY_TIME) < REGISTRY_BRIDGE_COOLDOWN then
        return
    end
    LAST_REGISTRY_TEXT = text
    LAST_REGISTRY_TIME = now
    local f = io.open(BRIDGE_REGISTRY_PATH, "w")
    if f then
        f:write(text .. "\n")
        f:close()
    end
end

local LAST_STATE_TEXT = ""
local LAST_STATE_TIME = 0
local STATE_COOLDOWN = 0.25

local function _bridge_state(text, force)
    text = tostring(text or "")
    if text == "" then return end
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if not force and text == LAST_STATE_TEXT and (now - LAST_STATE_TIME) < STATE_COOLDOWN then
        return
    end
    LAST_STATE_TEXT = text
    LAST_STATE_TIME = now
    local f = io.open(BRIDGE_STATE_PATH, "w")
    if f then
        f:write(text .. "\n")
        f:close()
    end
end

local function _set_panel_open(open, force_notice)
    local want = open and true or false
    if (not force_notice) and want == PANEL_OPEN then
        return
    end
    PANEL_OPEN = want
    _G.BlackboxRecode.PanelOpen = PANEL_OPEN
    _bridge_notice("PANEL=" .. (PANEL_OPEN and "1" or "0"))
end

local function _is_valid(obj)
    if not obj then return false end
    if obj.IsValid then
        local ok, v = pcall(obj.IsValid, obj)
        return ok and v
    end
    return true
end

local function _build_state_payload()
    local map_name = (Util and Util.get_current_map and Util.get_current_map())
        or (_G.get_current_map and _G.get_current_map())
        or (Teleport and Teleport.get_current_map and Teleport.get_current_map())
        or "Unknown"
    local pawn = (Util and Util.get_local_pawn and Util.get_local_pawn())
        or (_G.get_local_pawn and _G.get_local_pawn())
        or (Teleport and Teleport.get_local_pawn and Teleport.get_local_pawn())
        or nil
    local pawn_ok = _is_valid(pawn)
    local world_ready = (map_name ~= "Unknown" and map_name ~= "")
    local radar_active = (_G.BlackboxRecode and _G.BlackboxRecode.RadarActive) and true or false
    local protocol_version = 1

    local counts = Registry and Registry.get_counts and Registry.get_counts() or {}
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()

    local parts = {
        "MAP:" .. tostring(map_name),
        "WORLD:" .. (world_ready and "1" or "0"),
        "PAWN:" .. (pawn_ok and "1" or "0"),
        "RADAR:" .. (radar_active and "1" or "0"),
        "PANEL:" .. (PANEL_OPEN and "1" or "0"),
        "PROTO:" .. tostring(protocol_version),
        "REGTOTAL:" .. tostring(counts.total or 0),
        "MON:" .. tostring(counts.monsters or 0),
        "KEY:" .. tostring(counts.keycards or 0),
        "DISK:" .. tostring(counts.disks or 0),
        "BLACK:" .. tostring(counts.blackbox or 0),
        "WEAPON:" .. tostring(counts.weapons or 0),
        "MONEY:" .. tostring(counts.money or 0),
        "PUZZLES:" .. tostring(counts.puzzles or 0),
        "EMIT:" .. string.format("%.3f", tonumber(counts.last_emit or 0)),
        "PRUNE:" .. string.format("%.3f", tonumber(counts.last_prune or 0)),
        "STATEWRITE:" .. string.format("%.3f", now),
    }
    return "STATE=" .. table.concat(parts, "#")
end

_registry_tick = function(force_emit)
    if not Registry or not Registry.tick then return end
    local payload = Registry.tick(force_emit)
    if payload and payload:find("^WORLD=") then
        _bridge_registry(payload)
    end
    local state_payload = _build_state_payload()
    if state_payload then
        _bridge_state(state_payload, force_emit)
    end
end

local function _registry_track(obj)
    if not Registry or not Registry.track then return end
    if Registry.track(obj) and Registry.request_emit then
        Registry.request_emit(false)
    end
end

local function _registry_untrack(obj)
    if not Registry or not Registry.untrack then return end
    if Registry.untrack(obj) and Registry.request_emit then
        Registry.request_emit(false)
    end
end

local REGISTRY_TICK_INTERVAL = 0.30
local _last_registry_tick = 0

local function _registry_tick_throttled(force_emit)
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if not force_emit and (now - _last_registry_tick) < REGISTRY_TICK_INTERVAL then
        return
    end
    _last_registry_tick = now
    _registry_tick(force_emit)
end

local function _hook_print(cat, fn)
    if not (_G.BlackboxRecode and _G.BlackboxRecode.HookPrints) then
        return
    end
    cat = tostring(cat or "Hook")
    fn = tostring(fn or "")
    if fn ~= "" then
        print(string.format("[Hook] %s -> %s", cat, fn))
    else
        print(string.format("[Hook] %s", cat))
    end
end

local _describe_value

local function _hook_safe_str(v)
    local t = type(v)
    if t == "string" then return v end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "userdata" or t == "table" then
        if v.GetString then
            local ok, s = pcall(v.GetString, v)
            if ok and type(s) == "string" then return s end
        end
        if v.String and type(v.String) == "string" then
            return v.String
        end
        if _G.BlackboxRecode and _G.BlackboxRecode.HookWatchUseToString and v.ToString then
            local ok, s = pcall(v.ToString, v)
            if ok and type(s) == "string" then return s end
        end
    end
    return nil
end

local function _hook_describe_userdata(v)
    local name = nil
    if v.GetName then
        local ok, n = pcall(v.GetName, v)
        if ok then
            name = _hook_safe_str(n)
        end
    end
    local class_name = nil
    if v.GetClass then
        local okc, cls = pcall(v.GetClass, v)
        if okc and cls and cls.GetName then
            local okn, cn = pcall(cls.GetName, cls)
            if okn then
                class_name = _hook_safe_str(cn)
            end
        end
    end
    local full = nil
    if _G.BlackboxRecode and _G.BlackboxRecode.HookWatchUseFullName and v.GetFullName then
        local okf, fn = pcall(v.GetFullName, v)
        if okf then
            full = _hook_safe_str(fn)
        end
    end
    if full and full ~= "" then
        return "<userdata:" .. full .. ">"
    end
    if class_name and name then
        return "<userdata:" .. class_name .. ":" .. name .. ">"
    end
    if class_name then
        return "<userdata:" .. class_name .. ">"
    end
    if name then
        return "<userdata:" .. name .. ">"
    end
    return "<userdata>"
end

local function _hook_arg_to_string(v)
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "userdata" then
        if _G.BlackboxRecode and _G.BlackboxRecode.HookWatchDeep and _describe_value then
            local ok, desc = pcall(_describe_value, v, 1, {})
            if ok and desc and desc ~= "" then
                return desc
            end
        end
        return _hook_describe_userdata(v)
    end
    if t == "table" then
        local obj = rawget(v, "Object") or rawget(v, "This") or rawget(v, "self")
        if _is_valid(obj) then
            return "ctx{" .. _hook_describe_userdata(obj) .. "}"
        end
        return "<table>"
    end
    return "<" .. t .. ">"
end

local function _hook_ctx_to_string(ctx)
    if type(ctx) ~= "table" then
        return _hook_arg_to_string(ctx)
    end
    local obj = rawget(ctx, "Object") or rawget(ctx, "This") or rawget(ctx, "self")
    local fn = rawget(ctx, "Function")
    local obj_s = obj and _hook_arg_to_string(obj) or nil
    local fn_s = fn and _hook_arg_to_string(fn) or nil
    if obj_s or fn_s then
        return "ctx{obj=" .. (obj_s or "?") .. " fn=" .. (fn_s or "?") .. "}"
    end
    return "ctx"
end

local function _hook_print_args(tag, fn, ctx, ...)
    if not (_G.BlackboxRecode and _G.BlackboxRecode.HookPrints) then
        return
    end
    local parts = {}
    parts[#parts + 1] = string.format("[HookWatch] %s", tostring(fn or tag or ""))
    if ctx ~= nil then
        parts[#parts + 1] = _hook_ctx_to_string(ctx)
    end
    local argc = select("#", ...)
    if argc > 0 then
        local args = {}
        for i = 1, argc do
            args[#args + 1] = _hook_arg_to_string(select(i, ...))
        end
        parts[#parts + 1] = "args=" .. table.concat(args, ", ")
    end
    print(table.concat(parts, " "))
end

local function _try_register_hook(fn_name, cb)
    if not _G.RegisterHook then return false end
    local name = tostring(fn_name or "")
    if name:sub(1, 9) == "Function " then
        name = name:sub(10)
    end
    if name == "" then return false end
    local ok, hook_id = pcall(RegisterHook, name, cb)
    return ok and hook_id ~= nil
end

local CUSTOM_HOOK_WATCH_LIST = {
    "/Game/Blueprints/Screens/Terminals/BP_TerminalBasic.BP_TerminalBasic_C:BPI_Interactable_Input",
    "/Game/Blueprints/Core/BP_MyGameState.BP_MyGameState_C:ChangeLightStatut",
}

if _G.BlackboxRecode then
    if type(_G.BlackboxRecode.HookWatchList) == "table" then
        CUSTOM_HOOK_WATCH_LIST = _G.BlackboxRecode.HookWatchList
    else
        _G.BlackboxRecode.HookWatchList = CUSTOM_HOOK_WATCH_LIST
    end
end

local _custom_hooked = {}

local function _register_custom_hooks()
    if not _G.RegisterHook then return end
    for _, fn in ipairs(CUSTOM_HOOK_WATCH_LIST or {}) do
        local name = tostring(fn or "")
        if name ~= "" and not _custom_hooked[name] then
            local ok = _try_register_hook(name, function(ctx, ...)
                _hook_print_args("Custom", name, ctx, ...)
            end)
            if ok then
                _custom_hooked[name] = true
                if Util and Util.log then
                    Util.log("[BlackboxRecode] HookWatch active:", name)
                end
            else
                if Util and Util.warn then
                    Util.warn("[BlackboxRecode] HookWatch failed:", name)
                end
            end
        end
    end
end

local BRIDGE_POLL_INTERVAL = 0.10
local _bridge_last_poll = 0.0

local function _bridge_poll()
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if (now - _bridge_last_poll) < BRIDGE_POLL_INTERVAL then
        return
    end
    _bridge_last_poll = now
    local data = _bridge_read_all(BRIDGE_CMD_PATH)
    if data and data ~= "" then
        _bridge_clear(BRIDGE_CMD_PATH)
        for line in tostring(data):gmatch("[^\r\n]+") do
            _bridge_exec_cmd(line)
        end
    end
end

local function _start_bridge_loop()
    if _G.LoopAsync then
        LoopAsync(100, function()
            _bridge_poll()
            return false
        end)
        if Util and Util.log then
            Util.log("[BlackboxRecode] GUI bridge active (LoopAsync).")
        end
        return
    end

    if _G.RegisterHook then
        local candidates = {
            "/Script/Engine.PlayerController:PlayerTick",
            "/Script/Engine.PlayerController:Tick",
            "/Script/Engine.Actor:Tick",
        }
        for _, fn in ipairs(candidates) do
            local ok, hook_id = pcall(RegisterHook, fn, function()
                _bridge_poll()
            end)
            if ok and hook_id then
                if Util and Util.log then
                    Util.log("[BlackboxRecode] GUI bridge active (RegisterHook):", fn)
                end
                return
            end
        end
        if Util and Util.warn then
            Util.warn("[BlackboxRecode] RegisterHook failed; GUI bridge disabled.")
        else
            print("[WARN] RegisterHook failed; GUI bridge disabled.")
        end
        return
    end

    if Util and Util.warn then
        Util.warn("[BlackboxRecode] LoopAsync/RegisterHook missing; GUI bridge disabled.")
    else
        print("[WARN] LoopAsync/RegisterHook missing; GUI bridge disabled.")
    end
end

_start_bridge_loop()

_G.BlackboxRecode.BridgeNotice = _bridge_notice
_G.BlackboxRecode.BridgeRegistry = _bridge_registry
_G.BlackboxRecode.BridgeState = _bridge_state

local player_hooks = {
    "/Script/Engine.PlayerController:ClientRestart",
    "/Script/Engine.GameStateBase:OnRep_PlayerArray",
    "/Script/Engine.PlayerState:OnRep_PlayerName",
    "/Script/Engine.GameModeBase:PostLogin",
    "/Script/Engine.GameModeBase:Logout",
}

for _, fn in ipairs(player_hooks) do
    _try_register_hook(fn, function()
        _hook_print("Players", fn)
        _emit_players_notice(false)
        _emit_tp_notice(true)
    end)
end

_register_custom_hooks()

local PUZZLE_MATCH = {
    "BP_ReactorControl_Terminal_REFACT_C",
    "BP_GAZ_Control_Terminal_REFACT_C",
    "BP_ValvePipe_C",
}

local function _is_puzzle_actor(o)
    if not o then return false end
    local full = ""
    if type(o) == "userdata" or type(o) == "table" then
        if o.GetFullName then
            local ok, res = pcall(o.GetFullName, o)
            if ok then
                full = tostring(res or "")
            end
        end
    end
    if full == "" then
        full = tostring(o)
    end
    for _, s in ipairs(PUZZLE_MATCH) do
        if full:find(s, 1, true) then
            return true, s, full
        end
    end
    return false, nil, full
end

local function _puzzle_bump(tag)
    _hook_print("Puzzles", tag)
    _emit_puzzles_notice()
end

local CONTRACT_LIST_HOOKS = {
    "/Game/Blueprints/Screens/Terminals/Contract/WBP_MainContractManager.WBP_MainContractManager_C:BPI_ContractTerminal_SetContractList",
    "/Game/Blueprints/Screens/Terminals/Contract/WBP_Contract_ChoosePage.WBP_Contract_ChoosePage_C:BPI_ContractTerminal_SetContractList",
    "/Game/Blueprints/Screens/Terminals/Contract/BPI_ContractTerminal.BPI_ContractTerminal_C:BPI_ContractTerminal_SetContractList",
}
local CONTRACT_LIST_COUNT = 0
local LAST_CONTRACT_LIST_TIME = 0
local CONTRACT_LIST_DUMP_MAX_DEPTH = 2
local CONTRACT_LIST_DUMP_MAX_FIELDS = 20
local CONTRACT_LIST_PROP_MAX_FIELDS = 200
local CONTRACT_LIST_READY_COUNT = 20
local CONTRACT_LIST_READY_COOLDOWN = 0.35
local _last_contract_ready_count = 0
local _last_contract_ready_time = 0
-- _describe_value assigned later (used by hook printer when HookWatchDeep is enabled)
local _try_get_fullname

local _safe_get_field = _G.safe_get_field or (Util and Util.safe_get_field)

local function _is_remote_param(obj)
    if obj == nil then return false end
    local raw = tostring(obj or "")
    return raw ~= "" and raw:find("RemoteUnrealParam", 1, true) ~= nil
end

local function _unwrap_remote_value_once(obj)
    if obj == nil then return nil end
    if not _is_remote_param(obj) then
        return obj
    end
    local candidates = {
        "GetValue",
        "Get",
    }
    for _, name in ipairs(candidates) do
        local fn = _safe_get_field(obj, name)
        if type(fn) == "function" then
            local ok, val = pcall(fn, obj)
            if ok and val ~= nil and val ~= obj then
                return val
            end
        end
    end
    local ok_val, v = pcall(function() return obj.Value end)
    if ok_val and v ~= nil and v ~= obj then
        return v
    end
    local ok_obj, v2 = pcall(function() return obj.Object end)
    if ok_obj and v2 ~= nil and v2 ~= obj then
        return v2
    end
    return obj
end

local function _unwrap_remote_value(obj)
    local cur = obj
    if not _is_remote_param(cur) then
        return cur
    end
    local seen = {}
    for _ = 1, 6 do
        if not _is_remote_param(cur) then
            return cur
        end
        if seen[cur] then
            break
        end
        seen[cur] = true
        local next_val = _unwrap_remote_value_once(cur)
        if next_val == nil or next_val == cur then
            break
        end
        cur = next_val
    end
    return cur
end

local function _ui_cache_get()
    _G.BlackboxRecode = _G.BlackboxRecode or {}
    _G.BlackboxRecode.UI = _G.BlackboxRecode.UI or {}
    return _G.BlackboxRecode.UI
end

local function _ui_cache_set(key, obj)
    if not _is_valid(obj) then return false end
    local ui = _ui_cache_get()
    if _is_valid(ui[key]) then
        return false
    end
    ui[key] = obj
    return true
end

local function _ui_obj_has_token(obj, token)
    if not obj then return false end
    token = tostring(token or "")
    if token == "" then return false end

    local candidates = {}
    local ok, s = pcall(function() return tostring(obj) end)
    if ok and s then candidates[#candidates + 1] = s end

    local fn_full = _safe_get_field(obj, "GetFullName")
    if type(fn_full) == "function" then
        local ok2, v = pcall(fn_full, obj)
        if ok2 and v then candidates[#candidates + 1] = tostring(v) end
    end
    local fn_name = _safe_get_field(obj, "GetName")
    if type(fn_name) == "function" then
        local ok2, v = pcall(fn_name, obj)
        if ok2 and v then candidates[#candidates + 1] = tostring(v) end
    end

    local fn_class = _safe_get_field(obj, "GetClass")
    if type(fn_class) == "function" then
        local okc, cls = pcall(fn_class, obj)
        if okc and cls then
            local ok3, s2 = pcall(function() return tostring(cls) end)
            if ok3 and s2 then candidates[#candidates + 1] = s2 end
            local fn_cfull = _safe_get_field(cls, "GetFullName")
            if type(fn_cfull) == "function" then
                local ok4, v = pcall(fn_cfull, cls)
                if ok4 and v then candidates[#candidates + 1] = tostring(v) end
            end
            local fn_cname = _safe_get_field(cls, "GetName")
            if type(fn_cname) == "function" then
                local ok4, v = pcall(fn_cname, cls)
                if ok4 and v then candidates[#candidates + 1] = tostring(v) end
            end
        end
    end

    for _, c in ipairs(candidates) do
        if tostring(c):find(token, 1, true) then
            return true
        end
    end
    return false
end

local UI_WIDGET_CACHE = {
    MainContractManager = "WBP_MainContractManager_C",
    ChoosePage = "WBP_Contract_ChoosePage_C",
    DetailPage = "WBP_Contract_DetailPage_C",
    RecapPage = "WBP_Contract_RecapPage_C",
    MapDetailsPage = "WBP_Contract_MapDetailsPage_C",
}

local UScriptStructStaticClass = nil
pcall(function()
    UScriptStructStaticClass = StaticFindObject("/Script/CoreUObject.ScriptStruct")
end)

local function _is_script_struct(obj)
    if not obj then return false end
    local t = type(obj)
    if t ~= "userdata" and t ~= "table" then
        return false
    end
    local fn_is_a = _safe_get_field(obj, "IsA")
    if UScriptStructStaticClass and type(fn_is_a) == "function" then
        local ok, v = pcall(fn_is_a, obj, UScriptStructStaticClass)
        if ok and v then
            return true
        end
    end
    local fn_type = _safe_get_field(obj, "type")
    if type(fn_type) == "function" then
        local ok, v = pcall(fn_type, obj)
        if ok and v == "UScriptStruct" then
            return true
        end
    end
    local full = _try_get_fullname(obj)
    if full and full:find("UserDefinedStruct", 1, true) then
        return true
    end
    return false
end

local function _dump_struct_fields(param, struct_type, depth, seen)
    local target = struct_type or param
    local struct_name = _try_get_fullname(target) or _try_get_fullname(param) or "Struct"
    if depth <= 0 then
        return struct_name
    end
    local fields = {}
    local count = 0
    local ok = pcall(function()
        if not target or not target.ForEachProperty then
            return
        end
        target:ForEachProperty(function(prop)
            count = count + 1
            if count > CONTRACT_LIST_DUMP_MAX_FIELDS then
                return true
            end
            local fname = nil
            if prop and prop.GetFName then
                local okn, fn = pcall(prop.GetFName, prop)
                if okn and fn and fn.ToString then
                    local ok2, s = pcall(fn.ToString, fn)
                    if ok2 and s then fname = s end
                end
            end
            if not fname or fname == "" then
                return
            end
            local okv, val = false, nil
            if param ~= nil then
                okv, val = pcall(function() return param[fname] end)
            end
            if (not okv) and target ~= nil and target ~= param then
                okv, val = pcall(function() return target[fname] end)
            end
            if okv then
                fields[#fields + 1] = fname .. "=" .. _describe_value(val, depth - 1, seen)
            else
                fields[#fields + 1] = fname .. "=<err>"
            end
        end)
    end)
    if not ok then
        return struct_name
    end
    local suffix = ""
    if count > CONTRACT_LIST_DUMP_MAX_FIELDS then
        suffix = " ...(+)"
    end
    return struct_name .. "{" .. table.concat(fields, ", ") .. "}" .. suffix
end

_try_get_fullname = function(obj)
    if not obj then return nil end
    local fn_full = _safe_get_field(obj, "GetFullName")
    if type(fn_full) == "function" then
        local ok, v = pcall(fn_full, obj)
        if ok and v then return tostring(v) end
    end
    local fn_name = _safe_get_field(obj, "GetName")
    if type(fn_name) == "function" then
        local ok, v = pcall(fn_name, obj)
        if ok and v then return tostring(v) end
    end
    return nil
end

local function _try_get_class(obj)
    if not obj then return nil end
    local fn_class = _safe_get_field(obj, "GetClass")
    if type(fn_class) == "function" then
        local ok, v = pcall(fn_class, obj)
        if ok and v then
            local name = _try_get_fullname(v)
            if name then return name end
        end
    end
    return nil
end

local function _unwrap_remote_param(obj, depth, seen)
    local raw = tostring(obj or "")
    if raw == "" or (not raw:find("RemoteUnrealParam", 1, true)) then
        return nil
    end

    local candidates = {
        "GetValue",
        "Get",
        "ToString",
        "GetString",
    }
    for _, name in ipairs(candidates) do
        local fn = _safe_get_field(obj, name)
        if type(fn) == "function" then
            local ok, val = pcall(fn, obj)
            if ok and val ~= nil and val ~= obj then
                if _is_script_struct(val) then
                    return "RemoteUnrealParam: " .. _dump_struct_fields(obj, val, depth, seen)
                end
                return "RemoteUnrealParam: " .. _describe_value(val, depth, seen)
            end
        end
    end

    local direct_fields = { "Value", "value", "Val", "val", "Data", "data" }
    for _, name in ipairs(direct_fields) do
        local val = _safe_get_field(obj, name)
        if val ~= nil and val ~= obj then
            if _is_script_struct(val) then
                return "RemoteUnrealParam: " .. _dump_struct_fields(obj, val, depth, seen)
            end
            return "RemoteUnrealParam: " .. _describe_value(val, depth, seen)
        end
    end

    return raw
end

local function _get_param_value(obj)
    if obj == nil then return nil end
    local t = type(obj)
    if t ~= "userdata" and t ~= "table" then
        return obj
    end
    for _, name in ipairs({ "get", "Get", "GetValue" }) do
        local fn = _safe_get_field(obj, name)
        if type(fn) == "function" then
            local ok, val = pcall(fn, obj)
            if ok and val ~= nil and val ~= obj then
                return val
            end
        end
    end
    for _, name in ipairs({ "Value", "value", "Val", "val", "Data", "data" }) do
        local val = _safe_get_field(obj, name)
        if val ~= nil and val ~= obj then
            return val
        end
    end
    return obj
end

local function _try_dump_struct_value(obj, depth, seen)
    if not _is_script_struct(obj) then
        return nil
    end
    local mapped = nil
    local fn_mapped_obj = _safe_get_field(obj, "IsMappedToObject")
    if type(fn_mapped_obj) == "function" then
        local ok, v = pcall(fn_mapped_obj, obj)
        if ok then mapped = v end
    end
    if mapped ~= true then
        local fn_mapped_prop = _safe_get_field(obj, "IsMappedToProperty")
        if type(fn_mapped_prop) == "function" then
            local ok, v = pcall(fn_mapped_prop, obj)
            if ok then mapped = v end
        end
    end
    if mapped == false then
        return nil
    end
    return _dump_struct_fields(obj, obj, depth, seen)
end

local function _get_prop_class_name(prop)
    if not prop then return "Property" end
    local fn_cls = _safe_get_field(prop, "GetClass")
    if type(fn_cls) == "function" then
        local okc, cls = pcall(fn_cls, prop)
        if okc and cls then
            local fn_name = _safe_get_field(cls, "GetFName")
            if type(fn_name) == "function" then
                local okn, nm = pcall(fn_name, cls)
                if okn and nm and nm.ToString then
                    local ok2, s = pcall(nm.ToString, nm)
                    if ok2 and s then
                        return tostring(s)
                    end
                end
            end
        end
    end
    return "Property"
end

local function _format_contract_value(val)
    val = _get_param_value(val)
    local t = type(val)
    if t == "nil" then
        return "nil"
    end
    if t == "boolean" then
        return val and "true" or "false"
    end
    if t == "number" then
        return tostring(val)
    end
    if t == "string" then
        return val
    end
    if t == "userdata" or t == "table" then
        local fn_tostring = _safe_get_field(val, "ToString")
        if type(fn_tostring) == "function" then
            local ok, s = pcall(fn_tostring, val)
            if ok and s ~= nil then
                return tostring(s)
            end
        end
        local ok, desc = pcall(_describe_value, val, 1, {})
        if ok then
            return desc
        end
    end
    return tostring(val)
end

local function _dump_contract_struct(contract_struct, depth, seen)
    if not contract_struct then
        return "<nil>"
    end
    if not _is_script_struct(contract_struct) then
        local ok, desc = pcall(_describe_value, contract_struct, 1, {})
        return ok and desc or tostring(contract_struct)
    end
    local struct_name = _try_get_fullname(contract_struct) or "ContractStruct"
    local fields = {}
    local count = 0
    local ok = pcall(function()
        if not contract_struct.ForEachProperty then
            return
        end
        contract_struct:ForEachProperty(function(prop)
            count = count + 1
            local fname = nil
            if prop and prop.GetFName then
                local okn, fn = pcall(prop.GetFName, prop)
                if okn and fn and fn.ToString then
                    local ok2, s = pcall(fn.ToString, fn)
                    if ok2 and s then fname = s end
                end
            end
            if not fname or fname == "" then
                return
            end
            local okv, val = pcall(function() return contract_struct[fname] end)
            local ptype = _get_prop_class_name(prop)
            local vstr = okv and _format_contract_value(val) or "<err>"
            fields[#fields + 1] = string.format("%s(%s)=%s", fname, ptype, vstr)
            if count >= CONTRACT_LIST_PROP_MAX_FIELDS then
                return true
            end
        end)
    end)
    if not ok then
        return struct_name
    end
    local suffix = ""
    if count >= CONTRACT_LIST_PROP_MAX_FIELDS then
        suffix = " ...(+)"
    end
    return struct_name .. "{" .. table.concat(fields, ", ") .. "}" .. suffix
end

local function _find_contract_array(args)
    for i = 1, #args do
        local arg = args[i]
        if arg ~= nil then
            local raw = tostring(arg)
            if raw:find("TArray", 1, true) then
                return i, arg
            end
            local val = _get_param_value(arg)
            if val ~= nil and val ~= arg then
                local raw2 = tostring(val)
                if raw2:find("TArray", 1, true) then
                    return i, val
                end
            end
        end
    end
    return nil, nil
end

local function _get_tarray_num(arr)
    if not arr then return nil end
    for _, name in ipairs({ "Num", "GetArrayNum", "GetNum" }) do
        local fn = _safe_get_field(arr, name)
        if type(fn) == "function" then
            local ok, v = pcall(fn, arr)
            if ok and type(v) == "number" then
                return math.max(0, math.floor(v))
            end
        end
    end
    local ok, v = pcall(function() return #arr end)
    if ok and type(v) == "number" then
        return math.max(0, math.floor(v))
    end
    return nil
end

local function _maybe_emit_contracts_ready(count)
    count = tonumber(count) or 0
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if count < CONTRACT_LIST_READY_COUNT then
        _last_contract_ready_count = count
        return
    end
    if _last_contract_ready_count >= CONTRACT_LIST_READY_COUNT and
        (now - _last_contract_ready_time) < CONTRACT_LIST_READY_COOLDOWN then
        return
    end
    _last_contract_ready_count = count
    _last_contract_ready_time = now
    _emit_contracts_notice(true)
end

local function _dump_contract_list(hook_name, self_obj, args)
    local idx, arr = _find_contract_array(args)
    if not arr then
        return false
    end
    local num = _get_tarray_num(arr) or 0
    local header = string.format("[Contracts] ContractList Arg=%d Count=%d Hook=%s",
        idx or -1, num, tostring(hook_name or "?"))
    _G.BlackboxRecode = _G.BlackboxRecode or {}
    _G.BlackboxRecode.ContractList = arr
    _G.BlackboxRecode.ContractListCount = num
    _G.BlackboxRecode.ContractListHook = tostring(hook_name or "?")
    _G.BlackboxRecode.ContractLists = _G.BlackboxRecode.ContractLists or {}
    _G.BlackboxRecode.ContractLists[tostring(hook_name or "?")] = arr
    _G.BlackboxRecode.ContractListTargets = _G.BlackboxRecode.ContractListTargets or {}
    _G.BlackboxRecode.ContractListTargets[tostring(hook_name or "?")] = _get_param_value(self_obj) or self_obj
    _maybe_emit_contracts_ready(num)
    if Util and Util.log then
        Util.log(header)
    else
        print(header)
    end

    local printed = 0
    local fn_each = _safe_get_field(arr, "ForEach")
    if type(fn_each) == "function" then
        local ok = pcall(fn_each, arr, function(_idx, elem)
            local contract = _get_param_value(elem)
            if not _is_script_struct(contract) and _is_script_struct(elem) then
                contract = elem
            end
            local line = _dump_contract_struct(contract, CONTRACT_LIST_DUMP_MAX_DEPTH, {})
            local msg = string.format("[Contracts] Contract[%d] %s", printed, line)
            if Util and Util.log then
                Util.log(msg)
            else
                print(msg)
            end
            printed = printed + 1
            return false
        end)
        if ok then
            return true
        end
    end

    local max_items = num
    if max_items <= 0 then
        return true
    end
    for i = 0, max_items - 1 do
        local val = nil
        local got = false
        local fn_get = _safe_get_field(arr, "Get")
        if type(fn_get) == "function" then
            local ok, v = pcall(fn_get, arr, i)
            if ok then
                val = v
                got = true
            end
        end
        if not got then
            local ok, v = pcall(function() return arr[i] end)
            if ok then
                val = v
                got = true
            end
        end
        local contract = got and _get_param_value(val) or nil
        if not _is_script_struct(contract) and _is_script_struct(val) then
            contract = val
        end
        local line = _dump_contract_struct(contract, CONTRACT_LIST_DUMP_MAX_DEPTH, {})
        local msg = string.format("[Contracts] Contract[%d] %s", i, line)
        if Util and Util.log then
            Util.log(msg)
        else
            print(msg)
        end
    end
    return true
end

local function _try_dump_tarray(obj, depth, seen)
    local raw = tostring(obj or "")
    if raw == "" or (not raw:find("TArray", 1, true)) then
        return nil
    end

    local num = nil
    for _, name in ipairs({ "Num", "GetArrayNum", "GetNum" }) do
        local fn = _safe_get_field(obj, name)
        if type(fn) == "function" then
            local ok, v = pcall(fn, obj)
            if ok and type(v) == "number" then
                num = v
                break
            end
        end
    end
    if num == nil then
        local v = _safe_get_field(obj, "Num")
        if type(v) == "number" then
            num = v
        end
    end
    if num == nil then
        return raw
    end
    num = math.max(0, math.floor(num))
    if depth <= 0 then
        return string.format("TArray[%d]", num)
    end

    local max_items = math.min(num, CONTRACT_LIST_DUMP_MAX_FIELDS)
    local items = {}
    local used_foreach = false
    local fn_each = _safe_get_field(obj, "ForEach")
    if type(fn_each) == "function" then
        local count = 0
        local ok = pcall(fn_each, obj, function(_idx, elem)
            if count >= max_items then
                return true
            end
            count = count + 1
            local okv, desc = pcall(_describe_value, elem, depth - 1, seen)
            if okv then
                items[#items + 1] = desc
            else
                items[#items + 1] = "<err>"
            end
            return false
        end)
        used_foreach = ok
    end

    if not used_foreach then
        for i = 0, max_items - 1 do
            local got = false
            local val = nil

            local fn_get = _safe_get_field(obj, "Get")
            if type(fn_get) == "function" then
                local ok, v = pcall(fn_get, obj, i)
                if ok then
                    val = v
                    got = true
                end
            end
            if not got then
                local fn_getv = _safe_get_field(obj, "GetValue")
                if type(fn_getv) == "function" then
                    local ok, v = pcall(fn_getv, obj, i)
                    if ok then
                        val = v
                        got = true
                    end
                end
            end
            if not got then
                local ok, v = pcall(function() return obj[i] end)
                if ok then
                    val = v
                    got = true
                end
            end

            if got then
                items[#items + 1] = _describe_value(val, depth - 1, seen)
            else
                items[#items + 1] = "?"
            end
        end
    end
    local suffix = ""
    if num > max_items then
        suffix = string.format(" ...(+%d)", num - max_items)
    end
    return string.format("TArray[%d]{%s}%s", num, table.concat(items, ", "), suffix)
end

_describe_value = function(v, depth, seen)
    local t = type(v)
    if t == "nil" then
        return "nil"
    end
    if t == "string" then
        return tostring(v)
    end
    if t == "number" or t == "boolean" then
        return tostring(v)
    end
    if t ~= "table" and t ~= "userdata" then
        return tostring(v)
    end
    seen = seen or {}
    if seen[v] then
        return "<cycle>"
    end
    seen[v] = true
    if t == "userdata" then
        local remote = _unwrap_remote_param(v, depth - 1, seen)
        if remote then return remote end
        local arr = _try_dump_tarray(v, depth, seen)
        if arr then return arr end
        local struct = _try_dump_struct_value(v, depth, seen)
        if struct then return struct end
    end
    local full = _try_get_fullname(v)
    local cls = _try_get_class(v)
    if full or cls then
        local parts = {}
        if full then parts[#parts + 1] = "name=" .. full end
        if cls then parts[#parts + 1] = "class=" .. cls end
        return "<UObject " .. table.concat(parts, " ") .. ">"
    end
    if t == "userdata" then
        return tostring(v)
    end
    if depth <= 0 then
        return "<" .. t .. ">"
    end
    local out = {}
    local n = 0
    for k, val in pairs(v) do
        n = n + 1
        if n > CONTRACT_LIST_DUMP_MAX_FIELDS then
            out[#out + 1] = "...(" .. tostring(n - 1) .. "+)"
            break
        end
        local kk = _describe_value(k, depth - 1, seen)
        local vv = _describe_value(val, depth - 1, seen)
        out[#out + 1] = kk .. "=" .. vv
    end
    return "{" .. table.concat(out, ", ") .. "}"
end

_G.BlackboxRecode = _G.BlackboxRecode or {}
_G.BlackboxRecode.DescribeValue = _describe_value

local function _dump_contract_hook(hook_name, self_obj, ...)
    local args = { ... }
    if _dump_contract_list(hook_name, self_obj, args) then
        return
    end
    local ok_self, self_desc = pcall(_describe_value, self_obj, CONTRACT_LIST_DUMP_MAX_DEPTH, {})
    if not ok_self then
        self_desc = "<err>"
    end
    local header = string.format("[Contracts] Hook=%s Args=%d Self=%s",
        tostring(hook_name or "?"), #args, self_desc)
    if Util and Util.log then
        Util.log(header)
    else
        print(header)
    end
    for i = 1, #args do
        local ok_desc, desc = pcall(_describe_value, args[i], CONTRACT_LIST_DUMP_MAX_DEPTH, {})
        if not ok_desc then
            desc = "<err>"
        end
        if Util and Util.log then
            Util.log(string.format("[Contracts] Arg %d = %s", i, desc))
        else
            print(string.format("[Contracts] Arg %d = %s", i, desc))
        end
    end
end


local function _contract_list_bump(hook_name)
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    CONTRACT_LIST_COUNT = CONTRACT_LIST_COUNT + 1
    LAST_CONTRACT_LIST_TIME = now
    _G.BlackboxRecode.ContractListCount = CONTRACT_LIST_COUNT
    _G.BlackboxRecode.LastContractListTime = LAST_CONTRACT_LIST_TIME
    if Util and Util.log then
        Util.log(string.format("[Contracts] SetContractList fired (%d) -> %s", CONTRACT_LIST_COUNT, tostring(hook_name or "?")))
    else
        print(string.format("[Contracts] SetContractList fired (%d) -> %s", CONTRACT_LIST_COUNT, tostring(hook_name or "?")))
    end
    _hook_print("Contracts", tostring(hook_name or "SetContractList"))
end

local CONTRACT_HOOKS_REGISTERED = false
local CONTRACT_HOOK_CHECK_INTERVAL = 1.0
local _last_contract_hook_check = 0.0

local function _register_contract_hooks()
    for _, hook_name in ipairs(CONTRACT_LIST_HOOKS) do
        local ok = _try_register_hook(hook_name, function(self, ...)
            local args = { ... }
            local ok_cb, err = pcall(function()
                _contract_list_bump(hook_name)
                _dump_contract_hook(hook_name, self, table.unpack(args))
            end)
            if not ok_cb then
                local msg = "[Contracts] Hook error: " .. tostring(err)
                if Util and Util.log then
                    Util.log(msg)
                else
                    print(msg)
                end
            end
        end)
        if ok then
            local msg = "[Contracts] Hook registered: " .. tostring(hook_name or "?")
            if Util and Util.log then
                Util.log(msg)
            else
                print(msg)
            end
        else
            local msg = "[Contracts] Hook register failed: " .. tostring(hook_name or "?")
            if Util and Util.log then
                Util.log(msg)
            else
                print(msg)
            end
        end
    end
end

local function _contract_hook_tick()
    if CONTRACT_HOOKS_REGISTERED then
        return
    end
    local now = (Util and Util.now_time and Util.now_time()) or os.clock()
    if (now - _last_contract_hook_check) < CONTRACT_HOOK_CHECK_INTERVAL then
        return
    end
    _last_contract_hook_check = now
    local map_name = (Util and Util.get_current_map and Util.get_current_map())
        or (_G.get_current_map and _G.get_current_map())
        or (Teleport and Teleport.get_current_map and Teleport.get_current_map())
        or "Unknown"
    if map_name ~= "Lobby" then
        return
    end
    CONTRACT_HOOKS_REGISTERED = true
    _register_contract_hooks()
end

local puzzle_generic_hooks = {
    "/Script/Engine.Actor:ReceiveBeginPlay",
    "/Script/Engine.Actor:EndPlay",
    "/Script/Engine.Actor:ReceiveDestroyed",
}

for _, fn in ipairs(puzzle_generic_hooks) do
    _try_register_hook(fn, function(self)
        local ok, short = _is_puzzle_actor(self)
        if ok then
            _puzzle_bump(fn .. ":" .. tostring(short))
        end
    end)
end

local world_generic_hooks = {
    "/Script/Engine.Actor:ReceiveBeginPlay",
    "/Script/Engine.Actor:EndPlay",
    "/Script/Engine.Actor:ReceiveDestroyed",
}

for _, fn in ipairs(world_generic_hooks) do
    _try_register_hook(fn, function(self)
        _hook_print("World", fn)
        if fn:find("EndPlay", 1, true) or fn:find("Destroyed", 1, true) then
            _registry_untrack(self)
        else
            _registry_track(self)
        end
    end)
end

_contract_hook_tick()

if _G.NotifyOnNewObject then
    pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", function(obj)
        if not _is_valid(obj) then return end
        for key, token in pairs(UI_WIDGET_CACHE) do
            if _ui_obj_has_token(obj, token) then
                _ui_cache_set(key, obj)
            end
        end
    end)

    -- NOTE: Actor new-object hook disabled to avoid registry crashes during load.
end

if _G.LoopAsync then
    LoopAsync(300, function()
        _registry_tick_throttled(false)
        _contract_hook_tick()
        return false
    end)
else
    local tick_hooks = {
        "/Script/Engine.PlayerController:PlayerTick",
        "/Script/Engine.PlayerController:Tick",
        "/Script/Engine.Actor:Tick",
    }
    for _, fn in ipairs(tick_hooks) do
        if _try_register_hook(fn, function()
            _registry_tick_throttled(false)
            _contract_hook_tick()
        end) then
            break
        end
    end
end

_registry_tick_throttled(true)
_contract_hook_tick()

local function _register_panel_toggle()
    if not _G.RegisterKeyBind then
        return
    end
    local KEY_F1 = (Key and Key.F1) or 112
    RegisterKeyBind(KEY_F1, function()
        _set_panel_open(not PANEL_OPEN, true)
        _bridge_state(_build_state_payload(), true)
    end)
end

_register_panel_toggle()
