-- commands.lua
-- Console commands + action functions (actions can be used by future GUI too)

local Commands = {
    actions = {},
    meta = {}
}

local UEH = nil

-- Call an action directly (for GUI later)
-- Example: Commands.run("tp", "ship")
function Commands.run(cmd, ...)
    local fn = Commands.actions[cmd]
    if not fn then return false, "unknown action" end
    local args = { ... }
    return fn(args)
end


local U = nil
local P = nil
local TP = nil
local R = nil
local is_valid = _G.is_valid
local is_world_actor = _G.is_world_actor
local safe_get_field = _G.safe_get_field
local safe_call = _G.safe_call
local safe_call_err = _G.safe_call_err
local find_all = _G.find_all
local find_first = _G.find_first
local split_ws = _G.split_ws
local get_local_controller = _G.get_local_controller
local get_local_pawn = _G.get_local_pawn
local get_current_map = _G.get_current_map
local open_contracts_active = false
local start_contract_active = false
local esc_bound = false
local KEY_ESC = (Key and (Key.Escape or Key.ESC or Key.Esc)) or 27
local PIPE_TERMINAL_CLASS = "BP_ReactorControl_Terminal_REFACT_C"
local LAB_TERMINAL_CLASS = "BP_GAZ_Control_Terminal_REFACT_C"
local LAB_STATUT_PROP = "Statut"
local LAB_VALID_PROP = "Valid_8_9608484544DD1DEA4EC52BA6611258C1"
local LAB_LETTER_PROP = "Letter_13_494532284D3C19CA68C680B6321D6353"
local CONTRACT_PROP_ORDER = {
    "Valid_13_7EC50B9D43830CC60C6CFB89C4A56633",
    "ContractType_2_AD7B8E08435CF5A38556E7BA67C34760",
    "Difficulty_5_84E907A245C9C4C6CA73B4B492F85329",
    "Map_33_3AB0E6BD42FE920DECF2A89E52105CBF",
    "Bonus_37_1897E8074DDDA168BDAA24BC50497746",
    "RespawnTicket_8_A88C5BA64BADD031647C7BBAB7B1DCD3",
    "PowerAtStart_11_C457EA0B40DD327B66E17FBA29A033CD",
    "PirateInfasion_16_0C40614A4525CF1F61426D8C1612CD02",
    "ExplosiveItems_26_911C078943295906DC83AD9AE6E41C50",
    "WeaponsCat1_18_791AA0694D75543C3E72E9BF6CBDDED7",
    "WeaponsCat2_20_3287E6454140FA9F9FAEA2BBE0683E3A",
    "WeaponBeep_30_A709702A49C40150494FC5A3BC396644",
    "PaidAmmoAndHealingPoint_28_DD503146439664BB746EE4BCD5F9EB11",
    "PowerInstable_43_08F6519448E0B007804A8E98E1C81DBB",
    "Turret_44_40482A9D49BF678F60534D8484469ECC",
    "TimeLimit_23_33123F0347EBBAC12A84EF8683EDF14B",
    "MaxBounty_40_41D52ADA489C1A0CC271FC8E07865CA3",
    "TestModif_46_FC4300D547CDC9E3BD1A80B3F37854FB",
}

local function sanitize_notice_text(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n|]", " ")
    s = s:gsub("%s+", " ")
    return s:match("^%s*(.-)%s*$")
end

local function notify(text, level, duration_ms)
    local bridge = _G.BlackboxRecode and _G.BlackboxRecode.BridgeNotice
    if type(bridge) ~= "function" then
        return
    end
    local msg = sanitize_notice_text(text)
    if msg == "" then
        return
    end
    local lvl = tostring(level or "INFO"):upper()
    local dur = tonumber(duration_ms) or 2400
    bridge(string.format("SPLASH|%s|%d|%s", lvl, math.floor(dur), msg))
end

local function notify_ok(text, duration_ms)
    notify(text, "OK", duration_ms or 2200)
end

local function notify_warn(text, duration_ms)
    notify(text, "WARN", duration_ms or 2800)
end

local function notify_err(text, duration_ms)
    notify(text, "ERROR", duration_ms or 3200)
end

local function set_hook_prints(enable)
    _G.BlackboxRecode = _G.BlackboxRecode or {}
    _G.BlackboxRecode.HookPrints = enable and true or false
    return _G.BlackboxRecode.HookPrints
end

local function try_require_socket()
    local candidates = { "socket", "socket.core", "luasocket" }
    for _, name in ipairs(candidates) do
        local ok, mod = pcall(require, name)
        if ok and mod then
            return mod, name
        end
    end
    if type(_G.socket) == "table" then
        return _G.socket, "_G.socket"
    end
    return nil, nil
end

