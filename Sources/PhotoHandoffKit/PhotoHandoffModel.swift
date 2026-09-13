import Foundation
import Combine

@MainActor public final class PhotoHandoffModel: ObservableObject {
    @Published public private(set) var photos: [HandoffPhoto] = []
    @Published public private(set) var isEnabled = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var status = "Photos stay on this device until you send them."
    @Published public var error: String?
    public var isConfigured: Bool { transport.configuration.isConfigured }

    private let store: PhotoHandoffStore
    private let platform: String
    private let transport: any PhotoHandoffTransport
    private var document = PhotoHandoffDocument()
    private var writesBlocked = false
    private var generation = UUID()
    private var operation: UUID?
    private var verifiedURLs: [UUID: PhotoFileStamp] = [:]

    public init(directory: URL, platform: String, allowsCloudAccess: Bool = true,
                transport: (any PhotoHandoffTransport)? = nil) {
        store = PhotoHandoffStore(directory: directory)
        self.platform = String(platform.prefix(80))
        self.transport = allowsCloudAccess ? (transport ?? CloudPhotoTransport())
            : CloudPhotoTransport(configuration: PhotoCloudConfiguration(isConfigured: false,
                explanation: "This test library is local only. iCloud is disabled."))
        do {
            document = try store.load()
            isEnabled = document.enabled && self.transport.configuration.isConfigured
            if !self.transport.configuration.isConfigured { status = self.transport.configuration.explanation }
            else if isEnabled { status = "Open Refresh to check iCloud. Local photos are available." }
            publish()
        } catch { writesBlocked = true; self.error = "The photo library could not be opened. Saving is paused to preserve its files. \(error.localizedDescription)" }
        self.transport.onAccountChange = { [weak self] in self?.accountChanged() }
    }

    public func enable() async {
        guard isConfigured else { error = transport.configuration.explanation; status = "iCloud is not configured in this build."; return }
        guard let task = begin() else { return }
        let token = generation
        defer { end(task) }
        do {
            let account = try await transport.identity()
            try check(token); try account.validate()
            var next = document; next.account = account; next.enabled = true
            if !next.accounts.contains(where: { $0.account == account }) { next.accounts.append(PhotoAccountState(account: account)) }
            try commit(next)
            isEnabled = true; error = nil; status = "iCloud connected. Choose Send photo for a local image."
            try await receive(account, token: token)
        } catch { handle(error, token: token) }
    }

    public func disable() {
        generation = UUID(); operation = nil; transport.cancel(); isBusy = false; isEnabled = false
        var next = document; next.enabled = false
        do { try commit(next) } catch { self.error = error.localizedDescription }
        status = "iCloud is off. Local photos and existing cloud copies are kept."
    }

    public func refresh() async {
        guard isEnabled else { return }
        guard let task = begin() else { return }
        let token = generation
        defer { end(task) }
        do {
            let account = try await verifiedAccount(token)
            try waitForRetry(account)
            // Durable removal intent takes precedence over any prior upload.
            for photo in document.photos.filter({ $0.account == account && $0.disposition == .deleting }).prefix(5) {
                try await remove(photo, account: account, token: token)
            }
            for photo in document.photos.filter({ $0.account == account && $0.disposition == .queued }).prefix(5) {
                try await upload(photo, account: account, token: token)
            }
            try await receive(account, token: token)
            error = nil
        } catch { handle(error, token: token) }
    }

