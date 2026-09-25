# Servo

Servo is a native SwiftUI macOS app for managing local PHP/Laravel sites with its own runtime setup.

## Included in this MVP

- Choose any folder as your Servo sites folder.
- Discover every immediate child folder as a site.
- Add projects elsewhere using a symbolic link.
- Start Laravel or plain PHP sites with LAN-accessible HTTPS enabled automatically through Caddy's internal certificate authority.
- Detect Homebrew, PHP, Node.js, npm, Composer, the Laravel installer, and Caddy from standard macOS tool locations.
- Bootstrap Homebrew from its official signed macOS installer on a fresh Apple silicon Mac, then install the complete required toolchain.
- Create clean Laravel projects or projects based on Laravel's official Livewire starter kit.

## Run from source

```sh
swift run Servo
```

Run tests with `swift test` from a full Xcode toolchain. Build a double-clickable app bundle with `./scripts/build-app.sh`.

## Notes

LAN sharing binds a second development server to all local interfaces. Only enable it on trusted networks. HTTPS uses Caddy's internal CA on an unprivileged LAN port; its first use requires a one-time macOS trust authorization. Use a site's menu to export `Servo-Local-CA.crt` for your phone. After installing it on iOS, enable full trust under Settings > General > About > Certificate Trust Settings. This first version does not provide `.test` domains, automatic phone certificate installation, databases, or background launch-at-login behavior.

## Interface

Servo shares Clara’s visual styling: a 244-point wallpaper-backed glass sidebar, dark-tinted glass workspace, 14-point corners, neutral outline icons, macOS blue hover states, and matching typography and window controls. Sites, runtimes, and activity use floating glass surfaces. Liquid Glass is enabled on macOS 26+ with a material fallback on older supported systems. Build with the current macOS SDK; `SERVO_SDK_PATH` can explicitly select an SDK.

## Releases and updates

Published at https://github.com/Readyforeal/Servo. Use **Servo → Check for Updates…** (also available in Servo’s menu bar extra) to check published stable releases and download the installer when a newer version is available. Install updates by quitting Servo and dragging the replacement into Applications; settings and sites stay intact.

Current installers target Apple silicon, macOS 14 or newer. Liquid Glass requires macOS 26+. Development DMGs are ad hoc signed and not notarized; trusted distribution requires an Apple Developer membership and Developer ID signing. See [release instructions](docs/RELEASING.md).

## Per-site PHP and Node.js versions

In **Runtimes → Install version**, install PHP 8.4 alongside 8.5 (or another offered PHP/Node.js line). Servo discovers versioned Homebrew installations without changing global links. On a stopped site, choose its PHP and Node.js versions, then start it again. Each site has independent selections, saved across app launches; local and shared servers use the selected PHP.

Use the site's **… → Open Site Terminal** action for Composer, Artisan, npm, and other commands. That terminal starts in the project directory with its selected PHP/Node.js directories first on PATH. It uses a clean zsh session so shell startup files do not replace those selections. Open a new site terminal after changing versions; existing terminals keep their original environment. Ordinary external terminals continue to use their own environment.

New-site creation offers the same selectors and runs Composer/Laravel under the chosen PHP. Existing sites with no selection pin the detected installed defaults when first started or opened in a site terminal. To use 8.4, explicitly select it on the work site before starting it. Servo does not modify composer.json, package.json, lockfiles, or production servers.

Selections pin the resolved executable path, including the installed patch release. Homebrew upgrades or cleanup may remove that installation. In that case Servo reports the missing runtime and requires you to select an installed version again, rather than silently substituting a different one. Homebrew still manages shared libraries and extensions; this is per-site interpreter selection, not full container isolation. Install project dependencies with the selected runtime and test application compatibility before upgrading production.

Versioned formula references: [PHP 8.4](https://formulae.brew.sh/formula/php@8.4), [Node.js 24](https://formulae.brew.sh/formula/node@24).

Optional integration test (requires installed PHP 8.4 and 8.5): `SERVO_RUNTIME_SMOKE=1 swift test --disable-sandbox`. It starts two temporary local servers concurrently and verifies the PHP version each serves.
