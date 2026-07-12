import AppKit
import SwiftUI

// MARK: - Shared card chrome

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }
}

// MARK: - Media

struct MediaCard: View {
    @EnvironmentObject private var media: MediaController
    @State private var sliderVolume: Double = 50
    @State private var dragging = false

    var body: some View {
        Card(title: "Now Playing", systemImage: "music.note") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.nowPlayingTitle)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    Text(media.nowPlayingDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 26) {
                    Spacer()
                    Button { media.previous() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 18))
                    }
                    Button { media.playPause() } label: {
                        Image(systemName: media.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                    }
                    Button { media.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 18))
                    }
                    Spacer()
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $sliderVolume, in: 0...100) { editing in
                        dragging = editing
                        if !editing { media.setVolume(sliderVolume) }
                    }
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(media.$volume) { value in
            if !dragging { sliderVolume = value }
        }
    }
}

// MARK: - Tasks

struct TasksCard: View {
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var tracker: TimeTracker
    @State private var newTask = ""
    @State private var newTaskSubject = ""

    var body: some View {
        Card(title: "Tasks", systemImage: "checklist",
             trailing: "\(tasks.openTasks.count) open") {
            VStack(spacing: 10) {
                HStack {
                    TextField("Add a task…", text: $newTask)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Menu {
                        Button("No subject") { newTaskSubject = "" }
                        ForEach(tracker.subjects, id: \.self) { subject in
                            Button(subject) { newTaskSubject = subject }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "tag")
                            if !newTaskSubject.isEmpty {
                                Text(newTaskSubject).font(.system(size: 10))
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Tag the new task with a study subject")
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sortedTasks) { task in
                            taskRow(task)
                        }
                        if tasks.items.isEmpty {
                            Text("Nothing here — add your first task above")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.top, 30)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                if tasks.items.contains(where: \.done) {
                    Button("Clear completed") { tasks.clearCompleted() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var sortedTasks: [TaskItem] {
        tasks.items.sorted { !$0.done && $1.done }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            Button { tasks.toggle(task.id) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
                    .lineLimit(2)
                if let subject = task.subject {
                    Text(subject)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.2), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            if !task.done {
                Button {
                    tracker.startStopwatch(task.subject ?? tracker.subjects.first ?? "Other",
                                           detail: task.title,
                                           taskId: task.id)
                } label: {
                    Image(systemName: isTrackingThis(task) ? "record.circle.fill" : "play.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isTrackingThis(task) ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help("Start tracking time on this task")
            }
            Button { tasks.remove(task.id) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete task")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }

    private func isTrackingThis(_ task: TaskItem) -> Bool {
        tracker.isTracking
            && (tracker.activeTaskId == task.id || tracker.activeDetail == task.title)
    }

    private func add() {
        let title = newTask.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        tasks.add(title, subject: newTaskSubject.isEmpty ? nil : newTaskSubject)
        newTask = ""
    }
}

// MARK: - Focus timer

struct TimerCard: View {
    @EnvironmentObject private var timer: TimerManager
    @EnvironmentObject private var tracker: TimeTracker
    @State private var selectedSubject = ""
    @State private var customMinutes = ""

    var body: some View {
        Card(title: "Focus Timer", systemImage: "timer") {
            VStack(spacing: 10) {
                Text(timer.isRunning ? timer.remainingText : "Ready")
                    .font(.system(size: 40, weight: .light).monospacedDigit())
                    .frame(maxWidth: .infinity)
                if timer.isRunning {
                    if let subject = timer.subject {
                        Text("Logging to \(subject)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                    Button("Stop") { timer.stop() }
                        .controlSize(.large)
                } else {
                    Picker("", selection: $selectedSubject) {
                        ForEach(tracker.subjects, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                    HStack(spacing: 6) {
                        ForEach([30, 60, 120, 180], id: \.self) { minutes in
                            Button(minutes < 60 ? "\(minutes)m"
                                   : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m")) {
                                timer.start(minutes: minutes, subject: selectedSubject)
                            }
                        }
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 6) {
                        TextField("custom min", text: $customMinutes)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 84)
                        Button("Start") {
                            if let minutes = Int(customMinutes), (1...720).contains(minutes) {
                                timer.start(minutes: minutes, subject: selectedSubject)
                                customMinutes = ""
                            }
                        }
                        .controlSize(.small)
                        .disabled(Int(customMinutes) == nil)
                    }
                    .frame(maxWidth: .infinity)
                    Text("Finished time is logged to the subject above")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onAppear {
            if selectedSubject.isEmpty {
                selectedSubject = tracker.subjects.first ?? "Other"
            }
        }
    }
}

// MARK: - Processes / system

struct ProcessesCard: View {
    @EnvironmentObject private var stats: SystemStats
    var showKill = false

    var body: some View {
        Card(title: "System", systemImage: "cpu", trailing: stats.cpuSummary) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Memory: \(stats.memSummary)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: 48, alignment: .trailing)
                    Text("MEM").frame(width: 48, alignment: .trailing)
                    if showKill {
                        Text("").frame(width: 24)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(stats.processes) { process in
                            HStack {
                                Text(process.name)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.1f%%", process.cpu))
                                    .frame(width: 48, alignment: .trailing)
                                Text(String(format: "%.1f%%", process.mem))
                                    .frame(width: 48, alignment: .trailing)
                                if showKill {
                                    Button { stats.terminate(pid: process.pid) } label: {
                                        Image(systemName: "xmark.circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 24)
                                    .help("Quit \(process.name)")
                                }
                            }
                            .font(.system(size: 11).monospacedDigit())
                        }
                        if stats.processes.isEmpty {
                            Text("Measuring…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.top, 20)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}
