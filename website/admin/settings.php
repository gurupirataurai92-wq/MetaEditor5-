<?php
/** Company details shown across the public website. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Company details';
$tab = 'settings';

$fields = [
    'company_name'  => ['Company name', 'text'],
    'tagline'       => ['Tagline', 'text'],
    'phone'         => ['Phone', 'tel'],
    'whatsapp'      => ['WhatsApp number (international format)', 'tel'],
    'email'         => ['Sales email', 'email'],
    'parts_email'   => ['Parts email', 'email'],
    'address'       => ['Address', 'text'],
    'hours'         => ['Opening hours', 'text'],
    'stat_vehicles' => ['Home page figure: vehicles delivered', 'text'],
    'stat_parts'    => ['Home page figure: part lines sourced', 'text'],
    'stat_sailing'  => ['Home page figure: sailing time', 'text'],
    'stat_years'    => ['Home page figure: years in trade', 'text'],
];

$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();

    foreach (['email', 'parts_email'] as $f) {
        $v = trim((string)($_POST[$f] ?? ''));
        if ($v !== '' && !filter_var($v, FILTER_VALIDATE_EMAIL)) {
            $errors[$f] = 'That email address does not look right.';
        }
    }
    $wa = preg_replace('/[^0-9]/', '', (string)($_POST['whatsapp'] ?? ''));
    if ($wa !== '' && strlen($wa) < 8) {
        $errors['whatsapp'] = 'Use the full international number, e.g. +255 754 000 111.';
    }
    if (trim((string)($_POST['company_name'] ?? '')) === '') {
        $errors['company_name'] = 'The company needs a name.';
    }

    if (!$errors) {
        foreach (array_keys($fields) as $key) {
            q('INSERT INTO settings (name, value) VALUES (?, ?)
               ON DUPLICATE KEY UPDATE value = VALUES(value)',
              [$key, trim((string)($_POST[$key] ?? ''))]);
        }
        log_activity('updated the company details');
        flash('Company details saved. They are live on the website now.');
        redirect('admin/settings.php');
    }
}

require __DIR__ . '/_header.php';
?>

<div class="mgr-head">
  <div>
    <h2>Company details</h2>
    <p>These appear in the header, the footer, the contact page and every WhatsApp link.</p>
  </div>
</div>

<?php if ($errors): ?>
  <div class="form-status show bad" style="margin-bottom:18px">Please correct the highlighted fields.</div>
<?php endif; ?>

<form class="editor" method="post" action="<?= e(url('admin/settings.php')) ?>">
  <?= csrf_field() ?>
  <div class="field-row">
    <?php foreach ($fields as $key => [$label, $type]): ?>
      <div class="field">
        <label for="s-<?= e($key) ?>"><?= e($label) ?></label>
        <input type="<?= e($type) ?>" id="s-<?= e($key) ?>" name="<?= e($key) ?>"
               value="<?= e($_POST[$key] ?? setting($key)) ?>">
        <span class="err"><?= e($errors[$key] ?? '') ?></span>
      </div>
    <?php endforeach; ?>
  </div>
  <div class="editor-foot">
    <button class="btn btn--primary" type="submit">Save details</button>
  </div>
</form>

<div class="note">
  <p>The four "home page figure" boxes are shown as claims to visitors. Put real numbers there, or
     clear them if you would rather not make the claim.</p>
</div>

<?php require __DIR__ . '/_footer.php'; ?>
