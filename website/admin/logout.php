<?php
require __DIR__ . '/../includes/bootstrap.php';
logout();
flash('You have been signed out.');
redirect('admin/login.php');
