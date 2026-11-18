setup() {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$XDG_CONFIG_HOME/btop"
  export DARK_THEME_NAME=catppuccin_mocha LIGHT_THEME_NAME=catppuccin_latte
  export DARK_BLUE_RAW=000000 DARK_LAVENDER_RAW=000000
  export LIGHT_BLUE_RAW=ffffff LIGHT_LAVENDER_RAW=ffffff
  # shellcheck source=/dev/null
  source "$THEME_APPLY_LIB"
}

# Two overlapping runs, 0-5 ms apart, many times; the file must never be
# emptied or lose its other lines.
race() {
  local fn="$1" file="$2" i
  for i in $(seq 200); do
    printf '%s\n' "$SEED" >"$file"
    "$fn" dark &
    sleep "0.00$((i % 6))"
    "$fn" light &
    wait
    [[ -s $file ]] || { echo "iteration $i: $file is empty"; return 1; }
    grep -q '^keep = 1$' "$file" || { echo "iteration $i: lost keep line"; return 1; }
  done
}

@test "concurrent update_starship never empties starship.toml" {
  SEED=$'palette = "x"\nkeep = 1'
  race update_starship "$XDG_CONFIG_HOME/starship.toml"
}

@test "concurrent update_btop never empties btop.conf" {
  SEED=$'color_theme = "x"\nkeep = 1'
  race update_btop "$XDG_CONFIG_HOME/btop/btop.conf"
}

@test "update_btop on a read-only symlink keeps other settings" {
  printf 'color_theme = "old"\nvim_keys = True\n' >"$BATS_TEST_TMPDIR/store-btop.conf"
  chmod 444 "$BATS_TEST_TMPDIR/store-btop.conf"
  ln -s "$BATS_TEST_TMPDIR/store-btop.conf" "$XDG_CONFIG_HOME/btop/btop.conf"
  update_btop light
  [ ! -L "$XDG_CONFIG_HOME/btop/btop.conf" ]
  [ -w "$XDG_CONFIG_HOME/btop/btop.conf" ]
  grep -qx 'vim_keys = True' "$XDG_CONFIG_HOME/btop/btop.conf"
  grep -qx 'color_theme = "catppuccin_latte.theme"' "$XDG_CONFIG_HOME/btop/btop.conf"
}

@test "update_btop appends color_theme when absent from a read-only file" {
  printf 'vim_keys = True\n' >"$BATS_TEST_TMPDIR/store-btop.conf"
  chmod 444 "$BATS_TEST_TMPDIR/store-btop.conf"
  ln -s "$BATS_TEST_TMPDIR/store-btop.conf" "$XDG_CONFIG_HOME/btop/btop.conf"
  update_btop dark
  grep -qx 'vim_keys = True' "$XDG_CONFIG_HOME/btop/btop.conf"
  grep -qx 'color_theme = "catppuccin_mocha.theme"' "$XDG_CONFIG_HOME/btop/btop.conf"
}

@test "theme_apply_lock serialises concurrent runs" {
  printf 'palette = "x"\n' >"$XDG_CONFIG_HOME/starship.toml"
  harness="$BATS_TEST_TMPDIR/harness.sh"
  cat >"$harness" <<HARNESS
source "$THEME_APPLY_LIB"
theme_apply_lock
echo "start \$1" >>"$BATS_TEST_TMPDIR/log"
sleep 1
update_starship "\$1"
echo "end \$1" >>"$BATS_TEST_TMPDIR/log"
HARNESS
  bash "$harness" dark &
  sleep 0.3
  bash "$harness" light &
  wait
  run cat "$BATS_TEST_TMPDIR/log"
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = "start dark" ]
  [ "${lines[1]}" = "end dark" ]
  [ "${lines[2]}" = "start light" ]
  [ "${lines[3]}" = "end light" ]
  grep -q catppuccin_latte "$XDG_CONFIG_HOME/starship.toml"
}
