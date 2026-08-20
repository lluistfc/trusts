#!/usr/bin/env python3
"""Generate the Trust addon database from BG Wiki's canonical Trust page.

Only read-only MediaWiki API requests are made.  Linked action pages are queried in
batches; missing pages (redlinks) are deliberately ignored.
"""

from __future__ import annotations

import html
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://www.bg-wiki.com/api.php"
SOURCE_PAGE = "BGWiki:Trusts"
SOURCE_URL = "https://www.bg-wiki.com/ffxi/BGWiki:Trusts"
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "trust_profiles.lua"
UA = "Ashita-Trusts-Data-Updater/1.0 (read-only; source attribution in generated file)"

ROLES = {
    "Tank": "tank", "Melee Fighter": "melee", "Ranged Fighter": "ranged",
    "Offensive Caster": "caster", "Healer": "healer", "Support": "support",
    "Special": "special",
}
FIELDS = ("Job", "Spells", "Abilities", "Weapon Skills")
META_KEYS = {
    "element": ("element", "elements"),
    "damage_type": ("damage type", "damage", "type of damage"),
    "type": ("type", "category", "magic type", "ability type"),
    "range": ("range", "target", "targets"),
    "additional_effect": ("additional effect", "additional effects", "effect"),
    "description": ("description",),
}


def api(params: dict[str, str]) -> dict:
    params = {**params, "format": "json", "formatversion": "2"}
    request = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def raw_page(title: str) -> str:
    data = api({"action": "parse", "page": title, "prop": "wikitext"})
    return data["parse"]["wikitext"]


def clean_markup(value: str) -> str:
    value = re.sub(r"<!--.*?-->", "", value, flags=re.S)
    value = re.sub(r"\[\[(?:File|Image):.*?\]\]", "", value, flags=re.I)
    value = re.sub(r"\[https?://\S+\s+([^\]]+)\]", r"\1", value)
    value = re.sub(r"\[\[\s*:?(?:Category:)?([^]|#]+)(?:#[^]|]*)?\|([^]]+)\]\]", r"\2", value, flags=re.I)
    value = re.sub(r"\[\[\s*:?(?:Category:)?([^]|#]+)(?:#[^]|]*)?\]\]", r"\1", value, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"\{\{(?:None|verification|Information Needed)[^}]*\}\}", "", value, flags=re.I)
    value = re.sub(r"\{\{\s*(fire|ice|wind|earth|lightning|thunder|water|light|dark|question)\s*\}\}", lambda m: ("Lightning" if m.group(1).lower() == "thunder" else m.group(1).title()), value, flags=re.I)
    value = value.replace("'''", "").replace("''", "")
    value = html.unescape(value)
    return re.sub(r"\s+", " ", value).strip(" ,/*")


def links(value: str) -> list[dict[str, str]]:
    result = []
    seen = set()
    for match in re.finditer(r"\[\[\s*:?(?!File:|Image:)([^]|#]+)(?:#[^]|]*)?(?:\|([^]]+))?\]\]", value, re.I):
        target = match.group(1).strip().replace("_", " ")
        label = clean_markup(match.group(2) or target)
        if target.lower().startswith("category:"):
            target = target.split(":", 1)[1]
        key = (target, label)
        if key not in seen:
            seen.add(key)
            result.append({"name": label, "page": target})
    return result


