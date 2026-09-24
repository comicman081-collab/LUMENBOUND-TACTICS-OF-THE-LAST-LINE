# Chapter finale progression and boss staging

The normal chapter finale now opens the next normal chapter and retains the current chapter's optional Hard route. A persisted, one-shot `campaign_transition` connects the results action to the departing chapter's queued story, then the next chapter introduction and map. CH01/CH02 outro triggers accept their normal finales as well as their historical Hard finale. The remaining chapters already used N20 for their outro.

Existing saves with an earned normal finale recover the missing unlock on load without invoking reward services. A missing handoff field identifies the legacy migration; an acknowledged empty handoff remains empty on subsequent loads and earlier-chapter replays. CH20 creates no nonexistent CH21 destination.

Boss wave entry now owns a 3.8-second presentation interval: the chamber crossfades beneath a dark aperture, the camera pulls back, the boss descends and lands, and Korean warning captions appear in safe-area letterbox bands. The battle timer and simulation stop at the exact spawning tick, independent of 1x/2x/3x speed. Existing BGM continues without a restart. Last-enemy destruction from the same spawn tick is retained while the chamber opens.

The environment and formation remain attached to the boss arena after its HP reaches zero. Following the enemy destruction and victory poses, a 1.8-second completion caption/fade leads into the normal saved result transaction. Explicit battle skip still computes the real result immediately. New encounters reset the presentation state.

The shared map-to-battle presentation now resolves event metadata from the selected stage's own chapter map, rather than implicitly reading CH01.

## Verification scope

- Dedicated model checks cover every normal chapter finale, optional Hard unlock, replay/idempotency, old-save recovery without reward changes, final-chapter bounds, same-tick destruction, simulation hold, pause, event-log preservation and view reuse.
- Browser checks use disposable saves, actual Release entry rules and a geared level-60 party to finish CH01-N20 through ordinary AUTO combat. No forced victory, wave seek or skip is used for the combat checks. Story skip uses the real UI controls to verify scenario order and navigation, not every individual dialogue line.
- Both 936×526 and 640×360 verify descent, landing, victory background, the result action, CH01 outro, CH02 intro and a selectable route on the next map. Runtime art, audio and layout are inspected in captured frames.
- The Release boot check verifies the player build without a developer command bridge and checks the normal map/audio startup.

This batch creates no new illustrations, voices or music and changes no resource prices. Historical audio and intro files remain protected during export/cache retirement.
