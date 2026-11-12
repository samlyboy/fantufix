import Foundation

/// 写入相册的顺序模式：**三态互斥**，用同一个变量存放，物理上只能有一种生效。
enum WriteOrderMode: String, CaseIterable, Identifiable {
    /// 默认：网格里「起 → 止」怎么排就怎么写，完全不重排
    case gridOrder
    /// 图1 视1 图2 视2… 交替（各类内部保持原序，短的用完长的接后面）
    case interleave
    /// 先写全部图片（保持原序），再写全部视频（保持原序）
    case imagesFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gridOrder: return "按原序"
        case .interleave: return "图视交替"
        case .imagesFirst: return "图先视后"
        }
    }

    var detail: String {
        switch self {
        case .gridOrder: return "网格里怎么排就怎么写，不做任何重排"
        case .interleave: return "按 图1 视1 图2 视2… 交替穿插"
        case .imagesFirst: return "先写完全部图片，再写全部视频"
        }
    }

    /// 说明行：讲清楚这种模式对相册先后的影响，以及「倒序」时怎么走
    var hint: String {
        switch self {
        case .gridOrder:
            return "默认：完全按网格「起 → 止」的顺序写入相册，顺序原封不动；切「倒序」时整串反过来。"
        case .interleave:
            return "图、视各自保持原序，按 图1 视1 图2 视2… 交替写入；某一类用完后，另一类顺势接在后面。"
        case .imagesFirst:
            return "所有图片按原序写在最前，所有视频按原序接在后面；切「倒序」时两组各自反序，图片仍在前面。"
        }
    }
}

enum ReorderPlanner {

    /// 给区间内的素材分配**网格编号**与**写入顺序**。两者是分开的两件事：
    ///
    /// 1. **编号**（只在 App 网格右上角显示，不写进画面、不烧进图片视频）：取「遍历位次」。
    ///    从「起」那格开始、朝「止」的方向每格 +1，1…M 严格连排，与写入模式无关。
    ///    所以网格（始终按原始顺序显示）正序读是 1、2、3…，倒序读是 M、M-1…1。
    ///
    /// 2. **写入顺序**（时间戳，决定相册里从上往下的先后），由 `writeMode` 决定，三态互斥：
    ///    - `.gridOrder`（默认，按原序）：直接按遍历顺序写，不做任何重排。
    ///      正序 = 网格原顺序；倒序 = 整串反过来。此时编号 1…M 与相册先后完全一致。
    ///    - `.interleave`（图视交替）：图、视各抽一条序列，按「图1 视1 图2 视2 …」交替；
    ///      数量不等时短的一方用完，剩下的顺势接在后面。
    ///    - `.imagesFirst`（图先视后）：全部图片（组内保持遍历顺序）→ 全部视频（组内保持遍历顺序）。
    ///      倒序只反转两组内部，图片依旧在视频前面。
    ///
    /// - 写入相册时最前面有 1 张分隔图（配色由 `theme` 决定，默认红底黄字）；
    ///   其余都是原素材的干净副本：图片不重编码、视频最多裁掉开头，画面不加任何标记。
    /// - `start < end` 正序；`start > end` 倒序（区间仍是 [end, start]，遍历方向反过来）。
    static func makePlan(items: [MediaItem], start: Int, end: Int, now: Date,
                         writeMode: WriteOrderMode = .gridOrder,
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

        // 写入顺序：只影响时间戳，不影响编号。三选一，互不叠加。
        let writeOrder: [MediaItem]
        switch writeMode {
        case .gridOrder:
            writeOrder = walk
        case .interleave:
            writeOrder = interleaved(walk)
        case .imagesFirst:
            let images = walk.filter { $0.kind == .image }
            let videos = walk.filter { $0.kind == .video }
            writeOrder = images + videos
        }

        var entries: [PlanEntry] = []
        entries.reserveCapacity(writeOrder.count)
        for (writeIndex, item) in writeOrder.enumerated() {
            let number = numberByID[item.id] ?? (writeIndex + 1)
            let date = now.addingTimeInterval(-Double(writeIndex + 1) * 2.0)
            entries.append(PlanEntry(id: "\(number)-\(item.id)", item: item, number: number, date: date))
        }

        return ReorderPlan(separatorDate: now, entries: entries, theme: theme)
    }

    /// 图视交替：图、视各抽一条序列，按 图1 视1 图2 视2 … 交替；短的一方用完后剩下的接在后面
    private static func interleaved(_ src: [MediaItem]) -> [MediaItem] {
        let images = src.filter { $0.kind == .image }
        let videos = src.filter { $0.kind == .video }
        var order: [MediaItem] = []
        order.reserveCapacity(src.count)
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
        return order
    }
}
