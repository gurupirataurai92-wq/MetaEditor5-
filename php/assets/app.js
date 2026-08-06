/* SIMS AI — client behaviour: quantity picker + camera barcode scanning.
   No external libraries; uses the browser's native BarcodeDetector when
   available, with a manual/USB-scanner fallback (the scan box is a plain input,
   so USB scanners that "type" the code work everywhere). */
(function () {
  'use strict';

  // --- Quantity picker modal (POS: tap a product) --------------------------
  var modal = document.getElementById('qty-modal');
  if (modal) {
    var qmName = document.getElementById('qm-name');
    var qmPrice = document.getElementById('qm-price');
    var qmPid = document.getElementById('qm-pid');
    var qmQty = document.getElementById('qm-qty');

    function openModal(card) {
      qmName.textContent = card.dataset.name;
      qmPrice.textContent = card.dataset.price + ' each · ' + card.dataset.stock + ' in stock';
      qmPid.value = card.dataset.id;
      qmQty.value = 1;
      modal.hidden = false;
      qmQty.focus();
      qmQty.select();
    }
    function closeModal() { modal.hidden = true; }

    document.querySelectorAll('.product-card').forEach(function (card) {
      card.addEventListener('click', function () { openModal(card); });
    });
    document.getElementById('qm-minus').addEventListener('click', function () {
      qmQty.value = Math.max(1, (parseInt(qmQty.value, 10) || 1) - 1);
    });
    document.getElementById('qm-plus').addEventListener('click', function () {
      qmQty.value = (parseInt(qmQty.value, 10) || 1) + 1;
    });
    document.getElementById('qm-cancel').addEventListener('click', closeModal);
    modal.addEventListener('click', function (e) { if (e.target === modal) closeModal(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeModal(); });
  }

  // --- Camera barcode scanning --------------------------------------------
  var camBtn = document.getElementById('cam-btn');
  if (camBtn) {
    var wrap = document.getElementById('cam-wrap');
    var video = document.getElementById('cam-video');
    var stopBtn = document.getElementById('cam-stop');
    var stream = null, detector = null, raf = null;

    // Where a detected code should go: POS scan box, or the new-product code field.
    var target = document.getElementById('scan-input') || document.getElementById('new-code');
    var scanForm = target && target.form;
    var autoSubmit = target && target.id === 'scan-input'; // POS: submit to add

    function stop() {
      if (raf) cancelAnimationFrame(raf);
      if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
      stream = null;
      wrap.hidden = true;
    }

    async function start() {
      if (!('BarcodeDetector' in window)) {
        alert('This browser has no camera barcode reader. Use a USB scanner or type the code — the box accepts both.');
        target && target.focus();
        return;
      }
      try {
        detector = new window.BarcodeDetector({
          formats: ['ean_13', 'ean_8', 'code_128', 'upc_a', 'upc_e', 'code_39', 'qr_code']
        });
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
        video.srcObject = stream;
        await video.play();
        wrap.hidden = false;
        scanLoop();
      } catch (err) {
        alert('Could not open the camera: ' + err.message);
      }
    }

    async function scanLoop() {
      if (!stream) return;
      try {
        var codes = await detector.detect(video);
        if (codes && codes.length) {
          var value = codes[0].rawValue;
          if (target) target.value = value;
          stop();
          if (autoSubmit && scanForm) scanForm.submit();
          else if (target) target.focus();
          return;
        }
      } catch (e) { /* keep trying */ }
      raf = requestAnimationFrame(scanLoop);
    }

    camBtn.addEventListener('click', start);
    if (stopBtn) stopBtn.addEventListener('click', stop);
  }

  // --- Register a tiny service worker so the app installs on PC/tablet -----
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(function () {});
  }
})();
