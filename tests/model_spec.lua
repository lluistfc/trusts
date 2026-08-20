package.path = package.path .. ';../?.lua;../?/init.lua';

local evaluator = require('model.evaluator');
local optimizer = require('model.optimizer');

local function member(id, name, role, coverage, weapon_skills, behavior)
    return {
        id = id, name = name, role = role, coverage = coverage or {},
        weapon_skills = weapon_skills or {}, behavior = behavior or {},
        direct_ws_elements = {}, skillchain_properties = {}, confidence = 'documented',
    };
end

local tank = member(1, 'Tank', 'tank', { enmity = 0.9, mitigation = 0.9, physical_offense = 0.3 });
local healer = member(2, 'Healer', 'healer', { sustained_healing = 0.9, emergency_healing = 0.9, status_removal = 0.8 });
local closer = member(3, 'Closer', 'melee', { physical_offense = 0.9 }, {
    { name = 'Closing WS', properties = { 'Fusion' }, policy = 'closer', reliability = 0.9 },
});
local support = member(4, 'Support', 'support', { support = 0.9 }, {}, { physical_support = true });

local context = {
    situation = 'General Physical', player_properties = { Distortion = true },
    player_sc_policy = 'Trust Closes', requirements = { enmity = 0.65, healing = 0.65 },
};

local evaluated = evaluator.evaluate_team({ tank, healer, closer }, context);
assert(evaluated.eligible, 'complete coverage team should be eligible');
assert(evaluated.primary_sc_plan ~= nil, 'directed player-to-Trust SC plan should exist');
assert(evaluated.primary_sc_plan.direction == 'Player -> Closer', 'SC direction policy should be honored');

local incomplete = evaluator.evaluate_team({ closer, support }, context);
assert(not incomplete.eligible, 'hard survival requirements should reject incomplete teams');

local best = optimizer.optimize({ tank, healer, closer, support }, context, {
    max_trusts = 3, beam_width = 32, role_counts = { tank = 1, healer = 1 },
});
assert(best ~= nil and best.evaluation.eligible, 'optimizer should find an eligible deterministic team');
assert(#best.team == 3, 'optimizer should respect party size');

print('trusts model fixtures: ok');
