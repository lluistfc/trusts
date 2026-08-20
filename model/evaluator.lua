local graph = require('model.skillchain_graph');
local presets = require('model.presets');

local evaluator = {};
evaluator.version = 1;

local function sorted_members(team)
    local result = {};
    for _, member in ipairs(team or {}) do table.insert(result, member); end
    table.sort(result, function(a, b)
        if ((a.id or 0) ~= (b.id or 0)) then return (a.id or 0) < (b.id or 0); end
        return tostring(a.name) < tostring(b.name);
    end);
    return result;
end

local function add_ledger(result, id, category, delta, members, confidence, explanation)
    table.insert(result.ledger, {
        id = id, category = category, delta = delta, members = members or {},
        confidence = confidence or 'estimated', explanation = explanation,
    });
    result.categories[category] = (result.categories[category] or 0) + delta;
end

local function maximum_coverage(team, key)
    local value = 0;
    for _, member in ipairs(team) do value = math.max(value, member.coverage[key] or 0); end
    return value;
end

local function sum_capped(team, key, cap)
    local value = 0;
    for _, member in ipairs(team) do value = value + (member.coverage[key] or 0); end
    return math.min(cap or 1, value);
end

local function selected_count(values)
    local count = 0;
    for _, selected in pairs(values or {}) do if (selected) then count = count + 1; end end
    return count;
end

local function path_candidates(team, context)
    local paths = {};
    local player_properties = context.player_properties or {};
    for _, member in ipairs(team) do
        for _, ws in ipairs(member.weapon_skills or {}) do
            for _, trust_property in ipairs(ws.properties or {}) do
                for player_property in pairs(player_properties) do
                    local directions = {
                        { opening = player_property, closing = trust_property, direction = 'Player -> ' .. member.name },
                        { opening = trust_property, closing = player_property, direction = member.name .. ' -> Player' },
                    };
                    for _, direction in ipairs(directions) do
                        local allowed = context.player_sc_policy == nil or context.player_sc_policy == 'Either'
                            or (context.player_sc_policy == 'Trust Closes' and direction.direction:find('Player %-%>') == 1)
                            or (context.player_sc_policy == 'Trust Opens' and direction.direction:find('%-%> Player') ~= nil);
                        local result = allowed and graph.result(direction.opening, direction.closing) or nil;
                        if (result ~= nil) then
                            local policy = ws.policy or 'unknown';
                            local reliability = 0.35;
                            if (policy == 'closer' and direction.direction:find('Player %-%>') == 1) then reliability = 0.85; end
                            if (policy == 'opener' and direction.direction:find('%-%> Player') ~= nil) then reliability = 0.80; end
                            if (policy == 'free') then reliability = 0.45; end
                            local desired = selected_count(context.sc_result_elements);
                            local element_match = desired == 0;
                            for element, selected in pairs(context.sc_result_elements or {}) do
                                if (selected and graph.result_has_element(result, element)) then element_match = true; end
                            end
                            local value = (graph.level[result] or 1) * 20 * reliability * (element_match and 1 or 0.45);
                            table.insert(paths, {
                                member = member, ws = ws.name, result = result, direction = direction.direction,
                                reliability = reliability, value = value,
                            });
                        end
                    end
                end
            end
        end
    end
    for left_index, left in ipairs(team) do
        for right_index, right in ipairs(team) do
            if (left_index ~= right_index) then
                for _, left_ws in ipairs(left.weapon_skills or {}) do
                    for _, right_ws in ipairs(right.weapon_skills or {}) do
                        for _, opening in ipairs(left_ws.properties or {}) do
                            for _, closing in ipairs(right_ws.properties or {}) do
                                local result = graph.result(opening, closing);
                                if (result ~= nil) then
                                    local reliability = math.min(left_ws.reliability or 0.35, right_ws.reliability or 0.35);
                                    local desired, element_match = selected_count(context.sc_result_elements), false;
                                    for element, selected in pairs(context.sc_result_elements or {}) do
                                        if (selected and graph.result_has_element(result, element)) then element_match = true; end
                                    end
                                    if (desired == 0) then element_match = true; end
                                    table.insert(paths, {
                                        member = right, ws = right_ws.name, result = result,
                                        direction = left.name .. ' -> ' .. right.name,
                                        reliability = reliability,
                                        value = (graph.level[result] or 1) * 16 * reliability * (element_match and 1 or 0.45),
                                    });
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(paths, function(a, b)
        if (a.value ~= b.value) then return a.value > b.value; end
        return (a.direction .. a.ws) < (b.direction .. b.ws);
    end);
    return paths;
