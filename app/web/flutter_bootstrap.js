{{flutter_js}}
{{flutter_build_config}}

// Renderer choice. The wasm renderer (skwasm, Flutter 3.41) corrupts its own
// heap after 10-30 s of match load — "memory access out of bounds" inside
// paragraph layout / picture recording, in both multi- and single-threaded
// mode — which freezes or blacks out the screen. CanvasKit is stable, so it
// is the default. `?renderer=skwasm` (single-threaded) or
// `?renderer=skwasm-mt` opt back in for testing; `?renderer=canvaskit`
// resets. The choice is remembered in localStorage `rr_renderer`.
(function () {
  var r = null;
  try {
    r = new URLSearchParams(window.location.search).get('renderer');
    if (r) localStorage.setItem('rr_renderer', r);
    else r = localStorage.getItem('rr_renderer');
  } catch (e) {}
  var config = { renderer: 'canvaskit' };
  if (r === 'skwasm') {
    config = { renderer: 'skwasm', forceSingleThreadedSkwasm: true };
  } else if (r === 'skwasm-mt') {
    config = { renderer: 'skwasm' };
  }
  _flutter.loader.load({
    config: config,
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}},
    },
  });
})();
