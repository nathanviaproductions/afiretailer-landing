/**
 * Edge Function: sync-platform-data
 *
 * Pulls content and performance metrics from connected platform APIs.
 * Called by pg_cron on a per-platform schedule:
 *   - Meta (FB + IG): every 4 hours
 *   - YouTube: every 6 hours
 *   - Google Business Profile: every 12 hours
 *
 * Rate limit strategy:
 *   - Meta: 200 calls/hour per user token. We batch requests and use
 *     fields parameter to minimize calls. ~5 calls per store per sync.
 *   - YouTube Data API: 10,000 units/day quota. List+stats = ~5 units
 *     per call. We fetch max 50 videos per call. ~100 units per store.
 *   - GBP: 60 requests/minute. Light usage, well within limits.
 *
 * If rate-limited, we log it and retry on the next cron cycle.
 *
 * Invocation: POST /functions/v1/sync-platform-data
 * Body: { "platform": "meta" | "youtube" | "google_business" }
 * Auth: service_role key
 */
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin, logSync } from "../_shared/supabase-client.ts";

const META_GRAPH_URL = "https://graph.facebook.com/v19.0";
const YT_DATA_URL = "https://www.googleapis.com/youtube/v3";
const GBP_URL = "https://mybusinessbusinessinformation.googleapis.com/v1";

serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!authHeader?.includes(serviceKey!)) {
      return new Response("Unauthorized", { status: 401 });
    }

    const { platform } = await req.json();
    if (!platform) {
      return new Response(
        JSON.stringify({ error: "platform parameter required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Get all active connections for this platform that are due for sync
    const { data: connections, error } = await supabaseAdmin
      .from("platform_connections")
      .select("*")
      .eq("platform", platform)
      .eq("status", "active");

    if (error) throw error;
    if (!connections || connections.length === 0) {
      return new Response(
        JSON.stringify({
          message: `No active ${platform} connections`,
          count: 0,
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    const results = [];

    for (const conn of connections) {
      try {
        // Decrypt access token
        const { data: accessToken } = await supabaseAdmin.rpc(
          "decrypt_token",
          { encrypted_token: conn.access_token_encrypted }
        );

        if (!accessToken) {
          throw new Error("Failed to decrypt access token");
        }

        let recordsFetched = 0;
        let recordsUpserted = 0;

        // ==== Platform-specific sync logic ====

        if (platform === "meta") {
          // --- Fetch Facebook Page posts ---
          if (conn.platform_page_id) {
            const fbResult = await syncMetaPosts(
              conn,
              accessToken,
              conn.platform_page_id,
              "facebook"
            );
            recordsFetched += fbResult.fetched;
            recordsUpserted += fbResult.upserted;
          }

          // --- Fetch Instagram media ---
          if (conn.platform_ig_user_id) {
            const igResult = await syncMetaPosts(
              conn,
              accessToken,
              conn.platform_ig_user_id,
              "instagram"
            );
            recordsFetched += igResult.fetched;
            recordsUpserted += igResult.upserted;
          }
        } else if (platform === "youtube") {
          const ytResult = await syncYouTubeVideos(conn, accessToken);
          recordsFetched = ytResult.fetched;
          recordsUpserted = ytResult.upserted;
        } else if (platform === "google_business") {
          const gbpResult = await syncGoogleBusiness(conn, accessToken);
          recordsFetched = gbpResult.fetched;
          recordsUpserted = gbpResult.upserted;
        }

        // Update connection sync status
        await supabaseAdmin
          .from("platform_connections")
          .update({
            last_sync_at: new Date().toISOString(),
            last_sync_status: "completed",
            last_sync_error: null,
          })
          .eq("id", conn.id);

        await logSync({
          connection_id: conn.id,
          org_id: conn.org_id,
          platform,
          status: "completed",
          records_fetched: recordsFetched,
          records_upserted: recordsUpserted,
        });

        results.push({
          connection_id: conn.id,
          org_id: conn.org_id,
          status: "completed",
          records_fetched: recordsFetched,
          records_upserted: recordsUpserted,
        });
      } catch (err) {
        const errorMessage =
          err instanceof Error ? err.message : "Unknown error";
        const isRateLimit =
          errorMessage.includes("rate limit") ||
          errorMessage.includes("429") ||
          errorMessage.includes("quota");

        await supabaseAdmin
          .from("platform_connections")
          .update({
            last_sync_at: new Date().toISOString(),
            last_sync_status: isRateLimit ? "rate_limited" : "failed",
            last_sync_error: errorMessage,
          })
          .eq("id", conn.id);

        await logSync({
          connection_id: conn.id,
          org_id: conn.org_id,
          platform,
          status: isRateLimit ? "rate_limited" : "failed",
          error_message: errorMessage,
        });

        results.push({
          connection_id: conn.id,
          org_id: conn.org_id,
          status: "failed",
          error: errorMessage,
        });
      }
    }

    return new Response(JSON.stringify({ platform, results }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("sync-platform-data error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

// ============================================================================
// META (Facebook + Instagram) Sync
// ============================================================================

interface SyncResult {
  fetched: number;
  upserted: number;
}

async function syncMetaPosts(
  conn: Record<string, unknown>,
  accessToken: string,
  accountId: string,
  subPlatform: "facebook" | "instagram"
): Promise<SyncResult> {
  let fetched = 0;
  let upserted = 0;

  // Determine the fields based on sub-platform
  const isIG = subPlatform === "instagram";
  const fields = isIG
    ? "id,caption,media_type,permalink,thumbnail_url,timestamp,like_count,comments_count"
    : "id,message,type,permalink_url,created_time,full_picture";

  const endpoint = isIG
    ? `${META_GRAPH_URL}/${accountId}/media`
    : `${META_GRAPH_URL}/${accountId}/posts`;

  // Fetch recent posts (last 100)
  const response = await fetch(
    `${endpoint}?fields=${fields}&limit=100&access_token=${accessToken}`
  );

  if (!response.ok) {
    const errData = await response.json();
    throw new Error(
      `Meta API error: ${errData.error?.message || response.statusText}`
    );
  }

  const data = await response.json();
  const posts = data.data || [];
  fetched = posts.length;

  for (const post of posts) {
    // Determine content type
    let contentType = "image";
    if (isIG) {
      if (post.media_type === "VIDEO") contentType = "video";
      else if (post.media_type === "CAROUSEL_ALBUM") contentType = "carousel";
    } else {
      if (post.type === "video") contentType = "video";
      else if (post.type === "link") contentType = "link";
    }

    // Upsert creative
    const { error: upsertError } = await supabaseAdmin
      .from("creatives")
      .upsert(
        {
          org_id: conn.org_id,
          connection_id: conn.id,
          platform: subPlatform,
          platform_content_id: post.id,
          channel: "organic", // We'll update paid posts from ad insights separately
          content_type: contentType,
          title: isIG
            ? (post.caption || "").substring(0, 500)
            : (post.message || "").substring(0, 500),
          permalink: isIG ? post.permalink : post.permalink_url,
          thumbnail_path: isIG ? post.thumbnail_url : post.full_picture,
          published_at: isIG ? post.timestamp : post.created_time,
        },
        { onConflict: "org_id,platform,platform_content_id" }
      );

    if (!upsertError) upserted++;

    // Fetch insights for this post (engagement metrics)
    try {
      const insightsFields = isIG
        ? "impressions,reach,engagement"
        : "post_impressions,post_impressions_unique,post_engaged_users";

      const insightsResp = await fetch(
        `${META_GRAPH_URL}/${post.id}/insights?metric=${insightsFields}&access_token=${accessToken}`
      );

      if (insightsResp.ok) {
        const insightsData = await insightsResp.json();
        const metrics = parseMetaInsights(insightsData.data || []);

        // Get the creative ID
        const { data: creative } = await supabaseAdmin
          .from("creatives")
          .select("id")
          .eq("org_id", conn.org_id)
          .eq("platform", subPlatform)
          .eq("platform_content_id", post.id)
          .single();

        if (creative) {
          // Insert today's metric snapshot
          await supabaseAdmin.from("performance_metrics").upsert(
            {
              creative_id: creative.id,
              org_id: conn.org_id as string,
              platform: subPlatform,
              channel: "organic",
              metric_date: new Date().toISOString().split("T")[0],
              reach: metrics.reach || 0,
              impressions: metrics.impressions || 0,
              likes: isIG ? post.like_count || 0 : 0,
              comments: isIG ? post.comments_count || 0 : 0,
              engagement_rate: metrics.engagement_rate || 0,
            },
            { onConflict: "creative_id,metric_date" }
          );
        }
      }
    } catch {
      // Insights may not be available for all posts; continue
    }
  }

  return { fetched, upserted };
}

function parseMetaInsights(
  insights: Array<{ name: string; values: Array<{ value: number }> }>
): Record<string, number> {
  const result: Record<string, number> = {};
  for (const insight of insights) {
    const value = insight.values?.[0]?.value || 0;
    if (
      insight.name === "impressions" ||
      insight.name === "post_impressions"
    ) {
      result.impressions = value;
    } else if (
      insight.name === "reach" ||
      insight.name === "post_impressions_unique"
    ) {
      result.reach = value;
    } else if (
      insight.name === "engagement" ||
      insight.name === "post_engaged_users"
    ) {
      result.engagement_rate =
        result.reach && result.reach > 0 ? (value / result.reach) * 100 : 0;
    }
  }
  return result;
}

// ============================================================================
// YOUTUBE Sync
// ============================================================================

async function syncYouTubeVideos(
  conn: Record<string, unknown>,
  accessToken: string
): Promise<SyncResult> {
  let fetched = 0;
  let upserted = 0;

  // Step 1: Get the channel's uploads playlist
  const channelResp = await fetch(
    `${YT_DATA_URL}/channels?part=contentDetails&id=${conn.platform_account_id}&access_token=${accessToken}`
  );
  if (!channelResp.ok) throw new Error("YouTube channel fetch failed");
  const channelData = await channelResp.json();
  const uploadsPlaylistId =
    channelData.items?.[0]?.contentDetails?.relatedPlaylists?.uploads;
  if (!uploadsPlaylistId) throw new Error("No uploads playlist found");

  // Step 2: List videos from uploads playlist (max 50 per page)
  const playlistResp = await fetch(
    `${YT_DATA_URL}/playlistItems?part=snippet&playlistId=${uploadsPlaylistId}&maxResults=50&access_token=${accessToken}`
  );
  if (!playlistResp.ok) throw new Error("YouTube playlist fetch failed");
  const playlistData = await playlistResp.json();
  const videoItems = playlistData.items || [];
  fetched = videoItems.length;

  // Step 3: Get stats for all videos in one batch call
  const videoIds = videoItems
    .map(
      (item: { snippet: { resourceId: { videoId: string } } }) =>
        item.snippet.resourceId.videoId
    )
    .join(",");

  const statsResp = await fetch(
    `${YT_DATA_URL}/videos?part=statistics,contentDetails&id=${videoIds}&access_token=${accessToken}`
  );
  if (!statsResp.ok) throw new Error("YouTube stats fetch failed");
  const statsData = await statsResp.json();

  // Build a map of videoId -> stats
  const statsMap = new Map<
    string,
    { viewCount: string; likeCount: string; commentCount: string }
  >();
  for (const item of statsData.items || []) {
    statsMap.set(item.id, item.statistics);
  }

  // Step 4: Upsert each video
  for (const item of videoItems) {
    const videoId = item.snippet.resourceId.videoId;
    const stats = statsMap.get(videoId);
    const views = parseInt(stats?.viewCount || "0");
    const likes = parseInt(stats?.likeCount || "0");
    const comments = parseInt(stats?.commentCount || "0");
    const engagement =
      views > 0 ? ((likes + comments) / views) * 100 : 0;

    // Determine if this is a Short (< 60 seconds)
    const contentType = "video"; // Could check duration for 'short'

    const { error: upsertError } = await supabaseAdmin
      .from("creatives")
      .upsert(
        {
          org_id: conn.org_id,
          connection_id: conn.id,
          platform: "youtube",
          platform_content_id: videoId,
          channel: "organic",
          content_type: contentType,
          title: item.snippet.title,
          description: (item.snippet.description || "").substring(0, 1000),
          permalink: `https://www.youtube.com/watch?v=${videoId}`,
          thumbnail_path:
            item.snippet.thumbnails?.high?.url ||
            item.snippet.thumbnails?.default?.url,
          published_at: item.snippet.publishedAt,
          video_views: views,
          likes: likes,
          comments: comments,
          engagement_rate: parseFloat(engagement.toFixed(3)),
        },
        { onConflict: "org_id,platform,platform_content_id" }
      );

    if (!upsertError) upserted++;

    // Insert daily metric snapshot
    const { data: creative } = await supabaseAdmin
      .from("creatives")
      .select("id")
      .eq("org_id", conn.org_id)
      .eq("platform", "youtube")
      .eq("platform_content_id", videoId)
      .single();

    if (creative) {
      await supabaseAdmin.from("performance_metrics").upsert(
        {
          creative_id: creative.id,
          org_id: conn.org_id as string,
          platform: "youtube",
          channel: "organic",
          metric_date: new Date().toISOString().split("T")[0],
          video_views: views,
          likes,
          comments,
          engagement_rate: parseFloat(engagement.toFixed(3)),
        },
        { onConflict: "creative_id,metric_date" }
      );
    }
  }

  return { fetched, upserted };
}

// ============================================================================
// GOOGLE BUSINESS PROFILE Sync
// ============================================================================

async function syncGoogleBusiness(
  conn: Record<string, unknown>,
  accessToken: string
): Promise<SyncResult> {
  let fetched = 0;
  let upserted = 0;

  // Fetch local posts from GBP
  const postsResp = await fetch(
    `${GBP_URL}/${conn.platform_account_id}/localPosts`,
    {
      headers: { Authorization: `Bearer ${accessToken}` },
    }
  );

  if (!postsResp.ok) {
    throw new Error(`GBP API error: ${postsResp.statusText}`);
  }

  const postsData = await postsResp.json();
  const posts = postsData.localPosts || [];
  fetched = posts.length;

  for (const post of posts) {
    const { error: upsertError } = await supabaseAdmin
      .from("creatives")
      .upsert(
        {
          org_id: conn.org_id,
          connection_id: conn.id,
          platform: "google_business",
          platform_content_id: post.name,
          channel: "organic",
          content_type: "update",
          title: (post.summary || "").substring(0, 500),
          permalink: post.searchUrl,
          published_at: post.createTime,
        },
        { onConflict: "org_id,platform,platform_content_id" }
      );

    if (!upsertError) upserted++;

    // GBP post insights
    if (post.name) {
      try {
        const insightsResp = await fetch(
          `${GBP_URL}/${post.name}:getInsights`,
          {
            headers: { Authorization: `Bearer ${accessToken}` },
          }
        );

        if (insightsResp.ok) {
          const insightsData = await insightsResp.json();
          const { data: creative } = await supabaseAdmin
            .from("creatives")
            .select("id")
            .eq("org_id", conn.org_id)
            .eq("platform", "google_business")
            .eq("platform_content_id", post.name)
            .single();

          if (creative) {
            await supabaseAdmin.from("performance_metrics").upsert(
              {
                creative_id: creative.id,
                org_id: conn.org_id as string,
                platform: "google_business",
                channel: "organic",
                metric_date: new Date().toISOString().split("T")[0],
                impressions: insightsData.metricValues?.find(
                  (m: { metric: string }) =>
                    m.metric === "LOCAL_POST_VIEWS_SEARCH"
                )?.totalValue?.value || 0,
                clicks: insightsData.metricValues?.find(
                  (m: { metric: string }) =>
                    m.metric === "LOCAL_POST_ACTIONS_CALL_TO_ACTION"
                )?.totalValue?.value || 0,
                extended_metrics: insightsData,
              },
              { onConflict: "creative_id,metric_date" }
            );
          }
        }
      } catch {
        // Insights may not be available; continue
      }
    }
  }

  return { fetched, upserted };
}
