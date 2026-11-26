import AppKit
import AVFoundation
import Combine
import CodexPetCore
import Foundation

struct AppSettings: Codable {
    static let defaultPetClickFeedbackPhrases = [
        "我在这儿。",
        "摸摸头收到。",
        "今天也辛苦啦。",
        "尾巴摆摆。"
    ]

    var serverPort: UInt16 = 4789
    var enabledDictionaryIDs: Set<String> = []
    var syncFilePath: String?
    var logPaths: [String] = []
    var walkingPaused: Bool = false
    var positionLocked: Bool = false
    var lastWindowOrigin: CGPoint?
    var movementSpeedMultiplier: Double = 0.10
    var visualTheme: AppVisualTheme = .comic
    var exampleProvider: ExampleProvider = .openAI
    var openAIModel: String = "gpt-5.2"
    var deepSeekModel: String = DeepSeekConfiguration.defaultModel
    var deepSeekBaseURL: String = "https://api.deepseek.com"
    var dailyVocabularyLimit: Int = 10
    var dailyVocabularyUnlimited = false
    var dailyNewVocabularyUnlimited = false
    var vocabularyMinimumIntervalMinutes = 5
    var lastAutomaticVocabularyDate: Date?
    var vocabularyWindowHours: Int = 6
    var vocabularyStudyStartMinute: Int = VocabularyDisplayScheduler.defaultStudyStartMinute
    var vocabularyStudyEndMinute: Int = VocabularyDisplayScheduler.defaultStudyEndMinute
    var vocabularyQuestionPersists: Bool = true
    var vocabularyWindowStartDate: Date?
    var vocabularyShownCountDate: String?
    var vocabularyShownCount: Int = 0
    var dailyNewVocabularyLimit: Int = 3
    var newVocabularyKeys: [String] = []
    var vocabularyRecallMode: Bool = true
    var vocabularyRetention: Double = 0.9
    var petClickFeedbackPhrases: [String] = AppSettings.defaultPetClickFeedbackPhrases

    init() {}

    enum CodingKeys: String, CodingKey {
        case serverPort
        case enabledDictionaryIDs
        case syncFilePath
        case logPaths
        case walkingPaused
        case positionLocked
        case lastWindowOrigin
        case movementSpeedMultiplier
        case visualTheme
        case exampleProvider
        case openAIModel
        case deepSeekModel
        case deepSeekBaseURL
        case dailyVocabularyLimit
        case dailyVocabularyUnlimited, dailyNewVocabularyUnlimited, vocabularyMinimumIntervalMinutes
        case lastAutomaticVocabularyDate
        case vocabularyWindowHours
        case vocabularyStudyStartMinute
        case vocabularyStudyEndMinute
        case vocabularyQuestionPersists
        case vocabularyWindowStartDate
        case vocabularyShownCountDate
        case vocabularyShownCount
        case dailyNewVocabularyLimit, newVocabularyKeys, vocabularyRecallMode, vocabularyRetention
        case petClickFeedbackPhrases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverPort = try container.decodeIfPresent(UInt16.self, forKey: .serverPort) ?? 4789
        enabledDictionaryIDs = try container.decodeIfPresent(Set<String>.self, forKey: .enabledDictionaryIDs) ?? []
        syncFilePath = try container.decodeIfPresent(String.self, forKey: .syncFilePath)
        logPaths = try container.decodeIfPresent([String].self, forKey: .logPaths) ?? []
        walkingPaused = try container.decodeIfPresent(Bool.self, forKey: .walkingPaused) ?? false
        positionLocked = try container.decodeIfPresent(Bool.self, forKey: .positionLocked) ?? false
        lastWindowOrigin = try container.decodeIfPresent(CGPoint.self, forKey: .lastWindowOrigin)
        movementSpeedMultiplier = try container.decodeIfPresent(Double.self, forKey: .movementSpeedMultiplier) ?? 0.10
        visualTheme = (try container.decodeIfPresent(String.self, forKey: .visualTheme)).flatMap(AppVisualTheme.init(rawValue:)) ?? .comic
        exampleProvider = try container.decodeIfPresent(ExampleProvider.self, forKey: .exampleProvider) ?? .openAI
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? "gpt-5.2"
        deepSeekModel = try container.decodeIfPresent(String.self, forKey: .deepSeekModel) ?? DeepSeekConfiguration.defaultModel
        deepSeekBaseURL = try container.decodeIfPresent(String.self, forKey: .deepSeekBaseURL) ?? "https://api.deepseek.com"
        dailyVocabularyUnlimited = try container.decodeIfPresent(Bool.self, forKey: .dailyVocabularyUnlimited) ?? false
        dailyNewVocabularyUnlimited = try container.decodeIfPresent(Bool.self, forKey: .dailyNewVocabularyUnlimited) ?? false
        vocabularyMinimumIntervalMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .vocabularyMinimumIntervalMinutes) ?? 5)
        lastAutomaticVocabularyDate = try container.decodeIfPresent(Date.self, forKey: .lastAutomaticVocabularyDate)
        dailyVocabularyLimit = VocabularyDisplayScheduler.normalizedDailyLimit(
            try container.decodeIfPresent(Int.self, forKey: .dailyVocabularyLimit) ?? 10
        )
        vocabularyWindowHours = VocabularyDisplayScheduler.normalizedWindowHours(
            try container.decodeIfPresent(Int.self, forKey: .vocabularyWindowHours) ?? 6
        )
        let studyWindow = VocabularyDisplayScheduler.normalizedStudyWindow(
            startMinute: try container.decodeIfPresent(Int.self, forKey: .vocabularyStudyStartMinute)
                ?? VocabularyDisplayScheduler.defaultStudyStartMinute,
            endMinute: try container.decodeIfPresent(Int.self, forKey: .vocabularyStudyEndMinute)
                ?? VocabularyDisplayScheduler.defaultStudyEndMinute
        )
        vocabularyStudyStartMinute = studyWindow.startMinute
        vocabularyStudyEndMinute = studyWindow.endMinute
        vocabularyQuestionPersists = try container.decodeIfPresent(Bool.self, forKey: .vocabularyQuestionPersists) ?? true
        vocabularyWindowStartDate = try container.decodeIfPresent(Date.self, forKey: .vocabularyWindowStartDate)
        vocabularyShownCountDate = try container.decodeIfPresent(String.self, forKey: .vocabularyShownCountDate)
        vocabularyShownCount = max(0, try container.decodeIfPresent(Int.self, forKey: .vocabularyShownCount) ?? 0)
        dailyNewVocabularyLimit = max(0, try container.decodeIfPresent(Int.self, forKey: .dailyNewVocabularyLimit) ?? 3)
        newVocabularyKeys = try container.decodeIfPresent([String].self, forKey: .newVocabularyKeys) ?? []
        vocabularyRecallMode = try container.decodeIfPresent(Bool.self, forKey: .vocabularyRecallMode) ?? true
        vocabularyRetention = min(0.95, max(0.8, try container.decodeIfPresent(Double.self, forKey: .vocabularyRetention) ?? 0.9))
        petClickFeedbackPhrases = AppSettings.normalizedPetClickFeedbackPhrases(
            try container.decodeIfPresent([String].self, forKey: .petClickFeedbackPhrases)
            ?? AppSettings.defaultPetClickFeedbackPhrases
        )
    }

    static func normalizedPetClickFeedbackPhrases(_ phrases: [String]) -> [String] {
        var normalized = phrases.map {
            $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        normalized = Array(normalized.prefix(5))
        var fallbackIndex = 0
        while normalized.count < 3 {
            normalized.append(defaultPetClickFeedbackPhrases[fallbackIndex % defaultPetClickFeedbackPhrases.count])
            fallbackIndex += 1
        }
        return normalized
    }
}

