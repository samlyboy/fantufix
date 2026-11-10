import Foundation
import Photos
import UIKit
import AVFoundation

enum LibraryError: LocalizedError {
    case denied
    case assetMissing
    case noVideoTrack
    case renderFailed
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .denied: return "没有相册权限"
        case .assetMissing: return "素材已不在相册中"
        case .noVideoTrack: return "视频没有可用画面轨道"
        case .renderFailed: return "图片渲染失败"
        case .exportFailed(let msg): return "导出失败：\(msg)"
        case .cancelled: return "已取消"
        }
    }
}

/// 保证 continuation 只被 resume 一次（Photos 的回调可能触发多次）
final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

enum LibraryService {

    // MARK: - 权限

    static func ensureAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                    c.resume(returning: s)
                }
            }
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    // MARK: - 读取

    static func fetchItems(ids: [String]) -> [MediaItem] {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }

        let items: [MediaItem] = assets.map { asset in
            let kind: MediaKind = asset.mediaType == .video ? .video : .image
            return MediaItem(
                id: asset.localIdentifier,
                kind: kind,
                creationDate: asset.creationDate ?? asset.modificationDate ?? Date(),
                thumb: nil,
                pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                duration: asset.duration
            )
        }
        return items.sorted { $0.creationDate < $1.creationDate }
    }

    static func thumbnail(for id: String, size: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let once = ResumeOnce()
        return await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if once.claim() { c.resume(returning: image) }
            }
        }
    }

    static func imageData(for id: String) async throws -> Data {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw LibraryError.assetMissing
        }
        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard once.claim() else { return }
                if let data {
                    c.resume(returning: data)
                } else {
                    c.resume(throwing: LibraryError.assetMissing)
                }
            }
        }
    }

    static func avAsset(for id: String) async throws -> AVAsset {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw LibraryError.assetMissing
        }
        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<AVAsset, Error>) in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard once.claim() else { return }
                if let avAsset {
                    c.resume(returning: avAsset)
                } else {
                    c.resume(throwing: LibraryError.assetMissing)
                }
            }
        }
    }

    // MARK: - 写入

    static func savePhoto(data: Data, creationDate: Date, filename: String) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = creationDate
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = filename
                request.addResource(with: .photo, data: data, options: options)
            }, completionHandler: { success, error in
                if success {
                    c.resume()
                } else {
                    c.resume(throwing: error ?? LibraryError.renderFailed)
                }
            })
        }
    }

    static func saveVideo(fileURL: URL, creationDate: Date, filename: String) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = creationDate
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = filename
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: fileURL, options: options)
            }, completionHandler: { success, error in
                if success {
                    c.resume()
                } else {
                    c.resume(throwing: error ?? LibraryError.exportFailed("保存到相册失败"))
                }
            })
        }
    }
}
