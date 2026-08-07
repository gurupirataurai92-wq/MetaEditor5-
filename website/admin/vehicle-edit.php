<?php
/** Add or edit a vehicle, including its photographs. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Vehicle';
$tab = 'vehicles';

$id = (int)($_GET['id'] ?? 0);
$vehicle = $id ? q_one('SELECT * FROM vehicles WHERE id = ?', [$id]) : null;
if ($id && !$vehicle) { http_response_code(404); }

$errors = [];

$BODIES = ['sedan', 'hatchback', 'suv', 'van', 'pickup', 'truck'];
$FUELS  = ['Petrol', 'Diesel', 'Hybrid', 'Electric'];
$GEARS  = ['Automatic', 'Manual'];
$DRIVES = ['2WD', '4WD', 'AWD'];
$STATES = ['in-stock' => 'In stock', 'in-transit' => 'In transit', 'to-order' => 'To order'];
$GRADES = ['5', '4.5', '4', '3.5', '3', 'R'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $op = current_operator();
    $action = (string)($_POST['action'] ?? 'save');

    /* ---------------------------------------------------------- photos -- */
    if ($action === 'photo-delete' && $vehicle) {
        delete_photo((int)$_POST['photo_id'], 'vehicle', (int)$vehicle['id']);
        log_activity('deleted a vehicle photo', $vehicle['ref']);
        flash('Photograph removed.');
        redirect('admin/vehicle-edit.php?id=' . (int)$vehicle['id']);
    }
    if ($action === 'photo-cover' && $vehicle) {
        make_cover((int)$_POST['photo_id'], 'vehicle', (int)$vehicle['id']);
        flash('Cover photograph changed.');
        redirect('admin/vehicle-edit.php?id=' . (int)$vehicle['id']);
    }
    if ($action === 'delete' && $vehicle) {
        delete_photos_for('vehicle', (int)$vehicle['id']);
        q('DELETE FROM vehicles WHERE id = ?', [$vehicle['id']]);
        log_activity('deleted a vehicle', $vehicle['ref'] . ' ' . $vehicle['make'] . ' ' . $vehicle['model']);
        flash('Vehicle deleted.');
        redirect('admin/vehicles.php');
    }

    /* ------------------------------------------------------------ save -- */
    $in = [
        'make'         => trim((string)($_POST['make'] ?? '')),
        'model'        => trim((string)($_POST['model'] ?? '')),
        'year'         => (int)($_POST['year'] ?? 0),
        'body'         => (string)($_POST['body'] ?? 'sedan'),
        'fuel'         => (string)($_POST['fuel'] ?? 'Petrol'),
        'transmission' => (string)($_POST['transmission'] ?? 'Automatic'),
        'engine'       => trim((string)($_POST['engine'] ?? '')),
        'mileage'      => (int)($_POST['mileage'] ?? 0),
        'drive'        => (string)($_POST['drive'] ?? '2WD'),
        'colour'       => trim((string)($_POST['colour'] ?? '')),
        'price'        => (float)($_POST['price'] ?? 0),
        'status'       => (string)($_POST['status'] ?? 'in-stock'),
        'grade'        => (string)($_POST['grade'] ?? '4'),
        'steering'     => (string)($_POST['steering'] ?? 'RHD'),
        'note'         => trim((string)($_POST['note'] ?? '')),
        'is_published' => isset($_POST['is_published']) ? 1 : 0,
    ];

    if ($in['make'] === '')  { $errors['make'] = 'Which make is it?'; }
    if ($in['model'] === '') { $errors['model'] = 'Which model is it?'; }
    if ($in['year'] < 1970 || $in['year'] > (int)date('Y') + 2) {
        $errors['year'] = 'Enter a year between 1970 and ' . ((int)date('Y') + 2) . '.';
    }
    if ($in['price'] <= 0)   { $errors['price'] = 'Enter the price in US dollars.'; }
    if ($in['mileage'] < 0)  { $errors['mileage'] = 'Mileage cannot be negative.'; }
    if (!in_array($in['body'], $BODIES, true))          { $in['body'] = 'sedan'; }
    if (!in_array($in['fuel'], $FUELS, true))           { $in['fuel'] = 'Petrol'; }
    if (!in_array($in['transmission'], $GEARS, true))   { $in['transmission'] = 'Automatic'; }
    if (!in_array($in['drive'], $DRIVES, true))         { $in['drive'] = '2WD'; }
    if (!array_key_exists($in['status'], $STATES))      { $in['status'] = 'in-stock'; }
    if (!in_array($in['grade'], $GRADES, true))         { $in['grade'] = '4'; }
    if (!in_array($in['steering'], ['RHD', 'LHD'], true)) { $in['steering'] = 'RHD'; }

    if (!$errors) {
        if ($vehicle) {
            q('UPDATE vehicles SET make=?, model=?, year=?, body=?, fuel=?, transmission=?, engine=?,
                      mileage=?, drive=?, colour=?, price=?, status=?, grade=?, steering=?, note=?,
                      is_published=? WHERE id=?',
              [$in['make'], $in['model'], $in['year'], $in['body'], $in['fuel'], $in['transmission'],
               $in['engine'] ?: null, $in['mileage'], $in['drive'], $in['colour'] ?: null, $in['price'],
               $in['status'], $in['grade'], $in['steering'], $in['note'] ?: null, $in['is_published'],
               $vehicle['id']]);
            $vehicleId = (int)$vehicle['id'];
            $ref = $vehicle['ref'];
            log_activity('updated a vehicle', $ref . ' ' . $in['make'] . ' ' . $in['model']);
        } else {
            /* Next free reference, V-001 upwards. */
            $next = (int)q_val("SELECT COALESCE(MAX(CAST(SUBSTRING(ref, 3) AS UNSIGNED)), 0) + 1
                                  FROM vehicles WHERE ref REGEXP '^V-[0-9]+$'");
            $ref = 'V-' . str_pad((string)$next, 3, '0', STR_PAD_LEFT);
            q('INSERT INTO vehicles (ref, make, model, year, body, fuel, transmission, engine, mileage,
                                     drive, colour, price, status, grade, steering, note, is_published, created_by)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
              [$ref, $in['make'], $in['model'], $in['year'], $in['body'], $in['fuel'], $in['transmission'],
               $in['engine'] ?: null, $in['mileage'], $in['drive'], $in['colour'] ?: null, $in['price'],
               $in['status'], $in['grade'], $in['steering'], $in['note'] ?: null, $in['is_published'],
               $op['id']]);
            $vehicleId = (int)db()->lastInsertId();
            log_activity('added a vehicle', $ref . ' ' . $in['make'] . ' ' . $in['model']);
        }

        foreach (store_photos('photos', 'vehicle', $vehicleId, strtolower($ref)) as $problem) {
            flash($problem, 'bad');
        }

        flash($vehicle ? 'Vehicle updated.' : 'Vehicle ' . $ref . ' added.');
        redirect('admin/vehicle-edit.php?id=' . $vehicleId);
    }
}

