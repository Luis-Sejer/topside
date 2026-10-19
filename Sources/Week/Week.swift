import AppKit
import Kit
import SwiftUI

@main
enum Main {
    @MainActor static func main() { Kit.run { Week() } }
}

/// The ISO week number in the menu bar, the way Danes plan, with a month calendar that shows the weeks.
@MainActor
final class Week {
    private let month = MonthModel()
    private lazy var item = MenuBarItem(
        name: "Week",
        symbol: nil,
        click: .popover(AnyView(MonthView(model: month)), size: MonthView.size)
    )
    private var dayObserver: Any?

    init() {
        refresh()
        item.onShow = { [month] in
            month.today = Date()
            month.offset = 0
        }
        // Also posted on wake when the day changed during sleep.
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        month.today = Date()
        item.setTitle(Self.label(for: Date()))
    }

    nonisolated static func label(for date: Date, danish: Bool = Locale.preferredLanguages.first?.hasPrefix("da") == true) -> String {
        let week = Calendar.iso8601.component(.weekOfYear, from: date)
        return danish ? "Uge \(week)" : "W\(week)"
    }
}

extension Calendar {
    /// Weeks start on Monday and week 1 holds the year's first Thursday, as in Denmark and most of Europe.
    static let iso8601: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .current
        return calendar
    }()

    /// The Monday of every week that touches the month `date` is in.
    func weekStarts(inMonthOf date: Date) -> [Date] {
        guard let month = dateInterval(of: .month, for: date),
              var start = dateInterval(of: .weekOfYear, for: month.start)?.start else { return [] }
        var starts: [Date] = []
        while start < month.end {
            starts.append(start)
            start = self.date(byAdding: .weekOfYear, value: 1, to: start) ?? month.end
        }
        return starts
    }
}

final class MonthModel: ObservableObject {
    @Published var today = Date()
    /// Months away from this one, changed by the arrows.
    @Published var offset = 0
}

struct MonthView: View {
    static let size = NSSize(width: 288, height: 292)

    @ObservedObject var model: MonthModel
    private let calendar = Calendar.iso8601

    private var month: Date {
        let start = calendar.dateInterval(of: .month, for: model.today)?.start ?? model.today
        return calendar.date(byAdding: .month, value: model.offset, to: start) ?? start
    }

    /// Monday first, matching the ISO calendar.
    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[..<1])
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Text("Wk").foregroundStyle(.tertiary)
                    ForEach(weekdays.indices, id: \.self) { index in
                        Text(weekdays[index]).foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.medium))
                ForEach(calendar.weekStarts(inMonthOf: month), id: \.self) { start in
                    GridRow {
                        Text("\(calendar.component(.weekOfYear, from: start))")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Week \(calendar.component(.weekOfYear, from: start))")
                        ForEach(0..<7, id: \.self) { day in
                            dayCell(calendar.date(byAdding: .day, value: day, to: start) ?? start)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            if model.offset != 0 {
                Button("Today") { model.offset = 0 }
                    .buttonStyle(.borderless)
            }
            Button { model.offset -= 1 } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous month")
            Button { model.offset += 1 } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next month")
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: model.today)
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        return Text("\(calendar.component(.day, from: date))")
            .font(.callout.monospacedDigit())
            .frame(width: 30, height: 28)
            .foregroundStyle(isToday ? AnyShapeStyle(.white) : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .background(isToday ? Circle().fill(.tint) : nil)
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
