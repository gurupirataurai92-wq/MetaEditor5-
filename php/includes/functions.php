<?php
/** Small view/formatting helpers shared across pages. */

/** HTML-escape (use for every value printed into a page). */
function h($v): string
{
    return htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
}

/** Format a number as money in the configured currency. */
function money($amount): string
{
    return CUR_SYMBOL . number_format((float) $amount, 2);
}

/** Extract the VAT portion from a VAT-inclusive price. */
function vat_portion($inclusive): float
{
    $rate = VAT_RATE;
    return (float) $inclusive - ((float) $inclusive / (1 + $rate));
}

/** Net (VAT-exclusive) portion of a VAT-inclusive price. */
function net_portion($inclusive): float
{
    return (float) $inclusive / (1 + VAT_RATE);
}

/** CSRF token for forms. */
function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(16));
    }
    return $_SESSION['csrf'];
}

/** Hidden CSRF input for forms. */
function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="' . h(csrf_token()) . '">';
}

/** Verify the CSRF token submitted with a POST. Aborts on mismatch. */
function csrf_check(): void
{
    $sent = $_POST['csrf'] ?? '';
    if (!hash_equals($_SESSION['csrf'] ?? '', (string) $sent)) {
        http_response_code(400);
        exit('Invalid form token. Please go back and try again.');
    }
}

/** Redirect helper. */
function redirect(string $to): void
{
    header('Location: ' . $to);
    exit;
}

/** Flash message set/get (survives one redirect). */
function flash_set(string $type, string $msg): void
{
    $_SESSION['flash'] = ['type' => $type, 'msg' => $msg];
}

function flash_get(): ?array
{
    if (!empty($_SESSION['flash'])) {
        $f = $_SESSION['flash'];
        unset($_SESSION['flash']);
        return $f;
    }
    return null;
}
