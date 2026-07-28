<?php
/**
 * Database connection for LAKA LAKA CHICKEN (XAMPP / MySQL / MariaDB).
 *
 * Default XAMPP MySQL credentials are user "root" with an empty password.
 * Change these if your XAMPP MySQL is secured differently.
 */

define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'laka_laka_chicken');
define('DB_USER', 'root');
define('DB_PASS', '');       // XAMPP default: empty password
define('DB_PORT', 3306);

// VAT rate used across the POS (15% — ZIMRA standard rate).
define('TAX_RATE', 0.15);

function db(): PDO
{
    static $pdo = null;
    if ($pdo !== null) {
        return $pdo;
    }
    $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', DB_HOST, DB_PORT, DB_NAME);
    try {
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        die(
            '<h2 style="font-family:sans-serif">Database connection failed</h2>' .
            '<p style="font-family:sans-serif">' . htmlspecialchars($e->getMessage()) . '</p>' .
            '<p style="font-family:sans-serif">Make sure MySQL is running in XAMPP and that you have ' .
            'imported <code>sql/laka_laka_chicken.sql</code> via phpMyAdmin.</p>'
        );
    }
    return $pdo;
}

function money(float $n): string
{
    return number_format($n, 2);
}

/**
 * Render a menu item's picture.
 *
 * Uses the item's real photo (a local file under assets/food/photos/ or a full
 * URL) when one is set; if that photo is missing or fails to load it falls back
 * to the built-in illustration, so a card never shows a broken image.
 */
function food_img(?string $image, string $name): string
{
    $icon = 'assets/food/' . menu_icon($name) . '.svg';
    $photo = trim((string) $image);
    $hasPhoto = $photo !== '';
    $src = $hasPhoto ? $photo : $icon;
    $cls = $hasPhoto ? 'food-photo is-photo' : 'food-photo is-icon';
    $enc = fn($s) => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
    // On error: drop to the illustration and restyle as an icon.
    $fallback = "this.onerror=null;this.src='" . $enc($icon)
        . "';this.className='food-photo is-icon'";
    return '<img class="' . $cls . '" src="' . $enc($src) . '" alt="' . $enc($name)
        . '" loading="lazy" onerror="' . $enc($fallback) . '">';
}

/** Pick a food illustration for a menu item by keywords in its name. */
function menu_icon(string $name): string
{
    $n = strtolower($name);
    return match (true) {
        str_contains($n, 'bucket')                     => 'bucket',
        str_contains($n, 'wing')                       => 'wings',
        str_contains($n, 'burger') || str_contains($n, 'zinger') => 'burger',
        str_contains($n, 'fries') || str_contains($n, 'chips')   => 'fries',
        str_contains($n, 'drink') || str_contains($n, 'soda') || str_contains($n, 'cola') => 'drink',
        str_contains($n, 'combo') || str_contains($n, 'meal')    => 'combo',
        default                                        => 'chicken',
    };
}
