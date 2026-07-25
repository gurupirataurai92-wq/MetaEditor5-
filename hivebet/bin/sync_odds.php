<?php
/**
 * CLI odds sync — run from the project root:
 *
 *     php bin/sync_odds.php
 *
 * Schedule it like a real feed poller. Examples:
 *   Linux/macOS cron (every 5 min):
 *     * /5 * * * * php /opt/lampp/htdocs/hivebet/bin/sync_odds.php >> /var/log/hivebet-odds.log 2>&1
 *   Windows Task Scheduler:
 *     program: C:\xampp\php\php.exe   args: C:\xampp\htdocs\hivebet\bin\sync_odds.php
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("Run this from the command line.\n");
}

require __DIR__ . '/../config/db.php';        // gives us $pdo
require __DIR__ . '/../includes/odds_feed.php';

$res = odds_feed_sync($pdo);
printf("[%s] odds sync: fetched %d, inserted %d, updated %d\n",
    date('Y-m-d H:i:s'), $res['fetched'], $res['inserted'], $res['updated']);
