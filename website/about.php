<?php
/** How importing works: process, landed-cost example, auction grades, FAQ. */
require __DIR__ . '/includes/bootstrap.php';

$name = setting('company_name');
$page_title = 'How importing works — ' . $name;
$page_desc  = 'How we import Japanese vehicles: auction bidding, inspection grades, shipping, '
            . 'clearing and duty — plus answers to the questions buyers ask most.';
$nav = 'about';
require __DIR__ . '/includes/header.php';
?>


  <section class="page-hero">
    <div class="wrap">
      <p class="crumbs"><a href="<?= e(url('index.php')) ?>">Home</a> / How it works</p>
      <h1>How importing works</h1>
      <p>Buying a vehicle from eight thousand kilometres away only works if the process is boring
         and predictable. Here is exactly how ours runs, what it costs, and where the risks sit.</p>
    </div>
  </section>

  <!-- ---------------------------------------------------------- story -->
  <section class="section">
    <div class="wrap">
      <div class="grid grid--2 grid--top">
        <div>
          <span class="eyebrow">Who we are</span>
          <h2>Twelve years of moving cars and parts</h2>
          <p><?= e($name) ?> started as a two-person parts counter and grew into a full import
             desk. We buy from Japanese auction houses and established exporters — BE&nbsp;FORWARD
             among them — because their inspection sheets and export paperwork are consistent, which
             is what keeps a shipment from stalling at the port.</p>
          <p>The part of the business customers actually feel is the second half: the spares. A cheap
             import stops being cheap the day you cannot get a suspension arm for it. So we run the
             parts counter alongside the import desk, and we keep buying for a vehicle long after it
             has been handed over.</p>
          <ul>
            <li>Vehicles: sedans, hatchbacks, SUVs, vans, pickups and commercial trucks</li>
            <li>Parts: genuine, OEM, aftermarket and Japan-used, small to large</li>
            <li>Services: auction bidding, shipping, clearing, registration and trade accounts</li>
          </ul>
          <div class="btn-row" style="margin-top:20px">
            <a class="btn btn--primary" href="<?= e(url('contact.php')) ?>">Talk to the import desk</a>
          </div>
        </div>

        <div>
          <div class="panel">
            <h3>Indicative landed-cost example</h3>
            <p class="card-sub">A 2017 mid-size SUV, RoRo shipped. Figures are illustrative — your
               written quotation will carry the real numbers for your country and port.</p>
            <div class="table-scroll" style="margin-top:14px">
              <table>
                <thead><tr><th>Line</th><th>Amount</th></tr></thead>
                <tbody>
                  <tr><td>Vehicle price (FOB Japan)</td><td>$12,600</td></tr>
                  <tr><td>Ocean freight</td><td>$1,450</td></tr>
                  <tr><td>Marine insurance</td><td>$180</td></tr>
                  <tr><td><b>CIF total (what we quote)</b></td><td><b>$14,230</b></td></tr>
                  <tr><td>Import duty &amp; VAT</td><td>Per your country's tariff</td></tr>
                  <tr><td>Port charges &amp; clearing</td><td>Quoted at booking</td></tr>
                  <tr><td>Registration &amp; plates</td><td>Quoted at booking</td></tr>
                </tbody>
              </table>
            </div>
            <div class="note" style="margin-top:16px">
              <p>Duty is assessed by your customs authority on their own valuation, not on our
                 invoice. We give you a realistic estimate up front, but the final assessment is
                 always theirs.</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- --------------------------------------------------------- process -->
  <section class="section section--dark">
    <div class="wrap">
      <div class="section-head">
        <span class="eyebrow">Step by step</span>
        <h2>From your brief to your number plate</h2>
        <p>Typical timeline: 3 to 6 weeks for a unit in stock, 6 to 10 weeks for an auction purchase.</p>
      </div>

      <div class="grid grid--2">
        <div class="steps">
          <div class="step">
            <h3>Brief and budget</h3>
            <p>Model, year range, maximum mileage, gearbox, and the ceiling you are willing to pay
               landed. We tell you honestly what that budget buys.</p>
          </div>
          <div class="step">
            <h3>Sourcing and auction sheets</h3>
            <p>We send matching units with their auction sheets and inspector grades. You see the
               noted dents, scratches and repair marks before deciding.</p>
          </div>
          <div class="step">
            <h3>Bidding or reservation</h3>
            <p>For auction units we bid against your agreed maximum. For stock units we reserve
               against a deposit. You are never bound to a bid you did not approve.</p>
          </div>
          <div class="step">
            <h3>Proforma invoice and payment</h3>
            <p>A single invoice showing FOB, freight and insurance. Payment by bank transfer to the
               company account named on the invoice — never to an individual.</p>
          </div>
        </div>

        <div class="steps">
          <div class="step">
            <h3>Inspection and loading</h3>
            <p>Pre-shipment inspection where your country requires it (JEVIC, QISJ and similar),
               then RoRo or container loading at the port of departure.</p>
          </div>
          <div class="step">
            <h3>Documents in transit</h3>
            <p>Bill of lading, export certificate with English translation, inspection certificate
               and invoice couriered while the vessel sails.</p>
          </div>
          <div class="step">
            <h3>Clearing and duty</h3>
            <p>Our clearing desk lodges the entry, settles port charges and walks the duty
               assessment through customs.</p>
          </div>
          <div class="step">
            <h3>Handover and aftercare</h3>
            <p>Registration, plates, a first service with fresh filters and fluids, and a parts
               account for whatever comes next.</p>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- ------------------------------------------------------------ grades -->
  <section class="section section--alt">
    <div class="wrap">
      <div class="section-head">
        <span class="eyebrow">Auction grades</span>
        <h2>What the inspector's score actually means</h2>
        <p>Japanese auction houses grade every vehicle before it goes under the hammer. Learning to
           read the sheet is the single most useful thing an importer can teach you.</p>
      </div>

      <div class="table-scroll">
        <table>
          <thead>
            <tr><th>Grade</th><th>Condition</th><th>Sensible for</th></tr>
          </thead>
          <tbody>
            <tr><td><b>5 / 4.5</b></td><td>Near-new to excellent. Very low mileage, no meaningful damage.</td><td>Buyers who want showroom condition and will pay for it.</td></tr>
            <tr><td><b>4</b></td><td>Clean used unit. Minor scratches, everything works.</td><td>The mainstream choice — best balance of price and condition.</td></tr>
            <tr><td><b>3.5</b></td><td>Honest wear, small dents or panel marks noted on the sheet.</td><td>Value buyers and commercial use where cosmetics matter less.</td></tr>
            <tr><td><b>3 and below</b></td><td>Visible damage or high mileage.</td><td>Rarely worth importing once freight and duty are added.</td></tr>
            <tr><td><b>R / RA</b></td><td>Repaired accident history, disclosed on the sheet.</td><td>Only with a full explanation from us — and usually we advise against it.</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </section>

  <!-- --------------------------------------------------------------- faq -->
  <section class="section" id="faq">
    <div class="wrap">
      <div class="section-head">
        <span class="eyebrow">FAQ</span>
        <h2>Questions we get every week</h2>
      </div>

      <div style="max-width:860px">
        <details class="faq">
          <summary>Do you sell BE FORWARD cars?</summary>
          <p>We source vehicles from several Japanese exporters and auction houses, and BE&nbsp;FORWARD
             is one of the channels we buy through. We are an independent company — not an agent,
             branch or franchise of BE&nbsp;FORWARD or any other exporter. What we add is local
             clearing, registration, and a parts counter that keeps supporting the vehicle after
             delivery.</p>
        </details>

        <details class="faq">
          <summary>Can I import a vehicle older than eight years?</summary>
          <p>That depends entirely on your country's rules. Many markets cap the age of imported
             used vehicles or apply a penalty duty above a certain age. Tell us where the vehicle
             will be registered and we will confirm the limit before you commit to anything.</p>
        </details>

        <details class="faq">
          <summary>How do I pay, and is a deposit refundable?</summary>
          <p>Bank transfer to the company account printed on your proforma invoice. We do not accept
             payment to personal accounts, and you should be suspicious of any exporter who asks for
             one. Reservation deposits are refundable until we place a bid or issue a booking; after
             that they are applied to the purchase.</p>
        </details>

        <details class="faq">
          <summary>What if the vehicle arrives different from the description?</summary>
          <p>The auction sheet is the reference document, and you receive it before purchase. If a
             delivered unit does not match the sheet in a material way, raise it within seven days of
             collection with photographs and we will resolve it — repair, part replacement or, in a
             genuine misdescription, refund.</p>
        </details>

        <details class="faq">
          <summary>Do you supply parts for vehicles I did not buy from you?</summary>
          <p>Yes — most of our parts customers bought their vehicle somewhere else. Send the chassis
             number and we will quote regardless of where the car came from.</p>
        </details>

        <details class="faq">
          <summary>How small is "small" when it comes to parts?</summary>
          <p>Single clips, grommets, bulbs, sensors and washers — items worth a couple of dollars. We
             will happily quote them, and we consolidate small orders into one shipment so the
             freight makes sense.</p>
        </details>

        <details class="faq">
          <summary>Is there a warranty on used engines and gearboxes?</summary>
          <p>Japan-used engines, gearboxes and differentials carry a three-month exchange warranty
             against internal failure, provided they are fitted by a competent workshop and the
             installation invoice is kept. Consumables, electrical items and damage from overheating
             or running without oil are excluded.</p>
        </details>

        <details class="faq">
          <summary>Do you deliver upcountry or across borders?</summary>
          <p>Yes. Vehicles move by car carrier or driven under a temporary permit; parts go by the
             courier or bus service you prefer. Cross-border customers receive documents suited to
             transit clearance.</p>
        </details>
      </div>
    </div>
  </section>

  <section class="section section--tight">
    <div class="wrap">
      <div class="cta-band reveal">
        <div>
          <h2>Still deciding?</h2>
          <p>Send us your budget and how you will use the vehicle. We will tell you what is realistic
             — including when importing is the wrong answer.</p>
        </div>
        <div class="btn-row">
          <a class="btn btn--accent" href="<?= e(url('contact.php')) ?>">Get honest advice</a>
        </div>
      </div>
    </div>
  </section>

<?php require __DIR__ . '/includes/footer.php'; ?>
