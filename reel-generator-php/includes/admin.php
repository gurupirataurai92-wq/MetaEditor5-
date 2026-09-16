<?php
/** Shared chrome for the operator console (admin/ pages). */

declare(strict_types=1);

require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/helpers.php';

function admin_header(string $title, ?array $op = null): void
{
    ?><!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= h($title) ?> — Operator Console</title>
    <link rel="stylesheet" href="../assets/style.css">
</head>
<body>
    <header class="top">
        <div class="wrap">
            <a class="brand" href="index.php"><span class="dot">🛠️</span> Operator Console</a>
            <?php if ($op !== null): ?>
                <nav class="admin-nav">
                    <a href="index.php">Dashboard</a>
                    <a href="reels.php">Reels</a>
                    <a href="uploads.php">Uploads</a>
                    <a href="operators.php">Operators</a>
                    <a href="../index.php">↗ Site</a>
                    <a href="logout.php" class="danger-link"><?= h($op['username']) ?> · Logout</a>
                </nav>
            <?php endif; ?>
        </div>
    </header>
    <main class="wrap admin"><?php
}

function admin_footer(): void
{
    ?></main>
</body>
</html><?php
}
