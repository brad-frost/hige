module('hige', package.seeall)

local tags = { open = '{{', close = '}}' }

local function merge_environment(...)
    local numargs, out = select('#', ...), {}
    for i = 1, numargs do
        local t = select(i, ...)
        if type(t) == 'table' then
            for k, v in pairs(t) do 
                if (type(v) == 'function') then
                    out[k] = setfenv(v, setmetatable(out, { 
                        __index = getmetatable(getfenv()).__index 
                    }))
                else
                    out[k] = v 
                end
            end
        end
    end
    return out
end

local function escape(str)
    return str:gsub('[&"<>\]', function(c) 
        if c == '&' then return '&amp;'
        elseif c == '"' then return '\"'
        elseif c == '\\' then return '\\\\'
        elseif c == '<' then return '&lt;'
        elseif c == '>' then return '&gt;'
        else return c end
    end)
end

local function find(name, context)
    local value = context[name]
    if value == nil then 
        return ''
    elseif type(value) == 'function' then 
        return merge_environment(context, value)[name]()
    else 
        return value
    end
end

local function render_partial(state, name, context)
    local target_mt   = setmetatable(context, { __index = state.lookup_env })
    local target_name = setfenv(loadstring('return ' .. name), target_mt)()
    local target_type = type(target_name)

    if target_type == 'string' then
        return perform_render(state, target_name, context)
    elseif target_type == 'table' then
        local target_template = setfenv(loadstring('return '..name..'_template'), target_mt)()
        return perform_render(state, target_template, merge_environment(target_name, context))
    else
        error('unknown partial type "' .. tostring(name) .. '"')
    end
end

local operators = {
    -- comments 
    ['!'] = function(state, op, name, context) 
        return state.tag_open .. op .. name .. state.tag_close
    end, 
    -- the triple hige is unescaped
    ['{'] = function(state, op, name, context) 
        return find(name, context) 
    end, 
    -- render partial
    ['<'] = function(state, op, name, context) 
        return render_partial(state, name, context)
    end, 
    -- set new delimiters
    ['='] = function(state, op, name, context)
        -- FIXME!
        error('setting new delimiters in the template is currently broken')
        --[[
        return name:gsub('^(.-)%s+(.-)$', function(open, close)
            state.tag_open, state.tag_close = open, close
            return ''
        end)
        ]]
    end, 
}

local function render_tags(state, template, context)
    return template:gsub(state.tag_open..'([=!<{]?)%s*([^#/]-)%s*[=}]?%s*'..state.tag_close, function(op, name)
        if operators[op] ~= nil then
            return tostring(operators[op](state, op, name, context))
        else
            return escape(tostring((function() 
                if name ~= '.' then return find(name, context) else return context end
            end)()))
        end
    end)
end

local function render_section(state, template, context)
    for section_name in template:gmatch(state.tag_open..'#%s*([^#/]-)%s*'..state.tag_close) do 
        local found, value = context[section_name] ~= nil, find(section_name, context)
        local section_path = '('..state.tag_open..'#'..section_name..state.tag_close..'%s*(.*)'..state.tag_open..'/'..section_name..state.tag_close..')%s*'

        template = template:gsub(section_path, function(outer, inner)
            if found == false then return '' end

            if value == true then 
                return perform_render(state, inner, context)
            elseif type(value) == 'table' then 
                local output = {}
                for _, row in pairs(value) do 
                    if type(row) == 'table' then 
                        table.insert(output, (perform_render(state, inner, merge_environment(context, row))))
                    else
                        table.insert(output, (perform_render(state, inner, row)))
                    end
                end
                return table.concat(output)
            else 
                return ''
            end
        end)
    end

    return template
end

function perform_render(state, template, context)
    return render_tags(state, render_section(state, template, context), context)
end

function render(template, context, env)
    if template:find(tags.open) == nil then return template end

    local state = {
        lookup_env = env or _G, 
        tag_open   = tags.open, 
        tag_close  = tags.close, 
    }
    return perform_render(state, template, context or {})
end

