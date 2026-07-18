#!/bin/bash
#
# Convert a MOHAA-style ipfilter.cfg (wildcard format) into an nftables set,
# and (unless GENERATE_ONLY=1) load it. Re-run any time the ban list changes.
#
# Wildcard -> CIDR:
#   1.2.3.4   -> 1.2.3.4/32
#   1.2.3.*   -> 1.2.3.0/24
#   1.2.*.*   -> 1.2.0.0/16
#   1.*.*.*   -> 1.0.0.0/8
#
# Usage:
#   sudo ./blocklist-update.sh [ipfilter.cfg] [output.nft]   # convert + load
#   GENERATE_ONLY=1 ./blocklist-update.sh in.cfg out.nft     # convert only (CI)

set -euo pipefail

SRC="${1:-/home/debian/moh/main/ipfilter.cfg}"
OUT="${2:-/etc/nftables.d/mohaa-blocklist.nft}"
GAME_PORTS="12203, 12300"   # UDP ports the ban applies to

if [[ ! -f "$SRC" ]]; then
  echo "ipfilter source not found: $SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

elements=$(awk '
  { gsub(/[ \t\r]/, "") }
  /^$/  { next }
  /^#/  { next }
  {
    n = split($0, a, ".")
    if (n != 4) next
    if (a[1]=="*") next
    if (a[2]=="*") { print a[1]".0.0.0/8";              next }
    if (a[3]=="*") { print a[1]"."a[2]".0.0/16";        next }
    if (a[4]=="*") { print a[1]"."a[2]"."a[3]".0/24";   next }
    print $0"/32"
  }
' "$SRC" | paste -sd, -)

count=$(printf '%s' "$elements" | tr ',' '\n' | grep -c .)

tee "$OUT" > /dev/null <<EOF
table inet mohaa_blocklist {}
delete table inet mohaa_blocklist
table inet mohaa_blocklist {
	set blocked {
		type ipv4_addr
		flags interval
		auto-merge
		elements = { $elements }
	}
	chain input {
		type filter hook input priority -150; policy accept;
		udp dport { $GAME_PORTS } ip saddr @blocked drop
	}
}
EOF

echo "Generated $OUT ($count blocked ranges)."

if [[ "${GENERATE_ONLY:-0}" == "1" ]]; then
  exit 0
fi

nft -f "$OUT"
echo "Loaded into nftables (set: mohaa_blocklist/blocked)."
