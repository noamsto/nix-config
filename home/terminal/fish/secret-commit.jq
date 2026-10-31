# Deterministic conventional-commit message for one changed sops secret file.
#
# Invocation (the old document is jq's main input; pass `{}` when it does not
# exist yet, so every key reads as added):
#
#   jq -c -f secret-commit.jq --arg stem <stem> --slurpfile new <new.json> < <old.json>
#
# Both inputs are the YAML documents converted to JSON by yq (the fish
# function does that). Output: {"changed": bool, "subject": string, "body": string}
#
# sops reuses a value's ciphertext when its plaintext is unchanged — a sibling
# leaf stays byte-identical across `sops set` and `sops edit`, and a value set
# back to itself does not move at all — so a key path whose ciphertext differs
# is one whose value actually changed, and it is named here. A `sops updatekeys`
# run is the opposite case: every leaf stays byte-identical and only the
# metadata moves, which reads as a recipients update.

# Leaf key paths below the `sops` metadata subtree, e.g. ["db", "password"].
def leaves($d): [$d | paths(scalars) | select(.[0] != "sops")];

# Those leaves as a path-joined map, so a key path is one comparable string.
def keyed($d): reduce leaves($d)[] as $p ({}; .[$p | join(".")] = ($d | getpath($p)));

def actions($added; $updated; $removed):
  [(if ($added | length) > 0 then "add \($added | sort | join(", "))" else empty end),
   (if ($updated | length) > 0 then "update \($updated | sort | join(", "))" else empty end),
   (if ($removed | length) > 0 then "remove \($removed | sort | join(", "))" else empty end)]
  | join("; ");

def lines($added; $updated; $removed):
  [(if ($added | length) > 0 then "  added: \($added | sort | join(", "))" else empty end),
   (if ($updated | length) > 0 then "  updated: \($updated | sort | join(", "))" else empty end),
   (if ($removed | length) > 0 then "  removed: \($removed | sort | join(", "))" else empty end)]
  | join("\n");

($new[0] // {}) as $n |
. as $o |
keyed($o) as $ov |
keyed($n) as $nv |
($ov | keys) as $ok |
($nv | keys) as $nk |
($nk - $ok) as $added |
($ok - $nk) as $removed |
([$ok[] as $k | select($nk | index($k)) | select($ov[$k] != $nv[$k]) | $k]) as $updated |
(($added | length) + ($updated | length) + ($removed | length)) as $total |

if $total > 0 then
  ("chore(secrets): \($ARGS.named.stem): " + actions($added; $updated; $removed)) as $candidate |
  {changed: true,
   subject: (if ($candidate | length) > 72 then
               "chore(secrets): \($ARGS.named.stem): update \($total) keys"
             else $candidate end),
   body: lines($added; $updated; $removed)}
elif ($o.sops? != $n.sops?) then
  {changed: true,
   subject: "chore(secrets): \($ARGS.named.stem): update recipients",
   body: "  recipients updated"}
else
  {changed: false, subject: "", body: ""}
end