$photos = $vehicle ? photos_for('vehicle', (int)$vehicle['id']) : [];

/** Current value: submitted, then stored, then a default. */
function v_val(string $field, $default = '')
{
    global $vehicle;
    if (isset($_POST[$field])) { return $_POST[$field]; }
    return $vehicle[$field] ?? $default;
}

require __DIR__ . '/_header.php';
?>

<div class="mgr-head">
  <div>
    <h2><?= $vehicle ? 'Edit ' . e($vehicle['ref']) : 'Add a vehicle' ?></h2>
    <p><?= $vehicle
          ? 'Last changed ' . e(date('j M Y, H:i', strtotime($vehicle['updated_at'])))
          : 'A reference number is given automatically when you save.' ?></p>
  </div>
  <a class="btn btn--ghost" href="<?= e(url('admin/vehicles.php')) ?>">← All vehicles</a>
</div>

<?php if ($errors): ?>
  <div class="form-status show bad" style="margin-bottom:18px">Please correct the highlighted fields.</div>
<?php endif; ?>

<form class="editor" method="post" enctype="multipart/form-data"
      action="<?= e(url('admin/vehicle-edit.php' . ($vehicle ? '?id=' . (int)$vehicle['id'] : ''))) ?>">
  <?= csrf_field() ?>
  <input type="hidden" name="action" value="save">

  <div class="field-row">
    <div class="field">
      <label for="make">Make *</label>
      <input type="text" id="make" name="make" value="<?= e(v_val('make')) ?>" placeholder="Toyota">
      <span class="err"><?= e($errors['make'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="model">Model *</label>
      <input type="text" id="model" name="model" value="<?= e(v_val('model')) ?>" placeholder="Land Cruiser Prado TX">
      <span class="err"><?= e($errors['model'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="year">Year *</label>
      <input type="number" id="year" name="year" min="1970" max="<?= (int)date('Y') + 2 ?>"
             value="<?= e(v_val('year', (int)date('Y') - 6)) ?>">
      <span class="err"><?= e($errors['year'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="price">Price in USD *</label>
      <input type="number" id="price" name="price" min="0" step="50" value="<?= e(v_val('price')) ?>">
      <span class="err"><?= e($errors['price'] ?? '') ?></span>
    </div>
  </div>

  <div class="field-row">
    <div class="field">
      <label for="body">Body type</label>
      <select id="body" name="body">
        <?php foreach (['sedan' => 'Sedan', 'hatchback' => 'Hatchback', 'suv' => 'SUV / 4WD',
                        'van' => 'Van / MPV', 'pickup' => 'Pickup', 'truck' => 'Truck'] as $k => $label): ?>
          <option value="<?= e($k) ?>"<?= v_val('body', 'suv') === $k ? ' selected' : '' ?>><?= e($label) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field">
      <label for="fuel">Fuel</label>
      <select id="fuel" name="fuel">
        <?php foreach ($FUELS as $f): ?>
          <option<?= v_val('fuel', 'Petrol') === $f ? ' selected' : '' ?>><?= e($f) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field">
      <label for="transmission">Gearbox</label>
      <select id="transmission" name="transmission">
        <?php foreach ($GEARS as $g): ?>
          <option<?= v_val('transmission', 'Automatic') === $g ? ' selected' : '' ?>><?= e($g) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field">
      <label for="status">Availability</label>
      <select id="status" name="status">
        <?php foreach ($STATES as $k => $label): ?>
          <option value="<?= e($k) ?>"<?= v_val('status', 'in-stock') === $k ? ' selected' : '' ?>><?= e($label) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
  </div>

  <div class="field-row">
    <div class="field">
      <label for="engine">Engine size</label>
      <input type="text" id="engine" name="engine" value="<?= e(v_val('engine')) ?>" placeholder="2755 cc">
      <span class="err"></span>
    </div>
    <div class="field">
      <label for="mileage">Mileage in km</label>
      <input type="number" id="mileage" name="mileage" min="0" value="<?= e(v_val('mileage', 0)) ?>">
      <span class="err"><?= e($errors['mileage'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="drive">Drive</label>
      <select id="drive" name="drive">
        <?php foreach ($DRIVES as $d): ?>
          <option<?= v_val('drive', '2WD') === $d ? ' selected' : '' ?>><?= e($d) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field">
      <label for="colour">Colour</label>
      <input type="text" id="colour" name="colour" value="<?= e(v_val('colour')) ?>" placeholder="Pearl White">
      <span class="err"></span>
    </div>
  </div>

  <div class="field-row">
    <div class="field">
      <label for="grade">Auction grade</label>
      <select id="grade" name="grade">
        <?php foreach ($GRADES as $g): ?>
          <option<?= (string)v_val('grade', '4') === $g ? ' selected' : '' ?>><?= e($g) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field">
      <label for="steering">Steering</label>
      <select id="steering" name="steering">
        <?php foreach (['RHD', 'LHD'] as $s): ?>
          <option<?= v_val('steering', 'RHD') === $s ? ' selected' : '' ?>><?= e($s) ?></option>
        <?php endforeach; ?>
      </select><span class="err"></span>
    </div>
    <div class="field" style="grid-column:span 2">
      <label for="note">Short note shown on the card</label>
      <input type="text" id="note" name="note" maxlength="200" value="<?= e(v_val('note')) ?>"
             placeholder="Sunroof, leather trim, reverse camera.">
      <span class="err"></span>
    </div>
  </div>

  <label class="switch">
    <input type="checkbox" name="is_published" value="1" <?= (int)v_val('is_published', 1) ? 'checked' : '' ?>>
    <span>Show this vehicle on the website</span>
  </label>

  <div style="margin-top:18px">
    <label style="font-size:.82rem;font-weight:700;display:block;margin-bottom:6px">Add photographs</label>
    <div class="drop" id="v-drop" tabindex="0" role="button">
      <b>Choose photos</b>
      JPEG, PNG or WebP, up to <?= (int)(UPLOAD_MAX_BYTES / 1048576) ?> MB each. They are resized on
      upload. The first photo is the one buyers see on the card.
    </div>
    <input type="file" id="v-files" name="photos[]" accept="image/*" multiple hidden>
    <div class="thumbs" id="v-preview"></div>
  </div>

  <div class="editor-foot">
    <button class="btn btn--primary" type="submit"><?= $vehicle ? 'Save changes' : 'Create vehicle' ?></button>
    <a class="btn btn--ghost" href="<?= e(url('admin/vehicles.php')) ?>">Cancel</a>
  </div>
</form>

<?php if ($vehicle): ?>
  <div class="editor">
    <h3>Photographs <span class="card-sub">(<?= count($photos) ?> of <?= PHOTOS_PER_ITEM ?>)</span></h3>
    <?php if (!$photos): ?>
      <p class="card-sub">None yet. Until you add one, the website shows a drawing of a
         <?= e($vehicle['body']) ?>.</p>
    <?php else: ?>
      <div class="thumbs">
        <?php foreach ($photos as $i => $ph): ?>
          <div class="thumb-card">
            <?php if ($i === 0): ?><span class="cover-flag">Cover</span><?php endif; ?>
            <img src="<?= e(url('assets/uploads/' . rawurlencode($ph['filename']))) ?>" alt="">
            <div class="thumb-tools">
              <?php if ($i > 0): ?>
                <form method="post" action="<?= e(url('admin/vehicle-edit.php?id=' . (int)$vehicle['id'])) ?>">
                  <?= csrf_field() ?>
                  <input type="hidden" name="action" value="photo-cover">
                  <input type="hidden" name="photo_id" value="<?= (int)$ph['id'] ?>">
                  <button type="submit">Cover</button>
                </form>
              <?php else: ?>
                <button type="button" disabled>Cover</button>
              <?php endif; ?>
              <form method="post" action="<?= e(url('admin/vehicle-edit.php?id=' . (int)$vehicle['id'])) ?>"
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
    <h3>Delete this vehicle</h3>
    <p class="card-sub">Removes the record and its photographs for good.</p>
    <form method="post" action="<?= e(url('admin/vehicle-edit.php?id=' . (int)$vehicle['id'])) ?>"
          onsubmit="return confirm('Delete <?= e(addslashes($vehicle['make'] . ' ' . $vehicle['model'])) ?> permanently?')">
      <?= csrf_field() ?>
      <input type="hidden" name="action" value="delete">
      <button class="btn btn--ghost btn--sm" type="submit">Delete vehicle</button>
    </form>
  </div>
<?php endif; ?>

<?php require __DIR__ . '/_footer.php'; ?>
