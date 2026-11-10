import Foundation
import UIKit

enum Renderer {

    // MARK: - 红色分隔图（黄字日期时间）

    /// 每批素材最前面写一张：红底 + 黄字「分隔 · 批次起点 / 日期 / 时间 / 共 N 个素材」。
    /// 只生成这一张分隔图；图片与视频画面不做任何加工（不烧编号、不加角标）。
    static func separatorJPEG(count: Int, date: Date) -> Data {
        let size = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.78, green: 0.04, blue: 0.04, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            let yellow = UIColor(red: 1.0, green: 0.90, blue: 0.0, alpha: 1.0)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            func draw(_ text: String, font: UIFont, y: CGFloat) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: yellow,
                    .paragraphStyle: paragraph
                ]
                (text as NSString).draw(
                    in: CGRect(x: 0, y: y, width: size.width, height: font.lineHeight + 24),
                    withAttributes: attrs
                )
            }

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")
            timeFormatter.dateFormat = "HH:mm:ss"

            draw("分隔 · 批次起点", font: .systemFont(ofSize: 62, weight: .semibold), y: 610)
            draw(dateFormatter.string(from: date),
                 font: .monospacedDigitSystemFont(ofSize: 122, weight: .bold), y: 730)
            draw(timeFormatter.string(from: date),
                 font: .monospacedDigitSystemFont(ofSize: 122, weight: .bold), y: 890)
            draw("共 \(count) 个素材", font: .systemFont(ofSize: 54, weight: .medium), y: 1090)
        }

        return image.jpegData(compressionQuality: 0.92) ?? Data()
    }
}
