import AppKit
import CodexPetCore
import SwiftUI

enum SettingsRedesignRegression {
    @MainActor static func run() throws {
        precondition(SettingsTab.allCases.contains(.appearance))
        precondition(SettingsTab.learningTab("词典库") == .library)
        precondition(SettingsTab.learningTab("学习计划") == .plan)
        precondition(SettingsTab.learningTab("连接与 AI") == .connections)
        precondition(Set(AppVisualTheme.allCases.map(\.id)).count == AppVisualTheme.allCases.count)
        precondition(AppVisualTheme.allCases == [.comic, .storybook, .forest])
        precondition(AppVisualTheme.comic.rawValue == "comic" && AppVisualTheme.storybook.rawValue == "storybook")
        precondition(AppVisualTheme.forest.title == "森林漫步")
        precondition(AppSettings().visualTheme == .comic)
        try validateForestArtwork()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        while store.settings.petClickFeedbackPhrases.count < 4 { store.addPetClickFeedbackPhrase() }
        let last = store.settings.petClickFeedbackPhrases.count - 1
        let retained = Binding(get: { store.petClickFeedbackPhrase(at: last) },
            set: { store.setPetClickFeedbackPhrase(index: last, phrase: $0) })
        precondition(!retained.wrappedValue.isEmpty)
        store.removePetClickFeedbackPhrase(at: last)
        precondition(retained.wrappedValue.isEmpty)
        retained.wrappedValue = "stale binding"
        precondition(store.settings.petClickFeedbackPhrases.count == 3)
        let word = try store.captureWord(CapturePayload(term: "coherent", meaning: "adj. 连贯的"))
        let entry = ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: "我的生词", entry: word.entry)
        try store.reviewWord(entry, action: .unknown, now: Date(timeIntervalSince1970: 1_800_000_000))
        let history = try Data(contentsOf: store.progressURL)
        let notebook = try Data(contentsOf: store.personalVocabularyURL)
        let dictionaries = try JSONFileStore.encoder.encode(store.dictionaries)
        let pets = try JSONFileStore.encoder.encode(store.pets)
        let settingsBefore = try settingsWithoutTheme(at: store.settingsURL)
        for theme in AppVisualTheme.allCases {
            try store.selectVisualTheme(theme)
            let reloaded = try AppDataStore(root: root)
            precondition(reloaded.settings.visualTheme == theme)
            let historyAfter = try Data(contentsOf: store.progressURL)
            let notebookAfter = try Data(contentsOf: store.personalVocabularyURL)
            let dictionariesAfter = try JSONFileStore.encoder.encode(store.dictionaries)
            let petsAfter = try JSONFileStore.encoder.encode(store.pets)
            precondition(historyAfter == history && notebookAfter == notebook)
            precondition(dictionariesAfter == dictionaries && petsAfter == pets)
            let settingsAfter = try settingsWithoutTheme(at: store.settingsURL)
            precondition(settingsAfter == settingsBefore, "Theme selection must not modify learning or pet settings")
            let detail = NSHostingView(rootView: NotebookWordDetail(store: store, word: word)
                .environment(\.companionTheme, theme))
            detail.frame = NSRect(x: 0, y: 0, width: 350, height: 600)
            let window = NSWindow(contentRect: detail.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = detail
            detail.layoutSubtreeIfNeeded()
            precondition(detail.fittingSize.width <= 350)
            window.contentView = nil
        }
        print("settings-redesign-regression: three themes, forest artwork, restart persistence, unchanged settings/word/history/dictionaries/pets and compact inline detail passed")
    }

    private static func settingsWithoutTheme(at url: URL) throws -> NSDictionary {
        var values = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        values.removeValue(forKey: "visualTheme")
        return values as NSDictionary
    }

    private static func validateForestArtwork() throws {
        for name in ["forest-clearing", "forest-ferns"] {
            guard let url = AppResourceLocator.file(named: "Themes/\(name)", extension: "png"),
                  let image = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
                throw NSError(domain: "ForestThemeRegression", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing or invalid forest theme asset: \(name)"])
            }
            precondition(image.pixelsWide >= 1024 && image.pixelsHigh >= 512)
            var clear = 0
            var painted = 0
            for y in stride(from: 0, to: image.pixelsHigh, by: 32) {
                for x in stride(from: 0, to: image.pixelsWide, by: 32) {
                    let color = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if color.alphaComponent < 0.05 { clear += 1 }
                    if color.alphaComponent > 0.5 && color.greenComponent > color.redComponent + 0.03 { painted += 1 }
                }
            }
            precondition(painted > 30, "Forest artwork must contain visible foliage, not a blank placeholder")
            if name == "forest-ferns" { precondition(clear > 30, "Sidebar foliage needs genuine transparency") }
        }
        precondition(ForestThemeArtwork.clearing != nil && ForestThemeArtwork.ferns != nil)
    }
}
