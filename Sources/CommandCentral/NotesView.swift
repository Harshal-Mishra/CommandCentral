import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var notes: NoteStore
    @State private var selection: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Card(title: "Notes", systemImage: "note.text",
                 trailing: "\(notes.notes.count)") {
                VStack(spacing: 8) {
                    Button {
                        selection = notes.add()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(notes.notes) { note in
                                Button {
                                    selection = note.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(note.title)
                                            .font(.system(size: 12,
                                                          weight: selection == note.id ? .semibold : .regular))
                                            .lineLimit(1)
                                        Text(note.updatedAt, format: .dateTime.day().month().hour().minute())
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(selection == note.id
                                                ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                                : AnyShapeStyle(.quaternary.opacity(0.4)),
                                                in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        notes.delete(note.id)
                                        if selection == note.id { selection = notes.notes.first?.id }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 250)
            .frame(maxHeight: .infinity)

            Card(title: selectedTitle, systemImage: "square.and.pencil") {
                if selection != nil {
                    TextEditor(text: editorBinding)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Select a note or create a new one")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selection == nil { selection = notes.notes.first?.id }
        }
    }

    private var selectedTitle: String {
        guard let selection,
              let note = notes.notes.first(where: { $0.id == selection }) else { return "Editor" }
        return note.title
    }

    private var editorBinding: Binding<String> {
        Binding(
            get: { notes.text(of: selection) },
            set: { notes.update(selection, text: $0) }
        )
    }
}
