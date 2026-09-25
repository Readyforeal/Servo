import AppKit
import SwiftUI

// Kept in step with Clara's Palette, Glass, and SidebarAction components.
enum ServoPalette {
    static let cornerRadius: CGFloat = 14
    static let icon = Color(white: 0.72)
    static let muted = Color(red: 0.48, green: 0.50, blue: 0.55)
    static let background = Color(red: 0.035, green: 0.038, blue: 0.043)
    static let border = Color.white.opacity(0.075)
    static let accent = Color(nsColor: .systemBlue)
}
struct ServoWallpaperGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
struct ServoWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {}
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false; window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView); window.isMovableByWindowBackground = true
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "ServoWindowControls")
                toolbar.displayMode = .iconOnly; window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
        }
    }
}
extension View {
    func servoGlass() -> some View {
        background {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: ServoPalette.cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: ServoPalette.cornerRadius, style: .continuous).fill(.ultraThinMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: ServoPalette.cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
    }
    @ViewBuilder func servoPointer() -> some View {
        if #available(macOS 15.0, *) { pointerStyle(.default) } else { self }
    }
    @ViewBuilder func servoClearWindow() -> some View {
        if #available(macOS 15.0, *) { containerBackground(.clear, for: .window) } else { self }
    }
}
struct ServoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { ButtonBody(configuration: configuration) }
    private struct ButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: ServoPalette.cornerRadius))
                .background(RoundedRectangle(cornerRadius: ServoPalette.cornerRadius)
                    .fill(ServoPalette.accent.opacity(enabled ? (configuration.isPressed ? 0.26 : hovered ? 0.14 : 0) : 0)))
                .overlay(RoundedRectangle(cornerRadius: ServoPalette.cornerRadius)
                    .strokeBorder(ServoPalette.accent.opacity(enabled && hovered ? 0.32 : 0), lineWidth: 1).allowsHitTesting(false))
                .focusEffectDisabled().servoPointer().onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered).opacity(enabled ? 1 : 0.4)
        }
    }
}
struct ServoIconButton: View {
    let icon: String
    let help: String
    var size: CGFloat = 28
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13)).frame(width: size, height: size) }
            .buttonStyle(ServoButtonStyle()).foregroundStyle(ServoPalette.icon).help(help).accessibilityLabel(help)
    }
}
struct ServoSidebarAction: View {
    let title: String
    let icon: String
    var selected = false
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(ServoPalette.icon).frame(width: 18)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 10)).foregroundStyle(ServoPalette.muted) }
            }.padding(.horizontal, 8).frame(height: 38)
                .contentShape(RoundedRectangle(cornerRadius: ServoPalette.cornerRadius))
                .background(selected || hovered ? Color.white.opacity(selected ? 0.07 : 0.04) : .clear,
                    in: RoundedRectangle(cornerRadius: ServoPalette.cornerRadius, style: .continuous))
        }.buttonStyle(.plain).focusEffectDisabled().servoPointer().onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct ServoPageTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 30, weight: .medium)).tracking(-0.8)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(ServoPalette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
