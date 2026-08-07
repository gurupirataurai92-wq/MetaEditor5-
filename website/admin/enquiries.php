<?php
/** Customer enquiries from the contact form. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Enquiries';
$tab = 'enquiries';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $op = current_operator();
    $enquiryId = (int)($_POST['id'] ?? 0);
    $action = (string)($_POST['action'] ?? '');

    if ($action === 'status') {
        $status = (string)($_POST['status'] ?? 'new');
        if (in_array($status, ['new', 'in-progress', 'closed'], true)) {
            q('UPDATE enquiries SET status = ?, handled_by = ? WHERE id = ?',
              [$status, $op['id'], $enquiryId]);
            log_activity('changed an enquiry status', '#' . $enquiryId . ' → ' . $status);
            flash('Enquiry marked as ' . str_replace('-', ' ', $status) . '.');
        }
    } elseif ($action === 'delete') {
        q('DELETE FROM enquiries WHERE id = ?', [$enquiryId]);
        log_activity('deleted an enquiry', '#' . $enquiryId);
        flash('Enquiry deleted.');
    }
    redirect('admin/enquiries.php' . (isset($_POST['back']) ? '?status=' . urlencode((string)$_POST['back']) : ''));
}

$status = (string)($_GET['status'] ?? '');
$where = in_array($status, ['new', 'in-progress', 'closed'], true) ? 'WHERE status = ?' : '';
$params = $where ? [$status] : [];

$rows = q_all(
    "SELECT e.*, o.name AS handler FROM enquiries e
       LEFT JOIN operators o ON o.id = e.handled_by
     $where ORDER BY e.created_at DESC LIMIT 200",
    $params
);

$counts = [
    'new'         => (int)q_val("SELECT COUNT(*) FROM enquiries WHERE status='new'"),
    'in-progress' => (int)q_val("SELECT COUNT(*) FROM enquiries WHERE status='in-progress'"),
    'closed'      => (int)q_val("SELECT COUNT(*) FROM enquiries WHERE status='closed'"),
];

require __DIR__ . '/_header.php';
?>

<div class="mgr-head">
  <div>
    <h2>Enquiries</h2>
    <p><?= $counts['new'] ?> new · <?= $counts['in-progress'] ?> in progress · <?= $counts['closed'] ?> closed</p>
  </div>
  <div class="chips">
    <a class="chip" aria-pressed="<?= $status === '' ? 'true' : 'false' ?>" href="<?= e(url('admin/enquiries.php')) ?>">All</a>
    <?php foreach (['new' => 'New', 'in-progress' => 'In progress', 'closed' => 'Closed'] as $k => $label): ?>
      <a class="chip" aria-pressed="<?= $status === $k ? 'true' : 'false' ?>"
         href="<?= e(url('admin/enquiries.php?status=' . $k)) ?>"><?= e($label) ?></a>
    <?php endforeach; ?>
  </div>
</div>

<?php if (!$rows): ?>
  <div class="empty"><h3>No enquiries here</h3><p>Messages from the contact form arrive on this page.</p></div>
<?php endif; ?>

<div class="enquiry-list">
<?php foreach ($rows as $en): ?>
  <article class="editor" id="e<?= (int)$en['id'] ?>">
    <div class="enquiry-head">
      <div>
        <h3><?= e($en['name']) ?>
          <span class="badge-mini <?= $en['status'] === 'new' ? 'warn' : ($en['status'] === 'closed' ? '' : 'ok') ?>">
            <?= e(str_replace('-', ' ', $en['status'])) ?></span>
        </h3>
        <p class="meta">
          <a href="mailto:<?= e($en['email']) ?>"><?= e($en['email']) ?></a>
          <?php if ($en['phone']): ?> · <a href="tel:<?= e($en['phone']) ?>"><?= e($en['phone']) ?></a><?php endif; ?>
          · <?= e($en['topic']) ?>
          <?php if ($en['ref']): ?> · about <b><?= e($en['ref']) ?></b><?php endif; ?>
          · <?= e(date('j M Y, H:i', strtotime($en['created_at']))) ?>
          <?php if ($en['handler']): ?> · handled by <?= e($en['handler']) ?><?php endif; ?>
        </p>
      </div>
    </div>

    <blockquote class="enquiry-body"><?= nl2br(e($en['message'])) ?></blockquote>

    <div class="editor-foot">
      <a class="btn btn--primary btn--sm"
         href="mailto:<?= e($en['email']) ?>?subject=<?= e(rawurlencode('Re: your enquiry to ' . setting('company_name'))) ?>">Reply by email</a>
      <?php if ($en['phone']): ?>
        <a class="btn btn--ghost btn--sm" target="_blank" rel="noopener"
           href="https://wa.me/<?= e(preg_replace('/[^0-9]/', '', $en['phone'])) ?>">WhatsApp</a>
      <?php endif; ?>

      <?php foreach (['new' => 'Mark new', 'in-progress' => 'Mark in progress', 'closed' => 'Mark closed'] as $k => $label): ?>
        <?php if ($en['status'] !== $k): ?>
          <form method="post" action="<?= e(url('admin/enquiries.php')) ?>" style="display:inline">
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="status">
            <input type="hidden" name="id" value="<?= (int)$en['id'] ?>">
            <input type="hidden" name="status" value="<?= e($k) ?>">
            <input type="hidden" name="back" value="<?= e($status) ?>">
            <button class="btn btn--ghost btn--sm" type="submit"><?= e($label) ?></button>
          </form>
        <?php endif; ?>
      <?php endforeach; ?>

      <span class="spacer"></span>
      <form method="post" action="<?= e(url('admin/enquiries.php')) ?>" style="display:inline"
            onsubmit="return confirm('Delete this enquiry?')">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="delete">
        <input type="hidden" name="id" value="<?= (int)$en['id'] ?>">
        <input type="hidden" name="back" value="<?= e($status) ?>">
        <button class="btn btn--ghost btn--sm" type="submit">Delete</button>
      </form>
    </div>
  </article>
<?php endforeach; ?>
</div>

<?php require __DIR__ . '/_footer.php'; ?>
