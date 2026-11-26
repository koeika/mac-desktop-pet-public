import Foundation
import CodexPetCore

enum CompanionConfigurationRegression {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor static func run() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("companion-configuration-\(UUID().uuidString)", isDirectory: true)
        var pendingRecovery: URL?
        defer {
            if let pendingRecovery {
                do {
                    try fm.moveItem(at: pendingRecovery, to: root.appendingPathComponent("recovered-fixture.json"))
                } catch {
                    print("companion-configuration: fixture recovery failed at \(pendingRecovery.path): \(error)")
                }
            }
            do { try fm.removeItem(at: root) }
            catch { print("companion-configuration: fixture cleanup failed at \(root.path): \(error)") }
        }
        let store = try AppDataStore(root: root)
        let fixtureDate = Date(timeIntervalSince1970: 1_800_000_000)
        store.pets = AppDataStore.companionIDs.map { id in
            PetAsset(id: "fixture-\(id)", name: id, kind: .codexPackage, packageSourceID: id, createdAt: fixtureDate, isEnabled: false)
        }
        let custom = PetAsset(id: "custom", name: "Custom", kind: .codexPackage, createdAt: fixtureDate)
        store.pets.append(custom)
        try JSONFileStore.save(store.pets, to: store.petsManifestURL)
        try expect(store.selectedCompanionStyle == nil && store.companionPreviewPets.isEmpty, "disabled companions must not imply color selection")
        for theme in AppVisualTheme.allCases {
            try store.selectVisualTheme(theme)
            for style in CompanionStyle.allCases {
                try store.selectCompanionStyle(style)
                let expected = AppDataStore.companionIDs.filter(style.matches)
                try expect(store.selectedCompanionStyle == style, "selected style must follow actual enabled pets in \(theme)")
                try expect(store.companionPreviewPets.map(\.id) == expected.map { "fixture-\($0)" }, "preview must use selected asset IDs, including imported aliases")
                try expect(store.pets.first { $0.id == custom.id } == custom, "style selection must preserve custom pets")
                let persisted = try JSONFileStore.decoder.decode([PetAsset].self, from: Data(contentsOf: store.petsManifestURL))
                try expect(persisted == store.pets, "style selection must persist exactly what preview reflects")
            }
        }
        for index in store.pets.indices { store.pets[index].isEnabled = false }
        store.pets[0].isEnabled = true
        store.pets[2].isEnabled = true
        try expect(store.selectedCompanionStyle == nil && store.companionPreviewPets.count == 2, "mixed enabled styles must not show a false selected style")
        store.pets[0].weight = 0
        try expect(store.selectedCompanionStyle == .ink, "preview must exclude zero-weight desktop assets")

        let pack = DictionaryPack(id: "regression-recoverable", name: "Generated Trash fixture",
            entries: [DictionaryEntry(term: "recover", meaning: "restore")])
        let file = store.dictionariesURL.appendingPathComponent("\(pack.id).json")
        try JSONFileStore.save(pack, to: file)
        store.dictionaries.append(pack)
        store.settings.enabledDictionaryIDs.insert(pack.id)
        let key = WordStat.key(dictionaryID: pack.id, term: "recover")
        store.vocabularyProgress.stats[key] = WordStat(learned: true, seenCount: 3, lastAction: .known)
        try JSONFileStore.save(store.settings, to: store.settingsURL)
        try JSONFileStore.save(store.vocabularyProgress, to: store.progressURL)
        let fileBefore = try Data(contentsOf: file)
        let progressBefore = try Data(contentsOf: store.progressURL)
        let notebookBefore = try JSONFileStore.encoder.encode(store.personalVocabulary)

        let dictionariesBefore = try JSONFileStore.encoder.encode(store.dictionaries)
        let settingsBefore = try JSONFileStore.encoder.encode(store.settings)
        let revisionBefore = store.libraryRevision
        let hiddenFile = root.appendingPathComponent("missing-file-backup.json")
        try fm.moveItem(at: file, to: hiddenFile)
        try expectFailure("missing dictionary file must surface error") { _ = try store.deleteDictionary(pack.id) }
        try fm.moveItem(at: hiddenFile, to: file)
        let dictionariesAfterFailure = try JSONFileStore.encoder.encode(store.dictionaries)
        let settingsAfterFailure = try JSONFileStore.encoder.encode(store.settings)
        try expect(dictionariesBefore == dictionariesAfterFailure && settingsBefore == settingsAfterFailure,
            "failed deletion must preserve in-memory dictionaries and enabled state")
        try expect(store.libraryRevision == revisionBefore, "failed deletion must not publish a library mutation")

