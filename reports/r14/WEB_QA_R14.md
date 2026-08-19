# R14 Dynamic Exploration — Local Web QA

Date: 2026-08-19 (KST)  
Target: local Web release served at `http://127.0.0.1:8078/index.html?build=r7`

## Verified in the Codex in-app browser

1. Title → Home → Chapter 1 map rendered with Korean text and no console error/warning.
2. Cleared N01 state was restored from the browser save; N02 could be selected as a hostile map encounter.
3. The selected route was drawn, the squad travelled the route, then contact opened the unchanged real-time SD battle for `CH01-N02`.
4. The returned map advanced to N03. N03 patrol was allowed to move through one WAIT pulse, then the new encounter route was selected.
5. N03 route travel opened the unchanged real-time SD battle. Its result advanced the map to N04.
6. Browser reload restored the persisted Chapter 1 map and party position with N04 as the next encounter.
7. Browser console: **0 errors, 0 warnings** during the checked flow.

## Captured evidence

- `screenshots/01_PATROL_ENEMY.png`
- `screenshots/03_DANGEROUS_ROUTE.png`
- `screenshots/04_WAIT_BEFORE.png`
- `screenshots/04_WAIT_AFTER_PATROL_MOVE.png`
- `screenshots/13_CONTACT_BATTLE.png`
- `screenshots/16_RELOAD_RESTORED.png`

The screenshots are locally retained review evidence and are intentionally excluded from Git and release payloads.

## Remaining browser review scope

The live save used for this run had already progressed through N01–N03. Relay and event interaction logic is fully exercised in the deterministic 97-test map suite, but an end-to-end browser walk to every relay/event branch was not claimed as visually verified in this report. It remains available for the next local browser pass without a publish.

## External GPT review

No external ChatGPT message was sent in this pass. Browser policy requires a final action-time confirmation before transmitting screenshots or a review request to an external chat, even when collaboration has been preapproved earlier in the project.
