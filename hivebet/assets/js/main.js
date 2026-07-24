/* HiveBet — small front-end helpers */
(function () {
  // Confirm before placing/settling where data-confirm is set
  document.querySelectorAll('form[data-confirm]').forEach(function (f) {
    f.addEventListener('submit', function (e) {
      if (!window.confirm(f.getAttribute('data-confirm'))) e.preventDefault();
    });
  });

  // Auto-fill stake into a target field when clicking quick-stake chips
  document.querySelectorAll('[data-stake]').forEach(function (chip) {
    chip.addEventListener('click', function () {
      var target = document.querySelector(chip.getAttribute('data-target') || '#stake');
      if (target) target.value = chip.getAttribute('data-stake');
    });
  });
})();
