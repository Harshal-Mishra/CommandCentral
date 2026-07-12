import Charts
import SwiftUI

struct TrackerTabView: View {
    @EnvironmentObject private var tracker: TimeTracker
    @EnvironmentObject private var tasks: TaskStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                TrackNowCard()
                todayCard
                goalStreakCard
                Spacer()
            }
            .frame(width: 330)
            VStack(spacing: 14) {
                chartCard
                HStack(alignment: .top, spacing: 14) {
                    SubjectBreakdownCard()
                    RecentSessionsCard()
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Today

    private var tasksDoneToday: Int {
        tasks.items.filter { $0.doneAt.map(Calendar.current.isDateInToday) ?? false }.count
    }

    private var todayCard: some View {
        Card(title: "Today", systemImage: "sun.max",
             trailing: formatHM(tracker.todaySeconds)) {
            VStack(alignment: .leading, spacing: 8) {
                let breakdown = tracker.bySubjectToday()
                if breakdown.isEmpty {
                    Text("No study time logged yet today")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        let maxSeconds = breakdown.first?.seconds ?? 1
                        ForEach(breakdown, id: \.subject) { entry in
                            SubjectBar(subject: entry.subject,
                                       seconds: entry.seconds,
                                       fraction: Double(entry.seconds) / Double(maxSeconds))
                        }
                    }
                }
                if tasksDoneToday > 0 {
                    Divider()
                    Label("\(tasksDoneToday) task\(tasksDoneToday == 1 ? "" : "s") completed today",
                          systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Goal & streak

    private var goalStreakCard: some View {
        Card(title: "Goal & Streak", systemImage: "flame") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.flame)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(tracker.currentStreak) day\(tracker.currentStreak == 1 ? "" : "s")")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Best: \(tracker.bestStreak)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatHM(tracker.seconds(in: .month)))
                            .font(.system(size: 16, weight: .medium))
                        Text("\(tracker.activeDaysThisMonth) active days this month")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(1, Double(tracker.todaySeconds) / Double(tracker.dailyGoalMinutes * 60))) {
                    Text("Today: \(formatHM(tracker.todaySeconds)) of \(formatHM(tracker.dailyGoalMinutes * 60)) goal")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .tint(Theme.accent)
                Stepper("Daily goal: \(formatHM(tracker.dailyGoalMinutes * 60))",
                        value: Binding(get: { tracker.dailyGoalMinutes },
                                       set: { tracker.setGoal($0) }),
                        in: 15...720, step: 15)
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        Card(title: "Last 14 Days", systemImage: "chart.bar",
             trailing: formatHM(tracker.seconds(in: .week)) + " this week") {
            Chart {
                ForEach(tracker.dailyTotals(days: 14)) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", day.minutes)
                    )
                    .foregroundStyle(Theme.accent.gradient)
                    .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", Double(tracker.dailyGoalMinutes)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.flame.opacity(0.8))
                    .annotation(position: .topTrailing) {
                        Text("goal")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.flame)
                    }
            }
            .chartYAxisLabel("minutes")
            .frame(height: 250)
        }
    }
}

// MARK: - Track now

struct TrackNowCard: View {
    @EnvironmentObject private var tracker: TimeTracker
    @EnvironmentObject private var tasks: TaskStore
    @State private var selectedSubject = ""
    @State private var selectedTaskId: UUID?
    @State private var newSubject = ""

    var body: some View {
        Card(title: "Track Now", systemImage: "record.circle") {
            VStack(alignment: .leading, spacing: 10) {
                if let notice = tracker.autoStopNotice {
                    Label(notice, systemImage: "moon.zzz")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.flame)
                }
                if let active = tracker.activeSubject {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(spacing: 4) {
                            Text(active)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accent)
                            if let detail = tracker.activeDetail {
                                Text(detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(formatHMS(tracker.activeSeconds))
                                .font(.system(size: 38, weight: .light).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Button {
                        tracker.stopStopwatch()
                    } label: {
                        Label("Stop & Save", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    HStack {
                        Picker("", selection: $selectedSubject) {
                            ForEach(tracker.subjects, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                        Button(action: start) {
                            Label("Start", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if !tasks.openTasks.isEmpty {
                        Picker("", selection: $selectedTaskId) {
                            Text("No task — just the subject").tag(UUID?.none)
                            ForEach(tasks.openTasks) { task in
                                Text(task.title).tag(Optional(task.id))
                            }
                        }
                        .labelsHidden()
                        .onChange(of: selectedTaskId) {
                            if let task = tasks.openTasks.first(where: { $0.id == selectedTaskId }),
                               let subject = task.subject {
                                selectedSubject = subject
                            }
                        }
                    }
                    Text("Pick a task to pin the session to it. Focus Timer sessions are logged automatically too.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Divider()
                HStack {
                    TextField("New subject…", text: $newSubject)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(addSubject)
                    Button(action: addSubject) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                FlowChips(subjects: tracker.subjects) { subject in
                    tracker.removeSubject(subject)
                }
            }
        }
        .onAppear {
            if selectedSubject.isEmpty {
                selectedSubject = tracker.subjects.first ?? "Other"
            }
        }
    }

    private func start() {
        let task = tasks.openTasks.first { $0.id == selectedTaskId }
        tracker.startStopwatch(selectedSubject, detail: task?.title, taskId: task?.id)
        selectedTaskId = nil
    }

    private func addSubject() {
        let name = newSubject.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        selectedSubject = tracker.addSubjectIfNeeded(name)
        newSubject = ""
    }
}

private struct FlowChips: View {
    let subjects: [String]
    let onDelete: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 4)], spacing: 4) {
            ForEach(subjects, id: \.self) { subject in
                Text(subject)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.rowFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                    .contextMenu {
                        Button("Remove \"\(subject)\"", role: .destructive) {
                            onDelete(subject)
                        }
                    }
            }
        }
    }
}

// MARK: - Breakdown

struct SubjectBreakdownCard: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case subjects = "Subjects"
        case tasks = "Tasks"
        var id: String { rawValue }
    }

    @EnvironmentObject private var tracker: TimeTracker
    @EnvironmentObject private var tasks: TaskStore
    @State private var range: StatsRange = .week
    @State private var mode: Mode = .subjects

    var body: some View {
        Card(title: "Breakdown", systemImage: "chart.pie",
             trailing: formatHM(tracker.seconds(in: range))) {
            VStack(spacing: 10) {
                Picker("", selection: $range) {
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch mode {
                case .subjects: subjectList
                case .tasks: taskList
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var subjectList: some View {
        let breakdown = tracker.bySubject(range)
        if breakdown.isEmpty {
            Text("Nothing tracked in this period yet — hit Start or run a focus timer.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    let maxSeconds = breakdown.first?.seconds ?? 1
                    ForEach(breakdown, id: \.subject) { entry in
                        SubjectBar(subject: entry.subject,
                                   seconds: entry.seconds,
                                   fraction: Double(entry.seconds) / Double(maxSeconds))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var taskList: some View {
        let totals = tracker.byTask(range)
        if totals.isEmpty {
            Text("No task time in this period — press ▶ on a task, or pick one in Track Now.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    let maxSeconds = totals.first?.seconds ?? 1
                    ForEach(totals) { entry in
                        TaskTotalRow(entry: entry,
                                     done: isDone(entry),
                                     fraction: Double(entry.seconds) / Double(maxSeconds))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func isDone(_ entry: TimeTracker.TaskTotal) -> Bool {
        guard let taskId = entry.taskId else { return false }
        return tasks.items.first { $0.id == taskId }?.done ?? false
    }
}

private struct TaskTotalRow: View {
    let entry: TimeTracker.TaskTotal
    let done: Bool
    let fraction: Double

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 12))
                .foregroundStyle(done ? Theme.accent : .secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 12))
                        .strikethrough(done)
                        .lineLimit(1)
                    Text(entry.subject)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(formatHM(entry.seconds))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.rowFill)
                        Capsule()
                            .fill(Theme.accent.gradient)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecentSessionsCard: View {
    @EnvironmentObject private var tracker: TimeTracker
    @State private var manualSubject = ""
    @State private var manualMinutes = ""
    @State private var manualDate = Date()

    var body: some View {
        Card(title: "Sessions", systemImage: "clock.arrow.circlepath") {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(tracker.recentSessions) { session in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.subject)
                                        .font(.system(size: 12))
                                    if let detail = session.detail {
                                        Text(detail)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(formatHM(session.seconds))
                                        .font(.system(size: 11).monospacedDigit())
                                    Text(session.date, format: .dateTime.day().month().hour().minute())
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                Button { tracker.deleteSession(session.id) } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 7))
                        }
                        if tracker.recentSessions.isEmpty {
                            Text("Logged sessions show up here")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.top, 20)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Divider()
                VStack(spacing: 6) {
                    Text("Add missed time")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Two rows — one long row of controls can outgrow this
                    // card on narrower windows.
                    HStack(spacing: 6) {
                        Picker("", selection: $manualSubject) {
                            ForEach(tracker.subjects, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                        TextField("min", text: $manualMinutes)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 44)
                    }
                    HStack(spacing: 6) {
                        DatePicker("", selection: $manualDate, displayedComponents: .date)
                            .labelsHidden()
                            .controlSize(.small)
                        Spacer(minLength: 0)
                        Button("Add") { addManual() }
                            .controlSize(.small)
                            .disabled(Int(manualMinutes) == nil)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if manualSubject.isEmpty {
                manualSubject = tracker.subjects.first ?? "Other"
            }
        }
    }

    private func addManual() {
        guard let minutes = Int(manualMinutes), minutes > 0 else { return }
        tracker.addManual(subject: manualSubject, minutes: minutes, day: manualDate)
        manualMinutes = ""
    }
}

struct SubjectBar: View {
    let subject: String
    let seconds: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(subject)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.rowFill)
                    Capsule()
                        .fill(Theme.accent.gradient)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 12)
            Text(formatHM(seconds))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }
}
