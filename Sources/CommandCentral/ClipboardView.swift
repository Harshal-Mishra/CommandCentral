import SwiftUI

struct ClipboardView: View {
    @EnvironmentObject private var clipboard: ClipboardStore

    var body: some View {
        Card(title: "Clipboard History", systemImage: "doc.on.clipboard",
             trailing: "\(clipboard.items.count) items") {
            VStack(spacing: 10) {
                HStack {
                    Toggle("Capture new copies", isOn: $clipboard.capturing)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                    Button("Clear History") { clipboard.clear() }
                        .controlSize(.small)
                }
                Divider()
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(clipboard.items) { item in
                            Button {
                                clipboard.copy(item)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.text)
                                            .font(.system(size: 12))
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                        Text(item.date, format: .dateTime.day().month().hour().minute())
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.4),
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .help("Click to copy again")
                        }
                        if clipboard.items.isEmpty {
                            Text("Copy any text anywhere on your Mac and it shows up here.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Text("History is stored only on this Mac. Anything you copy — including sensitive text — is captured while the toggle is on.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}
