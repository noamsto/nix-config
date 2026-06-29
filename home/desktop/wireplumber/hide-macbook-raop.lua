-- Destroy RAOP sinks whose AirPlay friendly name marks them as a Mac, so the
-- office's coworker laptops stop cluttering the sink picker.
--
-- We use a node-added event hook rather than an ObjectManager's object-added:
-- the latter can fire before a *live*-arriving node's properties are enriched
-- (so a coworker waking their laptop slipped through), whereas the event subject
-- always has its properties populated. We match the AirPlay friendly name
-- (media.name / node.description) since node.name carries the mDNS hostname,
-- which is often a custom word (e.g. "horton") that has no Mac marker.
log = Log.open_topic("s-hide-macbook-raop")

SimpleEventHook {
  name = "node/hide-macbook-raop",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
    },
  },
  execute = function (event)
    local node = event:get_subject()
    local p = node.properties
    local name = p["node.name"] or ""
    if not name:find("^raop_sink%.") then
      return
    end
    local hay = name .. "|" .. (p["media.name"] or "") .. "|" .. (p["node.description"] or "")
    if hay:find("MacBook") or hay:find("iMac")
      or hay:find("Mac mini") or hay:find("Mac Studio") then
      log:info("hiding RAOP node: " .. name)
      node:request_destroy()
    end
  end,
}:register()
