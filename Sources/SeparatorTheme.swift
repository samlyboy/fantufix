import Foundation
import UIKit

/// 分隔图配色：只决定每批最前面那张分隔图的底色与字色。
/// 图片、视频画面不受影响（不烧编号、不加角标）。
struct SeparatorTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: UIColor
    let foreground: UIColor

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0)
    }

    /// 第一项即默认：红色底黄色字
    static let all: [SeparatorTheme] = [
        SeparatorTheme(id: "red_yellow",   name: "红色底黄色字",   background: rgb(0xC71212), foreground: rgb(0xFFE600)),
        SeparatorTheme(id: "yellow_black", name: "黄色底黑色字",   background: rgb(0xFFE600), foreground: rgb(0x000000)),
        SeparatorTheme(id: "red_white",    name: "红色底白色字",   background: rgb(0xC71212), foreground: rgb(0xFFFFFF)),
        SeparatorTheme(id: "black_white",  name: "黑色底白色字",   background: rgb(0x000000), foreground: rgb(0xFFFFFF)),
        SeparatorTheme(id: "black_yellow", name: "黑色底黄色字",   background: rgb(0x000000), foreground: rgb(0xFFE600)),
        SeparatorTheme(id: "white_black",  name: "白色底黑色字",   background: rgb(0xFFFFFF), foreground: rgb(0x000000)),
        SeparatorTheme(id: "blue_white",   name: "蓝色底白色字",   background: rgb(0x1565C0), foreground: rgb(0xFFFFFF)),
        SeparatorTheme(id: "green_white",  name: "绿色底白色字",   background: rgb(0x2E7D32), foreground: rgb(0xFFFFFF)),
        SeparatorTheme(id: "orange_black", name: "橙色底黑色字",   background: rgb(0xFF9800), foreground: rgb(0x000000)),
        SeparatorTheme(id: "purple_yellow", name: "紫色底黄色字",  background: rgb(0x6A1B9A), foreground: rgb(0xFFE600)),
        SeparatorTheme(id: "navy_yellow",  name: "深蓝色底黄色字", background: rgb(0x0D47A1), foreground: rgb(0xFFE600)),
        SeparatorTheme(id: "rose_white",   name: "玫红色底白色字", background: rgb(0xC2185B), foreground: rgb(0xFFFFFF))
    ]

    static let defaultTheme = all[0]

    /// 找不到（比如旧版本存过别的 id）就回落到默认配色
    static func withID(_ raw: String) -> SeparatorTheme {
        all.first { $0.id == raw } ?? defaultTheme
    }
}
