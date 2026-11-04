// Re-apply the "Enter opens the Linear issue in the browser" tweak to Vicinae's
// Linear extension. Vicinae installs Store extensions imperatively, so an
// update/reinstall wipes any edit to the bundle — this runs on every
// `nh home switch` to restore it.
//
// Stock binds Enter in the Search Issues list to "Show Details" (push a detail
// panel). We insert an OpenInBrowser action as the panel's first child so Enter
// opens the issue in the browser instead.
//
// The bundle is minified and its identifier aliases (jsx runtime, @raycast/api,
// the issue variable) are regenerated on every build, so they are captured out
// of the matched region rather than hardcoded — that is what lets the patch
// survive an extension update. If upstream restructures the action panel the
// match simply fails and the file is left untouched.
//
// Exit codes consumed by the activation wrapper:
//   0  already patched / nothing to do
//   10 newly patched -> wrapper restarts vicinae so the change loads
//   other (non-zero) skip reason; the wrapper ignores it (never fails switch)

const fs = require("fs");

const file = process.argv[2];
if (!file || !fs.existsSync(file)) {
  console.log("vicinae linear patch: extension not installed, skipping");
  process.exit(2);
}

const src = fs.readFileSync(file, "utf8");

const MARKER = 'Action.OpenInBrowser,{title:"Open Issue in Browser"';
if (src.includes(MARKER)) {
  console.log("vicinae linear patch: already applied");
  process.exit(0);
}

// children:[(0,<jsx>.jsx)(<api>.Action.Push,{title:"Show Details",icon:<api>.Icon.<x>,target:(0,<jsx>.jsx)(<x>,{issue:<iss>,
const re =
  /children:\[\(0,(\w+)\.jsx\)\((\w+)\.Action\.Push,\{title:"Show Details",icon:\2\.Icon\.\w+,target:\(0,\1\.jsx\)\(\w+,\{issue:(\w+),/;
const m = src.match(re);
if (!m) {
  console.log(
    "vicinae linear patch: anchor not found (layout changed?), skipping",
  );
  process.exit(3);
}

const [, jsx, api, iss] = m;
const anchor = `children:[(0,${jsx}.jsx)(${api}.Action.Push,{title:"Show Details"`;
if (src.split(anchor).length - 1 !== 1) {
  console.log("vicinae linear patch: anchor not unique, skipping");
  process.exit(4);
}

const inject = `children:[(0,${jsx}.jsx)(${api}.Action.OpenInBrowser,{title:"Open Issue in Browser",url:${iss}.url}),(0,${jsx}.jsx)(${api}.Action.Push,{title:"Show Details"`;
fs.writeFileSync(file, src.replace(anchor, inject));
console.log("vicinae linear patch: applied");
process.exit(10);
