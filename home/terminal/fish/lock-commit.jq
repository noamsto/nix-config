# Deterministic conventional-commit message for a flake.lock diff.
#
# Invocation (the old lock is jq's main input; pass `{}` when it does not
# exist yet so every input reads as added):
#
#   jq -c -f lock-commit.jq --slurpfile new <new flake.lock> < <old flake.lock>
#
# Output: {"changed": bool, "subject": string, "body": string}
#
# Every list is sorted and every date is computed here in jq (strftime is UTC
# on every platform), so the same lock diff always yields the same message.

def node($lock; $key): $lock.nodes[$key] // null;

# The root node's inputs: name -> node key (string) or follows path (array).
def root_inputs($lock): ($lock.nodes[$lock.root].inputs // {});

# Short identifier for a node: 7-char rev, else 12 chars of narHash after the
# `sha256-` prefix, else "unknown" for a node that carries neither.
def short_ref($n):
  if $n == null then "unknown"
  elif ($n.locked.rev? // null) != null then ($n.locked.rev[0:7])
  elif ($n.locked.narHash? // null) != null then (($n.locked.narHash | sub("^sha256-"; ""))[0:12])
  else "unknown" end;

# locked.lastModified as UTC YYYY-MM-DD, or "unknown" when absent.
def lock_date($n):
  if $n == null then "unknown"
  elif ($n.locked.lastModified? // null) != null then ($n.locked.lastModified | strftime("%Y-%m-%d"))
  else "unknown" end;

($new[0]) as $n |
. as $o |
(root_inputs($o)) as $oi |
(root_inputs($n)) as $ni |
(($oi | keys) + ($ni | keys) | unique) as $names |

# Direct inputs of the root node, classified. A `follows` input (array) has no
# node of its own; only an input that is a follows on BOTH sides is skipped, so
# a transition to/from a follows still classifies as added/removed.
[ $names[] as $name |
  ($oi[$name]) as $ov |
  ($ni[$name]) as $nv |
  select(($ov | type) != "array" or ($nv | type) != "array") |
  (if ($ov | type) == "string" then node($o; $ov) else null end) as $on |
  (if ($nv | type) == "string" then node($n; $nv) else null end) as $nn |
  if $on == null and $nn != null then
    {name: $name, kind: "added", old: null, new: $nn}
  elif $on != null and $nn == null then
    {name: $name, kind: "removed", old: $on, new: null}
  elif ($on.locked? != $nn.locked?) then
    {name: $name, kind: "updated", old: $on, new: $nn}
  else empty end
] | sort_by(.name) as $changes |

# Node keys referenced directly by the root, excluded from the transitive count.
(($oi | to_entries | map(select(.value | type == "string") | .value)) +
 ($ni | to_entries | map(select(.value | type == "string") | .value))) as $direct_keys |

# Non-root nodes (not direct inputs) whose `locked` moved.
((($o.nodes // {}) | keys) + (($n.nodes // {}) | keys) | unique) as $all_keys |
[ $all_keys[] as $k |
  select($k != "root") |
  select(($direct_keys | index($k)) == null) |
  select((node($o; $k).locked?) != (node($n; $k).locked?)) |
  $k
] | length as $transitive |

($changes | map(
  if .kind == "updated" then
    "- \(.name): \(short_ref(.old)) → \(short_ref(.new)) (\(lock_date(.old)) → \(lock_date(.new)))" +
    (if (.old.locked.type? == "github" and .new.locked.type? == "github") then
       "\n  https://github.com/\(.new.locked.owner)/\(.new.locked.repo)/compare/\(.old.locked.rev)...\(.new.locked.rev)"
     else "" end)
  elif .kind == "added" then
    "- \(.name): added (\(short_ref(.new)), \(lock_date(.new)))"
  else
    "- \(.name): removed"
  end
)) as $change_lines |

(if ($changes | length) > 0 then
   ($changes | map(.name) | join(", ")) as $joined |
   ("chore(deps): update \($joined)") as $candidate |
   if ($candidate | length) > 72 then
     "chore(deps): update \($changes | length) flake inputs"
   else $candidate end
 elif $transitive > 0 then
   "chore(deps): update transitive flake inputs"
 else
   ""
 end) as $subject |

{
  changed: ($subject != ""),
  subject: $subject,
  body: (($change_lines + (if $transitive > 0 then ["- \($transitive) transitive inputs changed"] else [] end)) | join("\n"))
}
