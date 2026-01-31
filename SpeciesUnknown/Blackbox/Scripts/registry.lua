-- registry.lua
-- World object registry (hook + scan based) with payload caching.

local Registry = {}

local U = nil
local P = nil
local TP = nil
local is_valid = _G.is_valid
local is_world_actor = _G.is_world_actor
local find_all = _G.find_all
local trim = _G.trim
local get_local_pawn = _G.get_local_pawn

local REGISTRY = {
    by_tag = {},
    by_obj = setmetatable({}, { __mode = "k" }),
    by_uid = {},
    by_id = {},
    id_by_obj = setmetatable({}, { __mode = "k" }),
    uid_by_obj = setmetatable({}, { __mode = "k" }),
    rules = {},
    rule_by_class = {},
    dirty = true,
    emit_requested = false,
    force_emit = false,
    last_payload = "",
    last_emit = 0,
    last_prune = 0,
    last_rescan = 0,
    initial_scan_done = false,
    self_pos = nil,
    alias_by_class = nil,
    next_id = 1,
    pending = {},
    pending_set = setmetatable({}, { __mode = "k" }),
    name_queue = {},
    name_queue_set = setmetatable({}, { __mode = "k" }),
    scan_jobs = {},
    scan_job_idx = 1,
    scan_list = nil,
    scan_list_idx = 1,
    scan_active = false,
    scan_seen = nil,
    ready_since = nil,
}

local EMIT_COOLDOWN = 0.25
local PRUNE_INTERVAL = 1.0
local RESCAN_INTERVAL = 20.0
local SCAN_BATCH_MAX = 120
local TRACK_BATCH_MAX = 80
local NAME_BATCH_MAX = 40
local CLASSIFY_DELAY = 0.25
local NAME_DELAY = 0.6
local MAX_CLASSIFY_ATTEMPTS = 4
local MAX_NAME_ATTEMPTS = 6
local READY_SCAN_DELAY = 0.8

local function now_time()
    return (U and U.now_time and U.now_time()) or os.clock()
end

local function _alloc_id(obj)
    local existing = REGISTRY.id_by_obj[obj]
    if existing then
        return existing
    end
    local id = REGISTRY.next_id or 1
    REGISTRY.next_id = id + 1
    REGISTRY.id_by_obj[obj] = id
    return id
end

local function _get_class_name(obj)
    if not obj or not obj.GetClass then return nil end
    local ok, cls = pcall(obj.GetClass, obj)
    if not ok or not cls or not cls.GetName then return nil end
    local okn, name = pcall(cls.GetName, cls)
    if okn and name then
        return tostring(name)
    end
    return nil
end

local function _get_uid(obj)
    if not obj then return nil end
    local fn = obj.GetUniqueID
    if type(fn) == "function" then
        local ok, v = pcall(fn, obj)
        if ok and v ~= nil then
            local n = tonumber(v)
            if n and n > 0 then return n end
        end
    end
    local ok_prop, vprop = pcall(function() return obj.UniqueID end)
    if ok_prop then
        local n = tonumber(vprop)
        if n and n > 0 then return n end
    end
    local ok_idx, v_idx = pcall(function() return obj.InternalIndex end)
    if ok_idx then
        local n = tonumber(v_idx)
        if n and n > 0 then return n end
    end
    return nil
end

local function _get_uid_cached(obj)
    local cached = REGISTRY.uid_by_obj[obj]
    if cached then
        return cached
    end
    local uid = _get_uid(obj)
    if uid then
        REGISTRY.uid_by_obj[obj] = uid
    end
    return uid
end

local function _find_entry(obj)
    local uid = _get_uid_cached(obj)
    if uid then
        return REGISTRY.by_uid[uid], uid
    end
    return REGISTRY.by_obj[obj], nil
end

