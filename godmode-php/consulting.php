<?php
require_once __DIR__ . '/includes/guard.php';

if (is_post()) {
    switch (post('action')) {
        case 'client-new':
            if (post('name') !== '') {
                insert('INSERT INTO clients (name, industry, contact, notes, swot_s, swot_w, swot_o, swot_t, created_at)
                        VALUES (?,?,?,?,?,?,?,?,?)',
                    [post('name'), post('industry'), post('contact'), post('notes'), '', '', '', '', today()]);
            }
            redirect('consulting.php', 'Client added.');
        case 'client-swot':
            $clean = fn($k) => implode("\n", array_filter(array_map('trim', explode("\n", post($k)))));
            q('UPDATE clients SET swot_s=?, swot_w=?, swot_o=?, swot_t=? WHERE id=?',
                [$clean('s'), $clean('w'), $clean('o'), $clean('t'), (int) post('id')]);
            redirect('consulting.php', 'SWOT updated.');
        case 'client-del':
            q('DELETE FROM clients WHERE id = ?', [(int) post('id')]);
            redirect('consulting.php', 'Client removed.');
        case 'eng-new':
            insert('INSERT INTO engagements (client_id, service, fee, status, start_date) VALUES (?,?,?,?,?)',
                [(int) post('client_id'), post('service', 'Consulting'), (float) post('fee'), post('status', 'active'), today()]);
            redirect('consulting.php', 'Engagement added.');
        case 'eng-next':
            $st = scalar('SELECT status FROM engagements WHERE id = ?', [(int) post('id')]);
            $next = $st === 'proposal' ? 'active' : 'completed';
            q('UPDATE engagements SET status = ? WHERE id = ?', [$next, (int) post('id')]);
            redirect('consulting.php');
        case 'eng-del':
            q('DELETE FROM engagements WHERE id = ?', [(int) post('id')]);
            redirect('consulting.php', 'Engagement removed.');
    }
    redirect('consulting.php');
}

$pageTitle = 'Consulting / CRM';
require __DIR__ . '/includes/header.php';
$clients = rows('SELECT * FROM clients ORDER BY name');
$engs = rows('SELECT * FROM engagements ORDER BY id DESC');
?>
<div class="view-head">
  <div><h1>Consulting &amp; CRM</h1>
    <div class="sub">Clients, engagements, pipeline and strategy (SWOT) per client.</div></div>
  <div class="head-actions">
    <button class="btn" onclick="document.getElementById('eng-form').showModal()" <?= $clients ? '' : 'disabled' ?>>+ Engagement</button>
    <button class="btn btn-primary" onclick="document.getElementById('client-form').showModal()">+ Client</button>
  </div>
</div>

<div class="grid grid-2">
  <div class="card">
    <h3>Clients (<?= count($clients) ?>)</h3>
    <?php if ($clients): ?>
      <div class="tbl-wrap"><table>
        <tr><th>Name</th><th>Industry</th><th>Contact</th><th></th></tr>
        <?php foreach ($clients as $c): ?>
          <tr id="c<?= $c['id'] ?>">
            <td><strong><?= e($c['name']) ?></strong></td>
            <td><?= e($c['industry'] ?: '—') ?></td>
            <td><?= e($c['contact'] ?: '—') ?></td>
            <td style="white-space:nowrap">
              <a class="btn btn-icon" href="client.php?id=<?= $c['id'] ?>" title="360° health report">360</a>
              <button class="btn btn-icon" title="SWOT"
                onclick='openSwot(<?= json_encode([
                  "id" => $c["id"], "name" => $c["name"],
                  "s" => $c["swot_s"], "w" => $c["swot_w"], "o" => $c["swot_o"], "t" => $c["swot_t"]
                ], JSON_HEX_APOS | JSON_HEX_QUOT) ?>)'>S/W</button>
              <form method="post" style="display:inline" data-confirm="Delete this client and all its records?">
                <input type="hidden" name="action" value="client-del"><input type="hidden" name="id" value="<?= $c['id'] ?>">
                <button class="btn btn-icon">✕</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
      </table></div>
    <?php else: ?><div class="empty">No clients yet.</div><?php endif; ?>
  </div>

  <div class="card">
    <h3>Engagements (<?= count($engs) ?>)</h3>
    <?php if ($engs): ?>
      <div class="tbl-wrap"><table>
        <tr><th>Client</th><th>Service</th><th class="num">Fee</th><th>Status</th><th></th></tr>
        <?php foreach ($engs as $en): ?>
          <tr>
            <td><?= e(client_name((int) $en['client_id'])) ?></td>
            <td><?= e($en['service']) ?></td>
            <td class="num"><?= money($en['fee']) ?></td>
            <td><?php echo $en['status'] === 'active' ? badge('active', 'b-green')
                        : ($en['status'] === 'proposal' ? badge('proposal', 'b-blue') : badge('completed', 'b-grey')); ?></td>
            <td style="white-space:nowrap">
              <?php if ($en['status'] !== 'completed'): ?>
              <form method="post" style="display:inline">
                <input type="hidden" name="action" value="eng-next"><input type="hidden" name="id" value="<?= $en['id'] ?>">
                <button class="btn btn-icon" title="advance status">→</button>
              </form>
              <?php endif; ?>
              <form method="post" style="display:inline" data-confirm="Delete this engagement?">
                <input type="hidden" name="action" value="eng-del"><input type="hidden" name="id" value="<?= $en['id'] ?>">
                <button class="btn btn-icon">✕</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
      </table></div>
    <?php else: ?><div class="empty">No engagements yet.</div><?php endif; ?>
  </div>
