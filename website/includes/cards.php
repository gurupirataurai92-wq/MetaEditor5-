<?php
/** Card markup shared by the home page and the two catalogue pages. */
if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }

function vehicle_card(array $v): void
{
    [$statusText, $statusClass] = status_label($v['status']);
    $title = $v['year'] . ' ' . $v['make'] . ' ' . $v['model'];
    $link  = url('vehicle.php?ref=' . urlencode($v['ref']));
    ?>
    <article class="card">
      <a class="card-media" href="<?= e($link) ?>">
        <img src="<?= e(vehicle_photo($v)) ?>" alt="<?= e($title) ?>" loading="lazy" width="800" height="500">
        <span class="card-flag <?= e($statusClass) ?>"><?= e($statusText) ?></span>
        <?php if ((int)($v['photo_count'] ?? 0) > 1): ?>
          <span class="card-count"><?= (int)$v['photo_count'] ?> photos</span>
        <?php endif; ?>
      </a>
      <div class="card-body">
        <h3 class="card-title"><a href="<?= e($link) ?>"><?= e($title) ?></a></h3>
        <p class="card-sub">Ref <?= e($v['ref']) ?> · Auction grade <?= e($v['grade']) ?> · <?= e($v['steering']) ?></p>
        <ul class="spec-list">
          <li><span class="k">Engine</span><span class="v"><?= e($v['engine'] ?: '—') ?></span></li>
          <li><span class="k">Fuel</span><span class="v"><?= e($v['fuel']) ?></span></li>
          <li><span class="k">Gearbox</span><span class="v"><?= e($v['transmission']) ?></span></li>
          <li><span class="k">Drive</span><span class="v"><?= e($v['drive']) ?></span></li>
          <li><span class="k">Mileage</span><span class="v"><?= e(km($v['mileage'])) ?></span></li>
          <li><span class="k">Colour</span><span class="v"><?= e($v['colour'] ?: '—') ?></span></li>
        </ul>
        <?php if (!empty($v['note'])): ?><p class="card-sub"><?= e($v['note']) ?></p><?php endif; ?>
        <div class="card-foot">
          <span class="price"><?= e(money($v['price'])) ?><small>CIF, duty not included</small></span>
          <a class="btn btn--primary btn--sm" href="<?= e($link) ?>">View</a>
        </div>
      </div>
    </article>
    <?php
}

function part_card(array $p): void
{
    [$stockText, $stockClass] = $p['stock'] === 'in-stock'
        ? ['In stock', 'card-flag--stock'] : ['On order', 'card-flag--order'];
    [$typeText, $typeClass] = part_type_label($p['type']);
    $link = url('part.php?ref=' . urlencode($p['ref']));
    ?>
    <article class="card part-card">
      <a class="card-media" href="<?= e($link) ?>">
        <img src="<?= e(part_photo($p)) ?>" alt="<?= e($p['name']) ?>" loading="lazy" width="800" height="500">
        <span class="card-flag <?= e($stockClass) ?>"><?= e($stockText) ?></span>
        <?php if ((int)($p['photo_count'] ?? 0) > 1): ?>
          <span class="card-count"><?= (int)$p['photo_count'] ?> photos</span>
        <?php endif; ?>
      </a>
      <div class="card-body">
        <h3 class="card-title"><a href="<?= e($link) ?>"><?= e($p['name']) ?></a></h3>
        <p class="card-sub">SKU <?= e($p['sku']) ?> · <?= e($p['brand']) ?></p>
        <div class="part-meta">
          <span class="tag <?= e($typeClass) ?>"><?= e($typeText) ?></span>
          <span class="tag"><?= e(size_label($p['size'])) ?></span>
        </div>
        <p class="fit-list"><b>Fits:</b> <?= e($p['fits']) ?></p>
        <?php if (!empty($p['note'])): ?><p class="card-sub"><?= e($p['note']) ?></p><?php endif; ?>
        <div class="card-foot">
          <span class="price"><?= e(money($p['price'])) ?><small>ex-works, per unit</small></span>
          <a class="btn btn--primary btn--sm" href="<?= e($link) ?>">View</a>
        </div>
      </div>
    </article>
    <?php
}

/** "Showing 1–12 of 40" plus previous/next links. */
function pager(int $total, int $page, int $perPage): void
{
    $pages = max(1, (int)ceil($total / $perPage));
    if ($pages < 2) { return; }
    ?>
    <nav class="pager" aria-label="Pages">
      <?php if ($page > 1): ?>
        <a class="btn btn--ghost btn--sm" href="<?= e(with_query(['page' => $page - 1])) ?>">← Previous</a>
      <?php endif; ?>
      <span>Page <?= $page ?> of <?= $pages ?></span>
      <?php if ($page < $pages): ?>
        <a class="btn btn--ghost btn--sm" href="<?= e(with_query(['page' => $page + 1])) ?>">Next →</a>
      <?php endif; ?>
    </nav>
    <?php
}
