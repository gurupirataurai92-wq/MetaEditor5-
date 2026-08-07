<?php
require_once __DIR__ . '/includes/guard.php';

$STAGES = ['Observe', 'Orient', 'Decide', 'Act'];
$COLS   = ['observe', 'orient', 'decide', 'act'];

function ooda_advance(array $o): void
{
    global $COLS;
    if ((int) $o['stage'] < 3) {
        q('UPDATE ooda SET stage = stage + 1 WHERE id = ?', [$o['id']]);
        return;
    }
    // full cycle complete: archive, restart at Observe
    insert('INSERT INTO ooda_log (ooda_id, cycle, logged_at, observe, orient, decide, act) VALUES (?,?,?,?,?,?,?)',
        [$o['id'], (int) $o['cycles'] + 1, today(), $o['observe'], $o['orient'], $o['decide'], $o['act']]);
    q("UPDATE ooda SET cycles = cycles + 1, stage = 0, observe='', orient='', decide='', act='' WHERE id = ?", [$o['id']]);
}

if (is_post()) {
    switch (post('action')) {
        case 'ooda-new':
            insert("INSERT INTO ooda (title, objective, status, stage, cycles, observe, orient, decide, act)
                    VALUES (?,?,'active',0,0,'','','','')", [post('title'), post('objective')]);
            redirect('ooda.php', 'Loop started — begin with Observe.');
        case 'ooda-note':
            $o = one('SELECT * FROM ooda WHERE id = ?', [(int) post('id')]);
            if ($o) {
                $col = $COLS[(int) $o['stage']];
                q("UPDATE ooda SET $col = ? WHERE id = ?", [post('note'), $o['id']]);
                $o[$col] = post('note');
                ooda_advance($o);
            }
            redirect('ooda.php');
        case 'ooda-skip':
            $o = one('SELECT * FROM ooda WHERE id = ?', [(int) post('id')]);
            if ($o) ooda_advance($o);
            redirect('ooda.php');
        case 'ooda-done':
            q("UPDATE ooda SET status = 'done' WHERE id = ?", [(int) post('id')]);
            redirect('ooda.php', 'Loop completed.');
        case 'ooda-del':
            q('DELETE FROM ooda WHERE id = ?', [(int) post('id')]);
            redirect('ooda.php', 'Loop removed.');
    }
    redirect('ooda.php');
}

$pageTitle = 'OODA Engine';
require __DIR__ . '/includes/header.php';
$loops = rows("SELECT * FROM ooda ORDER BY (status = 'active') DESC, id DESC");
$placeholders = [
    'observe' => 'Gather raw facts, data, signals.',
    'orient'  => 'Analyze context, biases, models.',
    'decide'  => 'Choose the course of action.',
    'act'     => 'Execute and measure the result.',
];
?>
<div class="view-head">
  <div><h1>OODA Decision Engine</h1>
    <div class="sub">Observe → Orient → Decide → Act. Cycle faster than the problem changes.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('ooda-form').showModal()">+ New Loop</button></div>
</div>

<?php if ($loops): foreach ($loops as $o):
    $logCount = (int) scalar('SELECT COUNT(*) FROM ooda_log WHERE ooda_id = ?', [(int) $o['id']]); ?>
  <div class="ooda-loop">
    <div class="ooda-top">
      <div>
        <div class="ooda-title"><?= e($o['title']) ?>
          <?= $o['status'] === 'done' ? badge('Completed', 'b-green') : badge('Cycle ' . ((int) $o['cycles'] + 1), 'b-gold') ?>
        </div>
        <div class="muted" style="font-size:12px"><?= e($o['objective']) ?></div>
      </div>
      <form method="post" data-confirm="Delete this loop?"><input type="hidden" name="action" value="ooda-del">
        <input type="hidden" name="id" value="<?= $o['id'] ?>"><button class="btn btn-icon">✕</button></form>
    </div>
    <div class="ooda-stages">
      <?php foreach ($STAGES as $i => $s): $col = $COLS[$i];
        $cls = $o['status'] === 'done' ? 'done' : ((int) $o['stage'] > $i ? 'done' : ((int) $o['stage'] === $i ? 'current' : '')); ?>
        <div class="ooda-stage <?= $cls ?>">
          <h4><?= ($i + 1) . '. ' . strtoupper($s) ?></h4>
          <p><?= $o[$col] !== '' ? e($o[$col]) : '<span class="placeholder">' . e($placeholders[$col]) . '</span>' ?></p>
        </div>
      <?php endforeach; ?>
    </div>
    <?php if ($o['status'] === 'active'): ?>
      <div class="ooda-foot">
        <button class="btn btn-primary btn-sm"
          onclick='oodaNote(<?= json_encode(['id' => $o['id'], 'title' => $o['title'], 'stage' => $STAGES[(int) $o['stage']], 'note' => $o[$COLS[(int) $o['stage']]]], JSON_HEX_APOS | JSON_HEX_QUOT) ?>)'>✎ <?= e($STAGES[(int) $o['stage']]) ?>: add notes &amp; advance</button>
        <form method="post" style="display:inline"><input type="hidden" name="action" value="ooda-skip">
          <input type="hidden" name="id" value="<?= $o['id'] ?>"><button class="btn btn-sm">Advance without notes</button></form>
        <form method="post" style="display:inline"><input type="hidden" name="action" value="ooda-done">
          <input type="hidden" name="id" value="<?= $o['id'] ?>"><button class="btn btn-sm btn-ghost">Mark loop complete</button></form>
        <span class="cycle-chip"><?= $logCount ?> past cycle note<?= $logCount === 1 ? '' : 's' ?> archived</span>
      </div>
    <?php endif; ?>
  </div>
<?php endforeach; else: ?>
  <div class="card"><div class="empty">No loops yet. Create one for any decision: pricing a proposal, restructuring a client, entering a market.</div></div>
<?php endif; ?>

<dialog id="ooda-form" class="dlg"><form method="post">
  <h2>New OODA Loop</h2><input type="hidden" name="action" value="ooda-new">
  <label>Decision / mission title *</label><input name="title" placeholder="e.g. Should client X expand to region Y?" required>
  <label>Objective</label><textarea name="objective" placeholder="What outcome defines success?"></textarea>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Start loop</button></div>
</form></dialog>

<dialog id="note-dlg" class="dlg"><form method="post">
  <h2 id="note-title">Notes</h2><input type="hidden" name="action" value="ooda-note"><input type="hidden" name="id" id="note-id">
  <label id="note-label">Notes</label><textarea name="note" id="note-text" rows="5"></textarea>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save &amp; Advance</button></div>
</form></dialog>

<script>
function oodaNote(o) {
  document.getElementById('note-title').textContent = o.stage + ' — ' + o.title;
  document.getElementById('note-label').textContent = o.stage + ' notes';
  document.getElementById('note-id').value = o.id;
  document.getElementById('note-text').value = o.note || '';
  document.getElementById('note-dlg').showModal();
}
</script>

<?php require __DIR__ . '/includes/footer.php'; ?>