        // Force a later staged write to fail and prove earlier writes are restored.
        store.settings.syncFilePath = root.appendingPathComponent("absent-parent/sync.json").path
        try JSONFileStore.save(store.settings, to: store.settingsURL)
        let rollbackSettings = try Data(contentsOf: store.settingsURL)
        let rollbackProgress = store.vocabularyProgress
        try expectFailure("sync write failure must prevent Trash and roll back settings/progress") {
            _ = try store.deleteDictionary(pack.id, deleteLearningProgress: true)
        }
        let settingsAfterRollback = try Data(contentsOf: store.settingsURL)
        let progressAfterRollback = try Data(contentsOf: store.progressURL)
        let fileAfterRollback = try Data(contentsOf: file)
        try expect(settingsAfterRollback == rollbackSettings && progressAfterRollback == progressBefore,
            "filesystem failure must restore persisted settings and learning records")
        try expect(fileAfterRollback == fileBefore && store.vocabularyProgress == rollbackProgress,
            "filesystem failure must preserve dictionary file and in-memory learning records")
        try expect(store.settings.enabledDictionaryIDs.contains(pack.id) && store.dictionaries.contains { $0.id == pack.id },
            "filesystem failure must retain enabled dictionary")
        store.settings.syncFilePath = nil
        try JSONFileStore.save(store.settings, to: store.settingsURL)

        // Exercise native Trash itself. Unsupported temp-root volumes must fail, never permanently delete.
        guard let trashURL = try store.deleteDictionary(pack.id) else {
            throw Failure(description: "companion-configuration: native Trash did not return a recoverable fixture URL")
        }
        pendingRecovery = trashURL
        try expect(!fm.fileExists(atPath: file.path) && fm.fileExists(atPath: trashURL.path), "dictionary must move to recoverable system Trash")
        let trashedData = try Data(contentsOf: trashURL)
        try expect(trashedData == fileBefore, "Trash must preserve the exact dictionary bytes")
        try expect(!store.dictionaries.contains { $0.id == pack.id } && !store.settings.enabledDictionaryIDs.contains(pack.id),
            "successful Trash must update memory and enabled state")
        let progressAfterTrash = try Data(contentsOf: store.progressURL)
        let notebookAfter = try JSONFileStore.encoder.encode(store.personalVocabulary)
        try expect(progressAfterTrash == progressBefore && notebookAfter == notebookBefore && store.vocabularyProgress.stats[key]?.learned == true,
            "default deletion must preserve learning and personal vocabulary")
        let reloaded = try AppDataStore(root: root)
        try expect(!reloaded.dictionaries.contains { $0.id == pack.id } && !reloaded.settings.enabledDictionaryIDs.contains(pack.id),
            "deletion must survive reload")
        try expect(reloaded.vocabularyProgress.stats[key]?.learned == true, "learning must survive reload")