end

function evaluator.evaluate_team(team, context)
    team = sorted_members(team);
    context = context or {};
    local result = {
        eligible = true, unmet_requirements = {}, total = 0, band = 'poor',
        categories = { survival = 0, offense = 0, support = 0, skillchain = 0, safety = 0 },
        ledger = {}, warnings = {}, confidence = { documented = 0, unknown = 0 },
        primary_sc_plan = nil, fallback_sc_plan = nil,
    };

    for _, member in ipairs(team) do
        if (member.confidence == 'unknown') then result.confidence.unknown = result.confidence.unknown + 1;
        else result.confidence.documented = result.confidence.documented + 1; end
    end
    if (result.confidence.unknown > 0) then
        table.insert(result.warnings, ('%u member(s) have incomplete behavior data.'):format(result.confidence.unknown));
    end

    local enmity = maximum_coverage(team, 'enmity');
    local mitigation = maximum_coverage(team, 'mitigation');
    local healing = maximum_coverage(team, 'sustained_healing');
    local emergency = maximum_coverage(team, 'emergency_healing');
    local aoe_healing = maximum_coverage(team, 'aoe_healing');
    local status_removal = maximum_coverage(team, 'status_removal');
    local physical = sum_capped(team, 'physical_offense', 2.5) / 2.5;
    local ranged = sum_capped(team, 'ranged_offense', 1.5) / 1.5;
    local magic = sum_capped(team, 'magical_offense', 1.5) / 1.5;
    local support = sum_capped(team, 'support', 1.5) / 1.5;
    local positioning = sum_capped(team, 'positioning_safety', #team > 0 and #team or 1) / math.max(1, #team);

    add_ledger(result, 'coverage.tank', 'survival', 45 * ((enmity + mitigation) / 2), {}, 'estimated', 'Tank control and mitigation coverage.');
    add_ledger(result, 'coverage.healing', 'survival', 45 * ((healing + emergency) / 2), {}, 'estimated', 'Sustained and emergency healing coverage.');
    add_ledger(result, 'coverage.aoe_status', 'survival', 10 * ((aoe_healing + status_removal) / 2), {}, 'estimated', 'AoE recovery and status-removal coverage.');
    if (context.enemy_count == 'Many') then
        add_ledger(result, 'context.many_enemies', 'survival', 18 * aoe_healing, {}, 'estimated', 'AoE recovery is more valuable against many enemies.');
    elseif (context.enemy_count == 'Few') then
        add_ledger(result, 'context.few_enemies', 'survival', 8 * aoe_healing, {}, 'estimated', 'AoE recovery helps against several enemies.');
    end
    add_ledger(result, 'offense.mix', 'offense', 100 * math.min(1, physical * 0.55 + ranged * 0.25 + magic * 0.20), {}, 'estimated', 'Combined physical, ranged, and magical pressure.');
    add_ledger(result, 'support.coverage', 'support', 100 * support, {}, 'estimated', 'Capped party support coverage.');
    add_ledger(result, 'safety.positioning', 'safety', 100 * positioning, {}, 'estimated', 'Ranged positioning and exposure profile.');

    local direct_selected = selected_count(context.ws_damage_elements);
    local property_selected = selected_count(context.preferred_skillchains);
    for _, member in ipairs(team) do
        local direct_matches, property_matches = 0, 0;
        for element, selected in pairs(context.ws_damage_elements or {}) do
            if (selected and member.direct_ws_elements[element]) then direct_matches = direct_matches + 1; end
        end
        for property, selected in pairs(context.preferred_skillchains or {}) do
            if (selected and member.skillchain_properties[property]) then property_matches = property_matches + 1; end
        end
        if (direct_matches > 0) then
            add_ledger(result, 'preference.direct.' .. tostring(member.id), 'offense', 18 * direct_matches / math.max(1, direct_selected),
                { member.id }, member.confidence, member.name .. ' matches selected direct WS elements.');
        end
        if (property_matches > 0) then
            add_ledger(result, 'preference.property.' .. tostring(member.id), 'skillchain', 18 * property_matches / math.max(1, property_selected),
                { member.id }, member.confidence, member.name .. ' has selected skillchain properties.');
        end
    end

    local has_healer = healing >= 0.65;
    local physical_members = 0;
    local autonomous_closers = 0;
    for _, member in ipairs(team) do
        if ((member.coverage.physical_offense or 0) >= 0.40 or (member.coverage.ranged_offense or 0) >= 0.40) then
            physical_members = physical_members + 1;
        end
        if (member.behavior.sc_policy == 'closer' and (member.behavior.sc_reliability or 0) >= 0.75) then
            autonomous_closers = autonomous_closers + 1;
        end
        if (member.behavior.requires_healer) then
            add_ledger(result, 'dependency.healer.' .. tostring(member.id or member.name), 'support', has_healer and 8 or -20,
                { member.id }, member.confidence, has_healer and (member.name .. ' has adequate healer support.') or (member.name .. ' lacks adequate healer support.'));
        end
        if ((context.situation == 'Avoid AoE' or context.aoe_tolerance == 'Low') and member.behavior.aoe_risk) then
            add_ledger(result, 'risk.aoe.' .. tostring(member.id or member.name), 'safety', -22, { member.id }, member.confidence, member.name .. ' has autonomous AoE risk.');
        end
    end
    if (autonomous_closers > 1) then
        add_ledger(result, 'skillchain.closer_collision', 'skillchain', -10 * (autonomous_closers - 1), {}, 'observed',
            'Multiple autonomous closers may compete for the same skillchain window.');
    end
    for _, member in ipairs(team) do
        if (member.behavior.physical_support) then
            add_ledger(result, 'synergy.physical_support.' .. tostring(member.id or member.name), 'support', math.min(18, physical_members * 4.5),
                { member.id }, member.confidence, member.name .. ' amplifies physical party members.');
        end
    end

    local paths = path_candidates(team, context);
    result.primary_sc_plan = paths[1];
    result.fallback_sc_plan = paths[2];
    if (paths[1] ~= nil) then
        add_ledger(result, 'skillchain.primary', 'skillchain', math.min(75, paths[1].value), { paths[1].member.id }, paths[1].member.confidence,
            ('%s using %s creates %s.'):format(paths[1].direction, paths[1].ws, paths[1].result));
    end
    if (paths[2] ~= nil) then
        add_ledger(result, 'skillchain.fallback', 'skillchain', math.min(25, paths[2].value * 0.30), { paths[2].member.id }, paths[2].member.confidence,
            ('Fallback: %s using %s creates %s.'):format(paths[2].direction, paths[2].ws, paths[2].result));
    end

    local requirements = context.requirements or {};
    local requirement_values = {
        enmity = enmity, healing = healing, support = support,
        status_removal = status_removal, aoe_healing = aoe_healing,
        dispel = maximum_coverage(team, 'dispel'),
    };
    for key, threshold in pairs(requirements) do
        if ((requirement_values[key] or 0) < threshold) then
            result.eligible = false;
            table.insert(result.unmet_requirements, key);
        end
    end

    local preset = presets[context.situation] or presets['General Physical'];
    for category, weight in pairs(preset.weights) do
        result.total = result.total + math.max(0, math.min(100, result.categories[category] or 0)) * weight;
    end
    if (not result.eligible) then result.total = result.total - 100; end
    if (result.total >= 82) then result.band = 'excellent';
    elseif (result.total >= 65) then result.band = 'good';
    elseif (result.total >= 45) then result.band = 'viable'; end
    return result;
end

return evaluator;
