# Trusts Addon — Consensus Implementation Plan

Date: 2026-08-03  
Starting version: `1.8.0`  
Source: `reviews/CONSENSUS.md`

## Objective

Turn the current advisory heuristic into a stable, explainable, situation-aware team recommender without disrupting existing Trust browsing, filtering, coverage icons, or manual summoning.

The implementation is split into independently releasable milestones. Each milestone must pass its exit criteria before work begins on the next one.

## Guiding constraints

- Keep manual per-Trust summon buttons; do not restore automatic team summoning.
- Do not add more name-specific score tuning until the pure evaluator and tests exist.
- Do not run recommendation search, exports, or settings writes every render frame.
- Keep scraped facts separate from editorial estimates and preset weights.
- Treat missing information as unknown, not zero or poor performance.
- Keep the scorer independent of Ashita memory, ImGui, filesystem access, clocks, and global mutable state.
- Every score-changing rule must have a stable ID, explanation, confidence, and deterministic fixture.

---

## Milestone 1 — Stabilization release

Target version: `1.8.1`

### 1.1 Remove obsolete automatic summoning

Delete:

- `queue_summon_team`;
- `summon_in_progress`, `summon_progress`, and `summon_queue_id`;
- coroutine/task scheduling for Trust teams;
- `/trusts summon` and `/trusts beast` execution paths;
- obsolete command help and messages;
- unused button-label parameters related to team summoning.

Retain:

- `summon_single_trust`;
- individual Summon buttons in every suggested-team list.

Compatibility behavior: old batch commands should print a concise migration message directing the user to the manual buttons rather than silently doing nothing.

### 1.2 Fix main-window close state

Move propagation of `visible[1]` outside the conditional body returned by `imgui.Begin`. Closing the window must leave it hidden until `/trusts ui` reopens it.

### 1.3 Stop render-time side effects

Refactor character activation so `d3d_present` only:

- observes readiness;
- renders already prepared state;
- marks a refresh revision when inputs change.

It must not:

- export files;
- rebuild the model twice;
- retry failed I/O continuously.

Automatic export on login should be removed unless explicitly configured later. Export remains an explicit UI/command action.

### 1.4 Add basic settings migration

Add `settings_version` and one migration function.

Validate and normalize:

- maximum Trust count: 1–5;
- role quotas: integer and nonnegative;
- selected situation enum;
- preferred WS still present;
- overlay visibility and positions;
- stale fields from removed batch summoning.

Do not silently resolve quotas exceeding capacity using role display order. Mark the configuration invalid and show the user what must change.

### 1.5 Add dependency diagnostics

Expose a one-time status for:

- Skillchains data loaded/missing/invalid;
- Trust profile count;
- behavior-data count;
- supplemental profiles loaded;
- XIUI element/SC icon availability.

SC ranking must be visibly disabled if the directed graph is unavailable.

### Milestone 1 tests

- Closing the main window persists.
- `/trusts ui` reopens it.
- Every manual summon button issues exactly one `/ma` command.
- Batch commands issue no casts.
- Login and zoning do not export files.
- Corrupt/old settings migrate deterministically.
- Missing Skillchains data does not crash the addon.

### Milestone 1 exit criteria

- No automatic summon state remains.
- No file export or recommendation calculation is initiated from normal render work.
- Current browsing, filtering, icons, overlay, and manual summon features still work in Ashita.

---

## Milestone 2 — Module boundaries and canonical data contract

Target version: `1.9.0`

### 2.1 Proposed module structure

```text
addons/trusts/
  trusts.lua                         Ashita lifecycle, commands, top-level UI
  model/
    schema.lua                       versions, validation, canonical enums
    data_adapter.lua                 generated/supplement/behavior merging
    skillchain_graph.lua             canonical directed SC rules
    capability_compiler.lua          raw facts -> normalized capabilities
    player_context.lua               immutable player/config snapshot
    evaluator.lua                    pure whole-team evaluation
    optimizer.lua                    team search and alternatives
    explanations.lua                 score-ledger text formatting
  ui/
    main.lua
    team_builder.lua
    trust_browser.lua
    coverage_overlay.lua
  data/
    trust_profiles.lua               generated action facts
    trust_profile_supplements.lua
    trust_behavior.lua               temporary curated source
    recommendation_facts.lua         new canonical curated facts
    presets.lua                      weights and coverage requirements
  tests/
    run.lua
    fixtures/
```

