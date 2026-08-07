<?php
/** Spare-part list for operators. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Spare parts';
$tab = 'parts';
require __DIR__ . '/_header.php';

$q = trim((string)($_GET['q'] ?? ''));
$where = [];
$params = [];
if ($q !== '') {
    $where[] = '(p.name LIKE ? OR p.sku LIKE ? OR p.ref LIKE ? OR p.fits LIKE ?)';
    $like = '%' . $q . '%';
    array_push($params, $like, $like, $like, $like);
}
$cat = trim((string)($_GET['category'] ?? ''));
if ($cat !== '') { $where[] = 'c.slug = ?'; $params[] = $cat; }
$show = (string)($_GET['show'] ?? '');
if ($show === 'draft')   { $where[] = 'p.is_published = 0'; }
if ($show === 'nophoto') { $where[] = "NOT EXISTS (SELECT 1 FROM photos ph WHERE ph.item_type='part' AND ph.item_id=p.id)"; }

$sql = 'FROM parts p JOIN part_categories c ON c.id = p.category_id'
     . ($where ? ' WHERE ' . implode(' AND ', $where) : '');
$rows = q_all(
    "SELECT p.*, c.slug AS category_slug, c.name AS category_name,
            (SELECT ph.filename FROM photos ph WHERE ph.item_type='part' AND ph.item_id=p.id
              ORDER BY ph.sort_order, ph.id LIMIT 1) AS cover,
            (SELECT COUNT(*) FROM photos ph WHERE ph.item_type='part' AND ph.item_id=p.id) AS photo_count
     $sql ORDER BY p.updated_at DESC",
    $params
);
$categories = q_all('SELECT * FROM part_categories ORDER BY sort_order');
?>

<div class="mgr-head">
  <div>
    <h2>Spare parts</h2>
    <p><?= count($rows) ?> shown · <?= (int)q_val('SELECT COUNT(*) FROM parts') ?> in total</p>
  </div>
  <a class="btn btn--primary" href="<?= e(url('admin/part-edit.php')) ?>">+ Add part</a>
</div>

<form class="toolbar" method="get" action="<?= e(url('admin/parts.php')) ?>">
  <div class="field-row">
    <div class="field">
      <label for="q">Search</label>
      <input type="search" id="q" name="q" value="<?= e($q) ?>" placeholder="Name, SKU, reference or fitment">
    </div>
    <div class="field">
      <label for="category">Category</label>
      <select id="category" name="category">
        <option value="">All categories</option>
        <?php foreach ($categories as $c): ?>
          <option value="<?= e($c['slug']) ?>"<?= $cat === $c['slug'] ? ' selected' : '' ?>><?= e($c['name']) ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="field">
      <label for="show">Show</label>
      <select id="show" name="show">
        <option value="">All parts</option>
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
  <div class="empty"><h3>Nothing here</h3><p>No parts match that filter.</p></div>
<?php endif; ?>
<?php foreach ($rows as $p): ?>
  <div class="item-row">
    <img class="thumb" src="<?= e(part_photo($p)) ?>" alt="">
    <div>
      <h3><?= e($p['name']) ?>
        <span class="badge-mini <?= $p['stock'] === 'in-stock' ? 'ok' : 'warn' ?>">
          <?= $p['stock'] === 'in-stock' ? 'In stock' : 'On order' ?></span>
        <?php if ((int)$p['photo_count']): ?>
          <span class="badge-mini ok"><?= (int)$p['photo_count'] ?> photo<?= $p['photo_count'] == 1 ? '' : 's' ?></span>
        <?php else: ?>
          <span class="badge-mini none">No photo</span>
        <?php endif; ?>
        <?php if (!$p['is_published']): ?><span class="badge-mini none">Unpublished</span><?php endif; ?>
      </h3>
      <p class="meta"><?= e($p['ref']) ?> · <?= e($p['sku']) ?> · <?= e($p['category_name']) ?>
         · <?= e(size_label($p['size'])) ?> · <?= e(money($p['price'])) ?></p>
    </div>
    <div class="item-actions">
      <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/part-edit.php?id=' . (int)$p['id'])) ?>">Edit</a>
      <a class="btn btn--ghost btn--sm" target="_blank" rel="noopener"
         href="<?= e(url('part.php?ref=' . urlencode($p['ref']))) ?>">View</a>
    </div>
  </div>
<?php endforeach; ?>
</div>

<?php require __DIR__ . '/_footer.php'; ?>
