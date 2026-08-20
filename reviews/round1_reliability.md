# Round 1 — Skeptical Ashita/Lua reliability review

Reviewer persona: senior Ashita/Lua reliability engineer. Scope: runtime safety, lifecycle, frame-time cost, settings migration, ImGui usage, scheduling, data loading, maintainability, and testability. This is a source review, not an in-game runtime test.

## Executive judgment

The addon has several strong defensive choices, but its newest recommendation layer has grown inside one 2,138-line module without a boundary between pure scoring and Ashita/UI side effects. The highest-priority defects are a reproducible ImGui close-state bug, an obsolete automatic summon path that remains command-accessible after the UI was deliberately changed to manual summoning, and synchronous export/scoring work initiated from the render callback. The recommendation algorithm is small enough today that it may appear smooth, but it needlessly reconstructs team candidates on every rendered Team Builder frame.

I would not call the addon production-hardened until the P1 items below are fixed and tested in Ashita across login, logout, zoning, addon reload, window close, corrupt settings, missing XIUI/skillchains dependencies, and export failures.

## Findings

### R1 — Main window close button does not reliably hide the window

Severity: **P1 / high**

Evidence: `trusts.lua:1819-1824`. `visible` is initialized before `imgui.Begin`, but `state.ui_visible = visible[1]` occurs only inside `if (opened)`. Dear ImGui can return `false` from `Begin` when the window is collapsed/closed; on a close click, `visible[1]` may become false while `opened` is false. The state then remains true and the window is submitted again next frame.

Pros:

- The addon correctly passes a mutable open flag and always pairs `Begin` with `End` (`trusts.lua:1822,1938`).
- Initial sizing uses `ImGuiCond_FirstUseEver`, preserving user resizing (`trusts.lua:1820`).

Cons:

- Close state is conditionally copied.
- `ui_visible` is not persisted, so even a corrected close is session-only; that may be intended, but should be explicit.

Fix: copy `visible[1]` into `state.ui_visible` immediately after `Begin`, regardless of `opened`. Keep content conditional and `End` unconditional.

### R2 — Removed/broken automatic summoning remains externally reachable

Severity: **P1 / high**

Evidence: automatic sequencing still exists at `trusts.lua:1409-1454`; `/trusts summon` and `/trusts beast` invoke it at `trusts.lua:2096-2128`; help advertises both at `trusts.lua:1950-1951`. The UI was changed to individual manual buttons (`trusts.lua:656-665`, `1678-1690`, `1790-1799`), but the old command surface and state (`summon_in_progress`, `summon_progress`, `summon_queue_id`) remain.

Pros:

- The queue has a generation token and checks character state, so logout/unload can cancel subsequent iterations (`trusts.lua:1436`, `2005-2007`).
- Manual buttons issue only one command and return an error if the chat manager is unavailable.

Cons:

- This preserves exactly the workflow the user reported as unreliable.
- `coroutine.sleepf(6.5)` assumes the task callback is running in a yieldable coroutine and uses elapsed time rather than observing cast/party state.
- The sequence does not verify whether a summon succeeded, whether the Trust is already present, party capacity, zoning, combat restrictions, or recast state.
- `summon_progress` has no UI consumer, so its state machinery is dead from the user's perspective.

Fix: remove the automatic queue, its commands/help, forward declaration, and state unless it is redesigned around incoming action/party-state confirmation. Keep only `summon_single_trust` for the agreed manual workflow.

### R3 — Character activation performs synchronous scoring and disk export from `d3d_present`

Severity: **P1 / high**

Evidence: every pre-login frame calls `activate_character` (`trusts.lua:2053-2061`). On the first ready frame it calls `refresh_recommendation` and then `try_export` (`trusts.lua:2023-2026`). Export scans resources, formats the entire action database, creates files, and writes four output files synchronously (`trusts.lua:1481-1628`).

Pros:

- The character-ready gate prevents character-dependent UI before spell and ability data exist (`trusts.lua:1981-2002`).
- Activation is idempotent once `state.character_loaded` becomes true.
- Logout clears character-derived recommendations and output state (`trusts.lua:2004-2012`).

Cons:

- File I/O on the graphics-present callback can cause a visible frame hitch, especially with the ~198 KB generated profile table.
- Automatic export is surprising and duplicates scoring immediately: `refresh_recommendation()` builds once, then `write_export_files()` builds it again at `trusts.lua:1497`.
- Before login, full readiness is polled every frame even though packet/state events can reduce polling frequency.

