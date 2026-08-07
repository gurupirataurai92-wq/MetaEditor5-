<?php
require_once __DIR__ . '/includes/functions.php';
require_once __DIR__ . '/includes/auth.php';
auth_boot();
logout();
header('Location: login.php');
exit;
