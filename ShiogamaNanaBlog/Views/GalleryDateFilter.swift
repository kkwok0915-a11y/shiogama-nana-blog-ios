import SwiftUI

/// Compact date control for the gallery. Nothing selected reads 全部日期.
/// Tapping opens a calendar limited to the newest and oldest days that have photos.
struct GalleryDateFilter: View {
    /// Available days, newest first (`yyyy-MM-dd`).
    let dates: [String]
    /// The day being shown, already snapped to a day that has photos.
    let value: String?
    var onChange: (String?) -> Void

    @State private var picking = false
    @State private var draft = Date()
    /// Day already applied. The calendar's first assignment of this day is ignored.
    @State private var seedDay = ""

    private static let tokyo = TimeZone(identifier: "Asia/Tokyo")
        ?? TimeZone(secondsFromGMT: 9 * 60 * 60)
        ?? TimeZone.current

    var body: some View {
        if let bounds {
            HStack(spacing: 6) {
                Button {
                    let start = value ?? dates.first ?? ""
                    seedDay = start
                    draft = Self.date(from: start) ?? bounds.upperBound
                    picking = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(value.map(Self.display) ?? "全部日期")
                            .lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(value == nil ? Theme.inkSoft : Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Theme.accent.opacity(value == nil ? 0.2 : 0.7), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == nil ? "全部日期" : Self.display(value ?? ""))
                .accessibilityHint("選擇日期")

                if value != nil {
                    stepButton("‹", enabled: older != nil, label: "上一個有內容的日期（較早）") {
                        if let older { onChange(older) }
                    }
                    stepButton("›", enabled: newer != nil, label: "下一個有內容的日期（較新）") {
                        if let newer { onChange(newer) }
                    }
                    Button("全部") { onChange(nil) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除日期，顯示全部日期")
                }
            }
            .popover(isPresented: $picking, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                VStack(spacing: 8) {
                    DatePicker(
                        "選擇日期",
                        selection: $draft,
                        in: bounds,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    Button("顯示這一天") {
                        onChange(Self.day(from: draft))
                        picking = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .environment(\.timeZone, Self.tokyo)
                .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                .padding()
                .frame(minWidth: 320)
                .presentationCompactAdaptation(.popover)
                .onChange(of: draft) { _, newValue in
                    let day = Self.day(from: newValue)
                    guard picking, day != seedDay else { return }
                    seedDay = day
                    onChange(day)
                    picking = false
                }
            }
        }
    }

    private var bounds: ClosedRange<Date>? {
        guard let newest = dates.first, let oldest = dates.last,
              let upper = Self.date(from: newest),
              let lower = Self.date(from: oldest),
              lower <= upper
        else { return nil }
        return lower...upper
    }

    /// `dates` is newest first, so the next newer day is the previous index.
    private var newer: String? {
        guard let value, let index = dates.firstIndex(of: value), index > 0 else { return nil }
        return dates[index - 1]
    }

    private var older: String? {
        guard let value, let index = dates.firstIndex(of: value), index + 1 < dates.count else { return nil }
        return dates[index + 1]
    }

    private func stepButton(_ title: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.inkSoft)
            .frame(width: 36, height: 36)
            .background(Theme.card, in: Circle())
            .overlay {
                Circle().strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .accessibilityLabel(label)
    }

    private static func display(_ day: String) -> String {
        day.replacingOccurrences(of: "-", with: ".")
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        calendar.locale = Locale(identifier: "zh_Hant_TW")
        return calendar
    }

    private static func date(from day: String?) -> Date? {
        guard let day else { return nil }
        let parts = day.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func day(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1, parts.month ?? 1, parts.day ?? 1)
    }
}