enum PetMediaKind: String, Codable, Equatable {
    case photo
    case animatedImage
    case video
    case codexPackage
}

typealias PetAssetKind = PetMediaKind

struct PetAsset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: PetAssetKind
    var imageFileName: String?
    var mediaFileName: String?
    var packageDirectoryName: String?
    var spriteFileName: String?
    var previewFileName: String?
    var packageSourceID: String?
    var packageSourceURL: String?
    var supportsNativeActions: Bool
    var actionFrameCount: Int
    var createdAt: Date
    var appearances: Int
    var isEnabled: Bool
    var weight: Double

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: PetAssetKind,
        imageFileName: String? = nil,
        mediaFileName: String? = nil,
        packageDirectoryName: String? = nil,
        spriteFileName: String? = nil,
        previewFileName: String? = nil,
        packageSourceID: String? = nil,
        packageSourceURL: String? = nil,
        supportsNativeActions: Bool = false,
        actionFrameCount: Int = 8,
        createdAt: Date = Date(),
        appearances: Int = 0,
        isEnabled: Bool = true,
        weight: Double = 1
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.imageFileName = imageFileName
        self.mediaFileName = mediaFileName
        self.packageDirectoryName = packageDirectoryName
        self.spriteFileName = spriteFileName
        self.previewFileName = previewFileName
        self.packageSourceID = packageSourceID
        self.packageSourceURL = packageSourceURL
        self.supportsNativeActions = supportsNativeActions
        self.actionFrameCount = max(1, min(64, actionFrameCount))
        self.createdAt = createdAt
        self.appearances = appearances
        self.isEnabled = isEnabled
        self.weight = max(0.1, min(5, weight))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case imageFileName
        case mediaFileName
        case packageDirectoryName
        case spriteFileName
        case previewFileName
        case packageSourceID
        case packageSourceURL
        case supportsNativeActions
        case actionFrameCount
        case createdAt
        case appearances
        case isEnabled
        case weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名宠物"
        kind = try container.decodeIfPresent(PetAssetKind.self, forKey: .kind) ?? .photo
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        mediaFileName = try container.decodeIfPresent(String.self, forKey: .mediaFileName) ?? imageFileName
        packageDirectoryName = try container.decodeIfPresent(String.self, forKey: .packageDirectoryName)
        spriteFileName = try container.decodeIfPresent(String.self, forKey: .spriteFileName)
        previewFileName = try container.decodeIfPresent(String.self, forKey: .previewFileName)
        packageSourceID = try container.decodeIfPresent(String.self, forKey: .packageSourceID)
        packageSourceURL = try container.decodeIfPresent(String.self, forKey: .packageSourceURL)
        supportsNativeActions = try container.decodeIfPresent(Bool.self, forKey: .supportsNativeActions) ?? (kind == .codexPackage)
        actionFrameCount = max(1, min(64, try container.decodeIfPresent(Int.self, forKey: .actionFrameCount) ?? 8))
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        appearances = try container.decodeIfPresent(Int.self, forKey: .appearances) ?? 0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        weight = max(0.1, min(5, try container.decodeIfPresent(Double.self, forKey: .weight) ?? 1))
    }
}

extension PetAsset {
    var mediaLabel: String {
        switch kind {
        case .photo: return "静态照片"
        case .animatedImage: return "GIF/APNG 动画"
        case .video: return "视频循环"
        case .codexPackage: return supportsNativeActions ? "原生 9 动作" : "Pet 包"
        }
    }
}

struct PetInstallPreview: Identifiable, Equatable {
    var id: String { packageID }
    var packageID: String
    var displayName: String
    var description: String?
    var sourceInput: String
    var sourceDownloadURL: URL
    var tempRootURL: URL
    var packageDirectoryURL: URL
    var spriteFileName: String
    var previewFileName: String?
    var supportsNativeActions: Bool
    var framesPerAction: Int
    var alreadyInstalled: Bool
}

struct DictionarySummary: Identifiable {
    var id: String { pack.id }
    var pack: DictionaryPack
    var isEnabled: Bool
    var isBuiltIn: Bool
    var category: String?
    var learnedCount: Int
    var unknownCount: Int
    var skippedCount: Int
}

final class AppDataStore: ObservableObject {
    let rootURL: URL
    let petsURL: URL
    let packagesURL: URL
    let dictionariesURL: URL
    let settingsURL: URL
    let petsManifestURL: URL
    let progressURL: URL

    let objectWillChange = ObservableObjectPublisher()
    private(set) var libraryRevision = 0
    var settings: AppSettings {
        didSet { if oldValue.enabledDictionaryIDs != settings.enabledDictionaryIDs { libraryRevision &+= 1 } }
    }
    var pets: [PetAsset]
    var dictionaries: [DictionaryPack] { didSet { libraryRevision &+= 1 } }
    var vocabularyProgress: VocabularyProgress { didSet { libraryRevision &+= 1 } }
    var personalVocabulary: PersonalVocabulary { didSet { libraryRevision &+= 1 } }
    let captureToken: String
    let isUsingAlternateDataDirectory: Bool
    let progressState = ProgressStateStore()
    private var previewImageCache: [String: NSImage] = [:]
    private var spriteRendererCache: [String: PetAnimationRenderer] = [:]

