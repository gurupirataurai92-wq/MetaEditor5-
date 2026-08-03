# Sakura Auto Imports — company website

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

## Structure

```
website/
├── index.html, vehicles.html, parts.html, about.html, contact.html
└── assets/
    ├── css/styles.css      design tokens + all component styles
    ├── js/data.js          catalogue content (vehicles, parts, categories, company details)
    ├── js/main.js          nav, filtering, rendering, form validation
    └── img/                placeholder SVG artwork (vehicle silhouettes, part category tiles)
```

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

1. **Wire up the form.** `contact.html` currently hands the enquiry to the visitor's mail client.
   Replace the marked block at the end of `assets/js/main.js` with a `POST` to your form endpoint
   or CRM.
2. **Replace the placeholder artwork** in `assets/img/` with real photographs of your stock.
   Vehicle cards expect a 16:10 image; the filename is derived from the `body` field.
3. **Swap the demo details** in `data.js` — the phone number, addresses and `*.example` email
   domains are all placeholders, as are the prices and the stock list.
4. **Check the disclaimer.** Every page footer states that the company is independent and not
   affiliated with or an agent of BE FORWARD or any other exporter. Keep that accurate: if a
   formal agency agreement exists, reword it to match reality; if it does not, leave it as is.
5. **Confirm the claims.** The stats strip ("2,400+ vehicles delivered", "12 years in the trade"),
   the testimonials and the warranty terms are sample copy and need replacing with true figures.

## Browser support

Modern evergreen browsers. Uses CSS grid, custom properties, `IntersectionObserver` (with a
graceful fallback) and `URLSearchParams`. Respects `prefers-reduced-motion` and includes print
styles.
