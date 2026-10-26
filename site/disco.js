(() => {
  // Renders disco.frag.glsl into a pair of canvases: soft screen-wide beams and a
  // sharp mirrored ball. The page overlay, the demo and the disco card share it.
  let shader = null;
  function loadShader() {
    shader ||= fetch('disco.frag.glsl').then(response => {
      if (!response.ok) throw new Error('Shader unavailable');
      return response.text();
    });
    return shader;
  }

  function createPass(element, fragment, onLost) {
    const gl = element.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: false, depth: false, powerPreference: 'low-power' });
    if (!gl) throw new Error('WebGL unavailable');
    const compile = (type, source) => {
      const compiled = gl.createShader(type);
      gl.shaderSource(compiled, source);
      gl.compileShader(compiled);
      if (!gl.getShaderParameter(compiled, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(compiled));
      return compiled;
    };
    const vertex = compile(gl.VERTEX_SHADER, `#version 300 es
    void main() {
      vec2 positions[3] = vec2[3](vec2(-1.,-1.),vec2(3.,-1.),vec2(-1.,3.));
      gl_Position=vec4(positions[gl_VertexID],0.,1.);
    }`);
    const pixel = compile(gl.FRAGMENT_SHADER, fragment);
    const program = gl.createProgram();
    gl.attachShader(program, vertex);
    gl.attachShader(program, pixel);
    gl.linkProgram(program);
    gl.deleteShader(vertex);
    gl.deleteShader(pixel);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
    gl.useProgram(program);
    const uniforms = Object.fromEntries(['canvas', 'viewport', 'timing', 'resolution'].map(name => [name, gl.getUniformLocation(program, name)]));
    element.addEventListener('webglcontextlost', onLost);
    return { element, gl, uniforms };
  }

  async function createRenderer(beams, sphere) {
    const fragment = await loadShader();
    const renderer = { lost: false };
    const passes = [beams, sphere].map(element => createPass(element, fragment, () => { renderer.lost = true; }));
    // `width` × `height` is the virtual screen the ball hangs in. Each view is the
    // part of that screen a canvas shows, in CSS pixels, with its pixel density.
    renderer.layout = (width, height, views) => {
      passes.forEach((pass, i) => {
        const { x, y, w, h, scale } = views[i];
        pass.element.width = Math.max(1, Math.round(w * scale));
        pass.element.height = Math.max(1, Math.round(h * scale));
        pass.element.style.width = `${w}px`;
        pass.element.style.height = `${h}px`;
        const { gl, uniforms } = pass;
        gl.viewport(0, 0, pass.element.width, pass.element.height);
        gl.uniform4f(uniforms.canvas, width, height, 1 / (scale * height), i);
        gl.uniform4f(uniforms.viewport, x, y, w, h);
        gl.uniform2f(uniforms.resolution, pass.element.width, pass.element.height);
      });
    };
    // The sphere view used by the native overlay: centered at the top of the screen.
    renderer.sphereView = (width, height, scale) => {
      const w = Math.max(160, height * .16);
      const h = Math.min(height, Math.max(180, height * .18));
      return { x: (width - w) / 2, y: 0, w, h, scale };
    };
    renderer.draw = (seconds, deployment) => {
      for (const { gl, uniforms } of passes) {
        gl.uniform4f(uniforms.timing, seconds, deployment, 0, 0);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }
    };
    return renderer;
  }
  window.TwiddleDisco = { createRenderer, loadShader };

  // Sweep the pointer across every letter of the wordmark or headline to start disco mode.
  const brand = document.querySelector('.brand');
  const overlay = document.querySelector('.disco');
  const heading = document.querySelector('h1');
  if (!brand || !overlay || !heading) return;
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const boundaries = [0, .119, .355, .411, .583, .755, .834, 1];
  const palette = ['#ff5366', '#ff963b', '#f4db58', '#66d588', '#65d4db', '#649aff', '#b88bff', '#ed81bf'];
  const logoLetters = boundaries.slice(0, -1).map((left, i) => {
    const letter = document.createElement('span');
    letter.style.left = `${left * 100}%`;
    letter.style.width = `${(boundaries[i + 1] - left) * 100}%`;
    brand.querySelector('.disco-color').append(letter);
    return letter;
  });
  heading.classList.add('disco-heading');
  heading.setAttribute('aria-label', heading.innerText.replace(/\s+/g, ' '));
  const headingLetters = [];
  for (const node of [...heading.childNodes]) {
    if (node.nodeType !== Node.TEXT_NODE) continue;
    const fragment = document.createDocumentFragment();
    for (const character of node.textContent) {
      if (!/[a-z]/i.test(character)) { fragment.append(character); continue; }
      const letter = document.createElement('span');
      letter.textContent = character;
      letter.setAttribute('aria-hidden', 'true');
      headingLetters.push(letter);
      fragment.append(letter);
    }
    node.replaceWith(fragment);
  }
  const groups = [
    { element: brand, letters: logoLetters, logo: true, visited: new Set(), previous: null },
    { element: heading, letters: headingLetters, logo: false, visited: new Set(), previous: null },
  ];
  let owner = null;
  function tint(group, letter, color) {
    if (group.logo) {
      letter.style.backgroundColor = color || '';
      letter.style.opacity = color ? '.95' : '0';
    } else letter.style.color = color || '';
  }
  function resetGroup(group) {
    group.visited.clear();
    group.previous = null;
    group.element.dataset.discoVisited = '0';
    group.element.classList.remove('disco-active');
    group.letters.forEach(letter => tint(group, letter, null));
  }
  // Segment/rectangle intersection catches letters crossed between pointer events.
  function crossed(from, to, rect) {
    let low = 0, high = 1;
    for (const [start, delta, min, max] of [
      [from.x, to.x - from.x, rect.left, rect.right],
      [from.y, to.y - from.y, rect.top, rect.bottom],
    ]) {
      if (delta === 0) { if (start < min || start > max) return false; }
      else {
        const a = (min - start) / delta, b = (max - start) / delta;
        low = Math.max(low, Math.min(a, b));
        high = Math.min(high, Math.max(a, b));
        if (low > high) return false;
      }
    }
    return true;
  }
  function visit(group, event) {
    if (owner || reducedMotion.matches) return;
    const point = { x: event.clientX, y: event.clientY };
    group.letters.forEach((letter, i) => {
      if (!group.visited.has(i) && crossed(group.previous || point, point, letter.getBoundingClientRect())) {
        group.visited.add(i);
        tint(group, letter, palette[i % palette.length]);
      }
    });
    group.previous = point;
    group.element.dataset.discoVisited = String(group.visited.size);
    if (group.visited.size === group.letters.length) {
      owner = group;
      group.element.classList.add('disco-active');
      show();
    }
  }
  let renderer, initializing, active = false, frame = 0, deployment = 0;
  let previous = 0, started = 0, lastColors = 0, unavailable = false;

  async function initialize() {
    if (renderer) return;
    initializing ||= createRenderer(overlay.querySelector('.disco-beams'), overlay.querySelector('.disco-sphere')).then(created => {
      renderer = created;
      resize();
    });
    return initializing;
  }

  function resize() {
    if (!renderer) return;
    const width = innerWidth, height = innerHeight;
    // Match the native split: soft screen-wide beams, sharp mirrored tiles.
    renderer.layout(width, height, [
      { x: 0, y: 0, w: width, h: height, scale: Math.min(1, 600 / height) },
      renderer.sphereView(width, height, Math.min(devicePixelRatio, 2)),
    ]);
  }

  function paint(now) {
    frame = 0;
    if (renderer.lost) { unavailable = true; stop(); return; }
    const elapsed = Math.min((now - previous) / 1000, .05);
    previous = now;
    deployment = Math.max(0, Math.min(1.12, deployment + (active ? elapsed : -elapsed)));
    if (!active && deployment === 0) { overlay.hidden = true; return; }
    renderer.draw((now - started) / 1000, deployment);
    if (active && now - lastColors > 220) {
      lastColors = now;
      owner?.letters.forEach(letter => {
        tint(owner, letter, Math.random() < .48 ? palette[Math.floor(Math.random() * palette.length)] : null);
      });
    }
    frame = requestAnimationFrame(paint);
  }

  async function show() {
    if (reducedMotion.matches || unavailable || document.hidden) { hide(); return; }
    active = true;
    try { await initialize(); }
    catch (error) { unavailable = true; stop(); console.warn('Disco renderer:', error.message); return; }
    if (!active) return;
    overlay.hidden = false;
    if (!frame) {
      previous = performance.now();
      if (!started) started = previous;
      frame = requestAnimationFrame(paint);
    }
  }
  function hide() {
    active = false;
    groups.forEach(resetGroup);
    owner = null;
  }
  function stop() {
    hide();
    cancelAnimationFrame(frame);
    frame = 0;
    deployment = 0;
    overlay.hidden = true;
  }
  groups.forEach(group => {
    group.element.addEventListener('pointerenter', event => visit(group, event));
    group.element.addEventListener('pointermove', event => visit(group, event));
    group.element.addEventListener('pointerleave', () => { if (owner !== group) resetGroup(group); });
    group.element.addEventListener('pointerdown', () => { group.dismissOnClick = owner !== null; });
    group.element.addEventListener('click', event => {
      if (owner) {
        event.preventDefault();
        if (group.dismissOnClick) hide();
      }
    });
    group.element.addEventListener('dragstart', event => event.preventDefault());
  });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') hide(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
  window.addEventListener('pagehide', stop);
  window.addEventListener('scroll', stop, { passive: true });
  window.addEventListener('resize', resize);
  reducedMotion.addEventListener('change', () => { if (reducedMotion.matches) stop(); });
})();
