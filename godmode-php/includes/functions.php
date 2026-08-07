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
   INVENTORY
   ============================================================ */
function inventory_stats(): array
{
    $items = rows('SELECT quantity, unit_cost, reorder_level FROM inventory_items');
    $value = 0; $low = 0; $out = 0;
    foreach ($items as $it) {
        $value += (float) $it['quantity'] * (float) $it['unit_cost'];
        if ((float) $it['quantity'] <= 0) $out++;
        elseif ((float) $it['quantity'] <= (float) $it['reorder_level']) $low++;
    }
    return ['count' => count($items), 'value' => $value, 'low' => $low, 'out' => $out,
            'alerts' => $low + $out];
}
function stock_status(array $it): array
{
    $qFloat = (float) $it['quantity'];
    if ($qFloat <= 0) return ['OUT OF STOCK', 'b-red'];
    if ($qFloat <= (float) $it['reorder_level']) return ['LOW — reorder', 'b-amber'];
    return ['in stock', 'b-green'];
}

/* ============================================================
   PAYMENTS (authorization / sign-off)
   ============================================================ */
function payment_stats(): array
{
    $pendCount = (int) scalar("SELECT COUNT(*) FROM payments WHERE status = 'pending'");
    $pendAmt   = (float) scalar("SELECT COALESCE(SUM(amount),0) FROM payments WHERE status = 'pending'");
    $signedAmt = (float) scalar("SELECT COALESCE(SUM(amount),0) FROM payments WHERE status = 'signed'");
    return ['pendCount' => $pendCount, 'pendAmt' => $pendAmt, 'signedAmt' => $signedAmt];
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

/* ============================================================
   ZIMBABWE LEGAL & COMPLIANCE KNOWLEDGE BASE
   Structural reference (statutes + authorities + obligations).
   Rates/thresholds change frequently — always verify the current
   figure with the named authority before acting.
   ============================================================ */
function zim_legal_kb(): array
{
    return [
        [
            'key' => 'income-tax', 'title' => 'Corporate Income Tax & Provisional Tax (QPDs)',
            'authority' => 'ZIMRA', 'act' => 'Income Tax Act [Chapter 23:06] & Finance Act',
            'summary' => 'Registered companies are taxed on taxable income and pay provisional tax on Quarterly Payment Dates (QPDs), not in one lump sum.',
            'obligations' => [
                'Provisional tax (QPDs), cumulative: 10% by 25 March, 25% by 25 June, 30% by 25 September, 35% by 20 December.',
                'Annual income tax return (ITF12C) after year-end.',
                'Keep records for at least 6 years.',
            ],
            'verify' => 'Confirm the current corporate rate and AIDS levy with ZIMRA — they are set each year in the Finance Act.',
        ],
        [
            'key' => 'vat', 'title' => 'Value Added Tax (VAT)',
            'authority' => 'ZIMRA', 'act' => 'Value Added Tax Act [Chapter 23:12]',
            'summary' => 'Businesses whose taxable turnover exceeds the prescribed registration threshold must register for VAT, charge output VAT, and file returns.',
            'obligations' => [
                'Register once taxable turnover exceeds the ZIMRA threshold (voluntary registration is possible below it).',
                'Standard rate is 15% (some goods are zero-rated or exempt).',
                'File VAT returns and remit by the due date for your category (commonly the 25th of the following month).',
                'Issue compliant fiscal tax invoices (fiscalisation applies to many taxpayers).',
            ],
            'verify' => 'Confirm the current registration threshold, rate and your filing category with ZIMRA.',
        ],
        [
            'key' => 'paye', 'title' => 'PAYE / Employees Tax (FDS)',
            'authority' => 'ZIMRA', 'act' => 'Income Tax Act [Chapter 23:06], 13th Schedule',
            'summary' => 'Employers must deduct employees tax (PAYE) under the Final Deduction System and remit it monthly.',
            'obligations' => [
                'Withhold PAYE per the current tax tables each pay run.',
                'Remit to ZIMRA by the 10th of the following month.',
                'File annual PAYE reconciliation (ITF16) and issue employee tax certificates.',
            ],
            'verify' => 'Use the current year PAYE tax tables from ZIMRA (they change annually and by currency, USD vs ZiG).',
        ],
        [
            'key' => 'nssa', 'title' => 'NSSA Social Security Contributions',
            'authority' => 'NSSA', 'act' => 'NSSA Act [Chapter 17:04] (POBS & APWCS schemes)',
            'summary' => 'Employers register with NSSA and remit monthly contributions for the pension (POBS) and accident (APWCS) schemes.',
            'obligations' => [
                'Register the business and each employee with NSSA.',
                'Deduct the employee share and add the employer share of insurable earnings, monthly.',
                'Remit by the NSSA due date each month.',
            ],
            'verify' => 'Confirm the current contribution rate and insurable-earnings ceiling with NSSA.',
        ],
        [
            'key' => 'zimdef', 'title' => 'ZIMDEF Skills Development Levy',
            'authority' => 'Ministry of Higher & Tertiary Education / ZIMDEF',
            'act' => 'Manpower Planning and Development Act [Chapter 28:02]',
            'summary' => 'Employers pay a manpower development (skills) levy on their wage bill.',
            'obligations' => [
                'Levy is 1% of the gross monthly wage bill.',
                'Remit to ZIMDEF monthly.',
            ],
            'verify' => 'Confirm the current levy rate and remittance channel with ZIMDEF.',
        ],
        [
            'key' => 'labour', 'title' => 'Labour & Employment',
            'authority' => 'Ministry of Labour / NEC for your sector',
            'act' => 'Labour Act [Chapter 28:01]',
            'summary' => 'Governs contracts, wages, working hours, leave, discipline and retrenchment. Many sectors have a National Employment Council (NEC) setting minimum wages and conditions.',
            'obligations' => [
                'Issue written particulars of employment.',
                'Pay at least the applicable sector minimum wage (set by NEC / statutory instrument).',
                'Follow the Act and your NEC code for discipline and retrenchment.',
            ],
            'verify' => 'Check your sector NEC for the current minimum wage and conditions of service.',
        ],
        [
            'key' => 'company', 'title' => 'Company Registration & Annual Returns',
            'authority' => 'Registrar of Companies (Deeds, Companies & Intellectual Property)',
            'act' => 'Companies and Other Business Entities Act [Chapter 24:31] (COBE)',
            'summary' => 'Entities must be registered and keep their filings current, including annual returns and beneficial ownership information.',
            'obligations' => [
                'File annual returns and keep statutory registers.',
                'Maintain and update beneficial ownership records.',
                'Notify changes of directors, address and share capital.',
            ],
            'verify' => 'Confirm annual return fees and deadlines with the Registrar.',
        ],
        [
            'key' => 'imtt', 'title' => 'Intermediated Money Transfer Tax (IMTT)',
            'authority' => 'ZIMRA', 'act' => 'Finance Act (IMTT provisions)',
            'summary' => 'A tax applies to electronic money transfers. Budget for it as a real transaction cost.',
            'obligations' => ['Account for IMTT on qualifying electronic transactions.'],
            'verify' => 'Confirm the current IMTT rate and exemptions with ZIMRA.',
        ],
        [
            'key' => 'data', 'title' => 'Data Protection',
            'authority' => 'POTRAZ (Data Protection Authority)',
            'act' => 'Cyber and Data Protection Act [Chapter 12:07]',
            'summary' => 'Businesses that process personal data must handle it lawfully and securely.',
            'obligations' => [
                'Process personal data lawfully and keep it secure.',
                'Register with / appoint a Data Protection Officer where required.',
            ],
            'verify' => 'Check current registration and DPO requirements with POTRAZ.',
        ],
    ];
}
function zim_legal_find(string $key): ?array
{
    foreach (zim_legal_kb() as $t) { if ($t['key'] === $key) return $t; }
    return null;
}

/* ============================================================
   ADVISOR — data-driven decision support ("AI") side panel.
   Reads live figures + the Zimbabwe KB and emits prioritized,
   actionable suggestions. Designed to be swappable for an LLM.
   ============================================================ */
function advisor_suggestions(): array
{
    $s = [];
    $add = function ($level, $text, $action = null) use (&$s) {
        $s[] = ['level' => $level, 'text' => $text, 'action' => $action];
    };

    $fin = financials();
    $inv = invoice_stats();
    $pf  = portfolio_stats();
    $pay = payment_stats();
    $invy = inventory_stats();

    // Books integrity
    $equityTotal = $fin['totalEquity'] + $fin['netIncome'];
    if (abs($fin['totalAssets'] - ($fin['totalLiabs'] + $equityTotal)) > 0.005) {
        $add('critical', 'Your books do not balance. Review recent journal entries before you rely on any report.', ['Open Accounting', 'accounting.php']);
    }

    // Compliance deadlines
    $overdueObl = (int) scalar("SELECT COUNT(*) FROM obligations WHERE status = 'pending' AND due_date < ?", [today()]);
    $soonObl = (int) scalar("SELECT COUNT(*) FROM obligations WHERE status = 'pending' AND due_date >= ? AND due_date <= ?", [today(), date('Y-m-d', strtotime('+14 days'))]);
    if ($overdueObl > 0) {
        $add('critical', $overdueObl . ' statutory filing(s) are overdue. In Zimbabwe, late ZIMRA/NSSA filings attract penalties and interest — file immediately.', ['Tax & Compliance', 'tax.php']);
    } elseif ($soonObl > 0) {
        $add('warn', $soonObl . ' compliance deadline(s) fall within 14 days. Prepare filings now to avoid penalties.', ['Tax & Compliance', 'tax.php']);
    }

    // Receivables
    if ($inv['overdueCount'] > 0) {
        $add('warn', $inv['overdueCount'] . ' invoice(s) overdue (' . money($inv['overdue']) . '). Chase collection — ageing receivables strangle cash flow.', ['Invoicing', 'invoicing.php']);
    }

    // Payments awaiting authorization
    if ($pay['pendCount'] > 0) {
        $add('info', $pay['pendCount'] . ' payment(s) await authorized sign-off (' . money($pay['pendAmt']) . '). Review before releasing funds.', ['Payments', 'payments.php']);
    }

    // Microfinance risk
    if ($pf['parPct'] > 5) {
        $add('warn', 'Portfolio-at-risk (>30d) is ' . fnum($pf['parPct']) . '% vs a <5% target. Tighten collections and re-score overdue borrowers.', ['Microfinance', 'microfinance.php']);
    }

    // Inventory
    if ($invy['out'] > 0) {
        $add('warn', $invy['out'] . ' item(s) are out of stock. Reorder to protect sales and service levels.', ['Inventory', 'inventory.php']);
    } elseif ($invy['low'] > 0) {
        $add('info', $invy['low'] . ' item(s) are at/below reorder level. Plan a purchase.', ['Inventory', 'inventory.php']);
    }

    // Risk register
    $sevRisks = (int) scalar("SELECT COUNT(*) FROM risks WHERE status = 'open' AND likelihood * impact >= 15");
    if ($sevRisks > 0) {
        $add('warn', $sevRisks . ' severe risk(s) (score ≥ 15) are unmitigated. Assign owners and mitigation actions.', ['Risk Register', 'risk.php']);
    }

    // Zimbabwe payroll obligations
    $emp = (int) scalar('SELECT COUNT(*) FROM employees');
    if ($emp > 0) {
        $add('info', 'Payroll is active (' . $emp . ' staff). Remit PAYE by the 10th, and NSSA + ZIMDEF (1% of the wage bill) monthly. Verify current rates.', ['Zim compliance', 'legal.php#paye']);
    }

    // Income tax provisional payments
    if (array_sum(array_column($fin['income'], 'amt')) > 0) {
        $add('info', 'You are earning income — set provisional tax aside for the QPDs (25 Mar / Jun / Sep / Dec) so quarterly payments do not squeeze cash.', ['Zim compliance', 'legal.php#income-tax']);
    }

    // Decision hygiene
    $activeLoops = (int) scalar("SELECT COUNT(*) FROM ooda WHERE status = 'active'");
    if ($activeLoops === 0) {
        $add('info', 'Facing a big call (pricing, hiring, expansion)? Run it through an OODA loop instead of deciding on instinct.', ['OODA Engine', 'ooda.php']);
    }

    // Onboarding
    if ((int) scalar('SELECT COUNT(*) FROM clients') === 0) {
        $add('info', 'Start by adding your first client in Consulting / CRM — most other modules build on it.', ['Add a client', 'consulting.php']);
    }

    if (!$s) {
        $add('good', 'No red flags right now. Keep filings current and log major decisions in the OODA engine.');
    }

    $rank = ['critical' => 0, 'warn' => 1, 'info' => 2, 'good' => 3];
    usort($s, fn($a, $b) => $rank[$a['level']] <=> $rank[$b['level']]);
    return $s;
}

function page_tip(string $page): string
{
    $tips = [
        'index.php'        => 'Scan the alert tiles top-to-bottom: red first, then amber. The Advisor panel turns them into a to-do list.',
        'ooda.php'         => 'Cycle faster than the problem changes: write what you Observe before you Orient, and always close with a measured Act.',
        'consulting.php'   => 'A SWOT per client sharpens your advice — strengths and threats often reveal the next engagement.',
        'auditing.php'     => 'Rank findings by severity; a critical control gap is worth more attention than ten cosmetic ones.',
        'accounting.php'   => 'Every transaction is two entries. If the balance sheet stops balancing, your last entry is the suspect.',
        'invoicing.php'    => 'Invoice the day work is delivered, not month-end — days saved here are cash in the bank.',
        'payments.php'     => 'Never release funds without a signatory. The signature is your audit trail if anything is queried.',
        'inventory.php'    => 'Set realistic reorder levels — the system will warn you before you run out, not after.',
        'microfinance.php' => 'Watch PAR>30 like a hawk; in microfinance, portfolio quality matters more than portfolio size.',
        'tax.php'          => 'In Zimbabwe, ZIMRA penalties compound. A filed-on-time nil return beats a late one every time.',
        'hr.php'           => 'Budget the full cost of an employee: gross pay plus PAYE, NSSA and ZIMDEF on top.',
        'risk.php'         => 'Likelihood × impact focuses the eye. Anything scoring 15+ deserves a named owner today.',
        'analysis.php'     => 'A current ratio below 1 is a liquidity warning even when the P&L looks healthy.',
        'legal.php'        => 'This is structural guidance — always confirm the current rate or threshold with the named authority.',
    ];
    return $tips[$page] ?? 'Use Ctrl+K to jump anywhere, and check the Advisor panel for what needs attention.';
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
