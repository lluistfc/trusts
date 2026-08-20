local graph = require('model.skillchain_graph');

local compiler = {};
compiler.version = 1;

local function set_add(set, value)
    if (value ~= nil and value ~= '') then set[value] = true; end
end

local function normalize_role(role)
    role = tostring(role or 'special'):lower();
    if (role == 'chain') then return 'melee'; end
    if (role == 'nuker') then return 'caster'; end
    if (role == 'utility') then return 'special'; end
    return role;
end

function compiler.compile(trust, profile, behavior, ws_by_name)
    behavior = behavior or {};
    local result = {
        id = trust.id,
        name = trust.name,
        role = normalize_role(profile and profile.role),
        profile = profile,
        behavior = behavior,
        direct_ws_elements = {},
        skillchain_properties = {},
        weapon_skills = {},
        coverage = {
            enmity = 0, mitigation = 0, sustained_healing = 0, emergency_healing = 0,
            aoe_healing = 0, status_removal = 0, physical_offense = 0,
            ranged_offense = 0, magical_offense = 0, support = 0,
            dispel = 0, interrupt = 0, positioning_safety = 0,
        },
        confidence = behavior.confidence or (next(behavior) and 'observed' or 'unknown'),
    };

    local coverage = result.coverage;
    if (result.role == 'tank') then coverage.enmity = 0.80; coverage.mitigation = 0.75; end
    if (result.role == 'healer') then coverage.sustained_healing = 0.80; coverage.emergency_healing = 0.70; coverage.status_removal = 0.50; end
    if (result.role == 'support') then coverage.support = 0.70; end
    if (result.role == 'melee') then coverage.physical_offense = 0.65; end
    if (result.role == 'ranged') then coverage.ranged_offense = 0.70; coverage.positioning_safety = 0.55; end
    if (result.role == 'caster') then coverage.magical_offense = 0.70; coverage.positioning_safety = 0.45; end

    if (behavior.tank) then coverage.enmity = math.max(coverage.enmity, 0.90); coverage.mitigation = math.max(coverage.mitigation, 0.85); end
    if (behavior.healer) then coverage.sustained_healing = math.max(coverage.sustained_healing, 0.90); coverage.emergency_healing = math.max(coverage.emergency_healing, 0.85); end
    if (behavior.aoe_healing) then coverage.aoe_healing = 0.85; end
    if (behavior.status_removal) then coverage.status_removal = 0.85; end
    if (behavior.physical) then coverage.physical_offense = math.max(coverage.physical_offense, math.min(1, behavior.physical / 40)); end
    if (behavior.magic) then coverage.magical_offense = math.max(coverage.magical_offense, math.min(1, behavior.magic / 40)); end
    if (behavior.ranged) then coverage.positioning_safety = math.max(coverage.positioning_safety, 0.65); end
    if (behavior.support or behavior.physical_support or behavior.haste_support or behavior.refresh_support) then coverage.support = math.max(coverage.support, 0.80); end
    if (behavior.dispel) then coverage.dispel = 0.90; end
    if (behavior.interrupt) then coverage.interrupt = 0.90; end

    for _, action in ipairs(profile and profile.actions or {}) do
        if (rawget(action, 'kind') == 'Weapon Skill') then
            local properties = rawget(action, 'skillchains');
            if (properties == nil or #properties == 0) then
                properties = ws_by_name[(rawget(action, 'name') or ''):lower()];
            end
            local ordered = {};
            for _, property in ipairs(properties or {}) do
                property = graph.canonical(property);
                table.insert(ordered, property);
                set_add(result.skillchain_properties, property);
            end

            local damage_type = tostring(rawget(action, 'damage_type') or ''):lower();
            local description = tostring(rawget(action, 'description') or ''):lower();
            local elemental = damage_type == 'magical' or damage_type == 'hybrid'
                or description:find('elemental damage', 1, true) ~= nil;
            local damage_element = elemental and rawget(action, 'element') or nil;
            if (damage_element ~= nil and damage_element ~= 'Question') then
                for value in damage_element:gmatch('[^/%s,]+') do
                    set_add(result.direct_ws_elements, value);
                end
            end

            table.insert(result.weapon_skills, {
                name = rawget(action, 'name') or 'Unknown',
                properties = ordered,
                damage_type = rawget(action, 'damage_type'),
                damage_element = damage_element,
                range = rawget(action, 'range'),
                aoe = tostring(rawget(action, 'range') or ''):lower():find('aoe', 1, true) ~= nil,
                policy = behavior.sc_policy or 'unknown',
                reliability = behavior.sc_reliability,
                confidence = behavior.confidence or 'unknown',
            });
        end
    end
    return result;
end

function compiler.compile_roster(trusts, data, ws_by_name)
    local result = {};
    for _, trust in ipairs(trusts or {}) do
        local profile = data.find(trust.name);
        local behavior = data.behavior(trust.name);
        table.insert(result, compiler.compile(trust, profile, behavior, ws_by_name));
    end
    table.sort(result, function(a, b) return a.name:lower() < b.name:lower(); end);
    return result;
end

return compiler;
