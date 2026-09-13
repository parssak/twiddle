const dial = document.querySelector('.dial');
const arc = document.querySelector('.dial-arc');
const ticks = document.querySelector('.dial-ticks');
const readout = document.querySelector('.dial-readout');
const panel = document.querySelector('.audio-flow');
let value = -35;
let drag = null;

function point(degrees, radius) {
  const angle = (degrees - 90) * Math.PI / 180;
  return [120 + Math.cos(angle) * radius, 120 + Math.sin(angle) * radius];
}

for (let i = -10; i <= 10; i++) {
  const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  const start = point(i * 13.5, 109);
  const end = point(i * 13.5, i === 0 ? 117 : 113);
  ['x1', 'y1', 'x2', 'y2'].forEach((key, j) => line.setAttribute(key, [...start, ...end][j]));
  ticks.append(line);
}

function update(next) {
  value = Math.max(-100, Math.min(100, Math.round(next)));
  const degrees = value * 1.35;
  const end = point(degrees, 98);
  dial.style.setProperty('--angle', `${degrees}deg`);
  arc.setAttribute('d', value === 0 ? '' : `M120 22 A98 98 0 0 ${value > 0 ? 1 : 0} ${end.join(' ')}`);
  panel.style.setProperty('--accent', value === 0 ? '#aaa' : '#ff8b34');
  [...ticks.children].forEach((tick, i) => {
    const tickValue = (i - 10) * 10;
    const swept = value !== 0 && (value < 0 ? tickValue <= 0 && tickValue >= value : tickValue >= 0 && tickValue <= value);
    tick.style.stroke = swept ? '#ff8b34' : i === 10 ? '#ddd' : '#656565';
  });
  const amount = Math.abs(value) / 100;
  const frequency = Math.round(value < 0 ? 20000 * Math.pow(115 / 20000, amount) : 20 * Math.pow(10000 / 20, amount));
  const label = value === 0 ? 'Bypass · Original audio' : `${value < 0 ? 'Low-pass' : 'High-pass'} · ${frequency.toLocaleString('en-US')} Hz`;
  readout.textContent = value === 0 ? 'Original' : value < 0 ? 'Low-pass' : 'High-pass';
  updateSpectrum(value);
  updateAudio(value);
  dial.setAttribute('aria-valuenow', value);
  dial.setAttribute('aria-valuetext', label);
}

dial.addEventListener('pointerdown', event => {
  if (!event.isPrimary || event.button !== 0) return;
  dial.dataset.pointer = '';
  dial.focus({ preventScroll: true });
  dial.setPointerCapture(event.pointerId);
  drag = { id: event.pointerId, x: event.clientX, y: event.clientY, value };
});

dial.addEventListener('pointermove', event => {
  if (drag && drag.id === event.pointerId) {
    const delta = (event.clientX - drag.x) + (drag.y - event.clientY);
    update(drag.value + delta * (event.shiftKey ? 0.15 : 0.6));
  }

});

dial.addEventListener('lostpointercapture', () => { drag = null; });
dial.addEventListener('pointerup', event => {
  if (dial.hasPointerCapture(event.pointerId)) dial.releasePointerCapture(event.pointerId);
});
dial.addEventListener('pointercancel', () => { drag = null; });
dial.addEventListener('keydown', event => {
  delete dial.dataset.pointer;
  const step = event.shiftKey ? 1 : 5;
  const values = { ArrowRight: value + step, ArrowUp: value + step, ArrowLeft: value - step, ArrowDown: value - step, Home: -100, End: 100, '0': 0 };
  if (!(event.key in values)) return;
  event.preventDefault();
  update(values[event.key]);
});
dial.addEventListener('dblclick', () => update(0));


const spectrum = document.querySelector('.spectrum');
const listen = document.querySelector('.listen');
const listenLabel = document.querySelector('.listen-label');
const bars = Array.from({ length: 27 }, (_, i) => {
  const bar = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  bar.setAttribute('x1', 6 + i * 6.4);
  bar.setAttribute('x2', 6 + i * 6.4);
  spectrum.append(bar);
  return bar;
});
let audio = null;
let playing = false;

function cutoff(position) {
  return position < 0 ? 20000 * Math.pow(115 / 20000, -position / 100) : 20 * Math.pow(500, position / 100);
}

