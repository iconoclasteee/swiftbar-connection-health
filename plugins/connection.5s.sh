#!/bin/bash
#
# Connection health — a SwiftBar plugin
#
# Menu bar: a coloured dot plus a FIXED-WIDTH text (always 5 characters).
# The fixed width is the whole point: without it, going from "42 ms" to "120 ms"
# widens the indicator and shifts every icon sitting to its left in the menu bar.
#
#   🟢 42 ms   healthy (< 80 ms)        🟠 200ms   fair (150-279 ms)
#   🟡 120ms   good (80-149 ms)         🔴 400ms   poor (>= 280 ms)
#   🔴 1834   >= 1000 ms: the unit is dropped, the value stays exact
#   ⚫ -OFF-   no network at all -> switch connection (Wi-Fi / cellular)
#   🚫 LOGIN   captive portal -> open a browser and sign in
#
# The full state wording stays readable in the dropdown ("Quality" line), together
# with a raw-network / DNS breakdown of what exactly is broken.
#
# The "5s" in the filename tells SwiftBar to re-run this script every 5 s.
# Rename to connection.3s.sh for faster outage detection (~5 s instead of ~7 s).
#
# Self-tests (no network required):  ./connection.5s.sh --test
#
# <bitbar.title>Connection health</bitbar.title>
# <bitbar.version>2.0</bitbar.version>
# <bitbar.author>Olivier Rhein</bitbar.author>
# <bitbar.desc>Latency and internet connection state in the menu bar, fixed width.</bitbar.desc>

# ----------------------------------------------------------------------------
# SETTINGS
# ----------------------------------------------------------------------------
UI_LANG="auto"                              # "fr" | "en" | "auto" (follow macOS, English fallback)
URL="http://www.gstatic.com/generate_204"   # "204" endpoint — http on purpose: detects captive portals
TIMEOUT=2                                   # seconds before declaring the link dead
EXT_IP_TTL=180                              # external-IP cache (s) — keeps network calls and data use down
SSID_TTL=30                                 # Wi-Fi name cache (s) — the name rarely changes

# Font of the menu bar line. A MONOSPACE font guarantees that 5 characters means 5
# identical widths in every case, text labels (-OFF-, LOGIN) included.
# "Menlo-Regular" ships with every macOS. SF Mono is NOT usable here: the system only
# exposes ".SF NS Mono", an internal name NSFont refuses (checked via NSFontManager).
# BAR_FONT="" falls back to the system font: numeric values stay aligned thanks to the
# figure space (see fmt_bar), only -OFF- / LOGIN shift slightly.
BAR_FONT="Menlo-Regular"
BAR_SIZE=""                                 # e.g. 12 if Menlo looks too big; "" = SwiftBar default

# Info lines are made "active" (a no-op click target) so macOS does not grey them out,
# which in turn makes color= apply. Shade picked at runtime for light / dark mode.
INFO_LIGHT="#555555"; INFO_DARK="#aaaaaa"
defaults read -g AppleInterfaceStyle 2>/dev/null | grep -qi dark && G="$INFO_DARK" || G="$INFO_LIGHT"
INFO="bash=/usr/bin/true terminal=false refresh=false color=$G"
# Same shade, but clickable: opens the macOS Wi-Fi settings pane.
WIFI_PANE="x-apple.systempreferences:com.apple.wifi-settings-extension"
INFO_WIFI="bash=/usr/bin/open param1=$WIFI_PANE terminal=false refresh=true color=$G"

# Latency thresholds in ms -> colour
T_GREEN=80     # < 80       : 🟢 healthy
T_YELLOW=150   # 80 to 149  : 🟡 good
T_ORANGE=280   # 150 to 279 : 🟠 fair   |   >= 280 : 🔴 poor

# ----------------------------------------------------------------------------
# LOCALISATION
# ----------------------------------------------------------------------------
# One function, one case per language. bash 3.2 (the /bin/bash macOS ships) has no
# associative arrays, so a case statement is the readable option here.
# Values holding %s are printf formats — see the call sites.
# The two menu bar tokens -OFF- and LOGIN are deliberately NOT translated: they are
# language-neutral and must stay exactly 5 characters wide.
# ----------------------------------------------------------------------------
if [ "$UI_LANG" = "auto" ]; then
  case "$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n"()' | cut -d, -f1)" in
    fr*) UI_LANG=fr ;;
    *)   UI_LANG=en ;;
  esac