Fix: activation should only populate an in-memory snapshot. Make export explicit, or schedule it outside the render callback after readiness. If automatic export is retained, run it once via a task and never recompute the recommendation inside export when a current snapshot exists.

### R4 — Team Builder recomputes the full model every visible frame

Severity: **P2 / medium**

Evidence: `draw_team_builder` calls `build_custom_team` every frame (`trusts.lua:1707-1713`). That scans every learned Trust, scans every action for each Trust, calculates player compatibility, and performs greedy team scoring (`trusts.lua:1054-1316`). The coverage overlay likewise rebuilds all summoned-Trust sets every frame (`trusts.lua:450-520`).

Pros:

- The UI always reflects a setting change immediately.
- Learned Trust/WS collections themselves are cached in `state.recommendation` rather than rescanned from resources every frame.

Cons:

- Most inputs change rarely: settings change on clicks, player WS data changes on ability packets/job state, and roster changes on spell data.
- `collect_trust_builder_capabilities` repeatedly normalizes names and traverses profile actions despite profiles being static.
- UI rendering, model construction, and domain scoring are coupled, making performance regression difficult to measure.

Fix: precompute immutable capability records once at module load or recommendation refresh. Cache the built result under a deterministic config revision/key and invalidate only on config, learned roster, learned WS, or relevant player-equipment changes. Cache summoned coverage until party membership changes or poll it at a modest interval.

### R5 — Data/dependency loading can abort or silently degrade the addon

Severity: **P2 / medium**

Evidence: all three Trust data files are required without protection at `trusts.lua:170-172`; a syntax/runtime error in generated or curated data prevents addon load. Skillchains data is loaded with `loadfile`/`pcall`, but all failure detail is discarded (`trusts.lua:229-240`). The dependency is read only once, so reloading/updating Skillchains leaves stale data until Trusts is reloaded. Icons hard-depend on XIUI's private asset layout (`trusts.lua:45-49`) and missing icons are negatively cached for the entire session.

Pros:

- Missing Skillchains data does not crash the addon.
- Missing XIUI icons degrade to first-letter text (`trusts.lua:557-559`).
- FFI texture creation checks both HRESULT and pointer and uses managed lifetime release (`trusts.lua:53-68`).

Cons:

- Silent Skillchains load failure produces lower-quality recommendations with no diagnostic explaining why.
- Executing another addon's Lua file via `loadfile` creates undocumented schema/code coupling.
- A transient missing device/file is cached as `false`, so an icon cannot recover later without addon reload.
- Generated data and hand-maintained supplements have no schema/version validation.

Fix: validate each loaded dataset against a minimal schema and log a single actionable warning. Return error details from `loadfile` and `pcall`. Prefer a versioned shared data module owned by Trusts (or a stable Skillchains API) rather than executing another addon's implementation file. Permit negative-icon-cache retry after device reset or a bounded delay.

### R6 — Settings migration validates presence, not values or types

Severity: **P2 / medium**

Evidence: `ensure_team_builder_config` fills missing tables/keys but accepts arbitrary `situation`, `preferred_ws`, role values, and selected-map values (`trusts.lua:1631-1648`). `max_trusts` is numerically parsed but not stored clamped; clamping occurs later only in model construction (`trusts.lua:1280`). `coverage_overlay.visible` is accessed directly without a local migration guard (`trusts.lua:516`, `1839`). Settings are saved on every individual checkbox/combo change (`trusts.lua:1653-1655`, `1721-1751`) with no batching/debounce.

Pros:

- Missing Team Builder keys receive sensible defaults.
- Old settings are unlikely to fail merely because new role keys were added.

Cons:

- Corrupt settings can yield invalid previews, quotas, or errors from indexing unexpected scalar values as tables.
- A removed/renamed learned WS can remain as `preferred_ws`, causing an empty player-property fit with no explanation.
- Frequent synchronous saves add avoidable writes and make settings behavior depend on the settings library's implicit current-object semantics (`settings.save()` has no explicit object).

Fix: introduce a versioned `migrate_and_validate_settings` called immediately after load. Type-check nested tables, clamp counts, constrain enums, coerce selected values to booleans, reset unavailable preferred WS to `Auto`, and debounce/save once after a changed frame or on unload.

### R7 — Exports are non-atomic and error handling is incomplete