local function get_actor_location(obj)
    if not is_valid(obj) or not obj.K2_GetActorLocation then return nil end
    local ok, loc = pcall(obj.K2_GetActorLocation, obj)
    if ok then return loc end
    return nil
end

local function get_number_prop(obj, prop)
    if not is_valid(obj) then return nil end
    local ok, v = pcall(function()
        return obj[prop]
    end)
    if not ok then return nil end
    return tonumber(v)
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
        if t == "table" then
            return tostring(v)
        end
        return nil
    end
    return tostring(v)
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
    return "Unknown"
end

local function sanitize_token(s)
    s = tostring(s or "")
    s = s:gsub("[|,;\r\n]", " ")
    s = s:gsub("%s+", " ")
    return trim(s)
end

local function is_bogus_location(x, y)
    return math.abs(x or 0) < 30 and math.abs(y or 0) < 30
end

local function add_rule(tag, short, code)
    if not short or short == "" then return end
    local existing = REGISTRY.rule_by_class[short]
    if existing then
        if not existing.code and code then
            existing.code = code
        end
        if not existing.tag and tag then
            existing.tag = tag
        end
        return
    end
    REGISTRY.rules[#REGISTRY.rules + 1] = {
        tag = tag,
        short = short,
        code = code,
    }
    REGISTRY.rule_by_class[short] = { tag = tag, code = code, short = short }
end

local function humanize_key(key)
    key = tostring(key or "")
    if key == "" then return key end
    key = key:gsub("_", " ")
    key = key:gsub("([a-z])([A-Z])", "%1 %2")
    key = key:gsub("(%a)(%d)", "%1 %2")
    key = key:gsub("%s+", " ")
    return trim(key)
end

local function build_alias_map()
    local map = {}
    if P and P.MONSTERS then
        for name, cls in pairs(P.MONSTERS) do
            map[cls] = humanize_key(name)
        end
    end
    if P and P.ITEMS then
        for name, cls in pairs(P.ITEMS) do
            local alias = humanize_key(name)
            if name == "DataDisk" then alias = "Data Disk" end
            if name == "BlackBox" then alias = "Blackbox" end
            map[cls] = alias
        end
    end
    if P and P.WEAPONS then
        for name, info in pairs(P.WEAPONS) do
            if info and info.class then
                map[info.class] = humanize_key(name)
            end
        end
    end
    if P and P.PIPES then
        -- Pipes intentionally excluded from world registry
    end
    return map
end

local function rebuild_rules()
    REGISTRY.rules = {}
    REGISTRY.rule_by_class = {}

    if P and P.CLASS_RULES then
        for _, rule in ipairs(P.CLASS_RULES) do
            if rule and rule.short and rule.short ~= "" then
                add_rule(rule.tag, rule.short, rule.code)
            end
        end
    end

    if P and P.MONSTERS then
        for _, cls in pairs(P.MONSTERS) do
            add_rule("MONSTER", cls, nil)
        end
    end

    if P and P.WEAPONS then
        for _, w in pairs(P.WEAPONS) do
            add_rule("WEAPON", w.class, w.code)
        end
    end

    if P and P.ITEMS then
        add_rule("MONEY", P.ITEMS.Credit1, nil)
        add_rule("MONEY", P.ITEMS.Credit2, nil)
        add_rule("MONEY", P.ITEMS.Credit3, nil)
        add_rule("DATA", P.ITEMS.DataDisk, nil)
        add_rule("OBJECTIVE", P.ITEMS.Keycard, nil)
        add_rule("BLACKBOX", P.ITEMS.BlackBox, nil)
    end

    -- Pipes intentionally excluded from world registry
end

local function classify_obj(obj)
    if not obj then return nil end
    local cls_name = _get_class_name(obj)
    if cls_name and REGISTRY.rule_by_class[cls_name] then
        local rule = REGISTRY.rule_by_class[cls_name]
        return rule.tag, rule.code, rule.short
    end
    if obj.IsA then
        for _, rule in ipairs(REGISTRY.rules) do
            if rule.short then
                local ok, v = pcall(obj.IsA, obj, rule.short)
                if ok and v then
                    return rule.tag, rule.code, rule.short
                end
            end
        end
    end
    return nil