fi

t() { # t <key> -> localized string
  if [ "$UI_LANG" = "fr" ]; then
    case "$1" in
      q_healthy)   echo "sain" ;;
      q_good)      echo "correct" ;;
      q_fair)      echo "moyen" ;;
      q_poor)      echo "mauvais" ;;
      q_offline)   echo "hors-ligne" ;;
      q_captive)   echo "pas d'internet" ;;
      net)         echo "Réseau : %s (%s)" ;;
      net_noname)  echo "Réseau : %s · nom indisponible (autorise WifiSSID dans Localisation)" ;;
      net_nohelp)  echo "Réseau : %s · nom Wi-Fi masqué (helper non installé : helper/build.sh)" ;;
      none)        echo "aucun" ;;
      lan)         echo "IP locale : %s" ;;
      lan_none)    echo "IP locale : aucune (pas de bail DHCP)" ;;
      lan_self)    echo "IP locale : %s ⚠️ auto-attribuée (DHCP en échec)" ;;
      gw)          echo "Passerelle : %s" ;;
      gw_none)     echo "Passerelle : aucune" ;;
      ext)         echo "IP externe : %s" ;;
      quality)     echo "Qualité : %s" ;;
      latency)     echo "Latence : %s ms (RTT TCP)" ;;
      raw)         echo "Réseau brut : %s" ;;
      dns)         echo "DNS : %s" ;;
      cause_link)  echo "Aucun réseau — change de connexion (Wi-Fi / données mobiles)" ;;
      cause_dns)   echo "Réseau OK mais DNS en rade — change de DNS" ;;
      cause_web)   echo "Réseau + DNS OK mais le web ne répond pas (FAI / filtrage ?)" ;;
      checked)     echo "Vérifié à : %s" ;;
      refresh)     echo "🔄 Tester maintenant" ;;
      open_script) echo "⚙️ Ouvrir le script" ;;
    esac
  else
    case "$1" in
      q_healthy)   echo "healthy" ;;
      q_good)      echo "good" ;;
      q_fair)      echo "fair" ;;
      q_poor)      echo "poor" ;;
      q_offline)   echo "offline" ;;
      q_captive)   echo "no internet" ;;
      net)         echo "Network: %s (%s)" ;;
      net_noname)  echo "Network: %s · name unavailable (allow WifiSSID under Location Services)" ;;
      net_nohelp)  echo "Network: %s · Wi-Fi name hidden (helper not installed: helper/build.sh)" ;;
      none)        echo "none" ;;
      lan)         echo "Local IP: %s" ;;
      lan_none)    echo "Local IP: none (no DHCP lease)" ;;
      lan_self)    echo "Local IP: %s ⚠️ self-assigned (DHCP failed)" ;;
      gw)          echo "Gateway: %s" ;;
      gw_none)     echo "Gateway: none" ;;
      ext)         echo "External IP: %s" ;;
      quality)     echo "Quality: %s" ;;
      latency)     echo "Latency: %s ms (TCP RTT)" ;;
      raw)         echo "Raw network: %s" ;;
      dns)         echo "DNS: %s" ;;
      cause_link)  echo "No network — switch connection (Wi-Fi / cellular)" ;;
      cause_dns)   echo "Network OK but DNS is down — change DNS" ;;
      cause_web)   echo "Network + DNS OK but the web is silent (ISP / filtering?)" ;;
      checked)     echo "Checked at: %s" ;;
      refresh)     echo "🔄 Test now" ;;
      open_script) echo "⚙️ Open the script" ;;
    esac
  fi
}

# say <key> [printf args...] -> localized line, ready to append SwiftBar params to
say() { local k="$1"; shift; printf "$(t "$k")" "$@"; }

