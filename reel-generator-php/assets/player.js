/**
 * In-browser reel player with SPOKEN AUDIO and per-character voices.
 *
 * Fetches the reel document (scenes + speakers + word timings) from api.php and
 * plays it in the 9:16 frame: it swaps the scene background, speaks each scene
 * with the Web Speech API (speechSynthesis), and highlights captions word by
 * word. Each character ("Name: line" in the script) is assigned a voice TONE
 * derived from who they are, so a king sounds deep, a child high, a robot flat.
 *
 * No API key and no server audio needed — synthesis runs in the browser. When
 * a real video provider has rendered an MP4, reel.php shows that instead.
 */
(function () {
  "use strict";

  var root = document.getElementById("player");
  if (!root) return; // provider-rendered <video> path: nothing to drive.

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
  var muteBtn = document.getElementById("muteBtn");
  var audioNote = document.getElementById("audioNote");
  var voicesEl = document.getElementById("voices");

  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

  var GRADIENTS = [
    ["#1b3a6b", "#071427"], ["#5a2b6b", "#16081f"], ["#0d5a4e", "#04160f"],
    ["#6b3b1b", "#1f1007"], ["#2b3b6b", "#080b1f"], ["#6b1b3a", "#1f0710"], ["#3a6b1b", "#101f07"]
  ];
  function hashStr(s) { var h = 0; for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0; return Math.abs(h); }
  function gradientFor(q) {
    var g = GRADIENTS[hashStr(q) % GRADIENTS.length];
    return "radial-gradient(120% 90% at 40% 30%, " + g[0] + ", " + g[1] + ")";
  }

  // ---- speech + per-character voices ----
  var hasSpeech = ("speechSynthesis" in window) && ("SpeechSynthesisUtterance" in window);
  var VOICES = [];
  function loadVoices() { try { VOICES = window.speechSynthesis.getVoices() || []; } catch (e) { VOICES = []; } }
  if (hasSpeech) { loadVoices(); window.speechSynthesis.onvoiceschanged = loadVoices; }
  var muted = false;

  var PALETTE = [
    { pitch: 1.0, rate: 1.0, kind: "neutral" }, { pitch: 0.82, rate: 0.98, kind: "steady" },
    { pitch: 1.32, rate: 1.05, kind: "bright" }, { pitch: 0.62, rate: 0.93, kind: "low" },
    { pitch: 1.55, rate: 1.08, kind: "lively" }
  ];
  function toneProfile(name, sample) {
    var s = (name + " " + (sample || "")).toLowerCase();
    if (/robot|android|machine|\bai\b|computer|cyborg|droid/.test(s)) return { pitch: 0.4, rate: 0.95, kind: "robotic", gender: null };
    if (/king|giant|monster|villain|ogre|boss|demon|beast|troll|dragon|grandpa|old man|father|\bdad\b|deep|captain/.test(s)) return { pitch: 0.55, rate: 0.9, kind: "deep", gender: "male" };
    if (/child|\bkid\b|little|baby|fairy|mouse|elf|pixie|\bboy\b|squeak/.test(s)) return { pitch: 1.75, rate: 1.1, kind: "high", gender: null };
    if (/queen|princess|woman|lady|\bshe\b|\bher\b|sister|witch|\bmom\b|mother|\bgirl\b/.test(s)) return { pitch: 1.28, rate: 1.0, kind: "warm", gender: "female" };
    if (/narrator|announcer|voice[- ]?over/.test(s)) return { pitch: 1.0, rate: 1.0, kind: "neutral", gender: null };
    return null;
  }
  function pickVoice(name, gender) {
    if (!VOICES.length) return null;
    var pool = VOICES.filter(function (v) { return /^en(\b|-|_)/i.test(v.lang); });
    if (!pool.length) pool = VOICES.slice();
    if (gender === "female") {
      var f = pool.filter(function (v) { return /female|samantha|victoria|karen|moira|tessa|zira|susan|fiona|serena|amelie|amelia/i.test(v.name); });
      if (f.length) pool = f;
    } else if (gender === "male") {
      var m = pool.filter(function (v) { return /\b(male|daniel|alex|fred|david|george|arthur|oliver|thomas)\b/i.test(v.name) && !/female/i.test(v.name); });
      if (m.length) pool = m;
    }
    return pool[hashStr(name) % pool.length] || null;
  }
  function buildVoiceMap(scenes) {
    var order = [], samples = {};
    scenes.forEach(function (sc) {
      var sp = sc.speaker || "Narrator";
      if (order.indexOf(sp) === -1) order.push(sp);
      samples[sp] = (samples[sp] || "") + " " + sc.text;
    });
    var map = {};
    order.forEach(function (sp) {
      var prof;
      if (sp.toLowerCase() === "narrator") prof = { pitch: 1.0, rate: 1.0, kind: "neutral", gender: null };
      else { prof = toneProfile(sp, samples[sp]); if (!prof) { var p = PALETTE[hashStr(sp) % PALETTE.length]; prof = { pitch: p.pitch, rate: p.rate, kind: p.kind, gender: null }; } }
      prof.voice = pickVoice(sp, prof.gender);
      map[sp] = prof;
    });
    return map;
  }

  // Precompute spoken text, tokens, and char offsets per scene (for caption sync).
  function prep(scene) {
    var tokens = (scene.text || "").split(/\s+/).filter(Boolean);
    var offsets = [], acc = 0;
    tokens.forEach(function (w) { offsets.push(acc); acc += w.length + 1; });
    scene.tokens = tokens;
    scene.spokenText = tokens.join(" ");
    scene.offsets = offsets;
    return scene;
  }

  // ---- player state ----
  var doc = null, scenes = [], voiceMap = {}, estDur = [], totalEst = 0;
  var sceneIdx = 0, playing = false, finished = false, sceneStart = 0, rafId = null, boundaryWord = -1;

  function renderCaption(scene, wordIdx) {
    captionEl.innerHTML = scene.tokens.map(function (w, j) {
      return '<span class="w' + (j === wordIdx ? " on" : "") + '">' + esc(w) + '</span>';
    }).join(" ");
  }
  function estimateScene(scene, prof) { return Math.max(1.3, scene.tokens.length * 0.36 / (prof ? prof.rate : 1)); }

  function speakScene(scene, prof) {
    if (!hasSpeech || muted) return;
    try {
      var u = new SpeechSynthesisUtterance(scene.spokenText);
      u.pitch = prof.pitch; u.rate = prof.rate; u.volume = 1;
      if (prof.voice) u.voice = prof.voice;
      u.onboundary = function (e) {
        if (e.name && e.name !== "word") return;
        var ci = e.charIndex || 0, idx = 0;
        for (var k = 0; k < scene.offsets.length; k++) { if (scene.offsets[k] <= ci) idx = k; else break; }
        boundaryWord = idx;
      };
      u.onend = function () { if (playing) advance(); };
      window.speechSynthesis.speak(u);
    } catch (e) {}
  }
  function startScene(idx) {
    sceneIdx = idx; boundaryWord = -1; sceneStart = performance.now();
    var scene = scenes[idx], prof = voiceMap[scene.speaker || "Narrator"];
    sceneBg.style.background = gradientFor(scene.visual ? scene.visual.query : scene.text);
    stageText.textContent = scene.speaker || "Narrator";
    renderCaption(scene, -1);
    if (hasSpeech && !muted) { try { window.speechSynthesis.cancel(); } catch (e) {} speakScene(scene, prof); }
    if (rafId) cancelAnimationFrame(rafId);
    rafId = requestAnimationFrame(frame);
  }
  function frame() {
    if (!playing) return;
    var scene = scenes[sceneIdx];
    var t = (performance.now() - sceneStart) / 1000;
    var est = estDur[sceneIdx] || 1;
    var frac = Math.min(1, t / est);
    var wordIdx = boundaryWord >= 0 ? boundaryWord : Math.min(scene.tokens.length - 1, Math.floor(frac * scene.tokens.length));
    renderCaption(scene, wordIdx);
    var before = 0; for (var k = 0; k < sceneIdx; k++) before += estDur[k];
    var cur = before + Math.min(est, t);
    curTime.textContent = Math.min(totalEst, cur).toFixed(1);
    progressBar.style.width = (Math.min(1, cur / Math.max(0.001, totalEst)) * 100).toFixed(1) + "%";
    var speaking = hasSpeech && !muted;
    if (!speaking && t >= est) { advance(); return; }
    if (speaking && t >= est + 2.5) { advance(); return; }
    rafId = requestAnimationFrame(frame);
  }
  function advance() {
    if (rafId) cancelAnimationFrame(rafId);
    if (sceneIdx + 1 < scenes.length) startScene(sceneIdx + 1);
    else finish();
  }
  function finish() {
    playing = false; finished = true;
    if (rafId) cancelAnimationFrame(rafId);
    if (hasSpeech) { try { window.speechSynthesis.cancel(); } catch (e) {} }
    progressBar.style.width = "100%";
    curTime.textContent = totalEst.toFixed(1);
    playBtn.textContent = "↻ Replay";
  }
  function play() {
    if (!scenes.length || playing) return;
    if (finished) { finished = false; sceneIdx = 0; }
    playing = true; playBtn.textContent = "❚❚ Pause";
    if (hasSpeech && !muted) { try { window.speechSynthesis.resume(); } catch (e) {} }
    startScene(sceneIdx);
  }
  function pause() {
    if (!playing) return;
    playing = false;
    if (rafId) cancelAnimationFrame(rafId);
    if (hasSpeech) { try { window.speechSynthesis.cancel(); } catch (e) {} }
    playBtn.textContent = "▶ Play";
  }

  function renderVoiceLegend() {
    if (!voicesEl) return;
    var order = [];
    scenes.forEach(function (sc) { var sp = sc.speaker || "Narrator"; if (order.indexOf(sp) === -1) order.push(sp); });
    voicesEl.innerHTML = order.map(function (sp) {
      var p = voiceMap[sp] || {};
      var vname = p.voice ? p.voice.name.replace(/\s*\(.*\)$/, "") : "default";
      return '<div class="voice-row"><span class="nm">' + esc(sp) + '</span>' +
        '<span class="spk">' + esc(vname) + '</span>' +
        '<span class="tone">' + esc(p.kind || "neutral") + '</span></div>';
    }).join("");
  }
  function updateAudioNote() {
    if (!audioNote) return;
    if (!hasSpeech) { audioNote.textContent = "This browser has no speech synthesis — captions play silently."; if (muteBtn) muteBtn.style.display = "none"; return; }
    audioNote.textContent = muted ? "🔇 Muted — captions only." : "🔊 Sound on — each character gets its own voice tone.";
    if (muteBtn) muteBtn.textContent = muted ? "🔇" : "🔊";
  }

  playBtn.addEventListener("click", function () { if (playing) pause(); else play(); });
  if (muteBtn) muteBtn.addEventListener("click", function () {
    muted = !muted;
    if (muted && hasSpeech) { try { window.speechSynthesis.cancel(); } catch (e) {} }
    updateAudioNote();
  });

  // ---- load ----
  function load() {
    stageText.textContent = "loading";
    fetch(api + "?id=" + encodeURIComponent(reelId))
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data.error) { stageText.textContent = "error"; return; }
        doc = data;
        scenes = (data.scenes || []).map(prep);
        voiceMap = buildVoiceMap(scenes);
        estDur = scenes.map(function (sc) { return estimateScene(sc, voiceMap[sc.speaker || "Narrator"]); });
        totalEst = estDur.reduce(function (a, b) { return a + b; }, 0);
        ratioText.textContent = data.reel.aspect + " · " + data.reel.fps + "fps";
        if (totTime) totTime.textContent = totalEst.toFixed(1);
        if (captionEl && data.reel.captionStyle) captionEl.className = "caption style-" + data.reel.captionStyle;
        renderVoiceLegend();
        updateAudioNote();
        if (scenes.length) { startAt0(); }
        stageText.textContent = scenes.length ? (scenes[0].speaker || "Narrator") : (data.reel.status || "ready");
        if (window.__REEL_AUTOPLAY && data.reel.status === "done") play();
      })
      .catch(function () { stageText.textContent = "offline"; });
  }
  function startAt0() {
    sceneBg.style.background = gradientFor(scenes[0].visual ? scenes[0].visual.query : scenes[0].text);
    renderCaption(scenes[0], -1);
    progressBar.style.width = "0%";
    if (curTime) curTime.textContent = "0.0";
  }

  load();
})();
