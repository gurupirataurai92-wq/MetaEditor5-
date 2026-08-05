<?php
declare(strict_types=1);

/**
 * Front controller — every api/... request lands here.
 *
 * Apache rewrites api/anything to this file (see api/.htaccess), and the
 * router below dispatches on method + path.
 */

namespace Haulr;

use Haulr\Controllers\{AuthController, ManagerController, OfferController, OperatorController, TrackingController, TripController};

// Never render a PHP error, warning or stack trace into a response: they leak
// file paths, SQL and version numbers. Everything is caught and turned into a
// clean JSON error at the bottom of this file.
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

spl_autoload_register(static function (string $class): void {
    $prefix = 'Haulr\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $relative = str_replace('\\', '/', substr($class, strlen($prefix)));
    $file = dirname(__DIR__) . '/app/' . $relative . '.php';
    if (is_file($file)) {
        require_once $file;
    }
});

Security::sendSecurityHeaders();

/* ==========================================================================
   Request parsing
   ========================================================================== */

$method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));

// The path after .../api/ — works whether the app sits at the web root or in
// a subfolder like htdocs/haulr.
$raw  = (string) ($_GET['_route'] ?? '');
if ($raw === '') {
    $uri  = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH) ?: '/';
    $pos  = strpos($uri, '/api/');
    $raw  = $pos === false ? '' : substr($uri, $pos + 5);
}
$path = trim($raw, '/');
$segments = $path === '' ? [] : explode('/', $path);

/** JSON body for write requests. */
$body = [];
if (in_array($method, ['POST', 'PATCH', 'PUT', 'DELETE'], true)) {
    $rawBody = file_get_contents('php://input') ?: '';
    if (strlen($rawBody) > 131072) { // 128 KB
        Response::error('Request body is too large.', 413);
    }
    if ($rawBody !== '') {
        $decoded = json_decode($rawBody, true);
        if (!is_array($decoded)) {
            Response::error('Request body is not valid JSON.');
        }
        $body = $decoded;
    }
}

$query = $_GET;
unset($query['_route']);

/**
 * Match the path against a pattern like 'trips/{id}/offers'.
 * Returns the captured numeric ids, or null when it does not match.
 */
function match_route(array $segments, string $pattern): ?array
{
    $parts = explode('/', $pattern);
    if (count($parts) !== count($segments)) {
        return null;
    }

    $params = [];
    foreach ($parts as $i => $part) {
        if ($part === '{id}') {
            if (!ctype_digit($segments[$i])) {
                return null;
            }
            $params[] = (int) $segments[$i];
            continue;
        }
        if ($part !== $segments[$i]) {
            return null;
        }
    }
    return $params;
}

/* ==========================================================================
   Routing
   ========================================================================== */

