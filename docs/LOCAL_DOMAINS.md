# Local .test sites and Clara

Start a site, or choose **File → Enable .test Addresses…**. macOS asks for administrator authentication to install the loopback port-80 relay and register the current site names. A folder named `shop` becomes `http://shop.test`. Names containing spaces, unsupported characters, or collisions get a stable suffix. Adding a new hostname requires authorizing setup again. Existing unrelated hosts entries are preserved; conflicting entries are reported instead of silently replaced.

The portless address uses HTTP on this Mac. The existing HTTPS IP/port address remains available for phones and other LAN devices. `.test` names are not automatically resolvable on other devices. Site processes and PHP/Node version selection are unchanged.

## Routing

A root-owned copy of Caddy and fixed JSON configuration live at `/Library/PrivilegedHelperTools/com.servo.local-domains`. A launch daemon at `/Library/LaunchDaemons/com.servo.local-domains.plist` accepts **127.0.0.1:80 only**, forwarding to the user's router at **127.0.0.1:17880**. It has no admin API, file serving, TLS, or user-editable configuration. The user-owned router runs with Servo, matches registered hostnames, preserves the Host header, and forwards to the existing per-site PHP ports. Unknown names return 404. Its admin socket is in the user's Servo Application Support directory. Setup fails visibly if routing cannot be verified; another application using either port needs to be addressed rather than silently displaced.

The helper persists across login; with Servo closed it cannot serve a site. Setup backs up the original hosts file to `hosts.before-servo` in the helper directory and edits only the `BEGIN/END SERVO LOCAL DOMAINS` block. Logs: `/var/log/servo-local-domains.log` for the relay and `~/Library/Application Support/Servo/domains.log` for the user router.

To remove setup, stop Servo, unload the exact launch daemon with `sudo launchctl bootout system /Library/LaunchDaemons/com.servo.local-domains.plist`, remove that plist and its helper directory, and remove only the marked Servo block from `/etc/hosts`. Flush DNS with `sudo dscacheutil -flushcache` and `sudo killall -HUP mDNSResponder`. Do not replace the entire hosts file with the old backup because unrelated entries may have changed since setup.

## Clara discovery contract

Servo atomically writes `~/Library/Application Support/Servo/sites.json` on server changes and every five seconds:

```json
{"version":1,"updatedAt":1790350000,"processID":1234,"sites":[{"path":"/Users/me/Servo/shop","resolvedPath":"/Users/me/Projects/shop","url":"http://shop.test","running":true}]}
```

Clara reads the exact published URL, matches resolved symlinks and nested folders, and only uses running entries from a manifest less than 20 seconds old. If a manifest exists but is stale or invalid, Clara does not fall back to a stale port. Older Servo builds without a manifest retain legacy port discovery. Reopening Clara's browser refreshes discovery; when its current page is on a previously discovered Servo origin, it migrates that page's path/query to the new origin. Unrelated browsing is preserved.

## Validation

Tests cover hostname sanitization/collisions, loopback configuration, stale/stopped manifest entries, nested folders, and scheme selection. A live two-backend Caddy check verifies host routing, scheme/Host preservation, health checks, unknown-host rejection, and configuration reload. Privileged installation still requires macOS administrator authentication.

Caddy references: [bind](https://caddyserver.com/docs/caddyfile/directives/bind), [admin sockets](https://caddyserver.com/docs/caddyfile/options#admin), [reverse proxy](https://caddyserver.com/docs/quick-starts/reverse-proxy).