# ----------------------------------------------------------------------------
# PURE FUNCTION: state(curl_exit, http_code, latency_ms) -> "dot|state_key"
# Returns a language-independent KEY, never a display string: the tests below assert
# on keys, and translation happens at print time only.
# No network dependency -> testable offline via ./connection.5s.sh --test
# ----------------------------------------------------------------------------
state() {
  local ok="$1" code="$2" lat="$3"
  if [ "$ok" != "0" ];     then echo "⚫|offline"; return; fi
  if [ "$code" != "204" ]; then echo "🚫|captive"; return; fi
  if   [ "$lat" -lt "$T_GREEN" ];  then echo "🟢|healthy"
  elif [ "$lat" -lt "$T_YELLOW" ]; then echo "🟡|good"
  elif [ "$lat" -lt "$T_ORANGE" ]; then echo "🟠|fair"
  else                                  echo "🔴|poor"
  fi
}

# ----------------------------------------------------------------------------
# PURE FUNCTION: fmt_bar(state_key, latency_ms) -> menu bar text
# No network dependency -> testable offline via ./connection.5s.sh --test
#
# Contract: the output is ALWAYS 5 characters.
#   9 ms    -> "09 ms"   leading zero: a real digit, never trimmed like a space
#   42 ms   -> "42 ms"
#   120 ms  -> "120ms"
#   1834 ms -> "1834 "   past 999 ms the unit is dropped rather than the value
#   offline -> "-OFF-"   no network (a state: the only move is to switch connection)
#   captive -> "LOGIN"   captive portal (an action: sign in from a browser)
#
# Two mechanisms stack up to keep the width stable:
#   - a monospace BAR_FONT -> 5 characters = 5 identical widths, letters included;
#   - the figure space U+2007, exactly as wide as a digit, which keeps numeric values
#     aligned even under the proportional system font (BAR_FONT="").
# ----------------------------------------------------------------------------
FIGSP=$'\xe2\x80\x87'   # U+2007 FIGURE SPACE — exactly one digit wide (bash 3.2 has no \u)

fmt_bar() {
  local st="$1" lat="$2"
  case "$st" in
    offline) printf '%s' "-OFF-"; return ;;
    captive) printf '%s' "LOGIN"; return ;;
  esac
  [ "$lat" -gt 9999 ] && lat=9999        # guard: TIMEOUT=2 s already caps the measure near 2000 ms
  if   [ "$lat" -ge 1000 ]; then printf '%d%s' "$lat" "$FIGSP"
  elif [ "$lat" -ge 100 ];  then printf '%dms' "$lat"
  else                           printf '%02d%sms' "$lat" "$FIGSP"
  fi
}

