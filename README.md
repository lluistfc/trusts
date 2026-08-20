# Trusts for Ashita v4

An Ashita addon for exporting Trust and weapon-skill data, recommending Trust
party combinations, and summoning selected Trusts.

## Features

- Reads the Trust spells and weapon skills learned by the current character.
- Shows searchable Trust profiles with spells, abilities, weapon skills,
  skillchain properties, roles, and behavior notes.
- Builds complete teams from party size, situation, role quotas, player weapon
  skill, desired skillchains/elements, enemy count, AoE tolerance, status
  removal, and Dispel requirements.
- Ranks teams using Trust behavior, directed skillchain paths, support scaling,
  role coverage, dependencies, and compatibility with the current character.
- Provides an optional element-coverage overlay for currently summoned Trusts.
- Summons only when an individual `Summon` button is pressed. Automatic team
  summoning has intentionally been removed.

Trust and weapon-skill data is not available until the character's spell and
ability data has loaded. Recommendations are built on request rather than every
frame.

## Optional integrations

- If `addons/skillchains/skills.lua` is installed, its data is used for richer
  weapon-skill and skillchain matching. Trusts continues with reduced matching
  data when SkillChains is absent.
- If matching XIUI hotbar icons are installed, the coverage display uses them.
  XIUI is optional and missing icons do not prevent the addon from loading.

## Commands

```text
/trusts
/trusts export
/trusts ui
/trusts help
```

`/trusts` and `/trusts export` refresh the recommendation and write export
files. `/trusts ui` toggles the main window. Team summoning is performed through
the individual buttons in the Teams and Team Builder tabs.

## Exports

Running `/trusts` or `/trusts export` writes the current character's Trust
roster, Trust actions, weapon skills, and team recommendation to:

```text
config/addons/trusts/exports/
```

Export files are kept in Ashita's configuration tree so the installed addon
directory contains only addon code and bundled data. The files are named after
the current character and include the learned Trust roster, Trust action
details, weapon skills, and generated recommendation.

Settings such as team-builder preferences and overlay visibility are persisted
through Ashita's settings system.

## Original project

This addon was developed as a custom Ashita addon and is not a port of a
single Windower addon, so there is no original addon repository to link.
