/* Sign-in / registration page. */
/* global window, document */

(function () {
  'use strict';

  const H = window.Haulr;
  const { $, $$ } = H;

  let mode = 'login'; // 'login' | 'register'

  document.addEventListener('DOMContentLoaded', async () => {
    // Already signed in? Go where they belong.
    if (H.Session.token && H.Session.user) {
      window.location.replace(nextUrl() || H.Session.homePath());
      return;
    }

    const params = new URLSearchParams(window.location.search);
    if (params.get('mode') === 'register') mode = 'register';

    await H.loadMeta();
    renderVehicleChoices();

    const wantedRole = params.get('role');
    if (wantedRole === 'operator' || wantedRole === 'customer') {
      const radio = $(`input[name="role"][value="${wantedRole}"]`);
      if (radio) radio.checked = true;
    }

    applyMode();

    $('#switchMode').addEventListener('click', (e) => {
      e.preventDefault();
      mode = mode === 'login' ? 'register' : 'login';
      hideAlert();
      applyMode();
    });

    for (const radio of $$('input[name="role"]')) {
      radio.addEventListener('change', applyMode);
    }

    $('#authForm').addEventListener('submit', onSubmit);

    for (const button of $$('[data-demo]')) {
      button.addEventListener('click', () => {
        mode = 'login';
        applyMode();
        $('#email').value = button.dataset.demo;
        $('#password').value = 'haulr1234';
        $('#authForm').requestSubmit();
      });
    }
  });

  function nextUrl() {
    const next = new URLSearchParams(window.location.search).get('next');
    // Only ever follow same-site paths — never an absolute URL from the query.
    return next && next.startsWith('/') && !next.startsWith('//') ? next : null;
  }

  const selectedRole = () => $('input[name="role"]:checked')?.value || 'customer';

  function applyMode() {
    const registering = mode === 'register';
    const isOperator = registering && selectedRole() === 'operator';

    $('#formTitle').textContent = registering
      ? isOperator
        ? 'Register your vehicle'
        : 'Create your account'
      : 'Welcome back';

    $('#formSubtitle').textContent = registering
      ? isOperator
        ? 'Tell us what you drive and start bidding on jobs near you.'
        : 'Post a delivery in about a minute.'
      : 'Sign in to post a delivery or pick up a job.';

    $('#roleField').classList.toggle('hidden', !registering);
    $('#nameField').classList.toggle('hidden', !registering);
    $('#phoneField').classList.toggle('hidden', !registering);
    $('#passwordHint').classList.toggle('hidden', !registering);
    $('#vehicleFields').classList.toggle('hidden', !isOperator);

    $('#password').setAttribute(
      'autocomplete',
      registering ? 'new-password' : 'current-password'
    );

    $('#submitBtn').textContent = registering ? 'Create account' : 'Sign in';
    $('#switchPrompt').textContent = registering
      ? 'Already have an account?'
      : 'New to Haulr?';
    $('#switchMode').textContent = registering ? 'Sign in' : 'Create an account';

    document.title = registering ? 'Create an account · Haulr' : 'Sign in · Haulr';
  }

  function renderVehicleChoices() {
    const host = $('#vehicleChoices');
    const meta = H.getMeta();

    host.innerHTML = meta.vehicleClasses
      .map(
        (v, index) => `
        <label class="choice">
          <input type="radio" name="vehicleClass" value="${v.id}" ${index === 3 ? 'checked' : ''} />
          <div class="choice-icon">${v.icon}</div>
          <div class="choice-name">${H.esc(v.name)}</div>
          <div class="choice-note">${H.esc(v.blurb)}<br>up to ${v.capacityKg.toLocaleString()} kg</div>
        </label>`
      )
      .join('');
  }

  function showAlert(message) {
    const box = $('#alert');
    box.textContent = message;
    box.classList.remove('hidden');
    box.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  function hideAlert() {
    $('#alert').classList.add('hidden');
  }

  async function onSubmit(event) {
    event.preventDefault();
    hideAlert();

    const email = $('#email').value.trim();
    const password = $('#password').value;

    if (!email || !password) return showAlert('Enter your email and password.');

    const payload =
      mode === 'login'
        ? { email, password }
        : buildRegistration(email, password);

    if (!payload) return; // buildRegistration already reported the problem

    await H.withBusy($('#submitBtn'), async () => {
      try {
        const path = mode === 'login' ? '/api/auth/login' : '/api/auth/register';
        const result = await H.api.post(path, payload);
        H.Session.save(result.token, result.user);
        window.location.href = nextUrl() || H.Session.homePath();
      } catch (err) {
        showAlert(err.message);
      }
    });
  }

  function buildRegistration(email, password) {
    const role = selectedRole();
    const fullName = $('#fullName').value.trim();
    const phone = $('#phone').value.trim();

    if (!fullName) {
      showAlert('Enter your full name.');
      return null;
    }
    if (!phone) {
      showAlert('Enter a mobile number — operators and customers need to reach each other.');
      return null;
    }

    const payload = { role, fullName, email, phone, password };
    if (role !== 'operator') return payload;

    const vehicleClass = $('input[name="vehicleClass"]:checked')?.value;
    const vehiclePlate = $('#vehiclePlate').value.trim();

    if (!vehicleClass) {
      showAlert('Choose the type of vehicle you drive.');
      return null;
    }
    if (!vehiclePlate) {
      showAlert('Enter your number plate.');
      return null;
    }

    return {
      ...payload,
      vehicleClass,
      vehiclePlate,
      vehicleMake: $('#vehicleMake').value.trim() || undefined,
      vehicleModel: $('#vehicleModel').value.trim() || undefined,
      licenceNumber: $('#licenceNumber').value.trim() || undefined,
      helpersAvailable: Number($('#helpersAvailable').value || 0),
      bio: $('#bio').value.trim() || undefined,
    };
  }
})();
