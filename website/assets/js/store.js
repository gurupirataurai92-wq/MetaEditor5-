/* ==========================================================================
   Lymond Services — local catalogue store
   --------------------------------------------------------------------------
   Holds the stock list and the photos the manager uploads, inside the
   browser, until they are published as real files.

   Two layers, so the public pages stay simple:
     • assets/js/data.js   — the published catalogue. Everyone sees this.
     • this store          — unpublished edits, visible only in the browser
                             that made them.

   Photos are keyed by their eventual filename (e.g. "uploads/v-001-1.jpg").
   Before publishing, the page finds the photo here; afterwards the real file
   sits at assets/img/uploads/... and the store entry is no longer needed.

   Uses IndexedDB where it is available (room for hundreds of photos) and
   falls back to localStorage (roughly 5 MB, so perhaps 30–40 photos).
   Browsers block IndexedDB when a page is opened straight from the file
   system, which is why the fallback exists — serve the folder over http to
   get the larger store.
   ========================================================================== */

window.LymondStore = (function () {
  'use strict';

  var DB_NAME = 'lymond-services';
  var DB_VERSION = 1;
  var STORE = 'kv';
  var LS_PREFIX = 'lymond.kv.';
  var CATALOGUE_KEY = 'catalogue';
  var PHOTO_PREFIX = 'photo:';

  var db = null;
  var backend = 'memory';
  var memory = {};

  /* ------------------------------------------------------------ open db -- */

  function openDb() {
    return new Promise(function (resolve) {
      var req;
      try {
        if (!window.indexedDB) { return resolve(null); }
        req = window.indexedDB.open(DB_NAME, DB_VERSION);
      } catch (e) {
        return resolve(null);           // blocked (file:// origin, private mode)
      }
      req.onupgradeneeded = function () {
        var d = req.result;
        if (!d.objectStoreNames.contains(STORE)) { d.createObjectStore(STORE); }
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { resolve(null); };
      req.onblocked = function () { resolve(null); };
      /* Some browsers neither resolve nor reject on a blocked file:// open. */
      setTimeout(function () { resolve(req.result || null); }, 2000);
    });
  }

  function localStorageWorks() {
    try {
      window.localStorage.setItem('lymond.probe', '1');
      window.localStorage.removeItem('lymond.probe');
      return true;
    } catch (e) {
      return false;
    }
  }

  var ready = openDb().then(function (handle) {
    if (handle) {
      db = handle;
      backend = 'indexeddb';
    } else if (localStorageWorks()) {
      backend = 'localstorage';
    } else {
      backend = 'memory';             // nothing persists; still usable in-session
    }
    return backend;
  });

  /* ----------------------------------------------------------- kv basics -- */

  function idbRun(mode, fn) {
    return new Promise(function (resolve, reject) {
      var tx = db.transaction(STORE, mode);
      var req = fn(tx.objectStore(STORE));
      tx.onabort = function () { reject(tx.error || new Error('transaction aborted')); };
      if (req) {
        req.onsuccess = function () { resolve(req.result); };
        req.onerror = function () { reject(req.error); };
      } else {
        tx.oncomplete = function () { resolve(); };
      }
    });
  }

  function get(key) {
    return ready.then(function () {
      if (backend === 'indexeddb') { return idbRun('readonly', function (s) { return s.get(key); }); }
      if (backend === 'localstorage') {
        var raw = window.localStorage.getItem(LS_PREFIX + key);
        return raw === null ? undefined : JSON.parse(raw);
      }
      return memory[key];
    });
  }

  function set(key, value) {
    return ready.then(function () {
      if (backend === 'indexeddb') { return idbRun('readwrite', function (s) { return s.put(value, key); }); }
      if (backend === 'localstorage') {
        try {
          window.localStorage.setItem(LS_PREFIX + key, JSON.stringify(value));
        } catch (e) {
          throw new Error('The browser ran out of storage room. Publish what you have, ' +
                          'or remove some photos, then try again.');
        }
        return;
      }
      memory[key] = value;
    });
  }

  function del(key) {
    return ready.then(function () {
      if (backend === 'indexeddb') { return idbRun('readwrite', function (s) { return s.delete(key); }); }
      if (backend === 'localstorage') { return window.localStorage.removeItem(LS_PREFIX + key); }
      delete memory[key];
    });
  }

  function keys() {
    return ready.then(function () {
      if (backend === 'indexeddb') { return idbRun('readonly', function (s) { return s.getAllKeys(); }); }
      if (backend === 'localstorage') {
        return Object.keys(window.localStorage)
          .filter(function (k) { return k.indexOf(LS_PREFIX) === 0; })
          .map(function (k) { return k.slice(LS_PREFIX.length); });
      }
      return Object.keys(memory);
    });
  }

  /* -------------------------------------------------------------- public -- */

  return {
    ready: ready,

    backend: function () { return backend; },

    /** Unpublished catalogue edits, or null when there are none. */
    getCatalogue: function () {
      return get(CATALOGUE_KEY).then(function (v) { return v || null; });
    },

    saveCatalogue: function (catalogue) {
      return set(CATALOGUE_KEY, catalogue);
    },

    clearCatalogue: function () {
      return del(CATALOGUE_KEY);
    },

    putPhoto: function (filename, dataUrl) {
      return set(PHOTO_PREFIX + filename, dataUrl);
    },

    deletePhoto: function (filename) {
      return del(PHOTO_PREFIX + filename);
    },

    /** All staged photos as { filename: dataUrl }. */
    allPhotos: function () {
      return keys().then(function (all) {
        var names = all.filter(function (k) { return String(k).indexOf(PHOTO_PREFIX) === 0; });
        return Promise.all(names.map(function (k) { return get(k); })).then(function (values) {
          var out = {};
          names.forEach(function (k, i) {
            if (values[i]) { out[String(k).slice(PHOTO_PREFIX.length)] = values[i]; }
          });
          return out;
        });
      });
    },

    /** Remove staged photos that no item refers to any more. */
    prunePhotos: function (usedFilenames) {
      var used = {};
      usedFilenames.forEach(function (f) { used[f] = true; });
      return keys().then(function (all) {
        var orphans = all
          .filter(function (k) { return String(k).indexOf(PHOTO_PREFIX) === 0; })
          .map(function (k) { return String(k).slice(PHOTO_PREFIX.length); })
          .filter(function (f) { return !used[f]; });
        return Promise.all(orphans.map(function (f) { return del(PHOTO_PREFIX + f); }))
          .then(function () { return orphans.length; });
      });
    },

    /** Rough usage figure for the storage meter. */
    usage: function () {
      if (navigator.storage && navigator.storage.estimate) {
        return navigator.storage.estimate().then(function (est) {
          return { bytes: est.usage || 0, quota: est.quota || 0, estimated: true };
        }).catch(function () { return { bytes: 0, quota: 0, estimated: false }; });
      }
      return ready.then(function () {
        var bytes = 0;
        if (backend === 'localstorage') {
          Object.keys(window.localStorage).forEach(function (k) {
            if (k.indexOf(LS_PREFIX) === 0) { bytes += (window.localStorage.getItem(k) || '').length * 2; }
          });
          return { bytes: bytes, quota: 5 * 1024 * 1024, estimated: false };
        }
        return { bytes: 0, quota: 0, estimated: false };
      });
    }
  };
}());
