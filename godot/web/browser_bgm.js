/* BGM runs on the browser audio rendering thread, independently of Godot frames. */
(() => {
  if (window.__lumenBGM) return;
  let context = null, master = null, sfxMaster = null, current = null, wanted = "", pending = "", sequence = 0;
  let level = 0.56, error = "", retryTimer = null;
  const cache = new Map(), nodes = new Set(), starts = {}, attempts = {}, failures = {};
  // Godot's WebAudio streaming voices can fail to re-open after a scene swap
  // even while the browser-owned BGM context remains healthy.  Keep combat
  // SFX in this same trusted context, with their own gain bus so the BGM and
  // SFX sliders still remain independent.
  let sfxLevel = 0.64, sfxError = "";
  const sfxCache = new Map(), sfxNodes = new Set(), sfxStarts = {}, sfxAttempts = {}, sfxFailures = {};
  // Story voice: one line at a time on its own gain bus. A scenario's compressed
  // files are prefetched when it opens; each line is decoded only when it plays.
  let voiceMaster = null, voiceLevel = 1, voiceError = "", voiceCurrent = null, voicePending = "", voiceSequence = 0;
  const voiceBytes = new Map(), voiceStarts = {}, voiceAttempts = {}, voiceFailures = {};
  const ensure = () => {
    if (!context) {
      context = new AudioContext({latencyHint: "playback"});
      master = context.createGain(); master.gain.value = level; master.connect(context.destination);
      sfxMaster = context.createGain(); sfxMaster.gain.value = sfxLevel; sfxMaster.connect(context.destination);
      voiceMaster = context.createGain(); voiceMaster.gain.value = voiceLevel; voiceMaster.connect(context.destination);
    }
    return context;
  };
  const unlock = () => {
    const ctx = ensure();
    if (ctx.state === "suspended") ctx.resume().catch(() => {});
  };
  for (const event of ["pointerdown", "touchstart", "keydown"])
    window.addEventListener(event, unlock, {capture: true, passive: true});
  const load = async (url) => {
    if (cache.has(url)) return cache.get(url);
    const promise = fetch(url).then(response => {
      if (!response.ok) throw new Error("BGM_HTTP_" + response.status);
      return response.arrayBuffer();
    }).then(bytes => ensure().decodeAudioData(bytes));
    cache.set(url, promise);
    try {
      const buffer = await promise;
      // Bound decoded residency; active AudioBufferSources retain their own buffers.
      while (cache.size > 3) cache.delete(cache.keys().next().value);
      return buffer;
    } catch (reason) { cache.delete(url); throw reason; }
  };
  const loadSfx = async (url) => {
    if (sfxCache.has(url)) return sfxCache.get(url);
    const promise = fetch(url).then(response => {
      if (!response.ok) throw new Error("SFX_HTTP_" + response.status);
      return response.arrayBuffer();
    }).then(bytes => ensure().decodeAudioData(bytes));
    sfxCache.set(url, promise);
    try {
      const buffer = await promise;
      // Retain recent combat effects for rapid attacks, but bound decoded
      // memory for longer map sessions.
      while (sfxCache.size > 20) sfxCache.delete(sfxCache.keys().next().value);
      return buffer;
    } catch (reason) { sfxCache.delete(url); throw reason; }
  };
  function stop() {
    sequence++; wanted = ""; pending = ""; current = null;
    clearTimeout(retryTimer); retryTimer = null;
    if (!context) return;
    const now = context.currentTime;
    for (const node of nodes) {
      node.gain.gain.cancelScheduledValues(now);
      node.gain.gain.setValueAtTime(node.gain.gain.value, now);
      node.gain.gain.linearRampToValueAtTime(0, now + 0.04);
      try { node.source.stop(now + 0.05); } catch (_) {}
    }
  }
  function play(id, path, loop = true, retry = 0, loopStart = 0, loopEnd = 0) {
    if (wanted === id && (pending === id || (current && current.id === id && !current.ended))) return false;
    const token = ++sequence;
    wanted = id; pending = id; error = "";
    clearTimeout(retryTimer); retryTimer = null;
    attempts[id] = (attempts[id] || 0) + 1;
    const url = new URL(path, location.href).href;
    load(url).then(async buffer => {
      if (token !== sequence) return;
      const ctx = ensure();
      if (ctx.state !== "running") await ctx.resume();
      if (token !== sequence) return;
      const start = ctx.currentTime + 0.025, fade = current ? 0.22 : 0.035;
      const source = ctx.createBufferSource(), gain = ctx.createGain();
      source.buffer = buffer; source.loop = loop;
      const end = loopEnd > loopStart ? Math.min(loopEnd, buffer.duration) : buffer.duration;
      const begin = Math.max(0, Math.min(loopStart, end - 0.01));
      source.loopStart = begin; source.loopEnd = end;
      source.connect(gain); gain.connect(master);
      gain.gain.setValueAtTime(0, start);
      gain.gain.linearRampToValueAtTime(1, start + fade);
      const node = {id, source, gain, start, duration: end - begin, sourceDuration: buffer.duration, begin, end, ended: false, loop};
      nodes.add(node);
      source.onended = () => {
        node.ended = true; source.disconnect(); gain.disconnect(); nodes.delete(node);
        if (current === node) current = null;
      };
      source.start(start, loop ? begin : 0);
      if (current) {
        const old = current;
        old.gain.gain.cancelScheduledValues(start);
        old.gain.gain.setValueAtTime(old.gain.gain.value, start);
        old.gain.gain.linearRampToValueAtTime(0, start + fade);
        try { old.source.stop(start + fade + 0.02); } catch (_) {}
      }
      current = node; pending = "";
      starts[id] = (starts[id] || 0) + 1;
    }).catch(reason => {
      if (token !== sequence) return;
      pending = ""; error = String(reason); failures[id] = (failures[id] || 0) + 1;
      // Keep the outgoing track while a replacement is unavailable.
      if (retry < 3) retryTimer = setTimeout(() => {
        if (token !== sequence || wanted !== id) return;
        wanted = ""; play(id, path, loop, retry + 1, loopStart, loopEnd);
      }, 2000 * (retry + 1));
    });
    return true;
  }
  function playSfx(id, path, gain = 1, pitch = 1) {
    const ctx = ensure();
    sfxAttempts[id] = (sfxAttempts[id] || 0) + 1;
    sfxError = "";
    const url = new URL(path, location.href).href;
    loadSfx(url).then(async buffer => {
      if (ctx.state !== "running") await ctx.resume();
      if (ctx.state !== "running") throw new Error("SFX_CONTEXT_" + ctx.state);
      const source = ctx.createBufferSource(), nodeGain = ctx.createGain();
      source.buffer = buffer;
      source.playbackRate.value = Math.max(0.01, Math.min(4, Number(pitch) || 1));
      nodeGain.gain.value = Math.max(0, Math.min(4, Number(gain) || 1));
      source.connect(nodeGain); nodeGain.connect(sfxMaster);
      const node = {id, source, gain: nodeGain, ended: false};
      sfxNodes.add(node);
      source.onended = () => {
        node.ended = true;
        try { source.disconnect(); nodeGain.disconnect(); } catch (_) {}
        sfxNodes.delete(node);
      };
      source.start(ctx.currentTime + 0.012);
      sfxStarts[id] = (sfxStarts[id] || 0) + 1;
    }).catch(reason => {
      sfxError = String(reason);
      sfxFailures[id] = (sfxFailures[id] || 0) + 1;
    });
    return true;
  }
  const fetchVoice = (url) => {
    if (voiceBytes.has(url)) return voiceBytes.get(url);
    const promise = fetch(url).then(response => {
      if (!response.ok) throw new Error("VOICE_HTTP_" + response.status);
      return response.arrayBuffer();
    });
    voiceBytes.set(url, promise);
    promise.catch(() => { if (voiceBytes.get(url) === promise) voiceBytes.delete(url); });
    while (voiceBytes.size > 64) voiceBytes.delete(voiceBytes.keys().next().value);
    return promise;
  };
  function stopVoice() {
    voiceSequence++; voicePending = "";
    const node = voiceCurrent; voiceCurrent = null;
    if (!node || !context) return;
    const now = context.currentTime;
    node.gain.gain.cancelScheduledValues(now);
    node.gain.gain.setValueAtTime(node.gain.gain.value, now);
    node.gain.gain.linearRampToValueAtTime(0, now + 0.03);
    try { node.source.stop(now + 0.04); } catch (_) {}
  }
  function playVoice(id, path) {
    stopVoice();
    const token = voiceSequence, ctx = ensure();
    voicePending = id; voiceError = "";
    voiceAttempts[id] = (voiceAttempts[id] || 0) + 1;
    const fail = reason => {
      if (token !== voiceSequence) return;
      voiceSequence++; voicePending = ""; voiceError = String(reason);
      voiceFailures[id] = (voiceFailures[id] || 0) + 1;
    };
    // A line that cannot start promptly is dropped rather than heard over a later one.
    setTimeout(() => { if (token === voiceSequence && voicePending === id) fail("VOICE_TIMEOUT"); }, 5000);
    fetchVoice(new URL(path, location.href).href)
      .then(bytes => ctx.decodeAudioData(bytes.slice(0)))
      .then(async buffer => {
        if (token !== voiceSequence) return;
        if (ctx.state !== "running") await ctx.resume();
        if (token !== voiceSequence) return;
        if (ctx.state !== "running") throw new Error("VOICE_CONTEXT_" + ctx.state);
        const source = ctx.createBufferSource(), gain = ctx.createGain();
        source.buffer = buffer; source.connect(gain); gain.connect(voiceMaster);
        const node = {id, source, gain, ended: false};
        source.onended = () => {
          node.ended = true;
          try { source.disconnect(); gain.disconnect(); } catch (_) {}
          if (voiceCurrent === node) voiceCurrent = null;
        };
        source.start(ctx.currentTime + 0.012);
        voiceCurrent = node; voicePending = "";
        voiceStarts[id] = (voiceStarts[id] || 0) + 1;
      }).catch(fail);
    return true;
  }
  window.__lumenBGM = {
    unlock, play, stop,
    volume(value) {
      level = Math.max(0, Math.min(1, Number(value)));
      if (master) master.gain.setTargetAtTime(level, context.currentTime, 0.02);
    },
    status() {
      const elapsed = current ? Math.max(0, context.currentTime - current.start) : 0;
      return {backend: "browser_audio_buffer", requested: wanted, current: current?.id || "",
        pending, active: !!current && !current.ended && context.state === "running" && context.currentTime >= current.start,
        position: current ? (current.loop ? elapsed % current.duration : elapsed) : 0,
        duration: current?.duration || 0, source_duration: current?.sourceDuration || 0,
        loop_start: current?.begin || 0, loop_end: current?.end || 0, context_state: context?.state || "uninitialized",
        context_time: context?.currentTime || 0, starts: {...starts}, attempts: {...attempts},
        failures: {...failures}, cached_tracks: cache.size, active_sources: nodes.size, error};
    },
    get context() { return context; },
    get output() { return master; }
  };
  window.__lumenSFX = {
    play: playSfx,
    volume(value) {
      sfxLevel = Math.max(0, Math.min(1, Number(value)));
      if (sfxMaster) sfxMaster.gain.setTargetAtTime(sfxLevel, context.currentTime, 0.02);
    },
    status() {
      return {backend: "browser_audio_buffer", active_sources: sfxNodes.size,
        starts: {...sfxStarts}, attempts: {...sfxAttempts}, failures: {...sfxFailures},
        cached_sounds: sfxCache.size, context_state: context?.state || "uninitialized", error: sfxError};
    }
  };
  window.__lumenVoice = {
    play: playVoice, stop: stopVoice,
    prefetch(paths) {
      for (const path of paths || []) fetchVoice(new URL(path, location.href).href).catch(() => {});
      return true;
    },
    busy() { return !!voicePending || (!!voiceCurrent && !voiceCurrent.ended); },
    volume(value) {
      voiceLevel = Math.max(0, Math.min(1, Number(value)));
      if (voiceMaster) voiceMaster.gain.setTargetAtTime(voiceLevel, context.currentTime, 0.02);
    },
    status() {
      return {backend: "browser_audio_buffer", current: voiceCurrent?.id || "", pending: voicePending,
        active: !!voiceCurrent && !voiceCurrent.ended, starts: {...voiceStarts}, attempts: {...voiceAttempts},
        failures: {...voiceFailures}, cached_lines: voiceBytes.size,
        context_state: context?.state || "uninitialized", error: voiceError};
    }
  };
})();
