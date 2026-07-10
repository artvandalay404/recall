import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import RecallCore

/// Field-based note editor (PRD §7.5): one rich-text field per note-type
/// field, a keyboard-accessory toolbar for bold/italic/underline/cloze/image/
/// audio acting on whichever field last had focus, and a per-field HTML
/// source toggle. Always presented modally with its own nav stack, so both
/// "add a note to this deck" and "edit this note from Browse" can reuse it
/// as a sheet.
struct NoteEditorView: View {
    private let deckID: String?
    private let editingNote: Note?
    private let editingNoteType: NoteType?

    @Environment(\.appDatabase) private var database
    @Environment(\.mediaStore) private var mediaStore
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: NoteEditorViewModel?
    @State private var sourceModeFieldIndices: Set<Int> = []
    @State private var fieldControllers: [Int: FieldEditorController] = [:]
    @State private var focusedFieldIndex = 0
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isPresentingAudioImporter = false
    @State private var isPresentingDeleteConfirm = false

    /// Create mode: a new note in `deckID`.
    init(deckID: String) {
        self.deckID = deckID
        self.editingNote = nil
        self.editingNoteType = nil
    }

    /// Edit mode: an existing note.
    init(note: Note, noteType: NoteType) {
        self.deckID = nil
        self.editingNote = note
        self.editingNoteType = noteType
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    form(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(editingNote == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            // A WKWebView's contenteditable focus doesn't register with
            // SwiftUI's focus system, so `.toolbar(placement: .keyboard)`
            // never attaches here — this bar is pinned above the safe area
            // instead, always visible while the editor is open rather than
            // tied to keyboard visibility.
            .safeAreaInset(edge: .bottom) {
                formattingToolbar
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
            .confirmationDialog("Delete this note?", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteNote() }
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel?.errorMessage ?? "")
            }
            .onAppear { setUpIfNeeded() }
            .onChange(of: photoPickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await insertPickedImage(newValue) }
            }
            .fileImporter(isPresented: $isPresentingAudioImporter, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    insertPickedAudio(url)
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel?.errorMessage != nil }, set: { if !$0 { viewModel?.errorMessage = nil } })
    }

    private func setUpIfNeeded() {
        guard viewModel == nil else { return }
        if let editingNote, let editingNoteType {
            viewModel = NoteEditorViewModel(database: database, note: editingNote, noteType: editingNoteType)
        } else if let deckID {
            viewModel = NoteEditorViewModel(database: database, deckID: deckID)
        }
    }

    @ViewBuilder
    private func form(_ viewModel: NoteEditorViewModel) -> some View {
        Form {
            if !viewModel.isEditing, viewModel.availableNoteTypes.count > 1 {
                Picker("Type", selection: Binding(
                    get: { viewModel.selectedNoteType.id },
                    set: { id in
                        guard let noteType = viewModel.availableNoteTypes.first(where: { $0.id == id }) else { return }
                        viewModel.selectNoteType(noteType)
                        fieldControllers = [:]
                        focusedFieldIndex = 0
                    }
                )) {
                    ForEach(viewModel.availableNoteTypes) { noteType in
                        Text(noteType.name).tag(noteType.id)
                    }
                }
            }

            ForEach(viewModel.fields.indices, id: \.self) { index in
                Section(viewModel.fields[index].name) {
                    fieldEditor(viewModel, index: index)
                }
            }

            Section("Tags") {
                TextField("space-separated tags", text: Binding(
                    get: { viewModel.tagsText },
                    set: { viewModel.tagsText = $0 }
                ))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }

            if viewModel.isEditing {
                Section {
                    Button("Delete Note", role: .destructive) {
                        isPresentingDeleteConfirm = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldEditor(_ viewModel: NoteEditorViewModel, index: Int) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if sourceModeFieldIndices.contains(index) {
                TextEditor(text: Binding(
                    get: { viewModel.fieldValues[index] },
                    set: { viewModel.fieldValues[index] = $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
            } else {
                FieldEditorWebView(
                    initialHTML: viewModel.fieldValues[index],
                    mediaBaseURL: mediaStore.directory,
                    onChange: { viewModel.fieldValues[index] = $0 },
                    onFocus: { focusedFieldIndex = index },
                    onControllerReady: { fieldControllers[index] = $0 }
                )
                .frame(minHeight: 90)
            }

            Button(sourceModeFieldIndices.contains(index) ? "Rich Text" : "HTML Source") {
                if sourceModeFieldIndices.contains(index) {
                    sourceModeFieldIndices.remove(index)
                } else {
                    sourceModeFieldIndices.insert(index)
                }
            }
            .font(.caption)
        }
    }

    private var formattingToolbar: some View {
        HStack(spacing: 20) {
            Button { fieldControllers[focusedFieldIndex]?.toggleBold() } label: {
                Image(systemName: "bold")
            }
            Button { fieldControllers[focusedFieldIndex]?.toggleItalic() } label: {
                Image(systemName: "italic")
            }
            Button { fieldControllers[focusedFieldIndex]?.toggleUnderline() } label: {
                Image(systemName: "underline")
            }
            if let viewModel, viewModel.clozeFieldIndex == focusedFieldIndex {
                Button { insertCloze() } label: {
                    Image(systemName: "c.square")
                }
            }
            Spacer()
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Image(systemName: "photo")
            }
            Button { isPresentingAudioImporter = true } label: {
                Image(systemName: "waveform")
            }
        }
        .disabled(sourceModeFieldIndices.contains(focusedFieldIndex))
    }

    private func insertCloze() {
        guard let viewModel else { return }
        let number = viewModel.nextClozeNumber()
        fieldControllers[focusedFieldIndex]?.wrapSelection(prefix: "{{c\(number)::", suffix: "}}")
    }

    private func insertPickedImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        guard let filename = try? mediaStore.importData(data, extension: ext) else { return }
        fieldControllers[focusedFieldIndex]?.insertHTML("<img src=\"\(filename)\">")
        photoPickerItem = nil
    }

    private func insertPickedAudio(_ url: URL) {
        guard let filename = try? mediaStore.importFile(from: url) else { return }
        fieldControllers[focusedFieldIndex]?.insertHTML("<audio controls src=\"\(filename)\"></audio>")
    }

    private func save() {
        guard let viewModel, viewModel.save() else { return }
        dismiss()
    }

    private func deleteNote() {
        guard let viewModel, viewModel.delete() else { return }
        dismiss()
    }
}
