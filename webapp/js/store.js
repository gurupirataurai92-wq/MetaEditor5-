/* Data layer: localStorage-backed store with seed data and helpers. */
(function () {
  const KEY = "godmode-consultant-db-v1";

  const seed = () => ({
    clients: [],
    engagements: [],
    audits: [],
    findings: [],
    accounts: [
      { id: "a-cash",  name: "Cash & Bank",          type: "Asset" },
      { id: "a-ar",    name: "Accounts Receivable",  type: "Asset" },
      { id: "a-equip", name: "Equipment",            type: "Asset" },
      { id: "l-ap",    name: "Accounts Payable",     type: "Liability" },
      { id: "l-loan",  name: "Loans Payable",        type: "Liability" },
      { id: "q-cap",   name: "Owner's Capital",      type: "Equity" },
      { id: "i-fees",  name: "Consulting Fees",      type: "Income" },
      { id: "i-int",   name: "Interest Income",      type: "Income" },
      { id: "e-rent",  name: "Rent Expense",         type: "Expense" },
      { id: "e-sal",   name: "Salaries Expense",     type: "Expense" },
      { id: "e-oth",   name: "Other Expenses",       type: "Expense" }
    ],
    journal: [],
    invoices: [],
    loans: [],
    obligations: [],
    employees: [],
    risks: [],
    ooda: [],
    settings: { currency: "USD" }
  });

  let db;
  try {
    db = JSON.parse(localStorage.getItem(KEY)) || seed();
  } catch (e) {
    db = seed();
  }
  // Backfill any collections added after first save.
  const fresh = seed();
  Object.keys(fresh).forEach(k => { if (db[k] === undefined) db[k] = fresh[k]; });

  window.DB = db;
  window.saveDB = function () { localStorage.setItem(KEY, JSON.stringify(db)); };
  window.resetDB = function () { localStorage.removeItem(KEY); location.reload(); };
  window.uid = function (p) { return (p || "id") + "-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 7); };

  window.exportDB = function () {
    const blob = new Blob([JSON.stringify(db, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "godmode-backup-" + new Date().toISOString().slice(0, 10) + ".json";
    a.click();
    URL.revokeObjectURL(a.href);
  };

  window.importDB = function (file, cb) {
    const r = new FileReader();
    r.onload = () => {
      try {
        const data = JSON.parse(r.result);
        if (typeof data !== "object" || !data.accounts) throw new Error("bad file");
        Object.keys(db).forEach(k => delete db[k]);
        Object.assign(db, seed(), data);
        saveDB();
        cb(true);
      } catch (e) { cb(false); }
    };
    r.readAsText(file);
  };
})();
