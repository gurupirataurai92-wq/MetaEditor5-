# Lymond Services — company website

A static marketing and catalogue site for a business that imports Japanese vehicles (sourced
through exporters and auction houses, BE FORWARD among them) and sells spare parts of every
size, from clips and filters to complete engines and gearboxes.

No build step, no framework, no external requests — plain HTML, CSS and JavaScript. Open
`index.html` in a browser, or serve the folder:

```bash
cd website && python3 -m http.server 8000
```

## Pages

| File | Purpose |
| --- | --- |
| `index.html` | Hero, quick stock search, featured vehicles, parts categories, import process, testimonials |
| `vehicles.html` | Full vehicle stock with search, make/body/fuel/gearbox/budget filters, sorting and stock-status chips |
| `parts.html` | Parts catalogue with search, category chips, part size (small→large), part grade and availability filters |
| `about.html` | How importing works, indicative landed-cost breakdown, auction grades, FAQ |
| `contact.html` | Enquiry form with validation, direct contact details, payment-safety notice |
| `manager.html` | Manager panel — add vehicles, parts and photos, then publish them (see below) |

## Structure

```
website/
├── index.html, vehicles.html, parts.html, about.html, contact.html
├── manager.html                the manager panel
└── assets/
    ├── css/styles.css          design tokens + all component styles
    ├── css/manager.css         manager-panel styles
    ├── js/data.js              published catalogue (vehicles, parts, categories, company details)
    ├── js/main.js              nav, filtering, rendering, form validation
    ├── js/store.js             browser storage for unpublished edits and photos
    ├── js/manager-config.js    manager sign-in settings — change the password here
    ├── js/manager.js           the manager panel itself
    ├── img/                    placeholder SVG artwork
    └── img/uploads/            real photos, once published
```

## The manager panel

Open `manager.html`. The default sign-in is **manager / ChangeMe2026!** — change it before the
site is public (Account tab, then paste the generated line into `assets/js/manager-config.js`).

What it does:

- **Vehicles / Spare parts** — add, edit and delete stock, with up to 8 photos each. Photos are
  shrunk to 1400 px automatically, so a phone picture straight from the camera is fine.
- **Company details** — phone, WhatsApp, emails, address and opening hours, applied site-wide.
- **Publish** — the important one. See below.
- **Account** — change the password, and a plain-English note on what the sign-in protects.

### How publishing works — please read this once

The site has no server, so the manager panel saves your work **inside your own browser**. You see
the changes on the site immediately; nobody else does. To put them live:

1. **Publish tab → Download data.js**, and use it to replace `website/assets/js/data.js`.
2. **Publish tab → Download photos**, and put the files in `website/assets/img/uploads/`
   (create the folder the first time).
3. Upload both to wherever the site is hosted.

Until you do that, the work exists only in that one browser. Clearing your browsing data will
lose it — so take a **backup** (Publish tab) after any big update.

### What the sign-in is and is not

It hides the manager screens; it does not secure them. The settings sit in a file the browser
downloads, so anyone determined can read them. That is a limit of a site with no server, not a
bug. Nothing entered in the panel is confidential — it is all destined for a public web page.

If you need genuine accounts — several staff, real access control, an audit trail, photos that
appear for everyone the moment they are uploaded — the site needs a server back end. The panel was
built with that in mind: the screens stay, and `assets/js/store.js` is the single place that would
be swapped for API calls.

## Editing content

Almost everything a non-developer needs to change lives in `assets/js/data.js`:

- **`company`** — name, phone, WhatsApp number, email addresses, physical address, opening hours.
  These are injected everywhere via `data-co="…"` attributes, so changing them once updates every
  page, including the `tel:`, `mailto:` and `wa.me` links.
- **`vehicles`** — one object per unit. `body` must be one of `sedan`, `hatchback`, `suv`, `van`,
  `pickup`, `truck` (it selects the illustration). `status` is `in-stock`, `in-transit` or `to-order`.
- **`parts`** — one object per part line. `category` must match a `partCategories` id, `size` is
  `small`/`medium`/`large`, `type` is `genuine`/`oem`/`aftermarket`/`used`, `stock` is
  `in-stock`/`order`.

The vehicle and part grids, the make dropdown, the category tiles and all result counts are
generated from that data, so adding an entry is enough — no HTML edits needed.

## Before going live

1. **Change the manager password** in `assets/js/manager-config.js` — see the Account tab.
2. **Wire up the form.** `contact.html` currently hands the enquiry to the visitor's mail client.
   Replace the marked block at the end of `assets/js/main.js` with a `POST` to your form endpoint
   or CRM.
3. **Replace the placeholder artwork** in `assets/img/` with real photographs of your stock.
   Vehicle cards expect a 16:10 image; the filename is derived from the `body` field.
4. **Swap the demo details** in `data.js` — the phone number, addresses and `*.example` email
   domains are all placeholders, as are the prices and the stock list.
5. **Check the disclaimer.** Every page footer states that the company is independent and not
   affiliated with or an agent of BE FORWARD or any other exporter. Keep that accurate: if a
   formal agency agreement exists, reword it to match reality; if it does not, leave it as is.
6. **Confirm the claims.** The stats strip ("2,400+ vehicles delivered", "12 years in the trade"),
   the testimonials and the warranty terms are sample copy and need replacing with true figures.

## Browser support

Modern evergreen browsers. Uses CSS grid, custom properties, `IntersectionObserver` (with a
graceful fallback) and `URLSearchParams`. Respects `prefers-reduced-motion` and includes print
styles.

The manager panel additionally uses IndexedDB, falling back to `localStorage`. Browsers block
IndexedDB when a page is opened straight off the file system, and `localStorage` holds only about
5 MB — so for photo work, serve the folder over http (`python3 -m http.server 8000`) rather than
double-clicking the file. The panel shows which store it is using in the top bar.
