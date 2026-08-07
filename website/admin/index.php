<?php
/** Operator dashboard. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Dashboard';
$tab = 'dash';
require __DIR__ . '/_header.php';

$stats = [
    'vehicles'      => (int)q_val('SELECT COUNT(*) FROM vehicles'),
    'vehicles_live' => (int)q_val('SELECT COUNT(*) FROM vehicles WHERE is_published = 1'),
    'no_photo_v'    => (int)q_val("SELECT COUNT(*) FROM vehicles v WHERE NOT EXISTS
                                    (SELECT 1 FROM photos p WHERE p.item_type='vehicle' AND p.item_id=v.id)"),
    'parts'         => (int)q_val('SELECT COUNT(*) FROM parts'),
    'parts_live'    => (int)q_val('SELECT COUNT(*) FROM parts WHERE is_published = 1'),
    'no_photo_p'    => (int)q_val("SELECT COUNT(*) FROM parts p WHERE NOT EXISTS
                                    (SELECT 1 FROM photos ph WHERE ph.item_type='part' AND ph.item_id=p.id)"),
    'enq_new'       => (int)q_val("SELECT COUNT(*) FROM enquiries WHERE status = 'new'"),
    'photos'        => (int)q_val('SELECT COUNT(*) FROM photos'),
];

$latest = q_all('SELECT * FROM enquiries ORDER BY created_at DESC LIMIT 6');
$recent = q_all(
    'SELECT a.*, o.name AS operator_name
       FROM activity_log a LEFT JOIN operators o ON o.id = a.operator_id
      ORDER BY a.happened_at DESC LIMIT 12'
);
?>

<div class="mgr-head">
  <div>
    <h2>Good to see you, <?= e($op['name']) ?></h2>
    <p>Everything below is live in the database. Changes appear on the website immediately.</p>
  </div>
  <div class="btn-row">
    <a class="btn btn--primary" href="<?= e(url('admin/vehicle-edit.php')) ?>">+ Add vehicle</a>
    <a class="btn btn--ghost" href="<?= e(url('admin/part-edit.php')) ?>">+ Add part</a>
  </div>
</div>

<div class="stat-cards">
  <a class="stat-card" href="<?= e(url('admin/vehicles.php')) ?>">
    <b><?= $stats['vehicles'] ?></b><span>Vehicles</span>
    <em><?= $stats['vehicles_live'] ?> published</em>
  </a>
  <a class="stat-card" href="<?= e(url('admin/parts.php')) ?>">
    <b><?= $stats['parts'] ?></b><span>Part lines</span>
    <em><?= $stats['parts_live'] ?> published</em>
  </a>
  <a class="stat-card" href="<?= e(url('admin/enquiries.php')) ?>">
    <b><?= $stats['enq_new'] ?></b><span>New enquiries</span>
    <em>waiting for a reply</em>
  </a>
  <div class="stat-card">
    <b><?= $stats['photos'] ?></b><span>Photographs</span>
    <em><?= $stats['no_photo_v'] + $stats['no_photo_p'] ?> items still without one</em>
  </div>
</div>

<?php if ($stats['no_photo_v'] + $stats['no_photo_p'] > 0): ?>
  <div class="note" style="margin-top:24px">
    <p><b>Items without a photograph show a drawing instead.</b>
       <?= $stats['no_photo_v'] ?> vehicle<?= $stats['no_photo_v'] === 1 ? '' : 's' ?> and
       <?= $stats['no_photo_p'] ?> part<?= $stats['no_photo_p'] === 1 ? '' : 's' ?> are waiting for
       pictures — buyers respond far better to real photos.</p>
  </div>
<?php endif; ?>

<div class="grid grid--2 grid--top" style="margin-top:28px">
  <div class="editor">
    <h3>Latest enquiries</h3>
    <?php if (!$latest): ?>
      <p class="card-sub">Nothing yet. Enquiries from the contact form arrive here.</p>
    <?php else: ?>
      <div class="table-scroll" style="margin-top:12px">
        <table>
          <thead><tr><th>From</th><th>About</th><th>When</th><th></th></tr></thead>
          <tbody>
          <?php foreach ($latest as $en): ?>
            <tr>
              <td><?= e($en['name']) ?>
                <?php if ($en['status'] === 'new'): ?><span class="badge-mini warn">new</span><?php endif; ?></td>
              <td><?= e($en['topic']) ?><?= $en['ref'] ? ' · ' . e($en['ref']) : '' ?></td>
              <td><?= e(date('j M, H:i', strtotime($en['created_at']))) ?></td>
              <td><a href="<?= e(url('admin/enquiries.php#e' . (int)$en['id'])) ?>">Open</a></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>
  </div>

  <div class="editor">
    <h3>Recent activity</h3>
    <p class="card-sub">Who changed what, most recent first.</p>
    <?php if (!$recent): ?>
      <p class="card-sub">Nothing logged yet.</p>
    <?php else: ?>
      <ul class="activity">
        <?php foreach ($recent as $a): ?>
          <li>
            <span class="when"><?= e(date('j M H:i', strtotime($a['happened_at']))) ?></span>
            <span><b><?= e($a['operator_name'] ?? 'system') ?></b>
              <?= e($a['action']) ?><?= $a['detail'] ? ' — ' . e($a['detail']) : '' ?></span>
          </li>
        <?php endforeach; ?>
      </ul>
    <?php endif; ?>
  </div>
</div>

<?php require __DIR__ . '/_footer.php'; ?>
