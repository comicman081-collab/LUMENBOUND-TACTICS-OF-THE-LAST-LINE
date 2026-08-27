# Release HARD attempt reset audit

Date: 2026-08-25 (KST)

## Static contract

`godot/autoload/app_state.gd` calls `reset_hard_attempts_if_needed()` before
stage-entry validation. The function compares `profile.hard_attempts.date`
with `Time.get_date_string_from_system()` and replaces the per-stage counts
with an empty map when the local date changes. HARD entries remain capped by
the authored `daily_attempts = 3` values in `data_source/stages.csv`.

## Actual Release evidence

- Release namespace: `hard-release-cert-r15`
- H02 authored entry cost: 12 operation power
- H02 was reached by physical multi-pulse movement and entered the existing
  real-time battle exactly once.
- The battle ended in a 20.83s defeat with zero survivors.
- Defeat granted no reward, kept the H02 hostile map pawn, restored the
  pre-contact map position, and survived browser reload → Continue → Home →
  HARD map.
- The entry counter reached `3/3`; this is consistent with the authored daily
  limit and blocked another same-day H02 entry.

## Verdict

`HARD_ATTEMPT_RESET_ACTUAL_WEB`: **UNVERIFIED**

The implementation has a date-change reset path, but a real browser check
across a local-date boundary has not been performed. No save edit, clock
change, developer override, or attempt reset was used to manufacture evidence.
H02 victory, H03, H04, H05, and H05 reload remain **UNVERIFIED** until a
legitimate reset permits a new Release attempt.
