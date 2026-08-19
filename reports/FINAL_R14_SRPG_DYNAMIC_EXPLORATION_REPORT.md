# R14 — SRPG Dynamic Exploration

## Implemented

- Fixed-tick, seeded `MapSimulation` separated from MapView.
- Selective enemy patrols with LOOP, PING_PONG, and GUARD_AREA modes.
- Awareness states, elevation/blocker line-of-sight, and non-debug danger feedback for route previews.
- WAIT pulse that advances patrols without moving the party.
- Encounter arbitration: only one hostile can own a contact transaction; battle begins only on actual contact.
- Relay discovery/activation, discovery expansion, intel, and safe active-relay fast travel.
- One-shot map events with two choices, shared reward resolution, and persistent exploration intel.
- Major/minor landmarks and minimap markers for active relays, known enemies, landmarks, and discovered treasure.
- Persisted map simulation, patrol, relay, event, intel, and exploration-completion state through save schema v5 migration.
- Camera-distance view streaming for map pawn rendering while logical patrol state continues deterministically.

## Verification

| Area | Result |
| --- | --- |
| R14 map simulation tests | 97 / 97 PASS |
| Static data validation | 60 / 60 PASS |
| Godot runtime validation | 92 / 92 PASS |
| Battle final/event hash regression | PASS |
| Actual local Web N02/N03 contact flow | PASS |
| Local Web reload state restoration | PASS |
| Browser console errors/warnings in checked flow | 0 / 0 |

## Scope retained

The existing real-time five-unit SD BattleSimulation, combat numbers, rewards, progression, and Web build target remain unchanged. R14 changes map exploration only.

## Review status

- Local Web implementation: **PASS for the checked contact, patrol wait, battle round-trip, and reload flow.**
- Full relay/event visual walk: **not claimed as completed**; deterministic coverage passes, while browser visual branch review remains scheduled.
- External GPT Web review: **waiting for browser action-time transmission confirmation.**
- Public deployment: **not performed.**
