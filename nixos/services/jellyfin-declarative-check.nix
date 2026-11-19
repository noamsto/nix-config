# Regression check for jellyfin-declarative: runs the shipped script against a mock
# Jellyfin API and a stub systemctl, covering convergence, idempotence and failure paths.
{pkgs}: let
  script = import ./jellyfin-declarative.nix {inherit pkgs;};
  mock = pkgs.writeText "jellyfin-mock.py" ''
    import json
    import os
    import re
    import sys
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    state = json.load(open(sys.argv[1]))
    portfile = sys.argv[2]


    def norm(s):
        return s.replace("-", "").lower()


    state["configs"] = {norm(k): v for k, v in state.get("configs", {}).items()}
    state.update(configPosts=0, libraryPosts=0, restarts=0)


    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, code, body=None):
            data = b"" if body is None else json.dumps(body).encode()
            self.send_response(code)
            if body is not None:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def route(self, method):
            path = self.path.split("?")[0]
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b""

            if path == "/_mock/restart" and method == "POST":
                state["restarts"] += 1
                if not state.get("stickyRestart"):
                    for p in state["plugins"]:
                        if p["Status"] == "Restart":
                            p["Status"] = "Active"
                return self.reply(204)
            if path == "/_mock/state" and method == "GET":
                return self.reply(200, state)
            if path == "/System/Info/Public" and method == "GET":
                return self.reply(200, {"Version": "mock"})

            if 'Token="testkey"' not in (self.headers.get("Authorization") or ""):
                return self.reply(401)

            if path == "/Plugins" and method == "GET":
                return self.reply(200, state["plugins"])

            m = re.fullmatch(r"/Plugins/([^/]+)/Configuration", path)
            if m:
                pid = norm(m.group(1))
                plugin = next((p for p in state["plugins"] if norm(p["Id"]) == pid), None)
                if plugin is None or plugin["Status"] == "Restart":
                    return self.reply(404)
                if method == "GET":
                    return self.reply(200, state["configs"].get(pid, {}))
                if method == "POST":
                    state["configs"][pid] = json.loads(raw)
                    state["configPosts"] += 1
                    return self.reply(204)

            if path == "/Library/VirtualFolders" and method == "GET":
                return self.reply(200, state["folders"])

            if path == "/Library/VirtualFolders/LibraryOptions" and method == "POST":
                body = json.loads(raw)
                folder = next((f for f in state["folders"] if f["ItemId"] == body["Id"]), None)
                if folder is None:
                    return self.reply(404)
                folder["LibraryOptions"] = body["LibraryOptions"]
                state["libraryPosts"] += 1
                return self.reply(204)

            return self.reply(404)

        def do_GET(self):
            self.route("GET")

        def do_POST(self):
            self.route("POST")


    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(portfile + ".tmp", "w") as f:
        f.write(str(server.server_address[1]))
    os.replace(portfile + ".tmp", portfile)
    server.serve_forever()
  '';
