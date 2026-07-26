<?php
/**
 * HiveBet — shared bootstrap + helper functions.
 * Included at the very top of every page.
 */

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

require_once __DIR__ . '/../config/db.php';

/* ------------------------------------------------------------------ *
 *  App constants
 * ------------------------------------------------------------------ */
const APP_NAME       = 'HiveBet';
const CURRENCY       = 'HC';          // "Hive Credits" — play money
const WELCOME_BONUS  = 1000.00;       // credits granted on registration
const HOUSE_EDGE     = 0.05;          // used by demo game odds

/* ------------------------------------------------------------------ *
 *  Auth helpers
 * ------------------------------------------------------------------ */
function current_user(PDO $pdo): ?array {
    if (empty($_SESSION['user_id'])) return null;
    static $cache = null;
    if ($cache && $cache['id'] == $_SESSION['user_id']) return $cache;
    $stmt = $pdo->prepare('SELECT * FROM users WHERE id = ?');
    $stmt->execute([$_SESSION['user_id']]);
    $cache = $stmt->fetch() ?: null;
    return $cache;
}

function is_logged_in(): bool { return !empty($_SESSION['user_id']); }

function require_login(): void {
    if (!is_logged_in()) {
        header('Location: login.php');
        exit;
    }
}

function user_role(PDO $pdo): string {
    $u = current_user($pdo);
    return $u['role'] ?? 'player';
}

/** Staff area: employees and owners. */
function require_staff(PDO $pdo): void {
    require_login();
    if (!in_array(user_role($pdo), ['staff', 'owner'], true)) {
        http_response_code(403);
        die('Staff only.');
    }
}

/** Owner console: owners only. */
function require_owner(PDO $pdo): void {
    require_login();
    if (user_role($pdo) !== 'owner') {
        http_response_code(403);
        die('Owners only.');
    }
}

/** Legacy alias — owner-level access. */
function require_admin(PDO $pdo): void { require_owner($pdo); }

/* ------------------------------------------------------------------ *
 *  CSRF protection
 * ------------------------------------------------------------------ */
function csrf_token(): string {
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function csrf_field(): string {
    return '<input type="hidden" name="csrf" value="' . csrf_token() . '">';
}

function check_csrf(): void {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (empty($_POST['csrf']) || !hash_equals($_SESSION['csrf'] ?? '', $_POST['csrf'])) {
            http_response_code(419);
            die('Session expired — please go back and try again.');
        }
    }
}

/* ------------------------------------------------------------------ *
 *  Flash messages
 * ------------------------------------------------------------------ */
function flash(string $msg, string $type = 'info'): void {
    $_SESSION['flash'][] = ['msg' => $msg, 'type' => $type];
}

function get_flashes(): array {
    $f = $_SESSION['flash'] ?? [];
    unset($_SESSION['flash']);
    return $f;
}

/* ------------------------------------------------------------------ *
 *  Formatting / escaping
 * ------------------------------------------------------------------ */
function e(?string $s): string { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

function money($n): string {
    return CURRENCY . ' ' . number_format((float)$n, 2);
}

/* ------------------------------------------------------------------ *
 *  Wallet — the single choke point for all balance changes.
 *  Every movement writes a transactions row (double-entry style audit).
 * ------------------------------------------------------------------ */
function wallet_move(PDO $pdo, int $userId, string $type, float $amount,
                     ?string $method = null, ?string $note = null,
                     string $status = 'completed', ?string $reference = null): float {
    // $amount is signed: positive = credit player, negative = debit player.
    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare('SELECT balance FROM users WHERE id = ? FOR UPDATE');
        $stmt->execute([$userId]);
        $balance = (float)$stmt->fetchColumn();

        $newBalance = $balance + $amount;
        if ($newBalance < 0) {
            throw new RuntimeException('Insufficient balance.');
        }

        $pdo->prepare('UPDATE users SET balance = ? WHERE id = ?')
            ->execute([$newBalance, $userId]);

        $pdo->prepare(
            'INSERT INTO transactions (user_id, type, method, amount, balance_after, status, reference, note)
             VALUES (?,?,?,?,?,?,?,?)'
        )->execute([$userId, $type, $method, $amount, $newBalance, $status, $reference, $note]);

        $pdo->commit();
        return $newBalance;
    } catch (Throwable $ex) {
        $pdo->rollBack();
        throw $ex;
    }
}

/* ------------------------------------------------------------------ *
 *  Place a bet: debit the stake, record the bet, return its id.
 * ------------------------------------------------------------------ */
