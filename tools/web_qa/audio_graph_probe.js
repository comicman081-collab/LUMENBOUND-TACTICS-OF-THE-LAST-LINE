// Local QA only. Observe the signal reaching the original audio destination;
// never replace its routing, modify the source audio, or enable autoplay.
(() => {
  const q = window.__localAudioGraph = {samples: [], mixed: [], connections: [], states: []};
  const taps = [], seen = new WeakSet(), original = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (...args) {
    const result = original.apply(this, args);
    const destination = args[0];
    if (destination instanceof AudioDestinationNode && !seen.has(this)) {
      seen.add(this);
      const context = this.context, analyser = context.createAnalyser();
      analyser.fftSize = 2048;
      original.call(this, analyser);
      const index = taps.length;
      taps.push({context, analyser, data: new Float32Array(2048)});
      q.connections.push({index, node: this.constructor.name, sample_rate: context.sampleRate});
      const state = () => q.states.push({index, at: performance.now(), state: context.state, time: context.currentTime});
      context.addEventListener('statechange', state); state();
    }
    return result;
  };
  setInterval(() => {
    let totalPower = 0, peakSignal = 0;
    const running = [];
    for (const [index, tap] of taps.entries()) {
      tap.analyser.getFloatTimeDomainData(tap.data);
      let sum = 0, peak = 0;
      for (const value of tap.data) {sum += value * value; peak = Math.max(peak, Math.abs(value));}
      q.samples.push({index, at: performance.now(), phase: window.__gameplayQA?.phase,
        state: tap.context.state, time: tap.context.currentTime, rms: Math.sqrt(sum / tap.data.length), peak});
      totalPower += sum / tap.data.length; peakSignal = Math.max(peakSignal, peak);
      running.push(tap.context.state);
    }
    if (taps.length) q.mixed.push({at: performance.now(), phase: window.__gameplayQA?.phase,
      state: running.every(state => state === 'running') ? 'running' : running.join(','),
      rms: Math.sqrt(totalPower), peak: peakSignal});
  }, 100);
})();
