export function checkFullDensity(state, check) {
  const battle = state.battle, actors = battle?.signature?.full_density, fx = battle?.signature?.full_density_effects;
  check(battle?.ready && actors && !actors.error, 'Web battle has a settled error-free full-density actor lease');
  check(actors.decoded_rgba_bytes > 0 && actors.decoded_rgba_bytes <= actors.budget_bytes, 'actual decoded HD actors remain inside the measured stage budget');
  check(fx && !fx.error && fx.decoded_rgba_bytes > 0 && fx.decoded_rgba_bytes <= fx.budget_bytes, 'own HD projectile/skill/ultimate pages are resident within budget');
  for (const actor of battle.actors) {
    check(actors.entity_ids.includes(actor.id), `${actor.id} uses its own loaded HD actor pages`);
    for (const action of ['idle','move','basic_attack','normal_skill','ultimate','hit','down','victory']) {
      const t = actor.action_textures?.[action];
      check(t?.width === 256 && t?.height === 256, `${actor.id} ${action} retains a 256px source canvas`);
    }
    check(fx.projectile_ids.includes(actor.id) && ['basic','normal','ultimate'].every(kind=>fx.effect_keys.includes(actor.id.toLowerCase()+'_'+kind)), `${actor.id} own projectile and all three FX families are attached`);
  }
}
