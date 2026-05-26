local function asString(value)
    if value == nil then
        return ""
    end

    return tostring(value)
end

function string:embodies(sub)
    sub = asString(sub)
    return self:find(sub, 1, true) ~= nil
end

function string:startsWith(start)
    start = asString(start)
    if start == "" then
        return true
    end

    return self:sub(1, start:len()) == start
end

function string:endsWith(ending)
    ending = asString(ending)
    if ending == "" then
        return true
    end

    return self:sub(-ending:len()) == ending
end

function string:replace(old, new)
    old = asString(old)
    new = asString(new)

    if old == "" then
        return self
    end

    local result = {}
    local cursor = 1

    while true do
        local first, last = self:find(old, cursor, true)
        if not first then
            result[#result + 1] = self:sub(cursor)
            break
        end

        result[#result + 1] = self:sub(cursor, first - 1)
        result[#result + 1] = new
        cursor = last + 1
    end

    return table.concat(result)
end

function string:insert(pos, text)
    pos = tonumber(pos) or 1
    text = asString(text)

    if pos < 1 then
        pos = 1
    end

    return self:sub(1, pos - 1) .. text .. self:sub(pos)
end

function string:hasword(needle)
    needle = asString(needle)
    if needle == "" then
        return false
    end

    local escaped = needle:gsub("([^%w])", "%%%1")
    local pattern = "%f[%w]" .. escaped .. "%f[%W]"
    return self:find(pattern) ~= nil
end
