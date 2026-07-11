import SwiftUI
import UniformTypeIdentifiers
import RecallCore

struct DeckListView: View {
    @Environment(\.appDatabase) private var database
    @Environment(\.mediaStore) private var mediaStore
    @State private var viewModel: DeckListViewModel?
    @State private var isPresentingNewDeckAlert = false
    @State private var newDeckName = ""
    @State private var deckPendingRename: Deck?
    @State private var renameText = ""

    @State private var importViewModel: ImportViewModel?
    @State private var isPresentingImporter = false

    private static let apkgContentTypes = [
        UTType(filenameExtension: "apkg") ?? .data,
        UTType(filenameExtension: "colpkg") ?? .data,
    ]

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Decks")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    BrowseView()
                } label: {
                    Label("Browse", systemImage: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        newDeckName = ""
                        isPresentingNewDeckAlert = true
                    } label: {
                        Label("New Deck", systemImage: "plus")
                    }
                    Button {
                        isPresentingImporter = true
                    } label: {
                        Label("Import Deck…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .alert("New Deck", isPresented: $isPresentingNewDeckAlert) {
            TextField("Deck name", text: $newDeckName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { viewModel?.createDeck(named: newDeckName) }
        }
        .alert("Rename Deck", isPresented: renameBinding) {
            TextField("Deck name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let deck = deckPendingRename {
                    viewModel?.rename(deck, to: renameText)
                }
            }
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.errorMessage ?? "")
        }
        .fileImporter(isPresented: $isPresentingImporter, allowedContentTypes: Self.apkgContentTypes) { result in
            if case .success(let url) = result {
                importViewModel?.importDeck(from: url)
            }
        }
        .alert("Import Error", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importViewModel?.errorMessage ?? "")
        }
        .alert("Import Complete", isPresented: importSummaryBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            if let summary = importViewModel?.summary {
                Text("Imported \(summary.deckCount) deck(s), \(summary.noteCount) notes, \(summary.cardCount) cards, and \(summary.mediaFileCount) media files.")
            }
        }
        .overlay {
            if importViewModel?.isImporting == true {
                ProgressView("Importing…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            let vm = viewModel ?? DeckListViewModel(database: database)
            viewModel = vm
            vm.refresh()

            let importVM = importViewModel ?? ImportViewModel(database: database, mediaStore: mediaStore)
            importViewModel = importVM
        }
        .onChange(of: importViewModel?.summary) { _, newValue in
            guard newValue != nil else { return }
            viewModel?.refresh()
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { deckPendingRename != nil }, set: { if !$0 { deckPendingRename = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel?.errorMessage != nil }, set: { if !$0 { viewModel?.errorMessage = nil } })
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importViewModel?.errorMessage != nil }, set: { if !$0 { importViewModel?.errorMessage = nil } })
    }

    private var importSummaryBinding: Binding<Bool> {
        Binding(get: { importViewModel?.summary != nil }, set: { if !$0 { importViewModel?.summary = nil } })
    }

    @ViewBuilder
    private func content(_ viewModel: DeckListViewModel) -> some View {
        if viewModel.rows.isEmpty {
            emptyState
        } else {
            List {
                ForEach(viewModel.rows) { row in
                    NavigationLink(value: row.deck) {
                        DeckRowView(row: row)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { viewModel.delete(row.deck) }
                    }
                    .contextMenu {
                        Button("Rename") {
                            deckPendingRename = row.deck
                            renameText = row.deck.name
                        }
                    }
                }
            }
            .navigationDestination(for: Deck.self) { deck in
                StudySessionView(deckID: deck.id, deckName: deck.name)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Decks Yet", systemImage: "square.stack")
        } description: {
            Text("Tap + to create your first deck.")
        }
    }
}

private struct DeckRowView: View {
    let row: AppDatabase.DeckRow

    var body: some View {
        HStack {
            Text(row.deck.name)
            Spacer()
            if row.stats.newCount > 0 {
                countLabel("\(row.stats.newCount)", color: .blue)
            }
            if row.stats.dueCount > 0 {
                countLabel("\(row.stats.dueCount)", color: .green)
            }
            if row.stats.newCount == 0 && row.stats.dueCount == 0 {
                Text("Done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func countLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout.monospacedDigit().weight(.semibold))
            .foregroundStyle(color)
    }
}
