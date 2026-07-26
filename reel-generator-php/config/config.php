<?php
/**
 * App + database configuration.
 *
 * Defaults match a stock XAMPP install (MySQL on 127.0.0.1:3306, user "root",
 * empty password). Change these if your MySQL is secured differently.
 */

declare(strict_types=1);

return [
    'db' => [
        'host'    => '127.0.0.1',
        'port'    => 3306,
        'name'    => 'reel_generator',
        'user'    => 'root',
        'pass'    => '',
        'charset' => 'utf8mb4',
    ],
    'app' => [
        'name'              => 'Reel Generator',
        'seconds_per_scene' => 4,
        // Auto-create the database + tables on first run. Turn off if you
        // prefer to import sql/schema.sql manually via phpMyAdmin.
        'auto_install'      => true,
    ],
];
