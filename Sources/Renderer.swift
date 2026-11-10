import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

enum Renderer {

    // MARK: - 角标

    /// 右上角圆形数字角标
    static func badgeImage(number: Int, diameter: CGFloat) -> UIImage {
        let side = max(24, diameter)
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.86, green: 0.11, blue: 0.11, alpha: 0.92).cgColor)
            cg.fillEllipse(in: rect)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(max(2, side * 0.055))
            cg.strokeEllipse(in: rect.insetBy(dx: side * 0.035, dy: side * 0.035))

            let text = "\(number)"
            let scale: CGFloat = text.count >= 3 ? 0.40 : (text.count == 2 ? 0.50 : 0.58)
            let font = UIFont.systemFont(ofSize: side * scale, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let string = text as NSString
            let size = string.size(withAttributes: attrs)
            string.draw(
                at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2),
                withAttributes: attrs
            )
        }
    }

    // MARK: - 红色分隔图（黄字日期时间）

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

    // MARK: - 图片烧角标 + 重写 EXIF 拍摄时间

    static func imageJPEGWithBadge(source: Data, number: Int, date: Date) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
              let originalProps = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let uiImage = UIImage(data: source) else {
            return nil
        }

        var width = uiImage.size.width
        var height = uiImage.size.height
        guard width > 1, height > 1 else { return nil }

        // 超大图（如 48MP）先限长边，避免内存爆掉
        let maxSide: CGFloat = 4096
        let ratio = min(1, maxSide / max(width, height))
        width = (width * ratio).rounded()
        height = (height * ratio).rounded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            uiImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            let side = min(width, height)
            let diameter = side * 0.155
            let margin = side * 0.032
            let badge = badgeImage(number: number, diameter: diameter)
            badge.draw(in: CGRect(x: width - margin - diameter, y: margin, width: diameter, height: diameter))
        }

        guard let cgImage = rendered.cgImage else { return nil }

        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.timeZone = TimeZone.current
        stampFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let stamp = stampFormatter.string(from: date)

        var props = originalProps
        props[kCGImagePropertyOrientation as String] = 1
        props[kCGImagePropertyPixelWidth as String] = Int(width)
        props[kCGImagePropertyPixelHeight as String] = Int(height)

        var exif = (props[kCGImagePropertyExifDictionary as String] as? [String: Any]) ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal as String] = stamp
        exif[kCGImagePropertyExifDateTimeDigitized as String] = stamp
        exif[kCGImagePropertyExifPixelXDimension as String] = Int(width)
        exif[kCGImagePropertyExifPixelYDimension as String] = Int(height)
        props[kCGImagePropertyExifDictionary as String] = exif

        var tiff = (props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFDateTime as String] = stamp
        props[kCGImagePropertyTIFFDictionary as String] = tiff

        props[kCGImageDestinationLossyCompressionQuality as String] = 0.95

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
