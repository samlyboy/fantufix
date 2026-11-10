import Foundation
import UIKit

enum MediaKind: String {
    case image
    case video

    var short: String {
        switch self {
        case .image: return "图"
        case .video: return "视"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo.fill"
        case .video: return "video.fill"
        }
    }
}

struct MediaItem: Identifiable {
    let id: String
    let kind: MediaKind
    let creationDate: Date
    var thumb: UIImage?
    var pixelSize: CGSize
    var duration: TimeInterval
    /// 是否参与本次重排；网格里点一下格子即可切换
    var isSelected: Bool = true
}

struct PlanEntry: Identifiable {
    let id: String
    let item: MediaItem
    /// 网格里显示的位次编号（仅 App 内辅助查看选中顺序，不会写进画面）
    let number: Int
    /// 写入相册时使用的创建时间，决定相册里的先后
    let date: Date
}

struct ReorderPlan {
    /// 红底黄字分隔图的创建时间：比本批所有素材都新，所以在相册里排最前
    var separatorDate: Date
    var entries: [PlanEntry]
}
