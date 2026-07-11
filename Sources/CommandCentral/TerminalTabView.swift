import AppKit
import SwiftTerm
import SwiftUI

/// One shared shell session that survives tab switches.
final class TerminalSession: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    static let shared = TerminalSession()

    @Published private(set) var running = false

    lazy var terminalView: LocalProcessTerminalView = {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        view.processDelegate = self
        return view
    }()

    func start() {
        guard !running else { return }
        let environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        terminalView.startProcess(executable: "/bin/zsh",
                                  args: ["-l"],
                                  environment: environment,
                                  execName: nil)
        running = true
    }

    func sendCommand(_ command: String) {
        start()
        terminalView.send(txt: command + "\n")
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        running = false
    }
}

private struct TerminalRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let session = TerminalSession.shared
        session.start()
        return session.terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

struct TerminalTabView: View {
    @ObservedObject private var session = TerminalSession.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    session.sendCommand("claude")
                } label: {
                    Label("Launch Claude Code", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                Button("Clear") { session.sendCommand("clear") }
                if !session.running {
                    Button("Restart Shell") { session.start() }
                        .tint(Theme.flame)
                }
                Spacer()
                Text("Full zsh login shell — run anything")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            TerminalRepresentable()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1))
        }
    }
}
