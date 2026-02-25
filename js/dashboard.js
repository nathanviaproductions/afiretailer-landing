/* ============================================
   AFI Retailer - Social Media Dashboard
   Demo data & interactivity
   ============================================ */

// ---------- Demo Creative Data ----------

var creatives = [
  {
    id: 1,
    title: "Memorial Day Sale - Living Room Sets 40% Off",
    platform: "facebook",
    channel: "paid",
    reach: 34200,
    views: 12800,
    likes: 1420,
    engagement: 6.8,
    spend: 450,
    revenue: 3150,
    roas: 7.0,
    color: "#1877f2"
  },
  {
    id: 2,
    title: "New Arrivals: Modern Farmhouse Collection",
    platform: "instagram",
    channel: "organic",
    reach: 18900,
    views: 8400,
    likes: 2310,
    engagement: 8.2,
    spend: 0,
    revenue: 0,
    roas: 0,
    color: "#e6683c"
  },
  {
    id: 3,
    title: "Customer Testimonial - The Johnson Family",
    platform: "youtube",
    channel: "organic",
    reach: 8700,
    views: 6200,
    likes: 340,
    engagement: 5.1,
    spend: 0,
    revenue: 0,
    roas: 0,
    color: "#ff0000"
  },
  {
    id: 4,
    title: "Spring Mattress Event - Save Up To $500",
    platform: "facebook",
    channel: "paid",
    reach: 28100,
    views: 9300,
    likes: 890,
    engagement: 4.2,
    spend: 620,
    revenue: 2850,
    roas: 4.6,
    color: "#1877f2"
  },
  {
    id: 5,
    title: "Behind the Scenes: Store Redesign Tour",
    platform: "instagram",
    channel: "organic",
    reach: 12400,
    views: 5600,
    likes: 1890,
    engagement: 9.4,
    spend: 0,
    revenue: 0,
    roas: 0,
    color: "#e6683c"
  },
  {
    id: 6,
    title: "Outdoor Patio Furniture - Summer Ready",
    platform: "facebook",
    channel: "paid",
    reach: 22300,
    views: 7800,
    likes: 670,
    engagement: 3.9,
    spend: 380,
    revenue: 1560,
    roas: 4.1,
    color: "#1877f2"
  },
  {
    id: 7,
    title: "How To Style Your Bedroom On A Budget",
    platform: "youtube",
    channel: "organic",
    reach: 15600,
    views: 11200,
    likes: 890,
    engagement: 7.3,
    spend: 0,
    revenue: 0,
    roas: 0,
    color: "#ff0000"
  },
  {
    id: 8,
    title: "Flash Sale: Dining Sets Starting at $499",
    platform: "instagram",
    channel: "paid",
    reach: 19800,
    views: 6100,
    likes: 1120,
    engagement: 5.6,
    spend: 520,
    revenue: 3900,
    roas: 7.5,
    color: "#e6683c"
  },
  {
    id: 9,
    title: "Kids Room Makeover Challenge",
    platform: "youtube",
    channel: "paid",
    reach: 9400,
    views: 7800,
    likes: 560,
    engagement: 6.1,
    spend: 275,
    revenue: 980,
    roas: 3.6,
    color: "#ff0000"
  },
  {
    id: 10,
    title: "Ashley HomeStore Grand Opening Event",
    platform: "facebook",
    channel: "organic",
    reach: 31200,
    views: 4100,
    likes: 2890,
    engagement: 11.2,
    spend: 0,
    revenue: 0,
    roas: 0,
    color: "#1877f2"
  },
  {
    id: 11,
    title: "Recliner Comfort Test - 30 Day Guarantee",
    platform: "facebook",
    channel: "paid",
    reach: 16700,
    views: 5900,
    likes: 430,
    engagement: 3.4,
    spend: 310,
    revenue: 2200,
    roas: 7.1,
    color: "#1877f2"
  },
  {
    id: 12,
    title: "Interior Design Tips: Small Space Solutions",
    platform: "instagram",
    channel: "organic",
    reach: 21500,
    views: 9800,
    likes: 3200,
    engagement: 10.1,
    spend: 0,
    revenue: 0,
    roas: 0,
    color: "#e6683c"
  }
];

// ---------- State ----------

var currentChannelFilter = "all";
var currentPlatformFilter = "all";
var currentSort = "engagement";

// ---------- Initialize ----------

document.addEventListener("DOMContentLoaded", function () {
  renderCreatives();
  initCharts();
});

// ---------- Filtering ----------

function setFilter(el) {
  var siblings = el.parentElement.querySelectorAll(".chip");
  siblings.forEach(function (s) { s.classList.remove("active"); });
  el.classList.add("active");
  currentChannelFilter = el.getAttribute("data-filter");
  renderCreatives();
  updateKPIs();
}

