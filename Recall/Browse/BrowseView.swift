import SwiftUI
import RecallCore

/// Light card search/browse (PRD §7.6): a searchable list across all notes,
/// tap to edit, swipe to delete. Deliberately not the full advanced query
/// browser the PRD defers past v1 — just enough to find and fix a card.
struct BrowseView: View {
    @Environment(\.appDatabase) private var database
    @State private var viewModel: BrowseViewModel?
    @State private var editingTarget: EditingTarget?

    private struct EditingTarget: Identifiable {
        let note: Note
        let noteType: NoteType
        var id: String { note.id }
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Browse")
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = BrowseViewModel(database: database)
        }
        .sheet(item: $editingTarget, onDismiss: { viewModel?.refresh() }) { target in
            NoteEditorView(note: target.note, noteType: target.noteType)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel?.errorMessage != nil },
            set: { if !$0 { viewModel?.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(_ viewModel: BrowseViewModel) -> some View {
        List {
            ForEach(viewModel.summaries) { summary in
                Button {
                    openEditor(summary)
                } label: {
                    row(summary)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { viewModel.delete(summary) }
                }
            }
        }
        .searchable(text: Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0 }
        ), prompt: "Search notes and tags")
        .overlay {
            if viewModel.summaries.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    private func row(_ summary: AppDatabase.NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(HTMLPlainText.preview(of: summary.note.fieldValues.first(where: { !$0.isEmpty }) ?? ""))
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text(summary.noteTypeName)
                Text("·")
                Text(summary.deckName)
                if summary.cardCount > 1 {
                    Text("· \(summary.cardCount) cards")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func openEditor(_ summary: AppDatabase.NoteSummary) {
        guard let noteType = try? database.noteType(id: summary.note.noteTypeID) else { return }
        editingTarget = EditingTarget(note: summary.note, noteType: noteType)
    }
}
