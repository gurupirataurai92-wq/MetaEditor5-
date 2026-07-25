/* HiveBet — live Aviator client.
   The server owns the crash point; this file animates and polls for the
   authoritative state, then lets the player cash out in real time. */
(function () {
  var box = document.getElementById('aviator');
  var playBtn = document.getElementById('av-play');
  if (!box || !playBtn) return; // logged-out view has no controls

  var multEl   = document.getElementById('av-mult');
  var planeEl  = document.getElementById('av-plane');
  var statusEl = document.getElementById('av-status');
  var fairEl   = document.getElementById('av-fair');
  var msgEl    = document.getElementById('av-msg');
  var balEl    = document.getElementById('av-balance');
  var cashBtn  = document.getElementById('av-cashout');
  var cashMult = document.getElementById('av-cashout-mult');
  var stakeEl  = document.getElementById('stake');

  var rate = 0.20, startTs = 0, raf = null, poll = null, running = false;

  function post(url, data) {
    var body = new URLSearchParams(data);
    body.append('csrf', window.HIVE_CSRF);
    return fetch(url, { method: 'POST', body: body, headers: { 'X-Requested-With': 'fetch' } })
      .then(function (r) { return r.json(); });
  }

  function reset(text) {
    running = false;
    cancelAnimationFrame(raf); clearInterval(poll);
    cashBtn.style.display = 'none';
    playBtn.style.display = '';
    playBtn.disabled = false;
    statusEl.textContent = text || 'Ready for take-off';
  }

  function render(mult, busted) {
    multEl.textContent = mult.toFixed(2) + '×';
    cashMult.textContent = mult.toFixed(2) + '×';
    // map multiplier onto the little runway (log scale so it eases upward)
    var p = Math.min(Math.log(mult) / Math.log(20), 1);
    planeEl.style.left   = (8 + p * 74) + '%';
    planeEl.style.bottom = (12 + p * 60) + '%';
    if (busted) { multEl.classList.add('busted'); planeEl.textContent = '💥'; }
    else { multEl.classList.remove('busted'); planeEl.textContent = '✈️'; }
  }

  function loop() {
    if (!running) return;
    var elapsed = (performance.now() - startTs) / 1000;
    render(Math.exp(rate * elapsed), false);
    raf = requestAnimationFrame(loop);
  }

  function startPolling() {
    poll = setInterval(function () {
      fetch('api/aviator_status.php').then(function (r) { return r.json(); }).then(function (s) {
        if (!running) return;
        if (s.state === 'crashed') {
          running = false;
          cancelAnimationFrame(raf); clearInterval(poll);
          render(s.point, true);
          statusEl.textContent = 'Flew away at ' + s.point.toFixed(2) + '×';
          msgEl.innerHTML = '<span class="neg">💥 Busted — lost the stake.</span>';
          fairEl.textContent = 'Seed: ' + s.seed;
          cashBtn.style.display = 'none';
          setTimeout(function () { reset(); multEl.classList.remove('busted'); render(1, false); }, 2200);
        }
      });
    }, 250);
  }

  playBtn.addEventListener('click', function () {
    var stake = parseFloat(stakeEl.value);
    if (!(stake >= 1)) { msgEl.innerHTML = '<span class="neg">Enter a stake of at least 1.</span>'; return; }
    playBtn.disabled = true;
    msgEl.textContent = 'Placing bet…';
    post('api/aviator_start.php', { stake: stake }).then(function (res) {
      if (!res.ok) { msgEl.innerHTML = '<span class="neg">' + res.error + '</span>'; playBtn.disabled = false; return; }
      rate = res.rate || 0.20;
      startTs = performance.now();
      running = true;
      if (balEl) balEl.textContent = 'HC ' + res.newBalance.toFixed(2);
      fairEl.textContent = 'Commitment (SHA-256 of seed): ' + res.commit;
      msgEl.textContent = '';
      multEl.classList.remove('busted');
      statusEl.textContent = 'Flying…';
      playBtn.style.display = 'none';
      cashBtn.style.display = '';
      loop();
      startPolling();
    }).catch(function () { msgEl.innerHTML = '<span class="neg">Network error.</span>'; playBtn.disabled = false; });
  });

  cashBtn.addEventListener('click', function () {
    if (!running) return;
    cashBtn.disabled = true;
    post('api/aviator_cashout.php', {}).then(function (res) {
      cashBtn.disabled = false;
      running = false;
      cancelAnimationFrame(raf); clearInterval(poll);
      if (res.ok) {
        render(res.multiplier, false);
        statusEl.textContent = 'Cashed out at ' + res.multiplier.toFixed(2) + '×';
        msgEl.innerHTML = '<span class="pos">💰 Won HC ' + res.payout.toFixed(2) + '!</span>';
        if (balEl) balEl.textContent = 'HC ' + res.newBalance.toFixed(2);
        fairEl.textContent = 'Seed: ' + res.seed + ' (crash was ' + res.point.toFixed(2) + '×)';
        setTimeout(function () { reset(); render(1, false); }, 2200);
      } else if (res.crashed) {
        render(res.point, true);
        statusEl.textContent = 'Flew away at ' + res.point.toFixed(2) + '×';
        msgEl.innerHTML = '<span class="neg">💥 Too late — busted at ' + res.point.toFixed(2) + '×.</span>';
        fairEl.textContent = 'Seed: ' + res.seed;
        setTimeout(function () { reset(); multEl.classList.remove('busted'); render(1, false); }, 2200);
      } else {
        msgEl.innerHTML = '<span class="neg">' + (res.error || 'Error') + '</span>';
        reset();
      }
    }).catch(function () { cashBtn.disabled = false; });
  });
})();
