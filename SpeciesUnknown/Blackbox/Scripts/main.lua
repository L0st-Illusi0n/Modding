-- BlackboxRecode (Lua-only)
-- v0: command system test
-- v1: teleport commands + shared action functions for future GUI

local function _script_dir()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then src = src:sub(2) end
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

-- Expose a single global table so future GUI can call actions without console commands.
_G.BlackboxRecode = _G.BlackboxRecode or {}
_G.BlackboxRecode.Util     = Util
_G.BlackboxRecode.Pointers = Pointers
_G.BlackboxRecode.Teleport = Teleport
_G.BlackboxRecode.Commands = Commands

if Util.log then
    Util.log("[BlackboxRecode] Loaded. Initializing modules...")
else
    print("[BlackboxRecode] Loaded. Initializing modules...")
end

if Teleport and Teleport.init then
    Teleport.init(Util, Pointers)
end

if Commands and Commands.init then
    Commands.init(Util, Pointers, Teleport)
else
    print("[BlackboxRecode] commands.lua missing Commands.init(Util, Pointers, Teleport)")
end

-- ================== External Bridge (Optional GUI) ==================
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

local function _bridge_read_all(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local d = f:read("*a") or ""
    f:close()
    return d
end

local function _bridge_clear(path)
    local f = io.open(path, "w")
    if f then f:write("") f:close() end
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
    -- Supports:
    --  CMD|id|NAME|ARG
    --  NAME|ARG|ID
    --  NAME|ARG
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
end

local function _emit_players_notice()
    if not Commands or not Commands.run then return end
    local ok, res = Commands.run("listplayers_gui")
    if ok and type(res) == "string" and res:find("^PLAYERS=") then
        _bridge_notice(res)
    end
end

local function _emit_tp_notice()
    if not Commands or not Commands.run then return end
    local ok, res = Commands.run("tp_gui_state")
    if ok and type(res) == "string" and res:find("^TPSTATE=") then
        _bridge_notice(res)
    end
end

local function _try_register_hook(fn_name, cb)
    if not _G.RegisterHook then return false end
    local ok, pre_id = pcall(RegisterHook, fn_name, cb)
    return ok and pre_id
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
        for _, fn_name in ipairs(candidates) do
            local ok, pre_id, post_id = pcall(RegisterHook, fn_name, function()
                _bridge_poll()
            end)
            if ok and pre_id then
                if Util and Util.log then
                    Util.log("[BlackboxRecode] GUI bridge active (RegisterHook):", fn_name)
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

-- ================== Event-based GUI updates ==================
_G.BlackboxRecode.BridgeNotice = _bridge_notice

local hooks = {
    "/Script/Engine.PlayerController:ClientRestart",
    "/Script/Engine.GameStateBase:OnRep_PlayerArray",
    "/Script/Engine.PlayerState:OnRep_PlayerName",
    "/Script/Engine.GameModeBase:PostLogin",
    "/Script/Engine.GameModeBase:Logout",
}

for _, fn in ipairs(hooks) do
    _try_register_hook(fn, function()
        _emit_players_notice()
        _emit_tp_notice()
    end)
end