    init(root: URL? = nil) throws {
        rootURL = try root ?? JSONFileStore.applicationSupportDirectory()
        let normalRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexDesktopPet")
        isUsingAlternateDataDirectory = rootURL.resolvingSymlinksInPath().standardizedFileURL != normalRoot.resolvingSymlinksInPath().standardizedFileURL
        petsURL = rootURL.appendingPathComponent("Pets", isDirectory: true)
        packagesURL = rootURL.appendingPathComponent("Packages", isDirectory: true)
        dictionariesURL = rootURL.appendingPathComponent("Dictionaries", isDirectory: true)
        settingsURL = rootURL.appendingPathComponent("settings.json")
        petsManifestURL = rootURL.appendingPathComponent("pets.json")
        progressURL = rootURL.appendingPathComponent("learning-progress.json")

        try FileManager.default.createDirectory(at: petsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dictionariesURL, withIntermediateDirectories: true)

        let tokenURL = rootURL.appendingPathComponent("browser-pairing-token")
        if let token = try? String(contentsOf: tokenURL, encoding: .utf8),
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            captureToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            captureToken = UUID().uuidString + UUID().uuidString
            try Data(captureToken.utf8).write(to: tokenURL, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        let notebookURL = rootURL.appendingPathComponent("personal-vocabulary.json")
        if FileManager.default.fileExists(atPath: notebookURL.path) {
            personalVocabulary = try JSONFileStore.decoder.decode(PersonalVocabulary.self, from: Data(contentsOf: notebookURL))
        } else {
            personalVocabulary = PersonalVocabulary()
        }

        settings = JSONFileStore.load(AppSettings.self, from: settingsURL, fallback: AppSettings())
        let currentModel = DeepSeekConfiguration.resolvedModel(settings.deepSeekModel, baseURL: settings.deepSeekBaseURL)
        if currentModel != settings.deepSeekModel {
            settings.deepSeekModel = currentModel
            try JSONFileStore.save(settings, to: settingsURL)
        }
        if abs(settings.movementSpeedMultiplier - 0.45) < 0.000_1 {
            settings.movementSpeedMultiplier = 0.20
        }
        pets = JSONFileStore.load([PetAsset].self, from: petsManifestURL, fallback: [])
        vocabularyProgress = JSONFileStore.load(VocabularyProgress.self, from: progressURL, fallback: VocabularyProgress())
        dictionaries = BuiltInDictionaries.packs
        try installBundledPetsIfNeeded()
        try installBundledDictionariesIfNeeded()
        try loadUserDictionaries()
        syncLearningProgress()
        resetVocabularyScheduleIfNeeded()
    }

    func saveSettings() {
        settings.dailyNewVocabularyLimit = max(0, settings.dailyNewVocabularyLimit)
        settings.vocabularyMinimumIntervalMinutes = max(1, settings.vocabularyMinimumIntervalMinutes)
        settings.movementSpeedMultiplier = min(max(settings.movementSpeedMultiplier, 0.05), 1.4)
        settings.dailyVocabularyLimit = VocabularyDisplayScheduler.normalizedDailyLimit(settings.dailyVocabularyLimit)
        settings.vocabularyWindowHours = VocabularyDisplayScheduler.normalizedWindowHours(settings.vocabularyWindowHours)
        let studyWindow = VocabularyDisplayScheduler.normalizedStudyWindow(
            startMinute: settings.vocabularyStudyStartMinute,
            endMinute: settings.vocabularyStudyEndMinute
        )
        settings.vocabularyStudyStartMinute = studyWindow.startMinute
        settings.vocabularyStudyEndMinute = studyWindow.endMinute
        settings.vocabularyWindowStartDate = nil
        settings.vocabularyShownCount = max(0, settings.vocabularyShownCount)
        settings.petClickFeedbackPhrases = AppSettings.normalizedPetClickFeedbackPhrases(settings.petClickFeedbackPhrases)
        try? JSONFileStore.save(settings, to: settingsURL)
    }

    func savePets() {
        try? JSONFileStore.save(pets, to: petsManifestURL)
    }

    func selectVisualTheme(_ theme: AppVisualTheme) throws {
        guard settings.visualTheme != theme else { return }
        var updated = settings
        updated.visualTheme = theme
        try JSONFileStore.save(updated, to: settingsURL)
        objectWillChange.send()
        settings = updated
        NotificationCenter.default.post(name: .companionThemeDidChange, object: self)
    }

    func saveLearningProgress() {
        syncLearningProgress()
        try? JSONFileStore.save(vocabularyProgress, to: progressURL)
        if let syncURL = syncFileURL {
            try? JSONFileStore.save(vocabularyProgress, to: syncURL)
        }
        objectWillChange.send()
    }

    func syncLearningProgress() {
        guard let syncURL = syncFileURL else { return }
        let remote = JSONFileStore.load(VocabularyProgress.self, from: syncURL, fallback: VocabularyProgress())
        vocabularyProgress.stats = LearningSync.merge(
            local: vocabularyProgress.stats,
            remote: remote.stats
        )
    }

    func setSyncDirectory(_ directory: URL) {
        let fileURL = directory.appendingPathComponent("codex-desktop-pet-learning.json")
        objectWillChange.send()
        settings.syncFilePath = fileURL.path
        saveSettings()
        saveLearningProgress()
    }

    var syncFileURL: URL? {
        settings.syncFilePath.map(URL.init(fileURLWithPath:))
    }

    func importDictionary(from url: URL) throws -> [DictionaryPack] {
        let data = try Data(contentsOf: url)
        let packs = try DictionaryImporter.importPacks(data: data, fileName: url.lastPathComponent)
        objectWillChange.send()
        for pack in packs {
            let outputURL = dictionariesURL.appendingPathComponent("\(pack.id).json")
            try JSONFileStore.save(pack, to: outputURL)
            settings.enabledDictionaryIDs.insert(pack.id)
        }
        try loadUserDictionaries()
        saveSettings()
        return packs
    }

    func renameDictionary(_ dictionaryID: String, name: String, category: String?) throws {
        guard !isBuiltInDictionary(dictionaryID) else {
            throw NSError(domain: "CodexDesktopPet", code: 61, userInfo: [NSLocalizedDescriptionKey: "内置示例词典不能重命名。"])
        }
        guard let index = dictionaries.firstIndex(where: { $0.id == dictionaryID }) else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw NSError(domain: "CodexDesktopPet", code: 62, userInfo: [NSLocalizedDescriptionKey: "词典名称不能为空。"])
        }

        objectWillChange.send()
        dictionaries[index].name = cleanName
        dictionaries[index].description = dictionaryDescription(
            category: category,
            existingDescription: dictionaries[index].description
        )
        try JSONFileStore.save(dictionaries[index], to: dictionaryFileURL(dictionaryID))
    }

