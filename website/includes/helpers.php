<?php
/**
 * Shared helpers: escaping, formatting, settings, flash messages, CSRF.
 */

if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }

/** Escape for HTML output. Every echoed value goes through this. */
function e($v): string
{
    return htmlspecialchars((string)($v ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function money($n): string
{
    return '$' . number_format((float)$n, 0, '.', ',');
}

function km($n): string
{
    return number_format((float)$n, 0, '.', ',') . ' km';
}

function url(string $path = ''): string
{
    return BASE_URL . '/' . ltrim($path, '/');
}

function redirect(string $path): never
{
    header('Location: ' . (preg_match('~^https?://~', $path) ? $path : url($path)));
    exit;
}

/* ------------------------------------------------------------- site settings */

function settings(): array
{
    static $cache = null;
    if ($cache === null) {
        $cache = [];
        foreach (q_all('SELECT name, value FROM settings') as $row) {
            $cache[$row['name']] = $row['value'];
        }
    }
    return $cache;
}

function setting(string $name, string $default = ''): string
{
    $s = settings();
    return isset($s[$name]) && $s[$name] !== '' ? $s[$name] : $default;
}

function wa_link(string $message): string
{
    $number = preg_replace('/[^0-9]/', '', setting('whatsapp'));
    return 'https://wa.me/' . $number . '?text=' . rawurlencode($message);
}

/* ------------------------------------------------------------------- photos */

/** Web path for a stored photo, or the placeholder illustration. */
function photo_url(?string $filename, string $fallback): string
{
    if ($filename && is_file(UPLOAD_DIR . '/' . basename($filename))) {
        return url('assets/uploads/' . rawurlencode(basename($filename)));
    }
    return url($fallback);
}

function vehicle_photo(array $v): string
{
    return photo_url($v['cover'] ?? null, 'assets/img/' . ($v['body'] ?? 'sedan') . '.svg');
}

function part_photo(array $p): string
{
    return photo_url($p['cover'] ?? null, 'assets/img/parts/' . ($p['category_slug'] ?? 'engine') . '.svg');
}

/* ------------------------------------------------------------ flash messages */

function flash(string $message, string $kind = 'ok'): void
{
    $_SESSION['flash'][] = ['message' => $message, 'kind' => $kind];
}

function take_flashes(): array
{
    $out = $_SESSION['flash'] ?? [];
    unset($_SESSION['flash']);
    return $out;
}

/* --------------------------------------------------------------------- CSRF */

function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="' . e(csrf_token()) . '">';
}

/** Verify the token on a POST, or stop the request. */
function csrf_check(): void
{
    $sent = $_POST['csrf'] ?? '';
    if (!is_string($sent) || !hash_equals($_SESSION['csrf'] ?? '', $sent)) {
        http_response_code(400);
        exit('Your session expired or the form was tampered with. Go back and try again.');
    }
}

/* --------------------------------------------------------------- form values */

/** Old input after a validation failure, so the operator does not retype it. */
function old(string $field, $default = '')
{
    return $_POST[$field] ?? $default;
}

function status_label(string $status): array
{
    return match ($status) {
        'in-stock'   => ['In stock', 'card-flag--stock'],
        'in-transit' => ['In transit', 'card-flag--order'],
        default      => ['To order', ''],
    };
}

function part_type_label(string $type): array
{
    return match ($type) {
        'genuine'     => ['Genuine', 'tag--genuine'],
        'oem'         => ['OEM', 'tag--oem'],
        'aftermarket' => ['Aftermarket', ''],
        default       => ['Japan used', ''],
    };
}

function body_label(string $body): string
{
    return match ($body) {
        'suv'       => 'SUV / 4WD',
        'van'       => 'Van / MPV',
        'hatchback' => 'Hatchback',
        'pickup'    => 'Pickup',
        'truck'     => 'Truck',
        default     => 'Sedan',
    };
}

function size_label(string $size): string
{
    return match ($size) {
        'small'  => 'Small part',
        'medium' => 'Medium part',
        default  => 'Large part',
    };
}

/** Keep the current query string but change one parameter (used by paging). */
function with_query(array $changes): string
{
    $params = array_merge($_GET, $changes);
    $params = array_filter($params, fn($v) => $v !== '' && $v !== null);
    return '?' . http_build_query($params);
}
