/**
 * KK Daily Tasks — sync the "TASK LISTS" sheet into the app.
 *
 * Setup (once):
 *  1. In the Google Sheet: Extensions → Apps Script. Paste this whole file.
 *  2. Replace PASTE-SYNC-CODE-HERE below with the sync code shown by sheet-sync.sql in Supabase.
 *  3. Save, close the Apps Script tab, reload the sheet.
 *  4. Menu "KK Tasks" → "Turn on automatic sync (every 15 min)" → allow access when Google asks.
 *
 * Sheet layout it reads:
 *  Row 1: manager names (one name can span two columns)
 *  Row 2: DAILY REPETITIVE / NON-DAILY under each name   (optional; without it every task is daily)
 *  Row 3+: tasks
 */

const SUPABASE_URL = "https://vuqisgqwbcturkbnntot.supabase.co";
const SUPABASE_KEY = "sb_publishable_7i6H9P5Himonj136Fb2PcA_sywIp0Qv"; // publishable key, safe to keep here
const SYNC_CODE    = "PASTE-SYNC-CODE-HERE";
const TASK_SHEET   = "TASK LISTS";
const LOG_SHEET    = "APP SYNC";

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu("KK Tasks")
    .addItem("Sync tasks to app now", "kkSyncNow")
    .addSeparator()
    .addItem("Turn on automatic sync (every 15 min)", "kkTurnOnAutoSync")
    .addItem("Turn off automatic sync", "kkTurnOffAutoSync")
    .addToUi();
}

function kkSyncNow() {
  const msg = kkSync_();
  SpreadsheetApp.getActive().toast(msg, "KK Tasks", 10);
}

function kkTurnOnAutoSync() {
  kkRemoveTriggers_();
  ScriptApp.newTrigger("kkAutoSync").timeBased().everyMinutes(15).create();
  const msg = kkSync_();
  SpreadsheetApp.getActive().toast("Automatic sync is on (every 15 minutes).\n" + msg, "KK Tasks", 10);
}

function kkTurnOffAutoSync() {
  kkRemoveTriggers_();
  SpreadsheetApp.getActive().toast("Automatic sync is off. Use “Sync tasks to app now” when needed.", "KK Tasks", 8);
}

function kkAutoSync() { kkSync_(); }

function kkRemoveTriggers_() {
  ScriptApp.getProjectTriggers()
    .filter(function (t) { return t.getHandlerFunction() === "kkAutoSync"; })
    .forEach(function (t) { ScriptApp.deleteTrigger(t); });
}

function kkSync_() {
  if (SYNC_CODE === "PASTE-SYNC-CODE-HERE") return kkLog_("Not synced: paste the sync code from Supabase into the Apps Script first.");
  const ss = SpreadsheetApp.getActive();
  const sheet = ss.getSheets().filter(function (s) { return s.getName().trim().toUpperCase() === TASK_SHEET; })[0];
  if (!sheet) return kkLog_("Not synced: there is no sheet named " + TASK_SHEET + ".");

  const managers = kkParseTaskSheet(sheet.getDataRange().getDisplayValues());
  if (!managers.length) return kkLog_("Not synced: no manager names found in row 1 of " + TASK_SHEET + ".");

  let res;
  try {
    res = UrlFetchApp.fetch(SUPABASE_URL + "/rest/v1/rpc/sync_tasks_from_sheet", {
      method: "post",
      contentType: "application/json",
      headers: { apikey: SUPABASE_KEY },
      payload: JSON.stringify({ p_token: SYNC_CODE, p_sheet: managers }),
      muteHttpExceptions: true,
    });
  } catch (e) {
    return kkLog_("Not synced: couldn't reach the app (" + e.message + "). It will try again at the next sync.");
  }
  const body = res.getContentText();
  if (res.getResponseCode() >= 300) {
    let m = body;
    try { m = JSON.parse(body).message || body; } catch (e) {}
    return kkLog_("Not synced: " + m);
  }
  const out = JSON.parse(body), s = out.totals || {};
  const parts = [];
  if (s.added) parts.push(s.added + " added");
  if (s.removed) parts.push(s.removed + " removed");
  if (s.restored) parts.push(s.restored + " back on");
  if (s.made_daily) parts.push(s.made_daily + " changed to daily");
  if (s.needs_schedule) parts.push(s.needs_schedule + " non-daily task(s) waiting for a schedule in the app");
  let msg = "Synced. " + (parts.length ? parts.join(", ") + "." : "No changes.");
  if (out.unknown && out.unknown.length) msg += " Names not found in the app (skipped): " + out.unknown.join(", ") + ".";
  return kkLog_(msg);
}

/** Turns the sheet's values into [{manager, daily:[...], nondaily:[...]}]. Same rules as the app's Excel import. */
function kkParseTaskSheet(rows) {
  const norm = function (v) { return String(v == null ? "" : v).replace(/\s+/g, " ").trim(); };
  const head = rows[0] || [], sub = rows[1] || [];
  const hasSub = sub.some(function (v) { return /DAILY/i.test(norm(v)); });
  const start = hasSub ? 2 : 1;
  let width = 0;
  rows.forEach(function (r) { width = Math.max(width, (r || []).length); });
  const byName = {}, order = [];
  let owner = null;
  for (let c = 0; c < width; c++) {
    const name = norm(head[c]);
    if (name) {
      const key = name.toUpperCase();
      if (!byName[key]) { byName[key] = { manager: name, daily: [], nondaily: [] }; order.push(key); }
      owner = byName[key];
    }
    if (!owner) continue;
    if (hasSub ? !norm(sub[c]) : !name) continue;
    const kind = hasSub && /NON/i.test(norm(sub[c])) ? "nondaily" : "daily";
    for (let r = start; r < rows.length; r++) {
      const t = norm((rows[r] || [])[c]);
      if (t) owner[kind].push(t);
    }
  }
  return order.map(function (k) { return byName[k]; });
}

function kkLog_(msg) {
  const ss = SpreadsheetApp.getActive();
  let log = ss.getSheetByName(LOG_SHEET);
  if (!log) log = ss.insertSheet(LOG_SHEET);
  const when = Utilities.formatDate(new Date(), "Asia/Kolkata", "dd MMM yyyy, h:mm a");
  log.getRange("A1:B2").setValues([["Last sync", when], ["Result", msg]]);
  log.getRange("A1:A2").setFontWeight("bold");
  log.setColumnWidth(2, 700);
  return msg;
}