function setPlatformFilter(el) {
  var siblings = el.parentElement.querySelectorAll(".chip");
  siblings.forEach(function (s) { s.classList.remove("active"); });
  el.classList.add("active");
  currentPlatformFilter = el.getAttribute("data-platform-filter");
  renderCreatives();
  updateKPIs();
}

function getFilteredCreatives() {
  return creatives.filter(function (c) {
    var channelMatch = currentChannelFilter === "all" || c.channel === currentChannelFilter;
    var platformMatch = currentPlatformFilter === "all" || c.platform === currentPlatformFilter;
    return channelMatch && platformMatch;
  });
}

// ---------- Sorting ----------

function sortCreatives() {
  currentSort = document.getElementById("sortSelect").value;
  renderCreatives();
}

function sortedCreatives(list) {
  return list.slice().sort(function (a, b) {
    switch (currentSort) {
      case "engagement": return b.engagement - a.engagement;
      case "reach": return b.reach - a.reach;
      case "roas": return b.roas - a.roas;
      case "views": return b.views - a.views;
      case "spend": return b.spend - a.spend;
      default: return b.engagement - a.engagement;
    }
  });
}

// ---------- Render Creatives ----------

function formatNumber(n) {
  if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
  if (n >= 1000) return (n / 1000).toFixed(1) + "K";
  return n.toString();
}

function getRoasClass(roas) {
  if (roas === 0) return "";
  if (roas >= 5) return "highlight";
  if (roas >= 3) return "warn";
  return "bad";
}

function getEngagementClass(rate) {
  if (rate >= 7) return "highlight";
  if (rate >= 4) return "";
  return "bad";
}

function renderCreatives() {
  var grid = document.getElementById("creativeGrid");
  var filtered = sortedCreatives(getFilteredCreatives());

  var html = "";
  filtered.forEach(function (c) {
    var platformLabel = c.platform.charAt(0).toUpperCase() + c.platform.slice(1);
    var channelLabel = c.channel.charAt(0).toUpperCase() + c.channel.slice(1);
    var platformBadgeClass = "badge-" + c.platform;
    var channelBadgeClass = c.channel === "paid" ? "badge-paid" : "badge-organic";

    html += '<div class="creative-card" data-channel="' + c.channel + '" data-platform="' + c.platform + '">';
    html += '  <div class="creative-thumbnail">';
    html += '    <div class="creative-placeholder">';
    html += '      <svg viewBox="0 0 24 24" fill="currentColor"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>';
    html += '      <span>' + platformLabel + ' Creative</span>';
    html += '    </div>';
    html += '    <div class="creative-badges">';
    html += '      <span class="creative-badge ' + platformBadgeClass + '">' + platformLabel + '</span>';
    html += '      <span class="creative-badge ' + channelBadgeClass + '">' + channelLabel + '</span>';
    html += '    </div>';
    html += '  </div>';
    html += '  <div class="creative-info">';
    html += '    <div class="creative-title" title="' + c.title + '">' + c.title + '</div>';
    html += '    <div class="creative-metrics">';
    html += '      <div class="metric"><span class="metric-label">Reach</span><span class="metric-value">' + formatNumber(c.reach) + '</span></div>';
    html += '      <div class="metric"><span class="metric-label">Views</span><span class="metric-value">' + formatNumber(c.views) + '</span></div>';
    html += '      <div class="metric"><span class="metric-label">Engagement</span><span class="metric-value ' + getEngagementClass(c.engagement) + '">' + c.engagement + '%</span></div>';

    if (c.channel === "paid") {
      html += '      <div class="metric"><span class="metric-label">ROAS</span><span class="metric-value ' + getRoasClass(c.roas) + '">' + c.roas + 'x</span></div>';
    } else {
      html += '      <div class="metric"><span class="metric-label">Likes</span><span class="metric-value">' + formatNumber(c.likes) + '</span></div>';
    }

    html += '    </div>';
    html += '  </div>';
    html += '</div>';
  });

  grid.innerHTML = html;
}

// ---------- KPI Updates ----------

function updateKPIs() {
  var filtered = getFilteredCreatives();
  var totalReach = 0, totalViews = 0, totalSpend = 0, totalRevenue = 0;
  var totalEngagement = 0;

  filtered.forEach(function (c) {
    totalReach += c.reach;
    totalViews += c.views;
    totalSpend += c.spend;
    totalRevenue += c.revenue;
    totalEngagement += c.engagement;
  });

  var avgEngagement = filtered.length > 0 ? (totalEngagement / filtered.length) : 0;
  var roas = totalSpend > 0 ? (totalRevenue / totalSpend) : 0;

  document.getElementById("kpiReach").textContent = formatNumber(totalReach);
  document.getElementById("kpiEngagement").textContent = avgEngagement.toFixed(1) + "%";
  document.getElementById("kpiSpend").textContent = "$" + formatNumber(totalSpend);
  document.getElementById("kpiRoas").textContent = roas.toFixed(1) + "x";
  document.getElementById("kpiViews").textContent = formatNumber(totalViews);
}

