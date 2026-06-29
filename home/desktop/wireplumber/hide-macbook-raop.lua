-- Destroy RAOP sinks whose AirPlay friendly name marks them as a Mac, so the
-- office's coworker laptops stop cluttering the sink picker. We match on the
-- friendly name (media.name, e.g. "RAOP to tom's MacBook Pro (2)") rather than
-- node.name, since node.name uses the mDNS hostname which is often a custom word
-- (e.g. "horton") that carries no Mac marker.
local om = ObjectManager {
  Interest {
    type = "node",
    Constraint { "node.name", "matches", "raop_sink.*" },
  }
}

om:connect("object-added", function (_, node)
  local p = node.properties
  local hay = (p["media.name"] or "") .. "|"
    .. (p["node.description"] or "") .. "|"
    .. (p["node.name"] or "")
  if hay:find("MacBook") or hay:find("iMac")
    or hay:find("Mac mini") or hay:find("Mac Studio") then
    Log.info("hide-macbook-raop: destroying " .. (p["node.name"] or "?"))
    node:request_destroy()
  end
end)

om:activate()