    /// Saving a capture is local. The UI calls sendPhoto only after an explicit Send.
    @discardableResult public func addPhoto(data: Data, title: String) async -> UUID? {
        guard let task = begin() else { return nil }
        defer { end(task) }
        status = "Preparing a smaller JPEG. The original stays on this device."
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try PhotoMedia.prepare(data) }.value
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let remote = RemoteHandoffPhoto(id: UUID(), title: cleanTitle.isEmpty ? "Untitled photo" : String(cleanTitle.prefix(160)),
                created: Date(), sourceDevice: platform, digest: prepared.digest, byteCount: prepared.jpeg.count,
                width: prepared.width, height: prepared.height)
            try store.insert(remote, jpeg: prepared.jpeg, original: data)
            let photo = HandoffPhoto(id: remote.id, title: remote.title, created: remote.created,
                sourceDevice: remote.sourceDevice, account: nil, disposition: .local, digest: remote.digest,
                byteCount: remote.byteCount, width: remote.width, height: remote.height, hasOriginal: true)
            var next = document; next.photos.insert(photo, at: 0); try commit(next)
            cacheVerified(photo)
            error = nil; status = "Saved on this device. Send photo when you are ready."
            return photo.id
        } catch { self.error = error.localizedDescription; status = "The photo could not be saved."; return nil }
    }

    public func sendPhoto(_ id: UUID) async {
        guard isEnabled else { error = "Enable private iCloud photo handoff before sending. Your photo stays on this device."; return }
        guard let task = begin() else { return }
        let token = generation
        defer { end(task) }
        do {
            guard let account = document.account else { throw PhotoHandoffError.accountChanged }
            try account.validate()
            guard let index = document.photos.firstIndex(where: { $0.id == id }) else { throw PhotoHandoffError.invalid("This local photo is no longer available.") }
            let photo = document.photos[index]
            guard photo.account == nil || photo.account == account else { throw PhotoHandoffError.accountChanged }
            guard photo.disposition != .deleting && photo.disposition != .removed else {
                throw PhotoHandoffError.invalid("This photo was removed from iCloud. Add a new copy if you want to send it again.")
            }
            if photo.isUploaded { status = "This photo is already in iCloud."; return }
            _ = try store.fileURL(photo)
            var next = document
            next.photos[index].account = account; next.photos[index].disposition = .queued
            try commit(next) // The exact account and stable ID survive an interrupted upload.
            // Explicit Send can queue offline for the last verified owner. It
            // never binds to an unknown account or uploads before a fresh check.
            _ = try await verifiedAccount(token)
            try waitForRetry(account)
            try await upload(document.photos[index], account: account, token: token)
            error = nil
        } catch { handle(error, token: token) }
    }

    public func removeFromCloud(_ id: UUID) async {
        guard isEnabled else { error = "Reconnect the photo's iCloud account before removing its cloud copy."; return }
        guard let task = begin() else { return }
        let token = generation
        defer { end(task) }
        do {
            let account = try await verifiedAccount(token); try waitForRetry(account)
            guard let index = document.photos.firstIndex(where: { $0.id == id }), document.photos[index].account == account else {
                throw PhotoHandoffError.invalid("This photo does not belong to the connected iCloud account.")
            }
            var next = document; next.photos[index].disposition = .deleting; try commit(next)
            try await remove(document.photos[index], account: account, token: token)
            error = nil
        } catch { handle(error, token: token) }
    }

    public func removeLocalPhoto(_ id: UUID) throws {
        guard !isBusy else { throw PhotoHandoffError.invalid("Wait for the current photo operation before removing its local copy.") }
        guard let photo = document.photos.first(where: { $0.id == id }) else { return }
        var next = document
        if let account = photo.account, !next.suppressed.contains(where: { $0.account == account && $0.id == id }) {
            next.suppressed.append(PhotoReceipt(account: account, id: id, digest: photo.digest))
        }
        next.photos.removeAll { $0.id == id }
        try commit(next) // Receipt first: a restart must not immediately download the removed photo.
        verifiedURLs.removeValue(forKey: id)
        try store.removeFiles(id)
        status = "Local photo removed. Other saved copies and iCloud are unchanged."
    }

    public func fileURL(for photo: HandoffPhoto) -> URL? {
        guard document.photos.contains(where: { $0.id == photo.id && $0.digest == photo.digest }) else { return nil }
        do {
            let url = try store.candidateURL(photo)
            let stamp = try PhotoFileStamp(url: url, digest: photo.digest)
            if verifiedURLs[photo.id] != stamp { _ = try store.fileURL(photo); verifiedURLs[photo.id] = stamp }
            return url
        } catch { verifiedURLs.removeValue(forKey: photo.id); return nil }
    }
    private func cacheVerified(_ photo: HandoffPhoto) {
        if let url = try? store.candidateURL(photo), let stamp = try? PhotoFileStamp(url: url, digest: photo.digest) {
            verifiedURLs[photo.id] = stamp
        }
    }

    private func upload(_ photo: HandoffPhoto, account: PhotoAccount, token: UUID) async throws {
        try check(token, account: account)
        let url = try store.fileURL(photo)
        show(photo.id, "Uploading to iCloud")
        defer { publish() }
        try await transport.upload(photo.remote, fileURL: url, account: account)
        try check(token, account: account)
        var next = document
        guard let index = next.photos.firstIndex(where: { $0.id == photo.id && $0.account == account && $0.disposition == .queued }) else {
            throw PhotoHandoffError.cancelled
        }
        next.photos[index].disposition = .uploaded; try commit(next)
        status = "In iCloud. Your Mac downloads it when Workbench refreshes."
    }
    private func remove(_ photo: HandoffPhoto, account: PhotoAccount, token: UUID) async throws {
        try check(token, account: account)
        try await transport.remove(photo.id, account: account)
        try check(token, account: account)
        var next = document
        if let index = next.photos.firstIndex(where: { $0.id == photo.id && $0.account == account }) {
            next.photos[index].disposition = .removed
        }
        try commit(next); status = "Removed from iCloud. Local and composed copies are kept."
    }
    private func receive(_ account: PhotoAccount, token: UUID) async throws {
        try waitForRetry(account); try check(token, account: account)
        // A change token cannot replay a photo whose local JPEG was damaged
        // later. Check retained cloud copies and repair at most three per run.
        var repairs = 0
        for photo in document.photos.filter({ $0.account == account && ($0.disposition == .uploaded || $0.disposition == .downloaded) }) {
            try check(token, account: account)
            let stamp = try? PhotoFileStamp(url: store.candidateURL(photo), digest: photo.digest)
            if let stamp, verifiedURLs[photo.id] == stamp { continue }
            let savedStore = store
            let readable = await Task.detached(priority: .utility) { (try? savedStore.fileURL(photo)) != nil }.value
            try check(token, account: account)
            if readable { cacheVerified(photo); continue }
            guard repairs < 3 else {
                throw PhotoHandoffError.invalid("Three local photo copies were repaired. Refresh again to repair the remaining copies.")
            }
            try await repair(photo, account: account, token: token); repairs += 1
        }
        // Foreground work is deliberately bounded. Every page has its own
        // durable checkpoint, so a later activation can resume a large inbox.
        for _ in 0..<3 {
            if try await !receivePage(account, token: token) { return }
        }
        status = "More photos are available. Refresh again to continue."
    }
    private func repair(_ photo: HandoffPhoto, account: PhotoAccount, token: UUID) async throws {
        status = "Restoring the saved photo from iCloud…"
        let jpeg = try await transport.download(photo.remote, account: account)
        try check(token, account: account)
        try store.repair(photo, jpeg: jpeg)
        cacheVerified(photo)
    }
    private func receivePage(_ account: PhotoAccount, token: UUID) async throws -> Bool {
        try waitForRetry(account); try check(token, account: account)
        let position = document.accounts.first { $0.account == account }?.checkpoint
        status = "Checking iCloud photos…"
        let page: PhotoChangePage
        do { page = try await transport.changes(after: position, account: account) }
        catch PhotoHandoffError.expiredCheckpoint {
            try check(token, account: account)
            var next = document
            if let index = next.accounts.firstIndex(where: { $0.account == account }) { next.accounts[index].checkpoint = nil }
            try commit(next); throw PhotoHandoffError.expiredCheckpoint
        }
        try check(token, account: account)
        guard page.photos.count <= 20, page.deletedIDs.count <= 100,
              (page.checkpoint?.count ?? 0) <= 512_000,
              Set(page.photos.map(\.id)).count == page.photos.count else {
            throw PhotoHandoffError.invalid("iCloud returned a photo batch outside the supported limits. The previous refresh position is preserved.")
        }
        for remote in page.photos {
            _ = try remote.validated()
            if let receipt = document.suppressed.first(where: { $0.account == account && $0.id == remote.id }) {
                guard receipt.digest == remote.digest else { throw duplicateConflict() }; continue
            }
            if let existing = document.photos.first(where: { $0.id == remote.id }) {
                guard existing.account == account, existing.digest == remote.digest else { throw duplicateConflict() }
                // Keep deletion intent even if a stale server page still contains the photo.
                if existing.disposition == .deleting || existing.disposition == .removed { continue }
                if (try? store.fileURL(existing)) == nil { try await repair(existing, account: account, token: token) }
                else { cacheVerified(existing) }
                continue
            }
            let jpeg = try await transport.download(remote, account: account)
            try check(token, account: account)
            try store.insert(remote, jpeg: jpeg, original: nil)
            let photo = HandoffPhoto(id: remote.id, title: remote.title, created: remote.created,
                sourceDevice: remote.sourceDevice, account: account, disposition: .downloaded,
                digest: remote.digest, byteCount: remote.byteCount, width: remote.width, height: remote.height, hasOriginal: false)
            var next = document; next.photos.insert(photo, at: 0); try commit(next)
            cacheVerified(photo)
        }
        try check(token, account: account)
        var next = document
        for id in page.deletedIDs {
            if let index = next.photos.firstIndex(where: { $0.id == id && $0.account == account }) { next.photos[index].disposition = .removed }
        }
        if let index = next.accounts.firstIndex(where: { $0.account == account }) {
            next.accounts[index].checkpoint = page.checkpoint; next.accounts[index].retryNotBefore = nil
        }
        try commit(next) // No checkpoint advances before all images are validated and durable.
        status = page.hasMore ? "More photos are available. Refresh again to continue." : "iCloud checked. Downloaded photos are available on this device."
        return page.hasMore
    }
    private func duplicateConflict() -> PhotoHandoffError {
        .invalid("A photo ID already exists with different content or ownership. Nothing was overwritten; refresh after the source is repaired.")
    }
    private func verifiedAccount(_ token: UUID) async throws -> PhotoAccount {
        guard isEnabled, let expected = document.account else { throw PhotoHandoffError.accountChanged }
        try waitForRetry(expected)
        let actual = try await transport.identity()
        try check(token)
        guard actual == expected else { accountChanged(); throw PhotoHandoffError.accountChanged }
        return actual
    }
    private func check(_ token: UUID, account: PhotoAccount? = nil) throws {
        guard token == generation, !Task.isCancelled else { throw PhotoHandoffError.cancelled }
        if let account { guard isEnabled, document.account == account else { throw PhotoHandoffError.accountChanged } }
    }
    private func waitForRetry(_ account: PhotoAccount) throws {
        if let date = document.accounts.first(where: { $0.account == account })?.retryNotBefore, date > Date() {
            throw PhotoHandoffError.retryAfter(date, "iCloud asked Workbench to wait. Try again after \(date.formatted(date: .omitted, time: .shortened)).")
        }
    }
    private func accountChanged() {
        generation = UUID(); operation = nil; transport.cancel(); isBusy = false; isEnabled = false
        var next = document; next.enabled = false
        do { try commit(next) } catch { self.error = error.localizedDescription }
        status = PhotoHandoffError.accountChanged.localizedDescription
    }
    private func begin() -> UUID? {
        guard !writesBlocked else { error = "Saving is paused because the photo library could not be read."; return nil }
        guard !isBusy else { error = "Finish the current photo operation first."; return nil }
        let id = UUID(); operation = id; isBusy = true; return id
    }
    private func end(_ id: UUID) { if operation == id { operation = nil; isBusy = false } }
    private func commit(_ next: PhotoHandoffDocument) throws {
        guard !writesBlocked else { throw PhotoHandoffError.invalid("Saving is paused to preserve the unreadable photo library.") }
        try store.save(next); document = next; publish()
    }
    private func publish() {
        photos = document.photos.filter { $0.account == nil || $0.account == document.account }
            .sorted { $0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created > $1.created }
    }
    private func show(_ id: UUID, _ message: String) {
        publish()
        if let index = photos.firstIndex(where: { $0.id == id }) { photos[index].transientStatus = message }
        status = message
    }
    private func handle(_ failure: Error, token: UUID) {
        guard token == generation else { return }
        if case PhotoHandoffError.retryAfter(let date, _) = failure, let account = document.account {
            var next = document
            if let index = next.accounts.firstIndex(where: { $0.account == account }) { next.accounts[index].retryNotBefore = date }
            do { try commit(next) } catch { self.error = error.localizedDescription; return }
        }
        if case PhotoHandoffError.accountChanged = failure { accountChanged() }
        error = failure.localizedDescription; status = "Photo handoff needs attention. Local photos are kept."
        publish()
    }
}

private struct PhotoFileStamp: Equatable {
    let url: URL
    let digest: String
    let bytes: Int
    let modified: Date
    let fileNumber: UInt64
    init(url: URL, digest: String) throws {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              let bytes = values[.size] as? NSNumber, let modified = values[.modificationDate] as? Date,
              let number = values[.systemFileNumber] as? NSNumber else { throw PhotoHandoffError.invalid("This photo is unavailable.") }
        self.url = url; self.digest = digest; self.bytes = bytes.intValue
        self.modified = modified; fileNumber = number.uint64Value
    }
}
