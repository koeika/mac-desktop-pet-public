import AppKit
import CodexPetCore
import SwiftUI

enum AppVisualTheme: String, Codable, CaseIterable, Identifiable {
    case comic
    case storybook

    var id: String { rawValue }
    var title: String { self == .comic ? "经典漫画" : "童话绘本" }
    var accentNSColor: NSColor {
        self == .comic ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.17, green: 0.39, blue: 0.32, alpha: 1)
    }
    var inkNSColor: NSColor {
        self == .comic ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.23, alpha: 1)
    }
    var lineNSColor: NSColor {
        self == .comic ? NSColor(calibratedWhite: 0.78, alpha: 1)
            : NSColor(calibratedRed: 0.70, green: 0.80, blue: 0.75, alpha: 1)
    }
    var washNSColor: NSColor {
        self == .comic ? NSColor(calibratedWhite: 0.965, alpha: 1)
            : NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.95, alpha: 1)
    }
    var ink: Color { Color(nsColor: inkNSColor) }
    var accent: Color { Color(nsColor: accentNSColor) }
    var line: Color { Color(nsColor: lineNSColor) }
    var wash: Color { Color(nsColor: washNSColor) }
    var paper: Color { .white }
}

private struct CompanionThemeKey: EnvironmentKey {
    static let defaultValue = AppVisualTheme.comic
}

extension EnvironmentValues {
    var companionTheme: AppVisualTheme {
        get { self[CompanionThemeKey.self] }
        set { self[CompanionThemeKey.self] = newValue }
    }
}

extension Notification.Name {
    static let companionThemeDidChange = Notification.Name("companionThemeDidChange")
}

struct InkButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.companionTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(primary ? .white : theme.accent)
            .background(primary ? theme.accent : theme.paper, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme == .comic ? theme.ink : theme.line, lineWidth: theme == .comic ? 1.3 : 1))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}

struct CompanionAnimation: View {
    let renderer: PetAnimationRenderer
    var action: CodexPetAction = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: reduceMotion)) { context in
            if let frame = renderer.frame(for: action, frameIndex: reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.16) % renderer.framesPerAction) {
                Image(nsImage: frame).resizable().scaledToFit()
            }
        }
        .accessibilityLabel(action.chineseName)
    }
}

struct CompanionDuo: View {
    @ObservedObject var store: AppDataStore
    @Environment(\.companionTheme) private var theme

    var body: some View {
        Group {
            if theme == .storybook,
               let url = AppResourceLocator.file(named: "Themes/storybook-duo", extension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .accessibilityLabel("Whisky 和 Cling 的童话绘本插画")
            } else {
                HStack(spacing: 8) {
                    forPet("whisky-color", name: "Whisky", detail: "银白 · 绿眼睛")
                    forPet("cling-color", name: "Cling", detail: "杏金 · 琥珀眼")
                }
            }
        }
    }

    private func forPet(_ id: String, name: String, detail: String) -> some View {
        VStack(spacing: 5) {
            if let pet = store.pets.first(where: { $0.id == id }), let renderer = store.spriteRenderer(for: pet) {
                CompanionAnimation(renderer: renderer).frame(height: 148)
            } else if let url = AppResourceLocator.file(named: "Pets/\(id)/spritesheet", extension: "png"),
                      let renderer = PetAnimationRenderer(spriteURL: url, framesPerAction: 4) {
                CompanionAnimation(renderer: renderer).frame(height: 148)
            }
            Text(name).font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
