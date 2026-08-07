<?php
require_once __DIR__ . '/includes/guard.php';

if (is_post()) {
    switch (post('action')) {
        case 'risk-new':
            insert('INSERT INTO risks (title, category, owner, likelihood, impact, mitigation, status) VALUES (?,?,?,?,?,?,?)',
                [post('title'), post('category', 'Operational'), post('owner'),
                 max(1, min(5, (int) post('likelihood', 3))), max(1, min(5, (int) post('impact', 3))),
                 post('mitigation'), 'open']);
            redirect('risk.php', 'Risk logged.');
        case 'risk-close':
            q("UPDATE risks SET status = 'mitigated' WHERE id = ?", [(int) post('id')]);
            redirect('risk.php', 'Risk mitigated.');
        case 'risk-del':
            q('DELETE FROM risks WHERE id = ?', [(int) post('id')]);
            redirect('risk.php', 'Risk removed.');
    }
    redirect('risk.php');
}

$pageTitle = 'Risk Register';
require __DIR__ . '/includes/header.php';
$risks = rows('SELECT * FROM risks ORDER BY likelihood * impact DESC, id DESC');
$scoreCls = fn($s) => $s >= 15 ? 'b-red' : ($s >= 8 ? 'b-amber' : 'b-green');
?>
<div class="view-head">
  <div><h1>Risk Register</h1>
    <div class="sub">Likelihood × impact scoring (1–5 each). Score ≥ 15 is severe, ≥ 8 elevated.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('risk-form').showModal()">+ Risk</button></div>
</div>

<div class="card">
  <?php if ($risks): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Risk</th><th>Category</th><th class="num">L</th><th class="num">I</th><th class="num">Score</th><th>Mitigation</th><th>Owner</th><th>Status</th><th></th></tr>
      <?php foreach ($risks as $r): $s = (int) $r['likelihood'] * (int) $r['impact']; ?>
        <tr><td><strong><?= e($r['title']) ?></strong></td><td><?= e($r['category']) ?></td>
          <td class="num"><?= (int) $r['likelihood'] ?></td><td class="num"><?= (int) $r['impact'] ?></td>
          <td class="num"><span class="badge <?= $scoreCls($s) ?> risk-score"><?= $s ?></span></td>
          <td><?= e($r['mitigation'] ?: '—') ?></td><td><?= e($r['owner'] ?: '—') ?></td>
          <td><?= $r['status'] === 'open' ? badge('open', 'b-amber') : badge('mitigated', 'b-green') ?></td>
          <td style="white-space:nowrap">
            <?php if ($r['status'] === 'open'): ?>
            <form method="post" style="display:inline"><input type="hidden" name="action" value="risk-close">
              <input type="hidden" name="id" value="<?= $r['id'] ?>"><button class="btn btn-icon" title="mark mitigated">✓</button></form>
            <?php endif; ?>
            <form method="post" style="display:inline" data-confirm="Delete this risk?"><input type="hidden" name="action" value="risk-del">
              <input type="hidden" name="id" value="<?= $r['id'] ?>"><button class="btn btn-icon">✕</button></form>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No risks logged. Think market, credit, operational, compliance, key-person, FX…</div><?php endif; ?>
</div>

<dialog id="risk-form" class="dlg"><form method="post">
  <h2>New Risk</h2><input type="hidden" name="action" value="risk-new">
  <label>Risk title *</label><input name="title" required>
  <div class="form-row">
    <div><label>Category</label><select name="category">
      <?php foreach (['Strategic','Financial','Credit','Operational','Compliance','Market','Reputational','Other'] as $c) echo "<option>$c</option>"; ?>
    </select></div>
    <div><label>Owner</label><input name="owner"></div>
  </div>
  <div class="form-row">
    <div><label>Likelihood (1–5)</label><input name="likelihood" type="number" min="1" max="5" value="3" required></div>
    <div><label>Impact (1–5)</label><input name="impact" type="number" min="1" max="5" value="3" required></div>
  </div>
  <label>Mitigation plan</label><textarea name="mitigation"></textarea>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<?php require __DIR__ . '/includes/footer.php'; ?>
