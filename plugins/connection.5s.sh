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
# The "5s" in the filename tells SwiftBar to re-run this script every 5 s. Do not go
# below that: on a dead link the probe chain costs about 3 s (curl 2 s, then the raw-IP
# and DNS checks in parallel), and a shorter interval would stack overlapping runs during
# the very outage the journal is meant to document.
#
# Self-tests (no network required):  ./connection.5s.sh --test
#
# <bitbar.title>Connection health</bitbar.title>
# <bitbar.version>2.5</bitbar.version>
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

# CSV journal — one row per refresh, meant to build evidence over days when an ISP
# says "we see nothing on our side". Logging is OFF until you switch it on from the
# dropdown; while it is off the extra ICMP probes below are never sent.
#   LOG_CSV=""  disables the feature entirely (the menu entries disappear).
LOG_CSV="${LOG_CSV:-$HOME/Library/Logs/connection-health.csv}"
LOG_FLAG="${LOG_FLAG:-$HOME/Library/Logs/.connection-health-logging}"   # this file exists => logging is on
UPLINK_IP="1.1.1.1"                         # pinged only while logging: uplink without DNS
# Column order: context first (when, where, what state), then one measurement block per
# layer — each RTT immediately followed by the address that was actually measured, so a
# row is self-explanatory without cross-referencing anything.
#   rtt_gw_ms     / gw_ip      your own gateway, over the LAN            -> your side
#   rtt_uplink_ms / uplink_ip  UPLINK_IP, raw ICMP, no DNS               -> the operator
#   rtt_web_ms    / web_ip     the host in URL, TCP handshake, resolved  -> the whole chain
# Kept in one constant because it is also the schema check — a journal whose header does
# not match this line is rotated aside rather than appended to, so two different column
# orders can never end up in the same file.
LOG_HEADER="timestamp;network;link;state;local_ip;rtt_gw_ms;gw_ip;rtt_uplink_ms;uplink_ip;rtt_web_ms;web_ip;raw_ok;dns_ok;epoch"

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
      log_on)      echo "📓 Journal actif · %s · %s relevés — ouvrir" ;;
      log_off)     echo "📓 Journal arrêté · %s conservés — ouvrir" ;;
      log_start)   echo "⏺ Démarrer le journal" ;;
      log_stop)    echo "⏹ Arrêter le journal…" ;;
      log_reveal)  echo "📂 Montrer dans le Finder" ;;
      ask_title)   echo "Journal de connexion" ;;
      ask_text)    echo "Suivi arrêté.\n\nVider le journal (%s relevés, %s) ou le conserver pour continuer plus tard ?" ;;
      ask_keep)    echo "Conserver" ;;
      ask_wipe)    echo "Vider" ;;
      path_space)  echo "⚠️ Boutons désactivés : un espace dans %s" ;;
      r_period)    echo "Période" ;;
      r_rows)      echo "Relevés" ;;
      r_gaps)      echo "Trous (Mac en veille / SwiftBar arrêté)" ;;
      r_bynet)     echo "Par réseau" ;;
      r_incidents) echo "Épisodes dégradés les plus longs" ;;
      r_none)      echo "Aucun épisode dégradé sur la période." ;;
      r_hdr_net)   echo "réseau" ;;
      r_hdr_rows)  echo "relevés" ;;
      r_hdr_ko)    echo "coupé" ;;
      r_hdr_slow)  echo "lent" ;;
      r_hdr_maxw)  echo "max web" ;;
      r_hdr_maxg)  echo "max box" ;;
      r_hdr_maxu)  echo "max uplink" ;;
      r_hdr_from)  echo "début" ;;
      r_hdr_dur)   echo "durée" ;;
      r_hdr_kind)  echo "nature" ;;
      r_empty)     echo "Journal vide ou introuvable : %s" ;;
      q_mixed)     echo "mixte" ;;
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
      log_on)      echo "📓 Journal running · %s · %s samples — open" ;;
      log_off)     echo "📓 Journal stopped · %s kept — open" ;;
      log_start)   echo "⏺ Start the journal" ;;
      log_stop)    echo "⏹ Stop the journal…" ;;
      log_reveal)  echo "📂 Reveal in Finder" ;;
      ask_title)   echo "Connection journal" ;;
      ask_text)    echo "Tracking stopped.\n\nWipe the journal (%s samples, %s) or keep it to continue later?" ;;
      ask_keep)    echo "Keep" ;;
      ask_wipe)    echo "Wipe" ;;
      path_space)  echo "⚠️ Buttons disabled: a space in %s" ;;
      r_period)    echo "Period" ;;
      r_rows)      echo "Samples" ;;
      r_gaps)      echo "Gaps (Mac asleep / SwiftBar stopped)" ;;
      r_bynet)     echo "Per network" ;;
      r_incidents) echo "Longest degraded episodes" ;;
      r_none)      echo "No degraded episode over the period." ;;
      r_hdr_net)   echo "network" ;;
      r_hdr_rows)  echo "samples" ;;
      r_hdr_ko)    echo "down" ;;
      r_hdr_slow)  echo "slow" ;;
      r_hdr_maxw)  echo "max web" ;;
      r_hdr_maxg)  echo "max gw" ;;
      r_hdr_maxu)  echo "max uplink" ;;
      r_hdr_from)  echo "from" ;;
      r_hdr_dur)   echo "length" ;;
      r_hdr_kind)  echo "kind" ;;
      r_empty)     echo "Journal empty or missing: %s" ;;
      q_mixed)     echo "mixed" ;;
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

