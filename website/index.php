<?php
require __DIR__ . '/includes/bootstrap.php';
require __DIR__ . '/includes/cards.php';

$name = setting('company_name', 'Lymond Services');

/* Featured stock: published, in the yard, newest first. */
$featured = q_all(
    "SELECT v.*,
            (SELECT p.filename FROM photos p
              WHERE p.item_type='vehicle' AND p.item_id=v.id
              ORDER BY p.sort_order, p.id LIMIT 1) AS cover,
            (SELECT COUNT(*) FROM photos p
              WHERE p.item_type='vehicle' AND p.item_id=v.id) AS photo_count
       FROM vehicles v
      WHERE v.is_published = 1 AND v.status = 'in-stock'
      ORDER BY v.updated_at DESC
      LIMIT 6"
);

$categories = q_all(
    "SELECT c.*, (SELECT COUNT(*) FROM parts p
                   WHERE p.category_id = c.id AND p.is_published = 1) AS line_count
       FROM part_categories c
      ORDER BY c.sort_order"
);

$makes = q_all("SELECT DISTINCT make FROM vehicles WHERE is_published = 1 ORDER BY make");

$page_title = $name . ' — Japanese imported cars & spare parts';
$page_desc  = 'Imported Japanese cars, vans, pickups and trucks shipped to your port, plus genuine '
            . 'and aftermarket spare parts from a single bolt to a complete engine.';