function place_bet(PDO $pdo, int $userId, string $game, string $selection,
                   float $stake, float $odds, ?int $eventId = null): int {
    if ($stake <= 0)  throw new RuntimeException('Stake must be greater than zero.');
    if ($odds  < 1.0) throw new RuntimeException('Invalid odds.');

    $potential = round($stake * $odds, 2);

    $pdo->beginTransaction();
    try {
        // Debit stake (re-uses wallet lock logic inline to stay in one tx)
        $stmt = $pdo->prepare('SELECT balance FROM users WHERE id = ? FOR UPDATE');
        $stmt->execute([$userId]);
        $balance = (float)$stmt->fetchColumn();
        if ($balance < $stake) throw new RuntimeException('Insufficient balance for this stake.');
        $newBalance = $balance - $stake;

        $pdo->prepare('UPDATE users SET balance = ? WHERE id = ?')->execute([$newBalance, $userId]);
        $pdo->prepare(
            'INSERT INTO transactions (user_id, type, method, amount, balance_after, note)
             VALUES (?,?,?,?,?,?)'
        )->execute([$userId, 'stake', $game, -$stake, $newBalance, $selection]);

        $pdo->prepare(
            'INSERT INTO bets (user_id, game, event_id, selection, stake, odds, potential_payout, status)
             VALUES (?,?,?,?,?,?,?,?)'
        )->execute([$userId, $game, $eventId, $selection, $stake, $odds, $potential, 'pending']);
        $betId = (int)$pdo->lastInsertId();

        $pdo->commit();
        return $betId;
    } catch (Throwable $ex) {
        $pdo->rollBack();
        throw $ex;
    }
}

/* ------------------------------------------------------------------ *
 *  Settle a bet as won/lost/void and pay out if won.
 * ------------------------------------------------------------------ */
function settle_bet(PDO $pdo, int $betId, string $outcome, ?string $resultText = null): void {
    // $outcome in {won, lost, void}
    $stmt = $pdo->prepare('SELECT * FROM bets WHERE id = ? AND status = "pending"');
    $stmt->execute([$betId]);
    $bet = $stmt->fetch();
    if (!$bet) return;

    $payout = 0.0;
    if ($outcome === 'won')  $payout = (float)$bet['potential_payout'];
    if ($outcome === 'void') $payout = (float)$bet['stake'];   // refund

    $pdo->prepare(
        'UPDATE bets SET status = ?, result = ?, payout = ?, settled_at = NOW() WHERE id = ?'
    )->execute([$outcome, $resultText, $payout, $betId]);

    if ($payout > 0) {
        $type = $outcome === 'void' ? 'payout' : 'payout';
        wallet_move($pdo, (int)$bet['user_id'], $type, $payout, $bet['game'],
                    ($outcome === 'void' ? 'Refund: ' : 'Winnings: ') . $bet['selection']);
    }
}

/* ------------------------------------------------------------------ *
 *  Provably-fair helper: deterministic crash multiplier from a seed.
 *  (Demo implementation — good enough to show the mechanic.)
 * ------------------------------------------------------------------ */
function crash_point(string $seed): float {
    $h = hexdec(substr(hash('sha256', $seed), 0, 8));
    $r = $h / 0xFFFFFFFF;                 // 0..1
    if ($r < 0.03) return 1.00;           // ~3% instant-bust (house edge)
    $point = 0.99 / (1 - $r);             // heavy-tailed distribution
    return min(round($point, 2), 1000.00);
}

/* ------------------------------------------------------------------ *
 *  Live Aviator helpers (server is the authority on the crash).
 *  The multiplier grows as m(t) = e^(RATE * seconds_elapsed); the
 *  crash point is committed up-front (hash shown to the player) and
 *  revealed after the round so it is provably fair.
 * ------------------------------------------------------------------ */
const AVIATOR_RATE = 0.20;   // multiplier growth per second

function aviator_multiplier(float $elapsedSeconds): float {
    return exp(AVIATOR_RATE * max($elapsedSeconds, 0));
}

/** Mark a live Aviator bet as lost — idempotent (only touches a pending bet). */
function aviator_bust(PDO $pdo, array $round): void {
    $stmt = $pdo->prepare('SELECT status FROM bets WHERE id = ?');
    $stmt->execute([$round['bet']]);
    if ($stmt->fetchColumn() === 'pending') {
        $pdo->prepare('UPDATE bets SET status = "lost", result = ?, settled_at = NOW() WHERE id = ?')
            ->execute(['Flew away at ' . number_format($round['crash'], 2) . '×', $round['bet']]);
    }
}

/** Cash a live Aviator bet out at $mult — idempotent, returns payout (0 if already settled). */
function aviator_cash_out(PDO $pdo, array $round, float $mult): float {
    $stmt = $pdo->prepare('SELECT status, stake, user_id FROM bets WHERE id = ?');
    $stmt->execute([$round['bet']]);
    $bet = $stmt->fetch();
    if (!$bet || $bet['status'] !== 'pending') return 0.0;

    $payout = round((float)$bet['stake'] * $mult, 2);
    $pdo->prepare(
        'UPDATE bets SET status = "cashed_out", odds = ?, potential_payout = ?, payout = ?,
                result = ?, settled_at = NOW() WHERE id = ?'
    )->execute([$mult, $payout, $payout, 'Cashed out at ' . number_format($mult, 2) . '×', $round['bet']]);

    wallet_move($pdo, (int)$bet['user_id'], 'payout', $payout, 'aviator',
                'Aviator cash-out at ' . number_format($mult, 2) . '×');
    return $payout;
}
