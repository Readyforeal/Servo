import AppKit
import SwiftUI

struct ServoMenuBarView: View {
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Servo", systemImage: "macwindow") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        if model.sites.isEmpty {
            Text("No sites in \(model.rootURL.lastPathComponent)")
        } else {
            ForEach(model.sites) { site in
                siteMenu(site)
            }
        }

        Divider()

        Button("Refresh Sites", systemImage: "arrow.clockwise") {
            model.refreshSites()
        }

        Button(updates.checking ? "Checking for Updates…" : "Check for Updates…", systemImage: "arrow.down.circle") {
            Task { await updates.check() }
        }.disabled(updates.checking)

        Button("Quit Servo", systemImage: "power") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func siteMenu(_ site: Site) -> some View {
        let isRunning = running(site)
        return Menu {
            if isRunning {
                Button("Open in Browser", systemImage: "safari") {
                    model.open(site)
                }

                if running(site) {
                    let url = model.siteURL(site)
                    Button("Copy Site URL", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    }
                }

                Divider()
            }

            Button(isRunning ? "Stop Site" : "Start Site", systemImage: isRunning ? "stop.circle" : "play.circle") {
                model.toggle(site)
            }
            .disabled(!model.httpsSiteIDs.isEmpty || model.isWorking)

            Button("Reveal in Finder", systemImage: "folder") {
                model.reveal(site)
            }
        } label: {
            Label(site.name, systemImage: isRunning ? "play.circle" : "circle")
        }
    }

    private func running(_ site: Site) -> Bool {
        _ = model.serverRevision
        return model.server.isRunning(site)
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingNewSite = false
    @State private var isSidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 244)
                .frame(width: isSidebarVisible ? 244 : 0, alignment: .leading)
                .clipped().allowsHitTesting(isSidebarVisible).accessibilityHidden(!isSidebarVisible)
            VStack(spacing: 0) {
                header
                Group {
                    switch model.selected ?? .sites {
                    case .sites: SitesView()
                    case .runtimes: RuntimesView()
                    case .activity: ActivityView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.background(ServoWallpaperGlass().overlay(Color.black.opacity(0.70)))
        }
        .overlay(alignment: .topLeading) {
            ServoIconButton(icon: "sidebar.left", help: isSidebarVisible ? "Hide sidebar" : "Show sidebar", size: 30) {
                isSidebarVisible.toggle()
            }.keyboardShortcut("s", modifiers: [.command, .control]).padding(.leading, 104).padding(.top, 12)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: isSidebarVisible)
        .background(ServoPalette.background).foregroundStyle(Color(white: 0.87))
        .preferredColorScheme(.dark).tint(ServoPalette.accent).focusEffectDisabled()
        .sheet(isPresented: $showingNewSite) { NewSiteView(isPresented: $showingNewSite) }
        .alert("Servo", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Servo").font(.system(size: 19, weight: .semibold, design: .rounded)).tracking(-0.6)
                .padding(.horizontal, 20).frame(height: 36).padding(.top, 56).padding(.bottom, 12)
            VStack(spacing: 2) {
                ServoSidebarAction(title: "New site", icon: "square.and.pencil", shortcut: "⌘N") { showingNewSite = true }
                    .keyboardShortcut("n")
                ServoSidebarAction(title: "Add existing site", icon: "folder.badge.plus") { model.addExistingSite() }
            }.padding(.horizontal, 12)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                .foregroundStyle(ServoPalette.muted).padding(.leading, 20).padding(.top, 26).padding(.bottom, 12)
            VStack(spacing: 2) {
                ForEach(SidebarItem.allCases) { item in
                    ServoSidebarAction(title: item.rawValue, icon: item.icon, selected: (model.selected ?? .sites) == item) { model.selected = item }
                }
            }.padding(.horizontal, 12)
            Spacer(minLength: 24)
            Button(action: model.chooseRoot) {
                HStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 18)).foregroundStyle(ServoPalette.icon)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.rootURL.lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text("Your sites folder").font(.system(size: 9)).foregroundStyle(ServoPalette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(ServoPalette.icon)
                }.padding(18).contentShape(Rectangle())
            }.buttonStyle(ServoButtonStyle()).help(model.rootPath).accessibilityLabel("Change sites folder")
                .overlay(alignment: .top) { Rectangle().fill(ServoPalette.border).frame(height: 1) }
        }.background(ServoWallpaperGlass().overlay(Color.black.opacity(0.22)))
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: (model.selected ?? .sites).icon).foregroundStyle(ServoPalette.muted)
            Text("Servo").foregroundStyle(ServoPalette.muted)
            Text("/").foregroundStyle(.white.opacity(0.2))
            Text((model.selected ?? .sites).rawValue)
            Spacer()
            if model.isWorking {
                ProgressView().controlSize(.mini)
                Text(model.operation).font(.system(size: 10)).foregroundStyle(ServoPalette.muted).lineLimit(1)
            }
            ServoIconButton(icon: "arrow.clockwise", help: "Refresh sites") { model.refreshSites() }
            Menu {
                Button("Create New Site…", systemImage: "square.and.pencil") { showingNewSite = true }
                Button("Add Existing Site…", systemImage: "folder.badge.plus") { model.addExistingSite() }
            } label: {
                Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(ServoPalette.icon).frame(width: 28, height: 28)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Add a site")
        }.font(.system(size: 11)).padding(.trailing, 26).padding(.leading, isSidebarVisible ? 26 : 154).frame(height: 54)
            .overlay(alignment: .bottom) { Rectangle().fill(ServoPalette.border).frame(height: 1) }
    }
}

