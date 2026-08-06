<?php
/** PWA manifest so the system installs as an app on tablets / PC / phone. */
require_once __DIR__ . '/config/config.php';
header('Content-Type: application/manifest+json');
$icon = 'data:image/svg+xml;base64,' . base64_encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">'
    . '<rect width="192" height="192" rx="42" fill="#0f9d72"/>'
    . '<text x="96" y="130" font-size="110" text-anchor="middle" fill="#fff" '
    . 'font-family="system-ui">◆</text></svg>'
);
?>
{
  "name": "<?= APP_NAME ?> — Business Ecosystem",
  "short_name": "<?= APP_NAME ?>",
  "start_url": "index.php",
  "scope": ".",
  "display": "standalone",
  "background_color": "#0b1220",
  "theme_color": "#0f9d72",
  "icons": [
    { "src": "<?= $icon ?>", "sizes": "192x192", "type": "image/svg+xml", "purpose": "any maskable" }
  ]
}