def split_actions(value: str) -> list[dict]:
    actions = []
    # Each Trust template uses commas/new list items between actions.  Parentheses
    # contain explanations and linked status effects, not additional actions.
    segments, start, parens, links_depth, templates = [], 0, 0, 0, 0
    index = 0
    while index < len(value):
        pair = value[index:index + 2]
        if pair == "[[": links_depth += 1; index += 2; continue
        if pair == "]]" and links_depth: links_depth -= 1; index += 2; continue
        if pair == "{{": templates += 1; index += 2; continue
        if pair == "}}" and templates: templates -= 1; index += 2; continue
        char = value[index]
        if not links_depth and not templates:
            if char == "(": parens += 1
            elif char == ")" and parens: parens -= 1
            elif char == "," and not parens:
                segments.append(value[start:index]); start = index + 1
            elif char == "\n" and not parens and re.match(r"\s*\*[^*]", value[index + 1:]):
                segments.append(value[start:index]); start = index + 1
        index += 1
    segments.append(value[start:])
    for segment in segments:
        top_level = re.sub(r"\([^()]*(?:\([^()]*\)[^()]*)*\)", "", segment)
        found = links(top_level)
        skillchains = [re.sub(r"^:Category:", "", x, flags=re.I) for x in re.findall(r"SC Icon\.png[^]]*\|link=([^]|]+)", segment, re.I)]
        for item in found:
            if item["page"] in skillchains:
                continue
            if skillchains:
                item["skillchains"] = list(dict.fromkeys(skillchains))
            if item["name"].strip().lower() in {"i", "ii", "iii", "iv", "v", "vi", "ni"}:
                item["name"] = item["page"]
            actions.append(item)
        if not found:
            plain_segment = clean_markup(top_level)
            plain_segment = re.sub(r"^(?:Neutral|Daybreak)\s*:\s*", "", plain_segment, flags=re.I)
            if plain_segment:
                actions.append({"name": plain_segment})
    # Preserve meaningful unlinked entries (many unique Trust actions are redlinks/plain text).
    plain = clean_markup(value)
    if not actions and plain:
        for name in re.split(r"\s*,\s*|\s+/\s+", plain):
            if name:
                actions.append({"name": name})
    return actions


def parse_trusts(text: str) -> list[dict]:
    section_matches = list(re.finditer(r"^==([^=\n]+)==\s*$", text, re.M))
    trusts = []
    for si, section in enumerate(section_matches):
        role_title = section.group(1).strip()
        if role_title not in ROLES:
            continue
        end = section_matches[si + 1].start() if si + 1 < len(section_matches) else len(text)
        chunk = text[section.end():end]
        headings = list(re.finditer(r"^===([^=\n]+)===\s*$", chunk, re.M))
        for hi, heading in enumerate(headings):
            block_end = headings[hi + 1].start() if hi + 1 < len(headings) else len(chunk)
            block = chunk[heading.end():block_end]
            name_match = re.search(r"^\|Name\s*=\s*(.+)$", block, re.M)
            name = clean_markup(name_match.group(1) if name_match else heading.group(1))
            trust = {"name": name, "role": ROLES[role_title], "source": SOURCE_URL + "#" + urllib.parse.quote(name.replace(" ", "_")), "actions": []}
            for field in FIELDS:
                m = re.search(r"^\|" + re.escape(field) + r"\s*=\s*(.*?)(?=^\|(?:Acquisition|Special|Synergy|Edit ID|Job|Spells|Abilities|Weapon Skills)\s*=|\Z)", block, re.M | re.S)
                value = m.group(1).strip() if m else ""
                if field == "Job":
                    trust["job"] = clean_markup(value) or "Unknown"
                else:
                    kind = {"Spells": "Spell", "Abilities": "Ability", "Weapon Skills": "Weapon Skill"}[field]
                    for action in split_actions(value):
                        action["kind"] = kind
                        trust["actions"].append(action)
            trusts.append(trust)
    return trusts


def query_linked_pages(titles: list[str]) -> dict[str, dict]:
    pages = {}
    for offset in range(0, len(titles), 50):
        batch = titles[offset:offset + 50]
        data = api({"action": "query", "prop": "revisions|info", "rvprop": "content", "rvslots": "main", "inprop": "url", "titles": "|".join(batch)})
        for page in data["query"]["pages"]:
            if page.get("missing"):
                continue
            content = page.get("revisions", [{}])[0].get("slots", {}).get("main", {}).get("content", "")
            pages[page["title"].replace("_", " ")] = {"url": page.get("fullurl"), "raw": content}
    return pages