    @discardableResult
    func deleteDictionary(_ dictionaryID: String, deleteLearningProgress: Bool = false) throws -> URL? {
        let isSample = isBuiltInDictionary(dictionaryID)
        let fileURL = dictionaryFileURL(dictionaryID).standardizedFileURL
        guard fileURL.deletingLastPathComponent() == dictionariesURL.standardizedFileURL,
              dictionaries.contains(where: { $0.id == dictionaryID }) else {
            throw NSError(domain: "CodexDesktopPet", code: 64, userInfo: [NSLocalizedDescriptionKey: "找不到可删除的本地词典。"])
        }
        let resourceOnly = isSample && !FileManager.default.fileExists(atPath: fileURL.path)
        if !resourceOnly {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw NSError(domain: "CodexDesktopPet", code: 65, userInfo: [NSLocalizedDescriptionKey: "词典文件无效，未移到废纸篓。"])
            }
        }
        var updatedSettings = settings
        updatedSettings.enabledDictionaryIDs.remove(dictionaryID)
        var updatedProgress = vocabularyProgress
        var writes: [(url: URL, data: Data)] = [
            (settingsURL, try JSONFileStore.encoder.encode(updatedSettings))
        ]
        if isSample {
            var removed = try removedSampleDictionaryIDs()
            removed.insert(dictionaryID)
            writes.append((sampleRemovalsURL, try JSONFileStore.encoder.encode(removed.sorted())))
        }
        if deleteLearningProgress {
            for url in [progressURL, syncFileURL].compactMap({ $0 }) {
                guard let data = try readLocalFileIfPresent(at: url) else { continue }
                let latest = try JSONFileStore.decoder.decode(VocabularyProgress.self, from: data)
                updatedProgress.stats = LearningSync.merge(local: updatedProgress.stats, remote: latest.stats)
            }
            updatedProgress.stats = updatedProgress.stats.filter { !$0.key.hasPrefix("\(dictionaryID)::") }
            let data = try JSONFileStore.encoder.encode(updatedProgress)
            writes.append((progressURL, data))
            if let syncURL = syncFileURL, syncURL.standardizedFileURL != progressURL.standardizedFileURL {
                writes.append((syncURL, data))
            }
        }
        var trashedURL: NSURL?
        try commitLocalFiles(writes) {
            // Trash is the last throwing operation; there is no permanent-delete fallback.
            if !resourceOnly { try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashedURL) }
        }
        objectWillChange.send()
        dictionaries.removeAll { $0.id == dictionaryID }
        settings = updatedSettings
        if deleteLearningProgress { vocabularyProgress = updatedProgress }
        return trashedURL.map { $0 as URL }
    }

    private var sampleRemovalsURL: URL { rootURL.appendingPathComponent("removed-sample-dictionaries.json") }

    private func removedSampleDictionaryIDs() throws -> Set<String> {
        guard let data = try readLocalFileIfPresent(at: sampleRemovalsURL) else { return [] }
        return Set(try JSONFileStore.decoder.decode([String].self, from: data))
    }

    func restoreSampleDictionaries() throws {
        try commitLocalFiles([(sampleRemovalsURL, try JSONFileStore.encoder.encode([String]()))])
        objectWillChange.send()
        try loadUserDictionaries()
    }

    func readLocalFileIfPresent(at url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    // These local commits stage memory separately and restore prior bytes on write/final-operation failure.
    func commitLocalFiles(_ writes: [(url: URL, data: Data)], finalOperation: () throws -> Void = {}) throws {
        let paths = writes.map { $0.url.standardizedFileURL.path }
        guard Set(paths).count == paths.count else {
            throw NSError(domain: "CodexDesktopPet", code: 67, userInfo: [NSLocalizedDescriptionKey: "本地文件路径冲突，未提交修改。"])
        }
        let originals = try writes.map { try readLocalFileIfPresent(at: $0.url) }
        var committed = 0
        do {
            for write in writes {
                try write.data.write(to: write.url, options: .atomic)
                committed += 1
            }
            try finalOperation()
        } catch {
            var rollbackErrors: [String] = []
            for index in (0..<committed).reversed() {
                do {
                    if let original = originals[index] {
                        try original.write(to: writes[index].url, options: .atomic)
                    } else {
                        try FileManager.default.removeItem(at: writes[index].url)
                    }
                } catch { rollbackErrors.append(error.localizedDescription) }
            }
            if !rollbackErrors.isEmpty {
                throw NSError(domain: "CodexDesktopPet", code: 66, userInfo: [
                    NSLocalizedDescriptionKey: "\(error.localizedDescription)；恢复本地文件失败：\(rollbackErrors.joined(separator: "; "))",
                    NSUnderlyingErrorKey: error
                ])
            }
            throw error
        }
    }

    func preparePDFDictionaryDraft(from url: URL) throws -> DictionaryImportDraft {
        try PDFDictionaryImporter.draft(fromPDF: url)
    }

    func importDictionaryDraft(_ draft: DictionaryImportDraft) throws -> DictionaryPack {
        let pack = draft.pack
        guard !pack.entries.isEmpty else {
            throw PDFDictionaryImportError.noEntries
        }
        objectWillChange.send()
        let outputURL = dictionariesURL.appendingPathComponent("\(pack.id).json")
        try JSONFileStore.save(pack, to: outputURL)
        settings.enabledDictionaryIDs.insert(pack.id)
        try loadUserDictionaries()
        saveSettings()
        return pack
    }

    func generateExamples(for draft: DictionaryImportDraft) async throws -> DictionaryImportDraft {
        let missing = draft.entries
            .filter { ($0.example ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(30)
        guard !missing.isEmpty else { return draft }

        let examples = try await ExampleGenerator.generateExamples(
            entries: Array(missing),
            apiKey: KeychainStore.readExampleAPIKey(provider: settings.exampleProvider) ?? "",
            model: exampleModel,
            provider: settings.exampleProvider,
            baseURL: settings.exampleProvider == .deepSeek ? settings.deepSeekBaseURL : nil
        )
        var updated = draft
        for generated in examples {
            guard let index = updated.entries.firstIndex(where: { $0.term.caseInsensitiveCompare(generated.term) == .orderedSame }) else {
                continue
            }
            updated.entries[index].example = generated.example
            updated.entries[index].exampleTranslation = generated.exampleTranslation
            updated.entries[index].hint = generated.hint
        }
        return updated
    }

    func parsePDFDraftWithDeepSeek(_ draft: DictionaryImportDraft) async throws -> DictionaryImportDraft {
        try await DeepSeekDictionaryParser.parseDictionary(
            sourceText: draft.sourceText ?? draft.entries.map(\.context).joined(separator: "\n"),
            fileName: draft.sourceFileName,
            dictionaryName: draft.dictionaryName,
            apiKey: KeychainStore.readExampleAPIKey(provider: .deepSeek) ?? "",
            model: settings.deepSeekModel,
            baseURL: settings.deepSeekBaseURL
        )
    }

    func addPet(name: String, imageData: Data) throws -> PetAsset {
        let id = UUID().uuidString
        let fileName = "\(id).png"
        try imageData.write(to: petsURL.appendingPathComponent(fileName), options: [.atomic])
        let pet = PetAsset(
            name: name,
            kind: .photo,
            imageFileName: fileName
        )
        objectWillChange.send()
        pets.append(pet)
        savePets()
        return pet
    }

    func addPetMedia(from url: URL) throws -> PetAsset {
        try addPetMedia(from: url, name: url.deletingPathExtension().lastPathComponent)
    }

    func importPetMediaItems(from url: URL) throws -> [PetAsset] {
        guard url.pathExtension.lowercased() == "zip" else {
            return [try addPetMedia(from: url)]
        }

        let extractRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-media-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: extractRoot) }
        try extractZipContents(url, to: extractRoot)

        let mediaFiles = try mediaFiles(in: extractRoot)
        guard !mediaFiles.isEmpty else {
            throw NSError(
                domain: "CodexDesktopPet",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "这个 zip 里没有可导入的图片/GIF/视频，也不是包含 pet.json 的 Codex pet 包。"]
            )
        }

        if mediaFiles.count >= 2,
           mediaFiles.allSatisfy({ Self.staticImageExtensions.contains($0.pathExtension.lowercased()) }) {
            return [try importPhotoArchiveAsAnimatedPet(name: url.deletingPathExtension().lastPathComponent, imageURLs: mediaFiles)]
        }

        let archiveName = url.deletingPathExtension().lastPathComponent
        return try mediaFiles.enumerated().map { index, mediaURL in
            try addPetMedia(from: mediaURL, name: "\(archiveName) \(index + 1)")
        }
    }

    private func importPhotoArchiveAsAnimatedPet(name: String, imageURLs: [URL]) throws -> PetAsset {
        let sourceID = CodexPetPackageInstaller.sanitizedIdentifier(name)
        objectWillChange.send()
        for pet in pets where pet.id == sourceID || pet.packageSourceID == sourceID {
            if let packageDirectoryName = pet.packageDirectoryName {
                try? FileManager.default.removeItem(at: packagesURL.appendingPathComponent(packageDirectoryName))
            }
            invalidatePetCaches(for: pet.id)
        }
        pets.removeAll { $0.id == sourceID || $0.packageSourceID == sourceID }

        let destinationName = sourceID
        let destination = packagesURL.appendingPathComponent(destinationName, isDirectory: true)
        let inspection = try PhotoArchivePetBuilder.buildPackage(
            name: name,
            imageURLs: imageURLs,
            destination: destination
        )

        let pet = PetAsset(
            id: destinationName,
            name: name,
            kind: .codexPackage,
            packageDirectoryName: destinationName,
            spriteFileName: inspection.spriteFileName,
            previewFileName: inspection.previewFileName,
            packageSourceID: sourceID,
            supportsNativeActions: true,
            actionFrameCount: inspection.framesPerAction
        )
        pets.append(pet)
        savePets()
        return pet
    }

    private func addPetMedia(from url: URL, name: String) throws -> PetAsset {
        let ext = url.pathExtension.lowercased()
        let id = UUID().uuidString

        if Self.videoExtensions.contains(ext) {
            let fileName = "\(id).\(ext.isEmpty ? "mov" : ext)"
            try FileManager.default.copyItem(at: url, to: petsURL.appendingPathComponent(fileName))
            let pet = PetAsset(name: name, kind: .video, mediaFileName: fileName)
            objectWillChange.send()
            pets.append(pet)
            savePets()
            return pet
        }

        if AnimatedPetRenderer.isAnimatedImage(url) {
            let fileName = "\(id).\(ext.isEmpty ? "gif" : ext)"
            try FileManager.default.copyItem(at: url, to: petsURL.appendingPathComponent(fileName))
            let pet = PetAsset(name: name, kind: .animatedImage, mediaFileName: fileName)
            objectWillChange.send()
            pets.append(pet)
            savePets()
            return pet
        }

        let data = try PetImageProcessor.processImage(at: url)
        return try addPet(name: name, imageData: data)
    }

    func importCodexPackage(from sourceURL: URL) throws -> PetAsset {
        if sourceURL.pathExtension.lowercased() == "zip" {
            let extractRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("codex-pet-local-package-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: extractRoot) }
            let packageDirectory = try CodexPetPackageInstaller.extractZip(sourceURL, to: extractRoot)
            return try importCodexPackage(from: packageDirectory)
        }

        let inspection = try CodexPetPackageInstaller.inspectPackage(at: sourceURL)
        let sourceID = CodexPetPackageInstaller.sanitizedIdentifier(inspection.manifest.id)
        let destinationName = uniquePackageDirectoryName(preferred: sourceID)
        let destination = packagesURL.appendingPathComponent(destinationName, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let pet = PetAsset(
            id: destinationName,
            name: inspection.manifest.resolvedDisplayName,
            kind: .codexPackage,
            packageDirectoryName: destinationName,
            spriteFileName: inspection.spriteFileName,
            previewFileName: inspection.previewFileName,
            packageSourceID: sourceID,
            supportsNativeActions: inspection.supportsNativeActions,
            actionFrameCount: inspection.framesPerAction
        )
        objectWillChange.send()
        pets.append(pet)
        savePets()
        return pet
    }

    func prepareRemotePetInstall(from rawInput: String) async throws -> PetInstallPreview {
        let reference = try CodexPetPackageInstaller.remoteReference(for: rawInput)
        let downloadURL = try await resolveDownloadURL(for: reference)
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let zipURL = tempRoot.appendingPathComponent(downloadURL.lastPathComponent.isEmpty ? "pet.zip" : downloadURL.lastPathComponent)
        let downloadedURL = try await downloadFile(from: downloadURL)
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: zipURL)

        let extractRoot = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        let packageDirectory = try CodexPetPackageInstaller.extractZip(zipURL, to: extractRoot)
        let inspection = try CodexPetPackageInstaller.inspectPackage(at: packageDirectory)
        let packageID = CodexPetPackageInstaller.sanitizedIdentifier(inspection.manifest.id)

        return PetInstallPreview(
            packageID: packageID,
            displayName: inspection.manifest.resolvedDisplayName,
            description: inspection.manifest.description,
            sourceInput: rawInput,
            sourceDownloadURL: downloadURL,
            tempRootURL: tempRoot,
            packageDirectoryURL: packageDirectory,
            spriteFileName: inspection.spriteFileName,
            previewFileName: inspection.previewFileName,
            supportsNativeActions: inspection.supportsNativeActions,
            framesPerAction: inspection.framesPerAction,
            alreadyInstalled: isPackageInstalled(sourceID: packageID)
        )
    }

    func installRemotePet(_ preview: PetInstallPreview, overwrite: Bool) throws -> PetAsset {
        let destination = packagesURL.appendingPathComponent(preview.packageID, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard overwrite else {
                throw NSError(domain: "CodexDesktopPet", code: 30, userInfo: [NSLocalizedDescriptionKey: "已经安装过 \(preview.displayName)。"])
            }
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: preview.packageDirectoryURL, to: destination)
        try installPackageForCodex(from: preview.packageDirectoryURL, packageID: preview.packageID, overwrite: overwrite)

        objectWillChange.send()
        pets.removeAll {
            $0.id == preview.packageID || $0.packageSourceID == preview.packageID
        }
        invalidatePetCaches(for: preview.packageID)

        let pet = PetAsset(
            id: preview.packageID,
            name: preview.displayName,
            kind: .codexPackage,
            packageDirectoryName: preview.packageID,
            spriteFileName: preview.spriteFileName,
            previewFileName: preview.previewFileName,
            packageSourceID: preview.packageID,
            packageSourceURL: preview.sourceInput,
            supportsNativeActions: preview.supportsNativeActions,
            actionFrameCount: preview.framesPerAction
        )
        pets.append(pet)
        savePets()
        discardInstallPreview(preview)
        return pet
    }

    func discardInstallPreview(_ preview: PetInstallPreview) {
        try? FileManager.default.removeItem(at: preview.tempRootURL)
    }

    func deletePet(_ pet: PetAsset) {
        objectWillChange.send()
        pets.removeAll { $0.id == pet.id }
        invalidatePetCaches(for: pet.id)
        if let imageFileName = pet.imageFileName {
            try? FileManager.default.removeItem(at: petsURL.appendingPathComponent(imageFileName))
        }
        if let mediaFileName = pet.mediaFileName, mediaFileName != pet.imageFileName {
            try? FileManager.default.removeItem(at: petsURL.appendingPathComponent(mediaFileName))
        }
        if let packageDirectoryName = pet.packageDirectoryName {
            try? FileManager.default.removeItem(at: packagesURL.appendingPathComponent(packageDirectoryName))
        }
        savePets()
    }

    func setPetEnabled(_ pet: PetAsset, isEnabled: Bool) {
        guard let index = pets.firstIndex(where: { $0.id == pet.id }) else { return }
        objectWillChange.send()
        pets[index].isEnabled = isEnabled
        savePets()
    }

    func setPetWeight(_ pet: PetAsset, weight: Double) {
        guard let index = pets.firstIndex(where: { $0.id == pet.id }) else { return }
        objectWillChange.send()
        pets[index].weight = max(0.1, min(5, weight))
        savePets()
    }

    func setMovementSpeedMultiplier(_ value: Double) {
        objectWillChange.send()
        settings.movementSpeedMultiplier = min(max(value, 0.05), 1.4)
        saveSettings()
    }

    func setWalkingPaused(_ value: Bool) {
        guard settings.walkingPaused != value else { return }
        objectWillChange.send()
        settings.walkingPaused = value
        saveSettings()
    }

    func petClickFeedbackPhrase(at index: Int) -> String {
        // SwiftUI can query a removed text field's binding during view teardown.
        settings.petClickFeedbackPhrases.indices.contains(index) ? settings.petClickFeedbackPhrases[index] : ""
    }

    func setPetClickFeedbackPhrase(index: Int, phrase: String) {
        guard settings.petClickFeedbackPhrases.indices.contains(index) else { return }
        objectWillChange.send()
        settings.petClickFeedbackPhrases[index] = phrase
        saveSettings()
    }

    func addPetClickFeedbackPhrase() {
        guard settings.petClickFeedbackPhrases.count < 5 else { return }
        objectWillChange.send()
        let fallback = AppSettings.defaultPetClickFeedbackPhrases[
            settings.petClickFeedbackPhrases.count % AppSettings.defaultPetClickFeedbackPhrases.count
        ]
        settings.petClickFeedbackPhrases.append(fallback)
        saveSettings()
    }

    func removePetClickFeedbackPhrase(at index: Int) {
        guard settings.petClickFeedbackPhrases.count > 3,
              settings.petClickFeedbackPhrases.indices.contains(index) else { return }
        objectWillChange.send()
        settings.petClickFeedbackPhrases.remove(at: index)
        saveSettings()
    }

    var availablePetClickFeedbackPhrases: [String] {
        let phrases = settings.petClickFeedbackPhrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return phrases.isEmpty ? AppSettings.defaultPetClickFeedbackPhrases : phrases
    }

    func setDailyVocabularyLimit(_ value: Int) {
        let next = VocabularyDisplayScheduler.normalizedDailyLimit(value)
        guard settings.dailyVocabularyLimit != next else { return }
        objectWillChange.send()
        settings.dailyVocabularyLimit = next
        if settings.vocabularyShownCount > next {
            settings.vocabularyShownCount = next
        }
        saveSettings()
    }

    func setVocabularyWindowHours(_ value: Int) {
        let next = VocabularyDisplayScheduler.normalizedWindowHours(value)
        guard settings.vocabularyWindowHours != next else { return }
        objectWillChange.send()
        settings.vocabularyWindowHours = next
        saveSettings()
    }

    func setVocabularyStudyStartMinute(_ value: Int) {
        let window = VocabularyDisplayScheduler.normalizedStudyWindow(
            startMinute: value,
            endMinute: settings.vocabularyStudyEndMinute
        )
        guard settings.vocabularyStudyStartMinute != window.startMinute
            || settings.vocabularyStudyEndMinute != window.endMinute else { return }
        objectWillChange.send()
        settings.vocabularyStudyStartMinute = window.startMinute
        settings.vocabularyStudyEndMinute = window.endMinute
        saveSettings()
    }

    func setVocabularyStudyEndMinute(_ value: Int) {
        let window = VocabularyDisplayScheduler.normalizedStudyWindow(
            startMinute: settings.vocabularyStudyStartMinute,
            endMinute: value
        )
        guard settings.vocabularyStudyStartMinute != window.startMinute
            || settings.vocabularyStudyEndMinute != window.endMinute else { return }
        objectWillChange.send()
        settings.vocabularyStudyStartMinute = window.startMinute
        settings.vocabularyStudyEndMinute = window.endMinute
        saveSettings()
    }

    func setVocabularyQuestionPersists(_ value: Bool) {
        guard settings.vocabularyQuestionPersists != value else { return }
        objectWillChange.send()
        settings.vocabularyQuestionPersists = value
        saveSettings()
    }

    func setOpenAIModel(_ value: String) {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = model.isEmpty ? "gpt-5.2" : model
        guard settings.openAIModel != next else { return }
        objectWillChange.send()
        settings.openAIModel = next
        saveSettings()
    }

    func setExampleProvider(_ provider: ExampleProvider) {
        guard settings.exampleProvider != provider else { return }
        objectWillChange.send()
        settings.exampleProvider = provider
        saveSettings()
    }

    func setDeepSeekModel(_ value: String) {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = model.isEmpty ? DeepSeekConfiguration.defaultModel : model
        guard settings.deepSeekModel != next else { return }
        objectWillChange.send()
        settings.deepSeekModel = next
        saveSettings()
    }

    func setDeepSeekBaseURL(_ value: String) {
        let url = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = url.isEmpty ? "https://api.deepseek.com" : url
        guard settings.deepSeekBaseURL != next else { return }
        objectWillChange.send()
        settings.deepSeekBaseURL = next
        saveSettings()
    }

    var exampleModel: String {
        switch settings.exampleProvider {
        case .openAI:
            return settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gpt-5.2" : settings.openAIModel
        case .deepSeek:
            return settings.deepSeekModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DeepSeekConfiguration.defaultModel : settings.deepSeekModel
        }
    }

    func recordAppearance(for pet: PetAsset) {
        guard let index = pets.firstIndex(where: { $0.id == pet.id }) else { return }
        pets[index].appearances += 1
        savePets()
    }

    func imageURL(for pet: PetAsset) -> URL {
        if let mediaFileName = pet.mediaFileName {
            return petsURL.appendingPathComponent(mediaFileName)
        }
        if let imageFileName = pet.imageFileName {
            return petsURL.appendingPathComponent(imageFileName)
        }
        if let packageDirectoryName = pet.packageDirectoryName,
           let previewFileName = pet.previewFileName ?? pet.spriteFileName {
            return packagesURL
                .appendingPathComponent(packageDirectoryName, isDirectory: true)
                .appendingPathComponent(previewFileName)
        }
        return petsURL.appendingPathComponent("__missing__.png")
    }

    func packageURL(for pet: PetAsset) -> URL? {
        guard let packageDirectoryName = pet.packageDirectoryName else { return nil }
        return packagesURL.appendingPathComponent(packageDirectoryName, isDirectory: true)
    }

    func spriteURL(for pet: PetAsset) -> URL? {
        guard let packageURL = packageURL(for: pet),
              let spriteFileName = pet.spriteFileName else {
            return nil
        }
        return packageURL.appendingPathComponent(spriteFileName)
    }

    func previewImage(for pet: PetAsset) -> NSImage? {
        if let cached = previewImageCache[pet.id] {
            return cached
        }
        let image: NSImage?
        if pet.kind == .video, let videoURL = mediaURL(for: pet) {
            image = videoPreviewImage(url: videoURL)
        } else if pet.kind == .animatedImage,
                  let mediaURL = mediaURL(for: pet),
                  let renderer = AnimatedPetRenderer(url: mediaURL) {
            image = renderer.stillFrame
        } else if pet.kind == .codexPackage,
                  let previewFileName = pet.previewFileName,
                  let packageURL = packageURL(for: pet) {
            image = NSImage(contentsOf: packageURL.appendingPathComponent(previewFileName))
        } else if pet.kind == .codexPackage,
                  let renderer = spriteRenderer(for: pet) {
            image = renderer.stillFrame()
        } else {
            image = NSImage(contentsOf: imageURL(for: pet))
        }
        if let image {
            previewImageCache[pet.id] = image
        }
        return image
    }

    func spriteRenderer(for pet: PetAsset) -> PetAnimationRenderer? {
        guard let spriteURL = spriteURL(for: pet) else { return nil }
        let cacheKey = "\(pet.id)-\(pet.actionFrameCount)-\(spriteURL.path)"
        if let cached = spriteRendererCache[cacheKey] {
            return cached
        }
        guard let renderer = PetAnimationRenderer(spriteURL: spriteURL, framesPerAction: pet.actionFrameCount) else {
            return nil
        }
        spriteRendererCache[cacheKey] = renderer
        return renderer
    }

    private func invalidatePetCaches(for petID: String) {
        previewImageCache.removeValue(forKey: petID)
        spriteRendererCache = spriteRendererCache.filter { !$0.key.hasPrefix("\(petID)-") }
    }

    func mediaURL(for pet: PetAsset) -> URL? {
        guard let mediaFileName = pet.mediaFileName ?? pet.imageFileName else { return nil }
        return petsURL.appendingPathComponent(mediaFileName)
    }

    func enabledPets() -> [PetAsset] {
        pets.filter { $0.isEnabled && $0.weight > 0 }
    }

    var vocabularyScheduleSnapshot: VocabularyDisplayScheduleSnapshot {
        get {
            VocabularyDisplayScheduleSnapshot(
                dailyLimit: settings.dailyVocabularyLimit,
                windowHours: settings.vocabularyWindowHours,
                questionPersists: settings.vocabularyQuestionPersists,
                windowStartDate: settings.vocabularyWindowStartDate,
                shownCountDate: settings.vocabularyShownCountDate,
                shownCount: settings.vocabularyShownCount,
                studyStartMinute: settings.vocabularyStudyStartMinute,
                studyEndMinute: settings.vocabularyStudyEndMinute
            )
        }
        set {
            let normalized = VocabularyDisplayScheduler.normalized(newValue)
            settings.dailyVocabularyLimit = normalized.dailyLimit
            settings.vocabularyWindowHours = normalized.windowHours
            settings.vocabularyQuestionPersists = normalized.questionPersists
            settings.vocabularyWindowStartDate = normalized.windowStartDate
            settings.vocabularyShownCountDate = normalized.shownCountDate
            settings.vocabularyShownCount = normalized.shownCount
            settings.vocabularyStudyStartMinute = normalized.studyStartMinute
            settings.vocabularyStudyEndMinute = normalized.studyEndMinute
        }
    }

    func resetVocabularyScheduleIfNeeded(now: Date = Date()) {
        let current = vocabularyScheduleSnapshot
        let updated = VocabularyDisplayScheduler.resetIfNeeded(current, now: now)
        guard current != updated else { return }
        objectWillChange.send()
        if current.shownCountDate != updated.shownCountDate { settings.newVocabularyKeys = [] }
        vocabularyScheduleSnapshot = updated
        saveSettings()
    }

    func canShowAutomaticVocabulary(now: Date = Date()) -> Bool {
        resetVocabularyScheduleIfNeeded(now: now)
        return VocabularyDisplayScheduler.canShowAutomaticVocabulary(vocabularyScheduleSnapshot, now: now, unlimited: settings.dailyVocabularyUnlimited)
    }

    func recordAutomaticVocabularyShown(now: Date = Date()) {
        objectWillChange.send()
        settings.lastAutomaticVocabularyDate = now
        vocabularyScheduleSnapshot = VocabularyDisplayScheduler.recordAutomaticVocabularyShown(vocabularyScheduleSnapshot, now: now, unlimited: settings.dailyVocabularyUnlimited)
        saveSettings()
    }

    func vocabularyScheduleStatusText(now: Date = Date()) -> String {
        let snapshot = VocabularyDisplayScheduler.resetIfNeeded(vocabularyScheduleSnapshot, now: now)
        let window = VocabularyDisplayScheduler.studyWindowDates(snapshot, now: now)
        let phase: String
        if now < window.start {
            phase = "未开始"
        } else if now >= window.end {
            phase = "已结束"
        } else {
            phase = "进行中"
        }
        let total = settings.dailyVocabularyUnlimited ? "不限量" : String(snapshot.dailyLimit)
        return "学习时段 \(VocabularyDisplayScheduler.timeText(for: snapshot.studyStartMinute))-\(VocabularyDisplayScheduler.timeText(for: snapshot.studyEndMinute)) · \(phase) · 今日 \(snapshot.shownCount)/\(total)"
    }

    func toggleDictionary(_ dictionaryID: String, isEnabled: Bool) {
        objectWillChange.send()
        if isEnabled {
            settings.enabledDictionaryIDs.insert(dictionaryID)
        } else {
            settings.enabledDictionaryIDs.remove(dictionaryID)
        }
        saveSettings()
    }

    func enabledEntries() -> [ScopedDictionaryEntry] {
        VocabularyPicker.scopedEntries(
            from: dictionaries + personalVocabulary.packs,
            enabledIDs: settings.enabledDictionaryIDs
        )
    }

    func dictionarySummaries() -> [DictionarySummary] {
        Self.dictionarySummaries(packs: dictionaries, stats: vocabularyProgress.stats, enabledIDs: settings.enabledDictionaryIDs)
    }

    static func dictionarySummaries(packs: [DictionaryPack], stats: [String: WordStat], enabledIDs: Set<String>, isCancelled: () -> Bool = { false }) -> [DictionarySummary] {
        packs.compactMap { pack in
            guard !isCancelled() else { return nil }
            var learned = 0
            var unknown = 0
            var skipped = 0
            for entry in pack.entries {
                guard !isCancelled() else { return nil }
                let key = WordStat.key(dictionaryID: pack.id, term: entry.term)
                guard let stat = stats[key] else { continue }
                if stat.learned { learned += 1 }
                if stat.unknownCount > 0 && !stat.learned { unknown += 1 }
                if stat.skippedCount > 0 { skipped += 1 }
            }
            return DictionarySummary(
                pack: pack,
                isEnabled: enabledIDs.contains(pack.id),
                isBuiltIn: BuiltInDictionaries.packs.contains { $0.id == pack.id },
                category: dictionaryCategory(for: pack),
                learnedCount: learned,
                unknownCount: unknown,
                skippedCount: skipped
            )
        }
    }

    func isBuiltInDictionary(_ dictionaryID: String) -> Bool {
        BuiltInDictionaries.packs.contains { $0.id == dictionaryID }
    }

    private func dictionaryFileURL(_ dictionaryID: String) -> URL {
        dictionariesURL.appendingPathComponent("\(dictionaryID).json")
    }

    private static func dictionaryCategory(from description: String?) -> String? {
        guard let description else { return nil }
        let prefix = "分类："
        guard description.hasPrefix(prefix) else { return nil }
        let rest = String(description.dropFirst(prefix.count))
        let value = rest.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func dictionaryCategory(for pack: DictionaryPack) -> String? {
        if let explicitCategory = dictionaryCategory(from: pack.description) {
            return explicitCategory
        }
        let lowerName = pack.name.lowercased()
        let tags = Set(pack.entries.flatMap(\.tags).map { $0.lowercased() })
        if tags.contains("japanese")
            || lowerName.contains("japanese")
            || pack.entries.contains(where: { containsJapanese($0.term) || containsJapanese($0.reading ?? "") }) {
            return "日语"
        }
        if tags.contains("ielts") || lowerName.contains("ielts") {
            return "IELTS"
        }
        return nil
    }

    private static func containsJapanese(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            let code = Int(scalar.value)
            return (0x3040...0x30ff).contains(code)
        }
    }

    private func dictionaryDescription(category: String?, existingDescription: String?) -> String? {
        let cleanCategory = nilIfBlank(category)
        let existing = nilIfBlank(existingDescription?.components(separatedBy: "\n").filter { !$0.hasPrefix("分类：") }.joined(separator: "\n"))
        guard let cleanCategory else { return existing }
        return ["分类：\(cleanCategory)", existing].compactMap { $0 }.joined(separator: "\n")
    }

    private func nilIfBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadUserDictionaries() throws {
        let removed = try removedSampleDictionaryIDs()
        dictionaries = BuiltInDictionaries.packs.filter { !removed.contains($0.id) }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dictionariesURL,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension.lowercased() == "json" {
            let pack = JSONFileStore.load(DictionaryPack.self, from: file, fallback: DictionaryPack(id: "", name: "", entries: []))
            if !pack.id.isEmpty, !pack.entries.isEmpty {
                dictionaries.removeAll { $0.id == pack.id }
                dictionaries.append(pack)
            }
        }
    }

    private func installBundledDictionariesIfNeeded() throws {
        let files = bundledDictionaryFiles()
        guard !files.isEmpty else {
            return
        }

        let receiptURL = rootURL.appendingPathComponent("bundled-dictionaries.json")
        let receiptData = try readLocalFileIfPresent(at: receiptURL)
        var installed = Set(try receiptData.map { try JSONFileStore.decoder.decode([String].self, from: $0) } ?? [])
        let previousInstalled = installed
        var updatedSettings = settings
        var writes: [(url: URL, data: Data)] = []
        for file in files {
            let pack = JSONFileStore.load(
                DictionaryPack.self,
                from: file,
                fallback: DictionaryPack(id: "", name: "", entries: [])
            )
            guard !pack.id.isEmpty, !pack.entries.isEmpty else { continue }
            // A missing previously installed pack is an intentional deletion, not a new install.
            guard !installed.contains(pack.id) else { continue }

            let destination = dictionariesURL.appendingPathComponent("\(pack.id).json")
            if try readLocalFileIfPresent(at: destination) == nil {
                writes.append((destination, try Data(contentsOf: file)))
                updatedSettings.enabledDictionaryIDs.insert(pack.id)
            }
            // Existing files migrate into the receipt without overwriting content or enablement.
            installed.insert(pack.id)
        }
        if updatedSettings.enabledDictionaryIDs != settings.enabledDictionaryIDs {
            writes.append((settingsURL, try JSONFileStore.encoder.encode(updatedSettings)))
        }
        if installed != previousInstalled || receiptData == nil {
            writes.append((receiptURL, try JSONFileStore.encoder.encode(installed.sorted())))
        }
        try commitLocalFiles(writes)
        settings = updatedSettings
    }

    private func bundledDictionaryFiles() -> [URL] {
        var seen = Set<String>()
        var files: [URL] = []
        for directory in AppResourceLocator.resourceBundleDirectories() {
            let possibleDirectories = [
                directory.appendingPathComponent("Dictionaries", isDirectory: true),
                directory
            ]
            for possibleDirectory in possibleDirectories {
                guard let contents = try? FileManager.default.contentsOfDirectory(
                    at: possibleDirectory,
                    includingPropertiesForKeys: nil
                ) else {
                    continue
                }
                for file in contents where file.pathExtension.lowercased() == "json" && !seen.contains(file.path) {
                    seen.insert(file.path)
                    files.append(file)
                }
            }
        }
        return files
    }

    private func resolveDownloadURL(for reference: CodexPetRemoteReference) async throws -> URL {
        if let directZipURL = reference.directZipURL {
            return directZipURL
        }

        if let metadataURL = reference.metadataURL {
            do {
                let (data, response) = try await URLSession.shared.data(from: metadataURL)
                try validateHTTPResponse(response, url: metadataURL)
                if let downloadURL = CodexPetPackageInstaller.downloadURL(fromMetadata: data, baseURL: metadataURL) {
                    return downloadURL
                }
            } catch {
                if reference.fallbackZipURL == nil {
                    throw error
                }
            }
        }

        if let fallbackZipURL = reference.fallbackZipURL {
            return fallbackZipURL
        }

        throw NSError(domain: "CodexDesktopPet", code: 31, userInfo: [NSLocalizedDescriptionKey: "没有找到可下载的宠物包。"])
    }

    private func downloadFile(from url: URL) async throws -> URL {
        let (fileURL, response) = try await URLSession.shared.download(from: url)
        try validateHTTPResponse(response, url: url)
        return fileURL
    }

    private func validateHTTPResponse(_ response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "CodexDesktopPet",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "下载失败：\(url.host ?? url.absoluteString) 返回 HTTP \(http.statusCode)。"]
            )
        }
    }

    private func isPackageInstalled(sourceID: String) -> Bool {
        pets.contains {
            $0.id == sourceID || $0.packageSourceID == sourceID || $0.packageDirectoryName == sourceID
        }
    }

    private func uniquePackageDirectoryName(preferred: String) -> String {
        let candidate = CodexPetPackageInstaller.sanitizedIdentifier(preferred)
        if !FileManager.default.fileExists(atPath: packagesURL.appendingPathComponent(candidate).path),
           !pets.contains(where: { $0.id == candidate }) {
            return candidate
        }

        var suffix = 2
        while true {
            let next = "\(candidate)-\(suffix)"
            if !FileManager.default.fileExists(atPath: packagesURL.appendingPathComponent(next).path),
               !pets.contains(where: { $0.id == next }) {
                return next
            }
            suffix += 1
        }
    }

    private func installPackageForCodex(from sourceURL: URL, packageID: String, overwrite: Bool) throws {
        let codexPetsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
        try FileManager.default.createDirectory(at: codexPetsURL, withIntermediateDirectories: true)

        let destination = codexPetsURL.appendingPathComponent(packageID, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard overwrite else { return }
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    private func videoPreviewImage(url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func extractZipContents(_ zipURL: URL, to destinationDirectory: URL) throws {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destinationDirectory.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "CodexDesktopPet",
                code: 41,
                userInfo: [NSLocalizedDescriptionKey: "解压 zip 失败，请确认文件没有损坏。"]
            )
        }
    }

    private func mediaFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            let pathPieces = file.pathComponents
            if pathPieces.contains("__MACOSX") || file.lastPathComponent.hasPrefix("._") {
                continue
            }
            guard Self.petMediaExtensions.contains(file.pathExtension.lowercased()) else {
                continue
            }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(file)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static let petMediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "webp", "gif", "apng", "mp4", "mov", "m4v"
    ]
    private static let staticImageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
}
