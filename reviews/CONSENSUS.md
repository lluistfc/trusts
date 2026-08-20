# Trusts Addon Review — Final Consensus

Date: 2026-08-03  
Reviewed version: Trusts `1.8.0`

Participants:

1. FFXI gameplay-systems reviewer
2. Ashita/Lua reliability reviewer
3. Quantitative ranking/optimization reviewer

This consensus is based on three independent first-round reviews followed by a circular cross-review. No addon code was changed during this audit.

## Consensus verdict

The addon has moved in the right direction: it enumerates the learned roster, represents directed skillchain relationships, exposes situations and preferred WS input, and attempts to score party synergy rather than isolated Trust names.

It is not yet reliable enough to describe its output as the "best" team. Its main weaknesses are architectural rather than numeric:

- the UI conflates direct WS damage elements with skillchain-result/burst elements;
- only a small curated subset has behavior data, so missing data is treated as poor performance;
- ordered greedy selection cannot optimize conditional whole-team synergy;
- Trust WS properties are flattened into an optimistic capability set without enough AI-policy context;
- heterogeneous hand-authored score scales have no common interpretation;
- the scorer and search are recomputed from the render path and remain coupled to a 2,000+ line Ashita/UI module;
- deterministic fixtures do not exist, so recommendation changes cannot be proven improvements.

The three reviewers agree that adding more isolated base-score tuning now would make the output look more precise without making it more truthful.

## Unanimous strengths

- Directed opener/closer lookup is a sound foundation.
- Separating action-derived capabilities from curated behavior is directionally correct.
- Manual preferred-WS selection is valuable.
- Situation presets are understandable and useful as explicit context.
- Modeling healer dependencies and support amplification is the correct type of party-level logic.
- Manual per-Trust summon controls match the requested interaction and should remain.
- The Valaineral / Zeid II / Semih Lafihna / Qultada / Apururu party is a valuable regression scenario when the context is explicitly physical, five-slot, and skillchain-friendly.

## Consensus P0 — Immediate correctness and stability

### 1. Split the two element concepts

Current behavior:

- Gold BEST FIT elements are derived from elements of possible skillchain results.
- Selecting an element rewards Trusts with a direct magical/hybrid WS of that element.

These are different questions presented as one control.

Required replacement:

- `Direct WS damage element`
- `Desired SC / magic-burst element`

Each control must calculate and display its own matching indicator. Existing ambiguous saved selections should be cleared during a versioned settings migration with a one-time notice rather than guessed.

### 2. Fix direct runtime defects

- Copy the mutable main-window visibility flag after `imgui.Begin` even when the window body is not open, so the close button persists.
- Delete the obsolete automatic multi-summon commands, coroutine, progress state, and command help. They conflict with the accepted manual-summon design and have already failed in game.
- Stop performing automatic export and duplicate recommendation work through `d3d_present` activation polling.
- Do not repeatedly retry permanent export failures on unrelated incoming packets.

### 3. Add versioned boundary validation

Validate:

- settings schema and enum values;
- preferred WS still present in the current learned/usable list;
- role/coverage constraints against maximum slots;
- behavior/profile schema versions;
- skillchain graph availability and canonical property names;
- generated and supplemental profile records.

Invalid optional records should be quarantined with a visible degraded-data warning. A broken core skillchain graph should disable SC ranking rather than silently assigning zero value.

## Consensus P0 — Trustworthy recommendation core

### 4. Extract a pure evaluator

Create modules with no Ashita, ImGui, filesystem, clock, or mutable settings dependencies:

```text
data_adapter
  -> capability_compiler
  -> player/context snapshot
  -> evaluate_team(team, context)
  -> optimizer
  -> structured result
```

`evaluate_team` must be order-independent and return:

- hard coverage results;
- normalized category ratings;
- team-level synergy and conflict rules;
- confidence/degraded-data state;
- a score ledger with stable rule IDs;
- exact directed SC plan evidence;
- model, data, and configuration versions.