Severity: **P2 / medium**

Evidence: four files are opened and overwritten sequentially (`trusts.lua:1456-1628`). Directory creation result is unchecked (`trusts.lua:1500-1503`). `file:write` and `file:close` results are ignored. If a later file fails, earlier files have already been replaced, leaving a mixed-generation export set. A failed automatic export sets `pending_export` (`trusts.lua:1977`), but retries are tied to receiving packet `0x00AA` (`trusts.lua:2041-2049`), which may never recur for a persistent filesystem error.

Pros:

- File-open failures return a path-specific message.
- Character names are sanitized for Windows-invalid filename characters (`trusts.lua:918-920`).

Cons:

- Partial/truncated files can replace valid prior output.
- Success is reported even if buffered close/write failed.
- Retrying a permissions/disk failure on a spell-data packet does not address the cause and is operationally opaque.

Fix: render strings first, write each to a temporary file in the same directory, verify write/flush/close, then rename as a group as safely as the platform allows. Check directory creation. Separate “data not ready” retry from permanent I/O errors; expose the last failure in UI.

### R8 — Lifecycle readiness may flap during normal transitions and lacks zone-specific invalidation

Severity: **P2 / medium**

Evidence: `d3d_present` deactivates immediately whenever party slot zero is not active/server-ID-backed (`trusts.lua:2053-2056`). A temporary invalid party view during zoning can clear all state and trigger a fresh auto-export when it returns. Conversely, while `character_loaded` remains true, there is no packet handler to refresh learned Trusts/WS after job/data changes except packet `0x00AA` when `pending_export` is true (`trusts.lua:2041-2049`).

Pros:

- Actual logout clears stale state and prevents rendering against missing memory.
- Loading the addon while already logged in is supported.

Cons:

- One-frame memory transitions are treated as logout.
- Recommendation snapshots may become stale after acquiring a Trust/WS or changing relevant player state.
- State transition logic is split among load, packet, present, command, and unload callbacks.

Fix: use an explicit lifecycle state machine (`unloaded`, `waiting_for_character`, `waiting_for_resources`, `ready`, `zoning`) with a small debounce/grace period. Invalidate the relevant snapshot on documented spell/ability/job/zone events, and keep render callbacks side-effect-light.

### R9 — Greedy role ordering creates deterministic but structurally biased teams

Severity: **P2 / medium reliability/correctness**

Evidence: quotas are filled in the fixed UI role order tank, healer, support, melee, ranged, caster, special (`trusts.lua:1006-1014`, `1304-1312`). Each candidate's synergy is evaluated only against members already selected (`trusts.lua:1221-1263`). Thus an early locally-best tank can prevent a globally superior team, while later roles get the benefit of synergy information unavailable to earlier choices.

Pros:

- The algorithm is understandable, fast, deterministic, and honors role quotas when candidates exist.
- Alphabetical tie-breaking makes output stable (`trusts.lua:1287-1291`).

Cons:

- “Team score” is actually the incremental score at selection time, not a comparable final member contribution (`trusts.lua:1295`, `1800-1803`).
- Results depend on arbitrary role declaration order.
- No diagnostic is emitted when a requested role has no matching learned Trust.

Fix: for a five-member maximum, evaluate bounded combinations that satisfy quotas, or use beam search. Score complete teams symmetrically. Report unmet constraints and display total score plus per-feature explanations, not incremental greedy scores.

### R10 — The module retains obsolete concepts and duplicated sources of truth

Severity: **P3 / low-to-medium**

Evidence: `choose_trust` is unused (`trusts.lua:1319-1328`). `chain_mode` is calculated and stored but not displayed/used (`trusts.lua:1352-1380`). `CHAIN_FRIENDLY_WEAPON_SKILLS` exists only to feed that dead value (`trusts.lua:141-168`). `button_label` is accepted by `draw_team_block` but unused (`trusts.lua:644`). `TRUST_ROLE_PRIORITY` still assigns curated roles/scores/notes, while the newer behavior dataset separately assigns roles/performance; the old `score` and `note` fields are no longer used for team scoring (`trusts.lua:129-139`). Automatic-summon state is also obsolete (R2).

Pros:

- The code contains useful compatibility fallbacks for profiles absent from generated data.

Cons:

