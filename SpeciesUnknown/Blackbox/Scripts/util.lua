-- util.lua - tiny helpers shared by modules

local Util = {}

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

function Util.safe_call(tag, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        Util.err(tag, res)
        return false, res
    end
    return true, res
end

return Util
