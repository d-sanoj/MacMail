import Foundation
import SQLite3
import SwiftUI

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }

    var base64URLDecodedString: String? {
        var encoded = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 {
            encoded.append("=")
        }
        guard let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    var htmlStripped: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributed.string
    }
}

extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}

extension Date {
    var mailboxTimestamp: String {
        if Calendar.current.isDateInToday(self) {
            return Self.timeFormatter.string(from: self)
        }
        return Self.dateFormatter.string(from: self)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()
}

enum TimeSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This week"
    case lastWeek = "Last week"
    case thisMonth = "This month"
    case older = "Older"
    
    var id: String { rawValue }
}

extension Date {
    var timeSection: TimeSection {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return .today }
        if calendar.isDateInYesterday(self) { return .yesterday }
        
        let now = Date()
        if calendar.isDate(self, equalTo: now, toGranularity: .weekOfYear) {
            return .thisWeek
        }
        
        if let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
           calendar.isDate(self, equalTo: lastWeekDate, toGranularity: .weekOfYear) {
            return .lastWeek
        }
        
        if calendar.isDate(self, equalTo: now, toGranularity: .month) {
            return .thisMonth
        }
        
        return .older
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let integer = Int(value, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((integer >> 16) & 0xff) / 255,
            green: Double((integer >> 8) & 0xff) / 255,
            blue: Double(integer & 0xff) / 255
        )
    }
}
