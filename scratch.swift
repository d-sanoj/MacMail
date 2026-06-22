import Foundation

func nextMorning() -> Date {
    let cal = Calendar.current
    var components = cal.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
    components.hour = 8
    return cal.date(from: components) ?? Date()
}
func nextAfternoon() -> Date {
    let cal = Calendar.current
    var components = cal.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
    components.hour = 13
    return cal.date(from: components) ?? Date()
}
func nextMondayMorning() -> Date {
    let cal = Calendar.current
    var date = Date()
    while cal.component(.weekday, from: date) != 2 { // 2 is Monday
        date = date.addingTimeInterval(86400)
    }
    var components = cal.dateComponents([.year, .month, .day], from: date)
    components.hour = 8
    return cal.date(from: components) ?? Date()
}

print(nextMorning())
print(nextAfternoon())
print(nextMondayMorning())