# ping_ms <host> -> round-trip in whole milliseconds, or "" when there is no reply.
# One packet, 1 s ceiling: on a dead link this costs a second, never more.
ping_ms() {
  ping -c1 -W 1000 -n "$1" 2>/dev/null \
    | awk -F'time=' '/time=/{split($2,a," "); printf "%.0f", a[1]; exit}'
}

# csv <field...> -> one semicolon-separated row. Semicolons inside a value become commas
# so a Wi-Fi name can never shift the columns.
csv() { local out="" f; for f in "$@"; do out="$out;${f//;/,}"; done; printf '%s\n' "${out:1}"; }

# now -> "YYYY-MM-DD HH:MM:SS.cc|epoch.cc". macOS date has no sub-second format and
# /bin/bash is 3.2 (no EPOCHREALTIME), so perl provides the hundredths. Without them two
# rows of the same second are indistinguishable, which breaks sorting and de-duplication.
# Both halves are derived from the SAME truncation, so they always name the same instant.
now() {
  perl -MTime::HiRes=time -MPOSIX=strftime -e '
    my $t = time; my $i = int $t; my $c = int(($t - $i) * 100);
    printf "%s.%02d|%d.%02d", strftime("%Y-%m-%d %H:%M:%S", localtime $i), $c, $i, $c;
  ' 2>/dev/null || printf '%s.00|%s.00' "$(date '+%Y-%m-%d %H:%M:%S')" "$(date +%s)"
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
        cause_web checked refresh open_script log_on log_off log_start log_stop log_reveal
        ask_title ask_text ask_keep ask_wipe path_space r_period r_rows
        r_gaps r_bynet r_incidents r_none r_hdr_net r_hdr_rows r_hdr_ko r_hdr_slow r_hdr_maxw
        r_hdr_maxg r_hdr_maxu r_hdr_from r_hdr_dur r_hdr_kind r_empty q_mixed"
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
# STOP MODE — what the "Stop the journal" menu entry runs.
# Stopping and wiping are two different intents: pausing for a video call must not
# destroy three days of evidence. So stopping always asks, and Keep is the default
# button — a stray Return keeps the data.
# ----------------------------------------------------------------------------
if [ "$1" = "--stop" ]; then
  rm -f "$LOG_FLAG"
  if [ -s "$LOG_CSV" ]; then
    n=$(( $(wc -l < "$LOG_CSV") - 1 )); [ "$n" -lt 0 ] && n=0
    sz=$(du -h "$LOG_CSV" 2>/dev/null | awk '{print $1}')
    script=$(printf 'display dialog "%s" buttons {"%s", "%s"} default button "%s" with icon note with title "%s"' \
             "$(say ask_text "$n" "$sz")" "$(t ask_keep)" "$(t ask_wipe)" "$(t ask_keep)" "$(t ask_title)")
    case "$(osascript -e "$script" 2>/dev/null)" in
      *"$(t ask_wipe)") rm -f "$LOG_CSV" ;;
    esac
  fi
  exit 0
