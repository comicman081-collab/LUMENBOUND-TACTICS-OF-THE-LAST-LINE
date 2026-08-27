# Current R7 Web Release — N01 E2E evidence

Date: 2026-08-25

Target: `builds/web_release/` served locally at `127.0.0.1:8078` only.

Save isolation: `r15-save-sandbox=1`, session `mvp_goal_20260825`.  The
browser-side save audit recorded zero production path, read, write, backup and
reset attempts.

## Verified sequence

1. Title rendered in the Godot 4.7.1 Compatibility Web build.
2. A user gesture entered Home; character artwork rendered on the party card.
3. Chapter 1 intro completed into the long SRPG map.
4. N01 selection showed the stage detail panel and a physical route preview.
5. The 7/7 exploration movement pulse was exhausted before N01 contact.
6. `WAIT` refilled the movement pulse while retaining party position.
7. The next confirmed physical move contacted N01 and automatically entered
   the unchanged five-unit real-time SD battle.
8. N01 completed as victory: 15.47 seconds, five survivors.
9. The result screen displayed item-by-item gains and before/after inventory
   totals, then returned to the map.
10. The map showed N01 cleared and N02 newly unlocked.
11. Browser refresh followed by title/home/map re-entry restored N01 clear,
    N02 next encounter, 4% exploration, party position and 6/7 remaining
    movement.

## Console / media evidence

- WebGL 2.0 Compatibility initialized successfully.
- Console errors: 0.
- Console warnings: 0.
- Trusted gesture unlocked audio.
- `audio_bgm_lobby` verified streaming playback from the 89.94-second local
  authored WAV; failed-playback count was zero.

This is an actual browser N01 vertical-slice verification, not a claim that
the entire N01→N10/HARD route was browser-played in this pass.  No package was
uploaded or deployed.