$nav = 'home';
require __DIR__ . '/includes/header.php';
?>

  <section class="hero">
    <div class="wrap">
      <div class="hero-grid">
        <div>
          <span class="eyebrow">Japan → your port → your driveway</span>
          <h1>Imported cars you can trust, and <span class="hl">every spare part</span> to keep them running.</h1>
          <p class="hero-lead">
            We import inspected Japanese vehicles through established exporters — including
            BE&nbsp;FORWARD — handle the shipping and clearing paperwork, and stock spare parts
            from a single clip to a complete engine assembly.
          </p>

          <div class="hero-badges">
            <span class="badge"><span class="dot"></span>Auction grade 3.5 and above</span>
            <span class="badge"><span class="dot"></span>Pre-shipment inspection</span>
            <span class="badge"><span class="dot"></span>Parts sourced in 48 hours</span>
          </div>

          <div class="btn-row">
            <a class="btn btn--primary" href="<?= e(url('vehicles.php')) ?>">Browse vehicles</a>
            <a class="btn btn--ghost" href="<?= e(url('parts.php')) ?>">Find a spare part</a>
          </div>
        </div>

        <div class="hero-art">
          <img src="<?= e(vehicle_photo($featured[0] ?? ['body' => 'suv'])) ?>"
               alt="Imported vehicle in stock" width="800" height="500">
        </div>
      </div>

      <div class="stats">
        <div class="stat"><b><?= e(setting('stat_vehicles')) ?></b><span>Vehicles delivered</span></div>
        <div class="stat"><b><?= e(setting('stat_parts')) ?></b><span>Part lines sourced</span></div>
        <div class="stat"><b><?= e(setting('stat_sailing')) ?></b><span>Typical sailing time</span></div>
        <div class="stat"><b><?= e(setting('stat_years')) ?></b><span>In the import trade</span></div>
      </div>
    </div>
  </section>

  <!-- --------------------------------------------------- quick search -->
  <section class="section section--tight section--alt">
    <div class="wrap">
      <div class="search-panel reveal">
        <h3>Tell us what you are looking for</h3>
        <p class="hint">Search our current stock, or send us a target spec and we will bid for it at the next Japanese auction.</p>
        <form action="<?= e(url('vehicles.php')) ?>" method="get">
          <div class="field-row">
            <div class="field">
              <label for="qs-make">Make</label>
              <select id="qs-make" name="make">
                <option value="">Any make</option>
                <?php foreach ($makes as $m): ?>
                  <option value="<?= e($m['make']) ?>"><?= e($m['make']) ?></option>
                <?php endforeach; ?>
              </select>
            </div>
            <div class="field">
              <label for="qs-body">Body type</label>
              <select id="qs-body" name="body">
                <option value="">Any body</option>
                <option value="sedan">Sedan</option>
                <option value="hatchback">Hatchback</option>
                <option value="suv">SUV / 4WD</option>
                <option value="van">Van / MPV</option>
                <option value="pickup">Pickup</option>
                <option value="truck">Truck</option>
              </select>
            </div>
            <div class="field">
              <label for="qs-budget">Budget up to (USD)</label>
              <select id="qs-budget" name="budget">
                <option value="">No limit</option>
                <option value="8000">$8,000</option>
                <option value="15000">$15,000</option>
                <option value="25000">$25,000</option>
                <option value="40000">$40,000</option>
              </select>
            </div>
            <div class="field">
              <label aria-hidden="true">&nbsp;</label>
              <button class="btn btn--primary btn--block" type="submit">Search stock</button>
            </div>
          </div>
        </form>
      </div>
    </div>
  </section>

  <!-- ------------------------------------------------ featured stock -->
  <section class="section">
    <div class="wrap">
      <div class="section-head">
        <span class="eyebrow">Available now</span>
        <h2>Featured imports in stock</h2>
        <p>Every unit is inspected before it leaves Japan and comes with its auction sheet, export
           certificate and de-registration papers.</p>
      </div>

      <div class="grid grid--3 reveal">
        <?php foreach ($featured as $v) { vehicle_card($v); } ?>
        <?php if (!$featured): ?>
          <div class="empty"><h3>No stock listed yet</h3>
            <p>An operator can add vehicles from the admin area.</p></div>
        <?php endif; ?>
      </div>

      <div class="btn-row" style="margin-top:28px">
        <a class="btn btn--ghost" href="<?= e(url('vehicles.php')) ?>">See all vehicles &amp; filters</a>
      </div>
    </div>
  </section>

  <!-- ------------------------------------------------ parts overview -->
  <section class="section section--alt">
    <div class="wrap">
      <div class="section-head">
        <span class="eyebrow">Spare parts</span>
        <h2>From the smallest clip to a complete engine</h2>
        <p>Genuine, OEM, quality aftermarket and Japan-used parts. If it is not on the shelf we
           source it from our Japanese and Dubai suppliers — usually quoted within 48 hours.</p>
      </div>

      <div class="grid grid--4 reveal">
        <?php foreach ($categories as $c): ?>
          <a class="tile" href="<?= e(url('parts.php?category=' . urlencode($c['slug']))) ?>">
            <span class="tile-icon" aria-hidden="true">
              <img src="<?= e(url('assets/img/parts/' . $c['slug'] . '.svg')) ?>" alt="" width="46" height="46">
            </span>
            <h3><?= e($c['name']) ?></h3>
            <p><?= e($c['blurb']) ?></p>
            <span class="count"><?= (int)$c['line_count'] ?> lines listed</span>
          </a>
        <?php endforeach; ?>
      </div>

      <div class="note" style="margin-top:26px">
        <p><b>Can't find the part?</b> Send us your chassis number (e.g. <code>NZE141-1234567</code>)
           and a photo of the old part. We match it against the manufacturer catalogue so you get the
           right item the first time.</p>
      </div>
    </div>
  </section>

  <!-- ---------------------------------------------------- how it works -->
  <section class="section section--dark">
    <div class="wrap">
      <div class="section-head">
        <span class="eyebrow">The process</span>
        <h2>Five steps from Japan to your gate</h2>
        <p>No surprises, no hidden charges — you approve a landed-cost quotation before any money moves.</p>
      </div>

      <div class="grid grid--2">
        <div class="steps">
          <div class="step"><h3>Choose or brief</h3>
            <p>Pick a unit from our stock list, or give us a target model, year, mileage and budget.</p></div>
          <div class="step"><h3>Auction bid &amp; inspection</h3>
            <p>We bid at Japanese auctions on your behalf and send you the auction sheet with the
               inspector's grade before committing.</p></div>
          <div class="step"><h3>Payment &amp; invoice</h3>
            <p>You receive a proforma invoice showing FOB, freight and insurance. Payment by bank
               transfer to a company account only.</p></div>
        </div>
        <div class="steps">
          <div class="step"><h3>Shipping &amp; documents</h3>
            <p>RoRo or container shipping with the bill of lading, export certificate and
               translation couriered to you.</p></div>
          <div class="step"><h3>Clearing &amp; handover</h3>
            <p>Our clearing desk handles port charges, duty assessment and registration, then hands
               you the keys.</p></div>
          <div class="step" style="border-color:rgba(246,167,35,.45)"><h3>After you drive away</h3>
            <p>The same team keeps you supplied with service kits and spares for the life of the vehicle.</p></div>
        </div>
      </div>
    </div>
  </section>

  <section class="section">
    <div class="wrap">
      <div class="cta-band reveal">
        <div>
          <h2>Ready to import, or just need a part?</h2>
          <p>Send us a model and budget, or a chassis number and a photo. You will have a written
             quote in your hands within two working days.</p>
        </div>
        <div class="btn-row">
          <a class="btn btn--accent" href="<?= e(url('contact.php')) ?>">Request a quote</a>
          <a class="btn btn--ghost" target="_blank" rel="noopener"
             href="<?= e(wa_link('Hello ' . $name . ', I would like a quote.')) ?>">WhatsApp</a>
        </div>
      </div>
    </div>
  </section>

<?php require __DIR__ . '/includes/footer.php'; ?>
