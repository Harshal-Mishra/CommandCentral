import AppKit
import SwiftUI

final class JournalWindowController: NSWindowController, NSWindowDelegate {
    private let state: AppState

    init(state: AppState) {
        self.state = state
        let content = JournalView()
            .environmentObject(state.journal)
            .environmentObject(state.tasks)
            .environmentObject(state.tracker)
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Journal"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 620))
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Auto-lock whenever the window closes.
    func windowWillClose(_ notification: Notification) {
        state.journal.lock()
    }
}

struct JournalView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var tracker: TimeTracker

    @State private var day = Date()
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        Group {
            if journal.unlocked {
                diary
            } else {
                lockScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.gradient)
        .tint(Theme.accent)
    }

    // MARK: - Lock screen

    private var lockScreen: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(journal.exists ? "Your journal is locked" : "Create your secret journal")
                .font(.system(size: 18, weight: .semibold))
            Text(journal.exists
                 ? "Pages are encrypted on disk — enter your password."
                 : "Pick a password. Pages are AES-encrypted with it; there is no recovery if you forget it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 340)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(submit)
            if !journal.exists {
                SecureField("Confirm password", text: $confirm)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit(submit)
            }
            Button(journal.exists ? "Unlock" : "Create Journal", action: submit)
                .buttonStyle(.borderedProminent)
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        error = nil
        if journal.exists {
            if !journal.unlock(password: password) {
                error = "Wrong password."
            }
        } else {
            guard password.count >= 4 else {
                error = "Use at least 4 characters."
                return
            }
            guard password == confirm else {
                error = "Passwords don't match."
                return
            }
            if !journal.create(password: password) {
                error = "Couldn't create the journal file."
            }
        }
        password = ""
        confirm = ""
    }

    // MARK: - Diary

    private var diary: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                daySummary
                    .frame(width: 250)
                Card(title: "How was the day?", systemImage: "square.and.pencil") {
                    TextEditor(text: Binding(
                        get: { journal.text(for: day) },
                        set: { journal.setText($0, for: day) }
                    ))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day } label: {
                Image(systemName: "chevron.left")
            }
            VStack(spacing: 1) {
                Text("Page \(calendar.ordinality(of: .day, in: .year, for: day) ?? 0) · \(calendar.component(.year, from: day))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 17, weight: .semibold))
            }
            Button { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(calendar.isDateInToday(day))
            Spacer()
            DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .controlSize(.small)
            if !calendar.isDateInToday(day) {
                Button("Today") { day = Date() }
                    .controlSize(.small)
            }
            Text("\(journal.pageCount) pages written")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button {
                journal.lock()
            } label: {
                Label("Lock", systemImage: "lock.fill")
            }
            .controlSize(.small)
        }
        .buttonStyle(.borderless)
    }

    private var daySummary: some View {
        Card(title: "That Day", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 8) {
                let studied = tracker.seconds(on: day)
                Label(studied > 0 ? "Studied \(formatHM(studied))" : "No study logged",
                      systemImage: "hourglass")
                    .font(.system(size: 12))
                let done = tasksDone
                if !done.isEmpty {
                    Text("Done that day")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(done) { task in
                        Label(task.title, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                if calendar.isDateInToday(day) {
                    let planned = tasks.openTasks.prefix(6)
                    if !planned.isEmpty {
                        Text("Still planned")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(planned)) { task in
                            Label(task.title, systemImage: "circle")
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private var tasksDone: [TaskItem] {
        tasks.items.filter { task in
            guard task.done, let doneAt = task.doneAt else { return false }
            return calendar.isDate(doneAt, inSameDayAs: day)
        }
    }
}
