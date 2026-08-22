local script_path = arg and arg[0] or ''
local tests_directory = script_path:match '^(.*[\\/])' or ''
local addon_directory = tests_directory .. '..\\'
package.path = package.path .. ';' .. addon_directory .. '?.lua;' .. addon_directory .. '?\\init.lua'

local evaluator = require 'model.evaluator'
local optimizer = require 'model.optimizer'
local compiler = require 'model.capability_compiler'

local function member(id, name, role, coverage, weapon_skills, behavior)
    return {
        id = id,
        name = name,
        role = role,
        coverage = coverage or {},
        weapon_skills = weapon_skills or {},
        behavior = behavior or {},
        direct_ws_elements = {},
        skillchain_properties = {},
        confidence = 'documented',
    }
end

local tank = member(1, 'Tank', 'tank', { enmity = 0.9, mitigation = 0.9, physical_offense = 0.3 })
local healer = member(2, 'Healer', 'healer', { sustained_healing = 0.9, emergency_healing = 0.9, status_removal = 0.8 })
local closer = member(3, 'Closer', 'melee', { physical_offense = 0.9 }, {
    { name = 'Closing WS', properties = { 'Fusion' }, policy = 'closer', reliability = 0.9 },
})
local support = member(4, 'Support', 'support', { support = 0.9 }, {}, { physical_support = true })

local context = {
    situation = 'General Physical',
    player_properties = { Distortion = true },
    player_sc_policy = 'Trust Closes',
    requirements = { enmity = 0.65, healing = 0.65 },
}

local evaluated = evaluator.evaluate_team({ tank, healer, closer }, context)
assert(evaluated.eligible, 'complete coverage team should be eligible')
assert(evaluated.primary_sc_plan ~= nil, 'directed player-to-Trust SC plan should exist')
assert(evaluated.primary_sc_plan.direction == 'Player -> Closer', 'SC direction policy should be honored')

local incomplete = evaluator.evaluate_team({ closer, support }, context)
assert(not incomplete.eligible, 'hard survival requirements should reject incomplete teams')

local best = optimizer.optimize({ tank, healer, closer, support }, context, {
    max_trusts = 3,
    beam_width = 32,
    role_counts = { tank = 1, healer = 1 },
})
assert(best ~= nil and best.evaluation.eligible, 'optimizer should find an eligible deterministic team')
assert(#best.team == 3, 'optimizer should respect party size')

print 'trusts model fixtures: ok'

local burster = member(5, 'Burster', 'caster', {
    magical_offense = 1.0,
    magic_burst = 0.9,
    positioning_safety = 0.6,
}, {}, { ai_instruction = 'Wait for the burst window.' })
local burst_context = {
    situation = 'Magic Burst',
    player_properties = { Distortion = true },
    player_sc_policy = 'Trust Closes',
    requirements = {},
}
local with_burster = evaluator.evaluate_team({ closer, burster }, burst_context)
local without_burster = evaluator.evaluate_team({ closer, support }, burst_context)
assert(with_burster.categories.skillchain > without_burster.categories.skillchain,
    'an executable chain with a real magic burster should beat a theoretical chain alone')
assert(#with_burster.instructions >= 2, 'AI and skillchain operation instructions should be emitted')

local compiled_burster = compiler.compile({ id = 6, name = 'Compiled Burster' }, {
    role = 'caster',
    actions = {},
}, {
    magic = 42,
    magic_burst = 35,
    mp_efficient = true,
    haste_support = true,
    silence_safe = true,
}, {})
assert(compiled_burster.coverage.magic_burst > 0.8, 'magic burst behavior should compile to functional coverage')
assert(compiled_burster.coverage.mp_sustain >= 0.8, 'MP efficiency should compile to sustain coverage')
assert(compiled_burster.coverage.haste_support >= 0.8, 'typed Haste support should be preserved')
assert(compiled_burster.coverage.status_resilience >= 0.8, 'status-safe behavior should compile to resilience')

local large_roster = {}
for index = 1, 25 do
    table.insert(large_roster, member(100 + index, 'Generic ' .. index, 'melee', { physical_offense = 0.8 }))
end
local specialist = member(999, 'Only Dispel', 'special', { dispel = 0.9 })
table.insert(large_roster, specialist)
local specialist_best = optimizer.optimize(large_roster, {
    situation = 'General Physical',
    requirements = { dispel = 0.65 },
}, { max_trusts = 2, beam_width = 48 })
assert(specialist_best ~= nil and specialist_best.evaluation.eligible,
    'functional specialists must survive roster pruning when required by the encounter')

print 'trusts advanced model fixtures: ok'
