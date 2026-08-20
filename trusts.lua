--[[
* Addons - Copyright (c) 2025 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

addon.name      = 'trusts';
addon.author    = 'Codex';
addon.version   = '2.0.0';
addon.desc      = 'Exports trust and weapon skill lists, shows recommended trust combos, and can summon them.';
addon.link      = 'https://ashitaxi.com/';

require 'common';

local chat = require 'chat';
local imgui = require 'imgui';
local settings = require 'settings';
local ffi = require 'ffi';
local d3d8 = require 'd3d8';
local model_schema = require 'model.schema';
local skillchain_graph = require 'model.skillchain_graph';
local data_adapter = require 'model.data_adapter';
local capability_compiler = require 'model.capability_compiler';
local team_optimizer = require 'model.optimizer';

local coverage_icon_cache = T{};
local COVERAGE_ICON_SIZE = 22;

local function load_coverage_icon(kind, name)
    local key = kind .. ':' .. name;
    if (coverage_icon_cache[key] ~= nil) then
        return coverage_icon_cache[key] or nil;
    end

    local directory = kind == 'skillchain' and 'skillchain' or 'elements';
    local path = AshitaCore:GetInstallPath() .. 'addons\\XIUI\\assets\\hotbar\\' .. directory .. '\\' .. name .. '.png';
    local device = d3d8.get_device();
    if (device == nil or not ashita.fs.exists(path)) then
        coverage_icon_cache[key] = false;
        return nil;
    end

    local texturePointer = ffi.new('IDirect3DTexture8*[1]');
    local result = ffi.C.D3DXCreateTextureFromFileExA(
        device, path,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
        1, 1, 0, nil, nil, texturePointer
    );
    if (result ~= ffi.C.S_OK or texturePointer[0] == nil) then
        coverage_icon_cache[key] = false;
        return nil;
    end

    local texture = ffi.new('IDirect3DTexture8*', texturePointer[0]);
    d3d8.gc_safe_release(texture);
    coverage_icon_cache[key] = texture;
    return texture;
end

local default_settings = T{
    settings_version = 3,
    coverage_overlay = T{
        visible = true,
    },
    team_builder = T{
        max_trusts = 3,
        situation = 'General Physical',
        preferred_ws = 'Auto',
        player_sc_policy = 'Either',
        player_role = 'Auto',
        enemy_count = 'Single',
        aoe_tolerance = 'Normal',
        require_status_removal = false,
        require_dispel = false,
        role_counts = T{
            tank = 1,
            healer = 1,
            support = 1,
            melee = 0,
            ranged = 0,
            caster = 0,
            special = 0,
        },
        ws_damage_elements = T{},
        sc_result_elements = T{},
        skillchains = T{},
    },
};

local state = T{
    character_loaded = false,
    refresh_scheduled = false,
    last_output = nil,
    ui_visible = true,
    recommendation = nil,
    recommendation_input_key = nil,
    builder_cache = nil,
    coverage_entries = T{},
    coverage_roster_key = nil,
    migration_notice = nil,
    settings = settings.load(default_settings),
    reset_coverage_position = false,
    trust_filters = T{
        action_kind = 'All',
        damage = 'All',
        element = 'All',
    },
};

local ui_style = T{
    window_bg = {0.067, 0.063, 0.055, 0.95},
    title_bg = {0.098, 0.090, 0.075, 1.0},
    title_bg_active = {0.137, 0.125, 0.106, 1.0},
    border = {0.3, 0.28, 0.24, 0.8},
    button = {0.098, 0.090, 0.075, 1.0},
    button_hovered = {0.137, 0.125, 0.106, 1.0},
    button_active = {0.176, 0.161, 0.137, 1.0},
    text = {0.9, 0.9, 0.9, 1.0},
    gold = {0.957, 0.855, 0.592, 1.0},
};

-- Trust spell ids currently shipped in this repo's resources.
local TRUST_MIN_ID = 896;
local TRUST_MAX_ID = 1019;
local WEAPON_SKILL_MIN_ID = 1;
local WEAPON_SKILL_MAX_ID = 1024;

local TRUST_PROFILE_DATA = require('data.trust_profiles');
local TRUST_PROFILE_SUPPLEMENTS = require('data.trust_profile_supplements');
local TRUST_BEHAVIOR_DATA = require('data.trust_behavior');

local function normalize_trust_name(name)
    return model_schema.normalize_name(name);
end

-- Retail spell resources abbreviate a few names that BG Wiki spells out.
local TRUST_PROFILE_ALIASES = T{
    ['Ark EV'] = 'Ark Angel EV',
    ['Ark GK'] = 'Ark Angel GK',
    ['Ark HM'] = 'Ark Angel HM',
    ['Ark MR'] = 'Ark Angel MR',
    ['Ark TT'] = 'Ark Angel TT',
    ['D. Shantotto'] = 'Domina Shantotto',
};
local CANONICAL_DATA = data_adapter.build(
    TRUST_PROFILE_DATA,
    TRUST_PROFILE_SUPPLEMENTS,
    TRUST_BEHAVIOR_DATA,
    TRUST_PROFILE_ALIASES
);

local function find_trust_profile(name)
    return CANONICAL_DATA.find(name);
end

local function load_skillchains_data()
    local path = AshitaCore:GetInstallPath() .. 'addons\\skillchains\\skills.lua';
    local chunk = loadfile(path);
    if (chunk == nil) then
        return nil;
    end

    local ok, result = pcall(chunk);
    return ok and result or nil;
end

local SKILLCHAINS_DATA = load_skillchains_data();
local SKILLCHAIN_WS_BY_NAME = T{};
if (SKILLCHAINS_DATA ~= nil and SKILLCHAINS_DATA.weapon_skills ~= nil) then
    for _, weaponSkill in pairs(SKILLCHAINS_DATA.weapon_skills) do
        if (weaponSkill.en ~= nil and weaponSkill.skillchain ~= nil) then
            SKILLCHAIN_WS_BY_NAME[weaponSkill.en:lower()] = weaponSkill.skillchain;
        end
    end
end

local function make_generic_trust_profile(trust)
    local role_name = 'utility';

    if (role_name == 'tank') then
        return T{
            damage = 'Physical',
            target = 'Mostly ST',
            skillchain = 'Usually a melee skillchain contributor',
            source = 'Role-based fallback; exact trust-page mapping not available in the Lua data table',
            lines = T{
                'Tank toolkit: enmity tools, mitigation, and defensive magic.',
                'Usually contributes a defensive weaponskill package and emergency cures or self-buffs.',
            },
        };
    end

    if (role_name == 'healer') then
        return T{
            damage = 'Magical / healing',
            target = 'ST + party support',
            skillchain = 'Usually not a chain driver',
            source = 'Role-based fallback; exact trust-page mapping not available in the Lua data table',
            lines = T{
                'Healer toolkit: Cure spells, status removal, Protect/Shell support, and emergency recovery.',
                'Usually leans on white magic first and may add a small MP recovery or support skill.',
            },
        };
    end

    if (role_name == 'support') then
        return T{
            damage = 'Magical / support',
            target = 'ST + party support',
            skillchain = 'Usually not a chain driver',
            source = 'Role-based fallback; exact trust-page mapping not available in the Lua data table',
            lines = T{
                'Support toolkit: buffs, refresh/haste, debuffs, and party utility.',
                'Usually favors keeping the party enhanced over spending time on melee damage.',
            },
        };
    end

    if (role_name == 'nuker') then
        return T{
            damage = 'Magical',
            target = 'ST / burst',
            skillchain = 'Usually not a chain driver unless the trust has a melee fallback',
            source = 'Role-based fallback; exact trust-page mapping not available in the Lua data table',
            lines = T{
                'Nuker toolkit: elemental magic and burst damage.',
                'Usually prefers casting over melee and may use a small set of weapon skills for emergencies.',
            },
        };
    end

    if (role_name == 'chain') then
        return T{
            damage = 'Physical',
            target = 'Melee / ST',
            skillchain = 'Usually a good SC partner',
            source = 'Role-based fallback; exact trust-page mapping not available in the Lua data table',
            lines = T{
                'Chain toolkit: melee pressure and skillchain-friendly weaponskills.',
                'Good for opening or closing skillchains and helping your party burst harder.',
            },
        };
    end

    return T{
        damage = 'Mixed',
        target = 'Varies',
        skillchain = 'Role-based estimate; exact trust-page mapping not available in current lookup',
        source = 'Role-based fallback; exact trust-page mapping not available in the Lua data table',
        lines = T{
            'Utility toolkit: a mixed set of melee, support, or magic actions depending on the fight.',
            'This entry uses a role-based summary until an exact trust-page mapping is added.',
        },
    };
end

local function get_trust_action_profile(trust)
    local profile = find_trust_profile(trust.name);
    if (profile ~= nil) then
        return profile;
    end

    return make_generic_trust_profile(trust);
end

local function get_trust_action_elements(trust)
    if (trust == nil) then
        return nil;
    end

    local entry = find_trust_profile(trust.name);
    if (entry ~= nil and entry.actions ~= nil) then
        return T{ source = entry.source, elements = entry.actions };
    end

    return nil;
end

local ELEMENT_ORDER = skillchain_graph.element_order;
local SKILLCHAIN_ORDER = skillchain_graph.property_order;
local SKILLCHAIN_ELEMENTS = skillchain_graph.elements;
local SKILLCHAIN_LEVEL = skillchain_graph.level;
local DIRECTED_SKILLCHAINS = skillchain_graph.combinations;
local canonical_skillchain_property = skillchain_graph.canonical;
local SPELL_ELEMENT_BY_PREFIX = T{
    fire = 'Fire', blizzard = 'Ice', aero = 'Wind', stone = 'Earth',
    thunder = 'Lightning', water = 'Water',
};

local function ordered_values(set, preferredOrder)
    local values = T{};
    for _, value in ipairs(preferredOrder or T{}) do
        if (set[value] == true) then
            values:append(value);
            set[value] = nil;
        end
    end
    for value in pairs(set) do
        values:append(value);
    end
    values:sort(function(a, b) return a:lower() < b:lower(); end);
    return values;
end

local function get_summoned_trusts()
    local results = T{};
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    local party = AshitaCore:GetMemoryManager():GetParty();
    local playerIndex = (party ~= nil and party:GetMemberTargetIndex(0)) or 0;
    if (entMgr == nil or party == nil or playerIndex == 0) then
        return results;
    end

    -- Trusts occupy local party slots, but their entity indices are not guaranteed
    -- to stay inside one fixed range. Reading party slots avoids silently missing one.
    for partyIndex = 1, 5 do
        local index = party:GetMemberTargetIndex(partyIndex) or 0;
        if (index ~= 0 and entMgr:GetTrustOwnerTargetIndex(index) == playerIndex) then
            local entity = GetEntity(index);
            local name = (entity ~= nil and entity.Name) or party:GetMemberName(partyIndex);
            if (name ~= nil and name ~= '') then
                results:append(T{ index = index, name = name });
            end
        end
    end

    results:sort(function(a, b) return a.name:lower() < b.name:lower(); end);
    return results;
end

local function build_trust_coverage_entries()
    local summoned = get_summoned_trusts();
    if (#summoned == 0) then
        state.coverage_entries = T{};
        state.coverage_roster_key = '';
        return T{};
    end

    local rosterParts = T{};
    for _, trust in ipairs(summoned) do rosterParts:append(('%u:%s'):fmt(trust.index or 0, normalize_trust_name(trust.name))); end
    local rosterKey = table.concat(rosterParts, '|');
    if (state.coverage_roster_key == rosterKey) then
        return state.coverage_entries;
    end

    local entries = T{};
    for _, trust in ipairs(summoned) do
        local profile = find_trust_profile(trust.name);
        local magicElements = T{};
        local wsElements = T{};
        local skillchainProperties = T{};

        for _, action in ipairs((profile ~= nil and rawget(profile, 'actions')) or T{}) do
            local kind = rawget(action, 'kind');
            local element = rawget(action, 'element');
            if (element ~= nil and element ~= '' and element ~= 'Question') then
                local destination = (kind == 'Spell') and magicElements or wsElements;
                for value in element:gmatch('[^/%s,]+') do
                    destination[value] = true;
                end
            end

            if (kind == 'Spell') then
                local actionName = (rawget(action, 'name') or ''):lower();
                if (actionName:find('elemental nuke', 1, true)) then
                    for _, value in ipairs(T{ 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water' }) do
                        magicElements[value] = true;
                    end
                else
                    for prefix, value in pairs(SPELL_ELEMENT_BY_PREFIX) do
                        if (actionName:find(prefix, 1, true) == 1) then
                            magicElements[value] = true;
                        end
                    end
                end
            end

            if (kind == 'Weapon Skill') then
                local properties = rawget(action, 'skillchains');
                if (properties == nil or #properties == 0) then
                    properties = SKILLCHAIN_WS_BY_NAME[(rawget(action, 'name') or ''):lower()];
                end
                for _, property in ipairs(properties or T{}) do
                    skillchainProperties[canonical_skillchain_property(property)] = true;
                end
            end
        end

        local magic = ordered_values(magicElements, ELEMENT_ORDER);
        local ws = ordered_values(wsElements, ELEMENT_ORDER);
        local skillchains = ordered_values(skillchainProperties, T{});
        if (#magic > 0 or #ws > 0 or #skillchains > 0) then
            entries:append(T{
                name = (profile ~= nil and rawget(profile, 'name')) or trust.name,
                magic = magic,
                ws = ws,
                skillchains = skillchains,
            });
        end
    end

    state.coverage_roster_key = rosterKey;
    state.coverage_entries = entries;
    return entries;
end

local function render_coverage_panel()
    if (not state.settings.coverage_overlay.visible) then
        return;
    end

    local entries = build_trust_coverage_entries();
    if (#entries == 0) then
        return;
    end

    imgui.SetNextWindowSize({ 0, 0 }, ImGuiCond_Always);
    if (state.reset_coverage_position) then
        imgui.SetNextWindowPos({ 560, 300 }, ImGuiCond_Always);
        state.reset_coverage_position = false;
    else
        imgui.SetNextWindowPos({ 560, 300 }, ImGuiCond_FirstUseEver);
    end
    local flags = bit.bor(
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_NoScrollWithMouse,
        ImGuiWindowFlags_NoCollapse
    );
    local visible = { state.settings.coverage_overlay.visible };
    if (imgui.Begin('Trust Element Coverage', visible, flags)) then
        local function draw_icon_row(label, values, kind)
            if (#values == 0) then
                return;
            end

            imgui.Text(label);
            imgui.SameLine();
            for index, value in ipairs(values) do
                local texture = load_coverage_icon(kind, value);
                if (texture ~= nil) then
                    local pointer = tonumber(ffi.cast('uint32_t', texture));
                    imgui.Image(pointer, { COVERAGE_ICON_SIZE, COVERAGE_ICON_SIZE });
                    if (imgui.IsItemHovered()) then
                        imgui.BeginTooltip();
                        imgui.Text(value);
                        imgui.EndTooltip();
                    end
                else
                    imgui.Text(value:sub(1, 1));
                end
                if (index < #values) then
                    imgui.SameLine();
                end
            end
        end

        for entryIndex, entry in ipairs(entries) do
            if (entryIndex > 1) then
                imgui.Separator();
            end
            imgui.TextColored(ui_style.gold, entry.name);
            draw_icon_row('Magic', entry.magic, 'element');
            draw_icon_row('WS', entry.ws, 'element');
            draw_icon_row('SC', entry.skillchains, 'skillchain');
        end
    end
    imgui.End();

    if (visible[1] ~= state.settings.coverage_overlay.visible) then
        state.settings.coverage_overlay.visible = visible[1];
        settings.save();
    end
end

local function push_window_style()
    imgui.PushStyleColor(ImGuiCol_WindowBg, ui_style.window_bg);
    imgui.PushStyleColor(ImGuiCol_ChildBg, ui_style.window_bg);
    imgui.PushStyleColor(ImGuiCol_PopupBg, ui_style.window_bg);
    imgui.PushStyleColor(ImGuiCol_TitleBg, ui_style.title_bg);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, ui_style.title_bg_active);
    imgui.PushStyleColor(ImGuiCol_Border, ui_style.border);
    imgui.PushStyleColor(ImGuiCol_Button, ui_style.button);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, ui_style.button_hovered);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, ui_style.button_active);
    imgui.PushStyleColor(ImGuiCol_FrameBg, ui_style.window_bg);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, ui_style.button);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, ui_style.button_hovered);
    imgui.PushStyleColor(ImGuiCol_Header, ui_style.button);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, ui_style.button_hovered);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, ui_style.button_active);
    imgui.PushStyleColor(ImGuiCol_Text, ui_style.text);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 4);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 3);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {10, 10});
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {6, 4});
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6});
end