        try fm.moveItem(at: trashURL, to: file)
        pendingRecovery = nil
        let restored = try AppDataStore(root: root)
        try expect(restored.dictionaries.contains { $0.id == pack.id }, "putting the Trash item back must restore the dictionary on reload")
        let reimported = try restored.importDictionary(from: file)
        try expect(reimported.contains { $0.id == pack.id } && restored.settings.enabledDictionaryIDs.contains(pack.id),
            "reimport must re-enable the restored dictionary")
        try expect(restored.vocabularyProgress.stats[key]?.learned == true, "restored/reimported dictionary must reuse retained study history")
        try syncMergeRegression(root: root.appendingPathComponent("sync-merge"))
        try bundledDictionaryRegression(root: root.appendingPathComponent("bundled-dictionary"))
        try petRestoreRegression(root: root.appendingPathComponent("pet-restore"))
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_SETTINGS_FIXTURE_DIR"] {
            let file = try writeDictionaryFixture(to: URL(fileURLWithPath: directory, isDirectory: true))
            print("companion-configuration: importable sample pack at \(file.path)")
        }
        print("companion-configuration-regression: preview selection, native Trash/recovery, merged sync preservation, bundled dictionary receipt, pet restore rollback and retained learning passed")
    }

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: "companion-configuration: \(message)") }
    }

    @MainActor private static func expectFailure(_ message: String, operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw Failure(description: "companion-configuration: expected failure: \(message)")
    }

    @MainActor private static func withTrashedDictionary(_ store: AppDataStore, id: String,
        deleteLearningProgress: Bool = false, verify: (URL) throws -> Void) throws {
        let file = store.dictionariesURL.appendingPathComponent("\(id).json")
        guard let trash = try store.deleteDictionary(id, deleteLearningProgress: deleteLearningProgress) else {
            throw Failure(description: "companion-configuration: native Trash returned no recovery URL")
        }
        do { try verify(trash) }
        catch {
            do { try FileManager.default.moveItem(at: trash, to: file) }
            catch let recoveryError {
                throw Failure(description: "companion-configuration: \(error); fixture recovery at \(trash.path) failed: \(recoveryError)")
            }
            throw error
        }
        try FileManager.default.moveItem(at: trash, to: file)
    }

    @MainActor private static func syncMergeRegression(root: URL) throws {
        let store = try AppDataStore(root: root)
        let pack = DictionaryPack(id: "sync-delete-fixture", name: "Sync fixture",
            entries: [DictionaryEntry(term: "target", meaning: "target")])
        let file = store.dictionariesURL.appendingPathComponent("\(pack.id).json")
        try JSONFileStore.save(pack, to: file)
        store.dictionaries.append(pack)
        store.settings.enabledDictionaryIDs.insert(pack.id)
        let sync = root.appendingPathComponent("latest-sync.json")
        store.settings.syncFilePath = sync.path
        try JSONFileStore.save(store.settings, to: store.settingsURL)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let target = WordStat.key(dictionaryID: pack.id, term: "target")
        let memory = VocabularyProgress(stats: [target: WordStat(updatedAt: date), "memory::only": WordStat(seenCount: 1, updatedAt: date)])
        let disk = VocabularyProgress(stats: [target: WordStat(seenCount: 2, updatedAt: date),
            "local::only": WordStat(learned: true, updatedAt: date), "other::shared": WordStat(seenCount: 3, updatedAt: date)])
        let remote = VocabularyProgress(stats: [target: WordStat(learned: true, updatedAt: date),
            "remote::only": WordStat(learned: true, updatedAt: date),
            "other::shared": WordStat(learned: true, seenCount: 5, lastAction: .known, updatedAt: date.addingTimeInterval(60))])
        store.vocabularyProgress = memory
        try JSONFileStore.save(disk, to: store.progressURL)
        try JSONFileStore.save(remote, to: sync)
        let settingsBefore = try Data(contentsOf: store.settingsURL)
        let fileBefore = try Data(contentsOf: file)
        let diskBefore = try Data(contentsOf: store.progressURL)
        let remoteBefore = try Data(contentsOf: sync)
        let malformed = Data("not-json".utf8)
        for failingURL in [store.progressURL, sync] {
            let original = try Data(contentsOf: failingURL)
            try malformed.write(to: failingURL, options: .atomic)
            try expectFailure("malformed learning file must not be treated as empty") {
                _ = try store.deleteDictionary(pack.id, deleteLearningProgress: true)
            }
            let untouched = try Data(contentsOf: failingURL)
            let settingsAfter = try Data(contentsOf: store.settingsURL)
            let fileAfter = try Data(contentsOf: file)
            try expect(untouched == malformed && settingsAfter == settingsBefore && fileAfter == fileBefore,
                "read/decode failure must precede any writes or Trash")
            try expect(store.vocabularyProgress == memory && store.settings.enabledDictionaryIDs.contains(pack.id),
                "read failure must preserve memory")
            try original.write(to: failingURL, options: .atomic)
        }
        // A directory at the sync URL produces a genuine filesystem read error, not just invalid JSON.
        try FileManager.default.moveItem(at: sync, to: root.appendingPathComponent("sync-backup.json"))
        try FileManager.default.createDirectory(at: sync, withIntermediateDirectories: false)
        try expectFailure("unreadable sync path must surface a filesystem error") {
            _ = try store.deleteDictionary(pack.id, deleteLearningProgress: true)
        }
        try FileManager.default.removeItem(at: sync)
        try FileManager.default.moveItem(at: root.appendingPathComponent("sync-backup.json"), to: sync)
        let diskAfterErrors = try Data(contentsOf: store.progressURL)
        let remoteAfterErrors = try Data(contentsOf: sync)
        try expect(diskAfterErrors == diskBefore && remoteAfterErrors == remoteBefore, "negative cases must preserve both learning files")
        let merged = LearningSync.merge(local: LearningSync.merge(local: memory.stats, remote: disk.stats), remote: remote.stats)
        let expected = VocabularyProgress(stats: merged.filter { !$0.key.hasPrefix("\(pack.id)::") })
        try withTrashedDictionary(store, id: pack.id, deleteLearningProgress: true) { trash in
            let persisted = try JSONFileStore.decoder.decode(VocabularyProgress.self, from: Data(contentsOf: store.progressURL))
            let synced = try JSONFileStore.decoder.decode(VocabularyProgress.self, from: Data(contentsOf: sync))
            try expect(persisted == expected && synced == expected && store.vocabularyProgress == expected,
                "explicit progress deletion must merge latest memory/disk/sync, then remove only the target namespace")
            try expect(expected.stats.count == 4 && expected.stats["other::shared"]?.learned == true,
                "remote-only, disk-only, memory-only and newer shared study records must survive")
            let trashed = try Data(contentsOf: trash)
            try expect(trashed == fileBefore, "explicit study deletion must still use recoverable native Trash")
        }
    }

    @MainActor private static func bundledDictionaryRegression(root: URL) throws {
        let store = try AppDataStore(root: root)
        let receipt = root.appendingPathComponent("bundled-dictionaries.json")
        let installed = try JSONFileStore.decoder.decode([String].self, from: Data(contentsOf: receipt))
        guard var pack = store.dictionaries.first(where: { installed.contains($0.id) && ($0.name.contains("雅思") || $0.id.lowercased().contains("ielts")) }) else {
            throw Failure(description: "companion-configuration: bundled IELTS resource required; no skipped fixture")
        }
        let file = store.dictionariesURL.appendingPathComponent("\(pack.id).json")
        pack.name += " - user copy"
        try JSONFileStore.save(pack, to: file)
        store.settings.enabledDictionaryIDs.remove(pack.id)
        try JSONFileStore.save(store.settings, to: store.settingsURL)
        let key = WordStat.key(dictionaryID: pack.id, term: pack.entries[0].term)
        store.vocabularyProgress.stats[key] = WordStat(learned: true, seenCount: 5, lastAction: .known)
        try JSONFileStore.save(store.vocabularyProgress, to: store.progressURL)
        let fileBefore = try Data(contentsOf: file)
        let progressBefore = try Data(contentsOf: store.progressURL)
        // Simulate an upgrade from a version without the dictionary installation receipt.
        try FileManager.default.removeItem(at: receipt)
        let migrated = try AppDataStore(root: root)
        let registered = try JSONFileStore.decoder.decode([String].self, from: Data(contentsOf: receipt))
        let fileAfterMigration = try Data(contentsOf: file)
        try expect(registered.contains(pack.id) && fileAfterMigration == fileBefore && !migrated.settings.enabledDictionaryIDs.contains(pack.id),
            "existing bundled dictionary must register without overwrite or re-enablement")
        let validReceipt = try Data(contentsOf: receipt)
        try Data("broken receipt".utf8).write(to: receipt, options: .atomic)
        try expectFailure("corrupt receipt must not silently reinstall dictionaries") { _ = try AppDataStore(root: root) }
        try validReceipt.write(to: receipt, options: .atomic)
        try withTrashedDictionary(migrated, id: pack.id) { trash in
            let firstReload = try AppDataStore(root: root)
            let secondReload = try AppDataStore(root: root)
            try expect(!firstReload.dictionaries.contains { $0.id == pack.id } && !secondReload.dictionaries.contains { $0.id == pack.id },
                "trashed bundled IELTS must remain absent across repeated startup")
            try expect(!FileManager.default.fileExists(atPath: file.path) && !secondReload.settings.enabledDictionaryIDs.contains(pack.id),
                "startup must not recreate or re-enable previously installed IELTS")
            let retained = try Data(contentsOf: store.progressURL)
            let trashed = try Data(contentsOf: trash)
            try expect(retained == progressBefore && secondReload.vocabularyProgress.stats[key]?.learned == true && trashed == fileBefore,
                "IELTS Trash must preserve learning and recoverable dictionary bytes")
        }
        let restored = try AppDataStore(root: root)
        try expect(restored.dictionaries.contains { $0.id == pack.id } && !restored.settings.enabledDictionaryIDs.contains(pack.id),
            "put-back must restore the dictionary without overriding disabled preference")
        _ = try restored.importDictionary(from: file)
        try expect(restored.settings.enabledDictionaryIDs.contains(pack.id) && restored.vocabularyProgress.stats[key]?.learned == true,
            "explicit reimport must enable restored IELTS and reuse retained study records")
    }

    @MainActor private static func petRestoreRegression(root: URL) throws {
        let fm = FileManager.default
        let store = try AppDataStore(root: root)
        let targets = ["whisky-color", "cling-color"]
        let receipt = root.appendingPathComponent("bundled-pets.json")
        let receiptBefore = try Data(contentsOf: receipt)
        for id in targets {
            guard let pet = store.pets.first(where: { AppDataStore.companionID(for: $0) == id }),
                  let directory = store.packageURL(for: pet) else {
                throw Failure(description: "companion-configuration: bundled \(id) required for restoration regression")
            }
            try fm.moveItem(at: directory, to: root.appendingPathComponent("backup-\(id)"))
        }
        store.pets.removeAll { pet in AppDataStore.companionID(for: pet).map { targets.contains($0) } ?? false }
        try JSONFileStore.save(store.pets, to: store.petsManifestURL)
        let petsBefore = store.pets
        let manifestBefore = try Data(contentsOf: store.petsManifestURL)
        let directoriesBefore = try fm.contentsOfDirectory(atPath: store.packagesURL.path).sorted()
        let existing = store.packagesURL.appendingPathComponent("cling-color")
        try fm.createDirectory(at: existing, withIntermediateDirectories: false)
        let marker = existing.appendingPathComponent("user-owned.txt")
        let markerData = Data("Do not touch existing assets".utf8)
        try markerData.write(to: marker)
        try expectFailure("second restore conflicts with an existing asset after first copy") { try store.selectCompanionStyle(.color) }
        let markerAfter = try Data(contentsOf: marker)
        let manifestAfterConflict = try Data(contentsOf: store.petsManifestURL)
        let receiptAfterConflict = try Data(contentsOf: receipt)
        try expect(markerAfter == markerData && !fm.fileExists(atPath: store.packagesURL.appendingPathComponent("whisky-color").path),
            "failed restoration must remove its first copied directory but preserve existing assets")
        try expect(store.pets == petsBefore && manifestAfterConflict == manifestBefore && receiptAfterConflict == receiptBefore,
            "conflicting restore must not publish pets, manifest or receipt changes")
        try fm.moveItem(at: existing, to: root.appendingPathComponent("saved-user-owned-directory"))

        let savedManifest = root.appendingPathComponent("pets-manifest-backup.json")
        try fm.moveItem(at: store.petsManifestURL, to: savedManifest)
        try fm.createDirectory(at: store.petsManifestURL, withIntermediateDirectories: false)
        try expectFailure("manifest filesystem failure after asset copies must roll back restoration") { try store.selectCompanionStyle(.color) }
        let directoriesAfterFailure = try fm.contentsOfDirectory(atPath: store.packagesURL.path).sorted()
        let receiptAfterFailure = try Data(contentsOf: receipt)
        try expect(store.pets == petsBefore && directoriesAfterFailure == directoriesBefore && receiptAfterFailure == receiptBefore,
            "failed manifest commit must remove only newly copied assets and staging, retaining memory and receipt")
        try fm.removeItem(at: store.petsManifestURL)
        try fm.moveItem(at: savedManifest, to: store.petsManifestURL)

        try Data("corrupt receipt".utf8).write(to: receipt, options: .atomic)
        try expectFailure("corrupt pet receipt must throw before restoring anything") { try store.selectCompanionStyle(.color) }
        let directoriesAfterCorruption = try fm.contentsOfDirectory(atPath: store.packagesURL.path).sorted()
        try expect(store.pets == petsBefore && directoriesAfterCorruption == directoriesBefore, "corrupt receipt cannot trigger reinstall or mutate memory")
        try receiptBefore.write(to: receipt, options: .atomic)
        try store.selectCompanionStyle(.color)
        try expect(store.selectedCompanionStyle == .color && store.companionPreviewPets.count == 2,
            "successful retry must restore and enable selected companions")
        let reloaded = try AppDataStore(root: root)
        let reloadedPets = try JSONFileStore.encoder.encode(reloaded.pets)
        let selectedPets = try JSONFileStore.encoder.encode(store.pets)
        try expect(reloaded.selectedCompanionStyle == .color && reloadedPets == selectedPets,
            "restored pet manifest and receipt must survive reload")
        for id in targets {
            let original = try Data(contentsOf: root.appendingPathComponent("backup-\(id)/pet.json"))
            let restored = try Data(contentsOf: store.packagesURL.appendingPathComponent("\(id)/pet.json"))
            try expect(original == restored, "restoration must copy original bundled assets intact")
        }
    }

    @discardableResult
    static func writeDictionaryFixture(to directory: URL) throws -> URL {
        let file = directory.appendingPathComponent("recoverable-dictionary-sample.json")
        guard !FileManager.default.fileExists(atPath: file.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let pack = DictionaryPack(id: "recoverable-dictionary-sample", name: "可恢复词典测试样本",
            entries: [DictionaryEntry(term: "recover", meaning: "恢复；找回"),
                      DictionaryEntry(term: "preserve", meaning: "保留；保护")])
        try JSONFileStore.save(pack, to: file)
        return file
    }
}
