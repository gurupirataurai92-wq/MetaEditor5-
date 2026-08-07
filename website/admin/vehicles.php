<?php
/** Vehicle list for operators. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Vehicles';
$tab = 'vehicles';
require __DIR__ . '/_header.php';

$q = trim((string)($_GET['q'] ?? ''));
$where = [];
$params = [];
if ($q !== '') {
    $where[] = '(v.make LIKE ? OR v.model LIKE ? OR v.ref LIKE ?)';
    $like = '%' . $q . '%';
    array_push($params, $like, $like, $like);
}
$show = (string)($_GET['show'] ?? '');
if ($show === 'draft')    { $where[] = 'v.is_published = 0'; }
if ($show === 'nophoto')  { $where[] = "NOT EXISTS (SELECT 1 FROM photos p WHERE p.item_type='vehicle' AND p.item_id=v.id)"; }

$sql = 'FROM vehicles v' . ($where ? ' WHERE ' . implode(' AND ', $where) : '');
$rows = q_all(
    "SELECT v.*,
            (SELECT p.filename FROM photos p WHERE p.item_type='vehicle' AND p.item_id=v.id
              ORDER BY p.sort_order, p.id LIMIT 1) AS cover,
            (SELECT COUNT(*) FROM photos p WHERE p.item_type='vehicle' AND p.item_id=v.id) AS photo_count
     $sql ORDER BY v.updated_at DESC",
    $params
);
?>

<div class="mgr-head">
  <div>
    <h2>Vehicles</h2>
    <p><?= count($rows) ?> shown · <?= (int)q_val('SELECT COUNT(*) FROM vehicles') ?> in total</p>
  </div>
  <a class="btn btn--primary" href="<?= e(url('admin/vehicle-edit.php')) ?>">+ Add vehicle</a>
</div>

<form class="toolbar" method="get" action="<?= e(url('admin/vehicles.php')) ?>">
  <div class="field-row">
    <div class="field">
      <label for="q">Search</label>
      <input type="search" id="q" name="q" value="<?= e($q) ?>" placeholder="Make, model or reference">
    </div>
    <div class="field">
      <label for="show">Show</label>
      <select id="show" name="show">
        <option value="">All vehicles</option>
        <option value="draft"<?= $show === 'draft' ? ' selected' : '' ?>>Unpublished only</option>
        <option value="nophoto"<?= $show === 'nophoto' ? ' selected' : '' ?>>Missing photographs</option>
      </select>
    </div>
    <div class="field">
      <label aria-hidden="true">&nbsp;</label>
      <button class="btn btn--primary btn--block" type="submit">Filter</button>
    </div>
  </div>
</form>

<div class="item-list">
<?php if (!$rows): ?>
  <div class="empty"><h3>Nothing here</h3><p>No vehicles match that filter.</p></div>
<?php endif; ?>
<?php foreach ($rows as $v): ?>
  <?php [$statusText, ] = status_label($v['status']); ?>
  <div class="item-row">
    <img class="thumb" src="<?= e(vehicle_photo($v)) ?>" alt="">
    <div>
      <h3><?= e($v['year'] . ' ' . $v['make'] . ' ' . $v['model']) ?>
        <span class="badge-mini <?= $v['status'] === 'in-stock' ? 'ok' : 'warn' ?>"><?= e($statusText) ?></span>
        <?php if ((int)$v['photo_count']): ?>
          <span class="badge-mini ok"><?= (int)$v['photo_count'] ?> photo<?= $v['photo_count'] == 1 ? '' : 's' ?></span>
        <?php else: ?>
          <span class="badge-mini none">No photo</span>
        <?php endif; ?>
        <?php if (!$v['is_published']): ?><span class="badge-mini none">Unpublished</span><?php endif; ?>
      </h3>
      <p class="meta"><?= e($v['ref']) ?> · <?= e(body_label($v['body'])) ?> · <?= e($v['fuel']) ?>
         · <?= e(km($v['mileage'])) ?> · <?= e(money($v['price'])) ?></p>
    </div>
    <div class="item-actions">
      <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/vehicle-edit.php?id=' . (int)$v['id'])) ?>">Edit</a>
      <a class="btn btn--ghost btn--sm" target="_blank" rel="noopener"
         href="<?= e(url('vehicle.php?ref=' . urlencode($v['ref']))) ?>">View</a>
    </div>
  </div>
<?php endforeach; ?>
</div>

<?php require __DIR__ . '/_footer.php'; ?>
