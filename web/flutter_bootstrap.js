{{flutter_js}}
{{flutter_build_config}}

// No service worker. Flutter's default one caches the app in the browser and
// can keep serving an old build after a deploy; this app needs the network
// anyway, and the backend already versions its files (/app/v/<stamp>/).
// Browsers that registered one under an earlier build drop it here.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.getRegistrations().then((registrations) => {
    for (const r of registrations) r.unregister();
  });
  if (window.caches) {
    caches.keys().then((keys) => keys.forEach((k) => caches.delete(k)));
  }
}

_flutter.loader.load();
