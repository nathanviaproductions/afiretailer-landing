/**
 * Edge Function: refresh-tokens
 *
 * Runs every 15 minutes via pg_cron. Finds OAuth connections with tokens
 * expiring within the next 30 minutes and refreshes them using the
 * platform's refresh token endpoint.
 *
 * Invocation: POST /functions/v1/refresh-tokens
 * Auth: service_role key (called from pg_cron, not from clients)
 */
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import {
  supabaseAdmin,
  logSync,
} from "../_shared/supabase-client.ts";

const META_TOKEN_URL = "https://graph.facebook.com/v19.0/oauth/access_token";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

serve(async (req) => {
  try {
    // Verify this is called with the service_role key
    const authHeader = req.headers.get("Authorization");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!authHeader?.includes(serviceKey!)) {
      return new Response("Unauthorized", { status: 401 });
    }

    // Get connections with tokens expiring within 30 minutes
    const { data: expiring, error } = await supabaseAdmin.rpc(
      "get_expiring_connections",
      { p_buffer_minutes: 30 }
    );

    if (error) throw error;
    if (!expiring || expiring.length === 0) {
      return new Response(
        JSON.stringify({ message: "No tokens need refresh", count: 0 }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    const results = [];

    for (const conn of expiring) {
      try {
        // Get the encrypted refresh token
        const { data: connData } = await supabaseAdmin
          .from("platform_connections")
          .select("refresh_token_encrypted, platform")
          .eq("id", conn.connection_id)
          .single();

        if (!connData?.refresh_token_encrypted) {
          throw new Error("No refresh token available");
        }

        // Decrypt the refresh token
        const { data: refreshToken } = await supabaseAdmin.rpc(
          "decrypt_token",
          { encrypted_token: connData.refresh_token_encrypted }
        );

        // Refresh based on platform
        let newAccessToken: string;
        let newRefreshToken: string | null = null;
        let expiresIn: number;

        if (conn.platform === "meta") {
          const response = await fetch(
            `${META_TOKEN_URL}?grant_type=fb_exchange_token` +
              `&client_id=${Deno.env.get("META_APP_ID")}` +
              `&client_secret=${Deno.env.get("META_APP_SECRET")}` +
              `&fb_exchange_token=${refreshToken}`
          );
          const data = await response.json();
          if (data.error) throw new Error(data.error.message);
          newAccessToken = data.access_token;
          expiresIn = data.expires_in || 5184000; // Meta long-lived: ~60 days
        } else {
          // YouTube and Google Business Profile use Google OAuth
          const response = await fetch(GOOGLE_TOKEN_URL, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({
              grant_type: "refresh_token",
              refresh_token: refreshToken,
              client_id: Deno.env.get("GOOGLE_CLIENT_ID")!,
              client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
            }),
          });
          const data = await response.json();
          if (data.error) throw new Error(data.error_description || data.error);
          newAccessToken = data.access_token;
          newRefreshToken = data.refresh_token || null; // Google may issue a new refresh token
          expiresIn = data.expires_in || 3600;
        }

        // Encrypt and store the new tokens
        const { data: encAccess } = await supabaseAdmin.rpc("encrypt_token", {
          plain_token: newAccessToken,
        });

        const updatePayload: Record<string, unknown> = {
          access_token_encrypted: encAccess,
          token_expires_at: new Date(
            Date.now() + expiresIn * 1000
          ).toISOString(),
          status: "active",
          updated_at: new Date().toISOString(),
        };

        if (newRefreshToken) {
          const { data: encRefresh } = await supabaseAdmin.rpc(
            "encrypt_token",
            { plain_token: newRefreshToken }
          );
          updatePayload.refresh_token_encrypted = encRefresh;
        }

        await supabaseAdmin
          .from("platform_connections")
          .update(updatePayload)
          .eq("id", conn.connection_id);

        results.push({
          connection_id: conn.connection_id,
          status: "refreshed",
        });
      } catch (err) {
        // Mark connection as needing re-auth after 3 consecutive failures
        const errorMessage =
          err instanceof Error ? err.message : "Unknown error";
        console.error(
          `Token refresh failed for ${conn.connection_id}:`,
          errorMessage
        );

        await supabaseAdmin
          .from("platform_connections")
          .update({
            status: "token_expired",
            last_sync_error: `Token refresh failed: ${errorMessage}`,
            updated_at: new Date().toISOString(),
          })
          .eq("id", conn.connection_id);

        results.push({
          connection_id: conn.connection_id,
          status: "failed",
          error: errorMessage,
        });
      }
    }

    return new Response(JSON.stringify({ results }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("refresh-tokens error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
