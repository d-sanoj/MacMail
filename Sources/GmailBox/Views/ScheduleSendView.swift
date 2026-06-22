import SwiftUI

struct ScheduleSendView: View {
    @Binding var customDate: Date
    let onSchedule: (Date) -> Void
    
    @State private var showingCustomPicker = false
    @State private var hoveredItem: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Schedule send")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Divider()
            
            presetButton("Tomorrow morning", date: nextMorning(), icon: "sunrise")
            presetButton("Tomorrow afternoon", date: nextAfternoon(), icon: "sun.max")
            presetButton("Monday morning", date: nextMondayMorning(), icon: "calendar")
            
            Divider()
            
            Button {
                withAnimation(.snappy) { showingCustomPicker.toggle() }
            } label: {
                HStack {
                    Image(systemName: "clock")
                        .frame(width: 24)
                    Text("Pick date & time")
                    Spacer()
                    Image(systemName: showingCustomPicker ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .background(hoveredItem == "Pick date & time" ? Color.secondary.opacity(0.1) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered { hoveredItem = "Pick date & time" }
                else if hoveredItem == "Pick date & time" { hoveredItem = nil }
            }
            
            if showingCustomPicker {
                VStack {
                    DatePicker("", selection: $customDate, in: Date()...)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    
                    Button("Schedule Send") {
                        onSchedule(customDate)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 320)
    }
    
    private func presetButton(_ title: String, date: Date, icon: String) -> some View {
        Button {
            onSchedule(date)
        } label: {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundColor(.secondary)
                Text(title)
                Spacer()
                Text(formatter.string(from: date))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(hoveredItem == title ? Color.secondary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered { hoveredItem = title }
            else if hoveredItem == title { hoveredItem = nil }
        }
    }
    
    private var formatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }

    private func nextMorning() -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
        components.hour = 8
        return cal.date(from: components) ?? Date()
    }
    
    private func nextAfternoon() -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
        components.hour = 13
        return cal.date(from: components) ?? Date()
    }
    
    private func nextMondayMorning() -> Date {
        let cal = Calendar.current
        var date = Date()
        while cal.component(.weekday, from: date) != 2 { // 2 is Monday
            date = date.addingTimeInterval(86400)
        }
        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = 8
        
        let monday = cal.date(from: components) ?? Date()
        // If today is Monday before 8 AM, don't return today.
        if monday <= Date() {
            return cal.date(byAdding: .day, value: 7, to: monday) ?? monday
        }
        return monday
    }
}
