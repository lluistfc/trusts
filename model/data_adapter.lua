local schema = require('model.schema');

local adapter = {};
adapter.version = 1;

local function copy_table(source)
    local result = {};
    for key, value in pairs(source or {}) do result[key] = value; end
    return result;
end

function adapter.build(profiles, supplements, behaviors, aliases)
    local by_name = {};
    local normalized = {};
    local diagnostics = { generated = 0, supplemental = 0, behavior = 0, invalid = 0 };

    local function add_profile(profile, supplemental)
        if (type(profile) ~= 'table' or type(profile.name) ~= 'string' or profile.name == '') then
            diagnostics.invalid = diagnostics.invalid + 1;
            return;
        end
        if (by_name[profile.name] == nil or not supplemental) then
            by_name[profile.name] = profile;
        end
        normalized[schema.normalize_name(profile.name)] = by_name[profile.name];
        if (supplemental) then diagnostics.supplemental = diagnostics.supplemental + 1;
        else diagnostics.generated = diagnostics.generated + 1; end
    end

    for _, profile in ipairs(profiles or {}) do add_profile(profile, false); end
    for _, profile in ipairs(supplements or {}) do
        if (by_name[profile.name] == nil) then add_profile(profile, true); end
    end

    for alias, canonical in pairs(aliases or {}) do
        if (by_name[canonical] ~= nil) then
            by_name[alias] = by_name[canonical];
            normalized[schema.normalize_name(alias)] = by_name[canonical];
        end
    end

    local behavior_normalized = {};
    for name, behavior in pairs(behaviors or {}) do
        local valid = schema.validate_behavior(behavior);
        if (valid) then
            behavior_normalized[schema.normalize_name(name)] = behavior;
            diagnostics.behavior = diagnostics.behavior + 1;
        else
            diagnostics.invalid = diagnostics.invalid + 1;
        end
    end

    local result = {
        version = adapter.version,
        by_name = by_name,
        normalized = normalized,
        behaviors = behavior_normalized,
        diagnostics = diagnostics,
    };

    function result.find(name)
        local key = schema.normalize_name(name);
        if (normalized[key] ~= nil) then return normalized[key]; end
        local matched = nil;
        for profile_name, profile in pairs(normalized) do
            if (profile_name:find(key, 1, true) == 1 or key:find(profile_name, 1, true) == 1) then
                if (matched ~= nil and matched ~= profile) then return nil; end
                matched = profile;
            end
        end
        return matched;
    end

    function result.behavior(name)
        return behavior_normalized[schema.normalize_name(name)];
    end

    return result;
end

return adapter;
