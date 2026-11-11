import Foundation

enum ReorderPlanner {

    /// 给区间内的素材分配**网格编号**与**写入顺序**。两者是分开的两件事：
    ///
    /// 1. **编号**（只在 App 网格右上角显示，不写进画面、不烧进图片视频）：取「遍历位次」。
    ///    从「起」那格开始、朝「止」的方向每格 +1，1…M 严格连排。
    ///
    /// 2. **写入顺序**（时间戳，决定相册里从上往下的先后）：**始终按勾选原序（网格原序）写**，
    ///    不做图视分堆/交替。`keepOriginalOrder` 保留但不再影响写入（仅为兼容旧调用签名），
    ///    无论开/关，写入顺序都是「网格原序」或「整串反过来（倒序）」。
    ///
    /// - 写入相册时最前面有 1 张分隔图（配色由 `theme` 决定，默认红底黄字）；
    ///   其余都是原素材的干净副本：图片不重编码、视频最多裁掉开头，画面不加任何标记。
    /// - `start < end` 正序；`start > end` 倒序（区间仍是 [end, start]，遍历方向反过来）。
    static func makePlan(items: [MediaItem], start: Int, end: Int, now: Date,
                         keepOriginalOrder: Bool = false,
                         theme: SeparatorTheme = .defaultTheme) -> ReorderPlan {
        let count = items.count
        guard count > 0 else {
            return ReorderPlan(separatorDate: now, entries: [], theme: theme)
        }

        let clampedStart = min(max(1, start), count)
        let clampedEnd = min(max(1, end), count)

        let lower = min(clampedStart, clampedEnd)
        let upper = max(clampedStart, clampedEnd)
        let isReverse = clampedStart > clampedEnd

        // 遍历顺序：区间内按原始顺序，倒序时整体反转
        var walk = Array(items[(lower - 1)...(upper - 1)])
        if isReverse { walk.reverse() }

        // 位次编号：遍历顺序里的第几个 → 编号几
        var numberByID: [String: Int] = [:]
        numberByID.reserveCapacity(walk.count)
        for (index, item) in walk.enumerated() {
            numberByID[item.id] = index + 1
        }

        // 写入顺序：始终按网格原序写（用户勾选的原序），不做图视分堆
        //  keepOriginalOrder 保留仅为兼容旧调用；无论开/关，写入顺序都是 walk（倒序=整串反过来）
        let writeOrder: [MediaItem] = walk

        var entries: [PlanEntry] = []
        entries.reserveCapacity(writeOrder.count)
        for (writeIndex, item) in writeOrder.enumerated() {
            let number = numberByID[item.id] ?? (writeIndex + 1)
            let date = now.addingTimeInterval(-Double(writeIndex + 1) * 2.0)
            entries.append(PlanEntry(id: "\(number)-\(item.id)", item: item, number: number, date: date))
        }

        return ReorderPlan(separatorDate: now, entries: entries, theme: theme)
    }
}
