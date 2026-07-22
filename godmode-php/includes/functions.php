<?php
/* ============================================================
   Shared helpers: DB access, formatting, and all business
   computations (accounting, microfinance, invoicing, health).
   ============================================================ */

require_once __DIR__ . '/../config/db.php';

/* ---------- query helpers ---------- */
function q(string $sql, array $params = []): PDOStatement
{
    $st = db()->prepare($sql);
    $st->execute($params);
    return $st;
}
function rows(string $sql, array $params = []): array { return q($sql, $params)->fetchAll(); }
function one(string $sql, array $params = []): ?array { $r = q($sql, $params)->fetch(); return $r ?: null; }
function scalar(string $sql, array $params = [])       { return q($sql, $params)->fetchColumn(); }
function insert(string $sql, array $params = []): int  { q($sql, $params); return (int) db()->lastInsertId(); }

/* ---------- request helpers ---------- */
function post(string $k, $default = '') { return isset($_POST[$k]) ? trim((string) $_POST[$k]) : $default; }
function getp(string $k, $default = '') { return isset($_GET[$k]) ? trim((string) $_GET[$k]) : $default; }
function is_post(): bool { return $_SERVER['REQUEST_METHOD'] === 'POST'; }

/* Post-Redirect-Get: redirect to $page with a flash message. */
function redirect(string $page, string $flash = ''): void
{
    if ($flash !== '') {
        $sep = strpos($page, '?') === false ? '?' : '&';
        $page .= $sep . 'msg=' . rawurlencode($flash);
    }
    header('Location: ' . $page);
    exit;
}

/* ---------- formatting ---------- */
function e($s): string { return htmlspecialchars((string) ($s ?? ''), ENT_QUOTES, 'UTF-8'); }

function currency_code(): string
{
    static $c = null;
    if ($c === null) { $c = (string) (scalar('SELECT currency FROM settings WHERE id = 1') ?: 'USD'); }
    return $c;
}

/* Minimal symbol map so amounts read naturally without the intl extension. */
function money($n): string
{
    $sym = [
        'USD' => '$', 'EUR' => '€', 'GBP' => '£', 'INR' => '₹', 'BRL' => 'R$', 'MXN' => 'MX$',
        'KES' => 'KSh ', 'NGN' => '₦', 'ZAR' => 'R', 'GHS' => 'GH₵', 'UGX' => 'USh ',
        'TZS' => 'TSh ', 'RWF' => 'FRw ', 'ZMW' => 'K', 'PHP' => '₱', 'IDR' => 'Rp ',
    ];
    $code = currency_code();
    $s = $sym[$code] ?? ($code . ' ');
    $v = (float) $n;
    $neg = $v < 0 ? '-' : '';
    return $neg . $s . number_format(abs($v), 2);
}
function fnum($n, int $dp = 2): string { return number_format((float) $n, $dp); }
function today(): string { return date('Y-m-d'); }
function days_until(string $d): int
{
    $a = new DateTime(today()); $b = new DateTime($d);
    return (int) $a->diff($b)->format('%r%a');
}

/* ---------- navigation ---------- */
function nav_active(string $file): string
{
    return basename($_SERVER['PHP_SELF']) === $file ? 'active' : '';
}

/* ============================================================
   ACCOUNTING
   ============================================================ */
