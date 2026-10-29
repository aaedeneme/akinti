import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CTorrent

struct TorrentItem: Identifiable, Hashable {
    let id: String
    var name: String
    var state: TEState
    var progress: Double
    var size: Int64
    var downloaded: Int64
    var uploaded: Int64
    var downRate: Int
    var upRate: Int
    var peers: Int
    var seeds: Int
    var savePath: String
    var error: String

    init(_ t: TETorrent) {
        id = t.infoHash; name = t.name; state = t.state; progress = t.progress
        size = t.totalSize; downloaded = t.downloaded; uploaded = t.uploaded
        downRate = Int(t.downloadRate); upRate = Int(t.uploadRate)
        peers = Int(t.peers); seeds = Int(t.seeds); savePath = t.savePath; error = t.errorMessage
    }

    var statusRank: Int { Int(state.rawValue) }

    var statusText: String {
        switch state {
        case .checking: return "Kontrol ediliyor"
        case .metadata: return "Üstveri alınıyor"
        case .downloading: return "İndiriliyor"
        case .seeding: return "Tohumlanıyor"
        case .paused: return "Duraklatıldı"
        case .error: return error.isEmpty ? "Hata" : "Hata: \(error)"
        @unknown default: return "—"
        }
    }

    var ratio: Double { downloaded > 0 ? Double(uploaded) / Double(downloaded) : (uploaded > 0 ? 99 : 0) }

    var etaText: String {
        guard state == .downloading, downRate > 0 else { return "∞" }
        let remaining = Double(size) * (1 - progress)
        let s = Int(remaining / Double(downRate))
        if s >= 86400 { return "\(s / 86400)g \((s % 86400) / 3600)sa" }
        if s >= 3600 { return "\(s / 3600)sa \((s % 3600) / 60)dk" }
        if s >= 60 { return "\(s / 60)dk \(s % 60)sn" }
        return "\(s)sn"
    }
}

struct TorrentFile: Identifiable {
    let id: Int
    let path: String
    let size: Int64
    let progress: Double
}

enum Filter: String, CaseIterable, Identifiable {
    case all = "Tümü", downloading = "İndiriliyor", seeding = "Tohumlanıyor"
    case paused = "Duraklatıldı", active = "Aktif"
    case completed = "Tamamlandı", error = "Hatalı"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .completed: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .seeding: return "arrow.up.circle"
        case .paused: return "pause.circle"
        case .active: return "bolt.circle"
        }
    }
    func matches(_ t: TorrentItem) -> Bool {
        switch self {
        case .all: return true
        case .completed: return t.progress >= 1
        case .error: return t.state == .error
        case .downloading: return t.state == .downloading || t.state == .metadata
        case .seeding: return t.state == .seeding
        case .paused: return t.state == .paused
        case .active: return t.downRate > 0 || t.upRate > 0
        }
    }
}

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}
func formatRate(_ n: Int) -> String { n > 0 ? formatBytes(Int64(n)) + "/s" : "—" }

@MainActor
final class TorrentStore: ObservableObject {
    @Published var torrents: [TorrentItem] = []
    @Published var files: [TorrentFile] = []
    @Published var selection = Set<String>() { didSet { refreshFiles() } }
    @Published var filter: Filter = .all
    @Published var search = ""
    @Published var errorMessage: String?

    @Published var downloadDir: String = UserDefaults.standard.string(forKey: "downloadDir")
        ?? (NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? NSHomeDirectory()) {
        didSet { UserDefaults.standard.set(downloadDir, forKey: "downloadDir") }
    }
    @Published var downLimitKB: Int = UserDefaults.standard.integer(forKey: "downLimitKB") {
        didSet { UserDefaults.standard.set(downLimitKB, forKey: "downLimitKB"); applyLimits() }
    }
    @Published var upLimitKB: Int = UserDefaults.standard.integer(forKey: "upLimitKB") {
        didSet { UserDefaults.standard.set(upLimitKB, forKey: "upLimitKB"); applyLimits() }
    }