local function pop_window_style()
    imgui.PopStyleVar(5);
    imgui.PopStyleColor(16);
end

local function get_trust_role(trust)
    if (trust == nil) then
        return nil;
    end

    local profile = find_trust_profile(trust.name);
    if (profile ~= nil and profile.role ~= nil) then return profile.role; end
    return 'utility';
end

local try_export;
local summon_single_trust;

local function collect_trust_action_entries(trusts)
    local entries = T{};
    for _, trust in ipairs(trusts or T{}) do
        entries:append(T{
            id = trust.id,
            name = trust.name,
            role = get_trust_role(trust),
            profile = get_trust_action_profile(trust),
        });
    end
    return entries;
end

local function draw_team_block(title, team, help_text, evaluation)
    imgui.TextColored(ui_style.gold, title);
    imgui.Separator();

    if (team == nil or #team == 0) then
        imgui.TextWrapped('No recommended trusts are available yet.');
        if help_text ~= nil then
            imgui.TextWrapped(help_text);
        end
        return;
    end

    for index, trust in ipairs(team) do
        local role = get_trust_role(trust);
        imgui.Text(('%u. %s [%s]'):fmt(index, trust.name, role));
        imgui.SameLine();
        if (imgui.Button(('Summon##suggested_%s_%u'):fmt(normalize_trust_name(title), index), { 90, 24 })) then
            local ok, err = summon_single_trust(trust);
            if (not ok) then
                print(chat.header(addon.name):append(chat.error(err)));
            end
        end
    end

    if help_text ~= nil then
        imgui.TextWrapped(help_text);
    end
    if (evaluation ~= nil) then
        imgui.TextColored(ui_style.gold, ('Rating: %.0f / 100 (%s)'):fmt(evaluation.total, evaluation.band));
        if (evaluation.primary_sc_plan ~= nil) then
            local plan = evaluation.primary_sc_plan;
            imgui.TextWrapped(('Primary SC: %s using %s -> %s'):fmt(plan.direction, plan.ws, plan.result));
        end
    end
end

local function draw_list_section(title, items)
    if (items == nil or #items == 0) then
        return;
    end

    imgui.TextColored(ui_style.gold, title);
    for _, item in ipairs(items) do
        imgui.BulletText(item);
    end
end

local function format_action_element(item)
    if (item == nil) then
        return 'Unknown action';
    end

    local label = rawget(item, 'name') or 'Unknown action';
    local tags = T{};

    local kind = rawget(item, 'kind');
    local scope = rawget(item, 'scope');
    local damage = rawget(item, 'damage');
    local element = rawget(item, 'element');
    local action_type = rawget(item, 'type');
    local damage_type = rawget(item, 'damage_type');
    local weapon_damage = rawget(item, 'weapon_damage');
    local action_range = rawget(item, 'range');
    local opens = rawget(item, 'opens');
    local involves = rawget(item, 'involves');
    local skillchains = rawget(item, 'skillchains');
    local notes = rawget(item, 'notes');
    local additional_effect = rawget(item, 'additional_effect');
    local description = rawget(item, 'description');
    local source = rawget(item, 'source');

    if (kind ~= nil) then
        tags:append(kind);
    end

    if (scope ~= nil) then
        tags:append(scope);
    end

    if (damage ~= nil) then
        tags:append(damage);
    end
    if (element ~= nil) then
        tags:append(('Element: %s'):fmt(element));
    end
    if (action_type ~= nil) then
        tags:append(('Type: %s'):fmt(action_type));
    end
    if (damage_type ~= nil) then
        tags:append(('Damage: %s'):fmt(damage_type));
    end
    if (weapon_damage ~= nil) then
        tags:append(('Weapon damage: %s'):fmt(weapon_damage));
    end
    if (action_range ~= nil) then
        tags:append(('Target/range: %s'):fmt(action_range));
    end

    if (#tags > 0) then
        label = ('%s [%s]'):fmt(label, table.concat(tags, ' | '));
    end

    local extras = T{};
    if (opens ~= nil and #opens > 0) then
        extras:append(('opens %s'):fmt(table.concat(opens, ', ')));
    end
    if (involves ~= nil and #involves > 0) then
        extras:append(('involved in %s'):fmt(table.concat(involves, ', ')));
    end
    if (skillchains ~= nil and #skillchains > 0) then
        extras:append(('skillchain properties: %s'):fmt(table.concat(skillchains, ', ')));
    end
    if (notes ~= nil and #notes > 0) then
        extras:append(table.concat(notes, '; '));
    end
    if (additional_effect ~= nil) then
        extras:append(('additional effect: %s'):fmt(additional_effect));
    end
    if (description ~= nil) then
        extras:append(description);
    end
    if (source ~= nil) then
        extras:append(('source: %s'):fmt(source));
    end

    if (#extras > 0) then
        label = ('%s -> %s'):fmt(label, table.concat(extras, ' | '));
    end

    return label;
end

local function draw_action_matrix_section(title, items)
    if (items == nil or #items == 0) then
        return;
    end

    imgui.TextColored(ui_style.gold, title);
    for _, item in ipairs(items) do
        imgui.BulletText(format_action_element(item));
    end
end

local TRUST_ACTION_KIND_FILTERS = T{ 'All', 'Spell', 'Ability', 'Weapon Skill' };
local TRUST_DAMAGE_FILTERS = T{ 'All', 'Physical', 'Magical', 'Slashing', 'Piercing', 'Blunt' };
local TRUST_ELEMENT_FILTERS = T{ 'All', 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' };

local function draw_filter_combo(label, id, current, options)
    imgui.Text(label);
    imgui.SameLine();
    imgui.SetNextItemWidth(150);
    if (imgui.BeginCombo(('##%s'):fmt(id), current, ImGuiComboFlags_None)) then
        for _, option in ipairs(options) do
            if (imgui.Selectable(('%s##%s_%s'):fmt(option, id, option), current == option)) then
                current = option;
            end
        end
        imgui.EndCombo();
    end
    return current;
end

local function action_matches_filters(action, filters)
    if (action == nil) then
        return false;
    end

    if (filters.action_kind ~= 'All' and rawget(action, 'kind') ~= filters.action_kind) then
        return false;
    end

    if (filters.element ~= 'All') then
        local element = (rawget(action, 'element') or ''):lower();
        local wanted = filters.element:lower();
        if (element ~= wanted and not element:find('%f[%a]' .. wanted .. '%f[%A]')) then
            return false;
        end
    end

    if (filters.damage ~= 'All') then
        local wanted = filters.damage:lower();
        local damage_type = (rawget(action, 'damage_type') or rawget(action, 'damage') or ''):lower();
        local weapon_damage = (rawget(action, 'weapon_damage') or ''):lower();

        if (wanted == 'physical') then
            if (not damage_type:find('physical', 1, true) and damage_type ~= 'slashing' and damage_type ~= 'piercing'
                and damage_type ~= 'blunt' and weapon_damage == '') then
                return false;
            end
        elseif (wanted == 'magical') then
            if (not damage_type:find('magical', 1, true)) then
                return false;
            end
        elseif (weapon_damage ~= wanted and damage_type ~= wanted) then
            return false;
        end
    end

    return true;
end

local function trust_matches_filters(trust, filters)
    local profile = get_trust_action_profile(trust);
    if (profile == nil or profile.actions == nil) then
        return filters.action_kind == 'All' and filters.damage == 'All' and filters.element == 'All';
    end

    for _, action in ipairs(profile.actions) do
        if (action_matches_filters(action, filters)) then
            return true;
        end
    end

    return false;
end

local function draw_trust_filters()
    local filters = state.trust_filters;
    imgui.TextColored(ui_style.gold, 'Filters');

    filters.action_kind = draw_filter_combo('Action', 'trust_action_kind', filters.action_kind, TRUST_ACTION_KIND_FILTERS);
    imgui.SameLine();
    filters.damage = draw_filter_combo('Damage', 'trust_damage', filters.damage, TRUST_DAMAGE_FILTERS);
    imgui.SameLine();
    filters.element = draw_filter_combo('Element', 'trust_element', filters.element, TRUST_ELEMENT_FILTERS);

    if (imgui.Button('Clear Filters', { 130, 24 })) then
        filters.action_kind = 'All';
        filters.damage = 'All';
        filters.element = 'All';
    end
end

local function draw_trust_profile(trust)
    local profile = get_trust_action_profile(trust);
    local action_details = get_trust_action_elements(trust);
    local role = get_trust_role(trust) or 'utility';

    if (imgui.CollapsingHeader(('%s##trust_%u'):fmt(trust.name, trust.id))) then
        imgui.TextColored(ui_style.gold, trust.name);
        imgui.Text(('Role: %s'):fmt(role));
        imgui.Text(('Job: %s'):fmt(profile.job or 'Unknown'));
        imgui.Text(('Spell ID: %u'):fmt(trust.id));

        if (profile.source ~= nil) then
            imgui.Text(('Source: %s'):fmt(profile.source));
        end

        if (action_details ~= nil and action_details.elements ~= nil and #action_details.elements > 0) then
            draw_action_matrix_section('Action matrix', action_details.elements);
        else
            draw_list_section('Job abilities', profile.job_abilities);
            draw_list_section('Weapon skills', profile.weapon_skills);
            draw_list_section('Spells', profile.spells);
        end

        draw_list_section('Skillchains / notes', profile.skillchains);

        if (profile.lines ~= nil and #profile.lines > 0) then
            imgui.TextColored(ui_style.gold, 'Summary');
            for _, line in ipairs(profile.lines) do
                imgui.BulletText(line);
            end
        end
    end
end

local function get_character_name()
    local party = AshitaCore:GetMemoryManager():GetParty();
    if (party == nil) then
        return nil;
    end

    local name = party:GetMemberName(0);
    if (name == nil or name:len() == 0) then
        return nil;
    end

    return name;
end

local function sanitize_filename(name)
    return (name:gsub('[<>:\"/\\|%?%*]', '_'));
end

local function get_job_name(job_id)
    local job_names = T{
        [1] = 'WAR', [2] = 'MNK', [3] = 'WHM', [4] = 'BLM', [5] = 'RDM', [6] = 'THF',
        [7] = 'PLD', [8] = 'DRK', [9] = 'BST', [10] = 'BRD', [11] = 'RNG', [12] = 'SAM',
        [13] = 'NIN', [14] = 'DRG', [15] = 'SMN', [16] = 'BLU', [17] = 'COR', [18] = 'PUP',
        [19] = 'DNC', [20] = 'SCH', [21] = 'GEO', [22] = 'RUN',
    };

    return job_names[job_id] or ('Job#' .. tostring(job_id));
end

local function collect_trusts()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player == nil or not player:HasSpellData()) then
        return nil, 'Spell data is not loaded yet.';
    end

    local resMgr = AshitaCore:GetResourceManager();
    local trusts = T{};

    for id = TRUST_MIN_ID, TRUST_MAX_ID do
        if (player:HasSpell(id)) then
            local spell = resMgr:GetSpellById(id);
            if (spell ~= nil and spell.Name ~= nil and spell.Name[1] ~= nil and spell.Name[1]:len() > 0) then
                trusts:append(T{
                    id = id,
                    name = spell.Name[1],
                });
            end
        end
    end

    trusts:sort(function (a, b)
        return a.name:lower() < b.name:lower();
    end);

    return trusts, nil;
end

local function collect_weapon_skills()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player == nil or not player:HasAbilityData()) then
        return nil, 'Ability data is not loaded yet.';
    end

    local resMgr = AshitaCore:GetResourceManager();
    local weapon_skills = T{};

    for id = WEAPON_SKILL_MIN_ID, WEAPON_SKILL_MAX_ID do
        if (player:HasWeaponSkill(id)) then
            local ability = resMgr:GetAbilityById(id);
            if (ability ~= nil and ability.Name ~= nil and ability.Name[1] ~= nil and ability.Name[1]:len() > 0) then
                weapon_skills:append(T{
                    id = id,
                    name = ability.Name[1],
                });
            end
        end
    end

    weapon_skills:sort(function (a, b)
        return a.name:lower() < b.name:lower();
    end);

    return weapon_skills, nil;
end

local TEAM_BUILDER_ROLES = T{
    T{ id = 'tank', label = 'Tank' },
    T{ id = 'healer', label = 'Healer' },
    T{ id = 'support', label = 'Support' },
    T{ id = 'melee', label = 'Melee DD' },
    T{ id = 'ranged', label = 'Ranged DD' },
    T{ id = 'caster', label = 'Caster' },
    T{ id = 'special', label = 'Special' },
};

local function normalize_builder_role(role)
    role = tostring(role or 'special'):lower();
    if (role == 'chain') then
        return 'melee';
    elseif (role == 'nuker') then
        return 'caster';
    elseif (role == 'utility') then
        return 'special';
    end
    return role;
end

local SITUATION_OPTIONS = T{
    'General Physical', 'Leveling', 'Skillchain', 'Magic Burst',
    'Boss Survival', 'Multiple Enemies', 'Status Heavy', 'Avoid AoE',
};
local TRUST_BEHAVIOR_COUNT = CANONICAL_DATA.diagnostics.behavior;

local function get_trust_behavior(trust)
    return CANONICAL_DATA.behavior(trust.name) or T{};
end

local function collect_character_ws_fit(weapon_skills, preferredWs)
    local skillchainScores = T{};
    local elementScores = T{};
    local properties = T{};
    local propertyCounts = T{};

    for _, weaponSkill in ipairs(weapon_skills or T{}) do
        if (preferredWs == nil or preferredWs == 'Auto' or weaponSkill.name == preferredWs) then
            local wsProperties = SKILLCHAIN_WS_BY_NAME[weaponSkill.name:lower()];
            for _, property in ipairs(wsProperties or T{}) do
                properties[property] = true;
                propertyCounts[property] = (propertyCounts[property] or 0) + 1;
            end
        end
    end

    -- Rank properties by whether they can actually open or close a directed chain
    -- with the selected player WS, rather than by simple property overlap.
    for _, candidateProperty in ipairs(SKILLCHAIN_ORDER) do
        local best = 0;
        for playerProperty, count in pairs(propertyCounts) do
            local playerOpens = DIRECTED_SKILLCHAINS[playerProperty] ~= nil
                and DIRECTED_SKILLCHAINS[playerProperty][candidateProperty] or nil;
            local trustOpens = DIRECTED_SKILLCHAINS[candidateProperty] ~= nil
                and DIRECTED_SKILLCHAINS[candidateProperty][playerProperty] or nil;
            local results = T{};
            if (playerOpens ~= nil) then results:append(playerOpens); end
            if (trustOpens ~= nil) then results:append(trustOpens); end
            for _, result in ipairs(results) do
                if (result ~= nil) then
                    local value = (SKILLCHAIN_LEVEL[result] or 1) * 12 + math.min(count, 5);
                    best = math.max(best, value);
                    for _, element in ipairs(SKILLCHAIN_ELEMENTS[result] or T{}) do
                        elementScores[element] = math.max(elementScores[element] or 0, value);
                    end
                end
            end
        end
        if (best > 0) then
            skillchainScores[candidateProperty] = best;
        end
    end

    local function best_set(scores)
        local result = T{};
        local highest = 0;
        for _, score in pairs(scores) do
            highest = math.max(highest, score);
        end
        if (highest > 0) then
            for name, score in pairs(scores) do
                if (score == highest) then
                    result[name] = true;
                end
            end
        end
        return result;
    end

    return T{
        skillchain_scores = skillchainScores,
        element_scores = elementScores,
        best_skillchains = best_set(skillchainScores),
        best_elements = best_set(elementScores),
        properties = properties,
    };
end

local CAPABILITY_CACHE = {};
local function collect_trust_builder_capabilities(trust)
    local key = ('%s:%s'):fmt(tostring(trust.id or 0), normalize_trust_name(trust.name));
    local cached = CAPABILITY_CACHE[key];
    if (cached ~= nil) then return cached; end

    local compiled = capability_compiler.compile(
        trust,
        find_trust_profile(trust.name),
        get_trust_behavior(trust),
        SKILLCHAIN_WS_BY_NAME
    );
    compiled.role = normalize_builder_role(get_trust_role(trust));
    -- Compatibility aliases while the UI is moved onto the canonical names.
    compiled.elements = compiled.direct_ws_elements;
    compiled.skillchains = compiled.skillchain_properties;
    CAPABILITY_CACHE[key] = compiled;
    return compiled;
end

local function count_selected(values)
    local count = 0;
    for _, selected in pairs(values or T{}) do
        if (selected == true) then
            count = count + 1;
        end
    end
    return count;
end

local function build_evaluation_context(weapon_skills, config)
    local fit = collect_character_ws_fit(weapon_skills, config.preferred_ws);
    local requirements = T{};
    if ((tonumber(config.role_counts.tank) or 0) > 0) then requirements.enmity = 0.65; end
    if ((tonumber(config.role_counts.healer) or 0) > 0) then requirements.healing = 0.65; end
    if ((tonumber(config.role_counts.support) or 0) > 0) then requirements.support = 0.45; end
    if (config.require_status_removal) then requirements.status_removal = 0.65; end
    if (config.require_dispel) then requirements.dispel = 0.65; end
    return T{
        situation = config.situation,
        player_properties = fit.properties,
        player_sc_policy = config.player_sc_policy or 'Either',
        player_role = config.player_role or 'Auto',
        enemy_count = config.enemy_count or 'Single',
        aoe_tolerance = config.aoe_tolerance or 'Normal',
        ws_damage_elements = config.ws_damage_elements,
        sc_result_elements = config.sc_result_elements,
        preferred_skillchains = config.skillchains,
        requirements = requirements,
    }, fit;
end

local function build_custom_team(trusts, weapon_skills, config)
    local context, fit = build_evaluation_context(weapon_skills, config);
    local maxTrusts = math.max(1, math.min(5, tonumber(config.max_trusts) or 3));
    local requestedSlots = 0;
    for _, role in ipairs(TEAM_BUILDER_ROLES) do
        requestedSlots = requestedSlots + math.max(0, tonumber(config.role_counts[role.id]) or 0);
    end
    if (requestedSlots > maxTrusts) then
        return T{}, fit, nil, ('Role quotas request %u slots but the maximum is %u.'):fmt(requestedSlots, maxTrusts);
    end
    local roster = {};
    for _, trust in ipairs(trusts or T{}) do table.insert(roster, collect_trust_builder_capabilities(trust)); end
    local best = team_optimizer.optimize(roster, context, {
        max_trusts = maxTrusts,
        beam_width = 140,
        role_counts = config.role_counts,
    });
    if (best == nil) then return T{}, fit, nil, 'No complete team satisfies the selected role requirements.'; end
    local byId, team = {}, T{};
    for _, trust in ipairs(trusts or T{}) do byId[trust.id] = trust; end
    for _, member in ipairs(best.team) do team:append(byId[member.id] or T{ id = member.id, name = member.name }); end
    return team, fit, best.evaluation, nil;
end

local function selection_fingerprint(values)
    local selected = {};
    for name, enabled in pairs(values or T{}) do if (enabled) then table.insert(selected, name); end end
    table.sort(selected);
    return table.concat(selected, ',');
end

local function builder_fingerprint(trusts, weapon_skills, config)
    local parts = {
        tostring(config.max_trusts), tostring(config.situation), tostring(config.preferred_ws),
        tostring(config.player_sc_policy), tostring(config.player_role), tostring(config.enemy_count),
        tostring(config.aoe_tolerance), tostring(config.require_status_removal), tostring(config.require_dispel),
        selection_fingerprint(config.ws_damage_elements),
        selection_fingerprint(config.sc_result_elements), selection_fingerprint(config.skillchains),
    };
    for _, role in ipairs(TEAM_BUILDER_ROLES) do table.insert(parts, role.id .. '=' .. tostring(config.role_counts[role.id] or 0)); end
    for _, trust in ipairs(trusts or T{}) do table.insert(parts, 't' .. tostring(trust.id)); end
    for _, ws in ipairs(weapon_skills or T{}) do table.insert(parts, 'w' .. tostring(ws.id)); end
    return table.concat(parts, '|');
end

local function cached_custom_team(trusts, weapon_skills, config)
    local fingerprint = builder_fingerprint(trusts, weapon_skills, config);
    if (state.builder_cache ~= nil and state.builder_cache.fingerprint == fingerprint) then
        return state.builder_cache.team, state.builder_cache.fit, state.builder_cache.evaluation, state.builder_cache.error;
    end
    local team, fit, evaluation, err = build_custom_team(trusts, weapon_skills, config);
    state.builder_cache = T{ fingerprint = fingerprint, team = team, fit = fit, evaluation = evaluation, error = err };
    return team, fit, evaluation, err;
end

local function collect_role_notes(trusts)
    local role_lines = T{};
    for _, trust in ipairs(trusts) do
        local capabilities = collect_trust_builder_capabilities(trust);
        local behavior = capabilities.behavior;
        local details = T{};
        if (behavior.tank) then details:append('tank control'); end
        if (behavior.healer) then details:append('healing'); end
        if (behavior.physical_support) then details:append('physical party buffs'); end
        if (behavior.sc_policy == 'closer') then details:append('skillchain closer'); end
        if (behavior.sc_policy == 'opener') then details:append('skillchain opener'); end
        if (behavior.interrupt) then details:append('interrupts'); end
        role_lines:append(('%s [%s]: %s'):fmt(
            trust.name,
            capabilities.role,
            #details > 0 and table.concat(details, ', ') or 'action and role coverage'
        ));
    end
    return role_lines;
end

local function build_recommendation(trusts, weapon_skills)
    local current_player = AshitaCore:GetMemoryManager():GetPlayer();
    local main_job = (current_player ~= nil and current_player:GetMainJob()) or 0;
    local main_job_name = get_job_name(main_job);
    local savedConfig = state.settings.team_builder or T{};
    local smartConfig = T{
        max_trusts = math.max(1, math.min(5, tonumber(savedConfig.max_trusts) or 3)),
        situation = savedConfig.situation or 'General Physical',
        preferred_ws = savedConfig.preferred_ws or 'Auto',
        player_sc_policy = savedConfig.player_sc_policy or 'Either',
        player_role = savedConfig.player_role or 'Auto',
        enemy_count = savedConfig.enemy_count or 'Single',
        aoe_tolerance = savedConfig.aoe_tolerance or 'Normal',
        require_status_removal = savedConfig.require_status_removal == true,
        require_dispel = savedConfig.require_dispel == true,
        role_counts = savedConfig.role_counts or T{ tank = 1, healer = 1, support = 1 },
        ws_damage_elements = savedConfig.ws_damage_elements or T{},
        sc_result_elements = savedConfig.sc_result_elements or T{},
        skillchains = savedConfig.skillchains or T{},
    };
    local smartTeam, _, smartEvaluation = build_custom_team(trusts, weapon_skills, smartConfig);

    local damageConfig = T{
        max_trusts = smartConfig.max_trusts,
        situation = 'General Physical',
        preferred_ws = smartConfig.preferred_ws,
        player_sc_policy = smartConfig.player_sc_policy,
        role_counts = T{ tank = 0, healer = 1, support = smartConfig.max_trusts >= 2 and 1 or 0, melee = 0, ranged = 0, caster = 0, special = 0 },
        ws_damage_elements = T{},
        sc_result_elements = smartConfig.sc_result_elements,
        skillchains = smartConfig.skillchains,
    };
    local damageTeam, _, damageEvaluation = build_custom_team(trusts, weapon_skills, damageConfig);

    local safeConfig = T{
        max_trusts = smartConfig.max_trusts,
        situation = 'Boss Survival',
        preferred_ws = smartConfig.preferred_ws,
        player_sc_policy = smartConfig.player_sc_policy,
        role_counts = T{ tank = smartConfig.max_trusts >= 2 and 1 or 0, healer = 1, support = smartConfig.max_trusts >= 3 and 1 or 0, melee = 0, ranged = 0, caster = 0, special = 0 },
        ws_damage_elements = T{}, sc_result_elements = smartConfig.sc_result_elements,
        skillchains = smartConfig.skillchains,
    };
    local safeTeam, _, safeEvaluation = build_custom_team(trusts, weapon_skills, safeConfig);

    return {
        main_job_name = main_job_name,
        all_trusts = trusts,
        weapon_skills = weapon_skills,
        ws_combo = smartTeam,
        beast_combo = damageTeam,
        safe_combo = safeTeam,
        ws_evaluation = smartEvaluation,
        beast_evaluation = damageEvaluation,
        safe_evaluation = safeEvaluation,
        ws_combo_reason = ('Full-roster team score for %s, including Trust AI policy, directed skillchains, support scaling, healer dependencies, and AoE risk.'):fmt(smartConfig.situation),
        beast_combo_reason = 'Damage-first full-roster score with one healer and one support; remaining slots are chosen by party synergy rather than a fixed name list.',
        safe_combo_reason = 'Survival-first alternative emphasizing tank control, healing, recovery, and safe positioning.',
        role_notes = collect_role_notes(smartTeam),
    };
end

local function recommendation_input_key(trusts, weapon_skills)
    local parts = T{ tostring(capability_compiler.version), tostring(team_optimizer.version), tostring(CANONICAL_DATA.version) };
    for _, trust in ipairs(trusts or T{}) do parts:append('t' .. tostring(trust.id)); end
    for _, weaponSkill in ipairs(weapon_skills or T{}) do parts:append('w' .. tostring(weaponSkill.id)); end
    return table.concat(parts, '|');
end

local function load_roster_snapshot()
    if (not state.character_loaded) then return false, 'No character is loaded.'; end
    local trusts, trustError = collect_trusts();
    local weaponSkills, weaponSkillError = collect_weapon_skills();
    if (trusts == nil or weaponSkills == nil) then return false, trustError or weaponSkillError; end
    local inputKey = recommendation_input_key(trusts, weaponSkills);
    if (state.recommendation ~= nil and state.recommendation_input_key == inputKey) then return true; end

    local currentPlayer = AshitaCore:GetMemoryManager():GetPlayer();
    local mainJob = (currentPlayer ~= nil and currentPlayer:GetMainJob()) or 0;
    state.recommendation = T{
        main_job_name = get_job_name(mainJob), all_trusts = trusts, weapon_skills = weaponSkills,
        ws_combo = T{}, beast_combo = T{}, safe_combo = T{}, role_notes = T{},
        recommendations_built = false,
    };
    state.recommendation_input_key = inputKey;
    state.builder_cache = nil;
    return true;
end

local function refresh_recommendation(force)
    if (not state.character_loaded) then
        state.recommendation = nil;
        return false, 'No character is loaded.';
    end

    local trusts, trust_err = collect_trusts();
    local weapon_skills, ws_err = collect_weapon_skills();

    if (trusts == nil or weapon_skills == nil) then
        state.recommendation = nil;
        return false, trust_err or ws_err;
    end

    local inputKey = recommendation_input_key(trusts, weapon_skills);
    if (not force and state.recommendation ~= nil and state.recommendation_input_key == inputKey) then
        return true;
    end

    state.recommendation = build_recommendation(trusts, weapon_skills);
    state.recommendation.recommendations_built = true;
    state.recommendation_input_key = inputKey;
    return true;
end

local function write_list_file(output_path, char_name, title, count_label, entries, empty_message)
    local file = io.open(output_path, 'w');
    if (file == nil) then
        return false, ('Failed to open output file: %s'):fmt(output_path);
    end

    file:write(('Character: %s\n'):fmt(char_name));
    file:write(('Generated: %s\n'):fmt(os.date('%Y-%m-%d %H:%M:%S')));
    file:write(('%s: %u\n\n'):fmt(count_label, #entries));

    if (#entries == 0) then
        file:write(('%s\n'):fmt(empty_message));
    else
        file:write(('%s\n'):fmt(title));
        file:write('\n');

        for _, entry in ipairs(entries) do
            file:write(('%s (%u)\n'):fmt(entry.name, entry.id));
        end
    end

    file:close();
    return true, output_path;
end

local function write_export_files()
    local char_name = get_character_name();
    if (char_name == nil) then
        return false, 'Unable to determine the current character name.';
    end

    local trusts, trust_err = collect_trusts();
    if (trusts == nil) then
        return false, trust_err;
    end

    local weapon_skills, ws_err = collect_weapon_skills();
    if (weapon_skills == nil) then
        return false, ws_err;
    end

    state.recommendation = build_recommendation(trusts, weapon_skills);
    local recommendation = state.recommendation;

    local config_dir = AshitaCore:GetInstallPath() .. 'config\\addons\\trusts';
    if (not ashita.fs.exists(config_dir)) then
        ashita.fs.create_dir(config_dir);
    end
    local output_dir = config_dir .. '\\exports';
    if (not ashita.fs.exists(output_dir)) then
        ashita.fs.create_dir(output_dir);
    end
    if (not ashita.fs.exists(output_dir)) then
        return false, ('Failed to create export directory: %s'):fmt(output_dir);
    end

    local safe_name = sanitize_filename(char_name);
    local trusts_output_path = ('%s\\%s_trusts.txt'):fmt(output_dir, safe_name);
    local trust_actions_output_path = ('%s\\%s_trust_actions.txt'):fmt(output_dir, safe_name);
    local weapon_skills_output_path = ('%s\\%s_weapon_abilities.txt'):fmt(output_dir, safe_name);
    local recommendation_output_path = ('%s\\%s_trust_recommendation.txt'):fmt(output_dir, safe_name);
    local trust_action_entries = collect_trust_action_entries(trusts);

    local ok, output_or_err = write_list_file(trusts_output_path, char_name, 'Trusts Learned', 'Trust Count', trusts, 'No trusts learned.');
    if (not ok) then
        return false, output_or_err;
    end

    ok, output_or_err = write_list_file(weapon_skills_output_path, char_name, 'Weapon Skills Learned', 'Weapon Skill Count', weapon_skills, 'No weapon skills learned.');
    if (not ok) then
        return false, output_or_err;
    end

    local file = io.open(trust_actions_output_path, 'w');
    if (file == nil) then
        return false, ('Failed to open output file: %s'):fmt(trust_actions_output_path);
    end

    file:write(('Character: %s\n'):fmt(char_name));
    file:write(('Generated: %s\n'):fmt(os.date('%Y-%m-%d %H:%M:%S')));
    file:write(('Trust Count: %u\n\n'):fmt(#trust_action_entries));

    for _, entry in ipairs(trust_action_entries) do
        local profile = entry.profile or T{};
        file:write(('%s (%u) [%s]\n'):fmt(entry.name, entry.id, entry.role));
        if (profile.source ~= nil) then
            file:write(('  Source: %s\n'):fmt(profile.source));
        end
        if (profile.job ~= nil) then
            file:write(('  Job: %s\n'):fmt(profile.job));
        end
        if (profile.damage ~= nil) then
            file:write(('  Damage: %s\n'):fmt(profile.damage));
        end
        if (profile.target ~= nil) then
            file:write(('  Target: %s\n'):fmt(profile.target));
        end
        if (profile.job_abilities ~= nil and #profile.job_abilities > 0) then
            file:write('  Job abilities:\n');
            for _, item in ipairs(profile.job_abilities) do
                file:write(('    - %s\n'):fmt(item));
            end
        end
        if (profile.weapon_skills ~= nil and #profile.weapon_skills > 0) then
            file:write('  Weapon skills:\n');
            for _, item in ipairs(profile.weapon_skills) do
                file:write(('    - %s\n'):fmt(item));
            end
        end
        if (profile.spells ~= nil and #profile.spells > 0) then
            file:write('  Spells:\n');
            for _, item in ipairs(profile.spells) do
                file:write(('    - %s\n'):fmt(item));
            end
        end
        local action_details = get_trust_action_elements(T{ name = entry.name });
        if (action_details ~= nil and action_details.elements ~= nil and #action_details.elements > 0) then
            file:write('  Action matrix:\n');
            for _, item in ipairs(action_details.elements) do
                file:write(('    - %s\n'):fmt(format_action_element(item)));
            end
        end
        if (profile.skillchains ~= nil and #profile.skillchains > 0) then
            file:write('  Skillchains / notes:\n');
            for _, item in ipairs(profile.skillchains) do
                file:write(('    - %s\n'):fmt(item));
            end
        end
        if (profile.lines ~= nil and #profile.lines > 0) then
            file:write('  Summary:\n');
            for _, line in ipairs(profile.lines) do
                file:write(('    - %s\n'):fmt(line));
            end
        end
        file:write('\n');
    end

    file:close();

    local file = io.open(recommendation_output_path, 'w');
    if (file == nil) then
        return false, ('Failed to open output file: %s'):fmt(recommendation_output_path);
    end

    file:write(('Character: %s\n'):fmt(char_name));
    file:write(('Main Job: %s\n'):fmt(recommendation.main_job_name));
    file:write(('Addon/model version: %s / %s\n'):fmt(addon.version, tostring(team_optimizer.version)));
    file:write(('Generated: %s\n\n'):fmt(os.date('%Y-%m-%d %H:%M:%S')));

    file:write('Recommended combo based on current weapon skills:\n');
    for index, trust in ipairs(recommendation.ws_combo) do
        file:write(('%u. %s (%u)\n'):fmt(index, trust.name, trust.id));
    end

    file:write('\nWhy this combo works:\n');
    file:write('- Tank, healer, support, and chain finisher are all covered.\n');
    file:write('- Your current weaponskills can push the party toward better skillchain windows when the finisher slot is chain-friendly.\n');
    file:write(('- %s\n'):fmt(recommendation.ws_combo_reason));
    if (recommendation.ws_evaluation ~= nil) then
        file:write(('Rating: %.1f (%s)\n'):fmt(recommendation.ws_evaluation.total, recommendation.ws_evaluation.band));
        for _, entry in ipairs(recommendation.ws_evaluation.ledger or {}) do
            file:write(('  [%s] %+.1f %s\n'):fmt(entry.id, entry.delta, entry.explanation));
        end
    end
    file:write('\nRole notes:\n');
    for _, line in ipairs(recommendation.role_notes) do
        file:write(('- %s\n'):fmt(line));
    end

    file:write('\nDamage-first situation-aware combo:\n');
    for index, trust in ipairs(recommendation.beast_combo) do
        file:write(('%u. %s (%u)\n'):fmt(index, trust.name, trust.id));
    end

    file:write('\nWhy this combo wins on raw nuking:\n');
    file:write(('- %s\n'):fmt(recommendation.beast_combo_reason));

    file:write('\nSurvival-first combo:\n');
    for index, trust in ipairs(recommendation.safe_combo or T{}) do
        file:write(('%u. %s (%u)\n'):fmt(index, trust.name, trust.id));
    end
    file:write(('- %s\n'):fmt(recommendation.safe_combo_reason));

    file:close();

    state.last_output = T{
        trusts = trusts_output_path,
        trust_actions = trust_actions_output_path,
        weapon_skills = weapon_skills_output_path,
        recommendation = recommendation_output_path,
    };
    return true, state.last_output;
end

local function ensure_team_builder_config()
    local config = state.settings.team_builder;
    if (config == nil) then
        config = T{};
        state.settings.team_builder = config;
    end
    config.max_trusts = tonumber(config.max_trusts) or 3;
    config.situation = config.situation or 'General Physical';
    config.preferred_ws = config.preferred_ws or 'Auto';
    config.player_sc_policy = config.player_sc_policy or 'Either';
    config.player_role = config.player_role or 'Auto';
    config.enemy_count = config.enemy_count or 'Single';
    config.aoe_tolerance = config.aoe_tolerance or 'Normal';
    if (config.require_status_removal == nil) then config.require_status_removal = false; end
    if (config.require_dispel == nil) then config.require_dispel = false; end
    config.role_counts = config.role_counts or T{};
    if (config.elements ~= nil) then
        config.elements = nil;
        config.ws_damage_elements = T{};
        config.sc_result_elements = T{};
    end
    config.ws_damage_elements = config.ws_damage_elements or T{};
    config.sc_result_elements = config.sc_result_elements or T{};
    config.skillchains = config.skillchains or T{};
    for _, role in ipairs(TEAM_BUILDER_ROLES) do
        if (config.role_counts[role.id] == nil) then
            config.role_counts[role.id] = (role.id == 'tank' or role.id == 'healer' or role.id == 'support') and 1 or 0;
        end
    end
    return config;
end

local function draw_builder_option(name, kind, selectedValues, bestValues, idPrefix)
    local selected = { selectedValues[name] == true };
    if (imgui.Checkbox(('##%s_%s'):fmt(idPrefix, name), selected)) then
        selectedValues[name] = selected[1];
        settings.save();
    end
    imgui.SameLine();

    local texture = load_coverage_icon(kind, name);
    if (texture ~= nil) then
        local pointer = tonumber(ffi.cast('uint32_t', texture));
        imgui.Image(pointer, { COVERAGE_ICON_SIZE, COVERAGE_ICON_SIZE });
        if (imgui.IsItemHovered()) then
            imgui.BeginTooltip();
            imgui.Text(name);
            imgui.EndTooltip();
        end
        imgui.SameLine();
    end

    if (bestValues[name]) then
        imgui.TextColored(ui_style.gold, ('%s  [BEST FIT]'):fmt(name));
    else
        imgui.Text(name);
    end
end

summon_single_trust = function(trust)
    if (trust == nil or trust.name == nil) then
        return false, 'No Trust was selected.';
    end

    local chatManager = AshitaCore:GetChatManager();
    if (chatManager == nil) then
        return false, 'The chat manager is not available.';
    end

    chatManager:QueueCommand(1, ('/ma "%s" <me>'):fmt(trust.name));
    return true;
end

local function behavior_summary(capabilities)
    local behavior = capabilities.behavior;
    local values = T{};
    if (behavior.tank) then values:append('tank control'); end
    if (behavior.healer) then values:append('healing'); end
    if (behavior.physical_support) then values:append('physical buffs'); end
    if (behavior.sc_policy == 'closer') then values:append('SC closer'); end
    if (behavior.sc_policy == 'opener') then values:append('SC opener'); end
    if (behavior.interrupt) then values:append('interrupts'); end
    if (behavior.status_removal) then values:append('status removal'); end
    if (behavior.aoe_healing) then values:append('AoE healing'); end
    if (behavior.aoe_risk) then values:append('AoE risk'); end
    return #values > 0 and table.concat(values, ', ') or 'action-data match';
end

local function draw_team_builder()
    local config = ensure_team_builder_config();
    local team, fit, evaluation, teamError = cached_custom_team(
        state.recommendation.all_trusts,
        state.recommendation.weapon_skills,
        config
    );

    imgui.TextWrapped('Teams are ranked from Trust AI behavior, situation, directed skillchain paths, role coverage, support scaling, and dependencies. Gold BEST FIT markers use the selected player weapon skill.');
    imgui.Separator();

    local maxOptions = T{ '1', '2', '3', '4', '5' };
    local selectedMax = draw_filter_combo('Maximum trusts', 'builder_max_trusts', tostring(config.max_trusts), maxOptions);
    local newMax = tonumber(selectedMax) or 3;
    if (newMax ~= config.max_trusts) then
        config.max_trusts = newMax;
        settings.save();
    end

    local newSituation = draw_filter_combo('Situation', 'builder_situation', config.situation, SITUATION_OPTIONS);
    if (newSituation ~= config.situation) then
        config.situation = newSituation;
        settings.save();
    end

    local weaponSkillOptions = T{ 'Auto' };
    for _, weaponSkill in ipairs(state.recommendation.weapon_skills or T{}) do
        weaponSkillOptions:append(weaponSkill.name);
    end
    local newPreferredWs = draw_filter_combo('Your WS', 'builder_preferred_ws', config.preferred_ws, weaponSkillOptions);
    if (newPreferredWs ~= config.preferred_ws) then
        config.preferred_ws = newPreferredWs;
        settings.save();
    end

    local scPolicyOptions = T{ 'Either', 'Trust Opens', 'Trust Closes' };
    local newScPolicy = draw_filter_combo('SC direction', 'builder_sc_policy', config.player_sc_policy, scPolicyOptions);
    if (newScPolicy ~= config.player_sc_policy) then
        config.player_sc_policy = newScPolicy;
        settings.save();
    end

    local playerRoleOptions = T{ 'Auto', 'Tank', 'Healer', 'Support', 'Damage' };
    local newPlayerRole = draw_filter_combo('Your role', 'builder_player_role', config.player_role, playerRoleOptions);
    if (newPlayerRole ~= config.player_role) then config.player_role = newPlayerRole; settings.save(); end
    local enemyOptions = T{ 'Single', 'Few', 'Many' };
    local newEnemyCount = draw_filter_combo('Enemies', 'builder_enemy_count', config.enemy_count, enemyOptions);
    if (newEnemyCount ~= config.enemy_count) then config.enemy_count = newEnemyCount; settings.save(); end
    local aoeOptions = T{ 'Low', 'Normal', 'High' };
    local newAoeTolerance = draw_filter_combo('AoE tolerance', 'builder_aoe_tolerance', config.aoe_tolerance, aoeOptions);
    if (newAoeTolerance ~= config.aoe_tolerance) then config.aoe_tolerance = newAoeTolerance; settings.save(); end

    local requireStatus = { config.require_status_removal == true };
    if (imgui.Checkbox('Require status removal', requireStatus)) then config.require_status_removal = requireStatus[1]; settings.save(); end
    local requireDispel = { config.require_dispel == true };
    if (imgui.Checkbox('Require Dispel', requireDispel)) then config.require_dispel = requireDispel[1]; settings.save(); end

    imgui.TextColored(ui_style.gold, 'Roles and quotas');
    local roleOptions = T{ '0', '1', '2', '3', '4', '5' };
    local quotaTotal = 0;
    for _, role in ipairs(TEAM_BUILDER_ROLES) do
        local count = tonumber(config.role_counts[role.id]) or 0;
        local selectedCount = draw_filter_combo(role.label, 'builder_role_' .. role.id, tostring(count), roleOptions);
        local newCount = tonumber(selectedCount) or 0;
        if (newCount ~= count) then
            config.role_counts[role.id] = newCount;
            settings.save();
        end
        quotaTotal = quotaTotal + newCount;
    end
    if (quotaTotal > config.max_trusts) then
        imgui.TextColored({ 1.0, 0.55, 0.35, 1.0 }, ('Role quotas total %u, above the maximum of %u. Reduce a quota to build a team.'):fmt(quotaTotal, config.max_trusts));
    end

    if (imgui.Button('Balanced Defaults', { 170, 26 })) then
        config.max_trusts = 3;
        config.situation = 'General Physical';
        config.preferred_ws = 'Auto';
        config.player_sc_policy = 'Either';
        config.player_role = 'Auto'; config.enemy_count = 'Single'; config.aoe_tolerance = 'Normal';
        config.require_status_removal = false; config.require_dispel = false;
        for _, role in ipairs(TEAM_BUILDER_ROLES) do
            config.role_counts[role.id] = (role.id == 'tank' or role.id == 'healer' or role.id == 'support') and 1 or 0;
        end
        config.ws_damage_elements = T{};
        config.sc_result_elements = T{};
        config.skillchains = T{};
        settings.save();
    end

    imgui.Separator();
    imgui.TextColored(ui_style.gold, 'Direct WS damage element');
    imgui.TextWrapped('Select elements to favor Trust weapon skills that directly deal magical or hybrid damage of that element.');
    for _, element in ipairs(ELEMENT_ORDER) do
        draw_builder_option(element, 'element', config.ws_damage_elements, T{}, 'builder_ws_damage_element');
    end

    imgui.Separator();
    imgui.TextColored(ui_style.gold, 'Desired SC / burst element');
    imgui.TextWrapped('Select elements you want the player and Trust weapon skills to produce as a skillchain result. BEST FIT is based on directed chains with your selected WS.');
    for _, element in ipairs(ELEMENT_ORDER) do
        draw_builder_option(element, 'element', config.sc_result_elements, fit.best_elements, 'builder_sc_result_element');
    end

    imgui.Separator();
    imgui.TextColored(ui_style.gold, 'Skillchain properties');
    imgui.TextWrapped('Select one or more properties to favor Trusts with matching weapon skills.');
    for _, property in ipairs(SKILLCHAIN_ORDER) do
        draw_builder_option(property, 'skillchain', config.skillchains, fit.best_skillchains, 'builder_sc');
    end

    imgui.Separator();
    imgui.TextColored(ui_style.gold, 'Built team');
    if (teamError ~= nil) then
        imgui.TextColored({ 1.0, 0.45, 0.35, 1.0 }, teamError);
        imgui.TextWrapped('Reduce one or more role quotas before a team can be recommended.');
        return;
    end
    if (count_selected(config.ws_damage_elements) == 0 and count_selected(config.sc_result_elements) == 0
        and count_selected(config.skillchains) == 0) then
        imgui.TextWrapped('No direct WS, SC-result element, or skillchain-property preference is selected; situation, coverage, AI behavior, and character compatibility determine the ranking.');
    end
    for index, trust in ipairs(team) do
        local capabilities = collect_trust_builder_capabilities(trust);
        imgui.Text(('%u. %s [%s]'):fmt(index, trust.name, capabilities.role));
        imgui.SameLine();
        if (imgui.Button(('Summon##built_team_%u_%s'):fmt(index, normalize_trust_name(trust.name)), { 90, 24 })) then
            local ok, err = summon_single_trust(trust);
            if (not ok) then
                print(chat.header(addon.name):append(chat.error(err)));
            end
        end
        imgui.TextColored({ 0.68, 0.68, 0.68, 1.0 }, ('   %s'):fmt(behavior_summary(capabilities)));
    end
    if (evaluation ~= nil) then
        imgui.TextColored(ui_style.gold, ('Team rating: %.1f / 100 (%s)'):fmt(evaluation.total, evaluation.band));
        if (evaluation.primary_sc_plan ~= nil) then
            local plan = evaluation.primary_sc_plan;
            imgui.TextWrapped(('Primary SC: %s using %s -> %s'):fmt(plan.direction, plan.ws, plan.result));
        end
        if (evaluation.fallback_sc_plan ~= nil) then
            local plan = evaluation.fallback_sc_plan;
            imgui.TextWrapped(('Fallback SC: %s using %s -> %s'):fmt(plan.direction, plan.ws, plan.result));
        end
        for _, warning in ipairs(evaluation.warnings or {}) do
            imgui.TextColored({ 1.0, 0.72, 0.35, 1.0 }, warning);
        end
        if (imgui.TreeNode('Why this team')) then
            for _, entry in ipairs(evaluation.ledger or {}) do
                if (math.abs(entry.delta or 0) >= 1) then
                    imgui.BulletText(('%+.1f %s: %s'):fmt(entry.delta, entry.category, entry.explanation));
                end
            end
            imgui.TreePop();
        end
    end
    if (#team == 0) then
        imgui.TextWrapped('No learned Trusts are available for this configuration.');
    end
end

local function draw_ui()
    if (not state.character_loaded or not state.ui_visible) then
        return;
    end

    local visible = { state.ui_visible };
    imgui.SetNextWindowSize({ 860, 620 }, ImGuiCond_FirstUseEver);
    push_window_style();
    local opened = imgui.Begin('Trusts###TrustsRecommendation', visible, ImGuiWindowFlags_AlwaysVerticalScrollbar);
    state.ui_visible = visible[1];
    if (opened) then
        if (state.recommendation == nil) then
            imgui.TextWrapped('Trust data is not ready yet.');
            imgui.TextWrapped('Try again after your spell and ability data loads.');
        else
            imgui.Text(('Main Job: %s'):fmt(state.recommendation.main_job_name));
            imgui.SameLine();
            imgui.Text('Team scoring: AI behavior + directed skillchains');
            imgui.Separator();

            if imgui.BeginTabBar('##TrustsConfigTabs', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
                if imgui.BeginTabItem('Overview') then
                    imgui.TextWrapped('This addon reads the Trusts and weapon skills your current character knows, then scores complete teams for the selected situation, party size, roles, Trust AI behavior, and directed skillchains.');
                    imgui.TextWrapped('The separate Trust Element Coverage overlay lists the magic elements, weapon-skill elements, and SkillChains properties available to each currently summoned trust.');
                    if (state.migration_notice ~= nil) then
                        imgui.TextColored({ 1.0, 0.72, 0.35, 1.0 }, state.migration_notice);
                    end
                    imgui.TextColored(ui_style.gold, 'Data status');
                    imgui.BulletText(('Trust profiles: %u generated + %u supplemental'):fmt(#TRUST_PROFILE_DATA, #TRUST_PROFILE_SUPPLEMENTS));
                    imgui.BulletText(('Curated behavior profiles: %u'):fmt(TRUST_BEHAVIOR_COUNT));
                    if (SKILLCHAINS_DATA ~= nil) then
                        imgui.BulletText('Skillchains data: loaded');
                    else
                        imgui.TextColored({ 1.0, 0.45, 0.35, 1.0 }, 'Skillchains data: unavailable; SC recommendations are degraded.');
                    end
                    local coverageVisible = { state.settings.coverage_overlay.visible };
                    if (imgui.Checkbox('Trust Element Coverage Overlay', coverageVisible)) then
                        state.settings.coverage_overlay.visible = coverageVisible[1];
                        settings.save();
                    end
                    imgui.SameLine();
                    if (imgui.Button('Reset Overlay Position')) then
                        state.reset_coverage_position = true;
                    end
                    imgui.Separator();
                    imgui.TextColored(ui_style.gold, 'Recommended role coverage');
                    for _, line in ipairs(state.recommendation.role_notes) do
                        imgui.BulletText(line);
                    end
                    imgui.EndTabItem();
                end

                if imgui.BeginTabItem('Teams') then
                    if (not state.recommendation.recommendations_built) then
                        imgui.TextWrapped('Team optimization has not been run. It only runs when you request it.');
                        if (imgui.Button('Build Recommendations', { 220, 28 })) then refresh_recommendation(true); end
                        imgui.Separator();
                    end
                    if (state.recommendation.recommendations_built and state.recommendation.ws_combo ~= nil) then
                        draw_team_block('Situation-aware team', state.recommendation.ws_combo, state.recommendation.ws_combo_reason, state.recommendation.ws_evaluation);
                    end

                    imgui.Separator();

                    if (state.recommendation.recommendations_built and state.recommendation.beast_combo ~= nil) then
                        draw_team_block('Damage-first team', state.recommendation.beast_combo, state.recommendation.beast_combo_reason, state.recommendation.beast_evaluation);
                    end

                    imgui.Separator();
                    if (state.recommendation.recommendations_built and state.recommendation.safe_combo ~= nil) then
                        draw_team_block('Survival-first team', state.recommendation.safe_combo, state.recommendation.safe_combo_reason, state.recommendation.safe_evaluation);
                    end
                    imgui.EndTabItem();
                end

                if imgui.BeginTabItem('Team Builder') then
                    draw_team_builder();
                    imgui.EndTabItem();
                end

                if imgui.BeginTabItem('Trusts') then
                    imgui.TextWrapped('Expand any trust to see a compact summary of the spells, weapon skills, and job abilities it uses.');
                    imgui.Separator();

                    draw_trust_filters();
                    imgui.Separator();

                    local matched_count = 0;
                    for _, trust in ipairs(state.recommendation and state.recommendation.all_trusts or T{}) do
                        if (trust_matches_filters(trust, state.trust_filters)) then
                            matched_count = matched_count + 1;
                            draw_trust_profile(trust);
                            imgui.Separator();
                        end
                    end

                    if (matched_count == 0) then
                        imgui.TextWrapped('No learned trusts match the selected filters.');
                    else
                        imgui.Text(('Matching learned trusts: %u'):fmt(matched_count));
                    end

                    imgui.EndTabItem();
                end

                if imgui.BeginTabItem('Exports') then
                    imgui.TextWrapped('Use the export button to write your current trusts, learned weapon skills, and recommendation files to config/addons/trusts/exports.');
                    imgui.Separator();

                    if imgui.Button('Refresh Recommendation', { 220, 28 }) then
                        refresh_recommendation(true);
                    end

                    if imgui.Button('Export Files', { 220, 28 }) then
                        try_export(true);
                    end

                    if (state.last_output ~= nil) then
                        imgui.Separator();
                        imgui.TextColored(ui_style.gold, 'Last export');
                        imgui.BulletText(('Trusts: %s'):fmt(state.last_output.trusts));
                        imgui.BulletText(('Trust actions: %s'):fmt(state.last_output.trust_actions));
                        imgui.BulletText(('Weapon skills: %s'):fmt(state.last_output.weapon_skills));
                        imgui.BulletText(('Recommendation: %s'):fmt(state.last_output.recommendation));
                    end

                    imgui.EndTabItem();
                end

                imgui.EndTabBar();
            end
        end

    end
    imgui.End();
    pop_window_style();
end

local function print_help(is_error)
    if (is_error) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message('/trusts export')):append(chat.color1(6, ' - Writes the current character trust and weapon skill lists to text files.')));
    print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message('/trusts ui')):append(chat.color1(6, ' - Toggles the recommendation window.')));
    print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message('/trusts help')):append(chat.color1(6, ' - Displays this help text.')));
end

try_export = function(reason)
    if (not state.character_loaded) then
        if (reason ~= nil) then
            print(chat.header(addon.name):append(chat.error('No character is loaded.')));
        end
        return false;
    end

    local ok, result = write_export_files();
    if (ok) then
        print(chat.header(addon.name):append(chat.message('Trust list exported to: ')):append(chat.success(result.trusts)));
        print(chat.header(addon.name):append(chat.message('Trust action list exported to: ')):append(chat.success(result.trust_actions)));
        print(chat.header(addon.name):append(chat.message('Weapon skill list exported to: ')):append(chat.success(result.weapon_skills)));
        print(chat.header(addon.name):append(chat.message('Trust recommendation exported to: ')):append(chat.success(result.recommendation)));
        return true;
    end

    if (reason ~= nil) then
        print(chat.header(addon.name):append(chat.error(result)));
    end

    return false;
end

local function has_local_character()
    local memory = AshitaCore:GetMemoryManager();
    local party = memory ~= nil and memory:GetParty() or nil;
    if (party == nil) then
        return false;
    end

    local name = party:GetMemberName(0);
    return party:GetMemberIsActive(0) ~= 0
        and party:GetMemberServerId(0) ~= 0
        and name ~= nil
        and name ~= '';
end

local function is_character_ready()
    if (not has_local_character()) then
        return false;
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer();
    return player ~= nil and player:HasSpellData() and player:HasAbilityData();
end

local function migrate_settings()
    local config = state.settings.team_builder or T{};
    state.settings.team_builder = config;
    config.max_trusts = model_schema.clamp_integer(config.max_trusts, 1, 5, 3);
    if (not model_schema.contains(model_schema.situations, config.situation)) then config.situation = 'General Physical'; end
    config.preferred_ws = config.preferred_ws or 'Auto';
    config.player_sc_policy = config.player_sc_policy or 'Either';
    config.player_role = config.player_role or 'Auto';
    config.enemy_count = config.enemy_count or 'Single';
    config.aoe_tolerance = config.aoe_tolerance or 'Normal';
    if (config.require_status_removal == nil) then config.require_status_removal = false; end
    if (config.require_dispel == nil) then config.require_dispel = false; end
    config.role_counts = config.role_counts or T{};
    config.ws_damage_elements = config.ws_damage_elements or T{};
    config.sc_result_elements = config.sc_result_elements or T{};
    config.skillchains = config.skillchains or T{};
    if (config.elements ~= nil) then
        config.elements = nil;
        config.ws_damage_elements = T{};
        config.sc_result_elements = T{};
        state.migration_notice = 'Old ambiguous element selections were cleared. Choose Direct WS and SC / burst elements separately.';
    end
    for _, role in ipairs(TEAM_BUILDER_ROLES) do
        config.role_counts[role.id] = math.max(0, model_schema.clamp_integer(config.role_counts[role.id], 0, 5,
            (role.id == 'tank' or role.id == 'healer' or role.id == 'support') and 1 or 0));
    end
    state.settings.coverage_overlay = state.settings.coverage_overlay or T{ visible = true };
    if (state.settings.coverage_overlay.visible == nil) then
        state.settings.coverage_overlay.visible = true;
    end
    state.settings.settings_version = 3;
    settings.save();
end

local function deactivate_character()
    state.character_loaded = false;
    state.refresh_scheduled = false;
    state.recommendation = nil;
    state.recommendation_input_key = nil;
    state.builder_cache = nil;
    state.coverage_entries = T{};
    state.coverage_roster_key = nil;
    state.last_output = nil;
end

local function schedule_recommendation_refresh()
    if (state.refresh_scheduled) then
        return;
    end
    state.refresh_scheduled = true;
    ashita.tasks.oncef(0, function()
        state.refresh_scheduled = false;
        if (state.character_loaded and is_character_ready()) then
            load_roster_snapshot();
        end
    end);
end

local function activate_character()
    if (state.character_loaded) then
        return true;
    end

    if (not is_character_ready()) then
        return false;
    end

    state.character_loaded = true;
    schedule_recommendation_refresh();
    return true;
end

ashita.events.register('load', 'load_cb', function ()
    migrate_settings();
    deactivate_character();
    activate_character();
end);

ashita.events.register('unload', 'unload_cb', function ()
    deactivate_character();
    settings.save();
    coverage_icon_cache = T{};
end);

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    -- Packet: Spells Information
    if (e.id == 0x00AA) then
        if (not state.character_loaded) then
            activate_character();
        else
            schedule_recommendation_refresh();
        end
    end
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    if (state.character_loaded and not has_local_character()) then
        deactivate_character();
        return;
    end

    if (not state.character_loaded and not activate_character()) then
        return;
    end

    draw_ui();
    render_coverage_panel();
end);

ashita.events.register('command', 'command_cb', function (e)
    local rawCommand = tostring(e.command or '');
    if (rawCommand:sub(1, 7):lower() ~= '/trusts') then
        return;
    end
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/trusts')) then
        return;
    end

    e.blocked = true;

    if (#args >= 2 and args[2]:any('help')) then
        print_help(false);
        return;
    end

    if (not state.character_loaded and not activate_character()) then
        print(chat.header(addon.name):append(chat.error('No character is loaded yet.')));
        return;
    end

    if (#args >= 2 and args[2]:any('ui')) then
        state.ui_visible = not state.ui_visible;
        print(chat.header(addon.name):append(chat.message('Trust UI is now: ')):append(chat.success(state.ui_visible and 'Visible' or 'Hidden')));
        return;
    end

    if (#args >= 2 and args[2]:any('export', 'write', 'save')) then
        try_export(true);
        return;
    end

    if (#args >= 2 and args[2]:any('summon')) then
        print(chat.header(addon.name):append(chat.message('Automatic team summoning was removed. Use the individual Summon buttons in Teams or Team Builder.')));
        return;
    end

    if (#args >= 2 and args[2]:any('beast', 'burst')) then
        print(chat.header(addon.name):append(chat.message('Automatic team summoning was removed. Use the individual Summon buttons in Teams or Team Builder.')));
        return;
    end

    if (#args == 1) then
        try_export(true);
        return;
    end

    print_help(true);
end);
