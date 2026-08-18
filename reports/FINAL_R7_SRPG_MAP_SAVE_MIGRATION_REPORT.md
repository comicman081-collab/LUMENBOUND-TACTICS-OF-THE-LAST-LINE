# Final R7 SRPG Map Save Migration Report

- Save schema: 2.
- Canonical position: axial integer q/r plus stable map/node IDs.
- Float Node3D world position is not saved.
- v1→v2 migration tested: PASS.
- Highest cleared NORMAL coordinate restoration: PASS.
- Cleared-node set restoration: PASS.
- Route reveal restoration: PASS.
- N10→HARD gate restoration: PASS.
- Existing stars/first clear/HARD attempts/pity preserved: PASS.
- Unknown node quarantined: PASS.
- Corrupt primary backup recovery: PASS in unchanged baseline suite.
- Atomic q/r save/load: PASS.
- Actual in-app browser refresh at q/r (2,0): PASS.

No old save was silently reset.
