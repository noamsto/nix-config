# Registers houston and `hookyard serve` (user services from home/ai/houston and
# home/ai/hookyard) on services.localProxy for any host with agentDashboard.enable.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.agentDashboard.enable {
    services.localProxy.services = {
      houston = {
        port = 9090;
        # `/houston` is the door in, stripped so houston answers it at its own
        # root; the `/` catch-all then serves the absolute asset URLs that page
        # goes on to request. Only the bare root moves, to the landing page.
        paths = ["/" "/houston"];
        stripPrefix = ["/houston"];
        streaming = true;
        responseHeaderTimeout = "300s";
        landing = {
          title = "Houston";
          description = "Monitor and steer remote agent sessions";
          icon = "🚀";
        };
      };
      # serve builds every URL absolutely (/static/, /api/...). `/hookyard` is
      # the door in, stripped; its own routes are claimed one by one rather
      # than as a blanket /api, which other services on this vhost share.
      #
      # serve 403s any Host but its loopback address, hence upstreamHost. It is
      # unauthenticated and shows tool payloads: only a proxy that keeps reach
      # private makes that acceptable (tailnet-only on halo; loopback plus an
      # allowlisted tsnet node on tp-g5).
      hookyard = {
        port = 7757;
        paths = ["/hookyard" "/static" "/api/days" "/api/events" "/api/flow" "/api/stats" "/api/stream" "/api/table"];
        stripPrefix = ["/hookyard"];
        upstreamHost = "localhost:7757";
        streaming = true;
        landing = {
          title = "hookyard";
          description = "Agent hook events and flow across engines";
          icon = "🪝";
        };
      };
    };
  };
}
