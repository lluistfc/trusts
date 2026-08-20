-- Curated Trust AI and performance metadata that cannot be inferred from action lists.
-- Scores are comparative signals for party construction, not damage-parser estimates.
return T{
    ['Valaineral'] = T{ base = 92, leveling = 25, physical = 10, survival = 18, multi_target = 22, aoe_risk = true, sc_policy = 'opener', sc_reliability = 0.70, tank = true },
    ['Ark Angel EV'] = T{ base = 94, boss = 24, survival = 30, aoe_safe = true, sc_policy = 'conservative', sc_reliability = 0.45, tank = true, interrupt = true },
    ['August'] = T{ base = 93, boss = 25, survival = 28, physical = 8, tank = true },
    ['Amchuchu'] = T{ base = 91, boss = 22, magic = 18, survival = 24, tank = true, sc_policy = 'closer', sc_reliability = 0.55 },

    ['Zeid II'] = T{ base = 98, leveling = 14, boss = 20, physical = 28, skillchain = 38, sc_policy = 'closer', sc_reliability = 1.00, requires_healer = true, interrupt = true, dispel = true },
    ['Semih Lafihna'] = T{ base = 100, leveling = 30, boss = 15, physical = 28, skillchain = 40, sc_policy = 'closer', sc_reliability = 0.95, ranged = true, aoe_risk = true, defense_down = true, evasion_down = true },
    ['Ayame'] = T{ base = 88, skillchain = 45, sc_policy = 'opener', sc_reliability = 1.00, physical = 18 },
    ['Ayame (UC)'] = T{ base = 94, skillchain = 48, sc_policy = 'closer', sc_reliability = 1.00, physical = 20 },
    ['Shantotto II'] = T{ base = 96, leveling = 22, magic = 42, magic_burst = 35, ranged = true, aoe_safe = true },
    ['Domina Shantotto'] = T{ base = 86, magic = 30, magic_burst = 22, ranged = true },
    ['Morimar'] = T{ base = 82, physical = 20, skillchain = 20, sc_policy = 'free', sc_reliability = 0.55 },
    ['Lehko Habhoka'] = T{ base = 78, physical = 17, skillchain = 16, sc_policy = 'free', sc_reliability = 0.50 },

    ['Qultada'] = T{ base = 98, leveling = 28, physical = 38, support = 35, physical_support = 2.0, dispel = true, sc_policy = 'free', sc_reliability = 0.45 },
    ['Koru-Moru'] = T{ base = 94, boss = 18, physical = 20, magic = 18, support = 36, haste_support = true, refresh_support = true, dispel = true, ranged = true, aoe_safe = true },
    ['Ulmia'] = T{ base = 84, support = 30, physical = 18, magic = 14, haste_support = true, ranged = true, aoe_safe = true },
    ['Joachim'] = T{ base = 82, support = 28, physical = 16, haste_support = true, ranged = true, aoe_safe = true },
    ['King of Hearts'] = T{ base = 80, support = 26, magic = 16, haste_support = true, refresh_support = true, dispel = true },

    ['Apururu (UC)'] = T{ base = 100, leveling = 22, survival = 38, status_heavy = 28, healer = true, aoe_healing = true, status_removal = true, haste_support = true, ranged = true },
    ['Apururu'] = T{ base = 100, leveling = 22, survival = 38, status_heavy = 28, healer = true, aoe_healing = true, status_removal = true, haste_support = true, ranged = true },
    ['Yoran-Oran (UC)'] = T{ base = 94, boss = 22, survival = 34, healer = true, status_removal = true, mp_efficient = true, ranged = true, aoe_safe = true },
    ['Monberaux'] = T{ base = 102, boss = 30, survival = 42, status_heavy = 48, healer = true, status_removal = true, mp_efficient = true, silence_safe = true, paralyze_safe = true, ranged = true, aoe_safe = true },
    ['Ygnas'] = T{ base = 96, boss = 22, survival = 36, healer = true, aoe_healing = true, status_removal = true, ranged = true },
    ['Kupipi'] = T{ base = 72, leveling = 12, survival = 20, healer = true, status_removal = true, ranged = true },
    ['Cherukiki'] = T{ base = 80, boss = 12, survival = 25, healer = true, regen = true, ranged = true, aoe_safe = true },
    ['Selh\'teus'] = T{ base = 88, survival = 26, support = 16, aoe_healing = true, mp_support = true, skillchain = 15 },
};
