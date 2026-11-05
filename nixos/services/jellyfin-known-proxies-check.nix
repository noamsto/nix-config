# Regression check for jellyfin-known-proxies: runs the shipped script against
# a missing file, a populated network.xml, a rerun and a file lacking the element.
{pkgs}: let
  script = import ./jellyfin-known-proxies.nix {inherit pkgs;};
in
  pkgs.runCommand "jellyfin-known-proxies-check" {
    nativeBuildInputs = [script pkgs.xmlstarlet pkgs.diffutils];
  } ''
    proxies() {
      xmlstarlet sel -t -m '/NetworkConfiguration/KnownProxies/string' -v . -o , "$1"
    }
    setting() {
      xmlstarlet sel -t -v "/NetworkConfiguration/$2" "$1"
    }
    expect() {
      if [ "$2" != "$3" ]; then
        echo "FAIL $1: got '$2', want '$3'" >&2
        exit 1
      fi
    }
    show() {
      echo "--- $1: input ---"
      if [ -e "$2" ]; then cat "$2"; else echo "(missing)"; fi
    }
    showout() {
      echo "--- $1: output ---"
      cat "$2"
    }

    # (i) missing file
    f=$TMPDIR/missing.xml
    show "missing file" $f
    jellyfin-known-proxies $f 192.0.2.10 proxy.example.test
    showout "missing file" $f
    expect missing "$(proxies $f)" "192.0.2.10,proxy.example.test,"

    # (ii) xsi/xsd root, other settings, stale proxies
    f=$TMPDIR/populated.xml
    cat > $f <<'XML'
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <BaseUrl>/jf</BaseUrl>
      <EnableUPnP>true</EnableUPnP>
      <KnownProxies>
        <string>198.51.100.1</string>
        <string>198.51.100.2</string>
      </KnownProxies>
      <PublicHttpPort>8096</PublicHttpPort>
    </NetworkConfiguration>
    XML
    sed -i 's/^    //' $f
    show "populated" $f
    jellyfin-known-proxies $f 192.0.2.10 100.64.0.1
    showout "populated" $f
    expect populated "$(proxies $f)" "192.0.2.10,100.64.0.1,"
    expect baseurl "$(setting $f BaseUrl)" "/jf"
    expect upnp "$(setting $f EnableUPnP)" "true"
    expect port "$(setting $f PublicHttpPort)" "8096"
    grep -q 'xmlns:xsi=' $f || { echo "FAIL: xsi namespace lost" >&2; exit 1; }
    grep -q 'xmlns:xsd=' $f || { echo "FAIL: xsd namespace lost" >&2; exit 1; }

    # (iii) idempotent rerun
    cp $f $TMPDIR/before.xml
    jellyfin-known-proxies $f 192.0.2.10 100.64.0.1
    showout "rerun" $f
    cmp $TMPDIR/before.xml $f

    # (iv) no KnownProxies element
    f=$TMPDIR/noelement.xml
    cat > $f <<'XML'
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration>
      <EnableUPnP>false</EnableUPnP>
    </NetworkConfiguration>
    XML
    sed -i 's/^    //' $f
    show "no element" $f
    jellyfin-known-proxies $f 192.0.2.10
    showout "no element" $f
    expect noelement "$(proxies $f)" "192.0.2.10,"
    expect upnp2 "$(setting $f EnableUPnP)" "false"

    touch $out
  ''
