// Animated feature cards. Each visual plays while its card is on screen and can be paused.
(() => {
  const T = window.Twiddle;
  if (!T) return;
  const SVG = 'http://www.w3.org/2000/svg';
  const { keyframes, step } = T;
  const svg = (name, attributes, parent) => {
    const element = document.createElementNS(SVG, name);
    for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, value);
    parent?.append(element);
    return element;
  };
  const once = (element, key, value, apply) => {
    if (element[key] === value) return;
    element[key] = value;
    apply(value);
  };

  // A filter's response, sweeping from low-pass through bypass to high-pass.
  function curve(inner) {
    const graph = inner.querySelector('.curve');
    const grid = graph.querySelector('.curve-grid');
    const line = graph.querySelector('.curve-line');
    const area = graph.querySelector('.curve-area');
    const dot = graph.querySelector('.curve-dot');
    const type = inner.querySelector('.curve-type');
    const hz = inner.querySelector('.curve-hz');
    const left = 30, right = 482, top = 72, bottom = 272;
    const x = f => left + (right - left) * Math.log(f / 20) / Math.log(1000);
    const y = db => top + (bottom - top) * (12 - db) / 54;
    for (const f of [50, 100, 200, 500, 1000, 2000, 5000, 10000]) svg('line', { x1: x(f), x2: x(f), y1: top - 8, y2: bottom }, grid);
    for (const db of [0, -12, -24, -36]) svg('line', { x1: left, x2: right, y1: y(db), y2: y(db), class: db === 0 ? 'zero' : '' }, grid);
    for (const [f, text] of [[100, '100 Hz'], [1000, '1 kHz'], [10000, '10 kHz']]) svg('text', { x: x(f) + 5, y: bottom - 6 }, grid).textContent = text;
    svg('text', { x: right - 26, y: y(0) - 6 }, grid).textContent = '0 dB';
    const samples = Array.from({ length: 140 }, (_, i) => 20 * Math.pow(1000, i / 139));
    const track = [[0, 0], [700, 0], [2300, -72], [3300, -72], [4300, -30], [5300, -30], [6000, 0], [6700, 0], [8100, 60], [9100, 60], [9800, 0], [10400, 0]];
    return {
      poster: 2600,
      frame(t) {
        const value = Math.round(keyframes(track, t % 10400) * 10) / 10;
        const bypass = Math.abs(value) < .5;
        graph.toggleAttribute('data-bypass', bypass);
        let d = '';
        samples.forEach((f, i) => {
          const db = 20 * Math.log10(Math.max(T.gain(bypass ? 0 : value, f), 1e-4));
          d += `${i ? 'L' : 'M'}${x(f).toFixed(1)} ${Math.min(bottom + 6, y(db)).toFixed(1)}`;
        });
        line.setAttribute('d', d);
        area.setAttribute('d', `${d}L${right} ${bottom + 6}L${left} ${bottom + 6}Z`);
        if (!bypass) {
          const cutoff = T.frequency(value);
          dot.setAttribute('cx', x(cutoff).toFixed(1));
          dot.setAttribute('cy', y(20 * Math.log10(T.gain(value, cutoff))).toFixed(1));
        }
        once(type, 'shown', bypass ? 'Bypass' : value < 0 ? 'Low-pass' : 'High-pass', text => { type.textContent = text; });
        once(hz, 'shown', bypass ? 'Original sound' : T.hz(value), text => { hz.textContent = text; });
      },
    };
  }

  // ⌥F10 to the preset, ⌥F12 twice to step up, ⌥F10 to go back.
  function keys(inner) {
    const dial = new T.Dial(inner.querySelector('.dial'));
    const caps = Object.fromEntries([...inner.querySelectorAll('kbd')].map(key => [key.dataset.key, key]));
    const action = inner.querySelector('.keys-action');
    const hz = inner.querySelector('.keys-hz');
    const pressed = [[0, []], [700, ['option']], [760, ['option', 'f10']], [1000, ['option']], [1100, []],
      [2600, ['option']], [2660, ['option', 'f12']], [2840, ['option']], [3200, ['option', 'f12']], [3380, ['option']], [3480, []],
      [5000, ['option']], [5060, ['option', 'f10']], [5300, ['option']], [5400, []]];
    const value = [[0, 0], [760, 0], [940, -60, 'out'], [2660, -60], [2820, -50, 'out'], [3200, -50], [3360, -40, 'out'], [5060, -40], [5240, 0, 'out']];
    const labels = [[0, 'Bypass'], [760, 'Your preset'], [2660, 'Step up'], [5060, 'Bypass']];
    return {
      poster: 1600,
      frame(t) {
        t %= 7000;
        const now = step(pressed, t, []);
        for (const [name, key] of Object.entries(caps)) key.classList.toggle('is-down', now.includes(name));
        const v = Math.round(keyframes(value, t) * 10) / 10;
        dial.set(v);
        once(action, 'shown', step(labels, t), text => { action.textContent = text; });
        once(hz, 'shown', v === 0 ? 'Original sound' : T.label(v), text => { hz.textContent = text; });
      },
    };
  }

  // Three triggers, one preset: the filter holds while any of them is active.
  function lanes(inner) {
    const blocks = { mic: [[.05, .27]], say: [[.37, .52]], app: [[.46, .74]] };
    const rows = Object.fromEntries([...inner.querySelectorAll('.lane')].map(row => [row.dataset.lane, row]));
    const segments = [];
    for (const [name, ranges] of Object.entries(blocks)) {
      for (const [from, to] of ranges) {
        const block = document.createElement('i');
        block.style.left = `${from * 100}%`;
        block.style.width = `${(to - from) * 100}%`;
        rows[name].querySelector('.lane-track').append(block);
        segments.push({ name, from, to, block });
      }
    }
    const active = position => segments.some(s => position >= s.from && position < s.to);
    // Ease into the preset in 180 ms and back out in 400 ms, on a nine-second lane.
    const level = position => {
      let value = 0;
      for (let p = 0; p <= position; p += .002) value = active(p) ? Math.min(1, value + .002 / .02) : Math.max(0, value - .002 / .044);
      return value;
    };
    const levels = Array.from({ length: 501 }, (_, i) => level(i / 500));
    const path = levels.map((v, i) => `${i ? 'L' : 'M'}${i * 2} ${(88 - 70 * v).toFixed(2)}`).join('');
    const curveSvg = inner.querySelector('.lane-curve');
    curveSvg.setAttribute('viewBox', '0 0 1000 100');
    inner.querySelector('.lane-curve-line').setAttribute('d', path);
    inner.querySelector('.lane-curve-area').setAttribute('d', `${path}L1000 100L0 100Z`);
    const playhead = inner.querySelector('.playhead');
    return {
      poster: 1500,
      frame(t) {
        const position = (t % 9000) / 9000;
        playhead.style.translate = `${(164 + position * 310).toFixed(1)}px 0`;
        for (const s of segments) s.block.classList.toggle('is-active', position >= s.from && position < s.to);
        for (const name of Object.keys(blocks)) rows[name].classList.toggle('is-active', segments.some(s => s.name === name && position >= s.from && position < s.to));
        rows.filter.classList.toggle('is-active', levels[Math.round(position * 500)] > .5);
      },
    };
  }

  function fx(inner) {
    const reverb = new T.Dial(inner.querySelector('.fx-reverb .dial'));
    const pitch = new T.Dial(inner.querySelector('.fx-pitch .dial'));
    const stop = inner.querySelector('.fx-stop');
    const readout = inner.querySelector('.fx-readout');
    const reverbTrack = [[0, 0], [600, 0], [1900, 70], [8200, 70], [8900, 0]];
    const pitchTrack = [[0, 0], [2600, 1], [2750, 2], [2900, 3], [3050, 4], [3200, 5], [4400, 4], [4550, 3], [4700, 2], [4850, 1], [5000, 0]];
    const held = [[0, false], [5800, true], [7300, false]];
    return {
      poster: 3300,
      frame(t) {
        t %= 9400;
        const r = keyframes(reverbTrack, t);
        const p = step(pitchTrack, t, 0);
        const stopped = step(held, t, false);
        reverb.set(r);
        pitch.set(p * 100 / 12);
        stop.classList.toggle('is-held', stopped);
        const text = t >= 5600 && t < 7500 ? (stopped ? 'Tape stop' : 'Back in') : t >= 2400 && t < 5400 ? `Pitch ${p > 0 ? '+' : ''}${p} semitone${Math.abs(p) === 1 ? '' : 's'}` : `Reverb ${Math.round(r)}%`;
        once(readout, 'shown', text, value => { readout.textContent = value; });
      },
    };
  }

  // Each tick passed while turning sends a light haptic pulse.
  function haptics(inner) {
    const dial = new T.Dial(inner.querySelector('.dial'));
    const pad = inner.querySelector('.trackpad');
    const ripples = [...inner.querySelectorAll('.ripple')];
    let lastTick = null, next = 0;
    return {
      poster: 1400,
      frame(t) {
        const value = 56 * Math.sin(t / 6000 * Math.PI * 2);
        dial.set(value);
        pad.style.setProperty('--finger-y', `${(-value * .4).toFixed(1)}px`);
        const tick = Math.round(value / 10);
        if (lastTick !== null && tick !== lastTick && !T.reducedMotion.matches) {
          const ripple = ripples[next++ % ripples.length];
          ripple.classList.remove('is-pulsing');
          void ripple.offsetWidth;
          ripple.classList.add('is-pulsing');
        }
        lastTick = tick;
      },
    };
  }

  // The real disco shader, with the ball hanging from a much taller virtual screen.
  function disco(inner) {
    const beams = inner.querySelector('.card-beams');
    const sphere = inner.querySelector('.card-sphere');
    const width = 506, height = 304, screenWidth = 2400, screenHeight = 1480;
    let renderer = null, loading = false, failed = false, scale = 1;
    sphere.style.left = `${width / 2 - 80}px`;
    sphere.style.top = '0';
    const layout = () => {
      if (!renderer) return;
      const dpr = Math.min(devicePixelRatio, 2);
      renderer.layout(screenWidth, screenHeight, [
        { x: (screenWidth - width) / 2, y: 0, w: width, h: height, scale: Math.min(scale * dpr, 1.5) },
        { x: screenWidth / 2 - 80, y: 0, w: 160, h: 230, scale: scale * dpr },
      ]);
    };
    const track = [[0, 0], [300, 0], [1420, 1.12, 'linear'], [8000, 1.12], [9120, 0, 'linear'], [9600, 0]];
    let latest = 0;
    return {
      poster: 4000,
      resize(next) { scale = next; layout(); },
      frame(t) {
        latest = t;
        if (!renderer && !loading && !failed) {
          loading = true;
          TwiddleDisco.createRenderer(beams, sphere)
            .then(created => { renderer = created; layout(); this.frame(latest); })
            .catch(() => { failed = true; inner.querySelector('.disco-card').classList.add('no-gl'); })
            .finally(() => { loading = false; });
        }
        if (!renderer || renderer.lost) return;
        renderer.draw(t / 1000, T.reducedMotion.matches ? 1.12 : keyframes(track, t % 9600));
      },
    };
  }

  // The CLI's real response shape: one line of JSON with sorted keys.
  function cli(inner) {
    const body = inner.querySelector('.terminal-body');
    const json = object => '{' + Object.entries(object).map(([key, value]) =>
      `<span class="key">"${key}"</span>:<span class="value">${JSON.stringify(value).replace(/"/g, '&quot;')}</span>`).join(',') + '}';
    const state = { audioError: null, autoApplyActive: false, automationSuppressed: false, baseline: -0.5, disco: false, ok: true, preset: -0.6, running: true, target: -0.5, targetApps: ['com.spotify.client'], triggerApps: [], value: -0.03 };
    const script = [
      { command: 'twiddle set -0.5', output: json(state) },
      { command: 'twiddle disco on', output: json({ ...state, autoApplyActive: true, disco: true, target: -0.6, value: -0.52 }) },
    ];
    const timeline = [];
    let at = 500;
    for (const item of script) {
      timeline.push({ ...item, start: at, typed: at + item.command.length * 55, printed: at + item.command.length * 55 + 350 });
      at += item.command.length * 55 + 2600;
    }
    const duration = at + 1600;
    return {
      poster: duration - 1700,
      frame(t) {
        t %= duration;
        let html = '';
        let typing = false;
        for (const item of timeline) {
          if (t < item.start) break;
          const chars = Math.min(item.command.length, Math.floor((t - item.start) / 55));
          html += `<span class="prompt">~ %</span> ${item.command.slice(0, chars)}`;
          if (t < item.printed) { typing = true; html += '<span class="caret"></span>\n'; break; }
          html += `\n${item.output}\n\n`;
        }
        if (!typing) html += '<span class="prompt">~ %</span> <span class="caret"></span>';
        once(body, 'shown', html, value => { body.innerHTML = value; });
      },
    };
  }

  const visuals = { curve, keys, lanes, fx, haptics, disco, cli, apps: () => ({}) };

  document.querySelectorAll('.card[data-visual]').forEach(card => {
    const inner = card.querySelector('.inner');
    const title = card.querySelector('h3').textContent;
    const pause = card.querySelector('.pause');
    const visual = visuals[card.dataset.visual](inner);
    let visible = false, paused = T.reducedMotion.matches, raf = 0, last = 0;
    let time = paused ? visual.poster ?? 0 : 0;
    T.fit(card.querySelector('.fit'), inner, 506, scale => visual.resize?.(scale));
    const playing = () => visible && !paused && !document.hidden;
    const loop = now => {
      raf = 0;
      time += Math.min(now - last, 100);
      last = now;
      visual.frame?.(time);
      if (playing()) raf = requestAnimationFrame(loop);
    };
    const update = () => {
      card.classList.toggle('is-playing', playing());
      pause.setAttribute('aria-pressed', String(paused));
      pause.setAttribute('aria-label', `${paused ? 'Play' : 'Pause'} the ${title} animation`);
      if (playing() && !raf && visual.frame) {
        last = performance.now();
        raf = requestAnimationFrame(loop);
      }
    };
    visual.frame?.(time);
    pause.addEventListener('click', () => { paused = !paused; update(); });
    T.onVisible(card, next => { visible = next; update(); }, .1);
    document.addEventListener('visibilitychange', update);
    update();
  });

  // Fade sections in as they scroll into view.
  const reveal = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.dataset.shown = '';
      reveal.unobserve(entry.target);
    }
  }, { threshold: .12, rootMargin: '0px 0px -40px 0px' });
  document.querySelectorAll('.section h2, .card, .intro, .shortcuts, .steps').forEach((element, i) => {
    if (element.getBoundingClientRect().top < innerHeight) return;
    element.dataset.reveal = '';
    if (element.classList.contains('card')) element.style.setProperty('--delay', `${(i % 2) * 90}ms`);
    reveal.observe(element);
  });
})();
