/* ==========================================================================
   Manager account settings
   --------------------------------------------------------------------------
   IMPORTANT — read this before you rely on the sign-in below.

   This site is a set of static files with no server behind it, so the sign-in
   on manager.html can only HIDE the manager screens. It cannot protect them.
   Anyone who opens this file in a browser can read the settings, and anyone
   who knows the address can look at the page source. Treat it as a lock on a
   drawer, not a safe.

   What that means in practice:
     • Never put anything confidential into the manager panel.
       Everything you add there ends up published on a public website anyway.
     • Do not reuse a password you use anywhere else.
     • If you need real accounts — several staff, audit trail, genuine access
       control — the site needs a server back end. See website/README.md.

   To change the password: sign in, open the "Account" tab, type the new
   password, and paste the generated line over PASSWORD_HASH below.

   Default sign-in — CHANGE THIS BEFORE THE SITE GOES PUBLIC:
       user:     manager
       password: ChangeMe2026!
   ========================================================================== */

window.MANAGER_CONFIG = {
  /* Sign-in name. Change it if you like. */
  USERNAME: 'manager',

  /* SHA-256 of (SALT + password). Never store the password itself here. */
  SALT: 'lymond-services-v1',
  PASSWORD_HASH: '4af1420d877c6832911158d684df0c39b4a7d8f9eaee5735e41354b97548cee3',

  /* Sign out automatically after this many minutes with no activity. */
  IDLE_TIMEOUT_MINUTES: 30,

  /* Uploaded photos are shrunk before saving, so the site stays fast and the
     browser does not run out of room. Longest side, in pixels. */
  PHOTO_MAX_EDGE: 1400,
  PHOTO_QUALITY: 0.78,
  PHOTOS_PER_ITEM: 8
};
