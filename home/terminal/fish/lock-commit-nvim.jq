# Deterministic conventional-commit message for a lazy.nvim lockfile diff.
#
# Invocation (the old lock is jq's main input; pass `{}` when it does not
# exist yet so every plugin reads as added):
#
#   jq -c -f lock-commit-nvim.jq --slurpfile new <new lazy-lock.json> < <old lazy-lock.json>
#
# Output: {"changed": bool, "subject": string, "body": string}
#
# The lock maps plugin name -> {branch, commit}. Every list is sorted and the
# short rev is derived here, so the same diff always yields the same message.

($new[0]) as $n |
. as $o |

([($o | keys)[] , ($n | keys)[]] | unique) as $names |

[ $names[] as $name |
  ($o[$name]? // null) as $ov |
  ($n[$name]? // null) as $nv |
  if $ov == null and $nv != null then
    {name: $name, kind: "added", old: null, new: $nv}
  elif $ov != null and $nv == null then
    {name: $name, kind: "removed", old: $ov, new: null}
  elif $ov.commit != $nv.commit then
    {name: $name, kind: "updated", old: $ov, new: $nv}
  else empty end
] as $changes |

($changes | map(
  if .kind == "updated" then
    "- \(.name): \(.old.commit[0:7]) → \(.new.commit[0:7])"
  elif .kind == "added" then
    "- \(.name): added (\(.new.commit[0:7]))"
  else
    "- \(.name): removed"
  end
)) as $lines |

(if ($changes | length) > 0 then
   ($changes | map(.name) | join(", ")) as $joined |
   ("chore(nvim): update \($joined)") as $candidate |
   if ($candidate | length) > 72 then
     "chore(nvim): update \($changes | length) nvim plugins"
   else $candidate end
 else "" end) as $subject |

{
  changed: ($subject != ""),
  subject: $subject,
  body: ($lines | join("\n"))
}