function account_balances(): array
{
    $bal = [];
    foreach (rows('SELECT id FROM accounts') as $a) { $bal[(int) $a['id']] = 0.0; }
    foreach (rows('SELECT debit_account, credit_account, amount FROM journal') as $j) {
        $bal[(int) $j['debit_account']]  = ($bal[(int) $j['debit_account']]  ?? 0) + (float) $j['amount'];
        $bal[(int) $j['credit_account']] = ($bal[(int) $j['credit_account']] ?? 0) - (float) $j['amount'];
    }
    return $bal;
}
function normal_balance(string $type, float $raw): float
{
    return ($type === 'Asset' || $type === 'Expense') ? $raw : -$raw;
}
function financials(): array
{
    $bal = account_balances();
    $accts = rows('SELECT * FROM accounts ORDER BY id');
    $by = fn($t) => array_values(array_filter(array_map(function ($a) use ($bal, $t) {
        if ($a['type'] !== $t) return null;
        return ['acc' => $a, 'amt' => normal_balance($a['type'], $bal[(int) $a['id']] ?? 0)];
    }, $accts)));
    $sum = fn($rs) => array_sum(array_column($rs, 'amt'));
    $income = $by('Income'); $expense = $by('Expense');
    $assets = $by('Asset'); $liabs = $by('Liability'); $equity = $by('Equity');
    $net = $sum($income) - $sum($expense);
    return [
        'income' => $income, 'expense' => $expense, 'assets' => $assets,
        'liabs' => $liabs, 'equity' => $equity, 'netIncome' => $net,
        'totalAssets' => $sum($assets), 'totalLiabs' => $sum($liabs), 'totalEquity' => $sum($equity),
    ];
}

/* ============================================================
   MICROFINANCE
   ============================================================ */
function loan_schedule(array $l): array
{
    $P = (float) $l['principal']; $months = (int) $l['months']; $annual = (float) $l['rate'] / 100;
    $rows = [];
    if ($P <= 0 || $months <= 0) return ['rows' => [], 'totalInterest' => 0, 'totalDue' => $P, 'payment' => 0];

    if ($l['method'] === 'flat') {
        $totalInterest = $P * $annual * ($months / 12);
        $payment = ($P + $totalInterest) / $months;
        $balance = $P + $totalInterest;
        for ($m = 1; $m <= $months; $m++) {
            $balance -= $payment;
            $rows[] = ['m' => $m, 'payment' => $payment, 'principal' => $P / $months,
                       'interest' => $totalInterest / $months, 'balance' => max(0, $balance)];
        }
        return ['rows' => $rows, 'totalInterest' => $totalInterest, 'totalDue' => $P + $totalInterest, 'payment' => $payment];
    }
    $r = $annual / 12;
    $payment = $r == 0 ? $P / $months : $P * $r / (1 - pow(1 + $r, -$months));
    $bal = $P; $totalInterest = 0;
    for ($m = 1; $m <= $months; $m++) {
        $interest = $bal * $r; $princ = $payment - $interest;
        $bal = max(0, $bal - $princ); $totalInterest += $interest;
        $rows[] = ['m' => $m, 'payment' => $payment, 'principal' => $princ, 'interest' => $interest, 'balance' => $bal];
    }
    return ['rows' => $rows, 'totalInterest' => $totalInterest, 'totalDue' => $P + $totalInterest, 'payment' => $payment];
}
function loan_outstanding(array $l): float
{
    $s = loan_schedule($l);
    return max(0, $s['totalDue'] - (float) $l['repaid']);
}
function portfolio_stats(): array
{
    $active = rows("SELECT * FROM loans WHERE status = 'active'");
    $outstanding = 0; $par30 = 0;
    foreach ($active as $l) {
        $o = loan_outstanding($l);
        $outstanding += $o;
        if ((int) $l['days_overdue'] > 30) $par30 += $o;
    }
    return ['count' => count($active), 'outstanding' => $outstanding, 'par30' => $par30,
            'parPct' => $outstanding ? $par30 / $outstanding * 100 : 0];
}

/* ============================================================
   INVOICING
   ============================================================ */
function invoice_items(int $id): array { return rows('SELECT * FROM invoice_items WHERE invoice_id = ?', [$id]); }
function invoice_total(int $id): float
{
    return (float) scalar('SELECT COALESCE(SUM(qty * price), 0) FROM invoice_items WHERE invoice_id = ?', [$id]);
}
function invoice_overdue(array $inv): bool
{
    return $inv['status'] === 'sent' && $inv['due_date'] < today();
}
function invoice_stats(): array
{
    $open = 0; $overdue = 0; $overdueCount = 0; $collected = 0;
    foreach (rows('SELECT * FROM invoices') as $i) {
        $t = invoice_total((int) $i['id']);
        if ($i['status'] === 'paid') { $collected += $t; continue; }
        $open += $t;
        if (invoice_overdue($i)) { $overdue += $t; $overdueCount++; }
    }
    return ['outstanding' => $open, 'overdue' => $overdue, 'overdueCount' => $overdueCount, 'collected' => $collected];
}
function next_invoice_number(): string
{
    return 'INV-' . str_pad((string) ((int) scalar('SELECT COUNT(*) FROM invoices') + 1), 4, '0', STR_PAD_LEFT);
}

