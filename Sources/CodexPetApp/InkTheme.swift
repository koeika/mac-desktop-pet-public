import AppKit
import CodexPetCore
import SwiftUI

struct VocabularyLimitControl: View {
    let title: String
    @Binding var count: Int
    @Binding var unlimited: Bool
    var minimum = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                TextField(title, value: Binding(get: { count }, set: { count = max(minimum, $0) }), format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                    .disabled(unlimited)
                Toggle("不限制", isOn: $unlimited)
                    .toggleStyle(.checkbox).accessibilityLabel("\(title)不限制")
            }
        }
    }
}

enum AppVisualTheme: String, Codable, CaseIterable, Identifiable {
    case comic
    case storybook
    case forest

    var id: String { rawValue }
    var title: String {
        switch self {
        case .comic: "经典漫画"
        case .storybook: "童话绘本"
        case .forest: "森林漫步"
        }
    }
    var accentNSColor: NSColor {
        switch self {
        case .comic: NSColor(calibratedWhite: 0.08, alpha: 1)
        case .storybook: NSColor(calibratedRed: 0.17, green: 0.39, blue: 0.32, alpha: 1)
        case .forest: NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.36, alpha: 1)
        }
    }
    var inkNSColor: NSColor {
        switch self {
        case .comic: NSColor(calibratedWhite: 0.08, alpha: 1)
        case .storybook: NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.23, alpha: 1)
        case .forest: NSColor(calibratedRed: 0.16, green: 0.23, blue: 0.22, alpha: 1)
        }
    }
    var lineNSColor: NSColor {
        switch self {
        case .comic: NSColor(calibratedWhite: 0.78, alpha: 1)
        case .storybook: NSColor(calibratedRed: 0.70, green: 0.80, blue: 0.75, alpha: 1)
        case .forest: NSColor(calibratedRed: 0.77, green: 0.84, blue: 0.81, alpha: 1)
        }
    }
    var washNSColor: NSColor {
        switch self {
        case .comic: NSColor(calibratedWhite: 0.965, alpha: 1)
        case .storybook: NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.95, alpha: 1)
        case .forest: NSColor(calibratedRed: 0.96, green: 0.975, blue: 0.97, alpha: 1)
        }
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
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(primary ? .white : theme.ink)
            .background(primary ? theme.accent : theme.wash, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.line.opacity(0.45), lineWidth: 0.6))
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
        VStack(spacing: 10) {
            if store.companionPreviewPets.isEmpty {
                Text("未启用内置小伙伴")
                    .foregroundStyle(.secondary).frame(height: 148)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(store.companionPreviewPets) { pet in
                        forPet(pet)
                    }
                }
            }
            if theme == .storybook,
               let url = AppResourceLocator.file(named: "Themes/storybook-duo", extension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: 64)
                    .accessibilityLabel("Whisky 和 Cling 的童话绘本插画")
            }
        }
    }

    private func forPet(_ pet: PetAsset) -> some View {
        VStack(spacing: 5) {
            if let renderer = store.spriteRenderer(for: pet) {
                CompanionAnimation(renderer: renderer)
                    .id("\(pet.id)-\(renderer.spriteURL.path)-\(pet.actionFrameCount)")
                    .frame(height: 148)
            } else if let image = store.previewImage(for: pet) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 148)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary).frame(height: 148)
            }
            Text(pet.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}
