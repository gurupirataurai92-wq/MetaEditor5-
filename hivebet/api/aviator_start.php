<?php
/** Start a live Aviator round: debit stake, commit a crash point, return the seed hash. */
require_once __DIR__ . '/../includes/functions.php';
header('Content-Type: application/json');

function jout(array $d): void { echo json_encode($d); exit; }

if ($_SERVER['REQUEST_METHOD'] !== 'POST')            jout(['ok' => false, 'error' => 'POST only.']);
if (!is_logged_in())                                  jout(['ok' => false, 'error' => 'Please log in to play.']);
if (empty($_POST['csrf']) || !hash_equals($_SESSION['csrf'] ?? '', $_POST['csrf']))
                                                      jout(['ok' => false, 'error' => 'Session expired — reload the page.']);
if (!empty($_SESSION['av_round']['open']))            jout(['ok' => false, 'error' => 'A round is already in flight.']);

$stake = (float)($_POST['stake'] ?? 0);
if ($stake < 1) jout(['ok' => false, 'error' => 'Minimum stake is ' . money(1) . '.']);

$user = current_user($pdo);
if ($stake > (float)$user['balance']) jout(['ok' => false, 'error' => 'Insufficient balance.']);

try {
    $betId = place_bet($pdo, (int)$user['id'], 'aviator',
                       'Aviator live round · stake ' . money($stake), $stake, 1.0);

    $seed  = bin2hex(random_bytes(16));
    $crash = crash_point($seed);

    $_SESSION['av_round'] = [
        'open'  => true,
        'bet'   => $betId,
        'stake' => $stake,
        'seed'  => $seed,
        'crash' => $crash,
        'start' => microtime(true),
    ];

    $bal = $pdo->prepare('SELECT balance FROM users WHERE id = ?');
    $bal->execute([$user['id']]);

    jout([
        'ok'         => true,
        'round'      => $betId,
        'commit'     => hash('sha256', $seed),   // provably-fair commitment
        'rate'       => AVIATOR_RATE,
        'newBalance' => (float)$bal->fetchColumn(),
    ]);
} catch (Throwable $ex) {
    jout(['ok' => false, 'error' => $ex->getMessage()]);
}
