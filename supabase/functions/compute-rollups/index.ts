/**
 * Edge Function: compute-rollups
 *
 * Computes daily KPI rollups for all active organizations.
 * Runs daily at 2 AM UTC via pg_cron, after all platform syncs complete.
 * Also triggered on-demand after individual syncs.
 *
 * Invocation: POST /functions/v1/compute-rollups
 * Body (optional): { "org_id": "uuid", "date": "YYYY-MM-DD" }
 * Auth: service_role key
 */
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";

serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!authHeader?.includes(serviceKey!)) {
      return new Response("Unauthorized", { status: 401 });
    }

    let body: { org_id?: string; date?: string } = {};
    try {
      body = await req.json();
    } catch {
      // Empty body is fine - we'll compute for all orgs for today
    }

    const targetDate =
      body.date || new Date().toISOString().split("T")[0];

    if (body.org_id) {
      // Compute rollup for a specific org
      const { error } = await supabaseAdmin.rpc("compute_daily_rollup", {
        p_org_id: body.org_id,
        p_date: targetDate,
      });

      if (error) throw error;

      return new Response(
        JSON.stringify({
          message: "Rollup computed",
          org_id: body.org_id,
          date: targetDate,
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // Compute rollups for ALL active organizations
    const { data: orgs, error: orgsError } = await supabaseAdmin
      .from("organizations")
      .select("id")
      .eq("is_active", true);

    if (orgsError) throw orgsError;

    const results = [];

    for (const org of orgs || []) {
      try {
        const { error } = await supabaseAdmin.rpc("compute_daily_rollup", {
          p_org_id: org.id,
          p_date: targetDate,
        });

        if (error) throw error;
        results.push({ org_id: org.id, status: "computed" });
      } catch (err) {
        const message = err instanceof Error ? err.message : "Unknown error";
        console.error(`Rollup failed for org ${org.id}:`, message);
        results.push({ org_id: org.id, status: "failed", error: message });
      }
    }

    // Also compute rollups for the previous day if any data arrived late
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split("T")[0];

    for (const org of orgs || []) {
      try {
        await supabaseAdmin.rpc("compute_daily_rollup", {
          p_org_id: org.id,
          p_date: yesterdayStr,
        });
      } catch {
        // Backfill failures are non-critical
      }
    }

    return new Response(
      JSON.stringify({
        message: "Rollups computed",
        date: targetDate,
        organizations: results.length,
        results,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("compute-rollups error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