Do not split everything mechanically in one patch. Extract pure data/scoring modules first, then move UI sections after characterization tests are passing.

### 2.2 Canonical Trust identity

Use the Trust spell/resource ID as the primary key where available.

Store:

- canonical ID;
- canonical display name;
- normalized aliases, including live entity/log forms;
- variant/Unity identity;
- generated action profile;
- supplemental facts;
- behavior facts;
- source and confidence metadata.

All profile and behavior lookup must go through this canonical index. Remove independent alias matching from separate subsystems after migration.

### 2.3 Versioned schema

Top-level metadata:

```lua
schema_version
generator_version
generated_at
source_url
source_revision
```

Per factual field:

```lua
value
source
retrieved_at
confidence = 'verified' | 'documented' | 'observed' | 'estimated' | 'unknown'
```

Separate:

- scraped facts;
- editorial capability estimates;
- recommendation weights.

Never execute expressions contained in generated data.

### 2.4 Split element domains

Replace ambiguous `team_builder.elements` with:

- `ws_damage_elements`;
- `sc_result_elements`.

Action schema must distinguish:

- `damage_type`;
- `damage_element`;
- ordered `skillchain_properties`.

Migration policy: clear old ambiguous selections and show a one-time notice.

UI labels:

- Direct WS Damage Element
- Desired SC / Burst Element

Each BEST FIT marker must use the same calculation as its control.

### 2.5 Compile normalized capabilities once

Compile and cache by `data_version`:

- functional coverage;
- per-action facts;
- per-WS records;
- buffs/debuffs;
- AI policy categories;
- positioning;
- dependencies;
- AoE risk;
- confidence/completeness.

Do not rescan all Trust actions while drawing Team Builder.

### Milestone 2 tests

- Every learned Trust resolves to one canonical identity.
- `Semihlafihna` resolves to Semih Lafihna.
- Unity variants do not inherit another variant's behavior accidentally.
- Direct Fire WS selection never scores a physical Darkness-property WS as Fire damage.
- Desired Fire SC selection scores only executable chains whose result contains Fire.
- Invalid records are quarantined and counted.
- Compiled capability output is deterministic.

### Milestone 2 exit criteria

- `trusts.lua` no longer owns scoring tables or directed SC rules.
- The merged data adapter produces a validated immutable roster.
- Direct damage and SC-result element concepts are separate end to end.

---

## Milestone 3 — Pure evaluator and explanation ledger

Target version: `2.0.0-alpha.1`

### 3.1 Immutable context snapshot

Define a plain Lua context value containing:

- maximum Trust slots;
- player job and selected functional role;
- one to three pinned WS;
- player SC policy: opens, closes, or either;
- situation preset;
- enemy count category;
- AoE tolerance;
- required functional coverage;
- direct WS damage-element preferences;
- desired SC/burst elements;
- owned Trust IDs;
- explicit selected/detected/unknown state for every contextual field.

No Ashita memory objects may cross this boundary.

### 3.2 Functional capability model

Replace optimization by exclusive role with normalized dimensions such as:

- enmity;
- mitigation;
- enmity recovery;
- sustained healing;
- emergency healing;
- AoE healing;
- status removal;
- physical/ranged/magical offense;
- attack/accuracy/haste/refresh support;
- dispel and interrupt;
- SC opening/closing control;
- positioning safety;
- AoE risk.

Keep familiar roles as derived display labels only.

Coverage rules may be nonlinear. Examples:

- require one adequate primary healer rather than summing two weak healers;
- cap Haste/support benefit;
- treat backup healing as resilience, not full replacement;
- do not double-count one capability as both a hard requirement and uncapped bonus.

### 3.3 Per-WS policy model

For relevant Trust WS actions store:

- ordered SC properties;
- minimum level;
- TP behavior;
- AI choice category;
- opener/closer tendency;
- AoE risk;
- usage conditions;
- qualitative reliability;
- source/confidence.