def extract_metadata(raw: str) -> dict[str, str]:
    result = {}
    # Standard BG Wiki templates express their useful infobox values as |key=value.
    values = {}
    for match in re.finditer(r"^\|\s*([^=\n]+?)\s*=\s*(.*?)(?=^\|\s*[^=\n]+?\s*=|^\}\}|\Z)", raw, re.M | re.S):
        key = re.sub(r"\s+", " ", match.group(1).strip().lower())
        value = clean_markup(match.group(2))
        if value and len(value) <= 300:
            values[key] = value
    for output_key, aliases in META_KEYS.items():
        for alias in aliases:
            if alias in values:
                result[output_key] = values[alias]
                break
    return result


WEAPON_DAMAGE = {
    "hand-to-hand": "Blunt", "club": "Blunt", "staff": "Blunt",
    "dagger": "Piercing", "polearm": "Piercing", "archery": "Piercing", "marksmanship": "Piercing",
    "sword": "Slashing", "great sword": "Slashing", "axe": "Slashing", "great axe": "Slashing",
    "scythe": "Slashing", "katana": "Slashing", "great katana": "Slashing",
}


def infer_weapon_damage(action: dict, meta: dict[str, str]) -> str | None:
    if action.get("kind") != "Weapon Skill":
        return None
    if meta.get("element"):
        return None
    weapon = meta.get("type", "").lower()
    return WEAPON_DAMAGE.get(weapon)


def infer_damage_type(action: dict, meta: dict[str, str]) -> str | None:
    if meta.get("damage_type") or action.get("kind") != "Weapon Skill":
        return None
    description = meta.get("description", "").lower()
    if meta.get("element") and ("elemental damage" in description or "magic damage" in description):
        return "Magical"
    if re.search(r"delivers? (?:an? |a \w+-|a \w+fold )?(?:area )?attack|\bphysical damage\b", description):
        return "Physical"
    return None


def lua(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("\r", " ").replace("\n", " ") + "'"


def write_lua(trusts: list[dict], pages: dict[str, dict]) -> None:
    out = ["-- Generated by tools/update_bgwiki_data.py; do not hand-edit.", "-- Source: " + SOURCE_URL, "require('common');", "", "return T{"]
    for trust in trusts:
        out += ["    T{", f"        name = {lua(trust['name'])},", f"        role = {lua(trust['role'])},", f"        job = {lua(trust['job'])},", f"        source = {lua(trust['source'])},", "        actions = T{"]
        for action in trust["actions"]:
            page = pages.get(action.get("page", ""))
            meta = extract_metadata(page["raw"]) if page else {}
            bits = [f"kind = {lua(action['kind'])}", f"name = {lua(action['name'])}"]
            if page:
                bits.append(f"source = {lua(page['url'])}")
            for key in ("element", "damage_type", "type", "range", "additional_effect", "description"):
                if meta.get(key):
                    bits.append(f"{key} = {lua(meta[key])}")
            weapon_damage = infer_weapon_damage(action, meta)
            if weapon_damage:
                bits.append(f"weapon_damage = {lua(weapon_damage)}")
            inferred_damage = infer_damage_type(action, meta)
            if inferred_damage:
                bits.append(f"damage_type = {lua(inferred_damage)}")
            if action.get("skillchains"):
                bits.append("skillchains = T{ " + ", ".join(lua(x) for x in action["skillchains"]) + " }")
            out.append("            T{ " + ", ".join(bits) + " },")
        out += ["        },", "    },"]
    out += ["};", ""]
    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")


def main() -> int:
    trusts = parse_trusts(raw_page(SOURCE_PAGE))
    titles = sorted({a["page"] for t in trusts for a in t["actions"] if a.get("page")})
    pages = query_linked_pages(titles)
    write_lua(trusts, pages)
    print(f"Generated {OUT} with {len(trusts)} Trusts, {sum(len(t['actions']) for t in trusts)} actions, and {len(pages)}/{len(titles)} live linked pages.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