    private let engine: TorrentEngine
    private var timer: Timer?
    private var tick = 0

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Akinti/state").path
        engine = TorrentEngine(stateDirectory: support)
        applyLimits()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    @Published var sortOrder = [KeyPathComparator(\TorrentItem.name)]

    var filtered: [TorrentItem] {
        torrents
            .filter { filter.matches($0) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted(using: sortOrder)
    }
    var totalDown: Int { torrents.reduce(0) { $0 + $1.downRate } }
    var totalUp: Int { torrents.reduce(0) { $0 + $1.upRate } }
    func count(_ f: Filter) -> Int { torrents.filter(f.matches).count }

    private func poll() {
        torrents = engine.snapshot().map(TorrentItem.init)
        refreshFiles()
        tick += 1
        if tick % 60 == 0 { DispatchQueue.global().async { [engine] in engine.saveState() } }
    }

    private func refreshFiles() {
        guard selection.count == 1, let id = selection.first else { files = []; return }
        files = engine.files(for: id).enumerated().map {
            TorrentFile(id: $0.offset, path: $0.element.path, size: $0.element.size, progress: $0.element.progress)
        }
    }

    private func applyLimits() {
        engine.setDownloadLimit(Int32(downLimitKB * 1024), uploadLimit: Int32(upLimitKB * 1024))
    }

    // MARK: Ekleme (kayıt yeri seçmeli)

    @Published var showAdd = false
    @Published var pendingFiles: [URL] = []
    @Published var pendingMagnets = ""
    @Published var pendingPath = ""

    func beginAdd(files: [URL] = [], magnet: String? = nil) {
        pendingFiles.append(contentsOf: files.filter { !pendingFiles.contains($0) })
        if let magnet, !magnet.isEmpty {
            pendingMagnets += (pendingMagnets.isEmpty ? "" : "\n") + magnet
        }
        if !showAdd { pendingPath = downloadDir }
        showAdd = true
    }

    func pickTorrentFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { beginAdd(files: panel.urls) }
    }

    func chooseFolder(start: String) -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: start)
        return p.runModal() == .OK ? p.url?.path : nil
    }

    func commitAdd() {
        let path = pendingPath.isEmpty ? downloadDir : pendingPath
        for line in pendingMagnets.split(whereSeparator: \.isNewline) {
            let uri = line.trimmingCharacters(in: .whitespaces)
            if uri.isEmpty { continue }
            do { try engine.addMagnet(uri, savePath: path) } catch { errorMessage = error.localizedDescription }
        }
        for url in pendingFiles {
            do { try engine.addTorrentFile(url.path, savePath: path) } catch { errorMessage = error.localizedDescription }
        }
        cancelAdd()
    }

    func cancelAdd() {
        pendingFiles = []; pendingMagnets = ""; showAdd = false
    }

    func handle(url: URL) {
        if url.isFileURL { beginAdd(files: [url]) } else { beginAdd(magnet: url.absoluteString) }
    }

    // MARK: Taşıma

    func moveSelected(_ ids: Set<String>) {
        guard !ids.isEmpty, let dest = chooseFolder(start: downloadDir) else { return }
        ids.forEach { engine.move($0, toPath: dest) }
    }

    func forceStart(_ ids: Set<String>) { ids.forEach { engine.forceStart($0) } }

    func pause(_ ids: Set<String>) { ids.forEach { engine.pause($0) } }
    func resume(_ ids: Set<String>) { ids.forEach { engine.resume($0) } }
    func recheck(_ ids: Set<String>) { ids.forEach { engine.recheck($0) } }
    func pauseAll() { torrents.forEach { engine.pause($0.id) } }
    func resumeAll() { torrents.forEach { engine.resume($0.id) } }

    func remove(_ ids: Set<String>, deleteFiles: Bool) {
        ids.forEach { engine.remove($0, deleteFiles: deleteFiles) }
        selection.subtract(ids)
    }

    func reveal(_ ids: Set<String>) {
        let urls = torrents.filter { ids.contains($0.id) }
            .map { URL(fileURLWithPath: $0.savePath).appendingPathComponent($0.name) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func saveState() { engine.saveState() }
}
