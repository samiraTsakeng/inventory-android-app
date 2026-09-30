const fs = require("fs");
const path = require("path");

// ✅ Shared "in-progress" scan list per counting sheet, so two team members
// on two different phones (logged in with the same head-of-team account)
// can scan into the SAME list and see each other's scans.
//
// This is intentionally file-based (not just in-memory) so an accidental
// server restart during a counting session doesn't wipe out a shared
// session that both phones are relying on. It's a lightweight JSON store,
// not meant to replace a real DB — fine for the scale of one warehouse
// team working a handful of sheets at a time.
//
// Data layout: data/live_sheets/<sheetId>.json -> { items: [ {...} ] }

const DATA_DIR = path.join(__dirname, "..", "data", "live_sheets");

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function filePathFor(sheetId) {
  return path.join(DATA_DIR, `${sheetId}.json`);
}

function readItems(sheetId) {
  ensureDataDir();
  const filePath = filePathFor(sheetId);
  if (!fs.existsSync(filePath)) return [];
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed.items) ? parsed.items : [];
  } catch (e) {
    console.error("liveSessionService: failed to read", filePath, e);
    return [];
  }
}

function writeItems(sheetId, items) {
  ensureDataDir();
  const filePath = filePathFor(sheetId);
  fs.writeFileSync(filePath, JSON.stringify({ items }, null, 2), "utf8");
}

const LiveSessionService = {
  // Returns the current shared list of scanned items for a sheet.
  getItems(sheetId) {
    return readItems(String(sheetId));
  },

  // ✅ Upsert a scan: if the barcode is already in the shared list, its
  // quantity is INCREASED by the incoming quantity (this covers both
  // "member 2 scanned something member 1 already scanned" and the rare
  // race where both scan a brand-new barcode within the same poll
  // window — either way, the server is the single authority so no
  // duplicate entries are ever created).
  // If the barcode is new, it's added as-is.
  upsertItem(sheetId, incomingItem) {
    const items = readItems(String(sheetId));
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

    writeItems(String(sheetId), items);
    return items;
  },

  // Called once the shared list has been saved into a batch and/or sent
  // to the ERP, so both phones start the next lot from an empty list.
  clearItems(sheetId) {
    writeItems(String(sheetId), []);
  },
};

module.exports = LiveSessionService;
 