struct SitesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ServoPageTitle(title: "Sites", subtitle: "Local projects in \(model.rootURL.lastPathComponent)")
            if model.sites.isEmpty {
                ContentUnavailableView {
                    Label("A little space to build", systemImage: "macwindow")
                } description: {
                    Text("Create a new site or add an existing project from the sidebar.")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.sites) { site in SiteRow(site: site) }
                    }.padding(2).padding(.bottom, 20)
                }
            }
        }.padding(.horizontal, 28).padding(.top, 28)
    }
}

struct SiteRow: View {
    @EnvironmentObject private var model: AppModel
    let site: Site

    private var running: Bool { _ = model.serverRevision; return model.server.isRunning(site) }
    private var https: Bool { _ = model.serverRevision; return model.server.isHTTPS(site) }
    private var changingHTTPS: Bool { model.httpsSiteIDs.contains(site.id) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: ServoPalette.cornerRadius).fill(Color.white.opacity(0.04))
                Image(systemName: site.isLaravel ? "laurel.leading" : "doc.text").font(.system(size: 20)).foregroundStyle(ServoPalette.icon)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(site.name).font(.system(size: 13, weight: .medium))
                    if running { Circle().fill(.green).frame(width: 5, height: 5).accessibilityLabel("Running") }
                    Text(site.isLaravel ? "Laravel" : "PHP").font(.system(size: 9)).foregroundStyle(ServoPalette.muted)
                }
                if running {
                    copyableURL(model.siteURL(site), icon: "globe")
                    if let secureURL = model.server.httpsURL(for: site) {
                        copyableURL(secureURL, icon: "lock")
                    }
                } else {
                    Text(site.path).lineLimit(1).truncationMode(.middle).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .trailing, spacing: 6) {
                SiteRuntimeMenu(kind: .php, selection: Binding(
                    get: { site.runtimeSelection.php },
                    set: { pin in
                        if let runtime = model.installed(.php).first(where: { $0.path == pin?.path }) { model.selectRuntime(runtime, for: site) }
                    }))
                SiteRuntimeMenu(kind: .node, selection: Binding(
                    get: { site.runtimeSelection.node },
                    set: { pin in
                        if let runtime = model.installed(.node).first(where: { $0.path == pin?.path }) { model.selectRuntime(runtime, for: site) }
                    }))
            }.disabled(running || changingHTTPS)
                .help(running ? "Stop this site to change its runtimes" : "Choose versions for this site")
            Spacer(minLength: 4)

            if running {
                if changingHTTPS {
                    ProgressView().controlSize(.small)
                } else if https {
                    Label("HTTPS", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
                if https {
                    ServoIconButton(icon: "safari", help: "Open secure site in browser") { model.open(site) }
                }
            }
            Menu {
                Button("Open Site Terminal", systemImage: "terminal") { model.openTerminal(site) }
                Button("Reveal in Finder") { model.reveal(site) }
                if https {
                    Divider()
                    Button("Export Phone Certificate…", systemImage: "iphone.and.arrow.forward") {
                        model.exportHTTPSCertificate()
                    }
                }
            } label: { Image(systemName: "ellipsis").foregroundStyle(ServoPalette.icon).frame(width: 28, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Site actions")
            Toggle(isOn: Binding(get: { running }, set: { _ in model.toggle(site) })) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(changingHTTPS)
        }
        .padding(16).servoGlass()
    }

    private func copyableURL(_ url: String, icon: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        } label: {
            Label(url, systemImage: icon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ServoPalette.icon)
        .font(.caption)
        .help("Copy \(url)")
    }
}

struct NewSiteView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var template: SiteTemplate = .livewire
    @State private var selection = SiteRuntimeSelection()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create a new site").font(.title2.bold())
                Text("Servo will create it inside \(model.rootURL.lastPathComponent).").foregroundStyle(.secondary)
            }
            Form {
                TextField("Site name", text: $name, prompt: Text("my-project"))
                Picker("Template", selection: $template) {
                    ForEach(SiteTemplate.allCases) { item in
                        VStack(alignment: .leading) { Text(item.rawValue); Text(item.detail) }.tag(item)
                    }
                }
                .pickerStyle(.radioGroup)
                SiteRuntimeMenu(kind: .php, selection: $selection.php, onManage: { isPresented = false })
                SiteRuntimeMenu(kind: .node, selection: $selection.node, onManage: { isPresented = false })
            }
            if model.isWorking { HStack { ProgressView(); Text(model.operation).foregroundStyle(.secondary) } }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction).disabled(model.isWorking)
                Button("Create") {
                    Task { if await model.createSite(name: name, template: template, runtimes: selection) { isPresented = false } }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.isEmpty || model.isWorking)
            }
        }
        .padding(28).frame(width: 480).background(ServoPalette.background).tint(ServoPalette.accent).focusEffectDisabled()
    }
}

