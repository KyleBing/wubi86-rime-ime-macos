import Foundation

/// 输入 date / time / week 编码时，插入基于系统时间的候选。
/// 五笔最多四码，只保留四码的 date / time / week；短码别名会在打四码词途中抢占正常候选，不再提供。
enum DateTimeCandidates {
    /// 匹配则返回候选列表；不匹配返回 nil
    static func candidates(for preedit: String) -> [String]? {
        let key = preedit
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return nil }
        let now = Date()
        switch key {
        case "date":
            // 日期在前，日期 + 时间组合排在后面翻页可见。
            return unique(dateFormats(now) + dateTimeFormats(now))
        case "time":
            return timeFormats(now)
        case "week":
            return weekFormats(now)
        default:
            return nil
        }
    }

    private static func dateFormats(_ date: Date) -> [String] {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let mm = String(format: "%02d", m)
        let dd = String(format: "%02d", d)
        let weekday = weekdayCN(cal.component(.weekday, from: date))
        return unique([
            "\(y)-\(mm)-\(dd)",
            "\(y)/\(mm)/\(dd)",
            "\(y).\(mm).\(dd)",
            "\(y)\(mm)\(dd)",
            "\(y)年\(m)月\(d)日",
            "\(m)月\(d)日",
            "\(mm)-\(dd)",
            "\(mm)/\(dd)",
            weekday,
            "\(y)年\(m)月\(d)日 \(weekday)"
        ])
    }

    private static func timeFormats(_ date: Date) -> [String] {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let mi = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        let hh = String(format: "%02d", h)
        let mm = String(format: "%02d", mi)
        let ss = String(format: "%02d", s)
        let ts = Int(date.timeIntervalSince1970)
        let tsMs = Int(date.timeIntervalSince1970 * 1000)
        // 第 3 位秒级时间戳、第 4 位「时分」，其余紧凑格式排在后面。
        return unique([
            "\(hh):\(mm):\(ss)",
            "\(hh):\(mm)",
            "\(ts)",
            "\(h)时\(mi)分",
            "\(hh)\(mm)\(ss)",
            "\(hh)\(mm)",
            "\(h)时\(mi)分\(s)秒",
            "\(tsMs)"
        ])
    }

    // 星期与周数：周数按 ISO 8601（周一为一周开始），与常见日历一致。
    private static func weekFormats(_ date: Date) -> [String] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let full = weekdayCN(weekday)
        let short = full.replacingOccurrences(of: "星期", with: "周")
        let libai = full.replacingOccurrences(of: "星期", with: "礼拜")
        let iso = Calendar(identifier: .iso8601)
        let week = iso.component(.weekOfYear, from: date)
        let weekYear = iso.component(.yearForWeekOfYear, from: date)
        let english = DateFormatter()
        english.locale = Locale(identifier: "en_US_POSIX")
        english.dateFormat = "EEEE"
        let englishFull = english.string(from: date)
        english.dateFormat = "EEE"
        let englishShort = english.string(from: date)
        return unique([
            full,
            short,
            "第\(week)周",
            "\(weekYear)年第\(week)周",
            libai,
            englishFull,
            englishShort,
            "\(weekYear)-W\(String(format: "%02d", week))"
        ])
    }

    private static func dateTimeFormats(_ date: Date) -> [String] {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let mo = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let h = cal.component(.hour, from: date)
        let mi = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        let mm = String(format: "%02d", mo)
        let dd = String(format: "%02d", d)
        let hh = String(format: "%02d", h)
        let mi2 = String(format: "%02d", mi)
        let ss = String(format: "%02d", s)
        return unique([
            "\(y)-\(mm)-\(dd) \(hh):\(mi2):\(ss)",
            "\(y)/\(mm)/\(dd) \(hh):\(mi2):\(ss)",
            "\(y)\(mm)\(dd)\(hh)\(mi2)\(ss)",
            "\(y)年\(mo)月\(d)日 \(h)时\(mi)分\(s)秒",
            "\(y)-\(mm)-\(dd) \(hh):\(mi2)",
            ISO8601DateFormatter().string(from: date)
        ])
    }

    private static func weekdayCN(_ weekday: Int) -> String {
        // Calendar: 1=周日 … 7=周六
        let names = ["", "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        guard weekday >= 1, weekday <= 7 else { return "" }
        return names[weekday]
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in items where !s.isEmpty {
            if seen.insert(s).inserted { out.append(s) }
        }
        return out
    }
}
