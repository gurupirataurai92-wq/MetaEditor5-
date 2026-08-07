<?php
/**
 * Lymond Services — configuration
 *
 * These are the XAMPP defaults. If you changed the MySQL root password in
 * phpMyAdmin, put the new one in DB_PASS below.
 */

if (!defined('LYMOND')) { define('LYMOND', true); }

/* ---------------------------------------------------------------- database */
define('DB_HOST', '127.0.0.1');
define('DB_PORT', '3306');
define('DB_NAME', 'lymond_services');
define('DB_USER', 'root');
define('DB_PASS', '');            // XAMPP ships with an empty root password

/* ------------------------------------------------------------------- paths */
define('APP_ROOT', dirname(__DIR__));
define('UPLOAD_DIR', APP_ROOT . '/assets/uploads');

/** Web path to the application root, e.g. "/lymond" under htdocs/lymond. */
define('BASE_URL', rtrim(str_replace('\\', '/', dirname(dirname($_SERVER['SCRIPT_NAME'] ?? '/'))), '/') ?: '');

/* ------------------------------------------------------------------ uploads */
define('UPLOAD_MAX_BYTES', 8 * 1024 * 1024);   // 8 MB per photo
define('PHOTO_MAX_EDGE', 1600);                // longest side after resizing
define('PHOTO_JPEG_QUALITY', 82);
define('PHOTOS_PER_ITEM', 10);

/* ------------------------------------------------------------------ signing */
define('LOGIN_MAX_ATTEMPTS', 5);               // per username+IP
define('LOGIN_LOCKOUT_MINUTES', 15);
define('SESSION_IDLE_MINUTES', 45);

/* ---------------------------------------------------------------- behaviour */
define('ITEMS_PER_PAGE', 12);
define('SHOW_ERRORS', true);                   // set false on a public server