Use categorical reliability initially. Numeric probabilities are explicitly out of scope.

### 3.4 Pure team evaluator

API:

```lua
result = evaluator.evaluate_team(team, context, compiled_data)
```

Result:

```lua
{
    eligible = boolean,
    unmet_requirements = {},
    total = number,
    band = 'excellent' | 'good' | 'viable' | 'poor',
    categories = {},
    ledger = {},
    primary_sc_plan = nil | {},
    fallback_sc_plan = nil | {},
    confidence = {},
    warnings = {},
}
```

Every ledger entry contains:

- stable rule ID;
- category;
- delta;
- involved Trust IDs;
- confidence;
- concise explanation.

Ledger totals must equal category and final totals within tolerance.

### 3.5 Executable SC plans

Evaluate individual WS paths, not flattened property sets.

Primary path score considers:

- direction;
- selected player WS;
- actor policy compatibility;
- TP/readiness tier;
- chain level/result;
- desired burst element;
- closer collision;
- magic-burst follow-through.

Add one discounted fallback path for resilience. Do not sum the best path from every party pair.

### 3.6 Missing-data policy

- Unknown value remains unknown.
- Role/job/action-derived estimates produce ranges with `estimated` confidence.
- Confidence is displayed separately from comparative value.
- Unknown candidates can appear in an uncertain alternative.
- Do not apply a universal uncertainty penalty that guarantees curated names win.

### Milestone 3 tests

- Evaluator output is invariant to team-member order.
- Ledger total reconciliation passes.
- Zeid II healer dependency is team-order independent.
- Support caps and redundancy behave deterministically.
- Nonreciprocal SC direction tests pass.
- Exclusive closer beats theoretical broad coverage in the correct fixture.
- Multiple autonomous closers incur collision risk.
- Unknown data produces a warning/range, not base-score punishment.
- The known five-Trust lineup receives the expected rule IDs in General Physical context.
- It loses appropriate value under Avoid AoE or incompatible player context.

### Milestone 3 exit criteria

- The existing greedy builder can call the pure evaluator temporarily, but all displayed scores come from final completed-team evaluation.
- UI explanations are generated from the evaluator ledger, not independently reconstructed strings.
- No recommendation rule depends on name-specific base scores.

---

## Milestone 4 — Whole-team optimizer and alternatives

Target version: `2.0.0-beta.1`

### 4.1 Search strategy

Implement in stages:

1. Exact combination search for small fixture rosters.
2. Feasibility pruning using ownership and hard coverage possibility.
3. Deterministic beam search or branch-and-bound for normal rosters.
4. Compare approximate results with exact results on bounded fixtures.

Search complete teams, not ordered additions.

Do not use fixed role-display order as a priority. If requested constraints cannot fit within maximum slots, report infeasibility and require the user to revise them.

### 4.2 Alternative selection

Produce:

- Balanced;
- Aggressive / Skillchain;
- Safe / Counter.

All must satisfy hard user constraints. Add an explicit diversity rule so alternatives are not one-member permutations without meaningful category differences.

### 4.3 Revision cache

Cache compiled capabilities, context evaluation, and search results by:

```text
model_version
data_version
roster_revision
player_context_revision
settings_revision
```

Recompute only on invalidation. Never search from `d3d_present` simply because a tab is visible.

If work is scheduled, include the requested revision and discard stale completion results.

### 4.4 UI presentation

For each alternative show:

- Trust list and manual Summon buttons;
- rating band and confidence;
- category bars or compact values;
- primary SC path;
- one-sentence advantage;
- one-sentence sacrifice;
- expandable ledger;
- closest excluded alternative and why it lost.

Avoid decimal precision beyond what the model supports.

### Milestone 4 tests and benchmarks

- Candidate and role input permutation invariance.
- Exact versus beam result agreement on small cases.
- Delayed-synergy counterexample defeats greedy output.
- Hybrid candidate survives pruning.
- Top alternatives meet diversity constraints.
- Cached and uncached results are identical.
- No visible per-frame recomputation.
- Search remains within the agreed frame-time/latency budget for a full learned roster.

