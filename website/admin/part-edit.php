<?php
/** Add or edit a spare part, including its photographs. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Spare part';
$tab = 'parts';

$id = (int)($_GET['id'] ?? 0);
$part = $id ? q_one('SELECT * FROM parts WHERE id = ?', [$id]) : null;
if ($id && !$part) { http_response_code(404); }

$categories = q_all('SELECT * FROM part_categories ORDER BY sort_order');
$categoryIds = array_map('intval', array_column($categories, 'id'));

$TYPES = ['genuine' => 'Genuine', 'oem' => 'OEM', 'aftermarket' => 'Aftermarket', 'used' => 'Japan used'];
$SIZES = ['small' => 'Small — clips, filters, sensors',
          'medium' => 'Medium — pumps, lamps, shocks',
          'large' => 'Large — engines, gearboxes, panels'];
$STOCKS = ['in-stock' => 'In stock', 'order' => 'On order'];

$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $op = current_operator();
    $action = (string)($_POST['action'] ?? 'save');

    if ($action === 'photo-delete' && $part) {
        delete_photo((int)$_POST['photo_id'], 'part', (int)$part['id']);
        log_activity('deleted a part photo', $part['ref']);
        flash('Photograph removed.');
        redirect('admin/part-edit.php?id=' . (int)$part['id']);
    }
    if ($action === 'photo-cover' && $part) {
        make_cover((int)$_POST['photo_id'], 'part', (int)$part['id']);
        flash('Cover photograph changed.');
        redirect('admin/part-edit.php?id=' . (int)$part['id']);
    }
    if ($action === 'delete' && $part) {
        delete_photos_for('part', (int)$part['id']);
        q('DELETE FROM parts WHERE id = ?', [$part['id']]);
        log_activity('deleted a part', $part['ref'] . ' ' . $part['name']);
        flash('Part deleted.');
        redirect('admin/parts.php');
    }

    $in = [
        'name'         => trim((string)($_POST['name'] ?? '')),
        'category_id'  => (int)($_POST['category_id'] ?? 0),
        'sku'          => trim((string)($_POST['sku'] ?? '')),
        'brand'        => trim((string)($_POST['brand'] ?? '')),
        'type'         => (string)($_POST['type'] ?? 'oem'),
        'size'         => (string)($_POST['size'] ?? 'small'),
        'price'        => (float)($_POST['price'] ?? 0),
        'stock'        => (string)($_POST['stock'] ?? 'in-stock'),
        'fits'         => trim((string)($_POST['fits'] ?? '')),
        'note'         => trim((string)($_POST['note'] ?? '')),
        'is_published' => isset($_POST['is_published']) ? 1 : 0,
    ];

    if ($in['name'] === '') { $errors['name'] = 'Give the part a name.'; }
    if ($in['sku'] === '')  { $errors['sku'] = 'Add a part number or SKU.'; }
    if ($in['price'] <= 0)  { $errors['price'] = 'Enter the price in US dollars.'; }
    if ($in['fits'] === '') { $errors['fits'] = 'List at least one vehicle this fits.'; }
    if (!in_array($in['category_id'], $categoryIds, true)) { $errors['category_id'] = 'Choose a category.'; }
    if (!array_key_exists($in['type'], $TYPES))   { $in['type'] = 'oem'; }
    if (!array_key_exists($in['size'], $SIZES))   { $in['size'] = 'small'; }
    if (!array_key_exists($in['stock'], $STOCKS)) { $in['stock'] = 'in-stock'; }

    if (!$errors) {
        if ($part) {
            q('UPDATE parts SET name=?, category_id=?, sku=?, brand=?, type=?, size=?, price=?,
                      stock=?, fits=?, note=?, is_published=? WHERE id=?',
              [$in['name'], $in['category_id'], $in['sku'], $in['brand'] ?: 'Unbranded', $in['type'],
               $in['size'], $in['price'], $in['stock'], $in['fits'], $in['note'] ?: null,
               $in['is_published'], $part['id']]);
            $partId = (int)$part['id'];
            $ref = $part['ref'];
            log_activity('updated a part', $ref . ' ' . $in['name']);
        } else {
            $next = (int)q_val("SELECT COALESCE(MAX(CAST(SUBSTRING(ref, 3) AS UNSIGNED)), 0) + 1
                                  FROM parts WHERE ref REGEXP '^P-[0-9]+$'");
            $ref = 'P-' . str_pad((string)$next, 3, '0', STR_PAD_LEFT);
            q('INSERT INTO parts (ref, name, category_id, sku, brand, type, size, price, stock, fits,
                                  note, is_published, created_by)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
              [$ref, $in['name'], $in['category_id'], $in['sku'], $in['brand'] ?: 'Unbranded',
               $in['type'], $in['size'], $in['price'], $in['stock'], $in['fits'],
               $in['note'] ?: null, $in['is_published'], $op['id']]);
            $partId = (int)db()->lastInsertId();
            log_activity('added a part', $ref . ' ' . $in['name']);
        }

        foreach (store_photos('photos', 'part', $partId, strtolower($ref)) as $problem) {
            flash($problem, 'bad');
        }

        flash($part ? 'Part updated.' : 'Part ' . $ref . ' added.');
        redirect('admin/part-edit.php?id=' . $partId);
    }
}

$photos = $part ? photos_for('part', (int)$part['id']) : [];

function p_val(string $field, $default = '')
{
    global $part;
    if (isset($_POST[$field])) { return $_POST[$field]; }
    return $part[$field] ?? $default;
}

require __DIR__ . '/_header.php';
?>

<div class="mgr-head">
  <div>
    <h2><?= $part ? 'Edit ' . e($part['ref']) : 'Add a spare part' ?></h2>
    <p><?= $part
          ? 'Last changed ' . e(date('j M Y, H:i', strtotime($part['updated_at'])))
          : 'A reference number is given automatically when you save.' ?></p>
  </div>
  <a class="btn btn--ghost" href="<?= e(url('admin/parts.php')) ?>">← All parts</a>
</div>

<?php if ($errors): ?>
  <div class="form-status show bad" style="margin-bottom:18px">Please correct the highlighted fields.</div>
<?php endif; ?>

<form class="editor" method="post" enctype="multipart/form-data"
      action="<?= e(url('admin/part-edit.php' . ($part ? '?id=' . (int)$part['id'] : ''))) ?>">
  <?= csrf_field() ?>
  <input type="hidden" name="action" value="save">

  <div class="field-row">
    <div class="field" style="grid-column:span 2">
      <label for="name">Part name *</label>
      <input type="text" id="name" name="name" value="<?= e(p_val('name')) ?>"
             placeholder="Front Brake Pad Set (Ceramic)">
      <span class="err"><?= e($errors['name'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="sku">Part number / SKU *</label>
      <input type="text" id="sku" name="sku" value="<?= e(p_val('sku')) ?>" placeholder="BRK-PAD-LC">
      <span class="err"><?= e($errors['sku'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="price">Price in USD *</label>
      <input type="number" id="price" name="price" min="0" step="1" value="<?= e(p_val('price')) ?>">
      <span class="err"><?= e($errors['price'] ?? '') ?></span>
    </div>
  </div>

  <div class="field-row">
    <div class="field">
      <label for="category_id">Category</label>
      <select id="category_id" name="category_id">
        <?php foreach ($categories as $c): ?>
          <option value="<?= (int)$c['id'] ?>"<?= (int)p_val('category_id', 0) === (int)$c['id'] ? ' selected' : '' ?>>
            <?= e($c['name']) ?></option>
        <?php endforeach; ?>
      </select>
      <span class="err"><?= e($errors['category_id'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="size">Size</label>
      <select id="size" name="size">
        <?php foreach ($SIZES as $k => $label): ?>
          <option value="<?= e($k) ?>"<?= p_val('size', 'small') === $k ? ' selected' : '' ?>><?= e($label) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field">
      <label for="type">Grade</label>
      <select id="type" name="type">
        <?php foreach ($TYPES as $k => $label): ?>
          <option value="<?= e($k) ?>"<?= p_val('type', 'oem') === $k ? ' selected' : '' ?>><?= e($label) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field">
      <label for="stock">Availability</label>
      <select id="stock" name="stock">
        <?php foreach ($STOCKS as $k => $label): ?>
          <option value="<?= e($k) ?>"<?= p_val('stock', 'in-stock') === $k ? ' selected' : '' ?>><?= e($label) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
  </div>

  <div class="field-row">
    <div class="field">
      <label for="brand">Brand</label>
      <input type="text" id="brand" name="brand" value="<?= e(p_val('brand')) ?>" placeholder="Advics">
      <span class="err"></span>
    </div>
    <div class="field" style="grid-column:span 3">
      <label for="fits">Fits which vehicles — separate with commas *</label>
      <input type="text" id="fits" name="fits" value="<?= e(p_val('fits')) ?>"
             placeholder="Toyota Prado 150, Toyota Hilux">
      <span class="err"><?= e($errors['fits'] ?? '') ?></span>
    </div>
  </div>

  <div class="field-row">
    <div class="field" style="grid-column:1 / -1">
      <label for="note">Short note shown on the card</label>
      <input type="text" id="note" name="note" maxlength="200" value="<?= e(p_val('note')) ?>"
             placeholder="Compression tested, 3-month warranty.">
      <span class="err"></span>
    </div>
  </div>

  <label class="switch">
    <input type="checkbox" name="is_published" value="1" <?= (int)p_val('is_published', 1) ? 'checked' : '' ?>>
    <span>Show this part on the website</span>
  </label>

  <div style="margin-top:18px">
    <label style="font-size:.82rem;font-weight:700;display:block;margin-bottom:6px">Add photographs</label>
    <div class="drop" id="v-drop" tabindex="0" role="button">
      <b>Choose photos</b>
      JPEG, PNG or WebP, up to <?= (int)(UPLOAD_MAX_BYTES / 1048576) ?> MB each. They are resized on upload.
    </div>
    <input type="file" id="v-files" name="photos[]" accept="image/*" multiple hidden>
    <div class="thumbs" id="v-preview"></div>
  </div>

  <div class="editor-foot">
    <button class="btn btn--primary" type="submit"><?= $part ? 'Save changes' : 'Create part' ?></button>
    <a class="btn btn--ghost" href="<?= e(url('admin/parts.php')) ?>">Cancel</a>
  </div>
</form>

<?php if ($part): ?>
  <div class="editor">
    <h3>Photographs <span class="card-sub">(<?= count($photos) ?> of <?= PHOTOS_PER_ITEM ?>)</span></h3>
    <?php if (!$photos): ?>
      <p class="card-sub">None yet. The website shows the category illustration until you add one.</p>
    <?php else: ?>
      <div class="thumbs">
        <?php foreach ($photos as $i => $ph): ?>
          <div class="thumb-card">
            <?php if ($i === 0): ?><span class="cover-flag">Cover</span><?php endif; ?>
            <img src="<?= e(url('assets/uploads/' . rawurlencode($ph['filename']))) ?>" alt="">
            <div class="thumb-tools">
              <?php if ($i > 0): ?>
                <form method="post" action="<?= e(url('admin/part-edit.php?id=' . (int)$part['id'])) ?>">
                  <?= csrf_field() ?>
                  <input type="hidden" name="action" value="photo-cover">
                  <input type="hidden" name="photo_id" value="<?= (int)$ph['id'] ?>">
                  <button type="submit">Cover</button>
                </form>
              <?php else: ?>
                <button type="button" disabled>Cover</button>
              <?php endif; ?>
              <form method="post" action="<?= e(url('admin/part-edit.php?id=' . (int)$part['id'])) ?>"
                    onsubmit="return confirm('Delete this photograph?')">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="photo-delete">
                <input type="hidden" name="photo_id" value="<?= (int)$ph['id'] ?>">
                <button type="submit" class="danger">Remove</button>
              </form>
            </div>
          </div>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>
  </div>

  <div class="editor danger-zone">
    <h3>Delete this part</h3>
    <p class="card-sub">Removes the record and its photographs for good.</p>
    <form method="post" action="<?= e(url('admin/part-edit.php?id=' . (int)$part['id'])) ?>"
          onsubmit="return confirm('Delete this part permanently?')">
      <?= csrf_field() ?>
      <input type="hidden" name="action" value="delete">
      <button class="btn btn--ghost btn--sm" type="submit">Delete part</button>
    </form>
  </div>
<?php endif; ?>

<?php require __DIR__ . '/_footer.php'; ?>