try {
    Security::pruneOldRecords();

    // CSRF is checked once, centrally, before any handler runs.
    Auth::checkCsrf($method);

    $auth     = new AuthController();
    $trips    = new TripController();
    $offers   = new OfferController();
    $operator = new OperatorController();
    $tracking = new TrackingController();
    $manager  = new ManagerController();

    // ---- meta / health ----------------------------------------------
    if ($method === 'GET' && $path === 'meta') {
        Response::json([
            'currency'            => Config::get('currency'),
            'vehicleClasses'      => Domain::VEHICLE_CLASSES,
            'categories'          => Domain::CATEGORIES,
            'paymentMethods'      => Domain::PAYMENT_METHODS,
            'statusLabels'        => Domain::STATUS_LABELS,
            'helperFeePerPerson'  => Domain::HELPER_FEE_PER_PERSON,
            'floorFee'            => Domain::FLOOR_FEE,
            'dispatchRadiusKm'    => Config::get('dispatch_radius_km', 25),
        ]);
    }

    if ($method === 'GET' && $path === 'health') {
        Response::json(['ok' => true, 'installed' => Database::isInstalled(), 'php' => PHP_VERSION]);
    }

    if ($method === 'GET' && $path === 'public/activity') {
        $operator->publicActivity();
    }

    // ---- events (the polling feed that replaces WebSockets) ----------
    if ($method === 'GET' && $path === 'events') {
        $user  = Auth::requireAuth();
        $since = (int) ($query['since'] ?? 0);
        Response::json(Events::pollFor($user, max(0, $since)));
    }

    // ---- auth --------------------------------------------------------
    match (true) {
        $method === 'POST' && $path === 'auth/register'         => $auth->register($body),
        $method === 'POST' && $path === 'auth/login'            => $auth->login($body),
        $method === 'POST' && $path === 'auth/login/2fa'        => $auth->loginTwoFactor($body),
        $method === 'POST' && $path === 'auth/logout'           => $auth->logout(),
        $method === 'GET'  && $path === 'auth/me'               => $auth->me(),
        $method === 'PATCH' && $path === 'auth/me'              => $auth->updateProfile($body),
        $method === 'GET'  && $path === 'auth/sessions'         => $auth->sessions(),
        $method === 'POST' && $path === 'auth/sessions/revoke-others' => $auth->revokeOtherSessions(),
        $method === 'POST' && $path === 'auth/password'         => $auth->changePassword($body),
        $method === 'POST' && $path === 'auth/2fa/start'        => $auth->startTwoFactor(),
        $method === 'POST' && $path === 'auth/2fa/enable'       => $auth->enableTwoFactor($body),
        $method === 'POST' && $path === 'auth/2fa/disable'      => $auth->disableTwoFactor($body),
        $method === 'GET'  && $path === 'auth/policy'           => $auth->policy(),
        default => null,
    };

    // ---- quote / trips ----------------------------------------------
    if ($method === 'POST' && $path === 'quote') {
        $trips->quote($body);
    }
    if ($method === 'POST' && $path === 'trips') {
        $trips->create($body);
    }
    if ($method === 'GET' && $path === 'trips') {
        $trips->index($query);
    }

    if (($p = match_route($segments, 'trips/{id}')) !== null && $method === 'GET') {
        $trips->show($p[0]);
    }
    if (($p = match_route($segments, 'trips/{id}/status')) !== null && $method === 'POST') {
        $trips->updateStatus($p[0], $body);
    }
    if (($p = match_route($segments, 'trips/{id}/cancel')) !== null && $method === 'POST') {
        $trips->cancel($p[0], $body);
    }
    if (($p = match_route($segments, 'trips/{id}/release')) !== null && $method === 'POST') {
        $trips->release($p[0], $body);
    }
    if (($p = match_route($segments, 'trips/{id}/rate')) !== null && $method === 'POST') {
        $trips->rate($p[0], $body);
    }
    if (($p = match_route($segments, 'trips/{id}/events')) !== null && $method === 'GET') {
        $trips->events($p[0]);
    }
    if (($p = match_route($segments, 'trips/{id}/messages')) !== null) {
        if ($method === 'GET') {
            $trips->messages($p[0]);
        }
        if ($method === 'POST') {
            $trips->sendMessage($p[0], $body);
        }
    }

    // ---- offers ------------------------------------------------------
    if (($p = match_route($segments, 'trips/{id}/accept')) !== null && $method === 'POST') {
        $offers->accept($p[0]);
    }
    if (($p = match_route($segments, 'trips/{id}/offers')) !== null) {
        if ($method === 'POST') {
            $offers->create($p[0], $body);
        }
        if ($method === 'GET') {
            $offers->index($p[0]);
        }
    }
    if (($p = match_route($segments, 'offers/{id}/accept')) !== null && $method === 'POST') {
        $offers->acceptOffer($p[0]);
    }
    if (($p = match_route($segments, 'offers/{id}')) !== null && $method === 'DELETE') {
        $offers->withdraw($p[0]);
    }

    // ---- tracking ----------------------------------------------------
    if (($p = match_route($segments, 'trips/{id}/location')) !== null && $method === 'POST') {
        $tracking->push($p[0], $body);
    }
    if (($p = match_route($segments, 'trips/{id}/track')) !== null && $method === 'GET') {
        $tracking->track($p[0]);
    }

    // ---- operator ----------------------------------------------------
    match (true) {
        $method === 'POST'  && $path === 'operator/status'   => $operator->setDuty($body),
        $method === 'PATCH' && $path === 'operator/profile'  => $operator->updateProfile($body),
        $method === 'GET'   && $path === 'operator/board'    => $operator->board($query),
        $method === 'GET'   && $path === 'operator/stats'    => $operator->stats(),
        $method === 'GET'   && $path === 'operators/nearby'  => $operator->nearby($query),
        default => null,
    };

    // ---- manager -----------------------------------------------------
    match (true) {
        $method === 'GET'  && $path === 'manager/overview' => $manager->overview(),
        $method === 'GET'  && $path === 'manager/trips'    => $manager->trips($query),
        $method === 'GET'  && $path === 'manager/fleet'    => $manager->fleet(),
        $method === 'GET'  && $path === 'manager/users'    => $manager->users($query),
        $method === 'GET'  && $path === 'manager/audit'    => $manager->audit($query),
        $method === 'GET'  && $path === 'manager/security' => $manager->security(),
        $method === 'POST' && $path === 'manager/managers' => $manager->createManager($body),
        default => null,
    };

    if (($p = match_route($segments, 'manager/trips/{id}')) !== null && $method === 'GET') {
        $manager->trip($p[0]);
    }
    if (($p = match_route($segments, 'manager/trips/{id}/reassign')) !== null && $method === 'POST') {
        $manager->reassign($p[0], $body);
    }
    if (($p = match_route($segments, 'manager/trips/{id}/cancel')) !== null && $method === 'POST') {
        $manager->cancelTrip($p[0], $body);
    }
    if (($p = match_route($segments, 'manager/trips/{id}/flag')) !== null && $method === 'POST') {
        $manager->flagTrip($p[0], $body);
    }
    if (($p = match_route($segments, 'manager/trips/{id}/candidates')) !== null && $method === 'GET') {
        $manager->candidates($p[0]);
    }
    if (($p = match_route($segments, 'manager/users/{id}/suspend')) !== null && $method === 'POST') {
        $manager->suspendUser($p[0], $body);
    }
    if (($p = match_route($segments, 'manager/users/{id}/reinstate')) !== null && $method === 'POST') {
        $manager->reinstateUser($p[0]);
    }
    if (($p = match_route($segments, 'manager/users/{id}/force-logout')) !== null && $method === 'POST') {
        $manager->forceLogout($p[0]);
    }
    if (($p = match_route($segments, 'manager/operators/{id}/verify')) !== null && $method === 'POST') {
        $manager->verifyOperator($p[0], $body);
    }

    Response::error('No such endpoint.', 404);
} catch (ValidationError $e) {
    Response::error($e->getMessage(), 400);
} catch (\Throwable $e) {
    // Log the detail for whoever runs the server; tell the caller nothing that
    // would help them map the internals.
    error_log('[haulr] ' . $e::class . ': ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());

    if (!Database::isInstalled()) {
        Response::error(
            'The database is not set up yet. Import database/schema.sql in phpMyAdmin, '
            . 'then run database/seed.php.',
            503
        );
    }
    Response::error('Something went wrong on our side.', 500);
}
