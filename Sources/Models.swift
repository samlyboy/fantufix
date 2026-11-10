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
    let number: Int
    let date: Date
}

struct ReorderPlan {
    var separatorDate: Date
    var entries: [PlanEntry]
}