The UI must only render results and record user choices.

### 5. Treat missing data as uncertainty, not weakness

The curated behavior table covers roughly one fifth of the generated roster. An unmapped Trust currently starts far behind a curated Trust because it receives an empty behavior record and a universal base score of 50.

Required policy:

- distinguish unknown from zero;
- attach provenance and confidence to individual facts;
- use role/action-informed neutral ranges only as estimates;
- label uncertain candidates explicitly;
- do not multiply confidence into value in a way that recreates the same automatic penalty;
- keep factual behavior, editorial capability estimates, and preset weights separate.

One stable Trust identity should join action profiles, aliases, behavior, supplements, and ownership data.

### 6. Preserve per-WS action identity

Do not collapse every Trust WS into one property set. Each WS record should retain:

- ordered SC properties;
- level availability;
- direct damage type and damage element;
- AoE shape/risk;
- TP threshold or hold behavior;
- qualitative AI use policy;
- conditions and priority;
- provenance and confidence.

Start with qualitative behavior tiers such as `exclusive`, `holds_for_chain`, `prefers_open`, `prefers_close`, and `free`. Do not invent precise probabilities.

### 7. Normalize scoring and separate constraints from preferences

- Represent capabilities on documented bounded scales.
- Put preset weights in a separate versioned configuration.
- Divide a fixed preference budget among multiple selected elements/properties instead of awarding a full bonus for every checkbox.
- Treat mandatory sustain, tanking, dispel, or status removal as thresholds where appropriate; do not let unrelated offense numerically compensate for a fatal gap.
- Apply explicit deterministic tie handling and show bands for near-equal results.

## Consensus P0 — Whole-team optimization

### 8. Replace ordered greedy construction

Role order must not decide which requirements survive when quotas exceed party capacity. Candidate input order must not affect the result.

Use a bounded complete-team method:

- exact enumeration for small fixture rosters;
- beam search or role-aware branch-and-bound for normal owned rosters;
- safe feasibility pruning before score-based pruning;
- deterministic ordering and tie-breaking;
- all constraints evaluated jointly at team completion.

Search must run only when a versioned input snapshot changes, never every render frame.

### 9. Score executable chain plans, not all theoretical pairs

Choose:

- one primary directed SC plan;
- one discounted fallback plan.

Account for:

- player opens versus Trust opens;
- selected/pinned player WS;
- Trust opener/closer policy;
- TP/readiness and timing category;
- WS choice policy;
- closer collision risk;
- backup-closer resilience;
- burst follow-through where requested.

A two-actor sequence cannot use the current maximum reliability of either actor. Use conservative conditional reliability categories until measured evidence exists.

### 10. Replace exclusive role labels with functional coverage

Keep Tank/Healer/Support/Melee/Ranged/Caster labels for navigation, but optimize named functions:

- enmity generation and recovery;
- mitigation;
- sustained and emergency healing;
- AoE healing;
- status removal;
- haste/refresh/attack/accuracy support;
- physical, ranged, and magical damage;
- interrupts and dispels;
- positioning and AoE risk.

Coverage is nonlinear: two weak emergency healers do not necessarily equal one reliable primary healer.

## Consensus P1 — Context and output quality

### 11. Make player intent explicit

Implement first:

- player role selector with a job-derived suggestion;
- one to three pinned WS choices;
- `Trust opens`, `Trust closes`, or `Either`;
- encounter size and AoE tolerance;
- required tank/healing/dispel/status coverage.

Equipment-aware Auto detection can follow through a debounced adapter. Every context value should be labeled selected, detected, or unknown. Broad automatic encounter detection is deferred.

### 12. Return diverse alternatives

Return three constrained, meaningfully different options:

- Balanced
- Aggressive / Skillchain
- Safe / Counter

For each, show one sentence describing the sacrifice. Expanded details should show category ratings, primary SC path, confidence, risks, and the closest excluded alternative.

### 13. Cache by explicit revisions

Recommended cache key inputs:

```text
model version
data version
roster revision
player/equipment revision
context revision
settings revision
```

Scheduled calculations must carry a revision and may not overwrite newer results. Cached and uncached outputs must be identical in tests.

## Consensus P1 — Tests and operational hardening

### Required deterministic fixtures

1. Known physical five-slot lineup ranks in the expected top tier and receives the correct synergy ledger.
2. The same lineup loses or changes under Avoid AoE where appropriate.
3. A healer player's context reduces redundant dedicated-healer value.
4. Zeid II's value changes correctly with and without adequate healing.
5. Reversing a nonreciprocal SC changes feasibility.
6. An exclusive reliable WS user outranks a broad theoretical property set when the relevant behavior warrants it.
7. Multiple closers incur collision risk but a fallback closer retains discounted value.
8. Unknown behavior is displayed as uncertainty, not silently scored as bad.
9. Team output is invariant to candidate and role display order.
10. Beam/branch results match exact enumeration on small rosters.
11. Direct WS element and SC-result element controls never cross domains.
12. Invalid settings, missing Skillchains data, corrupt profiles, zoning, logout, and UI close behavior degrade safely.

### Operational fixes

- Make exports explicit, revisioned, and atomic via generation files plus a manifest/pointer.
- Save settings on commit/debounce rather than every small UI change.
- Add a minimal character/data-ready state model with zoning tolerance.
- Compile static Trust capabilities once per data version.
- Remove unused hardcoded role priorities, legacy `chain_mode`, automatic summon code, and other duplicate sources of truth after characterization tests exist.

## Accepted with qualifications

- **Role capability vectors:** accepted, but functions and thresholds must be nonlinear and contextual rather than naively additive fractions.
- **Reliability multiplication:** accepted in principle, but use conditional direction/readiness logic, not independent-event multiplication.
- **Equipped weapon detection:** useful Auto default, never authoritative over pinned WS.
- **Coverage target:** broad coverage is necessary, but a rigid 90% headline is rejected; measure depth, provenance, and strategically relevant coverage.
- **Candidate pruning:** necessary for performance, but must preserve hybrids and low-individual/high-synergy candidates.

## Deferred or rejected

- Do not add more arbitrary name-specific base tuning before the model contract is repaired.
- Do not claim algorithmic optimality can compensate for missing behavioral facts.
- Do not invent precise WS-use probabilities from prose observations.
- Do not implement broad automatic encounter detection in the first redesign.
- Defer combat-log telemetry until schema, pure scoring, caching, tests, and lifecycle are stable.
- Future telemetry must be local, opt-in, bounded, contextual, and advisory; it must not silently rewrite factual behavior.
- Do not encode the user's known lineup as a universal rank-one answer. It is a context-specific benchmark and should lose in suitable counter-scenarios.

## Agreed implementation sequence

### Milestone 1 — Stabilize

Fix element semantics, close-state handling, obsolete summoning, render-time exports, settings migration, and dependency diagnostics.

### Milestone 2 — Establish the model contract

Create the versioned canonical schema, per-fact provenance/confidence, immutable context snapshots, pure capability compiler, pure whole-team evaluator, and score ledger.

### Milestone 3 — Prove the evaluator

Add golden and adversarial fixtures, normalization, per-WS policy, functional coverage, directed primary/fallback SC plans, and permutation invariance.

### Milestone 4 — Optimize and cache

Introduce bounded whole-team search, diverse alternatives, revision-based caching, and frame-time budgets.

### Milestone 5 — Expand knowledge

Research and cite behavior for strategically important Trusts, add narrow equipment/context adapters, improve export diagnostics, and only then consider optional telemetry.

## Final consensus

The next code change should be a stabilization and extraction pass, not another tuning pass. The target architecture is a small Ashita adapter around a validated, deterministic, cached recommendation engine. Once the same pure evaluator can explain why the known five-Trust team succeeds—and why it should lose under a different explicit context—the addon will have a defensible basis for deeper Trust research and calibration.
