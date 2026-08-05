<?php
declare(strict_types=1);

/**
 * Prints the code an account's authenticator is currently showing, so the
 * seeded demo can be explored without setting up a phone.
 *
 *   php database/totp_code.php manager@example.com
 *
 * Refuses to run over the web from anywhere but this machine: being able to
 * mint a valid second factor remotely would make the second factor pointless.
 */

namespace Haulr;

spl_autoload_register(static function (string $class): void {
    $prefix = 'Haulr\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $file = dirname(__DIR__) . '/app/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
    if (is_file($file)) {
        require_once $file;
    }
});

if (PHP_SAPI !== 'cli') {
    header('Content-Type: text/plain; charset=utf-8');
    if (!in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true)) {
        http_response_code(403);
        exit("Only available from the machine running the server.\n");
    }
}

$email = strtolower(trim((string) ($argv[1] ?? $_GET['email'] ?? '')));
if ($email === '') {
    exit("Usage: php database/totp_code.php <email>\n");
}

$user = Database::first('SELECT email, totp_secret, totp_enabled FROM users WHERE email = ?', [$email]);
if ($user === null) {
    exit("No account found for $email\n");
}
if ($user['totp_secret'] === null) {
    exit("$email has no second factor set up.\n");
}

$code = Totp::currentCode((string) $user['totp_secret']);
$secondsLeft = Totp::STEP_SECONDS - (time() % Totp::STEP_SECONDS);

echo "\n  $code\n\n";
echo "  valid for another {$secondsLeft}s";
echo (int) $user['totp_enabled'] === 1 ? "\n" : "  (2FA not yet enabled on this account)\n";