struct RuntimesView: View {
    @EnvironmentObject private var model: AppModel
    private let manageable: [RuntimeInfo.Kind] = [.homebrew, .php, .node, .composer, .laravel, .caddy]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                ServoPageTitle(title: "Runtimes", subtitle: "A complete Servo-managed development toolchain.")
                Spacer()
                Button {
                    Task { await model.installRequiredToolchain() }
                } label: {
                    Label("Install Toolchain", systemImage: "shippingbox.and.arrow.backward")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                }
                .buttonStyle(ServoButtonStyle())
                .disabled(model.isWorking || RuntimeService.requiredToolchain.allSatisfy(RuntimeService.isInstalled))
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    Text("Install versions side by side, then choose PHP and Node.js on each site. Stop a site before switching. Existing selections stay pinned; no global linking is changed.")
                        .font(.system(size: 11)).foregroundStyle(ServoPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                    ForEach(manageable, id: \.rawValue) { kind in runtimeRow(kind) }
                }.padding(2).padding(.bottom, 20)
            }
        }.padding(.horizontal, 28).padding(.top, 28)
            .task { await model.refreshRuntimes() }
    }
    private func runtimeRow(_ kind: RuntimeInfo.Kind) -> some View {
        let installed = model.installed(kind)
        let versions = RuntimeFormula.available.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "shippingbox").font(.system(size: 20)).foregroundStyle(ServoPalette.icon)
                Text(kind.rawValue).font(.system(size: 13, weight: .medium))
                Spacer()
                if !versions.isEmpty {
                    Menu("Install version") {
                        ForEach(versions) { formula in
                            Button(formula.label) { Task { await model.installVersion(formula) } }
                        }
                    }.menuStyle(.borderlessButton).fixedSize().disabled(model.isWorking)
                } else if installed.isEmpty {
                    Button("Install") { Task { await model.install(kind) } }
                        .buttonStyle(ServoButtonStyle()).disabled(model.isWorking)
                }
            }
            if installed.isEmpty {
                Text("Not installed").font(.system(size: 11)).foregroundStyle(ServoPalette.muted)
            }
            ForEach(installed) { runtime in
                VStack(alignment: .leading, spacing: 3) {
                    Text(runtime.version).font(.system(size: 11)).lineLimit(1)
                    Text(runtime.path).font(.system(size: 10)).foregroundStyle(ServoPalette.muted)
                        .lineLimit(1).truncationMode(.middle).help(runtime.path)
                }
            }
        }.padding(16).servoGlass()
    }
}

struct SiteRuntimeMenu: View {
    @EnvironmentObject private var model: AppModel
    let kind: RuntimeInfo.Kind
    @Binding var selection: RuntimePin?
    var onManage: (() -> Void)? = nil

    private var title: String {
        guard let selection else { return "\(kind.rawValue) · choose" }
        let version = selection.version.range(of: #"[0-9]+\.[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression)
            .map { String(selection.version[$0]) } ?? selection.version
        return "\(kind.rawValue) \(version)"
    }

    var body: some View {
        Menu {
            if let selection, !FileManager.default.isExecutableFile(atPath: selection.path) {
                Text("Selected version missing — choose an installed version")
            }
            ForEach(model.installed(kind)) { runtime in
                Button {
                    selection = RuntimePin(runtime)
                } label: {
                    if runtime.path == selection?.path { Label(runtime.version, systemImage: "checkmark") }
                    else { Text(runtime.version) }
                }
            }
            Divider()
            Button("Manage versions…") { model.selected = .runtimes; onManage?() }
        } label: {
            Text(title).font(.system(size: 11)).foregroundStyle(ServoPalette.icon)
        }.menuStyle(.borderlessButton).fixedSize()
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                ServoPageTitle(title: "Activity", subtitle: "Servers, installs, and everything in between.")
                ServoIconButton(icon: "trash", help: "Clear activity") { model.logs.removeAll() }.disabled(model.logs.isEmpty)
            }
            ScrollView {
                Text(model.logs.isEmpty ? "No activity yet." : model.logs.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(model.logs.isEmpty ? ServoPalette.muted : Color(white: 0.87))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(18)
            }.background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: ServoPalette.cornerRadius)).servoGlass()
        }.padding(28)
    }
}
