<?php
/** Shared page chrome. Call layout_header($title) then layout_footer(). */

declare(strict_types=1);

require_once __DIR__ . '/helpers.php';

function layout_header(string $title): void
{
    $app = config()['app']['name'] ?? 'Reel Generator';
    ?><!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= h($title) ?> — <?= h($app) ?></title>
    <link rel="stylesheet" href="<?= h(url('assets/style.css')) ?>">
</head>
<body>
    <header class="top">
        <div class="wrap">
            <a class="brand" href="<?= h(url('index.php')) ?>"><span class="dot">🎬</span> <?= h($app) ?></a>
            <span class="badge">PHP · MySQL · XAMPP</span>
        </div>
    </header>
    <main class="wrap"><?php
}

function layout_footer(): void
{
    ?></main>
    <footer class="wrap">
        <span>Reel Generator — runs on XAMPP (Apache + MySQL + PHP).</span>
        <span>Drop this folder in <code>htdocs/</code> and open it in your browser.</span>
    </footer>
</body>
</html><?php
}
