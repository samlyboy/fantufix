import Foundation
import SwiftUI
import AVFoundation

final class ReorderRunner: ObservableObject {
    @Published var isRunning = false
    @Published var status = ""
    @Published var fraction: Double = 0
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var showAlert = false

    @MainActor
    func run(plan: ReorderPlan, trimSeconds: Double = 0) async {
        guard !isRunning else { return }
        isRunning = true
        fraction = 0
        defer { isRunning = false }

        guard await LibraryService.ensureAccess() else {
            status = ""
            alertTitle = "没有相册权限"
            alertMessage = "请到「设置 → 返图修复集合 → 照片」，选「完全访问」后重试。"
            showAlert = true
            return
        }

        let total = Double(plan.entries.count)
        var done: Double = 0
        var failures: [String] = []

        for (index, entry) in plan.entries.enumerated() {
            let trimNote = entry.item.kind == .video && trimSeconds > 0
                ? " · 裁头 \(String(format: "%.2f", trimSeconds))s"
                : ""
            status = "处理中 \(index + 1) / \(plan.entries.count)（第 \(entry.number) 个 · \(entry.item.kind.short)\(trimNote)）"
            do {
                switch entry.item.kind {
                case .image:
                    // 原图字节直写相册：不解码、不重编码、不烧编号、不加任何标记
                    let source = try await LibraryService.imageData(for: entry.item.id)
                    guard !source.isEmpty else { throw LibraryError.assetMissing }
                    try await LibraryService.savePhoto(
                        data: source,
                        creationDate: entry.date,
                        filename: "reorder_\(entry.number).jpg"
                    )
                case .video:
                    let asset = try await LibraryService.avAsset(for: entry.item.id)
                    // 不裁头时把原视频文件原样写进相册；拿不到本地文件才做一次无标记导出
                    if trimSeconds <= 0, let urlAsset = asset as? AVURLAsset {
                        try await LibraryService.saveVideo(
                            fileURL: urlAsset.url,
                            creationDate: entry.date,
                            filename: "reorder_\(entry.number).mp4"
                        )
                    } else {
                        let tmp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("reorder_\(entry.number)_\(UUID().uuidString).mp4")
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        try await VideoBadger.export(
                            asset: asset,
                            trimSeconds: trimSeconds,
                            to: tmp
                        )
                        try await LibraryService.saveVideo(
                            fileURL: tmp,
                            creationDate: entry.date,
                            filename: "reorder_\(entry.number).mp4"
                        )
                    }
                }
            } catch {
                failures.append("第 \(entry.number) 个（\(entry.item.kind.short)）：\(error.localizedDescription)")
            }
            done += 1
            fraction = done / total
        }

        status = "完成"
        fraction = 1

        let successCount = plan.entries.count - failures.count
        alertTitle = failures.isEmpty ? "重排完成" : "部分完成"
        if failures.isEmpty {
            alertMessage = "已写入 \(successCount) 个新文件到系统相册，画面保持原样（不烧编号、不写分隔图）。原片未改动。"
        } else {
            alertMessage = "成功 \(successCount) 个，失败 \(failures.count) 个：\n"
                + failures.prefix(6).joined(separator: "\n")
        }
        showAlert = true
    }
}
