<?php
/**
 * Every page starts here.
 *
 *     require __DIR__ . '/includes/bootstrap.php';
 */

declare(strict_types=1);

define('LYMOND', true);

require __DIR__ . '/config.php';

if (SHOW_ERRORS) {
    error_reporting(E_ALL);
    ini_set('display_errors', '1');
} else {
    error_reporting(E_ALL);
    ini_set('display_errors', '0');
    ini_set('log_errors', '1');
}

require __DIR__ . '/db.php';
require __DIR__ . '/helpers.php';
require __DIR__ . '/auth.php';
require __DIR__ . '/photos.php';

start_session();

/* Modest hardening. A stricter Content-Security-Policy is possible once the
   few inline style attributes in the templates are moved into the stylesheet. */
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: SAMEORIGIN');
header('Referrer-Policy: same-origin');