</div>

<?php foreach ($clients as $c):
    $has = trim($c['swot_s'] . $c['swot_w'] . $c['swot_o'] . $c['swot_t']) !== '';
    if (!$has) continue;
    $list = fn($v) => array_filter(array_map('trim', explode("\n", (string) $v))); ?>
  <div class="card mt">
    <h3>SWOT — <?= e($c['name']) ?></h3>
    <div class="swot-grid">
      <?php foreach ([['s','Strengths'],['w','Weaknesses'],['o','Opportunities'],['t','Threats']] as $q):
        $items = $list($c['swot_' . $q[0]]); ?>
        <div class="swot-cell swot-<?= $q[0] ?>"><h4><?= strtoupper($q[1]) ?></h4>
          <ul><?php if ($items) foreach ($items as $x) echo '<li>• ' . e($x) . '</li>'; else echo '<li class="muted">—</li>'; ?></ul>
        </div>
      <?php endforeach; ?>
    </div>
  </div>
<?php endforeach; ?>

<!-- modals -->
<dialog id="client-form" class="dlg"><form method="post">
  <h2>New Client</h2>
  <input type="hidden" name="action" value="client-new">
  <label>Client name *</label><input name="name" required>
  <div class="form-row">
    <div><label>Industry</label><input name="industry"></div>
    <div><label>Contact</label><input name="contact" placeholder="phone / email"></div>
  </div>
  <label>Notes</label><textarea name="notes"></textarea>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<dialog id="eng-form" class="dlg"><form method="post">
  <h2>New Engagement</h2>
  <input type="hidden" name="action" value="eng-new">
  <label>Client *</label><select name="client_id" required>
    <?php foreach ($clients as $c) echo '<option value="' . $c['id'] . '">' . e($c['name']) . '</option>'; ?>
  </select>
  <div class="form-row">
    <div><label>Service</label><select name="service">
      <?php foreach (['Consulting','Audit','Accounting','Microfinance','Tax','HR','Other'] as $s) echo "<option>$s</option>"; ?>
    </select></div>
    <div><label>Fee</label><input name="fee" type="number" step="any" value="0"></div>
  </div>
  <label>Status</label><select name="status"><option value="proposal">Proposal</option><option value="active" selected>Active</option></select>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<dialog id="swot-form" class="dlg"><form method="post">
  <h2 id="swot-title">SWOT</h2>
  <input type="hidden" name="action" value="client-swot"><input type="hidden" name="id" id="swot-id">
  <div class="muted" style="font-size:12px;margin-bottom:4px">One item per line.</div>
  <div class="form-row">
    <div><label>Strengths</label><textarea name="s" id="swot-s"></textarea></div>
    <div><label>Weaknesses</label><textarea name="w" id="swot-w"></textarea></div>
    <div><label>Opportunities</label><textarea name="o" id="swot-o"></textarea></div>
    <div><label>Threats</label><textarea name="t" id="swot-t"></textarea></div>
  </div>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<script>
function openSwot(c) {
  document.getElementById('swot-title').textContent = 'SWOT — ' + c.name;
  document.getElementById('swot-id').value = c.id;
  document.getElementById('swot-s').value = c.s || '';
  document.getElementById('swot-w').value = c.w || '';
  document.getElementById('swot-o').value = c.o || '';
  document.getElementById('swot-t').value = c.t || '';
  document.getElementById('swot-form').showModal();
}
</script>

<?php require __DIR__ . '/includes/footer.php'; ?>
