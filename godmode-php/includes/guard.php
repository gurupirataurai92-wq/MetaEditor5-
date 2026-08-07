<?php
/* Entry guard for all business-side pages.
   Loads helpers + auth, requires a logged-in business user, logs the visit. */
require_once __DIR__ . '/functions.php';
require_once __DIR__ . '/auth.php';
auth_boot();
require_role('business');
log_usage('visit', basename($_SERVER['PHP_SELF'] ?? 'app'));
