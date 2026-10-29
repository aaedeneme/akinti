import SwiftUI
import CTorrent

struct ContentView: View {
    @EnvironmentObject var store: TorrentStore
    @State private var confirmRemove = false

    var body: some View {
        NavigationSplitView {
            List(Filter.allCases, selection: $store.filter) { f in
                Label(f.rawValue, systemImage: f.icon)
                    .badge(store.count(f))
                    .tag(f)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            VSplitView {
                table
                    .frame(minHeight: 200)
                DetailPanel()
                    .frame(minHeight: 120, idealHeight: 180)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        }
        .searchable(text: $store.search, placement: .toolbar, prompt: "Torrent ara")
        .toolbar { toolbar }
        .sheet(isPresented: $store.showAdd) { AddSheet().environmentObject(store) }
        .alert("Hata", isPresented: Binding(get: { store.errorMessage != nil },
                                            set: { if !$0 { store.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("Seçili torrentler silinsin mi?", isPresented: $confirmRemove) {
            Button("Yalnızca listeden kaldır") { store.remove(store.selection, deleteFiles: false) }
            Button("Dosyalarla birlikte sil", role: .destructive) { store.remove(store.selection, deleteFiles: true) }
            Button("Vazgeç", role: .cancel) {}
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { store.handle(url: $0) }
            return !urls.isEmpty
        }
        .dropDestination(for: String.self) { strings, _ in
            let magnets = strings.filter { $0.hasPrefix("magnet:") }
            magnets.forEach { store.beginAdd(magnet: $0) }
            return !magnets.isEmpty
        }
    }

    private var table: some View {
        Table(store.filtered, selection: $store.selection, sortOrder: $store.sortOrder) {
            TableColumn("Ad", value: \.name) { t in
                Text(t.name).lineLimit(1).help(t.name)
            }.width(min: 180, ideal: 300)
            TableColumn("Boyut", value: \.size) { Text(formatBytes($0.size)) }.width(70)
            TableColumn("İlerleme", value: \.progress) { t in
                HStack(spacing: 6) {
                    ProgressView(value: t.progress).tint(t.state == .seeding ? .green : .accentColor)
                    Text("\(Int(t.progress * 100))%").monospacedDigit().font(.caption)
                        .frame(width: 36, alignment: .trailing)
                }
            }.width(min: 120, ideal: 150)
            TableColumn("Durum", value: \.statusRank) { Text($0.statusText).lineLimit(1) }.width(min: 90, ideal: 110)
            TableColumn("Eş", value: \.peers) { Text("\($0.peers) (\($0.seeds))").monospacedDigit() }.width(60)
            TableColumn("↓ Hız", value: \.downRate) { Text(formatRate($0.downRate)).monospacedDigit() }.width(80)
            TableColumn("↑ Hız", value: \.upRate) { Text(formatRate($0.upRate)).monospacedDigit() }.width(80)
            TableColumn("Kalan") { Text($0.etaText).monospacedDigit() }.width(70)
            TableColumn("Oran", value: \.ratio) { Text(String(format: "%.2f", $0.ratio)).monospacedDigit() }.width(50)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button("Sürdür") { store.resume(ids) }
                Button("Zorla Başlat") { store.forceStart(ids) }
                Button("Durdur") { store.pause(ids) }
                Button("Yeniden Kontrol Et") { store.recheck(ids) }
                Divider()
                Button("Klasörde Göster") { store.reveal(ids) }
                Button("Klasöre Taşı…") { store.moveSelected(ids) }
                Divider()
                Button("Sil…", role: .destructive) { store.selection = ids; confirmRemove = true }
            }
        }
        .onDeleteCommand { if !store.selection.isEmpty { confirmRemove = true } }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label(formatRate(store.totalDown), systemImage: "arrow.down")
            Label(formatRate(store.totalUp), systemImage: "arrow.up")
            Spacer()
            Text("\(store.torrents.count) torrent")
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("Durum", selection: $store.filter) {
                ForEach(Filter.allCases) { f in Text("\(f.rawValue) (\(store.count(f)))").tag(f) }
            }
            .pickerStyle(.menu)
            .help("Duruma göre listele")
        }
        ToolbarItemGroup {
            Button { store.pickTorrentFiles() } label: { Label("Dosya Ekle", systemImage: "doc.badge.plus") }
            Button { store.beginAdd() } label: { Label("Magnet Ekle", systemImage: "link.badge.plus") }
        }
        ToolbarItemGroup {
            Button { store.resume(store.selection) } label: { Label("Sürdür", systemImage: "play.fill") }
                .disabled(store.selection.isEmpty)
            Button { store.forceStart(store.selection) } label: { Label("Zorla Başlat", systemImage: "forward.fill") }
                .disabled(store.selection.isEmpty)
            Button { store.pause(store.selection) } label: { Label("Durdur", systemImage: "stop.fill") }
                .disabled(store.selection.isEmpty)
            Button { store.reveal(store.selection) } label: { Label("Klasörde Göster", systemImage: "folder") }
                .disabled(store.selection.isEmpty)
            Button { store.moveSelected(store.selection) } label: { Label("Klasöre Taşı", systemImage: "folder.badge.gearshape") }
                .disabled(store.selection.isEmpty)
            Button { confirmRemove = true } label: { Label("Sil", systemImage: "trash") }
                .disabled(store.selection.isEmpty)
        }
    }
}

struct DetailPanel: View {
    @EnvironmentObject var store: TorrentStore

    var body: some View {
        if store.selection.count == 1, let t = store.torrents.first(where: { $0.id == store.selection.first }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 24) {
                    info("İndirilen", formatBytes(t.downloaded))
                    info("Yüklenen", formatBytes(t.uploaded))
                    info("Oran", String(format: "%.2f", t.ratio))
                    info("Kayıt yeri", t.savePath)
                    info("Hash", String(t.id.prefix(12)) + "…")
                }
                .padding(10)
                Divider()
                Table(store.files) {
                    TableColumn("Dosya") { Text($0.path).lineLimit(1) }
                    TableColumn("Boyut") { Text(formatBytes($0.size)) }.width(80)
                    TableColumn("İlerleme") { f in
                        ProgressView(value: f.progress)
                    }.width(120)
                }
            }
        } else {
            Text("Ayrıntı için bir torrent seçin")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).lineLimit(1).textSelection(.enabled)
        }
    }
}

struct AddSheet: View {
    @EnvironmentObject var store: TorrentStore

