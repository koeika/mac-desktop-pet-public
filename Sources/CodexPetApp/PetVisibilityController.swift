import AppKit

extension Notification.Name {
    static let petVisibilityPreferenceDidChange = Notification.Name("petVisibilityPreferenceDidChange")
}

final class PetVisibilityController {
    private weak var window: NSWindow?
    private weak var contentView: PetContentView?
    private let store: AppDataStore
    private var preferenceObserver: NSObjectProtocol?
    private(set) var isManuallyHidden = false

    init(window: NSWindow, contentView: PetContentView, store: AppDataStore) {
        self.window = window
        self.contentView = contentView
        self.store = store
        contentView.onPresentationChange = { [weak self] in self?.synchronize() }
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .petVisibilityPreferenceDidChange, object: store, queue: .main
        ) { [weak self] _ in self?.synchronize() }
        synchronize()
    }

    deinit {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }

    func show() {
        isManuallyHidden = false
        synchronize()
    }

    func hide() {
        isManuallyHidden = true
        synchronize()
    }

    private func synchronize() {
        guard let window, let contentView else { return }
        let onlyWithWords = store.settings.petOnlyWithVocabulary
        contentView.setPetVisible(!onlyWithWords || contentView.hasVisibleVocabularyCard)
        let visible = !isManuallyHidden && (!onlyWithWords || contentView.isBubbleVisible)
        if visible && !window.isVisible { window.orderFrontRegardless() }
        if !visible && window.isVisible { window.orderOut(nil) }
    }
}