function updateDashboard() {
  // In production, this would fetch fresh data for the selected date range
  updateKPIs();
}

// ---------- Charts ----------

function initCharts() {
  initPerformanceChart();
  initSpendChart();
}

function initPerformanceChart() {
  var ctx = document.getElementById("performanceChart").getContext("2d");

  var labels = [];
  var reachData = [];
  var engagementData = [];
  var viewsData = [];

  // Generate 30 days of demo data
  for (var i = 29; i >= 0; i--) {
    var d = new Date();
    d.setDate(d.getDate() - i);
    labels.push((d.getMonth() + 1) + "/" + d.getDate());
    reachData.push(Math.floor(3000 + Math.random() * 5000 + (30 - i) * 80));
    engagementData.push(+(3 + Math.random() * 5).toFixed(1));
    viewsData.push(Math.floor(1000 + Math.random() * 3000 + (30 - i) * 40));
  }

  new Chart(ctx, {
    type: "line",
    data: {
      labels: labels,
      datasets: [
        {
          label: "Reach",
          data: reachData,
          borderColor: "#e87a2e",
          backgroundColor: "rgba(232, 122, 46, 0.1)",
          fill: true,
          tension: 0.3,
          yAxisID: "y"
        },
        {
          label: "Video Views",
          data: viewsData,
          borderColor: "#60a5fa",
          backgroundColor: "transparent",
          borderDash: [5, 5],
          tension: 0.3,
          yAxisID: "y"
        },
        {
          label: "Engagement %",
          data: engagementData,
          borderColor: "#34d399",
          backgroundColor: "transparent",
          tension: 0.3,
          yAxisID: "y1"
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      interaction: {
        mode: "index",
        intersect: false
      },
      plugins: {
        legend: {
          labels: { color: "#8b8fa3", font: { size: 12 } }
        }
      },
      scales: {
        x: {
          ticks: { color: "#5e6275", maxTicksLimit: 10 },
          grid: { color: "rgba(46, 50, 71, 0.5)" }
        },
        y: {
          position: "left",
          ticks: {
            color: "#5e6275",
            callback: function (v) { return v >= 1000 ? (v / 1000).toFixed(0) + "K" : v; }
          },
          grid: { color: "rgba(46, 50, 71, 0.5)" }
        },
        y1: {
          position: "right",
          ticks: {
            color: "#5e6275",
            callback: function (v) { return v + "%"; }
          },
          grid: { drawOnChartArea: false }
        }
      }
    }
  });
}

function initSpendChart() {
  var ctx = document.getElementById("spendChart").getContext("2d");

  new Chart(ctx, {
    type: "doughnut",
    data: {
      labels: ["Facebook Ads", "Instagram Ads", "YouTube Ads"],
      datasets: [{
        data: [1380, 520, 275],
        backgroundColor: ["#1877f2", "#e6683c", "#ff0000"],
        borderColor: "#222533",
        borderWidth: 3
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        legend: {
          position: "bottom",
          labels: { color: "#8b8fa3", font: { size: 12 }, padding: 16 }
        }
      }
    }
  });
}

// ---------- Modal / Connect Platform ----------

function connectPlatform(platform) {
  var modal = document.getElementById("connectModal");
  var title = document.getElementById("modalTitle");
  var desc = document.getElementById("modalDesc");
  var btn = document.getElementById("oauthBtn");
  var btnText = document.getElementById("oauthBtnText");

  switch (platform) {
    case "meta":
      title.textContent = "Connect Meta";
      desc.textContent = "Connect your Facebook & Instagram business accounts to view ad and organic performance.";
      btn.style.backgroundColor = "#1877f2";
      btnText.textContent = "Continue with Meta";
      break;
    case "youtube":
      title.textContent = "Connect YouTube";
      desc.textContent = "Connect your YouTube channel to see video performance and ad metrics.";
      btn.style.backgroundColor = "#ff0000";
      btnText.textContent = "Continue with Google";
      break;
    case "gmb":
      title.textContent = "Connect Google Business Profile";
      desc.textContent = "Connect your Google Business Profile to see local search performance and reviews.";
      btn.style.backgroundColor = "#4285f4";
      btnText.textContent = "Continue with Google";
      break;
  }

  modal.classList.add("active");
}

function closeModal() {
  document.getElementById("connectModal").classList.remove("active");
}

function startOAuth() {
  // In production, this would redirect to the OAuth provider
  alert("OAuth integration requires a backend server.\n\nIn production, this would redirect to the platform's authorization page to securely connect your account with read-only access.");
}

// Close modal on overlay click
document.getElementById("connectModal").addEventListener("click", function (e) {
  if (e.target === this) closeModal();
});
