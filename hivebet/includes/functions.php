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

function require_admin(PDO $pdo): void {
    require_login();
    $u = current_user($pdo);
    if (!$u || !$u['is_admin']) {
        http_response_code(403);
        die('Admins only.');
    }
}

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
