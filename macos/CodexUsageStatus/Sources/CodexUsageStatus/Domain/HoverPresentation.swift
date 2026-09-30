import Foundation

struct HoverPresentation {
    let resetCredits: String
    let fiveHourReset: String
    let weeklyReset: String
    let nextRefresh: String
    let status: String
    let updatedAt: String
    let isStale: Bool

    init(usage: UsageSummary?, nextRefreshDate: Date?, lastRefreshDate: Date?,
         isRefreshing: Bool, refreshFailed: Bool, now: Date = Date(), timeZone: TimeZone = .current) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func resetTime(_ date: Date?) -> String {
            guard let date else { return "暂未提供" }
            formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "'今天' HH:mm" : "M月d日 HH:mm"
            return formatter.string(from: date)
        }
        resetCredits = usage?.availableResetCount.map { "\($0) 次" } ?? "暂未提供"
        fiveHourReset = resetTime(usage?.fiveHour.resetsAt)
        weeklyReset = resetTime(usage?.weekly.resetsAt)
        formatter.dateFormat = "HH:mm:ss"
        if isRefreshing {
            nextRefresh = "正在刷新…"
        } else if let nextRefreshDate {
            nextRefresh = nextRefreshDate > now ? formatter.string(from: nextRefreshDate) : "即将刷新"
        } else {
            nextRefresh = "等待首次刷新"
        }
        isStale = refreshFailed
        status = refreshFailed ? "更新失败 · 上次记录" : (isRefreshing ? "更新中" : "自动更新")
        if let lastRefreshDate {
            formatter.dateFormat = calendar.isDate(lastRefreshDate, inSameDayAs: now) ? "HH:mm:ss" : "M月d日 HH:mm:ss"
            updatedAt = "更新于 \(formatter.string(from: lastRefreshDate))"
        } else {
            updatedAt = "尚未取得额度数据"
        }
    }
}
