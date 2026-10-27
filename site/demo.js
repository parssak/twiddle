// The scripted desktop demo: five chapters played like a video, an audio loop the
// knob filters live, and a hands-on mode when you grab any control.
(() => {
  const T = window.Twiddle;
  const frame = document.querySelector('.frame');
  if (!T || !frame) return;
  const stage = frame.querySelector('.stage');
  const $ = selector => stage.querySelector(selector);
  const popoverPosition = $('.popover-position');
  const popover = $('.popover');
  const clip = $('.popover-clip');
  const outlinePath = $('.popover-outline path');
  const tray = $('.fx-tray');
  const fxButton = $('.pop-fx');
  const stopButton = $('.fx-stop');
  const discoButton = $('.fx-disco');
  const readout = $('.dial-readout');
  const filterLabel = $('.readout-filter');
  const songLabel = $('.readout-song');
  const songText = songLabel.firstElementChild;
  const menuToggle = $('.menu-twiddle');
  const menuKnob = $('.menu-knob');
  const menuTime = $('.menu-time');
  const cursor = $('.cursor');
  const caption = $('.caption');
  const captionText = $('.caption-text');
  const keysHud = $('.hud-keys');
  const keys = Object.fromEntries([...keysHud.querySelectorAll('kbd')].map(key => [key.dataset.key, key]));
  const dictation = $('.hud-dictation');
  const elapsedLabel = $('.player-elapsed');
  const progressBar = $('.player-time b');
  const discoLayer = $('.stage-disco');
  const listen = frame.querySelector('.listen');
  const controls = document.querySelector('.controls');
  const playButton = controls.querySelector('.control-play');
  const soundButton = controls.querySelector('.control-sound');
  const chapterButtons = [...controls.querySelectorAll('.chapters button')];
  const chapterFills = chapterButtons.map(button => button.querySelector('.fill'));

  const LAYOUTS = { wide: { width: 1200, height: 720 }, compact: { width: 640, height: 900 } };
  const SCALE = 1.5;
  const PRESET = -60;
  const BEAT = 60 / 112;
  const LOOP = 16 * BEAT;
  let layout = 'wide';
  let stageScale = 1;
  let geometry = { popLeft: 0, popTop: 36, arrowX: 120 };
  let anchors = {};
  let songOverflow = 0;

  // Bars span 45 Hz to 14 kHz on a log scale.
  const BAR_COUNT = 32;
  const barFrequencies = Array.from({ length: BAR_COUNT }, (_, i) => 45 * Math.pow(14000 / 45, i / (BAR_COUNT - 1)));
  const bars = barFrequencies.map(() => document.createElement('span'));
  $('.player-bars').append(...bars);
  const waveBars = Array.from({ length: 16 }, () => document.createElement('i'));
  $('.dictation-wave').append(...waveBars);

  function updateMenuTime() {
    const parts = new Intl.DateTimeFormat('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true }).formatToParts(new Date());
    const part = type => parts.find(item => item.type === type)?.value || '';
    menuTime.textContent = layout === 'compact'
      ? `${part('hour')}:${part('minute')} ${part('dayPeriod')}`
      : `${part('weekday')} ${part('month')} ${part('day')} ${part('hour')}:${part('minute')} ${part('dayPeriod')}`;
  }

  // Layout -------------------------------------------------------------------

  function measure() {
    const next = frame.clientWidth < 700 ? 'compact' : 'wide';
    if (next !== layout) {
      layout = next;
      frame.dataset.layout = layout;
      updateMenuTime();
    }
    const { width, height } = LAYOUTS[layout];
    stageScale = frame.clientWidth / width;
    stage.style.transform = `scale(${stageScale})`;
    frame.style.setProperty('--stage-scale', stageScale.toFixed(4));
    const stageRect = stage.getBoundingClientRect();
    const icon = menuToggle.getBoundingClientRect();
    const iconX = (icon.left + icon.width / 2 - stageRect.left) / stageScale;
    const popLeft = T.clamp(iconX - 120 * SCALE, 14, width - 14 - 240 * SCALE);
    geometry = { popLeft, popTop: 36, arrowX: T.clamp((iconX - popLeft) / SCALE, 40, 200) };
    popoverPosition.style.left = `${popLeft}px`;
    popoverPosition.style.top = `${geometry.popTop}px`;
    popoverPosition.style.setProperty('--origin', `${geometry.arrowX * SCALE}px ${9 * SCALE}px`);
    const at = (x, y) => [popLeft + x * SCALE, geometry.popTop + y * SCALE];
    anchors = {
      knob: at(120, 122), fx: at(209, 211), reverb: at(60, 296), pitch: at(180, 296),
      stop: at(120, 276), disco: at(120, 310),
      rest: [width * .5, height * .58], enter: [width * .55, height + 40],
    };
    chapters = SCRIPT.map(build => build(anchors));
    chapters.forEach((c, i) => { chapterButtons[i].parentElement.style.flexGrow = c.duration; });
    songOverflow = Math.max(0, songText.offsetWidth - songLabel.clientWidth);
    setClass(songLabel, 'is-overflowing', songOverflow > 0);
    shown.offset = null;
    lastShape = -1;
    layoutDisco();
    render();
  }

  let lastShape = -1;
  function shape(fx) {
    if (fx === lastShape) return;
    lastShape = fx;
    const trayHeight = 140 * T.smoothstep(fx);
    const height = 236 + trayHeight;
    const ax = geometry.arrowX;
    const d = `M20 20 H${ax - 18} C${ax - 10} 20 ${ax - 9} 9 ${ax} 9 C${ax + 9} 9 ${ax + 10} 20 ${ax + 18} 20 H220 Q239 20 239 39 V${height - 21} Q239 ${height - 1} 220 ${height - 1} H20 Q1 ${height - 1} 1 ${height - 21} V39 Q1 20 20 20 Z`;
    popover.style.height = `${height}px`;
    popoverPosition.style.width = `${240 * SCALE}px`;
    popoverPosition.style.height = `${height * SCALE}px`;
    clip.style.clipPath = `path("${d}")`;
    outlinePath.setAttribute('d', d);
    const reveal = T.smoothstep((fx - .2) / .8);
    tray.style.setProperty('--reveal', reveal.toFixed(3));
    tray.style.visibility = fx > 0 ? 'visible' : 'hidden';
    const open = fx > .5;
    fxButton.setAttribute('aria-expanded', String(open));
    for (const control of [stopButton, discoButton, reverbDial.element, pitchDial.element]) control.tabIndex = open ? 0 : -1;
  }

  // Script -------------------------------------------------------------------
  // Each chapter is a function of time, so pausing, seeking and looping stay exact.

  const SCRIPT = [
    a => {
      const k = (dx, dy) => [a.knob[0] + dx, a.knob[1] + dy];
      return {
        name: 'Turn', duration: 8200,
        open: [[0, true]],
        knob: [[0, 0], [1300, 0], [2500, -66], [3500, -66], [5000, 48], [6260, 48], [6660, 0, 'out']],
        cursor: [[0, ...a.enter], [1100, ...k(0, -36)], [1300, ...k(0, -36)], [2500, ...k(0, 54)], [3500, ...k(0, 54)], [5000, ...k(0, -74)], [5800, ...k(0, -74)], [6100, ...k(8, -66)], [7700, ...k(170, 60)]],
        cursorVisible: [[0, true]],
        cursorDown: [[0, false], [1250, true], [5800, false], [6140, true], [6210, false], [6280, true], [6350, false]],
        captions: [
          { from: 500, to: 5900, parts: [['Turn left to cut the highs,', 1300, 2400], ['right to cut the lows.', 3500, 4900]] },
          { from: 6100, to: 8100, parts: [['Double-click to glide back.', 6150, 6900]] },
        ],
      };
    },
    () => ({
      name: 'Shortcuts', duration: 8000,
      open: [[0, false], [1000, true], [2400, false], [3300, true], [5460, false], [6000, true], [7400, false]],
      knob: [[0, 0], [1000, 0], [1180, PRESET, 'out'], [3300, PRESET], [3460, PRESET + 10, 'out'], [3900, PRESET + 10], [4060, PRESET + 20, 'out'], [6000, PRESET + 20], [6180, 0, 'out']],
      keys: [[0, false], [500, true], [7600, false]],
      pressed: [[0, []], [940, ['option']], [1000, ['option', 'f10']], [1240, ['option']], [1340, []],
        [3240, ['option']], [3300, ['option', 'f12']], [3480, ['option']], [3900, ['option', 'f12']], [4080, ['option']], [4200, []],
        [5940, ['option']], [6000, ['option', 'f10']], [6220, ['option']], [6320, []]],
      captions: [
        { from: 400, to: 3000, parts: [['⌥F10 drops into your preset from any app.', 1000, 2000]] },
        { from: 3150, to: 5700, parts: [['⌥F11 and ⌥F12 step it down or up.', 3300, 4300]] },
        { from: 5850, to: 7800, parts: [['Press ⌥F10 again to go back.', 6000, 6700]] },
      ],
    }),
    () => ({
      name: 'Auto-apply', duration: 7800,
      open: [[0, true]],
      knob: [[0, 0], [1500, 0], [1680, PRESET, 'out'], [5300, PRESET], [5700, 0]],
      mic: [[0, false], [1450, true], [5250, false]],
      dictation: [[0, false], [1300, true], [5300, false]],
      speaking: [[0, false], [1600, true], [5050, false]],
      captions: [
        { from: 500, to: 4900, parts: [['Start dictating, and your preset kicks in.', 1500, 2600]] },
        { from: 5100, to: 7700, parts: [['Stop, and the music eases back.', 5300, 6100]] },
      ],
    }),
    a => {
      const r = (dx, dy) => [a.reverb[0] + dx, a.reverb[1] + dy];
      const p = (dx, dy) => [a.pitch[0] + dx, a.pitch[1] + dy];
      return {
        name: 'Effects', duration: 9800,
        open: [[0, true]],
        fx: [[0, 0], [1000, 0], [1240, 1, 'linear']],
        reverb: [[0, 0], [2500, 0], [3500, 62], [9800, 62]],
        pitch: [[0, 0], [4800, 0], [4950, 1, 'step'], [5100, 2, 'step'], [5250, 3, 'step'], [5400, 4, 'step'], [6290, 4], [6290, 0, 'step']],
        stop: [[0, false], [7150, true], [8350, false]],
        cursor: [[0, ...a.rest], [850, ...a.fx], [1400, ...a.fx], [2300, ...r(0, 0)], [2500, ...r(0, 0)], [3500, ...r(0, -60)], [3900, ...r(0, -60)], [4600, ...p(0, 0)], [4800, ...p(0, 0)], [5400, ...p(0, -32)], [5900, ...p(0, -32)], [6100, ...p(3, -28)], [6900, ...a.stop], [9800, ...a.stop]],
        cursorVisible: [[0, true]],
        cursorDown: [[0, false], [960, true], [1040, false], [2450, true], [3900, false], [4750, true], [5900, false], [6120, true], [6190, false], [6230, true], [6290, false], [7100, true], [8350, false]],
        captions: [
          { from: 400, to: 4450, parts: [['Open FX to add reverb,', 1000, 2700]] },
          { from: 4600, to: 6750, parts: [['bend the pitch in semitones,', 4800, 5500]] },
          { from: 6900, to: 9700, parts: [['or hold to stop the tape.', 7150, 7900]] },
        ],
      };
    },
    a => ({
      name: 'Disco', duration: 8600,
      open: [[0, true]],
      fx: [[0, 1]],
      reverb: [[0, 62]],
      disco: [[0, 0], [900, 0], [2020, 1.12, 'linear'], [7400, 1.12], [8520, 0, 'linear']],
      discoOn: [[0, false], [880, true], [7400, false]],
      cursor: [[0, ...a.stop], [700, ...a.disco], [1600, ...a.disco], [2400, a.disco[0] + 120, a.disco[1] + 160]],
      cursorVisible: [[0, true], [1800, false]],
      cursorDown: [[0, false], [820, true], [900, false]],
      captions: [{ from: 2200, to: 7200, parts: [['When the drop hits, there’s disco.', 2400, 3500]] }],
    }),
  ];
  let chapters = [];

  function point(track, t) {
    if (t <= track[0][0]) return [track[0][1], track[0][2]];
    for (let i = 1; i < track.length; i++) {
      const [time, x, y, curve = 'inOut'] = track[i];
      if (t < time) {
        const [start, x0, y0] = track[i - 1];
        const p = T.ease[curve]((t - start) / (time - start));
        return [T.lerp(x0, x, p), T.lerp(y0, y, p)];
      }
    }
    const last = track[track.length - 1];
    return [last[1], last[2]];
  }
  const { keyframes, step } = T;
  function sample(index, t) {
    const c = chapters[index];
    return {
      open: step(c.open, t, true),
      fx: keyframes(c.fx, t) ?? 0,
      knob: keyframes(c.knob, t) ?? 0,
      reverb: keyframes(c.reverb, t) ?? 0,
      pitch: keyframes(c.pitch, t) ?? 0,
      stop: step(c.stop, t, false),
      disco: keyframes(c.disco, t) ?? 0,
      discoOn: step(c.discoOn, t, false),
      keys: step(c.keys, t, false),
      pressed: step(c.pressed, t, []),
      mic: step(c.mic, t, false),
      dictation: step(c.dictation, t, false),
      speaking: step(c.speaking, t, false),
      cursorVisible: step(c.cursorVisible, t, false),
      cursorDown: step(c.cursorDown, t, false),
      cursor: c.cursor ? point(c.cursor, t) : null,
      caption: activeCaption(c, index, t),
    };
  }
  function activeCaption(c, index, t) {
    const i = c.captions.findIndex(item => t >= item.from && t < item.to);
    return i < 0 ? null : { key: `${index}:${i}`, parts: c.captions[i].parts, t };
  }

  // Playback state -----------------------------------------------------------

  let chapter = 0, time = 0;
  let playing = !T.reducedMotion.matches;
  let poster = T.reducedMotion.matches;
  let inView = false;
  let sound = false;
  let manual = null;
  let blend = null;
  let clock = 0, loopClock = 0, discoClock = 0, stopLevel = 1;

  function running() { return inView && !document.hidden && (playing || !!manual); }

  function takeover(withSound) {
    if (!manual) {
      const current = sample(chapter, time);
      manual = {
        open: current.open, fx: current.fx, fxTarget: current.fx > .5 ? 1 : 0,
        knob: current.knob, reverb: current.reverb, pitch: current.pitch, stop: false,
        disco: current.disco, discoOn: current.discoOn, glide: null, started: clock,
      };
      playing = false;
      poster = false;
    }
    if (withSound && !sound) setSound(true);
    sync();
  }
  function resume() {
    if (manual) {
      blend = { from: { knob: manual.knob, reverb: manual.reverb, pitch: manual.pitch }, started: clock };
      manual = null;
    }
    playing = true;
    poster = false;
    sync();
  }
  function seek(index) {
    if (manual) blend = { from: { knob: manual.knob, reverb: manual.reverb, pitch: manual.pitch }, started: clock };
    manual = null;
    chapter = index;
    time = 0;
    playing = true;
    poster = false;
    sync();
  }

  function manualState(dt) {
    const m = manual;
    m.fx = T.clamp(m.fx + (m.fxTarget ? 1 : -1) * dt / 240, 0, 1);
    m.disco = T.clamp(m.disco + (m.discoOn ? 1 : -1) * dt / 1000, 0, 1.12);
    if (m.glide) {
      const p = Math.min(1, (clock - m.glide.started) / 400);
      m[m.glide.key] = T.lerp(m.glide.from, 0, T.ease.out(p));
      if (p === 1) m.glide = null;
    }
    const since = clock - m.started;
    return {
      ...m, keys: false, pressed: [], mic: false, dictation: false, speaking: false,
      cursorVisible: false, cursorDown: false, cursor: null,
      caption: since < 3200 ? { key: 'manual', parts: [['Your turn. Drag, scroll or use the arrow keys.', 100, 900]], t: since } : null,
    };
  }

  // Rendering ----------------------------------------------------------------

  const mainDial = new T.Dial($('.dial-main'), {
    input: value => { manual.knob = value; manual.glide = null; kick(); },
    grab: () => takeover(true),
    reset: () => { manual.glide = { key: 'knob', from: manual.knob, started: clock }; kick(); },
  });
  const reverbDial = new T.Dial($('.fx-reverb .dial'), {
    input: value => { manual.reverb = value; manual.glide = null; kick(); },
    grab: () => takeover(true),
    reset: () => { manual.glide = { key: 'reverb', from: manual.reverb, started: clock }; kick(); },
  });
  const pitchDial = new T.Dial($('.fx-pitch .dial'), {
    steps: 24,
    input: value => { manual.pitch = value * 12 / 100; manual.glide = null; kick(); },
    grab: () => takeover(true),
    reset: () => { manual.glide = { key: 'pitch', from: manual.pitch, started: clock }; kick(); },
  });

  const shown = {};
  function setClass(element, name, on) {
    if (element[name] === on) return;
    element[name] = on;
    element.classList.toggle(name, on);
  }

  function render(dt = 0) {
    let state = manual ? manualState(dt) : sample(chapter, time);
    if (blend) {
      const p = Math.min(1, (clock - blend.started) / 450);
      const e = T.ease.out(p);
      state = { ...state, knob: T.lerp(blend.from.knob, state.knob, e), reverb: T.lerp(blend.from.reverb, state.reverb, e), pitch: T.lerp(blend.from.pitch, state.pitch, e) };
      if (p === 1) blend = null;
    }
    const knob = Math.abs(state.knob) < .05 ? 0 : Math.round(state.knob * 10) / 10;

    setClass(popoverPosition, 'is-closed', !state.open);
    if (shown.open !== state.open) {
      shown.open = state.open;
      popoverPosition.inert = !state.open;
      popoverPosition.setAttribute('aria-hidden', String(!state.open));
      menuToggle.setAttribute('aria-expanded', String(state.open));
    }
    shape(state.fx);

    mainDial.set(knob);
    reverbDial.set(state.reverb);
    pitchDial.set(state.pitch * 100 / 12);
    const label = T.label(knob);
    if (shown.label !== label) {
      shown.label = label;
      // Keep the last filter on screen while it fades out at center.
      if (knob !== 0) filterLabel.textContent = label;
      filterUntil = knob !== 0 ? clock + 1000 : 0;
      mainDial.element.setAttribute('aria-valuenow', String(knob));
      mainDial.element.setAttribute('aria-valuetext', label);
    }
    renderReadout();
    menuKnob.style.setProperty('--menu-angle', `${knob * 1.35}deg`);
    reverbDial.element.setAttribute('aria-valuenow', String(Math.round(state.reverb)));
    pitchDial.element.setAttribute('aria-valuenow', String(Math.round(state.pitch)));

    setClass(stopButton, 'is-held', state.stop);
    if (shown.discoOn !== state.discoOn) { shown.discoOn = state.discoOn; discoButton.setAttribute('aria-pressed', String(state.discoOn)); }

    setClass(keysHud, 'is-visible', state.keys);
    for (const [name, key] of Object.entries(keys)) setClass(key, 'is-down', state.pressed.includes(name));
    setClass(dictation, 'is-visible', state.dictation);
    if (shown.mic !== state.mic) { shown.mic = state.mic; stage.toggleAttribute('data-mic', state.mic); }
    if (state.dictation) {
      waveBars.forEach((bar, i) => {
        const level = state.speaking ? .25 + .75 * Math.abs(Math.sin(clock / 170 + i * .8) * Math.sin(clock / 410 + i * 1.7)) : .12;
        bar.style.transform = `scaleY(${level.toFixed(3)})`;
      });
    }

    setClass(cursor, 'is-visible', state.cursorVisible && !!state.cursor);
    setClass(cursor, 'is-down', state.cursorDown);
    if (state.cursor) cursor.style.translate = `${state.cursor[0].toFixed(1)}px ${state.cursor[1].toFixed(1)}px`;

    renderCaption(state.caption);
    renderMusic(state, knob, dt);
    renderDisco(state, dt);
    updateAudio(state, knob);
    updateControls();
  }

  // Like the app with Spotify, the footer shows the filter for a second after
  // each change, then the song, scrolling slowly when it does not fit.
  let filterUntil = 0, songSince = 0;
  function renderReadout() {
    const song = clock >= filterUntil;
    if (shown.song !== song) { shown.song = song; songSince = clock; setClass(readout, 'is-song', song); }
    const offset = song && !poster ? Math.round(marquee((clock - songSince) / 1000) * 10) / 10 : 0;
    if (shown.offset === offset) return;
    shown.offset = offset;
    songText.style.translate = `${-offset}px 0`;
    const left = Math.min(8, offset), right = Math.min(8, songOverflow - offset);
    songLabel.style.setProperty('--fade', songOverflow ? `linear-gradient(90deg, transparent, #000 ${left}px, #000 calc(100% - ${right}px), transparent)` : 'none');
  }
  // The app's 24 points per second, after a pause at each end.
  function marquee(t) {
    if (!songOverflow) return 0;
    const travel = songOverflow / 24, hold = 2;
    t = (t + hold - .5) % (2 * (travel + hold));
    if (t < hold) return 0;
    if ((t -= hold) < travel) return t * 24;
    if ((t -= travel) < hold) return songOverflow;
    return songOverflow - (t - hold) * 24;
  }

  let captionKey = null, words = [];
  function renderCaption(current) {
    const key = current?.key ?? null;
    if (key !== captionKey) {
      captionKey = key;
      if (current) {
        captionText.replaceChildren();
        words = [];
        current.parts.forEach(([text, from, to], partIndex) => {
          const list = text.split(' ');
          list.forEach((word, i) => {
            const span = document.createElement('span');
            span.className = 'word';
            span.textContent = word;
            words.push({ span, at: from + (to - from) * (list.length > 1 ? i / (list.length - 1) : 0) });
            captionText.append(span, ' ');
          });
          if (partIndex < current.parts.length - 1) captionText.append(' ');
        });
      }
      setClass(caption, 'is-visible', !!current);
    }
    if (current) for (const word of words) setClass(word.span, 'on', poster || current.t >= word.at);
  }

  function renderMusic(state, knob, dt) {
    const musicOn = (playing || !!manual) && !poster;
    if (shown.music !== musicOn) { shown.music = musicOn; stage.toggleAttribute('data-music', musicOn); }
    if (state.stop) stopLevel = Math.max(0, stopLevel - dt / 900);
    else stopLevel = 1;
    const live = audioRunning();
    if (musicOn && stopLevel > 0 && !live) loopClock = (loopClock + dt * stopLevel) % (LOOP * 1000);
    const position = live ? audioPosition() : loopClock / 1000;
    const seconds = Math.floor(position);
    if (shown.seconds !== seconds) { shown.seconds = seconds; elapsedLabel.textContent = `0:0${seconds}`; }
    progressBar.style.transform = `scaleX(${(position / LOOP).toFixed(4)})`;

    const beat = position % BEAT;
    const energy = (musicOn || poster ? 1 : .35) * (state.stop ? stopLevel : 1);
    const wobble = poster ? 1200 : clock;
    bars.forEach((bar, i) => {
      const x = i / (BAR_COUNT - 1);
      let db = -7 - 15 * Math.pow(x, 1.25);
      db += 9 * Math.exp(-beat / .11) * Math.max(0, 1 - i / 7);
      db += 7 * Math.exp(-Math.abs(beat - BEAT / 2) / .045) * T.smoothstep((i - 19) / 8);
      db += 3 * Math.sin(wobble / 330 + i * .9) + 2 * Math.sin(wobble / 190 + i * i * .37);
      const g = T.gain(knob, barFrequencies[i]);
      db += 20 * Math.log10(Math.max(g, 1e-4));
      const height = T.clamp((db + 44) / 44, .035, 1) * energy;
      bar.style.transform = `scaleY(${Math.max(.035, height).toFixed(3)})`;
      setClass(bar, 'cut', g < .3);
    });
  }

  // Disco --------------------------------------------------------------------

  let disco = null, discoLoading = false, discoFailed = false;
  function layoutDisco() {
    if (!disco) return;
    const { width, height } = LAYOUTS[layout];
    const dpr = Math.min(devicePixelRatio, 2);
    disco.layout(width, height, [
      { x: 0, y: 0, w: width, h: height, scale: Math.min(stageScale, 600 / height) },
      disco.sphereView(width, height, stageScale * dpr),
    ]);
  }
  function renderDisco(state, dt) {
    const deployment = state.disco;
    if (deployment > 0 && !disco && !discoLoading && !discoFailed && !T.reducedMotion.matches) {
      discoLoading = true;
      TwiddleDisco.createRenderer($('.stage-beams'), $('.stage-sphere'))
        .then(created => { disco = created; layoutDisco(); kick(); })
        .catch(error => { discoFailed = true; console.warn('Disco renderer:', error.message); })
        .finally(() => { discoLoading = false; });
    }
    const on = deployment > 0;
    setClass(discoLayer, 'is-on', on);
    setClass(discoLayer, 'is-lit', deployment > 1.04);
    if (!on) return;
    discoClock += dt;
    if (disco && !disco.lost) disco.draw(discoClock / 1000, deployment);
    else discoLayer.style.background = `rgb(0 0 0 / ${(.78 * T.smoothstep((deployment - 1) / .12)).toFixed(3)})`;
  }

  // Audio --------------------------------------------------------------------

  const audio = { context: null, buffers: new Map(), rendering: false, voice: null };

  // "Lights Down Low", an original four-bar disco loop at 112 BPM: Fmaj9, Em7,
  // Dm9 and E7 over a four-on-the-floor kick.
  const CHORDS = [
    { root: 41, voicing: [57, 60, 64, 67] },
    { root: 40, voicing: [55, 59, 62, 67] },
    { root: 38, voicing: [53, 57, 60, 64] },
    { root: 40, voicing: [56, 59, 62, 64] },
  ];
  // [sixteenth, length in sixteenths, interval above the root]
  const BASSLINE = [[0, 3, 0], [3, 1, 12], [4, 2, 0], [6, 1, 12], [7, 2, 0], [10, 1, 12], [11, 2, 0], [14, 1, 7], [15, 1, 12]];
  // [bar, sixteenth, length in sixteenths, MIDI note]
  const MELODY = [
    [0, 2, 4, 76], [0, 6, 2, 74], [0, 8, 4, 72], [0, 12, 2, 69], [0, 14, 2, 72],
    [1, 0, 6, 71], [1, 6, 2, 74], [1, 8, 6, 71], [1, 14, 2, 67],
    [2, 2, 2, 69], [2, 4, 2, 72], [2, 6, 4, 76], [2, 10, 2, 77], [2, 12, 2, 76], [2, 14, 2, 74],
    [3, 0, 4, 74], [3, 4, 4, 71], [3, 8, 6, 68],
  ];

  // Build the arrangement in an offline context. Pitch shifts every part,
  // drums included, like the app's pitch effect.
  function compose(context, semitones) {
    const shift = Math.pow(2, semitones / 12);
    const hz = midi => 440 * Math.pow(2, (midi + semitones - 69) / 12);
    const at = (bar, sixteenth) => (bar * 16 + sixteenth) * BEAT / 4;
    let seed = 7;
    const random = () => (seed = seed * 16807 % 2147483647) / 2147483647;
    const noise = context.createBuffer(1, context.sampleRate, context.sampleRate);
    noise.getChannelData(0).forEach((_, i, data) => { data[i] = random() * 2 - 1; });

    const gain = (destination, value = 1) => {
      const node = context.createGain();
      node.gain.value = value;
      node.connect(destination);
      return node;
    };
    const filter = (destination, type, frequency, q = .7) => {
      const node = context.createBiquadFilter();
      node.type = type;
      node.frequency.value = frequency;
      node.Q.value = q;
      node.connect(destination);
      return node;
    };
    const pan = (destination, value) => {
      const node = context.createStereoPanner();
      node.pan.value = value;
      node.connect(destination);
      return node;
    };
    const tone = (type, frequency, t, end, destination, detune = 0) => {
      const node = context.createOscillator();
      node.type = type;
      node.frequency.value = frequency;
      node.detune.value = detune;
      node.connect(destination);
      node.start(t);
      node.stop(end);
      return node;
    };
    // Attack to `level`, decay toward `level * sustain`, release from `end`.
    const envelope = (param, t, end, level, attack, decay, sustain, release) => {
      param.setValueAtTime(0, t);
      param.linearRampToValueAtTime(level, t + attack);
      param.setTargetAtTime(level * sustain, t + attack, decay);
      param.setTargetAtTime(0, end, release);
    };
    const burst = (t, decay, type, frequency, level, destination, q) => {
      const amp = gain(destination, 0);
      const source = context.createBufferSource();
      source.buffer = noise;
      source.connect(filter(amp, type, frequency * shift, q));
      amp.gain.setValueAtTime(level, t);
      amp.gain.setTargetAtTime(0, t, decay);
      source.start(t, random() * .5);
      source.stop(t + decay * 8);
      return amp;
    };

    // Everything but the drums ducks under each kick, then the mix saturates gently.
    const shaper = context.createWaveShaper();
    shaper.curve = Float32Array.from({ length: 2048 }, (_, i) => Math.tanh(1.5 * (i / 1023.5 - 1)) / Math.tanh(1.5));
    shaper.connect(context.destination);
    const master = gain(shaper, .6);
    const drums = gain(master), music = gain(master);
    const reverb = context.createConvolver();
    reverb.buffer = impulse(context, 1.2);
    reverb.connect(filter(music, 'lowpass', 5000));
    const room = gain(reverb, .35);
    const hats = pan(drums, .2);

    const bassDrum = t => {
      const amp = gain(drums, 0);
      const body = tone('sine', 150 * shift, t, t + .6, amp);
      body.frequency.setValueAtTime(150 * shift, t);
      body.frequency.exponentialRampToValueAtTime(46 * shift, t + .1);
      amp.gain.setValueAtTime(0, t);
      amp.gain.linearRampToValueAtTime(.9, t + .003);
      amp.gain.setTargetAtTime(0, t + .003, .12);
      burst(t, .004, 'highpass', 2500, .25, drums);
      music.gain.setTargetAtTime(.5, t, .006);
      music.gain.setTargetAtTime(1, t + .05, .09);
    };
    const clap = t => {
      for (const [offset, decay, level] of [[0, .005, 1.5], [.011, .005, 1.4], [.022, .006, 1.25], [.03, .07, 1.1]]) {
        burst(t + offset, decay, 'bandpass', 1250, level, drums, 1.4).connect(room);
      }
      const amp = gain(drums, 0);
      tone('triangle', 185 * shift, t, t + .25, amp);
      amp.gain.setValueAtTime(.6, t);
      amp.gain.setTargetAtTime(0, t, .04);
    };
    const hat = (t, open, level) => burst(t, open ? .055 : .012, 'highpass', open ? 6000 : 9000, level, hats);

    const bass = (t, duration, midi) => {
      const f = hz(midi), end = t + duration;
      const amp = gain(music, 0);
      envelope(amp.gain, t, end, .18, .004, .15, .7, .03);
      const tonal = filter(amp, 'lowpass', f * 16, 8);
      tonal.frequency.setValueAtTime(f * 16, t);
      tonal.frequency.setTargetAtTime(f * 4, t, .07);
      tone('sawtooth', f, t, end + .2, tonal);
      tone('sine', f, t, end + .2, gain(amp, .7));
    };
    const stab = (t, duration, notes, level) => {
      const end = t + duration;
      const amp = gain(music, 0);
      amp.connect(room);
      envelope(amp.gain, t, end, level, .003, .12, .55, .05);
      const tonal = filter(amp, 'lowpass', 6000 * shift, 3);
      tonal.frequency.setTargetAtTime(2200 * shift, t, .09);
      // Two saws per note, detuned and spread left and right.
      const left = pan(tonal, -.6), right = pan(tonal, .6);
      notes.forEach(midi => { tone('sawtooth', hz(midi), t, end + .25, left, -8); tone('sawtooth', hz(midi), t, end + .25, right, 8); });
    };
    const pad = (t, duration, notes) => {
      const end = t + duration;
      const amp = gain(music, 0);
      amp.connect(room);
      envelope(amp.gain, t, end, .035, .12, .5, .8, .25);
      const tonal = filter(amp, 'lowpass', 1800 * shift);
      notes.forEach(midi => { tone('triangle', hz(midi), t, end + 1, tonal, -5); tone('triangle', hz(midi), t, end + 1, tonal, 5); });
    };

    // A talk-box lead: one gliding square wave through two vowel formants,
    // with vibrato and a dotted-eighth echo.
    const lead = gain(music, .9);
    lead.connect(room);
    const echo = context.createDelay(1);
    echo.delayTime.value = BEAT * .75;
    const feedback = gain(echo, .3);
    echo.connect(filter(feedback, 'lowpass', 2500));
    echo.connect(gain(pan(music, -.35), .35));
    lead.connect(echo);
    const gate = gain(filter(lead, 'bandpass', 800 * shift, 4), 0);
    gate.connect(filter(lead, 'bandpass', 1250 * shift, 5));
    gate.connect(gain(filter(lead, 'lowpass', 2400 * shift), .25));
    const end = LOOP + 2;
    const voice = tone('square', hz(MELODY[0][3]), 0, end, gate);
    const vibrato = gain(voice.detune, 14);
    tone('sine', 5.2, 0, end, vibrato);
    for (const [bar, sixteenth, length, midi] of MELODY) {
      const t = at(bar, sixteenth), off = t + length * BEAT / 4;
      voice.frequency.setTargetAtTime(hz(midi), t, .02);
      gate.gain.setTargetAtTime(.22, t, .012);
      gate.gain.setTargetAtTime(0, off - .03, .03);
    }

    CHORDS.forEach(({ root, voicing }, bar) => {
      pad(at(bar, 0), 4 * BEAT - .05, voicing);
      for (const sixteenth of [2, 6, 10, 14]) stab(at(bar, sixteenth), BEAT * .3, voicing, .115);
      for (const [sixteenth, length, interval] of BASSLINE) bass(at(bar, sixteenth), length * BEAT / 4 * .9, root + interval);
      for (let beat = 0; beat < 4; beat++) {
        bassDrum(at(bar, beat * 4));
        if (beat % 2) clap(at(bar, beat * 4));
        hat(at(bar, beat * 4 + 1), false, .24);
        hat(at(bar, beat * 4 + 2), true, .65);
        hat(at(bar, beat * 4 + 3), false, .33);
      }
    });
  }

  // Render the loop with a two-second tail, then fold the tail over its start
  // so echoes and reverb carry across the loop point. Peaks normalize to -1 dB.
  // Before sound is on, render at a common rate; playback resamples if needed.
  function renderLoop(semitones) {
    const rate = audio.context?.sampleRate ?? 48000, length = Math.round(LOOP * rate), tail = 2 * rate;
    const offline = new OfflineAudioContext(2, length + tail, rate);
    compose(offline, semitones);
    return offline.startRendering().then(rendered => {
      const buffer = new AudioBuffer({ numberOfChannels: 2, length, sampleRate: rate });
      const channels = [0, 1].map(channel => {
        const input = rendered.getChannelData(channel), output = buffer.getChannelData(channel);
        output.set(input.subarray(0, length));
        for (let i = 0; i < tail; i++) output[i] += input[length + i];
        return output;
      });
      let peak = 0;
      for (const data of channels) for (const value of data) peak = Math.max(peak, Math.abs(value));
      for (const data of channels) for (let i = 0; i < data.length; i++) data[i] *= .89 / peak;
      return buffer;
    });
  }

  // Render one transposition at a time: the pitch playback wants now, then,
  // with sound on, the scripted demo's steps. Keep a handful of renders.
  function prepare(semitones) {
    if (semitones !== undefined) audio.wanted = semitones;
    if (audio.rendering || audio.failed) return;
    const next = [audio.wanted, 0, ...(sound ? [1, 2, 3, 4] : [])].find(s => s !== undefined && !audio.buffers.has(s));
    if (next === undefined) return;
    audio.rendering = true;
    Promise.resolve().then(() => renderLoop(next)).then(buffer => {
      audio.rendering = false;
      audio.buffers.set(next, buffer);
      if (audio.buffers.size > 8) {
        const old = [...audio.buffers.keys()].find(s => (s < 0 || s > 4) && s !== audio.voice?.semitones && s !== audio.wanted);
        if (old !== undefined) audio.buffers.delete(old);
      }
      syncAudio();
      prepare();
    }, error => {
      console.warn('Demo audio:', error.message);
      audio.rendering = false;
      audio.failed = true;
      setSound(false);
      listen.textContent = 'Audio unavailable';
    });
  }

  function impulse(context, seconds = 2.6) {
    const rate = context.sampleRate;
    const length = Math.round(rate * seconds);
    const buffer = context.createBuffer(2, length, rate);
    let seed = 11;
    for (let channel = 0; channel < 2; channel++) {
      const data = buffer.getChannelData(channel);
      for (let i = 0; i < length; i++) {
        seed = (seed * 16807) % 2147483647;
        const t = i / rate;
        data[i] = (seed / 2147483647 * 2 - 1) * Math.exp(-t * 2.6) * Math.min(1, t / .012) * .5;
      }
    }
    return buffer;
  }

  function ensureAudio() {
    if (audio.failed) return false;
    if (audio.context) return true;
    try {
      const context = new AudioContext();
      const filter = context.createBiquadFilter();
      filter.Q.value = 5;
      const wet = context.createGain(), dry = context.createGain(), mix = context.createGain();
      wet.gain.value = 0;
      filter.connect(wet).connect(mix);
      dry.connect(mix);
      const reverb = context.createConvolver();
      reverb.buffer = impulse(context);
      const reverbWet = context.createGain(), reverbDry = context.createGain(), output = context.createGain();
      reverbWet.gain.value = 0;
      output.gain.value = .6;
      mix.connect(reverbDry).connect(output);
      mix.connect(reverb).connect(reverbWet).connect(output);
      output.connect(context.destination);
      Object.assign(audio, { context, filter, wet, dry, reverbWet, reverbDry, origin: 0, applied: {} });
      return true;
    } catch {
      return false;
    }
  }
  function audioPosition() {
    const position = (audio.context.currentTime - audio.origin) % LOOP;
    return position < 0 ? position + LOOP : position;
  }
  function audioRunning() { return !!audio.context && audio.context.state === 'running' && !!audio.voice; }

  // Swap to a new voice at the live loop position with a short crossfade.
  function startVoice(semitones) {
    const { context } = audio;
    const now = context.currentTime;
    const offset = audio.voice ? audioPosition() : loopClock / 1000;
    if (!audio.voice) audio.origin = now - offset;
    const source = context.createBufferSource();
    source.buffer = audio.buffers.get(semitones);
    source.loop = true;
    const level = context.createGain();
    level.gain.setValueAtTime(0, now);
    level.gain.linearRampToValueAtTime(1, now + .03);
    source.connect(level);
    level.connect(audio.filter);
    level.connect(audio.dry);
    source.start(now, offset);
    const previous = audio.voice;
    if (previous) {
      previous.level.gain.cancelScheduledValues(now);
      previous.level.gain.setValueAtTime(previous.level.gain.value, now);
      previous.level.gain.linearRampToValueAtTime(0, now + .04);
      previous.source.stop(now + .06);
    }
    audio.voice = { source, level, semitones, stopping: false };
  }

  function updateAudio(state, knob) {
    if (!audioRunning()) return;
    const { context, filter, wet, dry, reverbWet, reverbDry, applied } = audio;
    const now = context.currentTime;
    if (applied.knob !== knob) {
      applied.knob = knob;
      // At center, keep the last filter type parked at its open end, so leaving
      // bypass never sweeps up from a closed filter.
      const type = knob === 0 ? filter.type : knob > 0 ? 'highpass' : 'lowpass';
      const cutoff = knob !== 0 ? T.frequency(knob) : type === 'highpass' ? 20 : 20000;
      if (type !== filter.type) {
        filter.type = type;
        filter.frequency.cancelScheduledValues(now);
        filter.frequency.setValueAtTime(cutoff, now);
      } else filter.frequency.setTargetAtTime(cutoff, now, .025);
      wet.gain.setTargetAtTime(knob === 0 ? 0 : 1, now, .015);
      dry.gain.setTargetAtTime(knob === 0 ? 1 : 0, now, .015);
    }
    const amount = Math.round(state.reverb) / 100;
    if (applied.reverb !== amount) {
      applied.reverb = amount;
      reverbWet.gain.setTargetAtTime(.7 * amount, now, .03);
      reverbDry.gain.setTargetAtTime(1 - .35 * amount, now, .03);
    }
    const voice = audio.voice;
    if (state.stop && !voice.stopping) {
      voice.stopping = true;
      voice.source.playbackRate.cancelScheduledValues(now);
      voice.source.playbackRate.setValueAtTime(1, now);
      voice.source.playbackRate.linearRampToValueAtTime(.001, now + .9);
    } else if (!state.stop && voice.stopping) {
      startVoice(voice.semitones);
    } else if (!state.stop && Math.round(state.pitch) !== voice.semitones) {
      const semitones = Math.round(state.pitch);
      if (audio.buffers.has(semitones)) startVoice(semitones);
      else prepare(semitones);
    }
  }

  function syncAudio() {
    const shouldPlay = sound && running();
    if (shouldPlay) {
      if (!ensureAudio()) return;
      // Until the loop renders, prepare() calls back here.
      const semitones = Math.round(manual ? manual.pitch : sample(chapter, time).pitch);
      if (!audio.voice && audio.buffers.has(semitones)) startVoice(semitones);
      prepare(audio.voice ? undefined : semitones);
      if (audio.context.state !== 'running') audio.context.resume().then(kick, () => {});
    } else if (audio.context?.state === 'running') {
      audio.context.suspend();
    }
  }

  function setSound(on) {
    sound = on;
    if (on && !ensureAudio()) { sound = false; listen.textContent = 'Audio unavailable'; }
    syncAudio();
  }

  // Controls -----------------------------------------------------------------

  let shownControls = {};
  function updateControls() {
    const paused = !playing;
    if (shownControls.paused !== paused) {
      shownControls.paused = paused;
      playButton.classList.toggle('is-paused', paused);
      playButton.setAttribute('aria-label', paused ? 'Play demo' : 'Pause demo');
    }
    if (shownControls.sound !== sound) {
      shownControls.sound = sound;
      soundButton.setAttribute('aria-pressed', String(sound));
      soundButton.setAttribute('aria-label', sound ? 'Turn off sound' : 'Turn on sound');
      listen.hidden = sound;
    }
    chapters.forEach((c, i) => {
      const progress = manual ? (i < chapter ? 1 : i === chapter ? time / c.duration : 0) : i < chapter ? 1 : i === chapter ? time / c.duration : 0;
      chapterFills[i].style.transform = `scaleX(${progress.toFixed(4)})`;
      const current = i === chapter;
      if (chapterButtons[i].current !== current) {
        chapterButtons[i].current = current;
        if (current) chapterButtons[i].setAttribute('aria-current', 'step');
        else chapterButtons[i].removeAttribute('aria-current');
      }
    });
  }

  // Loop ---------------------------------------------------------------------

  let raf = 0, last = 0;
  function tick(now) {
    raf = 0;
    const dt = Math.min(now - last, 100);
    last = now;
    clock += dt;
    if (playing && !manual) {
      time += dt;
      while (time >= chapters[chapter].duration) {
        time -= chapters[chapter].duration;
        chapter = (chapter + 1) % chapters.length;
        if (chapter === 3) TwiddleDisco.loadShader().catch(() => {});
      }
    }
    render(dt);
    if (running()) raf = requestAnimationFrame(tick);
  }
  function kick() {
    if (raf) return;
    if (running()) {
      last = performance.now();
      raf = requestAnimationFrame(tick);
    } else render();
  }
  function sync() {
    syncAudio();
    kick();
  }

  playButton.addEventListener('click', () => {
    if (playing) { playing = false; sync(); }
    else resume();
  });
  controls.querySelector('.control-replay').addEventListener('click', () => seek(0));
  soundButton.addEventListener('click', () => setSound(!sound));
  listen.addEventListener('click', () => {
    setSound(true);
    seek(0);
  });
  chapterButtons.forEach((button, i) => button.addEventListener('click', () => seek(i)));
  menuToggle.addEventListener('click', () => {
    takeover(false);
    manual.open = !manual.open;
    if (!manual.open) manual.stop = false;
    kick();
  });
  fxButton.addEventListener('click', () => {
    takeover(false);
    manual.fxTarget = manual.fxTarget ? 0 : 1;
    if (!manual.fxTarget) manual.stop = false;
    kick();
  });
  const hold = on => {
    if (on) takeover(true);
    if (!manual) return;
    manual.stop = on;
    kick();
  };
  stopButton.addEventListener('pointerdown', event => { if (event.button === 0) { stopButton.setPointerCapture(event.pointerId); hold(true); } });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) stopButton.addEventListener(type, () => hold(false));
  stopButton.addEventListener('keydown', event => { if ((event.key === ' ' || event.key === 'Enter') && !event.repeat) { event.preventDefault(); hold(true); } });
  stopButton.addEventListener('keyup', event => { if (event.key === ' ' || event.key === 'Enter') hold(false); });
  discoButton.addEventListener('click', () => {
    takeover(false);
    manual.discoOn = !manual.discoOn;
    kick();
  });
  // Keyboard focus inside the desktop hands control to the visitor.
  stage.addEventListener('focusin', () => { if (!manual) takeover(false); });
  frame.addEventListener('keydown', event => {
    if (event.key === 'Escape' && manual?.discoOn) { manual.discoOn = false; kick(); }
  });

  T.onVisible(frame, visible => { inView = visible; sync(); }, .15);
  // Start rendering the loop as soon as the visitor reaches for the demo.
  for (const type of ['pointerenter', 'focusin']) frame.addEventListener(type, () => prepare(), { once: true });
  document.addEventListener('visibilitychange', sync);
  window.addEventListener('pagehide', () => { audio.context?.suspend(); });
  T.reducedMotion.addEventListener('change', () => { if (T.reducedMotion.matches && playing) { playing = false; sync(); } });
  new ResizeObserver(measure).observe(frame);
  updateMenuTime();
  setInterval(() => { updateMenuTime(); measure(); }, 30_000);
  document.fonts?.ready.then(measure);
  if (poster) time = 3000;
  measure();
})();
