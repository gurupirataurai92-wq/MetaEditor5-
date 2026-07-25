<?php
/**
 * Odds-feed integration stub.
 *
 * In production you swap odds_feed_fetch() for a real HTTP call to a sports-data
 * provider (Sportradar, BetConstruct, The Odds API, OddsAPI, etc.). Everything
 * else — odds_feed_sync() and the admin/cron entry points — stays the same.
 *
 * Standalone: depends only on $pdo (no session), so it can run from the web
 * admin panel OR from the CLI cron script bin/sync_odds.php.
 */

/**
 * Pull the latest fixtures + odds from the provider.
 *
 * ---- REAL IMPLEMENTATION (example) ---------------------------------
 *   $apiKey = getenv('ODDS_API_KEY');
 *   $url = 'https://api.the-odds-api.com/v4/sports/soccer/odds/'
 *        . '?regions=uk&markets=h2h&oddsFormat=decimal&apiKey=' . $apiKey;
 *   $raw = file_get_contents($url);          // or curl / Guzzle
 *   $data = json_decode($raw, true);
 *   // ...map provider JSON into the normalised shape returned below...
 * --------------------------------------------------------------------
 *
 * The demo below returns a fixed slate with lightly randomised odds so each
 * sync visibly "moves the line", exactly like a live feed would.
 *
 * @return array<int,array{category:string,league:string,home:string,away:string,
 *               odds_home:float,odds_draw:?float,odds_away:float,starts_in_hours:int}>
 */
function odds_feed_fetch(): array {
    $j = fn(float $base) => round($base + mt_rand(-20, 20) / 100, 2); // ±0.20 jitter

    return [
        ['category'=>'football','league'=>'English Premier League','home'=>'Arsenal','away'=>'Chelsea',
         'odds_home'=>$j(2.10),'odds_draw'=>$j(3.30),'odds_away'=>$j(3.40),'starts_in_hours'=>2],
        ['category'=>'football','league'=>'English Premier League','home'=>'Man City','away'=>'Liverpool',
         'odds_home'=>$j(1.95),'odds_draw'=>$j(3.60),'odds_away'=>$j(3.80),'starts_in_hours'=>5],
        ['category'=>'football','league'=>'Castle Lager PSL','home'=>'Highlanders','away'=>'Dynamos',
         'odds_home'=>$j(2.45),'odds_draw'=>$j(3.10),'odds_away'=>$j(2.90),'starts_in_hours'=>26],
        ['category'=>'football','league'=>'Castle Lager PSL','home'=>'FC Platinum','away'=>'Chicken Inn',
         'odds_home'=>$j(1.80),'odds_draw'=>$j(3.20),'odds_away'=>$j(4.50),'starts_in_hours'=>28],
        ['category'=>'football','league'=>'UEFA Champions League','home'=>'Real Madrid','away'=>'Bayern',
         'odds_home'=>$j(2.30),'odds_draw'=>$j(3.50),'odds_away'=>$j(2.95),'starts_in_hours'=>72],
        ['category'=>'football','league'=>'La Liga','home'=>'Barcelona','away'=>'Sevilla',
         'odds_home'=>$j(1.65),'odds_draw'=>$j(3.90),'odds_away'=>$j(5.20),'starts_in_hours'=>50],
        ['category'=>'basketball','league'=>'NBA','home'=>'Lakers','away'=>'Celtics',
         'odds_home'=>$j(1.90),'odds_draw'=>null,'odds_away'=>$j(1.90),'starts_in_hours'=>6],
    ];
}

/**
 * Upsert the fetched slate into the events table.
 * - Existing OPEN event with the same home/away/league  -> odds are refreshed.
 * - Otherwise a new open event is inserted.
 * Settled/locked events are never touched.
 *
 * @return array{inserted:int,updated:int,fetched:int}
 */
function odds_feed_sync(PDO $pdo): array {
    $rows = odds_feed_fetch();
    $inserted = 0; $updated = 0;

    $find = $pdo->prepare(
        'SELECT id FROM events WHERE home = ? AND away = ? AND league = ? AND status = "open" LIMIT 1'
    );
    $upd = $pdo->prepare(
        'UPDATE events SET odds_home = ?, odds_draw = ?, odds_away = ? WHERE id = ?'
    );
    $ins = $pdo->prepare(
        'INSERT INTO events (category, league, home, away, odds_home, odds_draw, odds_away, starts_at, status)
         VALUES (?,?,?,?,?,?,?,?, "open")'
    );

    foreach ($rows as $r) {
        $find->execute([$r['home'], $r['away'], $r['league']]);
        $id = $find->fetchColumn();
        if ($id) {
            $upd->execute([$r['odds_home'], $r['odds_draw'], $r['odds_away'], $id]);
            $updated++;
        } else {
            $startsAt = date('Y-m-d H:i:s', time() + $r['starts_in_hours'] * 3600);
            $ins->execute([$r['category'], $r['league'], $r['home'], $r['away'],
                           $r['odds_home'], $r['odds_draw'], $r['odds_away'], $startsAt]);
            $inserted++;
        }
    }

    return ['inserted' => $inserted, 'updated' => $updated, 'fetched' => count($rows)];
}