# ----------------------------------------------------------------------------
# SELF-TEST MODE (the part that is verifiable without a network)
# ----------------------------------------------------------------------------
if [ "$1" = "--test" ]; then
  fail=0
  check() { # $1=expected  then the args of state()
    local exp="$1"; shift
    local got; got="$(state "$@")"
    if [ "$got" = "$exp" ]; then echo "ok    state($*) = $got"
    else echo "FAIL  state($*) = $got  (expected: $exp)"; fail=1; fi
  }
  check "⚫|offline" 1 000 0
  check "🚫|captive" 0 200 10
  check "🟢|healthy" 0 204 13
  check "🟢|healthy" 0 204 79
  check "🟡|good"    0 204 80
  check "🟡|good"    0 204 149
  check "🟠|fair"    0 204 150
  check "🟠|fair"    0 204 279
  check "🔴|poor"    0 204 280
  check "🔴|poor"    0 204 800

  # Width contract: the menu bar line is always 5 characters
  checkw() { # $1=expected  $2=state_key  $3=latency_ms
    local exp="$1"; shift
    local got n; got="$(fmt_bar "$@")"; n=${#got}
    if [ "$got" = "$exp" ] && [ "$n" = "5" ]; then echo "ok    fmt_bar($*) = [$got] ($n chars)"
    else echo "FAIL  fmt_bar($*) = [$got] ($n chars)  (expected: [$exp], 5 chars)"; fail=1; fi
  }
  checkw "-OFF-"        offline 0
  checkw "LOGIN"        captive 0
  checkw "09${FIGSP}ms" healthy 9
  checkw "42${FIGSP}ms" healthy 42
  checkw "99${FIGSP}ms" good 99
  checkw "100ms"        good 100
  checkw "999ms"        poor 999
  checkw "1000${FIGSP}" poor 1000
  checkw "1834${FIGSP}" poor 1834
  checkw "9999${FIGSP}" poor 40000

  # Every key must resolve in both languages: a missing case arm returns an empty string
  KEYS="q_healthy q_good q_fair q_poor q_offline q_captive net net_noname net_nohelp none
        lan lan_none lan_self gw gw_none ext quality latency raw dns cause_link cause_dns
        cause_web checked refresh open_script"
  for l in fr en; do
    UI_LANG="$l"
    for k in $KEYS; do
      if [ -n "$(t "$k")" ]; then echo "ok    t($l, $k) = $(t "$k")"
      else echo "FAIL  t($l, $k) is empty"; fail=1; fi
    done
  done

  [ "$fail" = "0" ] && echo "--- ALL TESTS PASS" || echo "--- FAILURE"
  exit $fail
fi

# ----------------------------------------------------------------------------
# THE ACTUAL PROBE
# ----------------------------------------------------------------------------
out=$(curl -s -o /dev/null --max-time "$TIMEOUT" \
  -w '%{http_code} %{time_namelookup} %{time_connect}' "$URL" 2>/dev/null)
curl_ok=$?
read -r code dns connect <<< "$out"

# latency = TCP handshake RTT = (time_connect - time_namelookup), in ms.
# Not the total request time, which would inflate the figure 3-4x.
if [ "$curl_ok" -eq 0 ] && [ -n "$connect" ]; then
  lat=$(awk -v c="$connect" -v d="$dns" 'BEGIN{ v=(c-d)*1000; if(v<0)v=0; printf "%d", v }')
else
  lat=0
fi

# Real internet access? Drives the raw-network / DNS breakdown and the external-IP call.
if [ "$curl_ok" -eq 0 ] && [ "$code" = "204" ]; then has_net=1; else has_net=0; fi

IFS='|' read -r dot st <<< "$(state "$curl_ok" "${code:-000}" "$lat")"

# ----------------------------------------------------------------------------
# BREAKDOWN: RAW NETWORK vs DNS  (only when the main probe failed)
# Telling "no network at all" apart from "internet fine but DNS is down" needs TWO
# signals that do not depend on DNS. On the healthy path a request to a NAME already
# succeeded => network and DNS are both fine, so no extra call is made.
# ----------------------------------------------------------------------------
if [ "$has_net" -eq 1 ]; then
  link_ok=1; dns_ok=1; cause=""
else
  nc -z -G 1 -w 1 1.1.1.1 443 >/dev/null 2>&1 && link_ok=1 || link_ok=0   # raw network (IP, no DNS)
  host -W 1 example.com       >/dev/null 2>&1 && dns_ok=1  || dns_ok=0    # name resolution
  if   [ "$link_ok" -eq 0 ]; then cause="$(t cause_link)"
  elif [ "$dns_ok"  -eq 0 ]; then cause="$(t cause_dns)"
  else                            cause="$(t cause_web)"
  fi
fi

# ----------------------------------------------------------------------------
# SWIFTBAR OUTPUT
# ----------------------------------------------------------------------------
# 1) Menu bar line — fixed width (see fmt_bar) so neighbouring icons never shift.
#    color=white lets the text follow the menu bar theme; the emoji dot keeps its own
#    colour. font/size are only emitted when set (${VAR:+…} adds nothing when empty).
echo "$dot $(fmt_bar "$st" "$lat") | color=white${BAR_FONT:+ font=$BAR_FONT}${BAR_SIZE:+ size=$BAR_SIZE}"

# 2) Dropdown (on click)
echo "---"
iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')

# Link type (Wi-Fi / iPhone USB / Bluetooth PAN…) — available without any permission
link=$(networksetup -listnetworkserviceorder 2>/dev/null \
        | grep "Device: ${iface})" | sed -E 's/.*Hardware Port: ([^,]+),.*/\1/' | head -1)

# Wi-Fi name (SSID): macOS hides it ("<redacted>") unless the caller is authorised for
# Location Services. We delegate to a small signed helper (see helper/) whose grant is
# bound to its own identity. Cached for SSID_TTL s so the helper is not re-run on every
# refresh. Note the support directory is named "connexion-menubar" for historical reasons:
# the Location grant is tied to that path and bundle id, renaming it would revoke it.
SSID_HELPER="$HOME/Library/Application Support/connexion-menubar/WifiSSID.app/Contents/MacOS/WifiSSID"
SSID_CACHE="${TMPDIR:-/tmp}/swiftbar_connection_ssid"
ssid=""
if [ -f "$SSID_CACHE" ] && [ "$(( $(date +%s) - $(stat -f %m "$SSID_CACHE" 2>/dev/null || echo 0) ))" -lt "$SSID_TTL" ]; then
  ssid=$(cat "$SSID_CACHE" 2>/dev/null)
elif [ -x "$SSID_HELPER" ]; then
  ssid=$("$SSID_HELPER" 2>/dev/null)
  [ -n "$ssid" ] && printf '%s' "$ssid" > "$SSID_CACHE"
fi
if [ -n "$ssid" ]; then
  echo "$(say net "$ssid" "${link:-$iface}") | $INFO_WIFI"
elif [ -x "$SSID_HELPER" ]; then
  echo "$(say net_noname "${link:-${iface:-$(t none)}}") | $INFO_WIFI"
else
  echo "$(say net_nohelp "${link:-${iface:-$(t none)}}") | $INFO_WIFI"
fi

# Local (private) IP — instant, fully local; 169.254.x means no DHCP lease.
# ipconfig getifaddr only reports addresses handed out by the IPConfiguration service.
# On iPhone Personal Hotspot the interface carries a 192.0.0.x address it does not report,
# so fall back to ifconfig before claiming there is no lease.
lan_ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
[ -z "$lan_ip" ] && lan_ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet /{print $2; exit}')
if [ -z "$lan_ip" ]; then
  echo "$(t lan_none) | $INFO"
elif [ "${lan_ip#169.254.}" != "$lan_ip" ]; then
  echo "$(say lan_self "$lan_ip") | $INFO"
else
  echo "$(say lan "$lan_ip") | $INFO"
fi

# Default gateway (the router, LAN side) — clickable: opens its admin interface
gw=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')
if [ -n "$gw" ]; then echo "$(say gw "$gw") | href=http://$gw"
else                  echo "$(t gw_none) | $INFO"
fi

# External (public) IP — one network call, cached EXT_IP_TTL s. It changes when you
# switch networks, which makes it a direct confirmation that the switch happened.
if [ "$has_net" -eq 1 ]; then
  ext_cache="${TMPDIR:-/tmp}/swiftbar_connection_extip"
  if [ -f "$ext_cache" ] && [ "$(( $(date +%s) - $(stat -f %m "$ext_cache" 2>/dev/null || echo 0) ))" -lt "$EXT_IP_TTL" ]; then
    ext_ip=$(cat "$ext_cache" 2>/dev/null)
  else
    ext_ip=$(curl -s --max-time 2 https://api.ipify.org)
    [ -n "$ext_ip" ] && printf '%s' "$ext_ip" > "$ext_cache"
  fi
  [ -n "$ext_ip" ] && echo "$(say ext "$ext_ip") | $INFO"
fi

echo "$(say quality "$(t "q_$st")") | $INFO"
[ "$has_net" -eq 1 ] && echo "$(say latency "$lat") | $INFO"
echo "$(say raw "$([ "$link_ok" -eq 1 ] && echo "✅" || echo "❌")") | $INFO"
echo "$(say dns "$([ "$dns_ok"  -eq 1 ] && echo "✅" || echo "❌")") | $INFO"
# Cause line — clickable: opens the macOS Wi-Fi pane so you can switch connection
[ -n "$cause" ] && echo "→ $cause | bash=/usr/bin/open param1=$WIFI_PANE terminal=false refresh=true"
echo "$(say checked "$(date '+%H:%M:%S')") | $INFO"
echo "---"
echo "$(t refresh) | refresh=true"
echo "$(t open_script) | bash=/usr/bin/open param1=-t param2=$0 terminal=false"
