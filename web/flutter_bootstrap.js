{{flutter_js}}
{{flutter_build_config}}

// Force local CanvasKit so the app never relies on www.gstatic.com CDN.
// This prevents net::ERR_NAME_NOT_RESOLVED crashes when offline, on restricted
// networks, or when Google static domains are unreachable.
if (window._flutter && window._flutter.buildConfig) {
  window._flutter.buildConfig.useLocalCanvasKit = true;
}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/"
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  }
});
