const fs = require("fs");
const path = require("path");

// ✅ Shared "in-progress" scan list per counting sheet, so two team members
// on two different phones (logged in with the same head-of-team account)
// can scan into the SAME list and see each other's scans.
//
// The list lives in memory (reads never touch the disk) and is persisted to
// a JSON file after each change, so an accidental server restart during a
// counting session doesn't wipe out a shared session both phones rely on.
// Each change bumps a version number: polling clients send the version
// they already have and get "unchanged" instead of the full list.
//
// Data layout: data/live_sheets/<sheetId>.json -> { version, items: [ {...} ] }

const DATA_DIR = path.join(__dirname, "..", "data", "live_sheets");

// sheetId -> { version, items }
const sessions = new Map();
// sheetId -> promise of the write in progress (writes are serialized)
const pendingWrites = new Map();

function filePathFor(sheetId) {
  return path.join(DATA_DIR, `${sheetId}.json`);
}

// Loaded from disk once, then served from memory.
function load(sheetId) {
  let session = sessions.get(sheetId);
  if (session) return session;

  session = { version: 0, items: [] };
  const filePath = filePathFor(sheetId);
  if (fs.existsSync(filePath)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
      session.items = Array.isArray(parsed.items) ? parsed.items : [];
      session.version = Number(parsed.version) || 0;
    } catch (e) {
      console.error("liveSessionService: failed to read", filePath, e);
    }
  }
  sessions.set(sheetId, session);
  return session;
}

// Writes the latest snapshot without blocking the event loop. Successive
// changes queue behind the current write; each write takes the state at
// the moment it runs, so the file always ends with the latest version.
function persist(sheetId) {
  const previous = pendingWrites.get(sheetId) || Promise.resolve();
  const next = previous.then(async () => {
    const session = sessions.get(sheetId);
    await fs.promises.mkdir(DATA_DIR, { recursive: true });
    await fs.promises.writeFile(filePathFor(sheetId),
      JSON.stringify({ version: session.version, items: session.items }), "utf8");
  }).catch((e) => console.error("liveSessionService: failed to write", sheetId, e));
  pendingWrites.set(sheetId, next);
  next.then(() => {
    if (pendingWrites.get(sheetId) === next) pendingWrites.delete(sheetId);
  });
}

function update(sheetId, items) {
  const session = load(sheetId);
  session.items = items;
  session.version += 1;
  persist(sheetId);
  return session;
}

const LiveSessionService = {
  // Returns { version, items } — the current shared list for a sheet.
  getSession(sheetId) {
    return load(String(sheetId));
  },

  // ✅ Upsert a scan: if the barcode is already in the shared list, its
  // quantity is INCREASED by the incoming quantity (this covers both
  // "member 2 scanned something member 1 already scanned" and the rare
  // race where both scan a brand-new barcode within the same poll
  // window — either way, the server is the single authority so no
  // duplicate entries are ever created).
  // If the barcode is new, it's added as-is.
  upsertItem(sheetId, incomingItem) {
    const id = String(sheetId);
    const items = load(id).items;
    const barcode = incomingItem.barcode;
    const existingIndex = items.findIndex((it) => it.barcode === barcode);

    if (existingIndex !== -1) {
      const addedQty = Number(incomingItem.quantity) || 1;
      items[existingIndex].quantity = (Number(items[existingIndex].quantity) || 0) + addedQty;
    } else {
      items.push({
        barcode,
        product_name: incomingItem.product_name || "",
        product_id: incomingItem.product_id || 0,
        quantity: Number(incomingItem.quantity) || 1,
        lot_number: incomingItem.lot_number || null,
        lot_id: incomingItem.lot_id || null,
        tracking: incomingItem.tracking || "none",
      });
    }

    return update(id, items);
  },

  // Removes one barcode from the shared list.
  removeItem(sheetId, barcode) {
    const id = String(sheetId);
    return update(id, load(id).items.filter((it) => it.barcode !== barcode));
  },

  // Called once the shared list has been saved into a batch and/or sent
  // to the ERP, so both phones start the next lot from an empty list.
  clearItems(sheetId) {
    return update(String(sheetId), []);
  },
};

module.exports = LiveSessionService;
