/**
 * Shared Supabase client for Edge Functions.
 * Uses the service_role key to bypass RLS for backend operations.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

/**
 * Decrypt an OAuth token stored in platform_connections.
 * Calls the decrypt_token() database function via service_role.
 */
export async function decryptToken(
  encryptedToken: Uint8Array
): Promise<string> {
  const { data, error } = await supabaseAdmin.rpc("decrypt_token", {
    encrypted_token: encryptedToken,
  });
  if (error) throw new Error(`Token decryption failed: ${error.message}`);
  return data;
}

/**
 * Log a sync attempt to the sync_log table.
 */
export async function logSync(entry: {
  connection_id: string;
  org_id: string;
  platform: string;
  status: string;
  records_fetched?: number;
  records_upserted?: number;
  error_message?: string;
  error_code?: string;
  rate_limit_remaining?: number;
  rate_limit_reset?: string;
}) {
  const { error } = await supabaseAdmin.from("sync_log").insert({
    ...entry,
    started_at: new Date().toISOString(),
    completed_at:
      entry.status === "completed" || entry.status === "failed"
        ? new Date().toISOString()
        : null,
  });
  if (error) console.error("Failed to log sync:", error.message);
}
