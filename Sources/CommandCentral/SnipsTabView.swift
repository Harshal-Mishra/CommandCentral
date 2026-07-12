import AppKit
import ImageIO
import SwiftUI
import Vision

struct SnipsTabView: View {
    @EnvironmentObject private var snips: SnipStore
    @EnvironmentObject private var state: AppState
    @State private var editing: SnipItem?

    var body: some View {
        VStack(spacing: 12) {
            header
            if snips.snips.isEmpty {
                emptyState
            } else {
                gallery
            }
        }
        .sheet(item: $editing) { item in
            SnipEditorView(item: item)
        }
        .onAppear {
            snips.reload()
            openPendingIfNeeded()
        }
        .onReceive(snips.$pendingEdit) { _ in
            openPendingIfNeeded()
        }
    }

    private func openPendingIfNeeded() {
        guard let url = snips.pendingEdit else { return }
        // Snips list may refresh in the same tick; defer one runloop turn.
        DispatchQueue.main.async {
            guard snips.pendingEdit == url else { return }
            snips.pendingEdit = nil
            editing = snips.snips.first { $0.url == url }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("New snip:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            // Icon-only: five labelled buttons would outgrow narrow windows.
            ForEach(SnipStore.Mode.allCases) { mode in
                Button {
                    state.startSnip(mode)
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 12))
                }
                .help("\(mode.title) — \(mode.subtitle)")
            }
            .controlSize(.small)
            Text("⇧⌘S anywhere · hover a snip for quick actions · drag one into any app")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Text("\(snips.snips.count) snip\(snips.snips.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button {
                NSWorkspace.shared.open(Storage.directory.appendingPathComponent("Snips"))
            } label: {
                Image(systemName: "folder")
            }
            .controlSize(.small)
            .help("Open the Snips folder")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "scissors")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("No snips yet")
                .font(.system(size: 14, weight: .medium))
            Text("Press ⇧⌘S anywhere, type “ss” in the palette, or use the buttons above.\nDraw on the selection, ⏎ copies & saves — everything lands here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(snips.byDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(group.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("· \(group.items.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(group.items) { item in
                                SnipCell(item: item) {
                                    editing = item
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Cell

private struct SnipCell: View {
    let item: SnipItem
    let onEdit: () -> Void
    @EnvironmentObject private var snips: SnipStore
    @State private var thumbnail: NSImage?
    @State private var dimensions: String?
    @State private var hovering = false
    @State private var flash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            thumbnailView
            captionRow
        }
        .contextMenu {
            Button("Edit") { onEdit() }
            Button("Copy Image") { copyImage() }
            Button("Copy Text (OCR)") { copyText() }
            Divider()
            Button("Save a Copy to Desktop") { saveToDesktop() }
            Button("Reveal in Finder") { snips.revealInFinder(item) }
            Divider()
            Button("Move to Trash", role: .destructive) { snips.delete(item) }
        }
        .task(id: item.id) {
            let loaded = await Self.load(item.url)
            thumbnail = loaded.image
            dimensions = loaded.dimensions
        }
    }

    private var thumbnailView: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.rowFill)
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .bottom) { hoverActions }
        .overlay { flashBadge }
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(hovering ? Theme.accent.opacity(0.75) : Theme.cardStroke,
                          lineWidth: hovering ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture(perform: onEdit)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
    }

    // Quick actions slide in over the bottom edge on hover.
    @ViewBuilder
    private var hoverActions: some View {
        if hovering {
            HStack(spacing: 3) {
                cellButton("doc.on.doc", help: "Copy image (also just drag the snip out)") { copyImage() }
                cellButton("text.viewfinder", help: "Copy text — OCR") { copyText() }
                cellButton("pencil", help: "Edit") { onEdit() }
                Spacer(minLength: 0)
                cellButton("trash", help: "Move to Trash") { snips.delete(item) }
            }
            .padding(5)
            .background(
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.72)],
                               startPoint: .top, endPoint: .bottom)
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var flashBadge: some View {
        if let flash {
            Text(flash)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.75), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private var captionRow: some View {
        HStack(spacing: 4) {
            Text(item.date, format: .dateTime.hour().minute())
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            if let dimensions {
                Text("· \(dimensions)")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
            Spacer()
        }
    }

    private func cellButton(_ icon: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 22)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: actions

    private func copyImage() {
        snips.copyToClipboard(item.url)
        show("Copied ✓")
    }

    private func copyText() {
        show("Reading…")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                DispatchQueue.main.async { show("Couldn't read file") }
                return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                if lines.isEmpty {
                    show("No text found")
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                    show("Text copied ✓")
                }
            }
        }
    }

    private func saveToDesktop() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let target = desktop.appendingPathComponent(item.url.lastPathComponent)
        try? FileManager.default.copyItem(at: item.url, to: target)
        show("On your Desktop ✓")
    }

    private func show(_ message: String) {
        withAnimation(.easeOut(duration: 0.15)) { flash = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeIn(duration: 0.2)) {
                if flash == message { flash = nil }
            }
        }
    }

    // MARK: loading

    /// Downsampled thumbnail + pixel dimensions, without decoding the full image.
    private static func load(_ url: URL) async -> (image: NSImage?, dimensions: String?) {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return (nil, nil)
            }
            var dimensions: String?
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = props[kCGImagePropertyPixelWidth] as? Int,
               let height = props[kCGImagePropertyPixelHeight] as? Int {
                dimensions = "\(width)×\(height)"
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return (nil, dimensions) }
            let image = NSImage(cgImage: cgImage,
                                size: NSSize(width: cgImage.width, height: cgImage.height))
            return (image, dimensions)
        }.value
    }
}
