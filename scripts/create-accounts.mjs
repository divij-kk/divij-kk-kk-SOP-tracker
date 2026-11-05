// One-time setup: creates the admin login and one login per manager,
// each manager with a random 6-digit PIN. Prints a PIN sheet and saves it
// to manager-pins.csv (keep that file private; delete it once PINs are handed out).
//
// Run from this folder:
//   npm install @supabase/supabase-js
//   SUPABASE_URL=https://xxxx.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=eyJ... \
//   ADMIN_PASSWORD='choose-a-strong-password' \
//   node scripts/create-accounts.mjs
//
// Safe to re-run: existing accounts are skipped (their PINs are not changed).
import { createClient } from "@supabase/supabase-js";
import { writeFileSync } from "node:fs";
import { randomInt } from "node:crypto";

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_PASSWORD } = process.env;
const DOMAIN = process.env.MANAGER_EMAIL_DOMAIN || "staff.kkumbrellas.com"; // must match index.html
const ADMIN_EMAIL = "kkumbrellas@gmail.com";

const MANAGERS = [
  "ANANDMOY BANERJEE", "ANUP ROY", "AVINASH SHAW", "BACHU BAKULI", "BOLAI SANTRA",
  "HIMANSHU KUMAR", "ISHAN CHATERJEE", "JOYDIP BAL", "JOYESH GHOSH", "LAKSHMIKANTA KARMAKAR",
  "MAINAK GANGULY", "MOLOY DHARA", "RAJU SANTRA", "SOUMITRO DE", "SUBRATA CHAKRABORTY",
  "SUROJIT CHAKRABORTY", "TRIDIB MANDAL", "UMA CHINA",
];

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first (Supabase → Project Settings → API).");
  process.exit(1);
}
const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const slugEmail = (n) => n.toLowerCase().trim().replace(/[^a-z0-9]+/g, ".").replace(/^\.|\.$/g, "") + "@" + DOMAIN;

async function existingEmails() {
  const set = new Set();
  for (let page = 1; ; page++) {
    const { data, error } = await sb.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    data.users.forEach((u) => set.add((u.email || "").toLowerCase()));
    if (data.users.length < 200) return set;
  }
}

const have = await existingEmails();

// Admin
if (have.has(ADMIN_EMAIL)) console.log(`Admin ${ADMIN_EMAIL} already exists — skipped.`);
else if (!ADMIN_PASSWORD || ADMIN_PASSWORD.length < 8) console.log("ADMIN_PASSWORD not set (min 8 characters) — admin login not created.");
else {
  const { error } = await sb.auth.admin.createUser({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD, email_confirm: true, user_metadata: { full_name: "KK Admin" } });
  if (error) throw error;
  console.log(`Admin ${ADMIN_EMAIL} created.`);
}

// Managers
const sheet = [["Manager", "Login (pick name in app)", "PIN"]];
for (const name of MANAGERS) {
  const email = slugEmail(name);
  if (have.has(email)) { console.log(`  ${name.padEnd(24)} already exists — skipped`); continue; }
  const pin = String(randomInt(100000, 1000000));
  const { error } = await sb.auth.admin.createUser({ email, password: pin, email_confirm: true, user_metadata: { full_name: name } });
  if (error) { console.log(`  ${name.padEnd(24)} FAILED: ${error.message}`); continue; }
  sheet.push([name, email, pin]);
  console.log(`  ${name.padEnd(24)} PIN ${pin}`);
}
if (sheet.length > 1) {
  writeFileSync("manager-pins.csv", sheet.map((r) => r.join(",")).join("\n") + "\n");
  console.log(`\nSaved ${sheet.length - 1} new PINs to manager-pins.csv`);
}
