<?php
/** Contact form. Valid enquiries are stored in the database for operators. */
require __DIR__ . '/includes/bootstrap.php';

$name = setting('company_name');
$errors = [];
$done = false;

$topics = ['Vehicle import', 'Spare parts', 'Auction sourcing', 'Clearing & registration',
           'Trade account', 'Something else'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();

    /* Hidden field no human fills in — a cheap filter for automated junk. */
    if (trim((string)($_POST['website'] ?? '')) !== '') {
        $done = true;                                  // pretend it worked
    } else {
        $in = [
            'name'    => trim((string)($_POST['name'] ?? '')),
            'email'   => trim((string)($_POST['email'] ?? '')),
            'phone'   => trim((string)($_POST['phone'] ?? '')),
            'topic'   => (string)($_POST['topic'] ?? ''),
            'message' => trim((string)($_POST['message'] ?? '')),
            'ref'     => trim((string)($_POST['ref'] ?? '')),
        ];

        if (mb_strlen($in['name']) < 2)   { $errors['name'] = 'Please tell us your name.'; }
        if (mb_strlen($in['name']) > 120) { $errors['name'] = 'That name is too long.'; }
        if (!filter_var($in['email'], FILTER_VALIDATE_EMAIL)) {
            $errors['email'] = 'Enter a valid email address.';
        }
        if ($in['phone'] !== '' && !preg_match('/^[+0-9 ()\-]{7,40}$/', $in['phone'])) {
            $errors['phone'] = 'Enter a valid phone number.';
        }
        if (!in_array($in['topic'], $topics, true)) { $in['topic'] = 'Something else'; }
        if (mb_strlen($in['message']) < 10) {
            $errors['message'] = 'Please give us a little more detail (10 characters or more).';
        }
        if (mb_strlen($in['message']) > 4000) {
            $errors['message'] = 'That message is too long — 4000 characters is the limit.';
        }

        /* One address cannot flood the inbox. */
        $recent = (int)q_val(
            'SELECT COUNT(*) FROM enquiries WHERE ip = ? AND created_at > (NOW() - INTERVAL 10 MINUTE)',
            [client_ip()]
        );
        if ($recent >= 5) {
            $errors['message'] = 'That is several enquiries in a row. Please call us instead — '
                               . setting('phone') . '.';
        }

        if (!$errors) {
            q('INSERT INTO enquiries (name, email, phone, topic, message, ref, ip)
               VALUES (?, ?, ?, ?, ?, ?, ?)',
              [$in['name'], $in['email'], $in['phone'] ?: null, $in['topic'], $in['message'],
               $in['ref'] ?: null, client_ip()]);
            $done = true;
        }
    }
}

$ref = trim((string)($_GET['ref'] ?? ''));
$prefill = '';
if ($ref !== '') {
    $prefill = 'I would like more information about ' . $ref . '.';
}

$page_title = 'Contact & request a quote — ' . $name;
$page_desc  = 'Request a vehicle import quote or a spare part price. Call, WhatsApp or send us your '
            . 'chassis number and we will reply within two working days.';
