<?php
require_once __DIR__ . '/includes/functions.php';
require_once __DIR__ . '/includes/auth.php';
auth_boot();
require_role('distributor');

if (is_post()) {
    switch (post('action')) {
        case 'biz-new':
            if (post('name') === '' || post('owner_email') === '' || post('owner_password') === '') {
                redirect('distributor.php', 'Name, owner email and password are required.');
            }
            if (one('SELECT id FROM users WHERE email = ?', [post('owner_email')])) {
                redirect('distributor.php', 'That owner email is already in use.');
            }
            $bid = insert('INSERT INTO businesses (name, contact_email, plan, status, trial_ends, created_at)
                           VALUES (?,?,?,?,?,?)',
                [post('name'), post('owner_email'), post('plan', 'Trial'), 'active',
                 post('plan') === 'Trial' ? date('Y-m-d', strtotime('+30 days')) : null, today()]);
            insert('INSERT INTO users (business_id, name, email, password_hash, role, created_at) VALUES (?,?,?,?,?,?)',
                [$bid, post('owner_name', 'Business Owner'), post('owner_email'),
                 password_hash(post('owner_password'), PASSWORD_BCRYPT), 'business', today()]);
            redirect('distributor.php', 'Business "' . post('name') . '" provisioned with a login.');
        case 'biz-status':
            q('UPDATE businesses SET status = ? WHERE id = ?',
                [post('status') === 'suspended' ? 'suspended' : 'active', (int) post('id')]);
            redirect('distributor.php', 'Subscription updated.');
        case 'biz-plan':
            q('UPDATE businesses SET plan = ? WHERE id = ?', [post('plan'), (int) post('id')]);
            redirect('distributor.php', 'Plan changed.');
        case 'biz-del':
            q('DELETE FROM businesses WHERE id = ?', [(int) post('id')]);
            redirect('distributor.php', 'Business removed.');
    }
    redirect('distributor.php');
}

$pageTitle = 'Distributor Console';
require __DIR__ . '/includes/header.php';

