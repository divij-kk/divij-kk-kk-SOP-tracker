// Supabase Edge Function: manage-manager
// Lets the admin (and only the admin) add a manager, reset a manager's PIN,
// or switch a manager's sign-in off/on. Needs the service-role key, which
// Supabase injects automatically as SUPABASE_SERVICE_ROLE_KEY.
//
// Deploy:  supabase functions deploy manage-manager
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, service, { auth: { persistSession: false } });

    // Who is calling?
    const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    const { data: caller } = await admin.auth.getUser(jwt);
    if (!caller?.user) return json({ error: "Please sign in again." }, 401);
    const { data: prof } = await admin.from("profiles").select("role, active").eq("id", caller.user.id).single();
    if (!prof || prof.role !== "admin" || !prof.active) return json({ error: "Only the admin can do this." }, 403);

    const body = await req.json();
    const pinOk = (p: unknown) => typeof p === "string" && /^\d{6}$/.test(p);

    if (body.action === "create") {
      if (!body.full_name || !body.email || !pinOk(body.pin)) return json({ error: "Name, email and a 6-digit PIN are needed." }, 400);
      const { data, error } = await admin.auth.admin.createUser({
        email: String(body.email).toLowerCase(),
        password: body.pin,
        email_confirm: true,
        user_metadata: { full_name: String(body.full_name).toUpperCase(), department: body.department || null },
      });
      if (error) return json({ error: /already/i.test(error.message) ? "A manager with this name already exists." : error.message }, 400);
      return json({ ok: true, id: data.user.id });
    }

    if (body.action === "reset_pin") {
      if (!body.user_id || !pinOk(body.pin)) return json({ error: "A 6-digit PIN is needed." }, 400);
      const { error } = await admin.auth.admin.updateUserById(body.user_id, { password: body.pin });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (body.action === "set_active") {
      const active = !!body.active;
      const { error: e1 } = await admin.from("profiles").update({ active }).eq("id", body.user_id).eq("role", "manager");
      if (e1) return json({ error: e1.message }, 400);
      // also block / unblock the login itself
      const { error: e2 } = await admin.auth.admin.updateUserById(body.user_id, { ban_duration: active ? "none" : "876000h" });
      if (e2) return json({ error: e2.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
