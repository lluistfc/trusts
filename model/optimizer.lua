local evaluator = require('model.evaluator');

local optimizer = {};
optimizer.version = 2;

local function team_key(team)
    local ids = {};
    for _, member in ipairs(team) do table.insert(ids, tostring(member.id or member.name)); end
    table.sort(ids);
    return table.concat(ids, ':');
end

local function copy_and_add(team, member)
    local result = {};
    for _, value in ipairs(team) do table.insert(result, value); end
    table.insert(result, member);
    return result;
end

local function role_count(team, role)
    local count = 0;
    for _, member in ipairs(team) do if (member.role == role) then count = count + 1; end end
    return count;
end

local function quotas_possible(team, remaining, quotas)
    local missing = 0;
    for role, wanted in pairs(quotas or {}) do
        missing = missing + math.max(0, (tonumber(wanted) or 0) - role_count(team, role));
    end
    return missing <= remaining;
end

local function quotas_met(team, quotas)
    return quotas_possible(team, 0, quotas);
end

local function better(a, b)
    if (b == nil) then return true; end
    if (a.evaluation.eligible ~= b.evaluation.eligible) then return a.evaluation.eligible; end
    if (a.evaluation.total ~= b.evaluation.total) then return a.evaluation.total > b.evaluation.total; end
    return a.key < b.key;
end

local function prune_roster(roster, context, limit_per_role, overall_limit)
    if (#roster <= 24) then return roster; end
    local scored = {};
    for _, member in ipairs(roster) do
        local relaxed = {};
        for key, value in pairs(context or {}) do relaxed[key] = value; end
        relaxed.requirements = {};
        table.insert(scored, { member = member, evaluation = evaluator.evaluate_team({ member }, relaxed), key = tostring(member.id or member.name) });
    end
    table.sort(scored, better);
    local selected, result, role_counts = {}, {}, {};
    local function add(entry)
        local identity = entry.member.id or entry.member.name;
        if (not selected[identity]) then selected[identity] = true; table.insert(result, entry.member); end
    end
    for index = 1, math.min(overall_limit or 18, #scored) do add(scored[index]); end
    -- Preserve the best specialist in every functional dimension. Singleton score
    -- alone undervalues members whose capability completes a whole-team strategy.
    local dimensions = {
        'enmity', 'mitigation', 'sustained_healing', 'emergency_healing', 'aoe_healing',
        'status_removal', 'physical_offense', 'ranged_offense', 'magical_offense',
        'attack_support', 'accuracy_support', 'haste_support', 'refresh_support',
        'mp_sustain', 'magic_burst', 'status_resilience', 'aoe_offense', 'dispel', 'interrupt',
    };
    for _, dimension in ipairs(dimensions) do
        local best_member, best_value = nil, 0;
        for _, member in ipairs(roster) do
            local value = (member.coverage and member.coverage[dimension]) or 0;
            if (value > best_value) then best_member, best_value = member, value; end
        end
        if (best_member ~= nil) then add({ member = best_member }); end
    end
    for _, entry in ipairs(scored) do
        local role = entry.member.role or 'special';
        role_counts[role] = role_counts[role] or 0;
        if (role_counts[role] < (limit_per_role or 7)) then add(entry); role_counts[role] = role_counts[role] + 1; end
    end
    table.sort(result, function(a, b) return tostring(a.id or a.name) < tostring(b.id or b.name); end);
    return result;
end

function optimizer.optimize(roster, context, options)
    options = options or {};
    local size = math.max(1, math.min(5, tonumber(options.max_trusts) or 3));
    local width = math.max(24, tonumber(options.beam_width) or 120);
    roster = prune_roster(roster or {}, context, options.per_role_limit, options.candidate_limit);
    local beam = { { team = {}, evaluation = evaluator.evaluate_team({}, context), key = '' } };

    for depth = 1, size do
        local expanded, seen = {}, {};
        for _, node in ipairs(beam) do
            local present = {};
            for _, member in ipairs(node.team) do present[member.id or member.name] = true; end
            for _, member in ipairs(roster or {}) do
                local identity = member.id or member.name;
                if (not present[identity]) then
                    local team = copy_and_add(node.team, member);
                    if (quotas_possible(team, size - depth, options.role_counts)) then
                        local key = team_key(team);
                        if (not seen[key]) then
                            seen[key] = true;
                            table.insert(expanded, {
                                team = team,
                                evaluation = evaluator.evaluate_team(team, context),
                                key = key,
                            });
                        end
                    end
                end
            end
        end
        table.sort(expanded, better);
        beam = {};
        for index = 1, math.min(width, #expanded) do table.insert(beam, expanded[index]); end
        if (#beam == 0) then break; end
    end

    local ranked = {};
    for _, node in ipairs(beam) do
        if (#node.team == size and quotas_met(node.team, options.role_counts)) then table.insert(ranked, node); end
    end
    table.sort(ranked, better);
    return ranked[1], ranked;
end

return optimizer;
