import Foundation

enum ReorderPlanner {

    /// 给区间内的素材分配**网格编号**与**写入顺序**。两者是分开的两件事：
    ///
    /// 1. **编号**（只在 App 网格右上角显示，不写进画面、不烧进图片视频）：取「遍历位次」。
    ///    从「起」那格开始、朝「止」的方向每格 +1，1…M 严格连排，与图视交替无关。
    ///    所以网格（始终按原始顺序显示）正序读是 1、2、3…，倒序读是 M、M-1…1。
    ///
    /// 2. **写入顺序**（时间戳，决定相册里从上往下的先后），由 `keepOriginalOrder` 决定两种模式：
    ///    - 关（默认，交替）：图、视各抽一条序列，按「图1 视1 图2 视2 …」交替；
    ///      数量不等时短的一方用完，剩下的顺势接在后面。编号 1 的时间最新。
    ///    - 开（保持原顺序）：直接按遍历顺序写，不做任何重排。
    ///      正序 = 网格原顺序；倒序 = 整串反过来。此时编号 1…M 与相册先后完全一致。
    ///
    /// - 写入相册的都是原素材的干净副本：图片不重编码、视频最多裁掉开头，画面不加任何标记。
    /// - `start < end` 正序；`start > end` 倒序（区间仍是 [end, start]，遍历方向反过来）。
    static func makePlan(items: [MediaItem], start: Int, end: Int, now: Date,
                         keepOriginalOrder: Bool = false) -> ReorderPlan {
        let count = items.count
        guard count > 0 else {
            return ReorderPlan(entries: [])
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

        // 写入顺序：只影响时间戳，不影响编号
        //  交替模式   = 图/视各抽一条序列，按 图1 视1 图2 视2 … 交替
        //  原顺序模式 = 直接按遍历顺序（正序=网格顺序，倒序=整串反过来），顺序原封不动
        let writeOrder: [MediaItem]
        if keepOriginalOrder {
            writeOrder = walk
        } else {
            let images = walk.filter { $0.kind == .image }
            let videos = walk.filter { $0.kind == .video }
            var order: [MediaItem] = []
            order.reserveCapacity(walk.count)
            var i = 0
            var j = 0
            while i < images.count || j < videos.count {
                if i < images.count {
                    order.append(images[i])
                    i += 1
                }
                if j < videos.count {
                    order.append(videos[j])
                    j += 1
                }
            }
            writeOrder = order
        }

        var entries: [PlanEntry] = []
        entries.reserveCapacity(writeOrder.count)
        for (writeIndex, item) in writeOrder.enumerated() {
            let number = numberByID[item.id] ?? (writeIndex + 1)
            let date = now.addingTimeInterval(-Double(writeIndex + 1) * 2.0)
            entries.append(PlanEntry(id: "\(number)-\(item.id)", item: item, number: number, date: date))
        }

        return ReorderPlan(entries: entries)
    }
}