in
  pkgs.runCommand "jellyfin-declarative-check" {
    nativeBuildInputs = [script pkgs.python3 pkgs.jq pkgs.curl];
  } ''
    mkdir -p $TMPDIR/bin $TMPDIR/logs
    cat > $TMPDIR/bin/systemctl <<'STUB'
    #!${pkgs.runtimeShell}
    echo "$*" >> "$TMPDIR/systemctl.log"
    if [ "$1" = restart ]; then
      curl -fsS -X POST "$MOCK/_mock/restart"
    fi
    STUB
    chmod +x $TMPDIR/bin/systemctl
    export PATH=$TMPDIR/bin:$PATH

    sentinelUser=os-user
    sentinelPw='s3cret pass'
    printf '  %s\n' "$sentinelUser" > $TMPDIR/user.txt
    printf ' %s \n' "$sentinelPw" > $TMPDIR/pass.txt
    printf 'testkey\n' > $TMPDIR/key.txt
    printf 'wrongkey\n' > $TMPDIR/bad.txt

    OSID=4b9ed42f-5185-48b5-9803-6ff2989014c4
    OSN=4b9ed42f518548b598036ff2989014c4
    OSCRED=$(jq -n --arg id "$OSID" --arg u $TMPDIR/user.txt --arg p $TMPDIR/pass.txt \
      '{pluginId: $id, usernameFile: $u, passwordFile: $p}')
    MOVIES='[{"name":"Movies","options":{"SubtitleDownloadLanguages":["heb"],"RequirePerfectSubtitleMatch":false}}]'

    MOCKPID=
    CASELOG=/dev/null
    trap '[ -z "$MOCKPID" ] || kill "$MOCKPID" 2>/dev/null || true' EXIT

    fail() {
      echo "FAIL $1" >&2
      echo "--- script log ---" >&2
      cat "$CASELOG" >&2
      echo "--- systemctl log ---" >&2
      cat $TMPDIR/systemctl.log >&2 || true
      exit 1
    }
    expect() {
      if [ "$2" != "$3" ]; then
        fail "$1: got '$2', want '$3'"
      fi
    }

    start_mock() {
      rm -f $TMPDIR/port $TMPDIR/systemctl.log
      : > $TMPDIR/systemctl.log
      python3 ${mock} "$1" $TMPDIR/port 2> $TMPDIR/mock.log &
      MOCKPID=$!
      for _ in $(seq 100); do
        [ -s $TMPDIR/port ] && break
        sleep 0.1
      done
      [ -s $TMPDIR/port ] || { cat $TMPDIR/mock.log >&2; echo "FAIL: mock did not start" >&2; exit 1; }
      PORT=$(cat $TMPDIR/port)
      export MOCK=http://127.0.0.1:$PORT
    }
    stop_mock() {
      kill "$MOCKPID"
      wait "$MOCKPID" || true
      MOCKPID=
    }
    # mkcfg <out> <keyfile> <plugins json> <openSubtitles json> <libraries json>
    mkcfg() {
      jq -n --arg base "$MOCK" --arg key "$2" --argjson plugins "$3" --argjson os "$4" --argjson libs "$5" \
        '{baseUrl: $base, apiKeyFile: $key, jellyfinUnit: "jellyfin.service", jellarrUnit: "jellarr.service",
          readyTimeout: 5, plugins: $plugins, openSubtitles: $os, libraries: $libs}' > "$1"
    }
    # run_case <name> <config>: sets RC and CASELOG, keeps a copy of the systemctl log for hygiene
    run_case() {
      CASELOG=$TMPDIR/logs/$1.log
      RC=0
      jellyfin-declarative-apply "$2" > "$CASELOG" 2>&1 || RC=$?
      cp $TMPDIR/systemctl.log "$TMPDIR/logs/$1.systemctl.log"
      echo "--- $1: exit $RC ---"
      cat "$CASELOG"
    }
    state() {
      curl -fsS "$MOCK/_mock/state" > $TMPDIR/state.json
    }
    sj() {
      jq -c "$1" $TMPDIR/state.json
    }
    no_start() {
      if grep -q '^start --no-block' $TMPDIR/systemctl.log; then
        fail "$1: jellarr was started"
      fi
    }

    # (1) first run: pending Open Subtitles, existing library with extra keys
    cat > $TMPDIR/fix1.json <<JSON
    {"plugins": [
       {"Name": "Open Subtitles", "Id": "$OSN", "Version": "1.0", "Status": "Restart"},
       {"Name": "AniDB", "Id": "a1b2c3d4e5f60718293a4b5c6d7e8f90", "Version": "1.0", "Status": "Active"}],
     "configs": {"$OSN": {"Username": "", "Password": "", "CredentialsInvalid": true, "CustomKey": "keep"}},
     "folders": [{"Name": "Movies", "ItemId": "f00d", "LibraryOptions": {
       "EnableRealtimeMonitor": true, "PathInfos": [{"Path": "/mnt/movies"}],
       "SubtitleDownloadLanguages": [], "RequirePerfectSubtitleMatch": true}}]}
    JSON
    start_mock $TMPDIR/fix1.json
    mkcfg $TMPDIR/cfg1.json $TMPDIR/key.txt '["Open Subtitles"]' "$OSCRED" "$MOVIES"
    run_case case1 $TMPDIR/cfg1.json
    expect "1 exit" "$RC" 0
    expect "1 systemctl" "$(cat $TMPDIR/systemctl.log)" "$(printf 'restart jellyfin.service\nstart --no-block jellarr.service')"
    state
    expect "1 config" "$(sj ".configs[\"$OSN\"] | [.Username, .Password, .CredentialsInvalid, .CustomKey]")" '["os-user","s3cret pass",false,"keep"]'
    expect "1 library" "$(sj '.folders[0].LibraryOptions | [.EnableRealtimeMonitor, .PathInfos[0].Path, .SubtitleDownloadLanguages, .RequirePerfectSubtitleMatch]')" '[true,"/mnt/movies",["heb"],false]'
    expect "1 counters" "$(sj '[.configPosts, .libraryPosts, .restarts]')" '[1,1,1]'

    # (2) rerun against the same mock: nothing to do
    cp $TMPDIR/systemctl.log $TMPDIR/systemctl.before
    run_case case2 $TMPDIR/cfg1.json
    expect "2 exit" "$RC" 0
    expect "2 systemctl" "$(cat $TMPDIR/systemctl.log)" "$(cat $TMPDIR/systemctl.before)"
    state
    expect "2 counters" "$(sj '[.configPosts, .libraryPosts, .restarts]')" '[1,1,1]'
    stop_mock

    # (3) plugin active, same credentials but flagged invalid: exactly one POST resets the flag
    cat > $TMPDIR/fix3.json <<JSON
    {"plugins": [{"Name": "Open Subtitles", "Id": "$OSN", "Version": "1.0", "Status": "Active"}],
     "configs": {"$OSN": {"Username": "$sentinelUser", "Password": "$sentinelPw", "CredentialsInvalid": true, "CustomKey": "keep"}},
     "folders": []}
    JSON
    start_mock $TMPDIR/fix3.json
    mkcfg $TMPDIR/cfg3.json $TMPDIR/key.txt '["Open Subtitles"]' "$OSCRED" '[]'
    run_case case3 $TMPDIR/cfg3.json
    expect "3 exit" "$RC" 0
    state
    expect "3 config" "$(sj ".configs[\"$OSN\"] | [.Username, .Password, .CredentialsInvalid, .CustomKey]")" '["os-user","s3cret pass",false,"keep"]'
    expect "3 counters" "$(sj '[.configPosts, .libraryPosts, .restarts]')" '[1,0,0]'
    expect "3 systemctl" "$(cat $TMPDIR/systemctl.log)" ""
    stop_mock

    # (5) declared plugin absent while another one restarts: fails, jellarr not started
    cat > $TMPDIR/fix5.json <<'JSON'
    {"plugins": [{"Name": "Other", "Id": "a1b2c3d4e5f60718293a4b5c6d7e8f90", "Version": "1.0", "Status": "Restart"}],
     "configs": {}, "folders": []}
    JSON
    start_mock $TMPDIR/fix5.json
    mkcfg $TMPDIR/cfg5.json $TMPDIR/key.txt '["Open Subtitles","Other"]' "$OSCRED" '[]'
    run_case case5 $TMPDIR/cfg5.json
    [ "$RC" != 0 ] || fail "5: expected a non-zero exit"
    grep -q 'plugin Open Subtitles: not installed' "$CASELOG" || fail "5: missing failure message"
    expect "5 restarts" "$(grep -c '^restart' $TMPDIR/systemctl.log)" 1
    no_start 5
    stop_mock

    # (6) declared library absent
    cat > $TMPDIR/fix6.json <<JSON
    {"plugins": [{"Name": "Open Subtitles", "Id": "$OSN", "Version": "1.0", "Status": "Restart"}],
     "configs": {"$OSN": {}}, "folders": [{"Name": "Shows", "ItemId": "beef", "LibraryOptions": {}}]}
    JSON
    start_mock $TMPDIR/fix6.json
    mkcfg $TMPDIR/cfg6.json $TMPDIR/key.txt '["Open Subtitles"]' null "$MOVIES"
    run_case case6 $TMPDIR/cfg6.json
    [ "$RC" != 0 ] || fail "6: expected a non-zero exit"
    grep -q 'library Movies: not found' "$CASELOG" || fail "6: missing failure message"
    no_start 6
    stop_mock

    # (7) plugin stays in Restart after the restart: one restart, no jellarr start
    cat > $TMPDIR/fix7.json <<JSON
    {"stickyRestart": true,
     "plugins": [{"Name": "Open Subtitles", "Id": "$OSN", "Version": "1.0", "Status": "Restart"}],
     "configs": {}, "folders": []}
    JSON
    start_mock $TMPDIR/fix7.json
    mkcfg $TMPDIR/cfg7.json $TMPDIR/key.txt '["Open Subtitles"]' "$OSCRED" '[]'
    run_case case7 $TMPDIR/cfg7.json
    [ "$RC" != 0 ] || fail "7: expected a non-zero exit"
    expect "7 restarts" "$(grep -c '^restart' $TMPDIR/systemctl.log)" 1
    no_start 7
    stop_mock

    # (8) wrong API key: the mock rejects it, proving the header is sent and checked
    start_mock $TMPDIR/fix3.json
    mkcfg $TMPDIR/cfg8.json $TMPDIR/bad.txt '["Open Subtitles"]' "$OSCRED" '[]'
    run_case case8 $TMPDIR/cfg8.json
    [ "$RC" != 0 ] || fail "8: expected a non-zero exit"
    state
    expect "8 counters" "$(sj '[.configPosts, .libraryPosts, .restarts]')" '[0,0,0]'
    stop_mock

    # (4) log hygiene: no secret value reaches any script or systemctl log
    CASELOG=/dev/null
    for needle in s3cret os-user testkey; do
      if grep -rqF -- "$needle" $TMPDIR/logs; then
        echo "FAIL 4: '$needle' leaked into a log" >&2
        exit 1
      fi
    done

    touch $out
  ''