$nav = 'contact';
require __DIR__ . '/includes/header.php';
?>

  <section class="page-hero">
    <div class="wrap">
      <p class="crumbs"><a href="<?= e(url('index.php')) ?>">Home</a> / Contact</p>
      <h1>Request a quote</h1>
      <p>Importing a vehicle, chasing a part, or opening a trade account — tell us what you need and
         we will come back with a written answer, normally within two working days.</p>
    </div>
  </section>

  <section class="section">
    <div class="wrap">
      <div class="grid grid--2 grid--top">

        <div class="panel">
          <?php if ($done): ?>
            <h2>Thank you — we have your enquiry</h2>
            <div class="form-status show ok" style="margin-top:0">
              It is now with our sales desk. You will get a reply within two working days, normally
              sooner. If it is urgent, call <?= e(setting('phone')) ?>.
            </div>
            <div class="btn-row" style="margin-top:18px">
              <a class="btn btn--primary" href="<?= e(url('vehicles.php')) ?>">Browse vehicles</a>
              <a class="btn btn--ghost" href="<?= e(url('parts.php')) ?>">Browse parts</a>
            </div>
          <?php else: ?>
            <h2>Send us the details</h2>
            <p class="card-sub">Fields marked * are required. For a part, include the chassis number
               if you have it — it is the fastest route to the right item.</p>

            <?php if ($errors): ?>
              <div class="form-status show bad" style="margin-top:14px">
                Please correct the highlighted fields and send again.
              </div>
            <?php endif; ?>

            <form method="post" action="<?= e(url('contact.php')) ?>" novalidate style="margin-top:18px">
              <?= csrf_field() ?>
              <input type="hidden" name="ref" value="<?= e(old('ref', $ref)) ?>">
              <div style="position:absolute;left:-9999px" aria-hidden="true">
                <label>Leave this empty <input type="text" name="website" tabindex="-1" autocomplete="off"></label>
              </div>

              <div class="field-row">
                <div class="field">
                  <label for="c-name">Your name *</label>
                  <input type="text" id="c-name" name="name" autocomplete="name"
                         value="<?= e(old('name')) ?>" <?= isset($errors['name']) ? 'aria-invalid="true"' : '' ?>>
                  <span class="err"><?= e($errors['name'] ?? '') ?></span>
                </div>
                <div class="field">
                  <label for="c-email">Email *</label>
                  <input type="email" id="c-email" name="email" autocomplete="email"
                         value="<?= e(old('email')) ?>" <?= isset($errors['email']) ? 'aria-invalid="true"' : '' ?>>
                  <span class="err"><?= e($errors['email'] ?? '') ?></span>
                </div>
                <div class="field">
                  <label for="c-phone">Phone / WhatsApp</label>
                  <input type="tel" id="c-phone" name="phone" autocomplete="tel" placeholder="+255 …"
                         value="<?= e(old('phone')) ?>" <?= isset($errors['phone']) ? 'aria-invalid="true"' : '' ?>>
                  <span class="err"><?= e($errors['phone'] ?? '') ?></span>
                </div>
                <div class="field">
                  <label for="c-topic">What is this about?</label>
                  <select id="c-topic" name="topic">
                    <?php foreach ($topics as $t): ?>
                      <option<?= old('topic') === $t ? ' selected' : '' ?>><?= e($t) ?></option>
                    <?php endforeach; ?>
                  </select>
                  <span class="err"></span>
                </div>
              </div>

              <div class="field" style="margin-top:14px">
                <label for="c-message">Your message *</label>
                <textarea id="c-message" name="message" <?= isset($errors['message']) ? 'aria-invalid="true"' : '' ?>
                  placeholder="e.g. Looking for a 2017–2019 Toyota Hilux double cab, automatic, under 80,000 km, budget $27,000 landed in Dar es Salaam."><?= e(old('message', $prefill)) ?></textarea>
                <span class="err"><?= e($errors['message'] ?? '') ?></span>
              </div>

              <div class="btn-row" style="margin-top:16px">
                <button class="btn btn--primary" type="submit">Send enquiry</button>
                <a class="btn btn--ghost" target="_blank" rel="noopener"
                   href="<?= e(wa_link('Hello ' . $name . ', I would like a quote.')) ?>">Or message on WhatsApp</a>
              </div>
            </form>
          <?php endif; ?>
        </div>

        <div>
          <div class="panel panel--dark">
            <h2>Reach us directly</h2>
            <ul class="contact-list" style="margin-top:18px">
              <li><span class="ico" aria-hidden="true">📞</span>
                <div><b>Sales &amp; imports</b>
                  <a href="tel:<?= e(preg_replace('/\s+/', '', setting('phone'))) ?>"><?= e(setting('phone')) ?></a></div></li>
              <li><span class="ico" aria-hidden="true">✉</span>
                <div><b>Vehicle enquiries</b>
                  <a href="mailto:<?= e(setting('email')) ?>"><?= e(setting('email')) ?></a></div></li>
              <li><span class="ico" aria-hidden="true">🔧</span>
                <div><b>Parts counter</b>
                  <a href="mailto:<?= e(setting('parts_email')) ?>"><?= e(setting('parts_email')) ?></a></div></li>
              <li><span class="ico" aria-hidden="true">📍</span>
                <div><b>Yard &amp; parts counter</b>
                  <span style="color:#fff;font-weight:600"><?= e(setting('address')) ?></span></div></li>
              <li><span class="ico" aria-hidden="true">🕗</span>
                <div><b>Opening hours</b>
                  <span style="color:#fff;font-weight:600"><?= e(setting('hours')) ?></span></div></li>
            </ul>
            <div class="btn-row" style="margin-top:22px">
              <a class="btn btn--accent btn--block" target="_blank" rel="noopener"
                 href="<?= e(wa_link('Hello ' . $name . ', I would like a quote.')) ?>">Start a WhatsApp chat</a>
            </div>
          </div>

          <div class="panel" style="margin-top:22px">
            <h3>What to include for a fast answer</h3>
            <ul>
              <li><b>Importing:</b> model, year range, gearbox, maximum mileage, budget and the port
                  or city where the vehicle will be registered.</li>
              <li><b>Parts:</b> chassis number (e.g. <code>NZE141-1234567</code>), the part name, and
                  a photo of the old item if you have one.</li>
              <li><b>Trade account:</b> business name, monthly volume and the makes you service most.</li>
            </ul>
            <p style="margin-bottom:0">We reply to every enquiry, including the ones where the honest
               answer is that we cannot help.</p>
          </div>

          <div class="panel" style="margin-top:22px">
            <h3>Payment safety</h3>
            <p style="margin-bottom:0">We only ever ask for payment by bank transfer to the company
               account printed on your proforma invoice. We will never ask you to pay an individual,
               and we will never change bank details by email mid-transaction. If you receive such a
               request, stop and call us on the number above.</p>
          </div>
        </div>

      </div>
    </div>
  </section>

<?php require __DIR__ . '/includes/footer.php'; ?>
