const dial = document.querySelector('.dial');
const arc = document.querySelector('.dial-arc');
const ticks = document.querySelector('.dial-ticks');
const readout = document.querySelector('.dial-readout');
const panel = document.querySelector('.popover');
const menuToggle = document.querySelector('.menu-twiddle');
const popoverPosition = document.querySelector('.popover-position');
const desktop = document.querySelector('.desktop');
const menuTime = document.querySelector('.menu-time');
let value = -35;
let drag = null;

function alignPopover() {
  const desktopRect = desktop.getBoundingClientRect();
  const iconRect = menuToggle.getBoundingClientRect();
  desktop.style.setProperty('--anchor-right', `${desktopRect.right - (iconRect.left + iconRect.width / 2)}px`);
}

function updateMenuTime() {
  const parts = new Intl.DateTimeFormat('en-US', {
    weekday: 'short', month: 'short', day: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true,
  }).formatToParts(new Date());
  const part = type => parts.find(item => item.type === type)?.value || '';
  menuTime.textContent = `${part('weekday')} ${part('month')} ${part('day')} ${part('hour')}:${part('minute')} ${part('dayPeriod')}`;
  alignPopover();
}
updateMenuTime();
new ResizeObserver(alignPopover).observe(desktop);
new ResizeObserver(alignPopover).observe(document.querySelector('.menu-right'));
setInterval(updateMenuTime, 30_000);

function point(degrees, radius) {
  const angle = (degrees - 90) * Math.PI / 180;
  return [110 + Math.cos(angle) * radius, 102 + Math.sin(angle) * radius];
}

for (let i = -10; i <= 10; i++) {
  const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  const start = point(i * 13.5, 94);
  const end = point(i * 13.5, i === 0 ? 102 : 98);
  ['x1', 'y1', 'x2', 'y2'].forEach((key, j) => line.setAttribute(key, [...start, ...end][j]));
  ticks.append(line);
}

function smoothstep(x) {
  x = Math.max(0, Math.min(1, x));
  return x * x * (3 - 2 * x);
}

function update(next) {
  value = Math.max(-100, Math.min(100, Math.round(next * 10) / 10));
  if (Math.abs(value) < 1.5) value = 0;
  const degrees = value * 1.35;
  const end = point(degrees, 85);
  dial.style.setProperty('--angle', `${degrees}deg`);
  // AppKit's drawing coordinates point upward; CSS rotation uses screen coordinates.
  dial.style.setProperty('--detail-angle', `${degrees}deg`);
  arc.setAttribute('d', value === 0 ? '' : `M110 17 A85 85 0 0 ${value > 0 ? 1 : 0} ${end.join(' ')}`);
  const colorAmount = smoothstep(Math.abs(value) / (20 / 135 * 100));
  const accent = `rgb(${Math.round(140 + 111 * colorAmount)} ${Math.round(140 - 22 * colorAmount)} ${Math.round(140 - 140 * colorAmount)})`;
  panel.style.setProperty('--accent', accent);
  [...ticks.children].forEach((tick, i) => {
    const tickValue = (i - 10) * 10;
    const swept = value !== 0 && (value < 0 ? tickValue <= 0 && tickValue >= value : tickValue >= 0 && tickValue <= value);
    tick.style.stroke = swept ? accent : i === 10 ? '#fff' : '#ffffff79';
  });
  const amount = Math.abs(value) / 100;
  const frequency = Math.round(value < 0 ? 20000 * Math.pow(115 / 20000, amount) : 20 * Math.pow(10000 / 20, amount));
  const label = value === 0 ? 'Bypass' : `${value < 0 ? 'Low-pass' : 'High-pass'} · ${frequency.toLocaleString('en-US')} Hz`;
  readout.textContent = label;
  updateAudio(value);
  dial.setAttribute('aria-valuenow', value);
  dial.setAttribute('aria-valuetext', label);
}

dial.addEventListener('pointerdown', event => {
  if (!event.isPrimary || event.button !== 0) return;
  startDemo();
  dial.dataset.pointer = '';
  dial.focus({ preventScroll: true });
  dial.setPointerCapture(event.pointerId);
  drag = { id: event.pointerId, y: event.clientY, value };
});

dial.addEventListener('pointermove', event => {
  if (drag && drag.id === event.pointerId) {
    const scale = dial.getBoundingClientRect().height / 164;
    const delta = (drag.y - event.clientY) / scale;
    update(drag.value + delta * (event.shiftKey ? .1 : .8));
  }
});

dial.addEventListener('lostpointercapture', () => { drag = null; });
dial.addEventListener('pointerup', event => {
  if (dial.hasPointerCapture(event.pointerId)) dial.releasePointerCapture(event.pointerId);
});
dial.addEventListener('pointercancel', () => { drag = null; });
dial.addEventListener('keydown', event => {
  delete dial.dataset.pointer;
  const step = event.shiftKey ? .5 : 2.5;
  const values = { ArrowRight: value + step, ArrowUp: value + step, ArrowLeft: value - step, ArrowDown: value - step, Home: -100, End: 100, '0': 0 };
  if (!(event.key in values)) return;
  event.preventDefault();
  startDemo();
  update(values[event.key]);
});
dial.addEventListener('dblclick', () => update(0));
// A wheel scroll upward raises the value, matching an upward drag in the app.
dial.addEventListener('wheel', event => {
  event.preventDefault();
  startDemo();
  update(value - event.deltaY * (event.shiftKey ? .012 : .12));
}, { passive: false });

menuToggle.addEventListener('click', () => {
  const open = menuToggle.getAttribute('aria-expanded') !== 'true';
  menuToggle.setAttribute('aria-expanded', String(open));
  popoverPosition.classList.toggle('is-closed', !open);
  popoverPosition.inert = !open;
  popoverPosition.setAttribute('aria-hidden', String(!open));
});

const listen = document.querySelector('.listen');
const listenIcon = document.querySelector('.listen-icon');
const demoPlayer = document.querySelector('.demo-player');
let audio = null;
let playing = false;
let starting = null;

function cutoff(position) {
  return position < 0 ? 20000 * Math.pow(115 / 20000, -position / 100) : 20 * Math.pow(500, position / 100);
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

function syncPlayer() {
  listenIcon.textContent = playing ? 'Ⅱ' : '▶';
  demoPlayer.classList.toggle('is-playing', playing);
  listen.setAttribute('aria-label', playing ? 'Pause audio demo' : 'Play audio demo');
  listen.setAttribute('aria-pressed', String(playing));
}

function startDemo() {
  if (playing) return Promise.resolve();
  if (starting) return starting;
  starting = (async () => {
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
      syncPlayer();
    } catch {
      listen.setAttribute('aria-label', 'Audio unavailable');
    }
  })().finally(() => { starting = null; });
  return starting;
}

listen.addEventListener('click', async () => {
  if (starting) await starting;
  listen.disabled = true;
  try {
    if (playing) {
      audio.source.stop();
      audio.source = null;
      await audio.context.suspend();
      playing = false;
      syncPlayer();
    } else await startDemo();
  } finally {
    listen.disabled = false;
  }
});
window.addEventListener('pagehide', () => {
  if (audio) audio.context.close();
  audio = null;
  playing = false;
  syncPlayer();
});
update(value);