end

local function get_tag_registry(tag)
    local reg = REGISTRY.by_tag[tag]
    if not reg then
        reg = {}
        REGISTRY.by_tag[tag] = reg
    end
    return reg
end

local function update_location(entry, loc)
    if not loc then return false end
    local x = tonumber(loc.X) or 0
    local y = tonumber(loc.Y) or 0
    local z = tonumber(loc.Z) or 0

    if is_bogus_location(x, y) then
        local changed = entry.bogus ~= true
        entry.bogus = true
        return changed
    end

    local changed = false
    if entry.x ~= x then entry.x = x; changed = true end
    if entry.y ~= y then entry.y = y; changed = true end
    if entry.z ~= z then entry.z = z; changed = true end
    if entry.bogus then
        entry.bogus = false
        changed = true
    end
    return changed
end

local function _queue_pending(obj)
    if REGISTRY.pending_set[obj] then return end
    REGISTRY.pending_set[obj] = true
    REGISTRY.pending[#REGISTRY.pending + 1] = {
        obj = obj,
        t = now_time(),
        attempts = 0,
    }
end

local function _queue_name(entry)
    if not entry or not entry.obj then return end
    local obj = entry.obj
    if REGISTRY.name_queue_set[obj] then return end
    REGISTRY.name_queue_set[obj] = true
    REGISTRY.name_queue[#REGISTRY.name_queue + 1] = {
        entry = entry,
        t = now_time(),
        attempts = 0,
    }
end

local function _add_or_update_entry(obj, tag, code, short, now)
    local entry, uid = _find_entry(obj)
    local changed = false
    local old_tag = entry and entry.tag or nil
    local old_key = entry and entry.key or nil
    if not entry then
        entry = {}
        REGISTRY.by_obj[obj] = entry
        local id = uid or _alloc_id(obj)
        entry.uid = uid
        entry.id = tostring(id)
        entry.key = entry.id
        REGISTRY.by_id[entry.id] = entry
        if uid then
            REGISTRY.by_uid[uid] = entry
        end
        entry.name = "Unknown #" .. tostring(entry.id)
        changed = true
    else
        if uid and not entry.uid then
            entry.uid = uid
            REGISTRY.by_uid[uid] = entry
        end
        if uid and tostring(uid) ~= entry.id then
            if REGISTRY.by_id[entry.id] == entry then
                REGISTRY.by_id[entry.id] = nil
            end
            entry.id = tostring(uid)
            entry.key = entry.id
            REGISTRY.by_id[entry.id] = entry
            changed = true
        end
    end
    if REGISTRY.by_obj[obj] ~= entry then
        REGISTRY.by_obj[obj] = entry
    end

    if old_tag then
        local old_reg = REGISTRY.by_tag[old_tag]
        if old_reg and old_key and old_reg[old_key] == entry then
            old_reg[old_key] = nil
        end
        if old_reg and entry.key and old_reg[entry.key] == entry and old_tag ~= tag then
            old_reg[entry.key] = nil
        end
    end

    local reg = get_tag_registry(tag)
    if not entry.key then
        entry.key = entry.id
    end
    if reg[entry.key] ~= entry then
        reg[entry.key] = entry
        changed = true
    end

    if entry.tag ~= tag then entry.tag = tag; changed = true end
    if entry.code ~= code then entry.code = code; changed = true end
    if entry.class ~= short then entry.class = short; changed = true end
    entry.obj = obj
    entry.last_seen = now or now_time()

    if not entry.name_ready then
        local alias = REGISTRY.alias_by_class and REGISTRY.alias_by_class[short] or nil
        if alias and alias ~= "" then
            if entry.name ~= alias then
                entry.name = alias
                changed = true
            end
            entry.name_ready = true
        else
            _queue_name(entry)
        end
    end

    if REGISTRY.scan_active and REGISTRY.scan_seen then
        REGISTRY.scan_seen[entry.key] = true
        REGISTRY.scan_seen[obj] = true
    end

    local loc = get_actor_location(obj)
    if update_location(entry, loc) then
        changed = true
    end

    return entry, changed