- Multiple datasets can disagree on roles and rankings.
- Dead code falsely implies supported behavior and raises regression risk.
- `trusts.lua` mixes D3D resources, generated-data adapters, filters, scoring, exports, lifecycle, commands, and five UI concerns in one file.

Fix: delete dead paths after confirming no external command compatibility requirement. Establish one canonical profile/capability schema and split into pure modules: `data_adapter`, `skillchain_graph`, `team_scorer`, `exporter`, `lifecycle`, and `ui`.

### R11 — There is no automated validation or regression harness

Severity: **P1 / high process risk**

Evidence: no tests or validation scripts are present under `addons/trusts`; the only tool is the BG Wiki generator. The large generated table, hand-curated supplements, directed graph, and scoring rules can regress independently. Prior user reports (method references displayed, D3D device crash, missing normalized Trust name, resize/summon failures) are exactly the class of defects unit fixtures could retain.

Pros:

- Core scoring functions are already mostly deterministic and could become testable with modest extraction.
- Data is represented declaratively, enabling schema tests.

Cons:

- Ashita global calls and UI code prevent loading the whole file in a plain Lua runner.
- There are no golden fixtures for the user's known-good lineup or lifecycle/UI regressions.

Fix: extract pure modules and add a lightweight Lua test harness. Minimum fixtures:

1. Name normalization: `Semih Lafihna` equals `Semihlafihna`; aliases remain unique.
2. Dataset schema: every action has string `name`/`kind`; lists are arrays; skillchain properties are known values; duplicate normalized names are rejected.
3. Directed chain table tests against authoritative combinations.
4. Team fixture: with Valaineral, Zeid II, Semih Lafihna, Qultada, and Apururu learned and five slots, the expected general-physical team ranks at or near the top.
5. Greedy/global-order counterexample test before replacing selection.
6. Settings fixtures: empty, old-version, corrupt scalar/table types, invalid enums/counts, removed preferred WS.
7. UI state test or minimal mocked ImGui test proving close sets `ui_visible=false` even when `Begin` returns false.
8. Lifecycle fixtures for pre-login, ready, zoning transient, logout, reload while logged in.
9. Export fault injection for create/open/write/close/rename failures and preservation of previous files.
10. Missing/corrupt Skillchains and missing XIUI fixtures with one-time diagnostics and graceful fallback.

## Prioritized remediation plan

1. **Fix main-window close propagation and remove the obsolete multi-summon commands/state.** These are direct user-facing regressions.
2. **Move automatic export out of `d3d_present`; avoid double recommendation builds.** Render should not synchronously write large files.
3. **Extract and test pure data normalization, skillchain graph, and whole-team scoring.** Add the known-good five-Trust golden fixture.
4. **Replace greedy role-ordered selection with bounded whole-team/beam evaluation and honest explanations.**
5. **Add versioned settings migration and schema validation for all three data sources.** Log dependency degradation once.
6. **Cache capabilities and team results; invalidate on explicit inputs rather than recomputing per frame.**
7. **Make exports atomic and distinguish transient readiness failures from permanent I/O failures.**
8. **Consolidate lifecycle into an explicit state machine with zoning tolerance.**
9. **Split the monolith and remove unused fields/functions.**

## Overall pros

- Defensive `rawget` use avoids T-table metatable method leakage in action metadata.
- Character readiness is checked before accessing learned spell/ability data.
- The coverage panel omits empty categories and tolerates missing icons.
- D3D textures use managed release semantics and are cleared on unload.
- Manual summoning is simple and matches the latest requested interaction.
- Selection is deterministic, bounded to five Trusts, and has stable tie-breaking.
- Missing exact Trust profiles degrade to a generic profile instead of crashing UI.

## Overall cons

- Render callbacks perform state transitions, expensive model reconstruction, and potentially heavy disk I/O.
- The obsolete automatic summoning path contradicts the current manual UI and user decision.
- Settings and external/generated datasets lack validation/version contracts.
- Export operations are partial/non-atomic.
- The greedy builder reports incremental scores as if they represented complete-team quality.
- One large source file and absent tests make each feature addition increasingly risky.

## Recommendation to the other reviewers

Any scoring/domain proposal should be accepted only if it also supplies deterministic fixtures and keeps the scoring engine pure. More behavior metadata alone will make the untested monolith harder to trust. The consensus should prioritize observability and reproducibility: show why a team won, preserve the user's known-good lineup as a golden scenario, and log when recommendations are degraded because Skillchains/profile data could not be loaded.