/* ============================================================
   CASH FLOW SERIES (monthly income vs expense from the journal)
   ============================================================ */
function cashflow_series(int $monthsBack): array
{
    $type = [];
    foreach (rows('SELECT id, type FROM accounts') as $a) { $type[(int) $a['id']] = $a['type']; }
    $keys = [];
    for ($i = $monthsBack - 1; $i >= 0; $i--) { $keys[] = date('Y-m', strtotime("first day of -$i month")); }
    $inc = array_fill_keys($keys, 0.0); $exp = array_fill_keys($keys, 0.0);
    foreach (rows('SELECT entry_date, amount, debit_account, credit_account FROM journal') as $j) {
        $k = substr((string) $j['entry_date'], 0, 7);
        if (!isset($inc[$k])) continue;
        $amt = (float) $j['amount'];
        $dt = $type[(int) $j['debit_account']] ?? ''; $ct = $type[(int) $j['credit_account']] ?? '';
        if ($ct === 'Income')  $inc[$k] += $amt;
        if ($dt === 'Income')  $inc[$k] -= $amt;
        if ($dt === 'Expense') $exp[$k] += $amt;
        if ($ct === 'Expense') $exp[$k] -= $amt;
    }
    $out = [];
    foreach ($keys as $k) {
        $out[] = ['key' => $k, 'label' => date('M', strtotime($k . '-01')),
                  'income' => $inc[$k], 'expense' => $exp[$k]];
    }
    return $out;
}

/* Validated 2-series palette for the dark surface (OKLCH band + CVD checked). */
const CHART_INCOME  = '#b98a20';
const CHART_EXPENSE = '#4489c2';

function cashflow_chart_html(array $series): string
{
    $W = 640; $H = 190; $padL = 8; $padB = 22; $padT = 12;
    $max = max(1, ...array_map(fn($s) => max($s['income'], $s['expense']), $series));
    $plotH = $H - $padB - $padT;
    $groupW = ($W - $padL * 2) / max(1, count($series));
    $barW = min(26, $groupW * 0.28);
    $y = fn($v) => $padT + $plotH * (1 - $v / $max);

    $grid = '';
    foreach ([0.25, 0.5, 0.75, 1] as $f) {
        $yy = $y($max * $f);
        $grid .= '<line class="grid" x1="' . $padL . '" x2="' . ($W - $padL) . '" y1="' . $yy . '" y2="' . $yy . '"></line>';
    }
    $bars = '';
    foreach ($series as $i => $m) {
        $gx = $padL + $i * $groupW + ($groupW - ($barW * 2 + 2)) / 2;
        $bars .= draw_bar($gx, $m['income'], CHART_INCOME, 'Income', $m['label'], $max, $padT, $plotH, $barW);
        $bars .= draw_bar($gx + $barW + 2, $m['expense'], CHART_EXPENSE, 'Expenses', $m['label'], $max, $padT, $plotH, $barW);
        $tx = $padL + $i * $groupW + $groupW / 2;
        $bars .= '<text class="axis-label" x="' . $tx . '" y="' . ($H - 6) . '" text-anchor="middle">' . e($m['label']) . '</text>';
    }
    $tbl = '';
    foreach ($series as $m) {
        $net = $m['income'] - $m['expense'];
        $tbl .= '<tr><td>' . e($m['label']) . '</td><td class="num">' . money($m['income']) . '</td><td class="num">'
              . money($m['expense']) . '</td><td class="num ' . ($net >= 0 ? 'pos' : 'neg') . '">' . money($net) . '</td></tr>';
    }
    return '
      <div class="chart-legend">
        <span><span class="chip" style="background:' . CHART_INCOME . '"></span>Income</span>
        <span><span class="chip" style="background:' . CHART_EXPENSE . '"></span>Expenses</span>
      </div>
      <svg class="cashflow-svg" viewBox="0 0 ' . $W . ' ' . $H . '" role="img" aria-label="Monthly income versus expenses">
        ' . $grid . '
        <line class="grid" x1="' . $padL . '" x2="' . ($W - $padL) . '" y1="' . ($padT + $plotH) . '" y2="' . ($padT + $plotH) . '" style="stroke:rgba(132,150,169,.5)"></line>
        ' . $bars . '
      </svg>
      <details class="chart-data"><summary>View as table</summary>
        <div class="tbl-wrap"><table>
          <tr><th>Month</th><th class="num">Income</th><th class="num">Expenses</th><th class="num">Net</th></tr>
          ' . $tbl . '
        </table></div>
      </details>';
}
function draw_bar($x, $v, $color, $name, $label, $max, $padT, $plotH, $barW): string
{
    $h = max(0, $plotH * ($v / $max));
    $r = min(4, $h);
    $tip = $label . ' · ' . $name . '|' . money($v);
    $d = 'M' . $x . ',' . ($padT + $plotH)
       . ' v' . (-($h - $r))
       . ' q0,-' . $r . ' ' . $r . ',-' . $r
       . ' h' . ($barW - 2 * $r)
       . ' q' . $r . ',0 ' . $r . ',' . $r
       . ' v' . ($h - $r) . ' z';
    return '<path class="bar" d="' . $d . '" fill="' . $color . '" data-tip="' . e($tip) . '"></path>';
}

