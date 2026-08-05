<?php
/** Ends the operator session. */

declare(strict_types=1);

require_once __DIR__ . '/../includes/auth.php';

logout();
header('Location: login.php');
exit;
