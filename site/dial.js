// Shared pieces of Twiddle's knob: geometry, filter curves, and small layout helpers.
(() => {
  const SVG = 'http://www.w3.org/2000/svg';
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const clamp = (x, low, high) => Math.min(high, Math.max(low, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const smoothstep = x => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };
  const ease = {
    linear: x => x,
    in: x => x * x * x,
    out: x => 1 - Math.pow(1 - x, 3),
    inOut: x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
    step: x => x < 1 ? 0 : 1,
  };

  // The app's cutoff mapping: low-pass 20 kHz to 115 Hz, high-pass 20 Hz to 10 kHz.
  function frequency(value) {
    const amount = Math.abs(value) / 100;
    return value < 0 ? 20000 * Math.pow(115 / 20000, amount) : 20 * Math.pow(500, amount);
  }
  function hz(value) { return `${Math.round(frequency(value)).toLocaleString('en-US')} Hz`; }
  function label(value) {
    if (value === 0) return 'Bypass';
    return `${value < 0 ? 'Low-pass' : 'High-pass'} · ${hz(value)}`;
  }

  // Grey at the center, warming to Twiddle orange within the first 20 degrees of travel.
  function accent(amount) {
    const a = smoothstep(Math.abs(amount) / (20 / 135));
    return `rgb(${Math.round(140 + 111 * a)} ${Math.round(140 - 22 * a)} ${Math.round(140 - 140 * a)})`;
  }

  // Magnitude of a Web Audio biquad (Audio EQ Cookbook) at frequency f. Q is resonance in dB.
  function response(type, cutoff, f, resonance = 5, rate = 48000) {
    const w0 = 2 * Math.PI * Math.min(cutoff, rate / 2 - 1) / rate;
    const cos = Math.cos(w0);
    const alpha = Math.sin(w0) / (2 * Math.pow(10, resonance / 20));
    const b0 = type === 'lowpass' ? (1 - cos) / 2 : (1 + cos) / 2;
    const b1 = type === 'lowpass' ? 1 - cos : -(1 + cos);
    const a0 = 1 + alpha, a1 = -2 * cos, a2 = 1 - alpha;
    const w = 2 * Math.PI * f / rate;
    const c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w);
    const nr = b0 + b1 * c1 + b0 * c2, ni = -(b1 * s1 + b0 * s2);
    const dr = a0 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2);
    return Math.sqrt((nr * nr + ni * ni) / (dr * dr + di * di));
  }
  // Gain of the main filter at knob position `value`, matching the demo's audio.
  function gain(value, f) {
    if (value === 0) return 1;
    return response(value < 0 ? 'lowpass' : 'highpass', frequency(value), f);
  }

  function point(degrees, radius) {
    const angle = (degrees - 90) * Math.PI / 180;
    return [110 + Math.cos(angle) * radius, 102 + Math.sin(angle) * radius];
  }

  // A wheel gesture that is already scrolling the page should keep scrolling it.
  let lastScroll = -Infinity;
  addEventListener('scroll', () => { lastScroll = performance.now(); }, { passive: true });

  const TEMPLATE = '<svg class="dial-scale" viewBox="0 0 220 204" aria-hidden="true"><g class="dial-ticks"></g><path class="dial-track" d="M49.9 162.1 A85 85 0 1 1 170.1 162.1"/><path class="dial-arc"/></svg><div class="dial-body"><div class="dial-face"><div class="dial-detail"></div></div><div class="dial-pointer"></div></div>';

  // A knob from -100 to 100 (bipolar) or 0 to 100 (unipolar). Pass `input` to make it draggable.
  class Dial {
    constructor(element, { mode = element.dataset.mode || 'bipolar', value = 0, input = null, grab = null, reset = null, steps = 0 } = {}) {
      this.element = element;
      this.mode = mode;
      this.steps = steps;
      this.value = NaN;
      if (!element.querySelector('.dial-scale')) element.innerHTML = TEMPLATE;
      this.arc = element.querySelector('.dial-arc');
      this.ticks = [];
      const group = element.querySelector('.dial-ticks');
      for (let i = -10; i <= 10; i++) {
        const line = document.createElementNS(SVG, 'line');
        const [x1, y1] = point(i * 13.5, 94);
        const [x2, y2] = point(i * 13.5, i === 0 && mode === 'bipolar' ? 102 : 98);
        Object.entries({ x1, y1, x2, y2 }).forEach(([key, v]) => line.setAttribute(key, v.toFixed(2)));
        group.append(line);
        this.ticks.push(line);
      }
      this.set(value);
      if (input) this.listen(input, grab, reset);
    }

    min() { return this.mode === 'unipolar' ? 0 : -100; }

    set(next) {
      const value = clamp(Math.round(next * 10) / 10, this.min(), 100);
      if (value === this.value) return;
      this.value = value;
      const unipolar = this.mode === 'unipolar';
      const degrees = unipolar ? -135 + value * 2.7 : value * 1.35;
      const amount = value / 100;
      const color = accent(amount);
      const style = this.element.style;
      style.setProperty('--angle', `${degrees}deg`);
      style.setProperty('--detail-angle', `${degrees}deg`);
      style.setProperty('--dial-accent', color);
      const [ex, ey] = point(degrees, 85);
      if (unipolar) {
        this.arc.setAttribute('d', value <= 0 ? '' : `M49.9 162.1 A85 85 0 ${degrees + 135 > 180 ? 1 : 0} 1 ${ex.toFixed(2)} ${ey.toFixed(2)}`);
      } else {
        this.arc.setAttribute('d', value === 0 ? '' : `M110 17 A85 85 0 0 ${value > 0 ? 1 : 0} ${ex.toFixed(2)} ${ey.toFixed(2)}`);
      }
      this.ticks.forEach((tick, i) => {
        const tickValue = unipolar ? i * 5 : (i - 10) * 10;
        const swept = unipolar
          ? value > 0 && tickValue <= value
          : value !== 0 && (value < 0 ? tickValue <= 0 && tickValue >= value : tickValue >= 0 && tickValue <= value);
        tick.style.stroke = swept ? color : !unipolar && i === 10 ? '#fff' : '';
      });
    }

    listen(input, grab, reset) {
      const element = this.element;
      let drag = null;
      element.dataset.interactive = '';
      const emit = (value, smooth) => {
        let next = clamp(value, this.min(), 100);
        if (this.steps && !smooth) next = Math.round(next / (200 / this.steps)) * (200 / this.steps);
        if (this.mode === 'bipolar' && !this.steps && Math.abs(next) < 1.5) next = 0;
        // Update now so repeated keys and wheel ticks within one frame accumulate.
        this.set(next);
        input(next);
      };
      element.addEventListener('pointerdown', event => {
        if (!event.isPrimary || event.button !== 0) return;
        grab?.();
        element.dataset.pointer = '';
        element.focus({ preventScroll: true });
        element.setPointerCapture(event.pointerId);
        drag = { id: event.pointerId, y: event.clientY, value: this.value };
        event.preventDefault();
      });
      element.addEventListener('pointermove', event => {
        if (!drag || drag.id !== event.pointerId) return;
        const scale = element.getBoundingClientRect().height / 164;
        const delta = (drag.y - event.clientY) / scale;
        emit(drag.value + delta * (event.shiftKey ? .1 : .8));
      });
      const end = () => { drag = null; };
      element.addEventListener('lostpointercapture', end);
      element.addEventListener('pointercancel', end);
      element.addEventListener('pointerup', event => {
        if (element.hasPointerCapture(event.pointerId)) element.releasePointerCapture(event.pointerId);
      });
      element.addEventListener('keydown', event => {
        delete element.dataset.pointer;
        const step = this.steps ? 200 / this.steps : event.shiftKey ? .5 : 2.5;
        const values = { ArrowRight: this.value + step, ArrowUp: this.value + step, ArrowLeft: this.value - step, ArrowDown: this.value - step, Home: this.min(), End: 100 };
        if (event.key === '0' || event.key === 'Enter') { event.preventDefault(); grab?.(); reset?.(); return; }
        if (!(event.key in values)) return;
        event.preventDefault();
        grab?.();
        emit(values[event.key], true);
      });
      element.addEventListener('dblclick', () => { grab?.(); reset?.(); });
      // Scrolling up raises the value, matching an upward drag in the app.
      element.addEventListener('wheel', event => {
        if (performance.now() - lastScroll < 400 && document.activeElement !== element) return;
        event.preventDefault();
        grab?.();
        emit(this.value - event.deltaY * (event.shiftKey ? .012 : .12), true);
      }, { passive: false });
    }
  }

  // Scale a fixed-size inner element to its container's width.
  function fit(container, inner, width, callback) {
    const update = () => {
      const scale = container.clientWidth / width;
      inner.style.transform = `scale(${scale})`;
      callback?.(scale);
    };
    new ResizeObserver(update).observe(container);
    update();
  }

  // Keyframe tracks: [[time, value, easing]] interpolates; step() holds the latest value.
  function keyframes(track, t) {
    if (!track) return undefined;
    if (t <= track[0][0]) return track[0][1];
    for (let i = 1; i < track.length; i++) {
      const [time, value, curve = 'inOut'] = track[i];
      if (t < time) {
        const [start, from] = track[i - 1];
        return lerp(from, value, ease[curve]((t - start) / (time - start)));
      }
    }
    return track[track.length - 1][1];
  }
  function step(track, t, fallback) {
    if (!track) return fallback;
    let value = track[0][1];
    for (const [time, next] of track) { if (t >= time) value = next; else break; }
    return value;
  }

  function onVisible(element, callback, threshold = .2) {
    new IntersectionObserver(([entry]) => callback(entry.isIntersecting), { threshold }).observe(element);
  }

  window.Twiddle = { Dial, frequency, hz, label, accent, response, gain, clamp, lerp, smoothstep, ease, keyframes, step, fit, onVisible, reducedMotion };
})();
