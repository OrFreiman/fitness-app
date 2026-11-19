import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// One server function for the app:
//   {action:"estimate", prompt, tier?, images?: [base64 jpeg]}  -> Claude reply parsed as JSON (counts toward the daily limit)
//   {action:"barcode", code}                                    -> product from the shared table or Open Food Facts (free)
// verify_jwt is off because the function checks the login itself (works with Supabase's new signing keys).

const MODEL = "claude-haiku-5-5";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function parseJsonText(t: string) {
  const s = t.replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/, "").trim();
  try { return JSON.parse(s); } catch { /* fall through */ }
  const a = s.indexOf("{"), b = s.lastIndexOf("}");
  if (a >= 0 && b > a) { try { return JSON.parse(s.slice(a, b + 1)); } catch { /* */ } }
  return null;
}

async function estimate(body: any) {
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return { error: "not_configured" };
  const prompt = String(body.prompt || "").slice(0, 20000);
  if (!prompt) return { error: "bad_request" };
  const images: string[] = Array.isArray(body.images) ? body.images.slice(0, 2) : [];
  const content: any[] = images.map((data) => ({ type: "image", source: { type: "base64", media_type: "image/jpeg", data } }));
  content.push({ type: "text", text: prompt });
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: body.tier === "quick" ? 1200 : 3000, messages: [{ role: "user", content }] }),
  });
  if (!r.ok) {
    const t = await r.text();
    console.error("anthropic", r.status, t.slice(0, 500));
    if (/credit balance/i.test(t)) return { error: "no_credit" };
    if (r.status === 429 || r.status === 529) return { error: "rate_limited" };
    return { error: "upstream" };
  }
  const out = await r.json();
  const text = (out.content || []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("");
  if (!text) return { error: "empty_completion" };
  const data = parseJsonText(text);
  if (!data || typeof data !== "object") return { error: "invalid_json" };
  return { data };
}

const num = (v: unknown) => { const n = Number(v); return isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : 0; };

async function barcode(admin: any, code: string) {
  code = String(code || "").replace(/\D/g, "");
  if (code.length < 6) return { error: "bad_request" };
  const { data: row } = await admin.from("products").select("*").eq("barcode", code).maybeSingle();
  if (row) return { data: { barcode: code, name: row.name, per100: row.per100, unitName: row.unit_name || "", unitGrams: Number(row.unit_grams) || 0, source: row.source } };
  try {
    const r = await fetch(`https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,product_name_he,brands,nutriments,serving_quantity,serving_size`, {
      headers: { "User-Agent": "FitnessApp/1.0 (github.com/OrFreiman/fitness-app)" },
    });
    if (!r.ok) return { data: null };
    const j = await r.json();
    const p = j && j.status === 1 ? j.product : null;
    const n = p && p.nutriments;
    if (!n) return { data: null };
    let kcal = num(n["energy-kcal_100g"]);
    if (!kcal && n["energy_100g"]) kcal = num(Number(n["energy_100g"]) / 4.184);
    if (!kcal) return { data: null };
    const name = String(p.product_name_he || p.product_name || "").trim() || (p.brands ? String(p.brands) : "");
    return { data: { barcode: code, name, per100: { kcal, p: num(n.proteins_100g), c: num(n.carbohydrates_100g), f: num(n.fat_100g), fib: num(n.fiber_100g) },
      unitName: p.serving_quantity ? "מנה" : "", unitGrams: num(p.serving_quantity), source: "openfoodfacts" } };
  } catch (e) {
    console.error("off", e);
    return { data: null };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "bad_request" }, 405);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const admin = createClient(SUPABASE_URL, SERVICE, { auth: { persistSession: false } });
  const { data: u } = token ? await admin.auth.getUser(token) : { data: null as any };
  if (!u || !u.user) return json({ error: "session_expired" }, 401);
  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }

  if (body.action === "barcode") return json(await barcode(admin, body.code));

  if (body.action === "estimate") {
    const { data: lim, error } = await admin.rpc("bump_usage", { p_user: u.user.id });
    if (error) { console.error("bump_usage", error); return json({ error: "upstream" }); }
    if (!lim.ok) return json({ error: lim.error, limit: lim.limit });
    const res: any = await estimate(body);
    if (res.error) await admin.rpc("refund_usage", { p_user: u.user.id }); // failed estimates don't count
    return json(res);
  }
  return json({ error: "bad_request" }, 400);
});