end

function Registry.init(Util, Pointers, Teleport)
    U = Util
    P = Pointers
    TP = Teleport
    if not is_valid and U and U.is_valid then is_valid = U.is_valid end
    if not is_world_actor and U and U.is_world_actor then is_world_actor = U.is_world_actor end
    if not find_all and U and U.find_all then find_all = U.find_all end
    if not trim and U and U.trim then trim = U.trim end
    if not get_local_pawn and U and U.get_local_pawn then get_local_pawn = U.get_local_pawn end
    rebuild_rules()
    REGISTRY.by_obj = setmetatable({}, { __mode = "k" })
    REGISTRY.by_uid = {}
    REGISTRY.by_id = {}
    REGISTRY.id_by_obj = setmetatable({}, { __mode = "k" })
    REGISTRY.uid_by_obj = setmetatable({}, { __mode = "k" })
    REGISTRY.pending = {}
    REGISTRY.pending_set = setmetatable({}, { __mode = "k" })
    REGISTRY.name_queue = {}
    REGISTRY.name_queue_set = setmetatable({}, { __mode = "k" })
    REGISTRY.scan_jobs = {}
    REGISTRY.scan_job_idx = 1
    REGISTRY.scan_list = nil
    REGISTRY.scan_list_idx = 1
    REGISTRY.scan_active = false
    REGISTRY.scan_seen = nil
    REGISTRY.ready_since = nil
    REGISTRY.initial_scan_done = false
    REGISTRY.next_id = 1
    REGISTRY.alias_by_class = build_alias_map()
    REGISTRY.by_tag.PIPE = nil
    REGISTRY.dirty = true
end

function Registry.request_emit(force)
    REGISTRY.emit_requested = true
    REGISTRY.force_emit = force and true or REGISTRY.force_emit
end

function Registry.track(obj)
    if not is_valid(obj) or not is_world_actor(obj) then return false end
    local entry, uid = _find_entry(obj)
    local changed = false
    if entry then
        if REGISTRY.by_obj[obj] ~= entry then
            REGISTRY.by_obj[obj] = entry
        end
        if uid and REGISTRY.uid_by_obj[obj] ~= uid then
            REGISTRY.uid_by_obj[obj] = uid
        end
        entry.last_seen = now_time()
        local loc = get_actor_location(obj)
        if update_location(entry, loc) then
            changed = true
        end
        if changed then
            REGISTRY.dirty = true
        end
        if REGISTRY.scan_active and REGISTRY.scan_seen then
            if entry.key then
                REGISTRY.scan_seen[entry.key] = true
            end
        end
        return changed
    end
    _queue_pending(obj)
    return false
end

function Registry.untrack(obj)
    if not obj then return false end
    local entry = nil
    local uid = _get_uid_cached(obj)
    if uid and REGISTRY.by_uid[uid] then
        entry = REGISTRY.by_uid[uid]
    else
        entry = REGISTRY.by_obj[obj]
    end
    if not entry then
        REGISTRY.pending_set[obj] = nil
        REGISTRY.name_queue_set[obj] = nil
        return false
    end
    if entry.tag and REGISTRY.by_tag[entry.tag] and entry.key then
        REGISTRY.by_tag[entry.tag][entry.key] = nil
    end
    for o, e in pairs(REGISTRY.by_obj) do
        if e == entry then
            REGISTRY.by_obj[o] = nil
            REGISTRY.id_by_obj[o] = nil
            REGISTRY.uid_by_obj[o] = nil
        end
    end
    if entry.uid then
        REGISTRY.by_uid[entry.uid] = nil
    end
    if entry.id then
        REGISTRY.by_id[entry.id] = nil
    end
    REGISTRY.pending_set[obj] = nil
    REGISTRY.name_queue_set[obj] = nil
    REGISTRY.dirty = true
    return true
