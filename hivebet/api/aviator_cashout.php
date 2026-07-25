<?php
/** Cash out the live round at the current server-side multiplier. */
require_once __DIR__ . '/../includes/functions.php';
header('Content-Type: application/json');

function jout(array $d): void { echo json_encode($d); exit; }

if ($_SERVER['REQUEST_METHOD'] !== 'POST') jout(['ok' => false, 'error' => 'POST only.']);
if (empty($_POST['csrf']) || !hash_equals($_SESSION['csrf'] ?? '', $_POST['csrf']))
    jout(['ok' => false, 'error' => 'Session expired.']);

$r = $_SESSION['av_round'] ?? null;
if (!$r || empty($r['open'])) jout(['ok' => false, 'error' => 'No active round.']);

$elapsed = microtime(true) - $r['start'];
$mult    = aviator_multiplier($elapsed);

if ($mult >= $r['crash']) {
    // Player was too slow — it already flew away.
    aviator_bust($pdo, $r);
    $_SESSION['av_round']['open'] = false;
    jout(['ok' => false, 'crashed' => true, 'point' => round($r['crash'], 2), 'seed' => $r['seed']]);
}

$mult   = round($mult, 2);
$payout = aviator_cash_out($pdo, $r, $mult);
$_SESSION['av_round']['open'] = false;

$bal = $pdo->prepare('SELECT balance FROM users WHERE id = ?');
$bal->execute([$_SESSION['user_id']]);

jout([
    'ok'         => true,
    'multiplier' => $mult,
    'payout'     => $payout,
    'point'      => round($r['crash'], 2),
    'seed'       => $r['seed'],
    'newBalance' => (float)$bal->fetchColumn(),
]);