local function resolve_ufunction(name)
    if not _G.StaticFindObject then
        return nil
    end
    local n = tostring(name or "")
    if n == "" then return nil end
    local candidates = {}
    candidates[#candidates + 1] = n
    if n:sub(1, 9) ~= "Function " then
        candidates[#candidates + 1] = "Function " .. n
    end
    for _, lookup in ipairs(candidates) do
        local ok, obj = pcall(_G.StaticFindObject, lookup)
        if ok and obj then
            return obj
        end
    end
    return nil
end

local function is_ufunction(obj)
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

local function call_ufunction_on(obj, ufn, ...)
    if not is_valid(obj) then
        return false, "invalid_obj"
    end
    if not is_ufunction(ufn) then
        return false, "invalid_ufunction"
    end
    local last_err = nil

    local cf = safe_get_field(obj, "CallFunction")
    if type(cf) == "function" then
        local ok, res = pcall(cf, obj, ufn, ...)
        if ok then
            return true, res
        end
        last_err = res
    elseif type(cf) == "userdata" and is_ufunction(cf) then
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

    return false, last_err or "call failed"
end

local function interact_ship_seat(pawn)
    if not is_valid(pawn) then
        return false, "local player not found"
    end

    local seats = find_all("BP_Seat_C")
    if seats == nil then
        seats = {}
    elseif type(seats) ~= "table" then
        local out = {}
        local okn, n = safe_call(seats, "Num")
        if not okn or type(n) ~= "number" then
            okn, n = safe_call(seats, "GetArrayNum")
        end
        if okn and type(n) == "number" and n > 0 then
            for i = 0, n - 1 do
                local ok, v = safe_call(seats, "Get", i)
                if not ok then
                    ok, v = pcall(function() return seats[i] end)
                end
                if ok and v ~= nil then
                    out[#out + 1] = v
                end
            end
        end
        seats = out
    end

    local function seat_idx(obj)
        if not is_valid(obj) then return nil end
        local name = nil
        if obj.GetFullName then
            local ok, full = pcall(obj.GetFullName, obj)
            if ok and full then
                name = tostring(full)
            end
        end
        if not name and obj.GetName then
            local ok, n = pcall(obj.GetName, obj)
            if ok and n then
                name = tostring(n)
            end
        end
        name = tostring(name or "")
        local idx = name:match("_(%d+)%s*$") or name:match("_(%d+)$")
        return tonumber(idx)
    end

    local ordered = {}
    for _, seat in ipairs(seats) do
        local idx = seat_idx(seat)
        if idx ~= nil and idx >= 0 and idx <= 3 then
            ordered[#ordered + 1] = { idx = idx, seat = seat }
        end
    end
    table.sort(ordered, function(a, b) return a.idx < b.idx end)
    local chosen = nil
    for _, entry in ipairs(ordered) do
        local seat = entry.seat
        if is_valid(seat) then
            local used = safe_get_field(seat, "IsUsed")
            if used == false or used == 0 or used == "false" or used == "0" or used == nil then
                chosen = seat
                break
            end
        end
    end
    if not chosen then
        return false, "no free seat found"
    end
    local ok = select(1, safe_call(chosen, "BPI_Interactable_Input", pawn))
    if ok then
        return true, "ok"
    end
    return false, "interaction failed"
end

local function ensure_keybinds()
    if esc_bound then return end
    if not _G.RegisterKeyBind then return end

    RegisterKeyBind(KEY_ESC, function()
        local handled = false

        if open_contracts_active then
            open_contracts_active = false
            handled = true
            print("[OpenContracts] ESC detected...")
            if TP and TP.return_self then
                local ok, msg = TP.return_self()
                if ok then
                    print("[OpenContracts] Returned to saved position.")
                else
                    print("[OpenContracts] " .. tostring(msg))
                end
            end
        end

        if start_contract_active then
            start_contract_active = false
            handled = true
            print("[StartContract] ESC detected...")
            if TP and TP.teleport then
                local function do_ship_return()
                    local ok, msg = TP.teleport("LOBBY:ship", nil, false)
                    if ok then
                        print("[StartContract] Teleported to ship.")
                        local pawn = get_local_pawn and get_local_pawn() or nil
                        local ok_seat, msg_seat = interact_ship_seat(pawn)
                        if ok_seat then
                            print("[StartContract] Seated.")
                        else
                            print("[StartContract] Seat interact failed: " .. tostring(msg_seat))
                        end
                    else
                        print("[StartContract] " .. tostring(msg))
                    end
                end

                if _G.LoopAsync then
                    LoopAsync(1000, function()
                        do_ship_return()
                        return true
                    end)
                else
                    do_ship_return()
                end
            end
        end

        if not handled then
            return
        end
    end)

    esc_bound = true
end

local function describe_obj(obj)
    if obj == nil then return "<nil>" end
    local parts = {}
    local ok, s = pcall(function() return tostring(obj) end)
    if ok and s then parts[#parts + 1] = "tostring=" .. tostring(s) end
    local fn_full = safe_get_field(obj, "GetFullName")
    if type(fn_full) == "function" then
        local ok2, v = pcall(fn_full, obj)
        if ok2 and v then parts[#parts + 1] = "full=" .. tostring(v) end
    end
    local fn_name = safe_get_field(obj, "GetName")
    if type(fn_name) == "function" then
        local ok2, v = pcall(fn_name, obj)
        if ok2 and v then parts[#parts + 1] = "name=" .. tostring(v) end
    end
    local fn_class = safe_get_field(obj, "GetClass")
    if type(fn_class) == "function" then
        local okc, cls = pcall(fn_class, obj)
        if okc and cls then
            local ok3, s2 = pcall(function() return tostring(cls) end)
            if ok3 and s2 then parts[#parts + 1] = "class=" .. tostring(s2) end
        end
    end
    if #parts == 0 then
        return "<obj>"
    end
    return table.concat(parts, " ")
end

local function iter_children(children, fn)
    if not children or not fn then return end
    local ok, n = safe_call(children, "Num")
    if not ok or type(n) ~= "number" then
        ok, n = safe_call(children, "GetArrayNum")
    end
    if not ok or type(n) ~= "number" then
        ok, n = safe_call(children, "GetNum")
    end
    if ok and type(n) == "number" and n > 0 then
        for i = 0, n - 1 do
            local ok2, entry = safe_call(children, "Get", i)
            if not ok2 then
                ok2, entry = safe_call(children, "GetValue", i)
            end
            if not ok2 then
                ok2, entry = pcall(function() return children[i] end)
            end
            if ok2 then
                pcall(fn, entry)
            end
        end
        return
    end
    if type(children) == "table" then
        for _, entry in pairs(children) do
            pcall(fn, entry)
        end
        return
    end
    local ok_len, n2 = pcall(function() return #children end)
    if ok_len and type(n2) == "number" and n2 > 0 then
        for i = 0, n2 - 1 do
            local ok2, entry = pcall(function() return children[i] end)
            if ok2 then
                pcall(fn, entry)
            end
        end
    end
end

local function get_player_state_from_pc(pc)
    if not is_valid(pc) then return nil end
    local ps = pc.PlayerState
    if is_valid(ps) then
        return ps
    end
    if pc.GetPlayerState then
        local ok, ps2 = pcall(pc.GetPlayerState, pc)
        if ok and is_valid(ps2) then
            return ps2
        end
    end
    local children = pc.Children
    if not children and pc.GetChildren then
        local ok3, ch = pcall(pc.GetChildren, pc)
        if ok3 then
            children = ch
        end
    end
    local found = nil
    iter_children(children, function(child)
        if found then return end
        if is_valid(child) then
            local ok, full = true, nil
            if child.GetFullName then
                ok, full = pcall(child.GetFullName, child)
            end
            if ok and full and tostring(full):find("BP_MyPlayerState_C", 1, true) then
                found = child
            end
        end
    end)
    return found
end

local function sanitize_player_name(s)
    s = tostring(s or "")
    s = s:gsub("[%|;%[%]\r\n]", "")
    return s
end

local function object_key(obj)
    if not obj then return nil end
    if obj.GetFullName then
        local ok, full = pcall(obj.GetFullName, obj)
        if ok and full and full ~= "" then
            return tostring(full)
        end
    end
    return tostring(obj)
end

local function coerce_string(v)
    if v == nil then return nil end
    local t = type(v)
    if t == "string" then return v end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "userdata" or t == "table" then
        if v.ToString then
            local ok, s = pcall(v.ToString, v)
            if ok and type(s) == "string" then return s end
        end
        if v.GetString then
            local ok, s = pcall(v.GetString, v)
            if ok and type(s) == "string" then return s end
        end
        if v.String and type(v.String) == "string" then
            return v.String
        end
    end
    return tostring(v)
end

local function is_empty_name(s)
    if s == nil then return true end
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return true end
    local low = s:lower()
    if low:match("^fstring:%s*[0-9a-fx]+$") then return true end
    if low:match("^ftext:%s*[0-9a-fx]+$") then return true end
    if low:match("^fname:%s*[0-9a-fx]+$") then return true end
    if low:match("^aactor%s+[%x]+$") then return true end
    if low:match("^uobject%s+[%x]+$") then return true end
    if low:match("^aactor%s+0x[%x]+$") then return true end
    if low:match("^uobject%s+0x[%x]+$") then return true end
    return false
end

local function resolve_player_name_from_state(ps)
    if not is_valid(ps) then
        return "Player"
    end
    local name = coerce_string(ps.PlayerNamePrivate)
    if is_empty_name(name) then
        name = coerce_string(ps.PlayerName)
    end
    if is_empty_name(name) and ps.GetPlayerName then
        local ok, n2 = pcall(ps.GetPlayerName, ps)
        if ok then name = coerce_string(n2) end
    end
    if is_empty_name(name) then
        if ps.GetName then
            local ok3, n3 = pcall(ps.GetName, ps)
            if ok3 then name = coerce_string(n3) end
        end
        if is_empty_name(name) and ps.GetFullName then
            local ok4, n4 = pcall(ps.GetFullName, ps)
            if ok4 then name = coerce_string(n4) end
        end
    end
    name = sanitize_player_name(name)
    if is_empty_name(name) then
        name = "Player"
    end
    return name
end

local function resolve_player_name(pc)
    local name = nil
    local ok, result = pcall(function()
        local ps = get_player_state_from_pc(pc)
        if is_valid(ps) then
            name = resolve_player_name_from_state(ps)
        end
        if is_empty_name(name) then
            name = coerce_string(pc.PlayerName)
        end
        if is_empty_name(name) then
            name = pc.GetName and pc:GetName() or (pc.GetFullName and pc:GetFullName() or "Player")
        end
        return name
    end)
    if not ok then
        return "Player"
    end
    name = sanitize_player_name(coerce_string(result))
    if is_empty_name(name) then
        name = "Player"
    end
    return name
end

local function get_number_prop(obj, prop)
    if not is_valid(obj) then return nil end
    local ok, v = pcall(function()
        return obj[prop]
    end)
    if not ok then return nil end
    return tonumber(v)
end

local function set_prop(obj, prop, value)
    if not is_valid(obj) then return false end
    local ok = pcall(function()
        if obj[prop] == nil then
            error("missing")
        end
        obj[prop] = value
    end)
    return ok
end

local function get_struct_field(obj, prop)
    if obj == nil then return nil end
    if type(obj) == "table" then
        local v = obj[prop]
        if v ~= nil then return v end
    end
    local v = safe_get_field(obj, prop)
    if v ~= nil then return v end
    local ok, pv = safe_call(obj, "GetPropertyValue", prop)
    if ok then return pv end
    return nil
end

local function set_struct_field(obj, prop, value)
    if obj == nil then return false end
    if type(obj) == "table" then
        obj[prop] = value
        return true
    end
    if set_prop(obj, prop, value) then
        return true
    end
    local ok = pcall(function() obj[prop] = value end)
    return ok
end

local function parse_bool(v)
    v = tostring(v or ""):lower()
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "1" or v == "true" or v == "on" or v == "yes" then
        return true
    end
    if v == "0" or v == "false" or v == "off" or v == "no" then
        return false
    end
    return nil
end

local function unwrap_param(obj)
    if obj == nil then return nil end
    local t = type(obj)
    if t ~= "userdata" and t ~= "table" then
        return obj
    end
    for _, name in ipairs({ "get", "Get", "GetValue" }) do
        local fn = safe_get_field(obj, name)
        if type(fn) == "function" then
            local ok, val = pcall(fn, obj)
            if ok and val ~= nil and val ~= obj then
                return val
            end
        end
    end
    for _, name in ipairs({ "Value", "value", "Val", "val", "Data", "data" }) do
        local val = safe_get_field(obj, name)
        if val ~= nil and val ~= obj then
            return val
        end
    end
    return obj
end

local function get_prop_name(prop)
    if not prop or not prop.GetFName then return nil end
    local okn, fn = pcall(prop.GetFName, prop)
    if okn and fn and fn.ToString then
        local ok2, s = pcall(fn.ToString, fn)
        if ok2 and s then return tostring(s) end
    end
    return nil
end

local function get_prop_class_name(prop)
    if not prop then return "Property" end
    local fn_cls = safe_get_field(prop, "GetClass")
    if type(fn_cls) == "function" then
        local okc, cls = pcall(fn_cls, prop)
        if okc and cls then
            local fn_name = safe_get_field(cls, "GetFName")
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

local function build_contract_prop_types(contract_struct)
    local types = {}
    if not contract_struct or not contract_struct.ForEachProperty then
        return types
    end
    pcall(function()
        contract_struct:ForEachProperty(function(prop)
            local name = get_prop_name(prop)
            if name and name ~= "" then
                types[name] = get_prop_class_name(prop)
            end
        end)
    end)
    return types
end

local function get_contract_lists()
    local bb = _G.BlackboxRecode or {}
    local lists = {}
    if type(bb.ContractLists) == "table" then
        for _, arr in pairs(bb.ContractLists) do
            if arr ~= nil then
                lists[#lists + 1] = arr
            end
        end
    elseif bb.ContractList then
        lists[#lists + 1] = bb.ContractList
    end
    return lists
end

local function get_ui_cache()
    local bb = _G.BlackboxRecode or {}
    if type(bb.UI) == "table" then
        return bb.UI
    end
    return nil
end

local function get_ui_obj(ui, key)
    if not ui or type(ui) ~= "table" then return nil end
    local obj = ui[key]
    if is_valid(obj) then
        return obj
    end
    return nil
end

local function has_contract_ui(ui)
    if not ui or type(ui) ~= "table" then return false end
    local keys = {
        "ContractTerminal",
        "MainContractManager",
        "ChoosePage",
        "DetailPage",
        "RecapPage",
        "MapDetailsPage",
    }
    for _, key in ipairs(keys) do
        if is_valid(ui[key]) then
            return true
        end
    end
    return false
end

local function get_contract_world_context(ui)
    local keys = {
        "ContractTerminal",
        "MainContractManager",
        "ChoosePage",
        "DetailPage",
        "RecapPage",
        "MapDetailsPage",
    }
    for _, key in ipairs(keys) do
        local obj = get_ui_obj(ui, key)
        if obj then return obj end
    end
    return nil
end

local function get_contract_refresh_kv(ui)
    local bb = _G.BlackboxRecode or {}
    local key = bb.ContractRefreshKey or bb.ContractReplicatorKey
    local val = bb.ContractRefreshValue or bb.ContractReplicatorValue
    local alt = bb.ContractRefreshAltValue or bb.ContractReplicatorAltValue
    if ui and type(ui) == "table" then
        key = key or ui.RefreshKey or ui.ReplicatorKey
        val = val or ui.RefreshValue or ui.ReplicatorValue
        alt = alt or ui.RefreshAltValue or ui.ReplicatorAltValue
    end
    return key, val, alt
end

local function reorganize_contract_list(list, world_context)
    if list == nil then return nil, false, "no_list" end
    local lib = _G.BP_Mission_FunctionLibrairy_C or BP_Mission_FunctionLibrairy_C
    if not lib and _G.StaticFindObject then
        local ok, obj = pcall(_G.StaticFindObject, "BP_Mission_FunctionLibrairy_C")
        if ok then lib = obj end
    end
    if not lib then
        return nil, false, "no_lib"
    end
    local ok, res, err = safe_call_err(lib, "ReorganizeContractList", list, world_context)
    if ok and res ~= nil then
        return res, true, "ok"
    end
    if err == "missing" then
        return nil, false, "missing_fn"
    end
    if err ~= nil then
        return nil, false, "error:" .. tostring(err)
    end
    if res == nil then
        return nil, false, "returned_nil"
    end
    return nil, false, "call_failed"
end

local function push_contract_list_to_ui(final_list, ui, verbose)
    if final_list == nil then
        return false, "no_list"
    end
    ui = ui or get_ui_cache()
    if not ui then
        return false, "no_ui"
    end

    local targets = {
        { get_ui_obj(ui, "ContractTerminal"), "BPI_ContractTerminal_SetContractList", "terminal" },
        { get_ui_obj(ui, "MainContractManager"), "BPI_ContractTerminal_SetContractList", "manager" },
        { get_ui_obj(ui, "ChoosePage"), "SetContractList", "choose_set" },
        { get_ui_obj(ui, "ChoosePage"), "BPI_ContractTerminal_SetContractList", "choose_bpi" },
    }

    for _, entry in ipairs(targets) do
        local obj, fn = entry[1], entry[2]
        if not is_valid(obj) then
            if verbose then
                print(string.format("[setcontract] SetContractList target %s: invalid", tostring(entry[3])))
            end
        else
            local func = safe_get_field(obj, fn)
            if type(func) ~= "function" then
                if verbose then
                    print(string.format("[setcontract] SetContractList target %s: missing %s (%s)",
                        tostring(entry[3]), tostring(fn), describe_obj(obj)))
                end
            else
                local ok_call, err = pcall(func, obj, final_list)
                if ok_call then
                    return true, entry[3]
                end
                if verbose then
                    print(string.format("[setcontract] SetContractList target %s: error %s",
                        tostring(entry[3]), tostring(err)))
                end
            end
        end
    end
    return false, "no_target"
end

local function force_contract_ui_refresh(ui, verbose)
    ui = ui or get_ui_cache()
    if not ui then
        return false, "no_ui"
    end

    -- Option A: replicator chain
    local fail_reason = nil
    local term = get_ui_obj(ui, "ContractTerminal")
    if term then
        local ok_rep, rep, err = safe_call_err(term, "BPI_TerminalReplicator_GetDynReplicator")
        if ok_rep and rep then
            local key, val, alt = get_contract_refresh_kv(ui)
            if key ~= nil and val ~= nil then
                if alt ~= nil and alt ~= val then
                    safe_call(rep, "SetInt", key, alt)
                end
                local ok_set = safe_call(rep, "SetInt", key, val)
                if ok_set then
                    return true, "replicator"
                end
                fail_reason = "replicator_set_failed"
            else
                fail_reason = "replicator_missing_kv"
            end
        elseif ok_rep and rep == nil then
            fail_reason = "replicator_nil"
        elseif err == "missing" then
            fail_reason = "replicator_missing_fn"
        else
            fail_reason = "replicator_call_error"
        end
    else
        fail_reason = "no_terminal"
    end

    -- Option B: index change / manager rebuild
    local mgr = get_ui_obj(ui, "MainContractManager")
    if mgr then
        local idx = safe_get_field(mgr, "CurrentIndex")
        if type(idx) ~= "number" then
            idx = safe_get_field(mgr, "Index")
        end
        if type(idx) ~= "number" then
            idx = safe_get_field(mgr, "CurrentPageIndex")
        end
        if type(idx) ~= "number" then
            idx = 0
        end
        if safe_call(mgr, "OnIndexChanged", idx) then
            return true, "indexchanged"
        end
        if safe_call(mgr, "SwitchPage", idx) then
            return true, "switchpage"
        end
        if safe_call(mgr, "OnBreadcrumbPageChanged", idx) then
            return true, "breadcrumb"
        end
        if fail_reason == nil then
            fail_reason = "manager_call_failed"
        end
    end

    -- Option C: brute-force setup calls
    local function call_setup(obj, fn_name, args)
        if not is_valid(obj) then return false end
        local fn = safe_get_field(obj, fn_name)
        if type(fn) ~= "function" then return false end
        if type(args) == "table" then
            local ok = pcall(fn, obj, table.unpack(args))
            if ok then return true end
        end
        local ok2 = pcall(fn, obj)
        return ok2 and true or false
    end

    local bb = _G.BlackboxRecode or {}
    local ok_any = false
    if call_setup(get_ui_obj(ui, "DetailPage"), "SetupContractDetailPage", ui.DetailPageArgs or bb.ContractDetailPageArgs) then
        ok_any = true
    end
    if call_setup(get_ui_obj(ui, "RecapPage"), "SetupContractRecapPage", ui.RecapPageArgs or bb.ContractRecapPageArgs) then
        ok_any = true
    end
    if call_setup(get_ui_obj(ui, "MapDetailsPage"), "SetupMapDetailPage", ui.MapDetailsPageArgs or bb.ContractMapDetailsPageArgs) then
        ok_any = true
    end
    if ok_any then
        return true, "setup"
    end
    if fail_reason then
        return false, fail_reason
    end
    return false, "no_widgets"
end

local function build_contract_values(contract_struct)
    local values = {}
    if not contract_struct then
        return values
    end
    for i = 1, #CONTRACT_PROP_ORDER do
        local name = CONTRACT_PROP_ORDER[i]
        local val = get_struct_field(contract_struct, name)
        if val ~= nil then
            local t = type(val)
            if t == "boolean" then
                values[name] = val and "1" or "0"
            elseif t == "number" then
                values[name] = tostring(math.floor(val))
            else
                values[name] = tostring(val)
            end
        end
    end
    return values
end

local function encode_contract_pairs(values, order, include_empty)
    local parts = {}
    for i = 1, #order do
        local name = order[i]
        local v = values and values[name]
        if v == nil then
            if include_empty then
                parts[#parts + 1] = tostring(name) .. "="
            end
        else
            parts[#parts + 1] = tostring(name) .. "=" .. tostring(v)
        end
    end
    return table.concat(parts, ",")
end

local function get_first_contract_struct(arr)
    if not arr then return nil end
    local elem = nil
    local ok_each = safe_call(arr, "ForEach", function(_idx, e)
        elem = e
        return true
    end)
    if not ok_each or elem == nil then
        local ok, v = safe_call(arr, "Get", 0)
        if ok then
            elem = v
        end
    end
    if elem == nil then
        local ok, v = pcall(function() return arr[0] end)
        if ok then elem = v end
    end
    return unwrap_param(elem)
end

local function print_setcontract_help(types)
    print("[setcontract] Usage: setcontract <" .. tostring(#CONTRACT_PROP_ORDER) .. " values> | setcontract help")
    print("[setcontract] Example: setcontract true 3 0 0 0 9 false false true true true true false false false 0 1000 false")
    print("[setcontract] Applies to the first contract in each active list screen.")
    print("[setcontract] Order:")
    for i = 1, #CONTRACT_PROP_ORDER do
        local name = CONTRACT_PROP_ORDER[i]
        local ptype = types and types[name] or "UnknownProperty"
        print(string.format("[setcontract] %02d %s (%s)", i, name, ptype))
    end
end

local function apply_contract_values(contract_struct, values)
    if not contract_struct then return false end
    local ok_any = false
    for name, val in pairs(values or {}) do
        if set_struct_field(contract_struct, name, val) then
            ok_any = true
        end
    end
    return ok_any
end

local function apply_contract_list_first(arr, values)
    if not arr then return 0 end
    local first = get_first_contract_struct(arr)
    if not first then return 0 end
    return apply_contract_values(first, values) and 1 or 0
end

local POWER_PROP_FALLBACK = {
    "bPowerOn",
    "PowerOn",
    "bIsPowerOn",
    "Power",
    "bLightOn",
    "LightOn",
    "bIsLightOn",
    "LightsOn",
    "bLightsOn",
    "LightStatut",
    "PowerStatut",
    "Statut",
}

local function _call_change_light(gs, arg0, arg1)
    local last_err = nil
    local ufn = resolve_ufunction("Function /Game/Blueprints/Core/BP_MyGameState.BP_MyGameState_C:ChangeLightStatut")
    if ufn then
        local ok, err = call_ufunction_on(gs, ufn, arg0, arg1)
        if ok then
            return true
        end
        last_err = err
    end
    if safe_call and safe_call(gs, "ChangeLightStatut", arg0, arg1) then
        return true
    end
    if safe_call and safe_call(gs, "ChangeLightStatut", arg1) then
        return true
    end
    return false, last_err
end

local function _set_power_state(enable)
    local gs = find_first("BP_MyGameState_C")
    if not is_valid(gs) then
        print("[Power] BP_MyGameState_C not found (be in-game, not main menu).")
        return false
    end

    local bool_val = enable and true or false
    local num_val = enable and 1 or 0

    -- HookWatch shows ChangeLightStatut(0, true) in live calls, so try 2-arg then 1-arg.
    local ok, err = _call_change_light(gs, 0, bool_val)
    if not ok then
        ok, err = _call_change_light(gs, 0, num_val)
    end

    local updated = 0
    for _, prop in ipairs(POWER_PROP_FALLBACK) do
        if set_prop(gs, prop, bool_val) or set_prop(gs, prop, num_val) then
            updated = updated + 1
        end
    end

    if ok or updated > 0 then
        print("[Power] " .. (enable and "ON" or "OFF") .. " via GameState (" .. tostring(updated) .. " fields).")
        return true
    end

    if err == "invalid_obj" then
        print("[Power] BP_MyGameState_C is nullptr/invalid right now (wrong map, main menu, or loading).")
    else
        print("[Power] Failed to update GameState power fields.")
    end
    return false
end

local function set_base_walk_speed(target, speed)
    if not is_valid(target) then return false end
    if target.BaseWalkSpeed ~= nil then
        target.BaseWalkSpeed = speed
        return true
    end
    return false
end

local function get_pipe_terminal()
    local term = find_first(PIPE_TERMINAL_CLASS)
    if is_valid(term) then
        return term
    end
    return nil
end

local function get_lab_terminal()
    local term = find_first(LAB_TERMINAL_CLASS)
    if is_valid(term) then
        return term
    end
    return nil
end

local function array_to_table(arr)
    if arr == nil then return nil end
    if type(arr) == "table" then
        return arr
    end
    local ok_tbl, tbl = safe_call(arr, "ToTable")
    if ok_tbl and type(tbl) == "table" then
        return tbl
    end
    local out = {}
    local ok_each = safe_call(arr, "ForEach", function(i, elem)
        local okg, v = pcall(function() return elem:get() end)
        if okg and v ~= nil then
            out[#out + 1] = v
        end
    end)
    if ok_each and #out > 0 then
        return out
    end
    local okn, n = safe_call(arr, "Num")
    if okn and type(n) == "number" and n > 0 then
        local out = {}
        for i = 0, n - 1 do
            local ok, v = safe_call(arr, "Get", i)
            if ok then
                out[#out + 1] = v
            end
        end
        return out
    end
    local okn2, n2 = safe_call(arr, "GetArrayNum")
    if okn2 and type(n2) == "number" and n2 > 0 then
        local out = {}
        for i = 0, n2 - 1 do
            local ok, v = pcall(function() return arr[i] end)
            if ok and v ~= nil then
                out[#out + 1] = v
            end
        end
        return out
    end
    local ok_len, n3 = pcall(function() return #arr end)
    if ok_len and type(n3) == "number" and n3 > 0 then
        local out = {}
        for i = 0, n3 - 1 do
            local ok, v = pcall(function() return arr[i] end)
            if ok and v ~= nil then
                out[#out + 1] = v
            end
        end
        return out
    end
    return nil
end

local function get_array_property_table(obj, prop)
    if not obj then return nil end
    local okp, arrp = safe_call(obj, "GetPropertyValue", prop)
    if okp and arrp ~= nil then
        return array_to_table(arrp)
    end
    local ok, arr = pcall(function() return obj[prop] end)
    if ok and arr ~= nil then
        return array_to_table(arr)
    end
    return nil
end

local function get_array_property_structs(obj, prop)
    if not obj then return nil end
    local direct = safe_get_field(obj, prop)
    if direct ~= nil then
        local out = array_to_table(direct)
        if out and #out > 0 then
            return out, direct
        end
    end
    local okp, arrp = safe_call(obj, "GetPropertyValue", prop)
    if okp and arrp ~= nil then
        local out = array_to_table(arrp)
        if out and #out > 0 then
            return out, arrp
        end
    end
    return nil, nil
end

local function pipe_array_get(arr, idx)
    if not arr then return nil, false end
    local ok, v = safe_call(arr, "Get", idx)
    if ok and v ~= nil then
        return v, true
    end
    local ok2, v2 = pcall(function() return arr[idx] end)
    if ok2 and v2 ~= nil then
        return v2, true
    end
    return nil, false
end

local function pipe_array_set(arr, idx, val)
    if not arr then return false end
    local ok = safe_call(arr, "Set", idx, val)
    if ok then return true end
    local ok2 = safe_call(arr, "SetValue", idx, val)
    if ok2 then return true end
    local ok3 = pcall(function() arr[idx] = val end)
    return ok3
end

local function get_array_num(arr)
    if not arr then return nil end
    local okn, n = safe_call(arr, "Num")
    if okn and type(n) == "number" then
        return n
    end
    local okn2, n2 = safe_call(arr, "GetArrayNum")
    if okn2 and type(n2) == "number" then
        return n2
    end
    local ok2, n2 = safe_call(arr, "GetNum")
    if ok2 and type(n2) == "number" then
        return n2
    end
    return nil
end

local function pipe_array_read_values(arr, base)
    local values = {}
    local hits = 0
    for i = 1, 8 do
        local idx = (base == 0) and (i - 1) or i
        local v, ok = pipe_array_get(arr, idx)
        if ok then
            values[i] = (v == true or v == 1)
            hits = hits + 1
        else
            values[i] = nil
        end
    end
    return values, hits
end

local function parse_bool_values_from_string(s)
    if type(s) ~= "string" then return nil, 0 end
    local values = {}
    for word in s:gmatch("%a+") do
        local low = word:lower()
        if low == "true" then
            values[#values + 1] = true
        elseif low == "false" then
            values[#values + 1] = false
        end
        if #values >= 8 then break end
    end
    if #values == 0 then return nil, 0 end
    -- Normalize to 8 entries
    for i = #values + 1, 8 do
        values[i] = nil
    end
    return values, #values
end

local function read_array_values_from_any(arr)
    if arr == nil then return nil, nil, 0 end

    local ok_tbl, tbl = safe_call(arr, "ToTable")
    if ok_tbl and type(tbl) == "table" then
        arr = tbl
    else
        local ok_str, s = safe_call(arr, "ToString")
        if ok_str then
            local parsed, hits = parse_bool_values_from_string(s)
            if parsed and hits > 0 then
                return parsed, 1, hits
            end
        end
        local ok_tostr, s2 = pcall(function() return tostring(arr) end)
        if ok_tostr then
            local parsed2, hits2 = parse_bool_values_from_string(s2)
            if parsed2 and hits2 > 0 then
                return parsed2, 1, hits2
            end
        end
    end

    local values1, hits1 = pipe_array_read_values(arr, 1)
    local values0, hits0 = pipe_array_read_values(arr, 0)

    local base, values, hits
    if hits0 > hits1 then
        base, values, hits = 0, values0, hits0
    elseif hits1 > hits0 then
        base, values, hits = 1, values1, hits1
    else
        base, values, hits = 1, values1, hits1
    end

    if hits == 0 then
        return nil, base, hits
    end
    return values, base, hits
end

local function read_pipe_array(term, prop)
    if not term then return nil, nil, nil, 0 end
    local okp, arrp = safe_call(term, "GetPropertyValue", prop)
    if okp and arrp ~= nil then
        local values, base, hits = read_array_values_from_any(arrp)
        if hits and hits > 0 then
            return values, arrp, base, hits
        end
    end

    local ok, arr = pcall(function() return term[prop] end)
    if not ok or arr == nil then
        return nil, nil, nil, 0
    end

    local values, base, hits = read_array_values_from_any(arr)
    if hits == 0 then
        return nil, arr, base, hits
    end
    return values, arr, base, hits
end

local function write_pipe_array(term, prop, values, arr, base)
    if not term or not values then return false end
    -- Always write as a 1..8 boolean array for UE4SS ArrayProperty handling.
    local t = {}
    for i = 1, 8 do
        t[i] = (values[i] == true)
    end
    if term.SetPropertyValue then
        local ok = pcall(term.SetPropertyValue, term, prop, t)
        if ok then return true end
    end
    return set_prop(term, prop, t)
end

local function resolve_pipe_indices(a, b)
    local p = tonumber(a) or 0
    local v = tonumber(b) or 0
    if (p == 1 or p == 2) and v >= 1 and v <= 8 then
        return p, v
    end
    if (v == 1 or v == 2) and p >= 1 and p <= 8 then
        return v, p
    end
    return nil, nil
end

local function get_valve_indices(obj)
    if not obj then return nil, nil end
    local pidx = safe_get_field(obj, "PipeIndex")
    if pidx == nil then
        local ok, v = safe_call(obj, "GetPropertyValue", "PipeIndex")
        if ok then pidx = v end
    end
    local vidx = safe_get_field(obj, "ValveIndex")
    if vidx == nil then
        local ok, v = safe_call(obj, "GetPropertyValue", "ValveIndex")
        if ok then vidx = v end
    end
    return tonumber(pidx), tonumber(vidx)
end

local function find_valve_by_set(set_idx, pipe_num)
    local cls = (P and P.PIPES and P.PIPES.ValvePipe) or "BP_ValvePipe_C"
    local valves = find_all(cls) or {}
    for _, obj in ipairs(valves) do
        if is_valid(obj) then
            local pidx, vidx = get_valve_indices(obj)
            local s, p = resolve_pipe_indices(pidx, vidx)
            if s == set_idx and p == pipe_num then
                return obj
            end
        end
    end
    return nil
end

local function get_valve_on(obj)
    if not obj then return nil end
    local function read_prop(name)
        local v = safe_get_field(obj, name)
        if v == nil then
            local ok, pv = safe_call(obj, "GetPropertyValue", name)
            if ok then v = pv end
        end
        return v
    end
    for _, name in ipairs({ "On", "bOn", "IsOn", "bIsOn", "Active", "bActive" }) do
        local v = read_prop(name)
        if v ~= nil then
            if type(v) == "boolean" then return v end
            if type(v) == "number" then return v ~= 0 end
            if type(v) == "string" then
                local b = parse_bool(v)
                if b ~= nil then return b end
            end
        end
    end
    return nil
end

local function set_valve_on(obj, enable)
    if not is_valid(obj) then return false end
    local val = enable and true or false
    local set_ok = false
    pcall(function()
        if obj.On ~= nil then
            obj.On = val
            set_ok = true
            return
        end
        if obj.bOn ~= nil then
            obj.bOn = val
            set_ok = true
            return
        end
        if obj.IsOn ~= nil then
            obj.IsOn = val
            set_ok = true
            return
        end
        if obj.bIsOn ~= nil then
            obj.bIsOn = val
            set_ok = true
        end
    end)
    if set_ok then
        return true
    end
    if obj.SetPropertyValue then
        local ok1 = pcall(obj.SetPropertyValue, obj, "On", val)
        if ok1 then return true end
        local ok2 = pcall(obj.SetPropertyValue, obj, "bOn", val)
        if ok2 then return true end
        local ok3 = pcall(obj.SetPropertyValue, obj, "IsOn", val)
        if ok3 then return true end
        local ok4 = pcall(obj.SetPropertyValue, obj, "bIsOn", val)
        if ok4 then return true end
    end
    if set_prop(obj, "On", val) then return true end
    if set_prop(obj, "bOn", val) then return true end
    if set_prop(obj, "IsOn", val) then return true end
    if set_prop(obj, "bIsOn", val) then return true end
    return false
end

local function merge_valve_state(current, next)
    if next == nil then return current end
    if current == true then return true end
    if current == false then
        return (next == true) and true or false
    end
    return next
end

local function get_valve_states_by_set()
    local cls = (P and P.PIPES and P.PIPES.ValvePipe) or "BP_ValvePipe_C"
    local valves = find_all(cls) or {}
    local out = { [1] = {}, [2] = {} }
    local found = false
    for _, obj in ipairs(valves) do
        if is_valid(obj) then
            local pidx, vidx = get_valve_indices(obj)
            local set_idx, pipe_num = resolve_pipe_indices(pidx, vidx)
            if set_idx and pipe_num then
                local on_flag = get_valve_on(obj)
                out[set_idx][pipe_num] = merge_valve_state(out[set_idx][pipe_num], on_flag)
                found = true
            end
        end
    end
    return found, out
end

local function merge_pipe_values(base_values, fallback_values)
    if not fallback_values then return base_values end
    local out = base_values or {}
    for i = 1, 8 do
        if out[i] == nil and fallback_values[i] ~= nil then
            out[i] = fallback_values[i]
        end
    end
    return out
end

local function set_valves_for_pipe(pipe_set, pipe_idx, enable)
    local cls = (P and P.PIPES and P.PIPES.ValvePipe) or "BP_ValvePipe_C"
    local valves = find_all(cls) or {}
    local count = 0
    for _, obj in ipairs(valves) do
        if is_valid(obj) then
            local pidx, vidx = get_valve_indices(obj)
            local set_idx, pipe_num = resolve_pipe_indices(pidx, vidx)
            local match = false
            if set_idx and pipe_num then
                match = (set_idx == pipe_set and pipe_num == pipe_idx)
            else
                match = (pidx == pipe_set and vidx == pipe_idx)
            end
            if match then
                if set_valve_on(obj, enable) then
                    count = count + 1
                end
            end
        end
    end
    return count > 0, count
end

local function set_all_valves(enable)
    local cls = (P and P.PIPES and P.PIPES.ValvePipe) or "BP_ValvePipe_C"
    local valves = find_all(cls) or {}
    local count = 0
    for _, obj in ipairs(valves) do
        if is_valid(obj) then
            if set_valve_on(obj, enable) then
                count = count + 1
            end
        end
    end
    return count > 0, count
end

local function set_terminal_pipe_state(pipe_set, pipe_idx, enable)
    local term = get_pipe_terminal()
    if pipe_idx < 1 or pipe_idx > 8 then return false end
    local term_ok = false
    if term then
        local prop = (pipe_set == 1) and "Pipe1" or "Pipe2"
        local values, raw, base, hits = read_pipe_array(term, prop)
        local desired = enable and true or false
        if not values then
            values = {}
            for i = 1, 8 do values[i] = false end
        end
        values[pipe_idx] = desired
        term_ok = write_pipe_array(term, prop, values, raw, base)
    end
    local valve_ok = set_valves_for_pipe(pipe_set, pipe_idx, enable)
    return term_ok or valve_ok
end

local function set_terminal_all_pipes(enable)
    local term = get_pipe_terminal()
    local term_ok = false
    if term then
        local val = enable and true or false
        local values = {}
        for i = 1, 8 do values[i] = val end

        local function apply_all(prop)
            local _, raw, base = read_pipe_array(term, prop)
            return write_pipe_array(term, prop, values, raw, base)
        end

        local ok1 = apply_all("Pipe1")
        local ok2 = apply_all("Pipe2")
        term_ok = ok1 or ok2
    end
    local valve_ok = set_all_valves(enable)
    return term_ok or valve_ok
end

local function pack_pipe_values(values)
    local out = {}
    for i = 1, 8 do
        local v = values and values[i]
        if v == true then
            out[#out + 1] = "1"
        elseif v == false then
            out[#out + 1] = "0"
        else
            out[#out + 1] = "?"
        end
    end
    return table.concat(out)
end

local function pack_air_entries(entries)
    if not entries or #entries == 0 then return "" end
    local out = {}
    for _, entry in ipairs(entries) do
        local letter = entry.letter or "?"
        local v = entry.valid
        local val = (v == true and "1") or (v == false and "0") or "?"
        out[#out + 1] = tostring(letter) .. "=" .. val
    end
    return table.concat(out, ",")
end

local function build_puzzles_payload()
    local parts = {}

    local pipe_term = get_pipe_terminal()
    local valves_found, valve_states = get_valve_states_by_set()
    local pipe_found = (pipe_term ~= nil) or valves_found
    parts[#parts + 1] = "PIPEFOUND:" .. (pipe_found and "1" or "0")
    local r_values = nil
    local b_values = nil
    if pipe_term then
        r_values = read_pipe_array(pipe_term, "Pipe2")
        b_values = read_pipe_array(pipe_term, "Pipe1")
    end
    if valves_found then
        r_values = merge_pipe_values(r_values, valve_states[2])
        b_values = merge_pipe_values(b_values, valve_states[1])
    end
    parts[#parts + 1] = "PIPER:" .. pack_pipe_values(r_values)
    parts[#parts + 1] = "PIPEB:" .. pack_pipe_values(b_values)

    local air_term = get_lab_terminal()
    local air_found = air_term ~= nil
    parts[#parts + 1] = "AIRFOUND:" .. (air_found and "1" or "0")
    local air_entries = {}
    if air_term then
        local entries = get_array_property_structs(air_term, LAB_STATUT_PROP)
        if entries and #entries > 0 then
            for _, entry in ipairs(entries) do
                local letter = coerce_string(get_struct_field(entry, LAB_LETTER_PROP))
                if not letter or letter == "" then
                    letter = "?"
                end
                local valid = get_struct_field(entry, LAB_VALID_PROP)
                air_entries[#air_entries + 1] = { letter = letter, valid = valid }
            end
        end
    end
    parts[#parts + 1] = "AIR:" .. pack_air_entries(air_entries)

    return "PUZZLES=" .. table.concat(parts, "#")
end

local function get_actor_location(obj)
    if not is_valid(obj) or not obj.K2_GetActorLocation then return nil end
    local ok, loc = pcall(obj.K2_GetActorLocation, obj)
    if ok then return loc end
    return nil
end

local function get_actor_rotation(obj)
    if not is_valid(obj) or not obj.K2_GetActorRotation then return nil end
    local ok, rot = pcall(obj.K2_GetActorRotation, obj)
    if ok then return rot end
    return nil
end

local function get_rotation_yaw(rot)
    if rot == nil then return nil end
    for _, key in ipairs({ "Yaw", "yaw", "Z", "z" }) do
        local ok, v = pcall(function() return rot[key] end)
        if ok and type(v) == "number" then
            return v
        end
    end
    return nil
end

local function safe_offset_from_actor(loc, rot, dist, up)
    dist = tonumber(dist) or 180
    up = tonumber(up) or 80
    if not loc then return nil end
    local yaw = get_rotation_yaw(rot)
    if yaw ~= nil then
        local r = math.rad(yaw)
        local fx = math.cos(r)
        local fy = math.sin(r)
        return {
            X = (loc.X or 0) + fx * dist,
            Y = (loc.Y or 0) + fy * dist,
            Z = (loc.Z or 0) + up,
        }
    end
    return {
        X = (loc.X or 0) + dist,
        Y = (loc.Y or 0),
        Z = (loc.Z or 0) + up,
    }
end

local function get_pawn_from_pc(pc)
    if not is_valid(pc) or not pc.K2_GetPawn then return nil end
    local ok, pawn = pcall(pc.K2_GetPawn, pc)
    if ok and is_valid(pawn) then
        return pawn
    end
    return nil
end

local function get_owner_pc_from_state(ps)
    if not is_valid(ps) then return nil end
    local owner = ps.Owner
    if is_valid(owner) then
        return owner
    end
    if ps.GetOwner then
        local ok, o = pcall(ps.GetOwner, ps)
        if ok and is_valid(o) then
            return o
        end
    end
    return nil
end

local function get_pawn_from_state(ps)
    if not is_valid(ps) then return nil end
    local pawn = ps.PawnPrivate or ps.Pawn
    if is_valid(pawn) then
        return pawn
    end
    if ps.GetPawn then
        local ok, p = pcall(ps.GetPawn, ps)
        if ok and is_valid(p) then
            return p
        end
    end
    return nil
end

local function get_all_player_entries()
    local entries = {}
    local order = {}
    local function add_entry(key, name)
        if not key then return nil end
        local e = entries[key]
        if not e then
            e = { key = key, name = name or "Player" }
            entries[key] = e
            order[#order + 1] = key
        else
            if is_empty_name(e.name) and not is_empty_name(name) then
                e.name = name
            end
        end
        return e
    end

    local states = find_all("BP_MyPlayerState_C") or {}
    for _, ps in ipairs(states) do
        if is_valid(ps) then
            local key = object_key(ps)
            local name = resolve_player_name_from_state(ps)
            local e = add_entry(key, name)
            if e then
                e.ps = ps
                local pawn = get_pawn_from_state(ps)
                if pawn then
                    e.pawn = pawn
                else
                    local owner_pc = get_owner_pc_from_state(ps)
                    if owner_pc then
                        e.pc = owner_pc
                        local pawn2 = get_pawn_from_pc(owner_pc)
                        if pawn2 then
                            e.pawn = pawn2
                        end
                    end
                end
            end
        end
    end

    local cls = (P and (P.CLASSES and P.CLASSES.PlayerController)) or "BP_MyPlayerController_C"
    local controllers = find_all(cls) or {}
    for _, pc in ipairs(controllers) do
        if is_valid(pc) then
            local ps = get_player_state_from_pc(pc)
            local key = object_key(ps) or object_key(pc)
            local name = resolve_player_name(pc)
            local e = add_entry(key, name)
            if e then
                e.pc = pc
                if ps then e.ps = ps end
                local pawn = get_pawn_from_pc(pc)
                if pawn then e.pawn = pawn end
            end
        end
    end

    return entries, order
end

local function distance3(a, b)
    if not a or not b then return nil end
    local dx = (a.X or 0) - (b.X or 0)
    local dy = (a.Y or 0) - (b.Y or 0)
    local dz = (a.Z or 0) - (b.Z or 0)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function get_actor_name(obj)
    if not obj then return "Unknown" end
    if obj.GetName then
        local ok, n = pcall(obj.GetName, obj)
        if ok and n ~= nil then
            n = coerce_string(n)
            if n and n ~= "" then return n end
        end
    end
    if obj.GetFullName then
        local ok, n = pcall(obj.GetFullName, obj)
        if ok and n ~= nil then
            n = coerce_string(n)
            if n and n ~= "" then return n end
        end
    end
    return tostring(obj)
end

local function resolve_item_classes(alias)
    if not alias or alias == "" then return nil end
    alias = tostring(alias):lower()
    local out = {}
    local seen = {}

    if P and P.ITEM_ALIASES then
        local v = P.ITEM_ALIASES[alias]
        if type(v) == "string" then
            if v:sub(-1) == "_" then
                local list = {}
                if P.ITEMS then
                    if P.ITEMS.Credit1 then list[#list + 1] = P.ITEMS.Credit1 end
                    if P.ITEMS.Credit2 then list[#list + 1] = P.ITEMS.Credit2 end
                    if P.ITEMS.Credit3 then list[#list + 1] = P.ITEMS.Credit3 end
                end
                for _, cls in ipairs(list) do
                    if cls and not seen[cls] then
                        seen[cls] = true
                        out[#out + 1] = cls
                    end
                end
                return out
            end
            if not seen[v] then
                seen[v] = true
                out[#out + 1] = v
                return out
            end
        end
    end

    if P and P.ITEMS then
        for k, cls in pairs(P.ITEMS) do
            if tostring(k):lower() == alias and cls and not seen[cls] then
                seen[cls] = true
                out[#out + 1] = cls
            end
        end
        if #out > 0 then return out end
    end

    out[#out + 1] = tostring(alias)
    return out
end

local function resolve_weapon_class(alias)
    if not alias or alias == "" then return nil end
    alias = tostring(alias):upper()
    if P and P.WEAPON_CODE_TO_CLASS and P.WEAPON_CODE_TO_CLASS[alias] then
        return P.WEAPON_CODE_TO_CLASS[alias]
    end
    if P and P.WEAPONS then
        for k, v in pairs(P.WEAPONS) do
            if tostring(k):upper() == alias or tostring(v.code or ""):upper() == alias then
                return v.class
            end
        end
    end
    return tostring(alias)
end

local function resolve_monster_class(alias)
    if not alias or alias == "" then return nil end
    alias = tostring(alias):lower()
    if P and P.MONSTER_ALIASES and P.MONSTER_ALIASES[alias] then
        return P.MONSTER_ALIASES[alias]
    end
    if P and P.MONSTERS then
        for k, cls in pairs(P.MONSTERS) do
            if tostring(k):lower() == alias then
                return cls
            end
        end
    end
    return tostring(alias)
end

local function find_nearest_actor(class_list, origin_loc)
    local best = nil
    local best_dist = nil
    for _, cls in ipairs(class_list or {}) do
        local list = find_all(cls) or {}
        for _, obj in ipairs(list) do
            if is_valid(obj) then
                local loc = get_actor_location(obj)
                if loc then
                    local dist = origin_loc and distance3(origin_loc, loc) or 0
                    if not best_dist or dist < best_dist then
                        best = obj
                        best_dist = dist
                    end
                end
            end
        end
    end
    return best, best_dist
end

local get_all_monsters
local get_all_weapons

local function nearest_by_type(type_key, origin_loc)
    type_key = tostring(type_key or ""):upper()
    if not origin_loc then return nil end

    if type_key == "MONSTER" then
        local monsters = get_all_monsters()
        if #monsters == 0 then return nil end
        local best = nil
        local best_d = nil
        for _, m in ipairs(monsters) do
            local loc = get_actor_location(m)
            if loc then
                local d = distance3(origin_loc, loc)
                if d and (not best_d or d < best_d) then
                    best_d = d
                    best = m
                end
            end
        end
        return best
    end

    if type_key == "KEYCARD" then
        local classes = resolve_item_classes("keycard")
        return find_nearest_actor(classes, origin_loc)
    end
    if type_key == "DATA" then
        local classes = resolve_item_classes("datadisk")
        return find_nearest_actor(classes, origin_loc)
    end
    if type_key == "BLACKBOX" then
        local classes = resolve_item_classes("blackbox")
        return find_nearest_actor(classes, origin_loc)
    end
    if type_key == "WEAPON" then
        local classes = {}
        if P and P.WEAPONS then
            for _, w in pairs(P.WEAPONS) do
                if w and w.class then
                    classes[#classes + 1] = w.class
                end
            end
        end
        if #classes == 0 then
            local weapons = get_all_weapons()
            if #weapons == 0 then return nil end
            local best = nil
            local best_d = nil
            for _, w in ipairs(weapons) do
                local loc = get_actor_location(w)
                if loc then
                    local d = distance3(origin_loc, loc)
                    if d and (not best_d or d < best_d) then
                        best_d = d
                        best = w
                    end
                end
            end
            return best
        end
        return find_nearest_actor(classes, origin_loc)
    end

    return nil
end

get_all_monsters = function()
    local out = {}
    local classes = {}
    if P and P.MONSTERS then
        for _, cls in pairs(P.MONSTERS) do
            classes[#classes + 1] = cls
        end
    end
    if #classes == 0 then
        return out
    end
    for _, cls in ipairs(classes) do
        local list = find_all(cls) or {}
        for _, obj in ipairs(list) do
            if is_valid(obj) then
                out[#out + 1] = obj
            end
        end
    end
    return out
end

local function get_player_weapon(pawn)
    if not pawn then
        pawn = get_local_pawn and get_local_pawn() or nil
    end
    if not pawn then return nil end
    local fields = { "CurrentWeapon", "EquippedWeapon", "Weapon", "ActiveWeapon" }
    for _, f in ipairs(fields) do
        local w = safe_get_field(pawn, f)
        if is_valid(w) then return w end
    end
    return nil
end

get_all_weapons = function()
    local out = {}
    local seen = {}
    if not (P and P.WEAPONS) then return out end
    for _, w in pairs(P.WEAPONS) do
        local cls = w.class
        if cls then
            local list = find_all(cls) or {}
            for _, obj in ipairs(list) do
                if is_valid(obj) and not seen[obj] then
                    seen[obj] = true
                    out[#out + 1] = obj
                end
            end
        end
    end
    return out
end

local function humanize_key(key)
    key = tostring(key or "")
    if key == "" then return key end
    key = key:gsub("_", " ")
    key = key:gsub("([a-z])([A-Z])", "%1 %2")
    key = key:gsub("(%a)(%d)", "%1 %2")
    key = key:gsub("%s+", " ")
    return key:match("^%s*(.-)%s*$")
end

local function sanitize_state_token(s)
    s = tostring(s or "")
    s = s:gsub("[#:%|;\r\n]", " ")
    s = s:gsub("%s+", " ")
    return s:match("^%s*(.-)%s*$")
end

local function weapon_meta_from_obj(obj)
    if not obj then return nil end
    local full = ""
    if obj.GetFullName then
        local ok, v = pcall(obj.GetFullName, obj)
        if ok and v then full = tostring(v) end
    end
    local name = get_actor_name(obj)
    local class_name = ""
    if obj.GetClass then
        local okc, cls = pcall(obj.GetClass, obj)
        if okc and cls and cls.GetName then
            local okn, cn = pcall(cls.GetName, cls)
            if okn and cn then class_name = tostring(cn) end
        end
    end
    if P and P.WEAPONS then
        for key, info in pairs(P.WEAPONS) do
            if info and info.class then
                local cls = tostring(info.class)
                if (full ~= "" and full:find(cls, 1, true))
                    or (name ~= "" and name:find(cls, 1, true))
                    or (class_name ~= "" and class_name:find(cls, 1, true)) then
                    return {
                        name = humanize_key(key),
                        code = tostring(info.code or ""),
                        class = cls,
                    }
                end
            end
        end
    end
    return nil
end

local function find_player_by_name(query)
    query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return nil end
    local entries, order = get_all_player_entries()
    local target = query:lower()
    local partial = nil
    for _, key in ipairs(order) do
        local e = entries[key]
        local name = tostring(e.name or ""):lower()
        if name == target then
            return e
        end
        if not partial and name:find(target, 1, true) then
            partial = e
        end
    end
    return partial
end

local function decode_arg(value)
    value = tostring(value or "")
    value = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return value
end

local function parse_target_args(args)
    local out = {}
    for i = 1, #args do
        out[i] = args[i]
    end
    local target_entry = nil
    local target_name = "self"
    if #out >= 1 then
        local last = tostring(out[#out])
        if last:lower() == "self" then
            table.remove(out, #out)
            target_name = "self"
        else
            local entry = find_player_by_name(last)
            if entry then
                table.remove(out, #out)
                target_entry = entry
                target_name = entry.name or last
            end
        end
    end
    local pawn = nil
    if target_entry then
        pawn = target_entry.pawn
    elseif get_local_pawn then
        pawn = get_local_pawn()
    end
    return pawn, target_name, out
end

local function normalize_console_args(name, cmd, parts)
    local args = {}

    if type(parts) == "table" then
        for i = 1, #parts do
            args[i] = tostring(parts[i])
        end
    elseif type(parts) == "string" then
        args = (U and U.split_ws and U.split_ws(parts)) or split_ws(parts)
    elseif type(cmd) == "string" then
        args = (U and U.split_ws and U.split_ws(cmd)) or split_ws(cmd)
    end

    if #args > 0 then
        local command = tostring(name):lower()
        local first = tostring(args[1]):lower()

        if first == command then
            table.remove(args, 1)
        elseif first == "ce" and #args >= 2 and tostring(args[2]):lower() == command then
            table.remove(args, 1)
            table.remove(args, 1)
        end
    end

    return args
end

local function reg(cmd, fn, help, category)
    -- store action for GUI / other modules
    Commands.actions[cmd] = fn
    Commands.meta[cmd] = {
        help = help or "",
        category = category or "Other",
    }

    -- register console command
    local has_global = RegisterConsoleCommandGlobalHandler ~= nil
    if has_global then
        local callback = function(cmdline, cmd_parts, ar)
            local ok_cb, res_cb = pcall(function()
                local args = normalize_console_args(cmd, cmdline, cmd_parts)
                local ok, res = pcall(fn, args, cmdline, cmd_parts, ar)
                if not ok then
                    if U and U.err then
                        U.err("Command error:", cmd, res)
                    else
                        print("[ERROR] Command error:", cmd, res)
                    end
                    return false
                end
                if type(res) == "boolean" then
                    return res
                end
                return true
            end)
            if not ok_cb then
                if U and U.err then
                    U.err("Command handler error:", cmd, res_cb)
                else
                    print("[ERROR] Command handler error:", cmd, res_cb)
                end
                return false
            end
            if type(res_cb) == "boolean" then
                return res_cb
            end
            return true
        end

        if has_global then
            RegisterConsoleCommandGlobalHandler(cmd, callback)
        end
    else
        if U and U.warn then
            U.warn("RegisterConsoleCommand handler API missing; cannot register:", cmd)
        else
            print("[WARN] RegisterConsoleCommand handler API missing; cannot register:", cmd)
        end
    end

    if help then
        Commands.actions["_help_" .. cmd] = help
    end
end

local function print_tp_list(map_name)
    local keys, resolved_map, tp_table = TP.list(map_name)
    print(string.format("=== Teleport Locations (%s) ===", tostring(resolved_map)))
    for _, k in ipairs(keys) do
        local e = tp_table[k]
        if e and e.pos then
            print(string.format("%s -> X=%.1f Y=%.1f Z=%.1f",
                k, e.pos.x, e.pos.y, e.pos.z))
        else
            print(k)
        end
    end
    if #keys == 0 then
        print("(none)")
    end
end

function Commands.init(Util, Pointers, Teleport, Registry)
    U = Util
    P = Pointers
    TP = Teleport
    R = Registry
    if not is_valid and U and U.is_valid then is_valid = U.is_valid end
    if not is_world_actor and U and U.is_world_actor then is_world_actor = U.is_world_actor end
    if not safe_get_field and U and U.safe_get_field then safe_get_field = U.safe_get_field end
    if not safe_call and U and U.safe_call then safe_call = U.safe_call end
    if not safe_call_err and U and U.safe_call_err then safe_call_err = U.safe_call_err end
    if not find_all and U and U.find_all then find_all = U.find_all end
    if not find_first and U and U.find_first then find_first = U.find_first end
    if not split_ws and U and U.split_ws then split_ws = U.split_ws end
    if not get_local_controller and U and U.get_local_controller then get_local_controller = U.get_local_controller end
    if not get_local_pawn and U and U.get_local_pawn then get_local_pawn = U.get_local_pawn end
    if not get_current_map and U and U.get_current_map then get_current_map = U.get_current_map end
    if UEH == nil then
        local ok, mod = pcall(require, "UEHelpers")
        if ok then UEH = mod else UEH = false end
    end

    -- 1) baseline test command
    reg("checkcommands", function(args)
        print("Command System: OK")
        return true
    end, "prints Command System: OK", "General")

    -- 2) quick debug
    reg("getmap", function(args)
        if not TP then
            print("[getmap] Teleport module not loaded.")
            return true
        end
        print("[Map] Current map:", get_current_map())
        return true
    end, "prints current detected map", "Debug")

    reg("getpos", function(args)
        if not TP then
            print("[getpos] Teleport module not loaded.")
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        if not pawn or not pawn.K2_GetActorLocation then
            print("[getpos] No pawn.")
            return true
        end
        local loc = pawn:K2_GetActorLocation()
        if not loc then
            print("[getpos] No loc.")
            return true
        end
        print(string.format("[POS] X=%.2f Y=%.2f Z=%.2f", loc.X or 0, loc.Y or 0, loc.Z or 0))
        return true
    end, "prints your current location (X,Y,Z)", "Debug")

    reg("hookprints", function(args)
        local mode = args and args[1] and tostring(args[1]):lower() or ""
        if mode == "" then
            local cur = _G.BlackboxRecode and _G.BlackboxRecode.HookPrints or false
            print("[hookprints] " .. (cur and "ON" or "OFF"))
            return true
        end
        local enable = parse_bool(mode)
        if enable == nil and mode == "toggle" then
            local cur = _G.BlackboxRecode and _G.BlackboxRecode.HookPrints or false
            enable = not cur
        end
        if enable == nil then
            print("[hookprints] Usage: hookprints <on|off|toggle>")
            return true
        end
        local state = set_hook_prints(enable)
        notify_ok("Hook prints: " .. (state and "ON" or "OFF"))
        print("[hookprints] " .. (state and "ON" or "OFF"))
        return true
    end, "hookprints <on|off|toggle> -> log when hooks fire", "Debug")

    reg("dumpfn", function(args)
        local name = args and args[1]
        if not name or name == "" then
            print("usage: dumpfn <FunctionNameOrPath>")
            return true
        end
        if not _G.StaticFindObject then
            print("StaticFindObject missing")
            return true
        end
        local lookup = name
        if lookup:sub(1,9) ~= "Function " then lookup = "Function " .. lookup end
        local ok, fn = pcall(_G.StaticFindObject, lookup)
        if not ok or not fn then
            print("Function not found:", lookup)
            return true
        end
        _G.dump_ufunction_safe(fn)
        return true
    end, "safe ufunction dump (no param traversal)", "Dev")

    -- 3) teleport core
    reg("tp", function(args)
        if not TP then
            print("[tp] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[tp] Usage: tp <key>  OR  tp LOBBY:key  OR  tp MAIN:key")
            print("[tp] Tip: run tplist to see keys.")
            return true
        end
        local spec = tostring(args[1])
        local ok, msg = TP.teleport(spec)
        if ok then
            notify_ok("Teleported to: " .. tostring(spec))
        else
            notify_err("Teleport Failed: " .. tostring(msg))
        end
        print(ok and ("[tp] OK -> " .. tostring(spec)) or ("[tp] FAIL -> " .. tostring(msg)))
        return true
    end, "tp <key> | tp LOBBY:key | tp MAIN:key", "Teleport")

    reg("tplist", function(args)
        if not TP then
            print("[tplist] Teleport module not loaded.")
            return true
        end
        local mode = args and args[1] and tostring(args[1]):lower() or ""
        if mode == "all" then
            print_tp_list("Lobby")
            print_tp_list("Main")
            return true
        end
        print_tp_list(nil) -- current map
        return true
    end, "tplist [all] -> lists teleports for current map (or both maps with 'all')", "Teleport")

    reg("listplayers", function(args)
        local entries, order = get_all_player_entries()
        if #order == 0 then
            print("[ListPlayers] No player states or controllers found.")
            return true
        end

        print("=== Players ===")
        local list = {}
        for _, key in ipairs(order) do
            list[#list + 1] = entries[key]
        end
        table.sort(list, function(a, b)
            return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
        end)

        for i, e in ipairs(list) do
            local name = tostring(e.name or "Player")
            local loc = e.pawn and get_actor_location(e.pawn) or nil
            local pos_str = "POS: N/A"
            if loc then
                pos_str = string.format("POS: X=%.1f Y=%.1f Z=%.1f", loc.X or 0, loc.Y or 0, loc.Z or 0)
            end
            local hp = e.pawn and get_number_prop(e.pawn, "Health") or nil
            local maxhp = e.pawn and get_number_prop(e.pawn, "MaxHealth") or nil
            local hp_str = "HP: N/A"
            if hp and maxhp then
                hp_str = string.format("HP: %.0f/%.0f", hp, maxhp)
            elseif hp then
                hp_str = string.format("HP: %.0f", hp)
            end
            print(string.format("%d) %s | %s | %s", i, name, pos_str, hp_str))
        end
        print("[ListPlayers] Total:", #list)
        return true
    end, "lists all players with position and HP", "Players")

    reg("ueplayers", function(args)
        if not UEH then
            print("[ueplayers] UEHelpers not loaded.")
            return true
        end
        if not UEH.GetAllPlayerStates or not UEH.GetAllPlayers then
            print("[ueplayers] UEHelpers missing GetAllPlayerStates/GetAllPlayers.")
            return true
        end

        local function print_list(label, list)
            if type(list) ~= "table" then
                print(string.format("[%s] None", label))
                return
            end
            print(string.format("=== %s (%d) ===", label, #list))
            for i, obj in ipairs(list) do
                local name = get_actor_name(obj)
                local full = ""
                if obj and obj.GetFullName then
                    local ok, v = pcall(obj.GetFullName, obj)
                    if ok and v then full = tostring(v) end
                end
                if full ~= "" and full ~= name then
                    print(string.format("%d) %s | %s", i, name, full))
                else
                    print(string.format("%d) %s", i, name))
                end
            end
        end

        local ok_ps, player_states = pcall(UEH.GetAllPlayerStates)
        if not ok_ps then
            print("[ueplayers] GetAllPlayerStates failed.")
        else
            print_list("PlayerStates", player_states)
        end

        local ok_players, players = pcall(UEH.GetAllPlayers)
        if not ok_players then
            print("[ueplayers] GetAllPlayers failed.")
        else
            print_list("Players", players)
        end
        return true
    end, "prints UEHelpers.GetAllPlayerStates and GetAllPlayers", "Players")

    reg("listplayers_gui", function(args)
        local entries, order = get_all_player_entries()
        local self_pawn = get_local_pawn and get_local_pawn() or nil
        local self_pc = get_local_controller and get_local_controller() or nil
        local self_ps = self_pc and get_player_state_from_pc(self_pc) or nil
        local self_keys = {}
        local function add_self_key(obj)
            local k = object_key(obj)
            if k then self_keys[k] = true end
        end
        add_self_key(self_ps)
        add_self_key(self_pc)
        add_self_key(self_pawn)
        local self_name_guess = nil
        if is_valid(self_ps) then
            local n = resolve_player_name_from_state(self_ps)
            if n and not is_empty_name(n) then
                self_name_guess = sanitize_player_name(n)
            end
        end
        if (not self_name_guess or self_name_guess == "") and is_valid(self_pc) then
            local n2 = resolve_player_name(self_pc)
            if n2 and not is_empty_name(n2) then
                self_name_guess = sanitize_player_name(n2)
            end
        end
        if (not self_name_guess or self_name_guess == "") and is_valid(self_pawn) then
            local n3 = get_actor_name(self_pawn)
            if n3 and not is_empty_name(n3) then
                self_name_guess = sanitize_player_name(n3)
            end
        end
        if self_name_guess then
            local b = tostring(self_name_guess)
            if b:find("/Game/", 1, true) or b:find("PersistentLevel", 1, true) then
                self_name_guess = nil
            else
                self_name_guess = b:gsub(":", " "):gsub(";", " ")
            end
        end

        if #order == 0 then
            return true, "PLAYERS="
        end

        local list = {}
        local self_name = nil
        for _, key in ipairs(order) do
            local e = entries[key]
            local name = sanitize_player_name(e.name or "Player")
            name = name:gsub(":", " "):gsub(";", " ")
            local is_self = false
            if self_pawn and e.pawn and e.pawn == self_pawn then
                is_self = true
            elseif self_pc and e.pc and e.pc == self_pc then
                is_self = true
            elseif self_ps and e.ps and e.ps == self_ps then
                is_self = true
            elseif e.key and self_keys[e.key] then
                is_self = true
            elseif e.ps and self_keys[object_key(e.ps)] then
                is_self = true
            elseif e.pc and self_keys[object_key(e.pc)] then
                is_self = true
            elseif e.pawn and self_keys[object_key(e.pawn)] then
                is_self = true
            elseif self_name_guess and tostring(name):lower() == tostring(self_name_guess):lower() then
                is_self = true
            end
            if is_self then
                local best = nil
                if e.ps and is_valid(e.ps) then
                    best = resolve_player_name_from_state(e.ps)
                end
                if (not best or is_empty_name(best)) and e.pc and is_valid(e.pc) then
                    best = resolve_player_name(e.pc)
                end
                if (not best or is_empty_name(best)) and e.pawn and is_valid(e.pawn) then
                    best = get_actor_name(e.pawn)
                end
                if best and not is_empty_name(best) then
                    local b = tostring(best)
                    if not b:find("/Game/", 1, true) and not b:find("PersistentLevel", 1, true) then
                        name = sanitize_player_name(b)
                        name = name:gsub(":", " "):gsub(";", " ")
                    end
                end
                self_name = name
            else
                list[#list + 1] = { name = name }
            end
        end

        if not self_name or self_name == "" then
            -- Try full chain: local PC -> player state -> resolved name.
            local pc = self_pc or (get_local_controller and get_local_controller()) or nil
            if pc and is_valid(pc) then
                local ps = get_player_state_from_pc(pc)
                if is_valid(ps) then
                    local n = resolve_player_name_from_state(ps)
                    if n and n ~= "" then
                        self_name = sanitize_player_name(n)
                    end
                end
                if (not self_name or self_name == "") then
                    self_name = sanitize_player_name(resolve_player_name(pc))
                end
            end
            if (not self_name or self_name == "") and self_pawn and is_valid(self_pawn) then
                self_name = sanitize_player_name(get_actor_name(self_pawn))
            end
            if self_name then
                local b = tostring(self_name)
                if b:find("/Game/", 1, true) or b:find("PersistentLevel", 1, true) then
                    self_name = nil
                else
                    self_name = b:gsub(":", " "):gsub(";", " ")
                end
            end
        end

        table.sort(list, function(a, b)
            return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
        end)

        local out = {}
        if self_name and self_name ~= "" then
            out[#out + 1] = "SELF:" .. tostring(self_name)
        end
        for _, e in ipairs(list) do
            out[#out + 1] = "P:" .. tostring(e.name or "Player")
        end
        if (not self_name or self_name == "") and #list == 1 then
            -- Single-player fallback: assume the only entry is self.
            self_name = tostring(list[1].name or "Player")
            out = { "SELF:" .. self_name }
        end
        local payload = "PLAYERS=" .. table.concat(out, ";")
        print("Player List Updated:", table.concat(out, ", "))
        return true, payload
    end, "GUI: returns player list string", "Players")

    reg("weapon_gui_state", function(args)
        local pawn, who = parse_target_args(args or {})
        local target_name = sanitize_state_token(who or "self")
        if not pawn then
            return true, "WEAPONSTATE=TARGET:" .. target_name .. "#OK:0"
        end
        local weapon = get_player_weapon(pawn)
        if not weapon then
            return true, "WEAPONSTATE=TARGET:" .. target_name .. "#OK:0"
        end
        local meta = weapon_meta_from_obj(weapon) or {}
        local name = meta.name or get_actor_name(weapon)
        local code = meta.code or ""
        local cls = meta.class or ""
        local payload = string.format(
            "WEAPONSTATE=TARGET:%s#OK:1#NAME:%s#CODE:%s#CLASS:%s",
            target_name,
            sanitize_state_token(name),
            sanitize_state_token(code),
            sanitize_state_token(cls)
        )
        return true, payload
    end, "GUI: returns current weapon for target player", "Weapons")

    reg("world_registry_scan", function(args)
        if R and R.full_rescan then
            R.full_rescan()
            if R.request_emit then
                R.request_emit(true)
            end
        end
        notify_ok("World registry scan requested.")
        return true, "OK"
    end, "GUI: rescan world registry (pushes bridge update)", "World")

    reg("world_gui_state", function(args)
        if not R then
            return true, "WORLD="
        end
        local mode = args and args[1] and tostring(args[1]):lower() or ""
        if mode == "scan" or mode == "refresh" or mode == "rescan" then
            if R.full_rescan then R.full_rescan() end
        end
        if R.build_payload then
            return true, R.build_payload()
        end
        return true, "WORLD="
    end, "GUI: returns world registry list (use 'scan' to rescan)", "World")

    reg("state_snapshot", function(args)
        notify_ok("State snapshot requested.")
        return true, "OK"
    end, "GUI: forces state snapshot emit", "Debug")

    reg("registry_clear", function(args)
        if R and R.clear then
            R.clear()
            if R.request_emit then
                R.request_emit(true)
            end
        end
        notify_ok("Registry cleared.")
        return true, "OK"
    end, "GUI: clears world registry", "Debug")

    reg("registry_rebuild", function(args)
        if R and R.rebuild then
            R.rebuild()
            if R.request_emit then
                R.request_emit(true)
            end
        end
        notify_ok("Registry rebuild started.")
        return true, "OK"
    end, "GUI: clears and rescans world registry", "Debug")

    reg("world_tp", function(args)
        if not R or not R.get_entry_by_id then
            notify_err("Teleport Failed: registry not loaded.")
            print("[world_tp] Registry not loaded.")
            return true
        end
        if not TP or not TP.teleport_to_location then
            notify_err("Teleport Failed: module not loaded.")
            print("[world_tp] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[world_tp] Usage: world_tp <id>")
            return true
        end
        local id = tostring(args[1] or "")
        local entry = R.get_entry_by_id(id)
        if not entry or not entry.obj or not is_valid(entry.obj) then
            notify_warn("Teleport Failed: object not found.")
            print("[world_tp] Object not found.")
            return true
        end
        local loc = get_actor_location(entry.obj)
        if not loc then
            if entry.x and entry.y and entry.z then
                loc = { X = entry.x, Y = entry.y, Z = entry.z }
            end
        end
        if not loc then
            notify_err("Teleport Failed: no object location.")
            print("[world_tp] No object location.")
            return true
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X or 0, y = loc.Y or 0, z = loc.Z or 0 })
        if ok then
            local name = entry.name or entry.class or "Object"
            notify_ok("Teleported to: " .. tostring(name))
        else
            notify_err("Teleport Failed: " .. tostring(msg))
        end
        print(ok and "[world_tp] OK" or ("[world_tp] FAIL -> " .. tostring(msg)))
        return true
    end, "world_tp <id> -> teleport to registry object", "World")

    reg("world_bring", function(args)
        if not R or not R.get_entry_by_id then
            notify_err("Bring failed: registry not loaded.")
            print("[world_bring] Registry not loaded.")
            return true
        end
        if not TP or not TP.teleport_to_location then
            notify_err("Bring failed: module not loaded.")
            print("[world_bring] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[world_bring] Usage: world_bring <id>")
            return true
        end
        local id = tostring(args[1] or "")
        local entry = R.get_entry_by_id(id)
        if not entry or not entry.obj or not is_valid(entry.obj) then
            notify_warn("Bring failed: object not found.")
            print("[world_bring] Object not found.")
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        if not pawn then
            notify_err("Bring failed: no local pawn.")
            print("[world_bring] No local pawn.")
            return true
        end
        local loc = get_actor_location(pawn)
        if not loc then
            notify_err("Bring failed: no local location.")
            print("[world_bring] No local location.")
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X or 0, y = loc.Y or 0, z = loc.Z or 0 }, entry.obj, false)
        if ok then
            local name = entry.name or entry.class or "Object"
            notify_ok("Brought to you: " .. tostring(name))
        else
            notify_err("Bring failed: " .. tostring(msg))
        end
        print(ok and "[world_bring] OK" or ("[world_bring] FAIL -> " .. tostring(msg)))
        return true
    end, "world_bring <id> -> bring registry object to you", "World")

    reg("gotoplayer", function(args)
        if not TP or not TP.teleport_to_location then
            notify_err("Teleport Failed: module not loaded.")
            print("[gotoplayer] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[gotoplayer] Usage: gotoplayer <name>")
            return true
        end
        local query = table.concat(args, " ")
        local entry = find_player_by_name(query)
        if not entry then
            notify_warn("Teleport Failed: player not found.")
            print("[gotoplayer] Player not found:", query)
            return true
        end
        if not entry.pawn then
            notify_err("Teleport Failed: no pawn for player.")
            print("[gotoplayer] No pawn for player:", entry.name)
            return true
        end
        local loc = get_actor_location(entry.pawn)
        if not loc then
            notify_err("Teleport Failed: no player location.")
            print("[gotoplayer] No location for player:", entry.name)
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z })
        if ok then
            notify_ok("Teleported to player: " .. tostring(entry.name))
        else
            notify_err("Teleport Failed: " .. tostring(msg))
        end
        print(ok and ("[gotoplayer] OK -> " .. tostring(entry.name)) or ("[gotoplayer] FAIL -> " .. tostring(msg)))
        return true
    end, "gotoplayer <name> -> teleports you to that player", "Players")

    reg("bringplayer", function(args)
        if not TP or not TP.teleport_to_location then
            notify_err("Bring failed: module not loaded.")
            print("[bringplayer] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[bringplayer] Usage: bringplayer <name>")
            return true
        end
        local query = table.concat(args, " ")
        local entry = find_player_by_name(query)
        if not entry then
            notify_warn("Bring failed: player not found.")
            print("[bringplayer] Player not found:", query)
            return true
        end
        if not entry.pawn then
            notify_err("Bring failed: no pawn for player.")
            print("[bringplayer] No pawn for player:", entry.name)
            return true
        end
        local self_pawn = get_local_pawn and get_local_pawn() or nil
        if not self_pawn then
            notify_err("Bring failed: no local pawn.")
            print("[bringplayer] No local pawn.")
            return true
        end
        local loc = get_actor_location(self_pawn)
        if not loc then
            notify_err("Bring failed: no local location.")
            print("[bringplayer] No local location.")
            return true
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z }, entry.pawn, false)
        if ok then
            notify_ok("Brought player: " .. tostring(entry.name))
        else
            notify_err("Bring failed: " .. tostring(msg))
        end
        print(ok and ("[bringplayer] OK -> " .. tostring(entry.name)) or ("[bringplayer] FAIL -> " .. tostring(msg)))
        return true
    end, "bringplayer <name> -> teleports that player to you", "Players")

    reg("tpplayerto", function(args)
        if not TP or not TP.teleport or not TP.teleport_to_location then
            notify_err("Teleport Failed: module not loaded.")
            print("[tpplayerto] Teleport module not loaded.")
            return true
        end
        if not args or #args < 2 then
            print("[tpplayerto] Usage: tpplayerto <player> <TP:key | P:name>")
            return true
        end
        local target_query = decode_arg(args[1])
        local dest_spec = decode_arg(table.concat(args, " ", 2))
        local entry = find_player_by_name(target_query)
        if not entry then
            notify_warn("Teleport Failed: player not found.")
            print("[tpplayerto] Player not found:", target_query)
            return true
        end
        if not entry.pawn then
            notify_err("Teleport Failed: no pawn for player.")
            print("[tpplayerto] No pawn for player:", entry.name)
            return true
        end
        local kind, value = dest_spec:match("^%s*(%a+)%s*:%s*(.+)$")
        if not kind or not value then
            notify_warn("Teleport Failed: bad destination.")
            print("[tpplayerto] Bad destination:", dest_spec)
            return true
        end
        kind = tostring(kind):upper()
        value = tostring(value)

        if TP.save_local_return then
            TP.save_local_return()
        end

        if kind == "TP" then
            local ok, msg = TP.teleport(value, entry.pawn, false)
            if ok then
                notify_ok("Teleported " .. tostring(entry.name) .. " to: " .. tostring(value))
            else
                notify_err("Teleport Failed: " .. tostring(msg))
            end
            print(ok and ("[tpplayerto] OK -> " .. tostring(entry.name)) or ("[tpplayerto] FAIL -> " .. tostring(msg)))
            return true
        end

        if kind == "P" or kind == "PLAYER" then
            local dest_entry = find_player_by_name(value)
            if not dest_entry then
                notify_warn("Teleport Failed: destination player not found.")
                print("[tpplayerto] Destination player not found:", value)
                return true
            end
            if not dest_entry.pawn then
                notify_err("Teleport Failed: no pawn for destination.")
                print("[tpplayerto] No pawn for destination:", dest_entry.name)
                return true
            end
            local loc = get_actor_location(dest_entry.pawn)
            if not loc then
                notify_err("Teleport Failed: no destination location.")
                print("[tpplayerto] No location for destination:", dest_entry.name)
                return true
            end
            local rot = get_actor_rotation(dest_entry.pawn)
            local pos = {
                x = loc.X, y = loc.Y, z = loc.Z,
                rot = rot and { pitch = rot.Pitch or 0, yaw = rot.Yaw or 0, roll = rot.Roll or 0 } or nil,
            }
            local ok, msg = TP.teleport_to_location(pos, entry.pawn, false)
            if ok then
                notify_ok("Teleported " .. tostring(entry.name) .. " to player: " .. tostring(dest_entry.name))
            else
                notify_err("Teleport Failed: " .. tostring(msg))
            end
            print(ok and ("[tpplayerto] OK -> " .. tostring(entry.name)) or ("[tpplayerto] FAIL -> " .. tostring(msg)))
            return true
        end

        notify_warn("Teleport Failed: unsupported destination.")
        print("[tpplayerto] Unsupported destination:", dest_spec)
        return true
    end, "tpplayerto <player> <TP:key | P:name> -> teleports player to destination", "Teleport")

    reg("returnself", function(args)
        if not TP or not TP.return_self then
            print("[returnself] Teleport module not loaded.")
            return true
        end
        local ok, msg = TP.return_self()
        if ok then
            print("[ReturnSelf] Returned to saved position.")
        else
            print("[ReturnSelf] " .. tostring(msg))
        end
        return true
    end, "returns you to your last saved position", "Teleport")

    reg("returnall", function(args)
        if not TP or not TP.return_all then
            print("[returnall] Teleport module not loaded.")
            return true
        end
        local ok, count = TP.return_all()
        if ok then
            print("[ReturnAll] Returned " .. tostring(count or 0) .. " players.")
        else
            print("[ReturnAll] Failed.")
        end
        return true
    end, "returns all players with saved positions", "Teleport")

    reg("tpsetreturn", function(args)
        if not TP or not TP.set_return_point then
            print("[tpsetreturn] Teleport module not loaded.")
            return true
        end
        local ok, msg = TP.set_return_point()
        if ok then
            notify_ok("Return point saved.")
        else
            notify_err("Return point failed: " .. tostring(msg))
        end
        print(ok and "[tpsetreturn] Saved." or ("[tpsetreturn] " .. tostring(msg)))
        return true
    end, "tpsetreturn -> save return point", "Teleport")

    reg("tpreturn", function(args)
        if not TP or not TP.return_self then
            print("[tpreturn] Teleport module not loaded.")
            return true
        end
        local ok, msg = TP.return_self()
        if ok then
            notify_ok("Returned to saved point.")
        else
            notify_err("Return failed: " .. tostring(msg))
        end
        print(ok and "[tpreturn] Returned." or ("[tpreturn] " .. tostring(msg)))
        return true
    end, "tpreturn -> return to saved point", "Teleport")

    reg("tpmap", function(args)
        if not TP then
            print("[tpmap] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[tpmap] Usage: tpmap <key>")
            return true
        end
        local key = tostring(args[1])
        local map = get_current_map and get_current_map() or "Unknown"
        if map == "Unknown" then
            notify_warn("Teleport Failed: map unknown.")
            print("[tpmap] Map unknown.")
            return true
        end
        local ok, msg = TP.teleport(key)
        if ok then
            notify_ok("Teleported to: " .. tostring(key))
        else
            notify_err("Teleport Failed: " .. tostring(msg))
        end
        print(ok and ("[tpmap] OK -> " .. key) or ("[tpmap] FAIL -> " .. tostring(msg)))
        return true
    end, "tpmap <key> -> teleport to map location", "Teleport")

    reg("tpallmap", function(args)
        if not TP or not TP.teleport then
            print("[tpallmap] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[tpallmap] Usage: tpallmap <key>")
            return true
        end
        local key = tostring(args[1])
        local map = get_current_map and get_current_map() or "Unknown"
        if map == "Unknown" then
            notify_warn("Teleport Failed: map unknown.")
            print("[tpallmap] Map unknown.")
            return true
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        local pawns = TP.get_all_player_pawns and TP.get_all_player_pawns() or nil
        if not pawns or #pawns == 0 then
            notify_warn("Teleport Failed: no players found.")
            print("[tpallmap] No players found.")
            return true
        end
        local count = 0
        for _, pawn in ipairs(pawns) do
            if pawn and pawn.IsValid and pawn:IsValid() then
                local ok = TP.teleport(key, pawn, false)
                if ok then count = count + 1 end
            end
        end
        notify_ok("Teleported all players to: " .. tostring(key) .. " (" .. tostring(count) .. ")")
        print("[tpallmap] Teleported:", count)
        return true
    end, "tpallmap <key> -> teleport all players to map location", "Teleport")

    reg("bringallplayers", function(args)
        if not TP or not get_local_pawn or not TP.teleport_to_location then
            notify_err("Bring failed: teleport module not loaded.")
            print("[bringallplayers] Teleport module not loaded.")
            return true
        end
        local pawn = get_local_pawn()
        if not pawn then
            notify_err("Bring failed: no local pawn.")
            print("[bringallplayers] No local pawn.")
            return true
        end
        local loc = get_actor_location(pawn)
        if not loc then
            notify_err("Bring failed: no local location.")
            print("[bringallplayers] No local location.")
            return true
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        local pawns = TP.get_all_player_pawns and TP.get_all_player_pawns() or nil
        if not pawns or #pawns == 0 then
            notify_warn("Bring failed: no players found.")
            print("[bringallplayers] No players found.")
            return true
        end
        local count = 0
        for _, p in ipairs(pawns) do
            if p and p.IsValid and p:IsValid() and p ~= pawn then
                local ok = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z }, p, false)
                if ok then count = count + 1 end
            end
        end
        notify_ok("Brought players: " .. tostring(count))
        print("[bringallplayers] Brought:", count)
        return true
    end, "bringallplayers -> bring all players to you", "Teleport")

    reg("tpnearest", function(args)
        if not TP then
            notify_err("Teleport Failed: module not loaded.")
            print("[tpnearest] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[tpnearest] Usage: tpnearest <type>")
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        if not pawn then
            notify_err("Teleport Failed: no local pawn.")
            print("[tpnearest] No local pawn.")
            return true
        end
        local origin = get_actor_location(pawn)
        if not origin then
            notify_err("Teleport Failed: no local location.")
            print("[tpnearest] No local location.")
            return true
        end
        local obj = nearest_by_type(args[1], origin)
        if not obj then
            notify_warn("Teleport Failed: none found.")
            print("[tpnearest] None found.")
            return true
        end
        local loc = get_actor_location(obj)
        if not loc then
            notify_err("Teleport Failed: no object location.")
            print("[tpnearest] No object location.")
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z })
        if ok then
            notify_ok("Teleported to nearest: " .. tostring(args[1]))
        else
            notify_err("Teleport Failed: " .. tostring(msg))
        end
        print(ok and "[tpnearest] OK" or ("[tpnearest] FAIL -> " .. tostring(msg)))
        return true
    end, "tpnearest <type> -> teleport to nearest object", "Teleport")

    reg("bringnearest", function(args)
        if not TP then
            notify_err("Bring failed: module not loaded.")
            print("[bringnearest] Teleport module not loaded.")
            return true
        end
        if not args or #args < 1 then
            print("[bringnearest] Usage: bringnearest <type>")
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        if not pawn then
            notify_err("Bring failed: no local pawn.")
            print("[bringnearest] No local pawn.")
            return true
        end
        local origin = get_actor_location(pawn)
        if not origin then
            notify_err("Bring failed: no local location.")
            print("[bringnearest] No local location.")
            return true
        end
        local obj = nearest_by_type(args[1], origin)
        if not obj then
            notify_warn("Bring failed: none found.")
            print("[bringnearest] None found.")
            return true
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        local ok, msg = TP.teleport_to_location({ x = origin.X, y = origin.Y, z = origin.Z }, obj, false)
        if ok then
            notify_ok("Brought nearest: " .. tostring(args[1]))
        else
            notify_err("Bring failed: " .. tostring(msg))
        end
        print(ok and "[bringnearest] OK" or ("[bringnearest] FAIL -> " .. tostring(msg)))
        return true
    end, "bringnearest <type> -> bring nearest object to you", "Teleport")

    reg("tp_gui_state", function(args)
        if not TP then
            return true, "TPSTATE=MAP:Unknown#PAWN:0#RETURN:0#TPS:#NEAR:#OTHERS:0"
        end
        local map = get_current_map and get_current_map() or "Unknown"
        local pawn = get_local_pawn and get_local_pawn() or nil
        local pawn_ok = pawn ~= nil
        local return_ok = false
        if pawn_ok and TP.get_return_position then
            local pos = TP.get_return_position(pawn)
            return_ok = pos ~= nil
        end

        local tp_items = {}
        if map ~= "Unknown" and TP.list then
            local keys, _map, tbl = TP.list(map)
            for _, k in ipairs(keys or {}) do
                local entry = tbl[k]
                local nm = (entry and entry.name) or k
                nm = sanitize_player_name(nm)
                nm = nm:gsub("=", " "):gsub(",", " "):gsub("#", " ")
                tp_items[#tp_items + 1] = tostring(k) .. "=" .. tostring(nm)
            end
        end

        local near = {}
        if pawn_ok then
            local origin = get_actor_location(pawn)
            if origin then
                near.MONSTER = nearest_by_type("MONSTER", origin) ~= nil
                near.KEYCARD = nearest_by_type("KEYCARD", origin) ~= nil
                near.DATA = nearest_by_type("DATA", origin) ~= nil
                near.BLACKBOX = nearest_by_type("BLACKBOX", origin) ~= nil
                near.WEAPON = nearest_by_type("WEAPON", origin) ~= nil
            end
        end
        local near_parts = {
            "MONSTER=" .. ((near.MONSTER and "1") or "0"),
            "KEYCARD=" .. ((near.KEYCARD and "1") or "0"),
            "DATA=" .. ((near.DATA and "1") or "0"),
            "BLACKBOX=" .. ((near.BLACKBOX and "1") or "0"),
            "WEAPON=" .. ((near.WEAPON and "1") or "0"),
        }

        -- count other players
        local entries, order = get_all_player_entries()
        local others = 0
        if order and #order > 0 then
            local self_pawn = get_local_pawn and get_local_pawn() or nil
            for _, key in ipairs(order) do
                local e = entries[key]
                local is_self = (self_pawn and e.pawn and e.pawn == self_pawn)
                if not is_self then
                    others = others + 1
                end
            end
        end

        local payload = table.concat({
            "MAP:" .. tostring(map),
            "PAWN:" .. (pawn_ok and "1" or "0"),
            "RETURN:" .. (return_ok and "1" or "0"),
            "TPS:" .. table.concat(tp_items, ","),
            "NEAR:" .. table.concat(near_parts, ","),
            "OTHERS:" .. tostring(others),
        }, "#")

        return true, "TPSTATE=" .. payload
    end, "GUI: teleport tab state", "Teleport")

    reg("listreturns", function(args)
        if not TP or not TP.list_returns then
            print("[listreturns] Teleport module not loaded.")
            return true
        end
        local keys, tbl = TP.list_returns()
        print("=== Return Positions ===")
        if not keys or #keys == 0 then
            print("[ListReturns] No entries.")
            return true
        end
        for _, key in ipairs(keys) do
            local pos = tbl[key]
            if pos and pos.x and pos.y and pos.z then
                print(string.format("%s -> X=%.1f Y=%.1f Z=%.1f", key, pos.x, pos.y, pos.z))
            else
                print(tostring(key))
            end
        end
        print("[ListReturns] Total:", #keys)
        return true
    end, "lists saved return positions", "Teleport")

    local function interact_contract_terminal(pawn)
        if not is_valid(pawn) then
            return false, "Local player not found."
        end
        local origin = get_actor_location(pawn)
        local classes = { "BP_ContractManagerTerminal_C" }
        local term = find_nearest_actor(classes, origin)
        if not is_valid(term) then
            return false, "Contract terminal not found."
        end
        local fn_name = "/Game/Blueprints/Screens/Terminals/BP_TerminalBasic.BP_TerminalBasic_C:BPI_Interactable_Input"
        local ufn = resolve_ufunction(fn_name)
        local last_err = nil
        if ufn and is_ufunction(ufn) then
            local ok_cf, cf_err = call_ufunction_on(term, ufn, pawn)
            if ok_cf then
                return true, "ok"
            end
            last_err = cf_err
        end
        local ok, _, err = safe_call_err(term, "BPI_Interactable_Input", pawn)
        if ok then
            return true, "ok"
        end
        return false, tostring(err or last_err or "failed")
    end

    reg("opencontracts", function(args)
        if not TP or not get_local_pawn then
            print("[OpenContracts] Teleport module not loaded.")
            return true
        end
        if TP.teleport then
            local ok_tp, msg = TP.teleport("LOBBY:contracts")
            if not ok_tp then
                print("[OpenContracts] Teleport failed: " .. tostring(msg))
                return true
            end
        end
        local pawn = get_local_pawn()
        local ok_int, msg_int = interact_contract_terminal(pawn)
        if not ok_int then
            print("[OpenContracts] " .. tostring(msg_int))
            return true
        end
        open_contracts_active = true
        ensure_keybinds()
        if _G.RegisterKeyBind then
            print("[OpenContracts] Press ESC to return.")
        else
            print("[OpenContracts] Use returnself to return.")
        end
        return true
    end, "opens contract terminal for local player (ESC to return)", "Contracts")

    reg("startcontract", function(args)
        if not TP then
            print("[startcontract] Teleport module not loaded.")
            return true
        end
        if get_current_map and get_current_map() ~= "Lobby" then
            print("[StartContract] Only available in Lobby.")
            return true
        end
        local ok, msg = TP.teleport("LOBBY:contracts")
        if not ok then
            print("[StartContract] " .. tostring(msg))
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        local ok_int, msg_int = interact_contract_terminal(pawn)
        if not ok_int then
            print("[StartContract] " .. tostring(msg_int))
            return true
        end
        start_contract_active = true
        ensure_keybinds()
        if _G.RegisterKeyBind then
            print("[StartContract] Press ESC to teleport to ship.")
        else
            print("[StartContract] Use tp LOBBY:ship to go to ship.")
        end
        return true
    end, "teleports to contracts in Lobby and interacts (ESC -> ship)", "Contracts")

    reg("setcontract", function(args)
        args = args or {}
        local bb = _G.BlackboxRecode or {}
        local lists = {}
        if type(bb.ContractLists) == "table" then
            for _, arr in pairs(bb.ContractLists) do
                if arr ~= nil then
                    lists[#lists + 1] = arr
                end
            end
        elseif bb.ContractList then
            lists[#lists + 1] = bb.ContractList
        end
        local first = lists[1] and get_first_contract_struct(lists[1]) or nil
        local types = first and build_contract_prop_types(first) or {}

        if #args == 0 or tostring(args[1]):lower() == "help" then
            print_setcontract_help(types)
            return true
        end
        if #lists == 0 then
            print("[setcontract] No contract list cached. Open the contract terminal first.")
            print_setcontract_help(types)
            return true
        end
        if not first then
            print("[setcontract] Could not read first contract struct.")
            print_setcontract_help(types)
            return true
        end
        if #args < #CONTRACT_PROP_ORDER then
            print(string.format("[setcontract] Expected %d values, got %d.", #CONTRACT_PROP_ORDER, #args))
            print_setcontract_help(types)
            return true
        end

        local values = {}
        for i = 1, #CONTRACT_PROP_ORDER do
            local name = CONTRACT_PROP_ORDER[i]
            local raw = args[i]
            if raw == nil then
                print(string.format("[setcontract] Missing value for %s", name))
                return true
            end
            local ptype = tostring(types[name] or "")
            local val = raw
            if ptype:find("BoolProperty", 1, true) then
                local b = parse_bool(raw)
                if b == nil then
                    print(string.format("[setcontract] Invalid bool for %s: %s", name, tostring(raw)))
                    return true
                end
                val = b
            elseif ptype:find("ByteProperty", 1, true) or ptype:find("IntProperty", 1, true) then
                local n = tonumber(raw)
                if n == nil then
                    print(string.format("[setcontract] Invalid number for %s: %s", name, tostring(raw)))
                    return true
                end
                val = math.floor(n)
            else
                local b = parse_bool(raw)
                if b ~= nil then
                    val = b
                else
                    local n = tonumber(raw)
                    if n ~= nil then
                        val = math.floor(n)
                    end
                end
            end
            values[name] = val
        end

        local function contract_field_match(values_table, needle)
            local needle_l = tostring(needle or ""):lower()
            for k, v in pairs(values_table or {}) do
                if tostring(k):lower():find(needle_l, 1, true) then
                    return v
                end
            end
            return nil
        end

        local updated = 0
        local seen = {}
        for _, arr in ipairs(lists) do
            local key = tostring(arr)
            if not seen[key] then
                seen[key] = true
                updated = updated + apply_contract_list_first(arr, values)
            end
        end
        if updated <= 0 then
            notify_warn("Contract Set: no contracts updated.")
            print("[setcontract] No contracts updated.")
        else
            local info = {}
            local ctype = contract_field_match(values, "contracttype")
            local diff = contract_field_match(values, "difficulty")
            local mapv = contract_field_match(values, "map")
            if ctype ~= nil then info[#info + 1] = "Type=" .. tostring(ctype) end
            if diff ~= nil then info[#info + 1] = "Diff=" .. tostring(diff) end
            if mapv ~= nil then info[#info + 1] = "Map=" .. tostring(mapv) end
            local suffix = (#info > 0) and (" (" .. table.concat(info, " ") .. ")") or ""
            notify_ok("Contract Set: updated " .. tostring(updated) .. " list(s)" .. suffix, 3200)
            print(string.format("[setcontract] Updated %d list(s).", updated))
        end
        return true
    end, "setcontract <values...> -> overwrite first contract in each list screen (use 'setcontract help')", "Contracts")

    reg("contract_gui_state", function(args)
        local lists = get_contract_lists()
        local first = lists[1] and get_first_contract_struct(lists[1]) or nil
        local types = first and build_contract_prop_types(first) or {}
        local values = first and build_contract_values(first) or {}
        local bb = _G.BlackboxRecode or {}
        local now = (U and U.now_time and U.now_time()) or os.clock()
        local last = tonumber(bb.LastContractListTime or 0) or 0
        local age = (last > 0) and math.max(0, now - last) or -1
        local map_name = (get_current_map and get_current_map()) or "Unknown"
        local payload = {
            "READY:" .. ((#lists > 0 and first) and "1" or "0"),
            "MAP:" .. tostring(map_name),
            "LISTS:" .. tostring(#lists),
            "FIRST:" .. (first and "1" or "0"),
            "PROPS:" .. tostring(#CONTRACT_PROP_ORDER),
            "HOOKS:" .. tostring(bb.ContractListCount or 0),
            "AGE:" .. string.format("%.3f", age),
            "VALUES:" .. encode_contract_pairs(values, CONTRACT_PROP_ORDER, false),
            "TYPES:" .. encode_contract_pairs(types, CONTRACT_PROP_ORDER, false),
        }
        return true, "CONTRACTS=" .. table.concat(payload, "#")
    end, "GUI: returns contract state string", "Contracts")

    reg("activatepower", function(args)
        local gs = find_first("BP_MyGameState_C")
        if not is_valid(gs) then
            print("[Power] Could not find BP_MyGameState_C (are you fully in-game?)")
            return true
        end
        local ok, err = _call_change_light(gs, 0, true)
        if not ok then
            print("[Power] Call failed: " .. tostring(err or "unknown"))
        else
            print("[Power] Activated.")
        end
        return true
    end, "turns power ON", "Power")

    reg("deactivatepower", function(args)
        local gs = find_first("BP_MyGameState_C")
        if not is_valid(gs) then
            print("[Power] Could not find BP_MyGameState_C (are you fully in-game?)")
            return true
        end
        local ok, err = _call_change_light(gs, 1, false)
        if not ok then
            print("[Power] Call failed: " .. tostring(err or "unknown"))
        else
            print("[Power] Deactivated.")
        end
        return true
    end, "turns power OFF", "Power")

    reg("heal", function(args)
        local pawn, who = parse_target_args(args or {})
        if not pawn then
            notify_err("Heal failed: no pawn for target.")
            print("[heal] No pawn for target:", tostring(who))
            return true
        end
        local max_hp = get_number_prop(pawn, "MaxHealth")
        if not max_hp then
            notify_err("Heal failed: no MaxHealth.")
            print("[heal] No MaxHealth on target:", tostring(who))
            return true
        end
        local ok = set_prop(pawn, "Health", max_hp)
        if ok then
            notify_ok("Healed: " .. tostring(who))
        else
            notify_err("Heal failed: " .. tostring(who))
        end
        print(ok and ("[heal] OK -> " .. tostring(who)) or ("[heal] Failed -> " .. tostring(who)))
        return true
    end, "heal [target] -> sets Health to MaxHealth", "Player")

    reg("god", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not pawn then
            notify_err("Godmode failed: no pawn for target.")
            print("[god] No pawn for target:", tostring(who))
            return true
        end
        if not rest or #rest < 1 then
            print("[god] Usage: god <on|off> [target]")
            return true
        end
        local enable = parse_bool(rest[1])
        if enable == nil then
            print("[god] Usage: god <on|off> [target]")
            return true
        end
        local ok = set_prop(pawn, "bCanBeDamaged", not enable)
        if ok then
            notify_ok("Godmode " .. (enable and "ON" or "OFF") .. ": " .. tostring(who))
        else
            notify_err("Godmode failed: " .. tostring(who))
        end
        print(ok and ("[god] OK -> " .. tostring(who)) or ("[god] Failed -> " .. tostring(who)))
        return true
    end, "god <on|off> [target] -> toggle invulnerability", "Player")

    reg("stamina", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not pawn then
            notify_err("Stamina failed: no pawn for target.")
            print("[stamina] No pawn for target:", tostring(who))
            return true
        end
        if not rest or #rest < 1 then
            print("[stamina] Usage: stamina <on|off> [target]")
            return true
        end
        local enable = parse_bool(rest[1])
        if enable == nil then
            print("[stamina] Usage: stamina <on|off> [target]")
            return true
        end
        local ok = set_prop(pawn, "UnlimitedStamina", enable)
        if ok then
            notify_ok("Stamina " .. (enable and "ON" or "OFF") .. ": " .. tostring(who))
        else
            notify_err("Stamina failed: " .. tostring(who))
        end
        print(ok and ("[stamina] OK -> " .. tostring(who)) or ("[stamina] Failed -> " .. tostring(who)))
        return true
    end, "stamina <on|off> [target] -> unlimited stamina", "Player")

    reg("battery", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not pawn then
            notify_err("Battery failed: no pawn for target.")
            print("[battery] No pawn for target:", tostring(who))
            return true
        end
        if not rest or #rest < 1 then
            print("[battery] Usage: battery <on|off> [target]")
            return true
        end
        local enable = parse_bool(rest[1])
        if enable == nil then
            print("[battery] Usage: battery <on|off> [target]")
            return true
        end
        local ok = set_prop(pawn, "UnlimitedFlashlight", enable)
        if ok then
            notify_ok("Battery " .. (enable and "ON" or "OFF") .. ": " .. tostring(who))
        else
            notify_err("Battery failed: " .. tostring(who))
        end
        print(ok and ("[battery] OK -> " .. tostring(who)) or ("[battery] Failed -> " .. tostring(who)))
        return true
    end, "battery <on|off> [target] -> unlimited flashlight", "Player")

    reg("walkspeed", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not pawn then
            notify_err("Walkspeed failed: no pawn for target.")
            print("[walkspeed] No pawn for target:", tostring(who))
            return true
        end
        if not rest or #rest < 1 then
            print("[walkspeed] Usage: walkspeed <number> [target]")
            return true
        end
        local speed = tonumber(rest[1])
        if not speed then
            print("[walkspeed] Invalid speed. Provide a number.")
            return true
        end
        local ok = set_base_walk_speed(pawn, speed)
        if ok then
            notify_ok(string.format("Walkspeed %.2f -> %s", speed, tostring(who)))
            print(string.format("[walkspeed] Set BaseWalkSpeed to %.2f for %s", speed, tostring(who)))
        else
            notify_err("Walkspeed failed: " .. tostring(who))
            print("[walkspeed] Could not find BaseWalkSpeed on target:", tostring(who))
        end
        return true
    end, "walkspeed <number> [target] -> set BaseWalkSpeed", "Player")

    reg("pipeall", function(args)
        if not args or #args < 1 then
            print("[pipeall] Usage: pipeall <on|off>")
            return true
        end
        local enable = parse_bool(args[1])
        if enable == nil then
            print("[pipeall] Usage: pipeall <on|off>")
            return true
        end
        local ok = set_terminal_all_pipes(enable)
        if ok then
            notify_ok("Pipes: all " .. (enable and "ON" or "OFF"))
        else
            notify_err("Pipes failed: terminal not found.")
        end
        print(ok and ("[pipeall] OK -> " .. (enable and "on" or "off")) or "[pipeall] Failed (terminal not found?)")
        return true
    end, "pipeall <on|off> -> sets all 16 pipes via terminal", "Pipes")

    reg("pipeset", function(args)
        if not args or #args < 3 then
            print("[pipeset] Usage: pipeset <red|blue> <1-8> <on|off>")
            return true
        end
        local color = tostring(args[1] or ""):lower()
        local pipe_set = nil
        if color == "red" then
            pipe_set = 2
        elseif color == "blue" then
            pipe_set = 1
        end
        if not pipe_set then
            print("[pipeset] Color must be red or blue.")
            return true
        end
        local idx = tonumber(args[2])
        if not idx or idx < 1 or idx > 8 then
            print("[pipeset] Valve must be 1-8.")
            return true
        end
        local enable = parse_bool(args[3])
        if enable == nil then
            print("[pipeset] Usage: pipeset <red|blue> <1-8> <on|off>")
            return true
        end
        local ok = set_terminal_pipe_state(pipe_set, idx, enable)
        if ok then
            notify_ok(string.format("Pipe %s %d -> %s", color, idx, enable and "ON" or "OFF"))
        else
            notify_err("Pipe set failed: terminal not found.")
        end
        print(ok and ("[pipeset] OK -> " .. color .. " " .. idx .. " " .. (enable and "on" or "off")) or "[pipeset] Failed (terminal not found?)")
        return true
    end, "pipeset <red|blue> <1-8> <on|off> -> sets one pipe via terminal", "Pipes")

    reg("pipegoto", function(args)
        if not TP or not TP.teleport_to_location then
            notify_err("Teleport Failed: module not loaded.")
            print("[pipegoto] Teleport module not loaded.")
            return true
        end
        if not args or #args < 2 then
            print("[pipegoto] Usage: pipegoto <red|blue> <1-8>")
            return true
        end
        local color = tostring(args[1] or ""):lower()
        local idx = tonumber(args[2])
        if (color ~= "red" and color ~= "blue") or not idx or idx < 1 or idx > 8 then
            print("[pipegoto] Usage: pipegoto <red|blue> <1-8>")
            return true
        end
        local pipe_set = (color == "red") and 2 or 1
        local obj = find_valve_by_set(pipe_set, idx)
        if not obj then
            notify_warn("Teleport Failed: valve not found.")
            print("[pipegoto] Valve not found.")
            return true
        end
        local loc = get_actor_location(obj)
        if not loc then
            notify_err("Teleport Failed: valve location missing.")
            print("[pipegoto] No valve location.")
            return true
        end
        local rot = get_actor_rotation(obj)
        local safe = safe_offset_from_actor(loc, rot, 180, 80)
        local ok, msg = TP.teleport_to_location({
            x = safe and safe.X or (loc.X or 0),
            y = safe and safe.Y or (loc.Y or 0),
            z = safe and safe.Z or (loc.Z or 0),
        })
        if ok then
            notify_ok(string.format("Teleported to pipe %s %d", color, idx))
        else
            notify_err("Teleport Failed: " .. tostring(msg))
        end
        print(ok and "[pipegoto] OK" or ("[pipegoto] FAIL -> " .. tostring(msg)))
        return true
    end, "pipegoto <red|blue> <1-8> -> teleport to valve", "Pipes")

    reg("pipestatus", function(args)
        local term = get_pipe_terminal()
        if not term then
            print("[pipestatus] Terminal not found.")
            return true
        end
        local r_values = read_pipe_array(term, "Pipe2")
        local b_values = read_pipe_array(term, "Pipe1")

        local function fmt(values)
            local out = {}
            for i = 1, 8 do
                local v = values and values[i]
                if v == nil then
                    out[#out + 1] = string.format("%d=?", i)
                else
                    out[#out + 1] = string.format("%d=%s", i, v and "ON" or "OFF")
                end
            end
            return table.concat(out, " ")
        end

        print("=== Pipe Status ===")
        print("RED:  " .. fmt(r_values))
        print("BLUE: " .. fmt(b_values))
        return true
    end, "pipestatus -> prints status of all 16 pipes", "Pipes")

    reg("labairlockstatus", function(args)
        local term = get_lab_terminal()
        if not term then
            print("[labairlockstatus] Terminal not found.")
            return true
        end
        local entries, arrp = get_array_property_structs(term, LAB_STATUT_PROP)
        if not entries or #entries == 0 then
            print("[labairlockstatus] Statut not found or empty.")
            local okp, raw = safe_call(term, "GetPropertyValue", LAB_STATUT_PROP)
            if okp then
                print("[labairlockstatus] Raw Statut:", tostring(raw))
                if raw then
                    print("[labairlockstatus] Raw Statut has Get:", tostring(safe_get_field(raw, "Get") ~= nil))
                    print("[labairlockstatus] Raw Statut has Num:", tostring(safe_get_field(raw, "Num") ~= nil))
                    print("[labairlockstatus] Raw Statut has ToTable:", tostring(safe_get_field(raw, "ToTable") ~= nil))
                    print("[labairlockstatus] Raw Statut has GetArrayNum:", tostring(safe_get_field(raw, "GetArrayNum") ~= nil))
                    print("[labairlockstatus] Raw Statut has ForEach:", tostring(safe_get_field(raw, "ForEach") ~= nil))
                    local ok_ts, s = safe_call(raw, "ToString")
                    if ok_ts then
                        print("[labairlockstatus] Raw Statut ToString:", tostring(s))
                    end
                    local ok_num, n = safe_call(raw, "Num")
                    if ok_num then
                        print("[labairlockstatus] Raw Statut Num:", tostring(n))
                    end
                end
            else
                local okf, raw2 = pcall(function() return term[LAB_STATUT_PROP] end)
                if okf then
                    print("[labairlockstatus] Raw Statut (field):", tostring(raw2))
                end
            end
            local direct = safe_get_field(term, LAB_STATUT_PROP)
            if direct ~= nil then
                print("[labairlockstatus] Direct Statut:", tostring(direct))
                print("[labairlockstatus] Direct Statut has ForEach:", tostring(safe_get_field(direct, "ForEach") ~= nil))
                local ok_len, n3 = pcall(function() return #direct end)
                if ok_len then
                    print("[labairlockstatus] Direct Statut #:", tostring(n3))
                end
            end
            return true
        end
        print("=== Lab Airlock Status ===")
        for i, entry in ipairs(entries) do
            local letter = get_struct_field(entry, LAB_LETTER_PROP)
            letter = coerce_string(letter)
            if letter == nil or letter == "" then
                letter = "?"
            end
            local valid = get_struct_field(entry, LAB_VALID_PROP)
            local valid_str = (valid == true) and "TRUE" or (valid == false and "FALSE" or "?")
            print(string.format("%d) %s | Valid=%s", i, letter, valid_str))
        end
        print("[labairlockstatus] Total:", #entries)
        return true
    end, "labairlockstatus -> prints Valid status for all 4 containers", "Lab")

    reg("labairlockset", function(args)
        if not args or #args < 1 then
            print("[labairlockset] Usage: labairlockset <on|off>  OR  labairlockset <1-4|all> <on|off>")
            return true
        end
        local term = get_lab_terminal()
        if not term then
            notify_err("Lab airlock failed: terminal not found.")
            print("[labairlockset] Terminal not found.")
            return true
        end
        local enable = parse_bool(args[#args])
        if enable == nil then
            print("[labairlockset] Usage: labairlockset <on|off>  OR  labairlockset <1-4|all> <on|off>")
            return true
        end
        local target = (#args >= 2) and tostring(args[1]) or "all"
        local entries, arrp = get_array_property_structs(term, LAB_STATUT_PROP)
        if not entries or #entries == 0 then
            notify_err("Lab airlock failed: status not found.")
            print("[labairlockset] Statut not found or empty.")
            return true
        end

        local changed = 0
        local target_idx = nil
        if target:lower() ~= "all" then
            target_idx = tonumber(target)
            if not target_idx or target_idx < 1 or target_idx > #entries then
                notify_warn("Lab airlock failed: invalid index.")
                print("[labairlockset] Index must be 1-" .. tostring(#entries) .. " or 'all'.")
                return true
            end
        end

        local ok = false
        if arrp and safe_get_field(arrp, "ForEach") then
            local idx = 0
            safe_call(arrp, "ForEach", function(i, elem)
                idx = idx + 1
                if (not target_idx) or (idx == target_idx) then
                    local okg, v = pcall(function() return elem:get() end)
                    if okg and v ~= nil then
                        if set_struct_field(v, LAB_VALID_PROP, enable) then
                            changed = changed + 1
                        end
                        pcall(function() elem:set(v) end)
                    end
                end
            end)
            ok = true
        else
            if target_idx then
                if set_struct_field(entries[target_idx], LAB_VALID_PROP, enable) then
                    changed = 1
                end
            else
                for _, entry in ipairs(entries) do
                    if set_struct_field(entry, LAB_VALID_PROP, enable) then
                        changed = changed + 1
                    end
                end
            end

            if term.SetPropertyValue then
                ok = pcall(term.SetPropertyValue, term, LAB_STATUT_PROP, entries)
            end
            if not ok then
                ok = set_prop(term, LAB_STATUT_PROP, entries)
            end
        end

        if ok then
            notify_ok(string.format("Lab airlock: %d set %s", changed, enable and "ON" or "OFF"))
        else
            notify_err("Lab airlock failed to write.")
        end
        print(ok and ("[labairlockset] OK -> " .. tostring(changed)) or "[labairlockset] Failed to write.")
        return true
    end, "labairlockset <on|off> | <1-4|all> <on|off> -> set Valid flag(s)", "Lab")

    reg("puzzlestate", function(args)
        local payload = build_puzzles_payload()
        return true, payload
    end, "GUI: returns puzzles state string", "Puzzles")

    reg("activateselfdestruct", function(args)
        local engines = find_all("BP_Engine_C") or {}
        if #engines == 0 then
            print("[activateselfdestruct] No BP_Engine_C found.")
            return true
        end
        local count = 0
        for _, eng in ipairs(engines) do
            if is_valid(eng) then
                local ok_speed = set_prop(eng, "TargetSpeed", 2.5)
                if (not ok_speed) and eng.SetPropertyValue then
                    ok_speed = pcall(eng.SetPropertyValue, eng, "TargetSpeed", 2.5)
                end
                local ok_state = set_prop(eng, "EngineState", "NewEnumerator2")
                if (not ok_state) and eng.SetPropertyValue then
                    ok_state = pcall(eng.SetPropertyValue, eng, "EngineState", "NewEnumerator2")
                end
                if ok_speed or ok_state then
                    count = count + 1
                end
            end
        end
        if count > 0 then
            print("[activateselfdestruct] Set TargetSpeed=2.5 on", count, "engines.")
        else
            print("[activateselfdestruct] Failed to set TargetSpeed.")
        end
        if TP and TP.teleport then
            local ok_tp, msg = TP.teleport("engines")
            if ok_tp then
                print("[activateselfdestruct] Teleported to Engines.")
            else
                print("[activateselfdestruct] Teleport failed:", tostring(msg))
            end
        end
        return true
    end, "activateselfdestruct -> sets BP_Engine_C TargetSpeed to 2.5", "Ship")

    reg("gotoitem", function(args)
        if not args or #args < 1 then
            print("[gotoitem] Usage: gotoitem <item>")
            return true
        end
        if not TP then
            print("[gotoitem] Teleport module not loaded.")
            return true
        end
        local classes = resolve_item_classes(args[1])
        if not classes or #classes == 0 then
            print("[gotoitem] Unknown item:", tostring(args[1]))
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        local origin = pawn and get_actor_location(pawn) or nil
        local obj = find_nearest_actor(classes, origin)
        if not obj then
            print("[gotoitem] No item found.")
            return true
        end
        local loc = get_actor_location(obj)
        if not loc then
            print("[gotoitem] No item location.")
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z })
        print(ok and "[gotoitem] OK" or ("[gotoitem] FAIL -> " .. tostring(msg)))
        return true
    end, "gotoitem <item> -> teleport to item", "Items")

    reg("bringitem", function(args)
        if not args or #args < 1 then
            print("[bringitem] Usage: bringitem <item>")
            return true
        end
        if not TP then
            print("[bringitem] Teleport module not loaded.")
            return true
        end
        local classes = resolve_item_classes(args[1])
        if not classes or #classes == 0 then
            print("[bringitem] Unknown item:", tostring(args[1]))
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        if not pawn then
            print("[bringitem] No local pawn.")
            return true
        end
        local loc = get_actor_location(pawn)
        if not loc then
            print("[bringitem] No local location.")
            return true
        end
        local obj = find_nearest_actor(classes, loc)
        if not obj then
            print("[bringitem] No item found.")
            return true
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        if TP.save_local_return then
            TP.save_local_return()
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z }, obj, false)
        print(ok and "[bringitem] OK" or ("[bringitem] FAIL -> " .. tostring(msg)))
        return true
    end, "bringitem <item> -> bring item to you", "Items")

    reg("gotoweapon", function(args)
        if not args or #args < 1 then
            print("[gotoweapon] Usage: gotoweapon <weapon>")
            return true
        end
        if not TP then
            print("[gotoweapon] Teleport module not loaded.")
            return true
        end
        local cls = resolve_weapon_class(args[1])
        local pawn = get_local_pawn and get_local_pawn() or nil
        local origin = pawn and get_actor_location(pawn) or nil
        local obj = find_nearest_actor({ cls }, origin)
        if not obj then
            print("[gotoweapon] No weapon found.")
            return true
        end
        local loc = get_actor_location(obj)
        if not loc then
            print("[gotoweapon] No weapon location.")
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z })
        print(ok and "[gotoweapon] OK" or ("[gotoweapon] FAIL -> " .. tostring(msg)))
        return true
    end, "gotoweapon <weapon> -> teleport to weapon", "Weapons")

    reg("bringweapon", function(args)
        if not args or #args < 1 then
            print("[bringweapon] Usage: bringweapon <weapon>")
            return true
        end
        if not TP then
            print("[bringweapon] Teleport module not loaded.")
            return true
        end
        local cls = resolve_weapon_class(args[1])
        local pawn = get_local_pawn and get_local_pawn() or nil
        if not pawn then
            print("[bringweapon] No local pawn.")
            return true
        end
        local loc = get_actor_location(pawn)
        if not loc then
            print("[bringweapon] No local location.")
            return true
        end
        local obj = find_nearest_actor({ cls }, loc)
        if not obj then
            print("[bringweapon] No weapon found.")
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z }, obj, false)
        print(ok and "[bringweapon] OK" or ("[bringweapon] FAIL -> " .. tostring(msg)))
        return true
    end, "bringweapon <weapon> -> bring weapon to you", "Weapons")

    reg("gotomonster", function(args)
        if not args or #args < 1 then
            print("[gotomonster] Usage: gotomonster <monster>")
            return true
        end
        if not TP then
            print("[gotomonster] Teleport module not loaded.")
            return true
        end
        local cls = resolve_monster_class(args[1])
        local pawn = get_local_pawn and get_local_pawn() or nil
        local origin = pawn and get_actor_location(pawn) or nil
        local obj = find_nearest_actor({ cls }, origin)
        if not obj then
            print("[gotomonster] No monster found.")
            return true
        end
        local loc = get_actor_location(obj)
        if not loc then
            print("[gotomonster] No monster location.")
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z })
        print(ok and "[gotomonster] OK" or ("[gotomonster] FAIL -> " .. tostring(msg)))
        return true
    end, "gotomonster <monster> -> teleport to monster", "Monsters")

    reg("bringmonster", function(args)
        if not args or #args < 1 then
            print("[bringmonster] Usage: bringmonster <monster>")
            return true
        end
        if not TP then
            print("[bringmonster] Teleport module not loaded.")
            return true
        end
        local cls = resolve_monster_class(args[1])
        local pawn = get_local_pawn and get_local_pawn() or nil
        if not pawn then
            print("[bringmonster] No local pawn.")
            return true
        end
        local loc = get_actor_location(pawn)
        if not loc then
            print("[bringmonster] No local location.")
            return true
        end
        local obj = find_nearest_actor({ cls }, loc)
        if not obj then
            print("[bringmonster] No monster found.")
            return true
        end
        local ok, msg = TP.teleport_to_location({ x = loc.X, y = loc.Y, z = loc.Z }, obj, false)
        print(ok and "[bringmonster] OK" or ("[bringmonster] FAIL -> " .. tostring(msg)))
        return true
    end, "bringmonster <monster> -> bring monster to you", "Monsters")

    reg("listmonsters", function(args)
        local monsters = get_all_monsters()
        if #monsters == 0 then
            print("[listmonsters] No monsters found.")
            return true
        end
        local pawn = get_local_pawn and get_local_pawn() or nil
        local origin = pawn and get_actor_location(pawn) or nil
        print("=== Monsters ===")
        for i, m in ipairs(monsters) do
            local loc = get_actor_location(m)
            local pos_str = loc and string.format("X=%.1f Y=%.1f Z=%.1f", loc.X or 0, loc.Y or 0, loc.Z or 0) or "N/A"
            local hp = get_number_prop(m, "Health")
            local maxhp = get_number_prop(m, "MaxHealth")
            local hp_str = (hp and maxhp) and string.format("%.0f/%.0f", hp, maxhp) or (hp and string.format("%.0f", hp) or "N/A")
            local dist = origin and loc and distance3(origin, loc) or nil
            local dist_str = dist and string.format("%.1f", dist) or "N/A"
            print(string.format("%d) %s | POS %s | HP %s | Dist %s",
                i, get_actor_name(m), pos_str, hp_str, dist_str))
        end
        print("[listmonsters] Total:", #monsters)
        return true
    end, "listmonsters -> name/pos/hp/distance", "Monsters")

    reg("invisible", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not pawn then
            notify_err("Invisible failed: no pawn for target.")
            print("[invisible] No pawn for target:", tostring(who))
            return true
        end
        if not rest or #rest < 1 then
            print("[invisible] Usage: invisible <on|off> [target]")
            return true
        end
        local enable = parse_bool(rest[1])
        if enable == nil then
            print("[invisible] Usage: invisible <on|off> [target]")
            return true
        end
        local desired = not enable
        local ok = set_prop(pawn, "CanBeSeen", desired)
        if not ok then
            ok = set_prop(pawn, "bCanBeSeen", desired)
        end
        if ok then
            notify_ok("Invisible " .. (enable and "ON" or "OFF") .. ": " .. tostring(who))
        else
            notify_err("Invisible failed: " .. tostring(who))
        end
        print(ok and ("[invisible] " .. (enable and "ON" or "OFF") .. " -> " .. tostring(who))
            or ("[invisible] Failed -> " .. tostring(who)))
        return true
    end, "invisible <on|off> [target] -> sets CanBeSeen false/true", "Player")

    reg("removemonster", function(args)
        local target = args and args[1] and tostring(args[1]) or "all"
        local removed = 0
        if target:lower() == "all" then
            for _, m in ipairs(get_all_monsters()) do
                if is_valid(m) and m.K2_DestroyActor then
                    if pcall(m.K2_DestroyActor, m) then
                        removed = removed + 1
                    end
                end
            end
        else
            local cls = resolve_monster_class(target)
            local list = find_all(cls) or {}
            for _, m in ipairs(list) do
                if is_valid(m) and m.K2_DestroyActor then
                    if pcall(m.K2_DestroyActor, m) then
                        removed = removed + 1
                    end
                end
            end
        end
        print("[removemonster] Removed:", removed)
        return true
    end, "removemonster [name|all] -> destroys monsters", "Monsters")

    reg("setweapondmg", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not rest or #rest < 1 then
            print("[setweapondmg] Usage: setweapondmg <damage> [target]")
            return true
        end
        local dmg = tonumber(rest[1])
        if not dmg then
            print("[setweapondmg] Invalid damage.")
            return true
        end
        local weapon = get_player_weapon(pawn)
        local targets = {}
        local target_is_self = tostring(who or ""):lower() == "self"
        if weapon then
            targets[1] = weapon
        elseif target_is_self then
            targets = get_all_weapons()
        else
            print("[setweapondmg] No weapon found for target:", tostring(who))
            return true
        end
        if #targets == 0 then
            print("[setweapondmg] No weapons found.")
            return true
        end
        local count = 0
        for _, w in ipairs(targets) do
            if is_valid(w) then
                local ok = set_prop(w, "Damage", dmg)
                if (not ok) then
                    ok = set_prop(w, "WeaponDamage", dmg)
                end
                if ok then count = count + 1 end
            end
        end
        print("[setweapondmg] Updated:", count)
        return true
    end, "setweapondmg <damage> [target] -> set weapon damage", "Weapons")

    reg("unlimitedammo", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not rest or #rest < 1 then
            print("[unlimitedammo] Usage: unlimitedammo <on|off> [target]")
            return true
        end
        local enable = parse_bool(rest[1])
        if enable == nil then
            print("[unlimitedammo] Usage: unlimitedammo <on|off> [target]")
            return true
        end
        local weapon = get_player_weapon(pawn)
        local targets = {}
        local target_is_self = tostring(who or ""):lower() == "self"
        if weapon then
            targets[1] = weapon
        elseif target_is_self then
            targets = get_all_weapons()
        else
            print("[unlimitedammo] No weapon found for target:", tostring(who))
            return true
        end
        if #targets == 0 then
            print("[unlimitedammo] No weapons found.")
            return true
        end
        local count = 0
        for _, w in ipairs(targets) do
            if is_valid(w) then
                local ok1 = set_prop(w, "Unlimited", enable)
                local ok2 = set_prop(w, "UnlimitedAmmo", enable)
                if ok1 or ok2 then
                    count = count + 1
                end
            end
        end
        print("[unlimitedammo] Updated:", count)
        return true
    end, "unlimitedammo <on|off> [target] -> set Unlimited + UnlimitedAmmo", "Weapons")

    reg("maxammo", function(args)
        local pawn, who = parse_target_args(args or {})
        local weapon = get_player_weapon(pawn)
        local targets = {}
        local target_is_self = tostring(who or ""):lower() == "self"
        if weapon then
            targets[1] = weapon
        elseif target_is_self then
            targets = get_all_weapons()
        else
            print("[maxammo] No weapon found for target:", tostring(who))
            return true
        end
        if #targets == 0 then
            print("[maxammo] No weapons found.")
            return true
        end
        local count = 0
        for _, w in ipairs(targets) do
            if is_valid(w) then
                local ammo_max = get_number_prop(w, "AmmoMax") or get_number_prop(w, "MaxAmmo")
                local inv_max = get_number_prop(w, "AmmoInventoryMax")
                local ok = false
                if ammo_max then
                    ok = set_prop(w, "Ammo", ammo_max) or ok
                end
                if inv_max then
                    ok = set_prop(w, "AmmoInventory", inv_max) or ok
                end
                if ok then count = count + 1 end
            end
        end
        print("[maxammo] Updated:", count)
        return true
    end, "maxammo [target] -> set Ammo to AmmoMax and AmmoInventory to AmmoInventoryMax", "Weapons")

    reg("sethp", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not pawn then
            notify_err("Set HP failed: no pawn for target.")
            print("[sethp] No pawn for target:", tostring(who))
            return true
        end
        if not rest or #rest < 1 then
            print("[sethp] Usage: sethp <number> [target]")
            return true
        end
        local hp = tonumber(rest[1])
        if not hp then
            print("[sethp] Invalid hp. Provide a number.")
            return true
        end
        local ok = set_prop(pawn, "Health", hp)
        if ok then
            notify_ok("HP set to " .. tostring(hp) .. " for " .. tostring(who))
        else
            notify_err("Set HP failed: " .. tostring(who))
        end
        print(ok and ("[sethp] OK -> " .. tostring(who)) or ("[sethp] Failed -> " .. tostring(who)))
        return true
    end, "sethp <number> [target] -> set Health", "Player")

    reg("setmaxhp", function(args)
        local pawn, who, rest = parse_target_args(args or {})
        if not pawn then
            notify_err("Set Max HP failed: no pawn for target.")
            print("[setmaxhp] No pawn for target:", tostring(who))
            return true
        end
        if not rest or #rest < 1 then
            print("[setmaxhp] Usage: setmaxhp <number> [target]")
            return true
        end
        local hp = tonumber(rest[1])
        if not hp then
            print("[setmaxhp] Invalid max hp. Provide a number.")
            return true
        end
        local ok = set_prop(pawn, "MaxHealth", hp)
        if ok then
            notify_ok("Max HP set to " .. tostring(hp) .. " for " .. tostring(who))
        else
            notify_err("Set Max HP failed: " .. tostring(who))
        end
        print(ok and ("[setmaxhp] OK -> " .. tostring(who)) or ("[setmaxhp] Failed -> " .. tostring(who)))
        return true
    end, "setmaxhp <number> [target] -> set MaxHealth", "Player")

    reg("help", function(args)
        local filter = args and args[1] and tostring(args[1]) or ""
        local categories = {}
        for cmd, meta in pairs(Commands.meta or {}) do
            local cat = meta.category or "Other"
            if filter == "" or tostring(cat):lower() == tostring(filter):lower() then
                categories[cat] = categories[cat] or {}
                categories[cat][#categories[cat] + 1] = cmd
            end
        end

        local cat_keys = {}
        for cat in pairs(categories) do
            cat_keys[#cat_keys + 1] = cat
        end
        table.sort(cat_keys)

        if #cat_keys == 0 then
            print("[help] No commands registered.")
            return true
        end

        for _, cat in ipairs(cat_keys) do
            print("=== " .. tostring(cat) .. " ===")
            local list = categories[cat]
            table.sort(list)
            for _, cmd in ipairs(list) do
                local meta = Commands.meta and Commands.meta[cmd] or nil
                local h = meta and meta.help or ""
                if h ~= "" then
                    print(string.format("%s - %s", cmd, h))
                else
                    print(cmd)
                end
            end
        end
        return true
    end, "help [category] -> lists commands by category", "General")

    -- Expose some nicer 'action' names for GUI later (optional aliases)
    Commands.actions.teleport = Commands.actions.tp
    Commands.actions.teleport_list = Commands.actions.tplist

    print("[BlackboxRecode] Commands loaded:",
        "checkcommands, getmap, getpos, hookprints, dumpfn, testsocket, tp, tplist, returnself, returnall, listreturns, tpsetreturn, tpreturn, tpmap, tpallmap, bringallplayers, tpnearest, bringnearest, tp_gui_state, opencontracts, startcontract, setcontract, contract_gui_state, listplayers, listplayers_gui, weapon_gui_state, state_snapshot, registry_clear, registry_rebuild, world_registry_scan, world_gui_state, world_tp, world_bring, gotoplayer, bringplayer, tpplayerto, heal, god, stamina, battery, walkspeed, sethp, setmaxhp, invisible, pipeall, pipeset, pipegoto, pipestatus, labairlockstatus, labairlockset, puzzlestate, activateselfdestruct, gotoitem, bringitem, gotoweapon, bringweapon, gotomonster, bringmonster, listmonsters, removemonster, setweapondmg, unlimitedammo, maxammo, help")
end

return Commands