end

function Registry.refresh_positions()
    local changed = false
    local to_remove = {}
    for _, entry in pairs(REGISTRY.by_id) do
        local obj = entry and entry.obj or nil
        if not obj or not is_valid(obj) or not is_world_actor(obj) then
            to_remove[#to_remove + 1] = obj
        else
            local loc = get_actor_location(obj)
            if update_location(entry, loc) then
                changed = true
            end
        end
    end
    for i = 1, #to_remove do
        Registry.untrack(to_remove[i])
        changed = true
    end
    if changed then
        REGISTRY.dirty = true
    end
    return changed
end

function Registry.prune(now)
    if not now then now = now_time() end
    if (now - REGISTRY.last_prune) < PRUNE_INTERVAL then
        return false
    end
    REGISTRY.last_prune = now
    return Registry.refresh_positions()
end

local function _start_scan(force)
    REGISTRY.scan_jobs = {}
    for i = 1, #REGISTRY.rules do
        REGISTRY.scan_jobs[i] = REGISTRY.rules[i]
    end
    REGISTRY.scan_job_idx = 1
    REGISTRY.scan_list = nil
    REGISTRY.scan_list_idx = 1
    REGISTRY.scan_current_rule = nil
    REGISTRY.scan_seen = {}
    REGISTRY.scan_active = true
    REGISTRY.scan_started_at = now_time()
    if force then
        REGISTRY.initial_scan_done = false
    end
end

local function _finish_scan()
    local seen = REGISTRY.scan_seen or {}
    local cutoff = REGISTRY.scan_started_at or 0
    local to_remove = {}
    for _, entry in pairs(REGISTRY.by_id) do
        if entry and (not seen[entry.key]) and (entry.last_seen or 0) <= cutoff then
            if entry.obj then
                to_remove[#to_remove + 1] = entry.obj
            else
                if entry.tag and REGISTRY.by_tag[entry.tag] and entry.key then
                    REGISTRY.by_tag[entry.tag][entry.key] = nil
                end
                if entry.uid then
                    REGISTRY.by_uid[entry.uid] = nil
                end
                if entry.id then
                    REGISTRY.by_id[entry.id] = nil
                end
            end
        end
    end
    for i = 1, #to_remove do
        Registry.untrack(to_remove[i])
    end
    REGISTRY.scan_active = false
    REGISTRY.scan_seen = nil
    REGISTRY.scan_current_rule = nil
    REGISTRY.scan_list = nil
    REGISTRY.scan_list_idx = 1
    REGISTRY.scan_job_idx = 1
    REGISTRY.initial_scan_done = true
end

local function _process_scan(now)
    if not REGISTRY.scan_active then return end
    local processed = 0
    while processed < SCAN_BATCH_MAX and REGISTRY.scan_active do
        if not REGISTRY.scan_list then
            local rule = REGISTRY.scan_jobs[REGISTRY.scan_job_idx]
            if not rule then
                _finish_scan()
                break
            end
            REGISTRY.scan_current_rule = rule
            REGISTRY.scan_list = find_all(rule.short) or {}
            REGISTRY.scan_list_idx = 1
        end

        local rule = REGISTRY.scan_current_rule
        while processed < SCAN_BATCH_MAX and REGISTRY.scan_list_idx <= #REGISTRY.scan_list do
            local obj = REGISTRY.scan_list[REGISTRY.scan_list_idx]
            REGISTRY.scan_list_idx = REGISTRY.scan_list_idx + 1
            if is_valid(obj) and is_world_actor(obj) then
                local _entry, changed = _add_or_update_entry(obj, rule.tag, rule.code, rule.short, now)
                if changed then
                    REGISTRY.dirty = true
                end
            end
            processed = processed + 1
        end

        if REGISTRY.scan_list_idx > #REGISTRY.scan_list then
            REGISTRY.scan_list = nil
            REGISTRY.scan_current_rule = nil
            REGISTRY.scan_job_idx = REGISTRY.scan_job_idx + 1
        end
    end
end

local function _process_pending(now)
    if #REGISTRY.pending == 0 then return end
    local processed = 0
    local i = 1
    while i <= #REGISTRY.pending and processed < TRACK_BATCH_MAX do
        local item = REGISTRY.pending[i]
        local obj = item and item.obj or nil
        if not obj or not is_valid(obj) or not is_world_actor(obj) then
            REGISTRY.pending_set[obj] = nil
            table.remove(REGISTRY.pending, i)
        elseif (now - (item.t or 0)) < CLASSIFY_DELAY then
            i = i + 1
        else
            local tag, code, short = classify_obj(obj)
            if tag then
                REGISTRY.pending_set[obj] = nil
                table.remove(REGISTRY.pending, i)
                local _entry, changed = _add_or_update_entry(obj, tag, code, short, now)
                if changed then
                    REGISTRY.dirty = true
                end
                processed = processed + 1
            else
                item.attempts = (item.attempts or 0) + 1
                item.t = now
                if item.attempts >= MAX_CLASSIFY_ATTEMPTS then
                    REGISTRY.pending_set[obj] = nil
                    table.remove(REGISTRY.pending, i)
                else
                    i = i + 1
                end
            end
        end
    end
end

local function _process_name_queue(now)
    if #REGISTRY.name_queue == 0 then return end
    local processed = 0
    local i = 1
    while i <= #REGISTRY.name_queue and processed < NAME_BATCH_MAX do
        local item = REGISTRY.name_queue[i]
        local entry = item and item.entry or nil
        local obj = entry and entry.obj or nil
        if not entry or not obj or not is_valid(obj) then
            if obj then REGISTRY.name_queue_set[obj] = nil end
            table.remove(REGISTRY.name_queue, i)
        elseif (now - (item.t or 0)) < NAME_DELAY then
            i = i + 1
        else
            local name = get_actor_name(obj)
            if name and name ~= "" and name ~= "Unknown" then
                entry.name = sanitize_token(name)
                entry.name_ready = true
                REGISTRY.name_queue_set[obj] = nil
                table.remove(REGISTRY.name_queue, i)
                REGISTRY.dirty = true
                processed = processed + 1
            else
                item.attempts = (item.attempts or 0) + 1
                item.t = now
                if item.attempts >= MAX_NAME_ATTEMPTS then
                    REGISTRY.name_queue_set[obj] = nil
                    table.remove(REGISTRY.name_queue, i)
                else
                    i = i + 1
                end
            end
        end
    end
end

local function _update_ready_state(now)
    local pawn = (get_local_pawn and get_local_pawn()) or nil
    if pawn and is_valid(pawn) then
        if not REGISTRY.ready_since then
            REGISTRY.ready_since = now
        end
    else
        REGISTRY.ready_since = nil
    end
end

function Registry.full_rescan()
    _start_scan(true)
    return true
end

function Registry.initial_scan()
    if REGISTRY.initial_scan_done or REGISTRY.scan_active then return end
    _start_scan(false)
end

local function tag_order()
    local order = {}
    local seen = {}
    local extra = {}
    if P and P.TAGS and P.TAGS.StaticTagOrder then
        for _, tag in ipairs(P.TAGS.StaticTagOrder) do
            if tag and not seen[tag] then
                seen[tag] = true
                order[#order + 1] = tag
            end
        end
    end
    for tag in pairs(REGISTRY.by_tag) do
        if not seen[tag] then
            seen[tag] = true
            extra[#extra + 1] = tag
        end
    end
    table.sort(extra)
    for _, tag in ipairs(extra) do
        order[#order + 1] = tag
    end
    return order
end

function Registry.list_entries()
    local out = {}
    for _, tag in ipairs(tag_order()) do
        local reg = REGISTRY.by_tag[tag]
        if reg then
            for _, entry in pairs(reg) do
                if entry then
                    out[#out + 1] = entry
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local at = tostring(a.tag or "")
        local bt = tostring(b.tag or "")
        if at ~= bt then
            return at < bt
        end
        return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
    end)
    return out
end

function Registry.get_entry_by_id(id)
    if not id or id == "" then return nil end
    local key = tostring(id)
    return REGISTRY.by_id[key] or REGISTRY.by_id[tonumber(id) or ""] or REGISTRY.by_id[id]
end

function Registry.get_counts()
    local counts = {
        total = 0,
        monsters = 0,
        keycards = 0,
        disks = 0,
        blackbox = 0,
        weapons = 0,
        money = 0,
        puzzles = 0,
        last_emit = REGISTRY.last_emit,
        last_prune = REGISTRY.last_prune,
        last_rescan = REGISTRY.last_rescan,
    }
    for tag, reg in pairs(REGISTRY.by_tag) do
        local tag_up = tostring(tag or ""):upper()
        local n = 0
        for _ in pairs(reg or {}) do
            n = n + 1
        end
        counts.total = counts.total + n
        if tag_up == "MONSTER" then
            counts.monsters = counts.monsters + n
        elseif tag_up == "OBJECTIVE" or tag_up == "KEYCARD" then
            counts.keycards = counts.keycards + n
        elseif tag_up == "DATA" then
            counts.disks = counts.disks + n
        elseif tag_up == "BLACKBOX" then
            counts.blackbox = counts.blackbox + n
        elseif tag_up == "WEAPON" then
            counts.weapons = counts.weapons + n
        elseif tag_up == "MONEY" then
            counts.money = counts.money + n
        elseif tag_up == "PUZZLES" then
            counts.puzzles = counts.puzzles + n
        end
    end
    return counts
end

function Registry.clear()
    for tag in pairs(REGISTRY.by_tag) do
        REGISTRY.by_tag[tag] = {}
    end
    REGISTRY.by_obj = setmetatable({}, { __mode = "k" })
    REGISTRY.by_uid = {}
    REGISTRY.by_id = {}
    REGISTRY.id_by_obj = setmetatable({}, { __mode = "k" })
    REGISTRY.uid_by_obj = setmetatable({}, { __mode = "k" })
    REGISTRY.pending = {}
    REGISTRY.pending_set = setmetatable({}, { __mode = "k" })
    REGISTRY.name_queue = {}
    REGISTRY.name_queue_set = setmetatable({}, { __mode = "k" })
    REGISTRY.scan_jobs = {}
    REGISTRY.scan_job_idx = 1
    REGISTRY.scan_list = nil
    REGISTRY.scan_list_idx = 1
    REGISTRY.scan_active = false
    REGISTRY.scan_seen = nil
    REGISTRY.scan_current_rule = nil
    REGISTRY.ready_since = nil
    REGISTRY.initial_scan_done = false
    REGISTRY.next_id = 1
    REGISTRY.dirty = true
    return true
end

function Registry.rebuild()
    Registry.clear()
    Registry.full_rescan()
    return true
end

local function entry_status(entry)
    if not entry then return "UNKNOWN" end
    local tag = tostring(entry.tag or "")
    if tag == "MONSTER" then
        local hp = get_number_prop(entry.obj, "Health")
        local maxhp = get_number_prop(entry.obj, "MaxHealth")
        if hp and maxhp then
            return string.format("HP %.0f/%.0f", hp, maxhp)
        end
        if hp then
            return string.format("HP %.0f", hp)
        end
        return "HP ?"
    end
    if entry.bogus then
        return "Collected"
    end
    return "Uncollected"
end

local function get_player_location()
    local pawn = (get_local_pawn and get_local_pawn()) or nil
    if pawn and is_valid(pawn) then
        return get_actor_location(pawn)
    end
    return nil
end

local function update_self_position()
    local loc = get_player_location()
    if not loc then
        return false
    end
    local x = tonumber(loc.X) or 0
    local y = tonumber(loc.Y) or 0
    local z = tonumber(loc.Z) or 0
    local prev = REGISTRY.self_pos
    if not prev then
        REGISTRY.self_pos = { x = x, y = y, z = z }
        return true
    end
    local dx = math.abs((prev.x or 0) - x)
    local dy = math.abs((prev.y or 0) - y)
    local dz = math.abs((prev.z or 0) - z)
    if dx > 1 or dy > 1 or dz > 1 then
        REGISTRY.self_pos = { x = x, y = y, z = z }
        return true
    end
    return false
end

function Registry.build_payload()
    local parts = {}
    local self_loc = REGISTRY.self_pos
    if self_loc then
        local sx = string.format("%.1f", tonumber(self_loc.x) or 0)
        local sy = string.format("%.1f", tonumber(self_loc.y) or 0)
        local sz = string.format("%.1f", tonumber(self_loc.z) or 0)
        parts[#parts + 1] = table.concat({ "SELF", "", "Self", sx, sy, sz, "", "" }, ",")
    end
    for _, entry in ipairs(Registry.list_entries()) do
        local tag = sanitize_token(entry.tag or "OBJECT")
        local code = sanitize_token(entry.code or "")
        local name = sanitize_token(entry.name or entry.class or "Unknown")
        local x = (entry.x ~= nil) and string.format("%.1f", entry.x) or ""
        local y = (entry.y ~= nil) and string.format("%.1f", entry.y) or ""
        local z = (entry.z ~= nil) and string.format("%.1f", entry.z) or ""
        local id = sanitize_token(entry.id or "")
        local status = entry_status(entry)
        parts[#parts + 1] = table.concat({ tag, code, name, x, y, z, id, status }, ",")
    end
    return "WORLD=" .. table.concat(parts, ";")
end

function Registry.consume_payload(force)
    local now = now_time()
    local wants_emit = REGISTRY.dirty or REGISTRY.emit_requested or force
    if not wants_emit then
        return nil
    end
    if not force and (now - REGISTRY.last_emit) < EMIT_COOLDOWN then
        return nil
    end
    local payload = Registry.build_payload()
    if not force and payload == REGISTRY.last_payload then
        REGISTRY.dirty = false
        REGISTRY.emit_requested = false
        REGISTRY.force_emit = false
        REGISTRY.last_emit = now
        return nil
    end
    REGISTRY.last_payload = payload
    REGISTRY.last_emit = now
    REGISTRY.dirty = false
    REGISTRY.emit_requested = false
    REGISTRY.force_emit = false
    return payload
end

function Registry.tick(force_emit)
    local now = now_time()
    _update_ready_state(now)
    if not REGISTRY.initial_scan_done and not REGISTRY.scan_active then
        if REGISTRY.ready_since and (now - REGISTRY.ready_since) >= READY_SCAN_DELAY then
            Registry.initial_scan()
        end
    end
    _process_pending(now)
    _process_scan(now)
    _process_name_queue(now)
    if update_self_position() then
        REGISTRY.dirty = true
    end
    if RESCAN_INTERVAL > 0 and (now - REGISTRY.last_rescan) > RESCAN_INTERVAL and not REGISTRY.scan_active then
        REGISTRY.last_rescan = now
        Registry.full_rescan()
    end
    Registry.prune(now)
    return Registry.consume_payload(force_emit or REGISTRY.force_emit)
end

return Registry
