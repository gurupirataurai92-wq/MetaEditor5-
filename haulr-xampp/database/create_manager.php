<?php
declare(strict_types=1);

/**
 * Creates a manager account.
 *
 *   php database/create_manager.php "Grace Molefe" grace@example.com "+27 82 555 0100"
 *
 * Manager accounts are deliberately not obtainable through the website: there
 * is no self-service path to the role that can read every job in the system.
 * This script (run by whoever administers the server) bootstraps the first
 * one; every manager after that is created from inside the console.
 *
 * The password is typed at the prompt, never passed as an argument, so it does
 * not end up in shell history or the process list.
 */

namespace Haulr;

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("This script only runs from a terminal.\n");
}

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

function ask(string $question): string
{
    echo $question;
    return trim((string) fgets(STDIN));
}

/** Prompt without echoing, where the platform allows it. */
function askHidden(string $question): string
{
    echo $question;
    if (DIRECTORY_SEPARATOR !== '\\' && function_exists('shell_exec')) {
        shell_exec('stty -echo 2>/dev/null');
        $value = trim((string) fgets(STDIN));
        shell_exec('stty echo 2>/dev/null');
        echo "\n";
        return $value;
    }
    // Windows: no portable way to disable echo, so warn instead of pretending.
    echo "\n  (your typing will be visible in this terminal)\n  ";
    return trim((string) fgets(STDIN));
}

$fullName = $argv[1] ?? ask('Full name: ');
$email    = strtolower($argv[2] ?? ask('Email: '));
$phone    = $argv[3] ?? ask('Phone: ');

if ($fullName === '' || $email === '' || $phone === '') {
    exit("Name, email and phone are all required.\n");
}
if (Database::first('SELECT id FROM users WHERE email = ?', [$email]) !== null) {
    exit("An account already exists for $email\n");
}

echo "\nPassword policy: " . Security::describePasswordPolicy() . "\n\n";
$password = askHidden('Password: ');
$confirm  = askHidden('Confirm password: ');

if ($password !== $confirm) {
    exit("Passwords do not match.\n");
}

$problems = Security::passwordProblems($password, $email, $fullName);
if ($problems !== []) {
    exit('Password must ' . implode(', ', $problems) . ".\n");
}

$id = Database::insert(
    "INSERT INTO users (role, full_name, email, phone, password_hash, password_changed_at)
     VALUES ('manager', ?, ?, ?, ?, NOW())",
    [$fullName, $email, $phone, Auth::hashPassword($password)]
);

Audit::record(Audit::MANAGER_CREATED, null, 'user', $id, "$email (created via CLI)");

echo "\nManager account created for $email\n";
echo "On first sign-in they must enrol two-factor authentication before the console will open.\n";
