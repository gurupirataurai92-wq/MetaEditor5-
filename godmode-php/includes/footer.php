  </main>
</div>

<div class="cmdk-backdrop" id="cmdk" hidden>
  <div class="cmdk">
    <input id="cmdk-input" placeholder="Search clients, invoices, loans, risks… or jump to a page" autocomplete="off">
    <div class="cmdk-results" id="cmdk-results"></div>
  </div>
</div>
<div class="chart-tip" id="chart-tip" hidden></div>

<?php
/* Build the command-palette search index server-side. */
$cmdIndex = [];
$pages = [
    ['Dashboard', 'index.php'], ['OODA Engine', 'ooda.php'], ['Consulting / CRM', 'consulting.php'],
    ['Auditing', 'auditing.php'], ['Accounting', 'accounting.php'], ['Invoicing', 'invoicing.php'],
    ['Payments', 'payments.php'], ['Inventory', 'inventory.php'],
    ['Microfinance', 'microfinance.php'], ['Tax & Compliance', 'tax.php'], ['HR & Payroll', 'hr.php'],
    ['Risk Register', 'risk.php'], ['Financial Analysis', 'analysis.php'],
];
foreach ($pages as $p) { $cmdIndex[] = ['tag' => 'go to', 'label' => $p[0], 'sub' => '', 'href' => $p[1]]; }
foreach (rows('SELECT id, name, industry FROM clients ORDER BY name') as $c) {
    $cmdIndex[] = ['tag' => 'client', 'label' => $c['name'], 'sub' => $c['industry'], 'href' => 'consulting.php#c' . $c['id']];
}
foreach (rows('SELECT id, number, client_id FROM invoices ORDER BY id DESC') as $i) {
    $cmdIndex[] = ['tag' => 'invoice', 'label' => $i['number'] . ' · ' . client_name((int) $i['client_id']),
                   'sub' => money(invoice_total((int) $i['id'])), 'href' => 'invoice.php?id=' . $i['id']];
}
foreach (rows('SELECT id, borrower FROM loans') as $l) {
    $cmdIndex[] = ['tag' => 'loan', 'label' => $l['borrower'], 'sub' => '', 'href' => 'microfinance.php'];
}
foreach (rows('SELECT id, name, quantity, unit FROM inventory_items ORDER BY name') as $it) {
    $cmdIndex[] = ['tag' => 'stock', 'label' => $it['name'], 'sub' => fnum($it['quantity']) . ' ' . $it['unit'], 'href' => 'inventory.php'];
}
foreach (rows('SELECT id, payee, amount, status FROM payments ORDER BY id DESC') as $p2) {
    $cmdIndex[] = ['tag' => 'payment', 'label' => $p2['payee'], 'sub' => money($p2['amount']) . ' · ' . $p2['status'], 'href' => 'payments.php'];
}
foreach (rows('SELECT id, title, severity FROM findings') as $f) {
    $cmdIndex[] = ['tag' => 'finding', 'label' => $f['title'], 'sub' => $f['severity'], 'href' => 'auditing.php'];
}
foreach (rows('SELECT id, title, likelihood, impact FROM risks') as $r) {
    $cmdIndex[] = ['tag' => 'risk', 'label' => $r['title'], 'sub' => 'score ' . ((int) $r['likelihood'] * (int) $r['impact']), 'href' => 'risk.php'];
}
foreach (rows('SELECT id, name, due_date FROM obligations') as $o) {
    $cmdIndex[] = ['tag' => 'deadline', 'label' => $o['name'], 'sub' => 'due ' . $o['due_date'], 'href' => 'tax.php'];
}
foreach (rows('SELECT id, title, status, stage FROM ooda') as $o) {
    $stages = ['Observe', 'Orient', 'Decide', 'Act'];
    $cmdIndex[] = ['tag' => 'ooda', 'label' => $o['title'],
                   'sub' => $o['status'] === 'active' ? 'stage: ' . $stages[(int) $o['stage']] : 'done', 'href' => 'ooda.php'];
}
?>
<script>
window.CMD_INDEX = <?= json_encode($cmdIndex, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
</script>
<script src="assets/app.js"></script>
</body>
</html>
