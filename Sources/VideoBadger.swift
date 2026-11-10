import Foundation
import AVFoundation

/// 视频只做「裁掉开头 N 秒」这一件事。
/// 输出画面保持原样：不烧编号、不加角标、不加任何标记。
enum VideoBadger {

    /// - Parameter trimSeconds: 裁掉开头多少秒；0 = 不裁，仅做一次无改动的导出。
    ///   视频太短（剩余不足 0.3 秒）时自动不裁（避免切出空视频）。
    static func export(asset: AVAsset, trimSeconds: Double, to outputURL: URL) async throws {
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else {
            throw LibraryError.noVideoTrack
        }

        let duration = asset.duration
        guard duration.isValid, duration.seconds > 0 else {
            throw LibraryError.exportFailed("视频时长为 0")
        }

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

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw LibraryError.exportFailed("创建导出会话失败")
        }

        try? FileManager.default.removeItem(at: outputURL)
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false
        // 不设置 videoComposition：画面一层不改，只保留裁头后的时间段
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
