<?php
/** Entry point: send signed-in users to their dashboard, others to login. */
require_once __DIR__ . '/includes/auth.php';

$u = current_user();
if ($u) {
    redirect(ROLE_HOME[$u['role']] ?? 'login.php');
}
redirect('login.php');