function updateSpectrum(position) {
  bars.forEach((bar, i) => {
    const frequency = 40 * Math.pow(400, i / 26);
    const ratio = position < 0 ? frequency / cutoff(position) : cutoff(position) / frequency;
    const gain = position === 0 ? 1 : 1 / Math.sqrt(1 + Math.pow(ratio, 4));
    const height = Math.max(2, (24 + 60 * Math.pow(Math.sin(i * 1.9 + 0.5), 2)) * gain);
    bar.setAttribute('y1', 60 - height / 2);
    bar.setAttribute('y2', 60 + height / 2);
    bar.style.opacity = .25 + .75 * gain;
  });
}

// An original eight-second musical loop, generated locally. No audio downloads.
function makeLoop(context) {
  const buffer = context.createBuffer(1, context.sampleRate * 8, context.sampleRate);
  const data = buffer.getChannelData(0);
  const rate = context.sampleRate;
  function note(start, duration, midi, level) {
    const frequency = 440 * Math.pow(2, (midi - 69) / 12);
    const offset = Math.round(start * rate);
    const count = Math.min(Math.round(duration * rate), data.length - offset);
    for (let i = 0; i < count; i++) {
      const t = i / rate;
      const phase = 2 * Math.PI * frequency * t;
      const envelope = Math.min(1, t / .008) * Math.exp(-t * 4 / duration) * Math.min(1, (count - i) / (rate * .02));
      data[offset + i] += level * envelope * (Math.sin(phase) + .3 * Math.sin(phase * 2) + .12 * Math.sin(phase * 4));
    }
  }
  const chords = [[57,60,64], [53,57,60], [60,64,67], [55,59,62]];
  chords.forEach((chord, bar) => {
    chord.forEach(pitch => note(bar * 2, 1.95, pitch, .065));
    for (let beat = 0; beat < 4; beat++) {
      note(bar * 2 + beat * .5, .42, chord[0] - 12, .15);
      note(bar * 2 + beat * .5 + .25, .23, chord[beat % 3] + 12, .075);
    }
  });
  let seed = 7;
  for (let beat = 0; beat < 16; beat++) {
    const offset = Math.round(beat * .5 * rate);
    for (let i = 0; i < rate * .16 && offset + i < data.length; i++) {
      const t = i / rate;
      data[offset + i] += .2 * Math.sin(2 * Math.PI * (48 * t + 7 * (1 - Math.exp(-t * 25)))) * Math.exp(-t * 35) * Math.min(1, t * 1000);
    }
    const hat = offset + Math.round(.25 * rate);
    for (let i = 0; i < rate * .055 && hat + i < data.length; i++) {
      seed = (seed * 16807) % 2147483647;
      data[hat + i] += (seed / 2147483647 * 2 - 1) * .025 * Math.exp(-i / (rate * .012));
    }
  }
  return buffer;
}

function updateAudio(position) {
  if (!audio) return;
  const now = audio.context.currentTime;
  audio.filter.type = position > 0 ? 'highpass' : 'lowpass';
  audio.filter.frequency.setTargetAtTime(cutoff(position), now, .025);
  audio.wet.gain.setTargetAtTime(position === 0 ? 0 : 1, now, .015);
  audio.dry.gain.setTargetAtTime(position === 0 ? 1 : 0, now, .015);
}

listen.addEventListener('click', async () => {
  listen.disabled = true;
  try {
    if (!audio) {
      const context = new AudioContext();
      const filter = context.createBiquadFilter();
      filter.Q.value = Math.SQRT1_2;
      const wet = context.createGain();
      const dry = context.createGain();
      const output = context.createGain();
      output.gain.value = .65;
      filter.connect(wet).connect(output);
      dry.connect(output);
      output.connect(context.destination);
      audio = { context, filter, wet, dry, buffer: makeLoop(context), source: null };
    }
    if (playing) {
      audio.source.stop();
      await audio.context.suspend();
      playing = false;
    } else {
      await audio.context.resume();
      updateAudio(value);
      const source = audio.context.createBufferSource();
      source.buffer = audio.buffer;
      source.loop = true;
      source.connect(audio.filter);
      source.connect(audio.dry);
      source.start();
      audio.source = source;
      playing = true;
    }
    listenLabel.textContent = playing ? 'Ⅱ Pause' : '▶ Play demo';
    listen.setAttribute('aria-label', playing ? 'Pause audio demo' : 'Play audio demo');
    listen.setAttribute('aria-pressed', String(playing));
  } catch {
    listenLabel.textContent = 'Audio unavailable';
  } finally {
    listen.disabled = false;
  }
});
window.addEventListener('pagehide', () => {
  if (audio) audio.context.close();
  audio = null;
  playing = false;
  listenLabel.textContent = '▶ Play demo';
  listen.setAttribute('aria-label', 'Play audio demo');
  listen.setAttribute('aria-pressed', 'false');
});
update(value);
