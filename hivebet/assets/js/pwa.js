/* Registers the service worker and offers an "Install app" button. */
(function () {
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('sw.js').catch(function () {/* ignore on file:// */});
    });
  }

  // Custom install prompt (Android/desktop Chrome). iOS uses Share → Add to Home Screen.
  var deferred = null;
  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault();
    deferred = e;
    var btn = document.createElement('button');
    btn.id = 'installApp';
    btn.textContent = '📲 Install app';
    btn.style.cssText = 'position:fixed;left:16px;bottom:16px;z-index:60;padding:11px 18px;border:none;'
      + 'border-radius:999px;font-weight:800;cursor:pointer;color:#231400;'
      + 'background:linear-gradient(135deg,#ffc531,#ff8a00);box-shadow:0 0 26px rgba(255,176,0,.4)';
    btn.addEventListener('click', function () {
      btn.remove();
      deferred.prompt();
      deferred = null;
    });
    document.body.appendChild(btn);
  });
})();