$biz = rows('SELECT * FROM businesses ORDER BY name');
$total = count($biz);
$active = count(array_filter($biz, fn($b) => $b['status'] === 'active'));
$suspended = $total - $active;
$trials = count(array_filter($biz, fn($b) => $b['plan'] === 'Trial'));
$totalUsers = (int) scalar('SELECT COUNT(*) FROM users WHERE role = ?', ['business']);
$cutoff7 = date('Y-m-d H:i:s', strtotime('-7 days'));
$activeUsers = (int) scalar('SELECT COUNT(DISTINCT user_id) FROM usage_log WHERE at >= ?', [$cutoff7]);
$recent = rows(
    'SELECT u.name AS uname, b.name AS bname, l.page, l.action, l.at
       FROM usage_log l
       LEFT JOIN users u ON u.id = l.user_id
       LEFT JOIN businesses b ON b.id = l.business_id
      ORDER BY l.id DESC LIMIT 15');
$planBadge = fn($p) => ['Trial' => 'b-amber', 'Starter' => 'b-blue', 'Professional' => 'b-gold', 'Enterprise' => 'b-green'][$p] ?? 'b-grey';
?>
<div class="view-head">
  <div><h1>Distributor Console</h1>
    <div class="sub">Subscribers, plans and live usage of the platform.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('biz-form').showModal()">+ Provision Business</button></div>
</div>

<div class="grid grid-4">
  <div class="stat accent"><div class="label">Businesses</div><div class="value"><?= $total ?></div>
    <div class="hint"><?= $trials ?> on trial</div></div>
  <div class="stat good"><div class="label">Active Subscriptions</div><div class="value"><?= $active ?></div></div>
  <div class="stat <?= $suspended ? 'bad' : '' ?>"><div class="label">Suspended</div><div class="value"><?= $suspended ?></div></div>
  <div class="stat"><div class="label">Active Users (7d)</div><div class="value"><?= $activeUsers ?></div>
    <div class="hint"><?= $totalUsers ?> business users total</div></div>
</div>

<div class="card mt">
  <h3>Subscribers</h3>
  <?php if ($biz): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Business</th><th>Owner contact</th><th>Plan</th><th class="num">Users</th><th>Last active</th><th>Status</th><th></th></tr>
      <?php foreach ($biz as $b):
        $users = (int) scalar('SELECT COUNT(*) FROM users WHERE business_id = ?', [(int) $b['id']]); ?>
        <tr>
          <td><strong><?= e($b['name']) ?></strong>
            <div class="muted" style="font-size:11px">since <?= e($b['created_at']) ?><?= $b['trial_ends'] ? ' · trial ends ' . e($b['trial_ends']) : '' ?></div></td>
          <td><?= e($b['contact_email'] ?: '—') ?></td>
          <td>
            <form method="post" style="display:inline">
              <input type="hidden" name="action" value="biz-plan"><input type="hidden" name="id" value="<?= $b['id'] ?>">
              <select name="plan" onchange="this.form.submit()" class="mini-select">
                <?php foreach (['Trial','Starter','Professional','Enterprise'] as $pl): ?>
                  <option <?= $pl === $b['plan'] ? 'selected' : '' ?>><?= $pl ?></option>
                <?php endforeach; ?>
              </select>
            </form>
            <?= badge($b['plan'], $planBadge($b['plan'])) ?>
          </td>
          <td class="num"><?= $users ?></td>
          <td><?= e(ago($b['last_active'])) ?></td>
          <td><?= $b['status'] === 'active' ? badge('active', 'b-green') : badge('suspended', 'b-red') ?></td>
          <td style="white-space:nowrap">
            <form method="post" style="display:inline">
              <input type="hidden" name="action" value="biz-status"><input type="hidden" name="id" value="<?= $b['id'] ?>">
              <input type="hidden" name="status" value="<?= $b['status'] === 'active' ? 'suspended' : 'active' ?>">
              <button class="btn btn-icon" title="<?= $b['status'] === 'active' ? 'suspend' : 'reactivate' ?>"><?= $b['status'] === 'active' ? '⏸' : '▶' ?></button>
            </form>
            <form method="post" style="display:inline" data-confirm="Delete this business and all its users?">
              <input type="hidden" name="action" value="biz-del"><input type="hidden" name="id" value="<?= $b['id'] ?>">
              <button class="btn btn-icon">✕</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No businesses yet. Provision your first subscriber.</div><?php endif; ?>
</div>

<div class="card mt">
  <h3>Who's Using the System — recent activity</h3>
  <?php if ($recent): ?>
    <div class="tbl-wrap"><table>
      <tr><th>User</th><th>Business</th><th>Action</th><th>Page</th><th>When</th></tr>
      <?php foreach ($recent as $r): ?>
        <tr><td><?= e($r['uname'] ?: '—') ?></td><td><?= e($r['bname'] ?: '—') ?></td>
          <td><?= $r['action'] === 'login' ? badge('login', 'b-green') : badge('visit', 'b-grey') ?></td>
          <td class="mono"><?= e($r['page']) ?></td><td><?= e(ago($r['at'])) ?></td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No activity recorded yet.</div><?php endif; ?>
</div>

<dialog id="biz-form" class="dlg"><form method="post">
  <h2>Provision a Business</h2><input type="hidden" name="action" value="biz-new">
  <label>Business name *</label><input name="name" required>
  <div class="form-row">
    <div><label>Plan</label><select name="plan"><option>Trial</option><option>Starter</option><option selected>Professional</option><option>Enterprise</option></select></div>
    <div><label>Owner full name</label><input name="owner_name" placeholder="Business Owner"></div>
  </div>
  <div class="form-row">
    <div><label>Owner login email *</label><input name="owner_email" type="email" required></div>
    <div><label>Temp password *</label><input name="owner_password" required></div>
  </div>
  <div class="muted" style="font-size:11.5px;margin-top:6px">The owner signs in with this email/password on the same login page and lands on the business app.</div>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Create login</button></div>
</form></dialog>

<?php require __DIR__ . '/includes/footer.php'; ?>
