#!/bin/sh
# Invoked through macOS administrator authorization. Only the fixed relay runs as root.
set -eu
[ "$(id -u)" = 0 ] || exit 1
# Refuse a malformed managed block rather than risk dropping unrelated lines.
/usr/bin/awk '/^# BEGIN SERVO LOCAL DOMAINS$/{if(open) exit 1;open=1} /^# END SERVO LOCAL DOMAINS$/{if(!open) exit 1;open=0} END{if(open) exit 1}' /etc/hosts
caddy=$1; shift
[ -x "$caddy" ] || exit 1
[ "$#" -gt 0 ] || exit 1
for host in "$@"; do
    printf '%s\n' "$host" | /usr/bin/grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.test$' || exit 1
done
for host in "$@"; do
    /usr/bin/awk -v host="$host" '
    /^# BEGIN SERVO LOCAL DOMAINS$/{skip=1;next}
    /^# END SERVO LOCAL DOMAINS$/{skip=0;next}
    !skip {sub(/#.*/, ""); for(i=2;i<=NF;i++) if(tolower($i)==host && $1!="127.0.0.1") exit 1}
    ' /etc/hosts || { echo "An existing hosts entry conflicts with $host. Resolve it before enabling Servo domains." >&2; exit 1; }
done
base=/Library/PrivilegedHelperTools/com.servo.local-domains
plist=/Library/LaunchDaemons/com.servo.local-domains.plist
/bin/mkdir -p "$base"
/usr/sbin/chown root:wheel "$base"
/bin/chmod 755 "$base"
/bin/cp "$caddy" "$base/caddy.new"
/usr/sbin/chown root:wheel "$base/caddy.new"
/bin/chmod 755 "$base/caddy.new"
/bin/mv -f "$base/caddy.new" "$base/caddy"
/bin/cat > "$base/relay.json" <<'JSON'
{"admin":{"disabled":true},"apps":{"http":{"servers":{"relay":{"listen":["127.0.0.1:80"],"automatic_https":{"disable":true},"routes":[{"handle":[{"handler":"reverse_proxy","upstreams":[{"dial":"127.0.0.1:17880"}]}]}]}}}}}
JSON
/bin/cat > "$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.servo.local-domains</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/com.servo.local-domains/caddy</string><string>run</string><string>--config</string><string>/Library/PrivilegedHelperTools/com.servo.local-domains/relay.json</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardErrorPath</key><string>/var/log/servo-local-domains.log</string>
<key>StandardOutPath</key><string>/var/log/servo-local-domains.log</string>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$base/relay.json" "$plist"
/bin/chmod 644 "$base/relay.json" "$plist"
# Keep unrelated entries; back up the first pre-Servo hosts file.
[ -e "$base/hosts.before-servo" ] || /bin/cp /etc/hosts "$base/hosts.before-servo"
/usr/bin/awk '/^# BEGIN SERVO LOCAL DOMAINS$/{skip=1;next} /^# END SERVO LOCAL DOMAINS$/{skip=0;next} !skip{print}' /etc/hosts > "$base/hosts.new"
printf '\n# BEGIN SERVO LOCAL DOMAINS\n' >> "$base/hosts.new"
for host in "$@"; do printf '127.0.0.1 %s\n' "$host" >> "$base/hosts.new"; done
printf '# END SERVO LOCAL DOMAINS\n' >> "$base/hosts.new"
/bin/cat "$base/hosts.new" > /etc/hosts
/bin/rm "$base/hosts.new"
/bin/launchctl bootout system "$plist" 2>/dev/null || true
/bin/launchctl bootstrap system "$plist"
/usr/bin/dscacheutil -flushcache
/usr/bin/killall -HUP mDNSResponder || true
