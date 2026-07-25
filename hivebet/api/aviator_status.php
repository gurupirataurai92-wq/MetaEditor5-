<?php
/** Poll the live round. Server decides if/when it has crashed and settles the loss. */
require_once __DIR__ . '/../includes/functions.php';
header('Content-Type: application/json');

$r = $_SESSION['av_round'] ?? null;
if (!$r || empty($r['open'])) { echo json_encode(['state' => 'idle']); exit; }

$elapsed = microtime(true) - $r['start'];
$mult    = aviator_multiplier($elapsed);

if ($mult >= $r['crash']) {
    // Crashed — settle the bet as lost and close the round.
    aviator_bust($pdo, $r);
    $_SESSION['av_round']['open'] = false;
    echo json_encode([
        'state' => 'crashed',
        'point' => round($r['crash'], 2),
        'seed'  => $r['seed'],   // reveal for provably-fair verification
    ]);
    exit;
}

echo json_encode(['state' => 'running', 'multiplier' => round($mult, 2)]);
