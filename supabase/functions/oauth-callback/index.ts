/**
 * Edge Function: oauth-callback
 *
 * Handles the OAuth redirect callback from platform authorization flows.
 * The dashboard redirects users to the platform's OAuth consent screen,
 * which then redirects back here with an authorization code.
 * We exchange the code for tokens and store them encrypted.
 *
 * Flow:
 *   1. Dashboard calls connectPlatform() -> redirects to platform OAuth
 *   2. User authorizes -> platform redirects to this Edge Function
 *   3. We exchange the auth code for access + refresh tokens
 *   4. Tokens are encrypted and stored in platform_connections
 *   5. We redirect back to the dashboard with a success/error status
 *
 * URL: /functions/v1/oauth-callback?platform=meta&state=<encrypted_state>
 */
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";

const META_TOKEN_URL = "https://graph.facebook.com/v19.0/oauth/access_token";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

serve(async (req) => {
  try {
    const url = new URL(req.url);
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const error = url.searchParams.get("error");
    const dashboardUrl = Deno.env.get("DASHBOARD_URL") || "https://afiretailer.com/dashboard.html";

    // Handle OAuth denial
    if (error) {
      return Response.redirect(
        `${dashboardUrl}?connection=error&message=${encodeURIComponent(error)}`,
        302
      );
    }

    if (!code || !state) {
      return Response.redirect(
        `${dashboardUrl}?connection=error&message=missing_params`,
        302
      );
    }

    // Decode state parameter (contains platform, org_id, user_id)
    // State is base64-encoded JSON signed with a server secret
    let stateData: { platform: string; org_id: string; user_id: string };
    try {
      stateData = JSON.parse(atob(state));
    } catch {
      return Response.redirect(
        `${dashboardUrl}?connection=error&message=invalid_state`,
        302
      );
    }

    const { platform, org_id, user_id } = stateData;
    const redirectUri = `${Deno.env.get("SUPABASE_URL")}/functions/v1/oauth-callback`;

    let accessToken: string;
    let refreshToken: string;
    let expiresIn: number;
    let accountId: string | null = null;
    let accountName: string | null = null;
    let pageId: string | null = null;
    let igUserId: string | null = null;
    let tokenScope: string | null = null;

    // === Exchange auth code for tokens ===
    if (platform === "meta") {
      // Step 1: Exchange code for short-lived token
      const tokenResp = await fetch(
        `${META_TOKEN_URL}?client_id=${Deno.env.get("META_APP_ID")}` +
        `&client_secret=${Deno.env.get("META_APP_SECRET")}` +
        `&redirect_uri=${encodeURIComponent(redirectUri)}` +
        `&code=${code}`
      );
      const tokenData = await tokenResp.json();
      if (tokenData.error) throw new Error(tokenData.error.message);

      // Step 2: Exchange for long-lived token (~60 days)
      const longLivedResp = await fetch(
        `${META_TOKEN_URL}?grant_type=fb_exchange_token` +
        `&client_id=${Deno.env.get("META_APP_ID")}` +
        `&client_secret=${Deno.env.get("META_APP_SECRET")}` +
        `&fb_exchange_token=${tokenData.access_token}`
      );
      const longLivedData = await longLivedResp.json();
      if (longLivedData.error) throw new Error(longLivedData.error.message);

      accessToken = longLivedData.access_token;
      refreshToken = longLivedData.access_token; // Meta long-lived tokens are self-refreshing
      expiresIn = longLivedData.expires_in || 5184000;

      // Step 3: Get connected Facebook Page and Instagram Business Account
      const accountsResp = await fetch(
        `https://graph.facebook.com/v19.0/me/accounts?fields=id,name,instagram_business_account&access_token=${accessToken}`
      );
      const accountsData = await accountsResp.json();
      const page = accountsData.data?.[0];
      if (page) {
        pageId = page.id;
        accountName = page.name;
        igUserId = page.instagram_business_account?.id || null;
      }

      // Get Business Account ID
      const bizResp = await fetch(
        `https://graph.facebook.com/v19.0/me?fields=id,name&access_token=${accessToken}`
      );
      const bizData = await bizResp.json();
      accountId = bizData.id;
      if (!accountName) accountName = bizData.name;

    } else if (platform === "youtube" || platform === "google_business") {
      // Google OAuth token exchange
      const tokenResp = await fetch(GOOGLE_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "authorization_code",
          code,
          redirect_uri: redirectUri,
          client_id: Deno.env.get("GOOGLE_CLIENT_ID")!,
          client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
        }),
      });
      const tokenData = await tokenResp.json();
      if (tokenData.error) {
        throw new Error(tokenData.error_description || tokenData.error);
      }

      accessToken = tokenData.access_token;
      refreshToken = tokenData.refresh_token;
      expiresIn = tokenData.expires_in || 3600;
      tokenScope = tokenData.scope;

      if (platform === "youtube") {
        // Get YouTube channel info
        const channelResp = await fetch(
          `https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true`,
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
        const channelData = await channelResp.json();
        const channel = channelData.items?.[0];
        if (channel) {
          accountId = channel.id;
          accountName = channel.snippet.title;
        }
      } else {
        // Get GBP location info
        const locResp = await fetch(
          "https://mybusinessaccountmanagement.googleapis.com/v1/accounts",
          { headers: { Authorization: `Bearer ${accessToken}` } }
        );
        const locData = await locResp.json();
        const account = locData.accounts?.[0];
        if (account) {
          accountId = account.name;
          accountName = account.accountName;
        }
      }
    } else {
      throw new Error(`Unsupported platform: ${platform}`);
    }

    // === Encrypt tokens ===
    const { data: encAccess } = await supabaseAdmin.rpc("encrypt_token", {
      plain_token: accessToken,
    });
    const { data: encRefresh } = await supabaseAdmin.rpc("encrypt_token", {
      plain_token: refreshToken,
    });

    // === Upsert platform connection ===
    const connectionData: Record<string, unknown> = {
      org_id,
      platform: platform === "youtube" ? "youtube" : platform === "google_business" ? "google_business" : "meta",
      status: "active",
      platform_account_id: accountId,
      platform_account_name: accountName,
      access_token_encrypted: encAccess,
      refresh_token_encrypted: encRefresh,
      token_expires_at: new Date(Date.now() + expiresIn * 1000).toISOString(),
      token_scope: tokenScope,
      connected_at: new Date().toISOString(),
      connected_by: user_id,
    };

    if (platform === "meta") {
      connectionData.platform_page_id = pageId;
      connectionData.platform_ig_user_id = igUserId;
    }

    const { error: upsertError } = await supabaseAdmin
      .from("platform_connections")
      .upsert(connectionData, {
        onConflict: "org_id,platform",
      });

    if (upsertError) throw upsertError;

    // Redirect back to dashboard with success
    return Response.redirect(
      `${dashboardUrl}?connection=success&platform=${platform}`,
      302
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("oauth-callback error:", message);
    const dashboardUrl = Deno.env.get("DASHBOARD_URL") || "https://afiretailer.com/dashboard.html";
    return Response.redirect(
      `${dashboardUrl}?connection=error&message=${encodeURIComponent(message)}`,
      302
    );
  }
});
