-- registry.lua
-- World object registry (hook + scan based) with payload caching.

local Registry = {}

local U = nil
local P = nil
local TP = nil

local REGISTRY = {
    by_tag = {},
    by_id = {},
    rules = {},
    dirty = true,
    emit_requested = false,
    force_emit = false,
    last_payload = "",
    last_emit = 0,
    last_prune = 0,
    last_rescan = 0,
    initial_scan_done = false,
    self_pos = nil,
}

local EMIT_COOLDOWN = 0.25
local PRUNE_INTERVAL = 1.0
local RESCAN_INTERVAL = 0.0

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
    if obj.GetFullName then
        local ok, n = pcall(obj.GetFullName, obj)
        if ok and n ~= nil then
            n = coerce_string(n)
            if n and n ~= "" then return n end
        end
    end
    return tostring(obj)
end

local function trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sanitize_token(s)
    s = tostring(s or "")
    s = s:gsub("[|,;\r\n]", " ")
    s = s:gsub("%s+", " ")
    return trim(s)
end

local function sanitize_id(s)
    s = tostring(s or "")
    s = s:gsub("[%s|,;\r\n]", "_")
    s = s:gsub("_+", "_")
    return trim(s)
end

local function is_bogus_location(x, y)
    return math.abs(x or 0) < 30 and math.abs(y or 0) < 30
end

local function add_rule(tag, short, code)
    if not short or short == "" then return end
    REGISTRY.rules[#REGISTRY.rules + 1] = {
        tag = tag,
        short = short,
        code = code,
    }
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

local function classify_full(full)
    if not full or full == "" then return nil end
    for _, rule in ipairs(REGISTRY.rules) do
        if rule.short and full:find(rule.short, 1, true) then
            return rule.tag, rule.code, rule.short
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

function Registry.init(Util, Pointers, Teleport)
    U = Util
    P = Pointers
    TP = Teleport
    rebuild_rules()
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
    local full = ""
    if obj.GetFullName then
        local ok, res = pcall(obj.GetFullName, obj)
        if ok then full = tostring(res or "") end
    end
    if full == "" then full = tostring(obj) end

    local tag, code, short = classify_full(full)
    if not tag then return false end
    local key = object_key(obj)
    if not key or key == "" then return false end

    local reg = get_tag_registry(tag)
    local entry = reg[key]
    local changed = false
    if not entry then
        entry = { key = key }
        reg[key] = entry
        changed = true
    end

    local alias = nil
    if REGISTRY.alias_by_class then
        alias = REGISTRY.alias_by_class[short]
    end
    if not alias or alias == "" then
        alias = sanitize_token(get_actor_name(obj))
        if alias:find("/Game/", 1, true) or alias:find("PersistentLevel", 1, true) then
            local last = alias:match("([^%.%/]+)$")
            if last and last ~= "" then
                alias = last
            end
        end
    end
    if entry.tag ~= tag then entry.tag = tag; changed = true end
    if entry.code ~= code then entry.code = code; changed = true end
    if entry.class ~= short then entry.class = short; changed = true end
    if entry.full ~= full then entry.full = full; changed = true end
    if entry.name ~= alias then entry.name = alias; changed = true end
    entry.obj = obj
    entry.last_seen = now_time()
    entry.id = sanitize_id(key)
    if entry.id ~= "" then
        REGISTRY.by_id[entry.id] = entry
    end

    local loc = get_actor_location(obj)
    if update_location(entry, loc) then
        changed = true
    end

    if changed then
        REGISTRY.dirty = true
    end
    return changed
end

function Registry.untrack(obj)
    if not obj then return false end
    local key = object_key(obj)
    if not key or key == "" then return false end
    local changed = false
    for tag, reg in pairs(REGISTRY.by_tag) do
        local entry = reg[key]
        if entry ~= nil then
            reg[key] = nil
            if entry.id and REGISTRY.by_id[entry.id] == entry then
                REGISTRY.by_id[entry.id] = nil
            end
            changed = true
        end
    end
    if changed then
        REGISTRY.dirty = true
    end
    return changed
end

function Registry.refresh_positions()
    local changed = false
    for _, reg in pairs(REGISTRY.by_tag) do
        for key, entry in pairs(reg) do
            local obj = entry.obj
            if not is_valid(obj) or not is_world_actor(obj) then
                reg[key] = nil
                if entry.id and REGISTRY.by_id[entry.id] == entry then
                    REGISTRY.by_id[entry.id] = nil
                end
                changed = true
            else
                local loc = get_actor_location(obj)
                if update_location(entry, loc) then
                    changed = true
                end
            end
        end
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

function Registry.full_rescan()
    local seen = {}
    for _, rule in ipairs(REGISTRY.rules) do
        local list = find_all(rule.short) or {}
        for _, obj in ipairs(list) do
            if is_valid(obj) and is_world_actor(obj) then
                local key = object_key(obj)
                if key then seen[key] = true end
                Registry.track(obj)
            end
        end
    end
    for _, reg in pairs(REGISTRY.by_tag) do
        for key, entry in pairs(reg) do
            if not seen[key] then
                reg[key] = nil
                if entry and entry.id and REGISTRY.by_id[entry.id] == entry then
                    REGISTRY.by_id[entry.id] = nil
                end
                REGISTRY.dirty = true
            end
        end
    end
    return true
end

function Registry.initial_scan()
    if REGISTRY.initial_scan_done then return end
    REGISTRY.initial_scan_done = true
    Registry.full_rescan()
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
    local norm = sanitize_id(id)
    return REGISTRY.by_id[norm] or REGISTRY.by_id[id]
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
    local pawn = (TP and TP.get_local_pawn and TP.get_local_pawn()) or nil
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
    Registry.initial_scan()
    if update_self_position() then
        REGISTRY.dirty = true
    end
    if RESCAN_INTERVAL > 0 and (now - REGISTRY.last_rescan) > RESCAN_INTERVAL then
        REGISTRY.last_rescan = now
        Registry.full_rescan()
    end
    Registry.prune(now)
    return Registry.consume_payload(force_emit or REGISTRY.force_emit)
end

return Registry