/* ============================================================
   CLIENT 360 HEALTH
   ============================================================ */
function client_health(int $cid): array
{
    $score = 100; $notes = [];
    $findings = rows(
        "SELECT f.* FROM findings f JOIN audits a ON a.id = f.audit_id
         WHERE a.client_id = ? AND f.status = 'open'", [$cid]);
    $severe = 0;
    foreach ($findings as $f) { if ($f['severity'] === 'critical' || $f['severity'] === 'high') $severe++; }
    $fp = min(30, $severe * 10 + (count($findings) - $severe) * 3);
    if ($fp) { $score -= $fp; $notes[] = count($findings) . ' open audit finding(s), ' . $severe . ' severe'; }

    $invs = rows('SELECT * FROM invoices WHERE client_id = ?', [$cid]);
    $od = 0; $odAmt = 0;
    foreach ($invs as $i) { if (invoice_overdue($i)) { $od++; $odAmt += invoice_total((int) $i['id']); } }
    if ($od) { $score -= 15; $notes[] = $od . ' overdue invoice(s) — ' . money($odAmt); }

    $obl = (int) scalar("SELECT COUNT(*) FROM obligations WHERE client_id = ? AND status = 'pending' AND due_date < ?", [$cid, today()]);
    if ($obl) { $score -= 10; $notes[] = $obl . ' compliance deadline(s) missed'; }

    $risk = (int) scalar("SELECT COUNT(*) FROM risks WHERE status = 'open' AND likelihood * impact >= 15");
    if ($risk) { $score -= min(15, $risk * 5); $notes[] = $risk . ' severe open risk(s) on the register'; }

    $score = max(0, $score);
    $grade = $score >= 85 ? 'A' : ($score >= 70 ? 'B' : ($score >= 55 ? 'C' : ($score >= 40 ? 'D' : 'E')));
    return ['score' => $score, 'grade' => $grade, 'notes' => $notes, 'findings' => $findings, 'invs' => $invs];
}

/* ---------- small view helpers ---------- */
function client_name(?int $id): string
{
    if (!$id) return '—';
    $n = scalar('SELECT name FROM clients WHERE id = ?', [$id]);
    return $n !== false && $n !== null ? (string) $n : '—';
}
function badge(string $text, string $cls): string { return '<span class="badge ' . $cls . '">' . e($text) . '</span>'; }
function flash(): string
{
    $m = getp('msg');
    return $m === '' ? '' : '<div class="toast" style="position:static;display:inline-block;margin-bottom:14px">' . e($m) . '</div>';
}
