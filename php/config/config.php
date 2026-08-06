<?php
/**
 * SIMS AI — configuration.
 *
 * These are the XAMPP defaults (MySQL user "root", empty password). Change
 * them here if your MySQL is set up differently.
 */
define('DB_HOST', '127.0.0.1');
define('DB_PORT', '3306');
define('DB_NAME', 'sims_ai');
define('DB_USER', 'root');
define('DB_PASS', '');

define('APP_NAME', 'SIMS AI');
define('CURRENCY', 'USD');
define('CUR_SYMBOL', '$');
define('VAT_RATE', 0.15);          // ZIMRA standard VAT (15%), prices are VAT-inclusive

date_default_timezone_set('Africa/Harare');