    private var empty: Bool {
        store.pendingFiles.isEmpty && store.pendingMagnets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Torrent Ekle").font(.headline)

            Text("Magnet bağlantıları (her satıra bir tane)").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $store.pendingMagnets)
                .font(.system(.body, design: .monospaced))
                .frame(height: 90)
                .border(Color.secondary.opacity(0.3))

            if !store.pendingFiles.isEmpty {
                Text("Torrent dosyaları").font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach(store.pendingFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                            Text(url.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button { store.pendingFiles.removeAll { $0 == url } } label: {
                                Image(systemName: "xmark.circle.fill")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 90)
            }
            Button("Dosya Seç…") { store.pickTorrentFiles() }

            Divider()
            HStack {
                Text("Kayıt yeri:")
                Text(store.pendingPath).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                Button("Seç…") {
                    if let p = store.chooseFolder(start: store.pendingPath) { store.pendingPath = p }
                }
            }

            HStack {
                Spacer()
                Button("Vazgeç") { store.cancelAdd() }.keyboardShortcut(.cancelAction)
                Button("Ekle") { store.commitAdd() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(empty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if store.pendingMagnets.isEmpty, store.pendingFiles.isEmpty,
               let s = NSPasteboard.general.string(forType: .string), s.hasPrefix("magnet:") {
                store.pendingMagnets = s
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: TorrentStore

    var body: some View {
        Form {
            HStack {
                Text("İndirme klasörü")
                Text(store.downloadDir).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                Button("Seç…") {
                    let p = NSOpenPanel()
                    p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK, let u = p.url { store.downloadDir = u.path }
                }
            }
            Stepper("İndirme sınırı: \(store.downLimitKB == 0 ? "sınırsız" : "\(store.downLimitKB) KB/s")",
                    value: $store.downLimitKB, in: 0...1_000_000, step: 100)
            Stepper("Yükleme sınırı: \(store.upLimitKB == 0 ? "sınırsız" : "\(store.upLimitKB) KB/s")",
                    value: $store.upLimitKB, in: 0...1_000_000, step: 50)
        }
        .padding(20)
        .frame(width: 480)
    }
}