fi

# ----------------------------------------------------------------------------
# REPORT MODE — turns the CSV journal into the summary you hand to an ISP.
# Reads only the journal, never the network: safe to run while logging continues.
# ----------------------------------------------------------------------------
if [ "$1" = "--report" ]; then
  if [ -z "$LOG_CSV" ] || [ ! -s "$LOG_CSV" ]; then say r_empty "$LOG_CSV"; echo; exit 1; fi
  # nominal sampling step, read from this file's own name (connection.5s.sh -> 5)
  step=$(basename "$0" | awk -F. '{print $(NF-1)}' | sed 's/[^0-9]//g'); step=${step:-5}
  tmp="${TMPDIR:-/tmp}/connection-health-report.$$"

  awk -F';' -v step="$step" '
    NR==1 && $1=="timestamp" { next }
    NF < 14 { next }
    {
      rows++; ts=$1; net=$2; st=$4; gw=$6+0; up=$8+0; web=$10+0; ep=$14+0
      if (first=="") { first=ts; }
      last=ts
      n[net]++
      bad = 0
      if (st=="offline" || st=="captive") { down[net]++; bad=1 }
      else if (st=="poor")                { slow[net]++; bad=1 }
      if (web > maxw[net]) maxw[net]=web
      if (up  > maxu[net]) maxu[net]=up
      if (gw  > maxg[net]) maxg[net]=gw
      # a jump far beyond the sampling step is a gap, not an outage: the Mac slept
      # or SwiftBar was stopped. Reporting it as downtime would be a lie.
      if (prevep > 0 && ep - prevep > step * 6) { gaps++; gaptime += ep - prevep; broke=1 } else broke=0
      # A gap must never let one episode swallow the time it hides — but the row that
      # follows it is still a real measurement, so it starts a NEW episode instead of
      # being dropped. Closing first, then opening, keeps those two rules independent.
      if (inep && (!bad || broke)) {
        printf "EP;%d;%s;%s;%s\n", epend-epstartep+step, epstart, epkind, epnet; inep=0
      }
      if (bad) {
        if (!inep) { inep=1; epstart=ts; epstartep=ep; epkind=st; epnet=net }
        else if (epkind != st) epkind="mixed"
        epend=ep
      }
      prevep=ep
    }
    END {
      if (inep) printf "EP;%d;%s;%s;%s\n", epend-epstartep+step, epstart, epkind, epnet
      printf "META;%s;%s;%d;%d;%d\n", first, last, rows, gaps, gaptime
      for (k in n) printf "NET;%s;%d;%d;%d;%d;%d;%d\n", k, n[k], down[k], slow[k], maxg[k], maxu[k], maxw[k]
    }
  ' "$LOG_CSV" > "$tmp"

  # printf's %-24s pads by BYTES, so an accented header ("réseau", "relevés") comes out
  # one column short and the whole table drifts. ${#s} counts CHARACTERS under a UTF-8
  # locale, so pad by hand instead.
  lpad() { local v="$1" w="$2" n=$(( $2 - ${#1} )); [ "$n" -lt 0 ] && n=0; printf '%s%*s' "$v" "$n" ""; }
  rpad() { local v="$1" w="$2" n=$(( $2 - ${#1} )); [ "$n" -lt 0 ] && n=0; printf '%*s%s' "$n" "" "$v"; }

  dur() { # dur <seconds> -> compact human duration
    local d="$1"
    if   [ "$d" -lt 60 ];   then printf '%d s' "$d"
    elif [ "$d" -lt 3600 ]; then printf '%d min %02d s' $((d/60)) $((d%60))
    else                         printf '%d h %02d min' $((d/3600)) $(((d%3600)/60))
    fi
  }

  IFS=';' read -r _ m_first m_last m_rows m_gaps m_gaptime <<< "$(grep '^META;' "$tmp")"
  printf '%s : %s  ->  %s\n' "$(t r_period)" "$m_first" "$m_last"
  printf '%s : %s  (~%s)\n' "$(t r_rows)" "$m_rows" "$(dur $((m_rows * step)))"
  printf '%s : %s  (%s)\n\n' "$(t r_gaps)" "$m_gaps" "$(dur "${m_gaptime:-0}")"

  printf '%s\n' "$(t r_bynet)"
  printf '  %s %s %s %s %s %s %s\n' "$(lpad "$(t r_hdr_net)" 24)" "$(rpad "$(t r_hdr_rows)" 8)" \
         "$(rpad "$(t r_hdr_ko)" 7)" "$(rpad "$(t r_hdr_slow)" 7)" \
         "$(rpad "$(t r_hdr_maxg)" 10)" "$(rpad "$(t r_hdr_maxu)" 11)" "$(rpad "$(t r_hdr_maxw)" 10)"
  grep '^NET;' "$tmp" | sort -t';' -k3 -rn | while IFS=';' read -r _ net rows down slow maxg maxu maxw; do
    printf '  %s %s %s %s %s %s %s\n' "$(lpad "$net" 24)" "$(rpad "$rows" 8)" "$(rpad "$down" 7)" \
           "$(rpad "$slow" 7)" "$(rpad "$maxg ms" 10)" "$(rpad "$maxu ms" 11)" "$(rpad "$maxw ms" 10)"
  done
  echo

  printf '%s\n' "$(t r_incidents)"
  if grep -q '^EP;' "$tmp"; then
    printf '  %s %s %s %s\n' "$(lpad "$(t r_hdr_from)" 23)" "$(rpad "$(t r_hdr_dur)" 14)" \
           "  $(lpad "$(t r_hdr_kind)" 12)" "$(t r_hdr_net)"
    grep '^EP;' "$tmp" | sort -t';' -k2 -rn | head -20 | while IFS=';' read -r _ d start kind net; do
      printf '  %s %s %s %s\n' "$(lpad "$start" 23)" "$(rpad "$(dur "$d")" 14)" \
             "  $(lpad "$(t "q_$kind")" 12)" "$net"
    done
  else
    printf '  %s\n' "$(t r_none)"
  fi
  rm -f "$tmp"
  exit 0
fi

# ----------------------------------------------------------------------------
# THE ACTUAL PROBE
# ----------------------------------------------------------------------------
# %{remote_ip} is the address curl actually reached: on a CDN it changes, and it exposes
# whether the probe went over IPv4 or IPv6 — a v6-only degradation is a real failure mode.
out=$(curl -s -o /dev/null --max-time "$TIMEOUT" \
  -w '%{http_code} %{time_namelookup} %{time_connect} %{remote_ip}' "$URL" 2>/dev/null)
curl_ok=$?
read -r code dns connect web_ip <<< "$out"

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
  # Both probes run CONCURRENTLY. Sequentially the failure path costs curl 2 s + nc 1 s +
  # resolver, which pushes a cycle past the 5 s refresh interval — precisely during the
  # outage the journal is supposed to document. In parallel the worst case is 2 s + 1 s.
  # dig rather than host: host's -W is per attempt and it always retries, so it takes 2 s
  # against a silent server (measured) where dig +time=1 +tries=1 is bounded at 1 s.
  nc -z -G 1 -w 1 "$UPLINK_IP" 443 >/dev/null 2>&1 &                      # raw network (IP, no DNS)
  nc_pid=$!
  dig_out=$(dig +short +time=1 +tries=1 example.com 2>/dev/null)          # name resolution
  wait "$nc_pid" && link_ok=1 || link_ok=0
  # dig exits 0 on NXDOMAIN too, so the answer itself is the signal, not the status.
  [ -n "$dig_out" ] && dns_ok=1 || dns_ok=0
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
# SwiftBar needs an absolute path in bash=. $0 is absolute when SwiftBar runs the
# plugin, but relative when it is launched by hand from its own folder.
case "$0" in /*) SELF="$0" ;; *) SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" ;; esac
# One route call for both values: it is queried on every refresh, 17280 times a day.
route_out=$(route -n get default 2>/dev/null)
iface=$(echo "$route_out" | awk '/interface:/{print $2}')
gw=$(echo   "$route_out" | awk '/gateway/{print $2}')
# Local (private) IP — instant, fully local; 169.254.x means no DHCP lease.
# ipconfig getifaddr only reports addresses handed out by the IPConfiguration service.
# On iPhone Personal Hotspot the interface carries a 192.0.0.x address it does not report,
# so fall back to ifconfig before claiming there is no lease.
lan_ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
[ -z "$lan_ip" ] && lan_ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet /{print $2; exit}')

# Link type (Wi-Fi / iPhone USB / Bluetooth PAN…) — available without any permission
link=$(networksetup -listnetworkserviceorder 2>/dev/null \
        | grep "Device: ${iface})" | sed -E 's/.*Hardware Port: ([^,]+),.*/\1/' | head -1)

# Wi-Fi name (SSID): macOS hides it ("<redacted>") unless the caller is authorised for
# Location Services. We delegate to a small signed helper (see helper/) whose grant is
# bound to its own identity. Cached for SSID_TTL s so the helper is not re-run on every
# refresh. Note the support directory is named "connexion-menubar" for historical reasons:
# the Location grant is tied to that path and bundle id, renaming it would revoke it.
SSID_HELPER="$HOME/Library/Application Support/connexion-menubar/WifiSSID.app/Contents/MacOS/WifiSSID"
# The cache key carries the network identity, not just a filename: a plain time-based
# cache kept naming the OLD network for up to SSID_TTL after a switch, so several journal
# rows were attributed to the wrong Wi-Fi — the exact thing the network column exists to
# avoid. Any change of interface, gateway or local address is a different key, hence an
# immediate re-read. Non-alphanumerics are squeezed out so the key is a safe filename.
SSID_KEY=$(printf '%s' "$iface-$gw-$lan_ip" | tr -c 'A-Za-z0-9' '_')
SSID_CACHE="${TMPDIR:-/tmp}/swiftbar_connection_ssid_$SSID_KEY"
ssid=""
if [ -f "$SSID_CACHE" ] && [ "$(( $(date +%s) - $(stat -f %m "$SSID_CACHE" 2>/dev/null || echo 0) ))" -lt "$SSID_TTL" ]; then
  ssid=$(cat "$SSID_CACHE" 2>/dev/null)
elif [ -x "$SSID_HELPER" ]; then
  ssid=$("$SSID_HELPER" 2>/dev/null)
  [ -n "$ssid" ] && printf '%s' "$ssid" > "$SSID_CACHE"
fi
# A Wi-Fi name is an arbitrary 32-byte string. SwiftBar splits a menu row on the first
# "|", so a name containing one would truncate the row and have the rest parsed as
# parameters. The CSV is already safe (csv() neutralises its own delimiter).
ssid_menu=${ssid//|/¦}
if [ -n "$ssid" ]; then
  echo "$(say net "$ssid_menu" "${link:-$iface}") | $INFO_WIFI"
elif [ -x "$SSID_HELPER" ]; then
  echo "$(say net_noname "${link:-${iface:-$(t none)}}") | $INFO_WIFI"
else
  echo "$(say net_nohelp "${link:-${iface:-$(t none)}}") | $INFO_WIFI"
fi

if [ -z "$lan_ip" ]; then
  echo "$(t lan_none) | $INFO"
elif [ "${lan_ip#169.254.}" != "$lan_ip" ]; then
  echo "$(say lan_self "$lan_ip") | $INFO"
else
  echo "$(say lan "$lan_ip") | $INFO"
fi

# Default gateway (the router, LAN side) — clickable: opens its admin interface
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

# ----------------------------------------------------------------------------
# CSV JOURNAL — one row per refresh while the flag file exists.
# Three measuring points, so a degradation can be pinned on a layer instead of
# being argued about: the gateway (your own link), a raw IP (the operator uplink,
# no DNS involved), and the name-based probe (the whole chain).
# The two extra pings only run on a healthy link: when the link is already down
# they would add 2 s to a 5 s cycle for a result the state column already gives.
# ----------------------------------------------------------------------------
if [ -n "$LOG_CSV" ] && [ -f "$LOG_FLAG" ]; then
  rtt_gw=""; rtt_up=""; rtt_web=""
  if [ "$has_net" -eq 1 ]; then
    [ -n "$gw" ] && rtt_gw=$(ping_ms "$gw")
    rtt_up=$(ping_ms "$UPLINK_IP")
    rtt_web="$lat"
  fi
  # A journal written under a different column order would silently corrupt every
  # later report: rotate it aside instead of appending to it.
  if [ -f "$LOG_CSV" ] && [ "$(head -1 "$LOG_CSV" 2>/dev/null)" != "$LOG_HEADER" ]; then
    mv "$LOG_CSV" "${LOG_CSV%.csv}-$(date +%Y%m%d-%H%M%S).csv"
  fi
  if [ ! -f "$LOG_CSV" ]; then
    mkdir -p "$(dirname "$LOG_CSV")"
    printf '%s\n' "$LOG_HEADER" > "$LOG_CSV"
  fi
  IFS='|' read -r log_ts log_ep <<< "$(now)"
  # Re-check the flag: this cycle may have spent two seconds in its pings while the user
  # clicked Stop and chose Wipe. Appending now would resurrect the journal it just erased.
  [ -f "$LOG_FLAG" ] || exit 0
  csv "$log_ts" "${ssid:-${link:-${iface:-?}}}" "${link:-}" "$st" "${lan_ip:-}" \
      "$rtt_gw" "${gw:-}" "$rtt_up" "${rtt_up:+$UPLINK_IP}" "$rtt_web" "${rtt_web:+$web_ip}" \
      "$link_ok" "$dns_ok" "$log_ep" >> "$LOG_CSV"
fi

echo "---"
# SwiftBar splits bash=/param= values on spaces, so a path containing one would make the
# buttons below silently do nothing. Whether quoting the value rescues it is undocumented
# and unverified here, so rather than guess we refuse to draw a button that might be a
# no-op, and say why. Everything else in the plugin keeps working.
path_ok=1
case "$SELF$LOG_CSV$LOG_FLAG" in *" "*) path_ok=0 ;; esac
if [ "$path_ok" -eq 0 ]; then
  case "$SELF" in *" "*) echo "$(say path_space "$SELF") | color=#d9534f" ;;
                  *)     echo "$(say path_space "$LOG_CSV") | color=#d9534f" ;;
  esac
fi
if [ -n "$LOG_CSV" ] && [ "$path_ok" -eq 1 ]; then
  # Status line first, and it is the one that opens the file: "where is my journal"
  # and "is it recording" are the same question, so they get the same row.
  # du -h and wc -l on a week-long journal cost ~3 ms together — fine every 5 s.
  if [ -s "$LOG_CSV" ]; then
    log_sz=$(du -h "$LOG_CSV" 2>/dev/null | awk '{print $1}')
    log_n=$(( $(wc -l < "$LOG_CSV") - 1 )); [ "$log_n" -lt 0 ] && log_n=0
    if [ -f "$LOG_FLAG" ]; then line="$(say log_on "$log_sz" "$log_n")"
    else                        line="$(say log_off "$log_sz")"
    fi
    echo "$line | bash=/usr/bin/open param1=$LOG_CSV terminal=false color=$G"
  fi
  if [ -f "$LOG_FLAG" ]; then
    echo "$(t log_stop) | bash=$SELF param1=--stop terminal=false refresh=true"
  else
    echo "$(t log_start) | bash=/usr/bin/touch param1=$LOG_FLAG terminal=false refresh=true"
  fi
  [ -s "$LOG_CSV" ] && echo "$(t log_reveal) | bash=/usr/bin/open param1=-R param2=$LOG_CSV terminal=false"
fi
echo "$(t refresh) | refresh=true"
[ "$path_ok" -eq 1 ] && echo "$(t open_script) | bash=/usr/bin/open param1=-t param2=$SELF terminal=false"