### Milestone 4 exit criteria

- Ordered greedy construction is deleted.
- Every shown recommendation is a final-team evaluation.
- Search results are cached and reproducible from exported context/data revisions.

---

## Milestone 5 — Context adapters and research expansion

Target version: `2.0.0`

### 5.1 Player-context UI

Add compact inputs:

- player role;
- pinned WS list;
- Trust opens/closes/either;
- enemy count;
- AoE tolerance;
- sustain/status/dispel requirements.

Use job only as a suggested default. Never force role from job.

### 5.2 Narrow equipment-aware Auto

Implement after manual pins are stable:

- inspect stable equipment snapshots outside render;
- map current weapon family to relevant WS;
- account for level sync where reliably available;
- debounce gear changes;
- label detection and fallback state in UI.

Pinned WS remains authoritative.

### 5.3 Behavior research workflow

Prioritize strategically distinct and commonly used Trusts rather than shallow coverage of every Trust.

For each researched fact record:

- source URL;
- retrieved date;
- source type;
- confidence;
- exact claim;
- applicable level/conditions;
- reviewer note where interpretation was required.

Update the BG Wiki generator so curated behavior and supplemental facts survive regeneration and validation.

### 5.4 Export hardening

Export only on explicit request.

Write a complete generation with:

- model/data/config versions;
- immutable context snapshot;
- ranked alternatives;
- score ledgers;
- data-degradation warnings;
- manifest identifying the active complete generation.

Use temporary generation files and switch the manifest only after every file succeeds.

### 5.5 Deferred telemetry boundary

Do not implement in the initial `2.0.0` unless all previous milestones are stable.

Future telemetry requirements:

- explicit opt-in;
- local bounded aggregates;
- contextual sample buckets;
- visible sample counts/confidence;
- batched writes;
- no automatic rewriting of factual behavior;
- no raw-log retention by default.

### Milestone 5 exit criteria

- Context assumptions are visible and reproducible.
- Pinned WS works independently of equipment detection.
- Common competitive Trusts have cited categorical behavior data.
- Exported recommendations can reproduce the UI result offline.

---

## Test harness plan

Because Ashita runtime objects are difficult to execute headlessly, split testing into two layers.

### Pure Lua tests

Cover:

- schema validation;
- canonical name/ID resolution;
- capability compilation;
- directed SC graph;
- evaluator ledgers;
- hard coverage;
- optimizer invariance;
- settings migration;
- cache-key determinism.

Provide a small runner that can use LuaJIT/Ashita's Lua environment when available.

### Ashita integration checklist

Run manually for each release:

- load before login;
- load while logged in;
- logout/login;
- zone transition;
- job change;
- level sync;
- missing Skillchains addon/data;
- missing XIUI icons;
- corrupt settings;
- window close/reopen;
- resize persistence;
- summoned-Trust coverage detection;
- individual summon buttons;
- explicit export failure and success.

## Release and rollback strategy

- Commit each milestone separately.
- Preserve `1.8.0` behavior behind no compatibility flag; fixes should replace broken semantics rather than maintain two scorers.
- Keep generated data changes separate from engine changes where possible.
- Before deleting the old scorer, save its fixtures as characterization tests.
- Do not migrate settings destructively without a versioned backup or one-time diagnostic.
- If the new optimizer fails validation, fall back to browsing/manual selection—not to silently using stale or invalid rankings.

## Definition of done for Trusts 2.0

- Direct WS and SC/burst element semantics are distinct and correct.
- Recommendation scoring is pure, deterministic, order-independent, versioned, and cached.
- Unknown behavior is visible as uncertainty.
- Individual WS policy and directed primary/fallback SC paths drive SC value.
- Teams are optimized as complete sets.
- Three meaningful alternatives are shown with sacrifices and confidence.
- The user's known lineup is a passing contextual regression fixture and loses in appropriate counter-fixtures.
- No recommendation/export/settings work runs continuously from rendering.
- Manual summoning, Trust browsing, filtering, and coverage overlay remain functional.
- All pure fixtures pass and the Ashita integration checklist is completed.
