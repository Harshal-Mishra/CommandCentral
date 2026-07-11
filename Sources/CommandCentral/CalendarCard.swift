import SwiftUI

struct CalendarCard: View {
    var cellSize: CGFloat = 26
    @State private var monthOffset = 0

    private var calendar: Calendar { Calendar.current }

    private var displayedMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    var body: some View {
        Card(title: "Calendar", systemImage: "calendar") {
            VStack(spacing: 8) {
                HStack {
                    Text(displayedMonth, format: .dateTime.month(.wide).year())
                        .font(.system(size: max(14, cellSize * 0.5), weight: .semibold))
                    if monthOffset != 0 {
                        Button("Today") { monthOffset = 0 }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                    Spacer()
                    Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                          spacing: cellSize * 0.18) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: max(10, cellSize * 0.36), weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            Text("\(day)")
                                .font(.system(size: max(12, cellSize * 0.42)).monospacedDigit())
                                .frame(width: cellSize, height: cellSize)
                                .background(isToday(day) ? Color.accentColor : .clear,
                                            in: Circle())
                                .foregroundStyle(isToday(day) ? .white : .primary)
                        } else {
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var dayCells: [Int?] {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    private func isToday(_ day: Int) -> Bool {
        monthOffset == 0 && day == calendar.component(.day, from: Date())
    }
}
