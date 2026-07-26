/**
 * In-browser reel player. Fetches the reel document (scenes + word timings)
 * from api.php and plays it back in the 9:16 phone frame: it swaps the scene
 * background, drives the karaoke captions off the real word timings, and
 * advances the progress bar. This is the "watchable output" without ffmpeg.
 */
(function () {
  "use strict";

  var root = document.getElementById("player");
  if (!root) return;

  var api = root.getAttribute("data-api");
  var reelId = root.getAttribute("data-reel-id");

  var sceneBg = document.getElementById("sceneBg");
  var captionEl = document.getElementById("caption");
  var stageText = document.getElementById("stageText");
  var ratioText = document.getElementById("ratioText");
  var progressBar = document.getElementById("progressBar");
  var playBtn = document.getElementById("playBtn");
  var curTime = document.getElementById("curTime");
  var totTime = document.getElementById("totTime");

  // Deterministic gradient per visual query, so a scene always looks the same.
  var GRADIENTS = [
    ["#1b3a6b", "#071427"],
    ["#5a2b6b", "#16081f"],
    ["#0d5a4e", "#04160f"],
    ["#6b3b1b", "#1f1007"],
    ["#2b3b6b", "#080b1f"],
    ["#6b1b3a", "#1f0710"],
    ["#3a6b1b", "#101f07"],
  ];
  function gradientFor(query) {
    var hash = 0;
    for (var i = 0; i < query.length; i++) {
      hash = (hash * 31 + query.charCodeAt(i)) | 0;
    }
    var g = GRADIENTS[Math.abs(hash) % GRADIENTS.length];
    return "radial-gradient(120% 90% at 40% 30%, " + g[0] + ", " + g[1] + ")";
  }

  var doc = null;
  var duration = 0;
  var playing = false;
  var startWall = 0;
  var elapsedAtPause = 0;
  var rafId = null;

  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function load() {
    stageText.textContent = "loading";
    fetch(api + "?id=" + encodeURIComponent(reelId))
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data.error) { stageText.textContent = "error"; return; }
        doc = data;
        duration = data.reel.durationSec || 0;
        ratioText.textContent = data.reel.aspect + " · " + data.reel.fps + "fps";
        if (totTime) totTime.textContent = duration.toFixed(1);
        if (captionEl && data.reel.captionStyle) {
          captionEl.className = "caption style-" + data.reel.captionStyle;
        }
        renderAt(0);
        stageText.textContent = data.reel.status === "done" ? "ready" : data.reel.status;
        if (window.__REEL_AUTOPLAY && data.reel.status === "done") play();
      })
      .catch(function () { stageText.textContent = "offline"; });
  }

  function activeScene(t) {
    if (!doc) return null;
    for (var i = 0; i < doc.scenes.length; i++) {
      var s = doc.scenes[i];
      if (t >= s.startSec && t < s.endSec) return s;
    }
    return doc.scenes.length ? doc.scenes[doc.scenes.length - 1] : null;
  }

  function renderAt(t) {
    var scene = activeScene(t);
    if (!scene) return;

    sceneBg.style.background = gradientFor(scene.visual.query);
    stageText.textContent = "scene " + (scene.index + 1) + "/" + doc.scenes.length;

    // Words belonging to this scene, highlighting the one active at time t.
    var words = doc.words.filter(function (w) { return w.sceneId === scene.id; });
    if (words.length === 0) {
      captionEl.textContent = scene.text;
    } else {
      captionEl.innerHTML = words
        .map(function (w) {
          var on = t >= w.startSec && t < w.endSec;
          return '<span class="w' + (on ? " on" : "") + '">' + esc(w.word) + "</span>";
        })
        .join(" ");
    }

    var pct = duration > 0 ? Math.min(1, t / duration) : 0;
    progressBar.style.width = (pct * 100).toFixed(1) + "%";
    if (curTime) curTime.textContent = t.toFixed(1);
  }

  function tick() {
    if (!playing) return;
    var t = elapsedAtPause + (performance.now() - startWall) / 1000;
    if (t >= duration) {
      renderAt(duration);
      stop(true);
      return;
    }
    renderAt(t);
    rafId = requestAnimationFrame(tick);
  }

  function play() {
    if (!doc || duration <= 0 || playing) return;
    if (elapsedAtPause >= duration) elapsedAtPause = 0; // replay from start
    playing = true;
    startWall = performance.now();
    playBtn.textContent = "❚❚ Pause";
    rafId = requestAnimationFrame(tick);
  }

  function pause() {
    if (!playing) return;
    elapsedAtPause += (performance.now() - startWall) / 1000;
    playing = false;
    if (rafId) cancelAnimationFrame(rafId);
    playBtn.textContent = "▶ Play";
  }

  function stop(finished) {
    playing = false;
    if (rafId) cancelAnimationFrame(rafId);
    playBtn.textContent = finished ? "↻ Replay" : "▶ Play";
    if (finished) elapsedAtPause = duration;
  }

  playBtn.addEventListener("click", function () {
    if (playing) pause();
    else play();
  });

  load();
})();
