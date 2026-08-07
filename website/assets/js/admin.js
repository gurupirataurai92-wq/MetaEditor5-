/* Operator area: file-picker wiring and a preview of what is about to upload. */
(function () {
  'use strict';
  var drop = document.getElementById('v-drop');
  var input = document.getElementById('v-files');
  var preview = document.getElementById('v-preview');
  if (!drop || !input) { return; }

  function open() { input.click(); }
  drop.addEventListener('click', open);
  drop.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); }
  });

  ['dragenter', 'dragover'].forEach(function (evt) {
    drop.addEventListener(evt, function (e) { e.preventDefault(); drop.classList.add('over'); });
  });
  ['dragleave', 'drop'].forEach(function (evt) {
    drop.addEventListener(evt, function (e) { e.preventDefault(); drop.classList.remove('over'); });
  });
  drop.addEventListener('drop', function (e) {
    if (e.dataTransfer && e.dataTransfer.files.length) {
      input.files = e.dataTransfer.files;
      render();
    }
  });

  input.addEventListener('change', render);

  function render() {
    if (!preview) { return; }
    preview.innerHTML = '';
    Array.prototype.forEach.call(input.files, function (file) {
      if (!/^image\//.test(file.type)) { return; }
      var card = document.createElement('div');
      card.className = 'thumb-card';
      var img = document.createElement('img');
      img.src = URL.createObjectURL(file);
      img.onload = function () { URL.revokeObjectURL(img.src); };
      var cap = document.createElement('div');
      cap.className = 'thumb-tools';
      cap.textContent = 'Uploads when you save';
      card.appendChild(img);
      card.appendChild(cap);
      preview.appendChild(card);
    });
  }
}());
