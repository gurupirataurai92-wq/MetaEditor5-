<?php
require_once __DIR__ . '/includes/guard.php';
if (is_post()) {
    $cur = post('currency', 'USD');
    $allowed = ['USD','EUR','GBP','KES','NGN','ZAR','GHS','UGX','TZS','RWF','ZMW','INR','PHP','IDR','BRL','MXN'];
    if (in_array($cur, $allowed, true)) {
        q('UPDATE settings SET currency = ? WHERE id = 1', [$cur]);
    }
}
redirect($_SERVER['HTTP_REFERER'] ?? 'index.php');
