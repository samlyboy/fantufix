import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import UIKit

/// 给视频右上角烧数字角标 + 裁掉开头 N 秒（必须重编码，一次导出两件事一起做）
enum VideoBadger {

    /// - Parameter trimSeconds: 裁掉开头多少秒；0 = 不裁。视频太短（剩余不足 0.3 秒）时自动不裁。
    static func export(asset: AVAsset, number: Int, trimSeconds: Double, to outputURL: URL) async throws {
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else {
            throw LibraryError.noVideoTrack
        }

        let duration = asset.duration
        guard duration.isValid, duration.seconds > 0 else {
            throw LibraryError.exportFailed("视频时长为 0")
        }

        // 裁头：剩余时长不足 0.3 秒就不裁（避免切出空视频）
        var trim = max(0, trimSeconds)
        if trim > 0 && duration.seconds - trim < 0.3 { trim = 0 }
        let start = CMTime(seconds: trim, preferredTimescale: 600)
        let range = CMTimeRange(start: start, end: duration)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw LibraryError.exportFailed("创建视频轨道失败")
        }
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)

        if let sourceAudio = asset.tracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
        }

        // 角标素材（1024 边长，足够任意分辨率使用）
        guard let badgeCG = Renderer.badgeImage(number: number, diameter: 1024).cgImage else {
            throw LibraryError.renderFailed
        }
        let badgeCI = CIImage(cgImage: badgeCG)

        let videoComposition = AVMutableVideoComposition(asset: composition) { request in
            let source = request.sourceImage
            let extent = source.extent
            guard extent.width > 1, extent.height > 1 else {
                request.finish(with: source, context: nil)
                return
            }

            let side = min(extent.width, extent.height)
            let diameter = side * 0.155
            let margin = side * 0.032

            let scale = diameter / badgeCI.extent.width
            // CoreImage 坐标原点在左下角：右上角 = (maxX - 直径 - 边距, maxY - 直径 - 边距)
            let placed = badgeCI
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(
                    translationX: extent.maxX - margin - diameter,
                    y: extent.maxY - margin - diameter
                ))

            let composited = placed.composited(over: source)
            request.finish(with: composited.cropped(to: extent), context: nil)
        }

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw LibraryError.exportFailed("创建导出会话失败")
        }

        try? FileManager.default.removeItem(at: outputURL)
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = false
        // composition 里已经从 .zero 起插入（已裁掉开头），导出整段即可
        session.timeRange = CMTimeRange(start: .zero, duration: range.duration)

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    c.resume()
                case .cancelled:
                    c.resume(throwing: LibraryError.cancelled)
                default:
                    c.resume(throwing: LibraryError.exportFailed(
                        session.error?.localizedDescription ?? "未知错误"
                    ))
                }
            }
        }
    }
}
