import SwiftUI
import RecallCore

struct DeckListView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: DeckListViewModel?
    @State private var isPresentingNewDeckAlert = false
    @State private var newDeckName = ""
    @State private var deckPendingRename: Deck?
    @State private var renameText = ""

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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newDeckName = ""
                    isPresentingNewDeckAlert = true
                } label: {
                    Label("Add Deck", systemImage: "plus")
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
        .onAppear {
            let vm = viewModel ?? DeckListViewModel(database: database)
            viewModel = vm
            vm.refresh()
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { deckPendingRename != nil }, set: { if !$0 { deckPendingRename = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel?.errorMessage != nil }, set: { if !$0 { viewModel?.errorMessage = nil } })
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
