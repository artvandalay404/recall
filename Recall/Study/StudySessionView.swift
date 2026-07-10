import SwiftUI
import RecallCore

struct StudySessionView: View {
    let deckID: String
    let deckName: String

    @Environment(\.appDatabase) private var database
    @Environment(\.mediaStore) private var mediaStore
    @State private var viewModel: StudyViewModel?
    @State private var loadError: String?
    @State private var isPresentingNoteEditor = false

    var body: some View {
        Group {
            if let viewModel {
                sessionBody(viewModel)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn't Start Session",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(deckName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingNoteEditor = true
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNoteEditor, onDismiss: loadSession) {
            NoteEditorView(deckID: deckID)
        }
        .onAppear {
            guard viewModel == nil else { return }
            loadSession()
        }
    }

    private func loadSession() {
        do {
            viewModel = try StudyViewModel(database: database, deckID: deckID)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func sessionBody(_ viewModel: StudyViewModel) -> some View {
        if viewModel.isComplete {
            completeState
        } else {
            VStack(spacing: 0) {
                header(viewModel)

                CardWebView(
                    html: viewModel.phase == .question ? viewModel.questionHTML : viewModel.answerHTML,
                    baseURL: mediaStore.directory
                )
                    .overlay {
                        if viewModel.phase == .question {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { viewModel.reveal() }
                        }
                    }

                controls(viewModel)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func header(_ viewModel: StudyViewModel) -> some View {
        HStack {
            Button {
                viewModel.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)

            Spacer()

            Text("\(viewModel.remainingCount) remaining")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func controls(_ viewModel: StudyViewModel) -> some View {
        if viewModel.phase == .question {
            Button {
                viewModel.reveal()
            } label: {
                Text("Show Answer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        } else {
            HStack(spacing: 8) {
                gradeButton(.again, label: "Again", color: .red, viewModel: viewModel)
                gradeButton(.hard, label: "Hard", color: .orange, viewModel: viewModel)
                gradeButton(.good, label: "Good", color: .green, viewModel: viewModel)
                gradeButton(.easy, label: "Easy", color: .blue, viewModel: viewModel)
            }
            .padding()
        }
    }

    private func gradeButton(_ rating: Rating, label: String, color: Color, viewModel: StudyViewModel) -> some View {
        Button {
            viewModel.grade(rating)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.bold())
                if let interval = viewModel.intervalPreviews[rating] {
                    Text(interval)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private var completeState: some View {
        ContentUnavailableView {
            Label("All Done", systemImage: "checkmark.circle")
        } description: {
            Text("No more cards due in \(deckName) right now.")
        }
    }
}
