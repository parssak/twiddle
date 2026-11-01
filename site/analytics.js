// PostHog page analytics. Memory persistence sets no cookies or localStorage,
// so a visitor counts once per page load and no consent banner is needed.
(() => {
  const key = 'phc_ncXfH39L3dD95XzjpxVCXqq8HdzJRywMn68SrrJCGxM9'; // Public write-only project key. gitleaks:allow
  const host = 'https://us.i.posthog.com';
  if (location.hostname !== 'twiddle.fun') return;

  // Official PostHog loader: queues calls until array.js arrives.
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="init capture register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset identify alias set_config".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);

  posthog.init(key, {
    api_host: host,
    persistence: 'memory',
    person_profiles: 'identified_only',
    capture_pageview: true,
    capture_pageleave: true,
    autocapture: true,
    disable_session_recording: true,
    disable_surveys: true,
  });

  // Named events for the clicks that matter, so funnels don't depend on autocapture selectors.
  document.addEventListener('click', (event) => {
    const el = event.target.closest('[data-track], .listen, .control-sound, .chapters button');
    if (!el) return;
    if (el.dataset.track) {
      const [name, placement] = el.dataset.track.split(':');
      posthog.capture(name, { placement, href: el.href });
    } else if (el.matches('.chapters button')) {
      posthog.capture('demo_chapter', { chapter: el.textContent.trim().replace(/^\d/, '') });
    } else if (el.matches('.listen') || el.getAttribute('aria-pressed') === 'false') {
      posthog.capture('demo_sound_on', { placement: el.matches('.listen') ? 'play_button' : 'toggle' });
    }
  }, { capture: true });
})();
