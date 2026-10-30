import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

// MARK: - スタッフの似顔絵（HOTEL-SHIFT のアバターを移したもの）
// 輪郭・髪型・目・服などを選んで描き、PNG にしてスタッフの写真に入れる。選んだ内容は PNG の中に残すので、あとから直せる。
// 「写真から似せる」は端末の中（Vision）で顔の形と肌の色の目安を読むだけで、写真をどこにも送らない。

// Original vector avatar. The same renderer is used for preview and stored PNG.
struct StaffAvatarConfiguration: Equatable, Codable {
    var dimensional: Bool { false }
    var clothing = "シンプル"
    var nose = "ふつう"
    var hijabColor: Int? = nil
    var eyeScale: Double = 1
    var eyeSpacing: Double = 1
    var mouthScale: Double = 1
    var skin = 1
    var face = "まるい"
    var hairColor = 0
    var hair = "ショート"
    var expression = "笑顔"
    var eyes = "ふつう"
    var eyebrows = "ふつう"
    var beard = "なし"
    var accessory = "なし"
    var glassesShape = "スクエア"
    var glasses = false
    var background = 0
    var outfit = 0
}

enum StaffAvatarDrawing {
    static let storedSize: CGFloat = 240
    static let skins: [UIColor] = [UIColor(red: 1, green: 0.85, blue: 0.71, alpha: 1), UIColor(red: 0.90, green: 0.68, blue: 0.49, alpha: 1), UIColor(red: 0.67, green: 0.43, blue: 0.29, alpha: 1), UIColor(red: 0.39, green: 0.25, blue: 0.19, alpha: 1), UIColor(red: 1, green: 0.92, blue: 0.84, alpha: 1), UIColor(red: 0.96, green: 0.76, blue: 0.62, alpha: 1), UIColor(red: 0.76, green: 0.54, blue: 0.37, alpha: 1), UIColor(red: 0.49, green: 0.32, blue: 0.23, alpha: 1), UIColor(red: 0.98, green: 0.82, blue: 0.69, alpha: 1), UIColor(red: 0.84, green: 0.61, blue: 0.45, alpha: 1), UIColor(red: 0.72, green: 0.46, blue: 0.32, alpha: 1), UIColor(red: 0.58, green: 0.37, blue: 0.26, alpha: 1), UIColor(red: 0.94, green: 0.73, blue: 0.57, alpha: 1), UIColor(red: 0.99, green: 0.89, blue: 0.77, alpha: 1), UIColor(red: 0.45, green: 0.29, blue: 0.21, alpha: 1), UIColor(red: 0.33, green: 0.21, blue: 0.17, alpha: 1)]
    static let hairs: [UIColor] = [UIColor(white: 0.12, alpha: 1), UIColor(red: 0.36, green: 0.21, blue: 0.13, alpha: 1), UIColor(red: 0.79, green: 0.59, blue: 0.26, alpha: 1), UIColor(white: 0.65, alpha: 1), UIColor(red: 0.59, green: 0.28, blue: 0.16, alpha: 1), UIColor(red: 0.96, green: 0.86, blue: 0.64, alpha: 1), UIColor(red: 0.38, green: 0.27, blue: 0.50, alpha: 1), UIColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 1), UIColor(red: 0.16, green: 0.11, blue: 0.09, alpha: 1), UIColor(red: 0.45, green: 0.3, blue: 0.2, alpha: 1), UIColor(red: 0.68, green: 0.46, blue: 0.27, alpha: 1), UIColor(red: 0.74, green: 0.34, blue: 0.22, alpha: 1), UIColor(red: 0.3, green: 0.34, blue: 0.39, alpha: 1), UIColor(red: 0.18, green: 0.35, blue: 0.35, alpha: 1), UIColor(red: 0.72, green: 0.44, blue: 0.58, alpha: 1), UIColor(red: 0.94, green: 0.8, blue: 0.64, alpha: 1)]
    static let backgrounds: [UIColor] = [UIColor(red: 0.83, green: 0.91, blue: 1, alpha: 1), UIColor(red: 0.87, green: 0.94, blue: 0.84, alpha: 1), UIColor(red: 1, green: 0.87, blue: 0.86, alpha: 1), UIColor(red: 0.92, green: 0.86, blue: 0.98, alpha: 1), UIColor(red: 1, green: 0.95, blue: 0.76, alpha: 1), UIColor(red: 0.78, green: 0.94, blue: 0.93, alpha: 1), UIColor(red: 0.98, green: 0.85, blue: 0.93, alpha: 1), UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1), UIColor(red: 0.98, green: 0.92, blue: 0.86, alpha: 1), UIColor(red: 0.84, green: 0.96, blue: 0.98, alpha: 1), UIColor(red: 0.95, green: 0.94, blue: 0.86, alpha: 1), UIColor(red: 0.92, green: 0.94, blue: 0.98, alpha: 1), UIColor(red: 0.87, green: 0.82, blue: 0.76, alpha: 1), UIColor(red: 0.74, green: 0.87, blue: 0.82, alpha: 1), UIColor(red: 0.9, green: 0.81, blue: 0.83, alpha: 1), UIColor(red: 0.76, green: 0.83, blue: 0.95, alpha: 1)]
    static let outfits: [UIColor] = [UIColor(red: 0.12, green: 0.28, blue: 0.46, alpha: 1), UIColor(red: 0.21, green: 0.48, blue: 0.40, alpha: 1), UIColor(red: 0.70, green: 0.28, blue: 0.26, alpha: 1), UIColor(red: 0.47, green: 0.30, blue: 0.62, alpha: 1), UIColor(red: 0.85, green: 0.57, blue: 0.19, alpha: 1), UIColor(red: 0.18, green: 0.57, blue: 0.65, alpha: 1), UIColor(red: 0.32, green: 0.34, blue: 0.38, alpha: 1), UIColor(red: 0.91, green: 0.87, blue: 0.79, alpha: 1), UIColor(red: 0.18, green: 0.23, blue: 0.32, alpha: 1), UIColor(red: 0.81, green: 0.4, blue: 0.57, alpha: 1), UIColor(red: 0.64, green: 0.7, blue: 0.3, alpha: 1), UIColor(red: 0.38, green: 0.58, blue: 0.78, alpha: 1), UIColor(red: 0.82, green: 0.47, blue: 0.23, alpha: 1), UIColor(red: 0.44, green: 0.31, blue: 0.21, alpha: 1), UIColor(red: 0.9, green: 0.9, blue: 0.88, alpha: 1), UIColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1)]
    static let hairStyles = ["ショート", "ロング", "カール", "ボブ", "前髪", "センター分け", "おだんご", "ベリーショート", "マッシュ", "サイド分け", "外はね", "ウェーブ", "ポニーテール", "ツインテール", "三つ編み", "モヒカン", "アフロ", "刈り上げ", "ぱっつん", "なし"]
    static let faces = ["まるい", "すっきり", "面長", "ふっくら", "たまご型", "四角", "逆三角", "小顔"]
    static let expressions = ["笑顔", "おだやか", "ウインク", "にっこり", "びっくり", "大笑い", "への字", "にやり", "口を結ぶ"]
    static let eyeStyles = ["ふつう", "まるい", "細め", "にこにこ", "ぱっちり", "たれ目", "つり目", "まつげ"]
    static let browStyles = ["ふつう", "太め", "きりっと", "アーチ", "細い", "困り眉"]
    static let beardStyles = ["なし", "口ひげ", "あごひげ", "無精ひげ", "フル", "ちょびひげ"]
    static let accessories = ["なし", "ピアス", "ヘアピン", "リボン", "ヘッドバンド", "そばかす", "ヒジャブ"]
    static let glassesStyles = ["スクエア", "まる", "サングラス", "細フレーム", "ハーフリム", "大きめ"]
    static let clothes = ["シンプル", "スーツ", "シャツ", "ポロシャツ", "ボーダー"]
    static let noses = ["ふつう", "小さめ", "まるい", "すっきり"]
    static func png(_ configuration: StaffAvatarConfiguration) -> Data? {
        // スタッフの写真と同じ 240px（iCloud 同期・バックアップに入るので小さく）
        guard let image = render(configuration, size: StaffAvatarDrawing.storedSize).cgImage,
              let json = try? JSONEncoder().encode(configuration),
              let text = String(data: json, encoding: .utf8) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let properties: [String: Any] = [kCGImagePropertyPNGDictionary as String: ["Description": "hotelshift-avatar-v1:" + text]]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
    static func restored(from data: Data?) -> StaffAvatarConfiguration? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any],
              let text = png["Description"] as? String,
              text.hasPrefix("hotelshift-avatar-v1:"), text.utf8.count < 16000,
              let json = String(text.dropFirst("hotelshift-avatar-v1:".count)).data(using: .utf8),
              var value = try? JSONDecoder().decode(StaffAvatarConfiguration.self, from: json) else { return nil }
        value.skin = min(skins.count - 1, max(0, value.skin))
        value.hairColor = min(hairs.count - 1, max(0, value.hairColor))
        value.background = min(backgrounds.count - 1, max(0, value.background))
        value.outfit = min(outfits.count - 1, max(0, value.outfit))
        if let color = value.hijabColor { value.hijabColor = min(outfits.count - 1, max(0, color)) }
        value.eyeScale = value.eyeScale.isFinite ? min(1.3, max(0.8, value.eyeScale)) : 1
        value.eyeSpacing = value.eyeSpacing.isFinite ? min(1.15, max(0.85, value.eyeSpacing)) : 1
        value.mouthScale = value.mouthScale.isFinite ? min(1.2, max(0.8, value.mouthScale)) : 1
        return value
    }
    static func render(_ c: StaffAvatarConfiguration, size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let g = context.cgContext
            g.scaleBy(x: size / 320, y: size / 320)
            func mixed(_ color: UIColor, white: CGFloat) -> UIColor {
                var r: CGFloat = 0, green: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                color.getRed(&r, green: &green, blue: &b, alpha: &a)
                return UIColor(red: r + (1-r)*white, green: green + (1-green)*white, blue: b + (1-b)*white, alpha: a)
            }
            func shaded(_ path: UIBezierPath, _ color: UIColor) {
                guard c.dimensional else { color.setFill(); path.fill(); return }
                g.saveGState(); path.addClip()
                let colors = [mixed(color, white: 0.22).cgColor, color.cgColor, color.withAlphaComponent(1).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1]) {
                    let bounds = path.bounds
                    g.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: bounds.minY), end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    g.setBlendMode(.multiply)
                    let shade = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.2).cgColor] as CFArray
                    if let shadow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shade, locations: [0, 1]) {
                        g.drawLinearGradient(shadow, start: CGPoint(x: bounds.midX, y: bounds.midY), end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: .drawsAfterEndLocation)
                    }
                }
                g.restoreGState()
            }
            func ellipse(_ rect: CGRect, _ color: UIColor) { shaded(UIBezierPath(ovalIn: rect), color) }
            func stroke(_ points: [CGPoint], color: UIColor, width: CGFloat) {
                guard let first = points.first else { return }
                let p = UIBezierPath(); p.move(to: first)
                for point in points.dropFirst() { p.addLine(to: point) }
                p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round; color.setStroke(); p.stroke()
            }
            backgrounds[c.background].setFill(); g.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            let skin = skins[c.skin], hair = hairs[c.hairColor]
            let wearsHijab = c.accessory == "ヒジャブ"
            let fabric = outfits[c.hijabColor ?? c.outfit]
            let ink = UIColor(red: 0.16, green: 0.12, blue: 0.12, alpha: 1)
            if !wearsHijab {
            if c.hair == "ポニーテール" { ellipse(CGRect(x: 213, y: 104, width: 48, height: 146), hair) }
            if c.hair == "三つ編み" { for i in 0..<5 { ellipse(CGRect(x: 213 + (i % 2) * 8, y: 116 + i * 23, width: 34, height: 36), hair) } }
            if c.hair == "ツインテール" {
                for x in [CGFloat(51), CGFloat(221)] { ellipse(CGRect(x: x, y: 95, width: 48, height: 153), hair) }
            }
            if c.hair == "アフロ" { ellipse(CGRect(x: 59, y: 15, width: 202, height: 208), hair) }
            if c.hair == "ロング" { ellipse(CGRect(x: 75, y: 40, width: 170, height: 238), hair) }
            if c.hair == "ボブ" { ellipse(CGRect(x: 75, y: 43, width: 170, height: 185), hair) }
            if c.hair == "おだんご" { ellipse(CGRect(x: 127, y: 15, width: 66, height: 60), hair) }
            }
            ellipse(CGRect(x: 53, y: 238, width: 214, height: 160), outfits[c.outfit])
            if c.clothing == "ボーダー" {
                outfits[c.outfit].withAlphaComponent(0.4).setFill()
                for y in stride(from: 273, through: 315, by: 14) { UIColor.white.withAlphaComponent(0.55).setFill(); UIBezierPath(rect: CGRect(x: 90, y: y, width: 140, height: 5)).fill() }
            }
            if ["シャツ", "スーツ", "ポロシャツ"].contains(c.clothing) {
                let collar = UIBezierPath(); collar.move(to: CGPoint(x: 132, y: 251)); collar.addLine(to: CGPoint(x: 160, y: 278)); collar.addLine(to: CGPoint(x: 188, y: 251)); collar.addLine(to: CGPoint(x: 179, y: 297)); collar.addLine(to: CGPoint(x: 141, y: 297)); collar.close(); UIColor.white.setFill(); collar.fill()
                if c.clothing == "スーツ" { let tie = UIBezierPath(); tie.move(to: CGPoint(x: 160, y: 273)); tie.addLine(to: CGPoint(x: 168, y: 306)); tie.addLine(to: CGPoint(x: 160, y: 315)); tie.addLine(to: CGPoint(x: 152, y: 306)); tie.close(); UIColor.systemBlue.setFill(); tie.fill() }
                if c.clothing == "ポロシャツ" { stroke([CGPoint(x: 160, y: 279), CGPoint(x: 160, y: 311)], color: .white, width: 3) }
            }
            skin.setFill(); UIBezierPath(roundedRect: CGRect(x: 139, y: 218, width: 42, height: 48), cornerRadius: 16).fill()
            if !wearsHijab {
                ellipse(CGRect(x: 78, y: 130, width: 26, height: 41), skin)
                ellipse(CGRect(x: 216, y: 130, width: 26, height: 41), skin)
            } else {
                ellipse(CGRect(x: 69, y: 30, width: 182, height: 244), fabric)
                let drape = UIBezierPath(); drape.move(to: CGPoint(x: 84, y: 174))
                drape.addQuadCurve(to: CGPoint(x: 65, y: 289), controlPoint: CGPoint(x: 78, y: 254))
                drape.addQuadCurve(to: CGPoint(x: 255, y: 289), controlPoint: CGPoint(x: 160, y: 323))
                drape.addQuadCurve(to: CGPoint(x: 236, y: 174), controlPoint: CGPoint(x: 242, y: 254))
                drape.close(); fabric.setFill(); drape.fill()
                stroke([CGPoint(x: 104, y: 224), CGPoint(x: 136, y: 264), CGPoint(x: 214, y: 286)], color: UIColor.white.withAlphaComponent(0.18), width: 3)
            }
            let face: CGRect
            switch c.face {
            case "すっきり": face = CGRect(x: 99, y: 54, width: 122, height: 184)
            case "面長": face = CGRect(x: 100, y: 48, width: 120, height: 195)
            case "ふっくら": face = CGRect(x: 83, y: 66, width: 154, height: 170)
            case "たまご型": face = CGRect(x: 95, y: 60, width: 130, height: 179)
            case "四角": face = CGRect(x: 90, y: 65, width: 140, height: 171)
            case "逆三角": face = CGRect(x: 89, y: 57, width: 142, height: 181)
            case "小顔": face = CGRect(x: 104, y: 70, width: 112, height: 158)
            default: face = CGRect(x: 90, y: 66, width: 140, height: 170)
            }
            if c.face == "四角" {
                skin.setFill(); UIBezierPath(roundedRect: face, cornerRadius: 38).fill()
            } else if c.face == "逆三角" {
                let outline = UIBezierPath(); outline.move(to: CGPoint(x: 93, y: 112))
                outline.addCurve(to: CGPoint(x: 160, y: 238), controlPoint1: CGPoint(x: 85, y: 193), controlPoint2: CGPoint(x: 143, y: 235))
                outline.addCurve(to: CGPoint(x: 227, y: 112), controlPoint1: CGPoint(x: 177, y: 235), controlPoint2: CGPoint(x: 235, y: 193))
                outline.addCurve(to: CGPoint(x: 93, y: 112), controlPoint1: CGPoint(x: 235, y: 38), controlPoint2: CGPoint(x: 85, y: 38))
                outline.close(); skin.setFill(); outline.fill()
            } else { ellipse(face, skin) }
            if c.hair != "なし" && !wearsHijab {
                let p = UIBezierPath(); p.move(to: CGPoint(x: 92, y: 142))
                p.addCurve(to: CGPoint(x: 112, y: 54), controlPoint1: CGPoint(x: 75, y: 90), controlPoint2: CGPoint(x: 91, y: 63))
                p.addCurve(to: CGPoint(x: 229, y: 135), controlPoint1: CGPoint(x: 200, y: 12), controlPoint2: CGPoint(x: 250, y: 76))
                p.addLine(to: CGPoint(x: 214, y: 105))
                p.addQuadCurve(to: CGPoint(x: 122, y: 97), controlPoint: CGPoint(x: 180, y: 113))
                p.addLine(to: CGPoint(x: 92, y: 142)); p.close(); shaded(p, hair)
                if c.dimensional {
                    for offset in [CGFloat(0), 15, 30] {
                        let lock = UIBezierPath(); lock.move(to: CGPoint(x: 99 + offset * 0.3, y: 109 - offset * 0.7))
                        lock.addCurve(to: CGPoint(x: 211 - offset * 0.3, y: 80 - offset * 0.5), controlPoint1: CGPoint(x: 116, y: 35 - offset * 0.15), controlPoint2: CGPoint(x: 180, y: 42 - offset * 0.1))
                        lock.lineWidth = 12; lock.lineCapStyle = .round
                        mixed(hair, white: 0.1).setStroke(); lock.stroke()
                        lock.lineWidth = 2; mixed(hair, white: 0.2).setStroke(); lock.stroke()
                    }
                }
                if ["マッシュ", "ぱっつん", "前髪", "ボブ"].contains(c.hair) {
                    hair.setFill()
                    UIBezierPath(roundedRect: CGRect(x: 103, y: 76, width: 114, height: 47), cornerRadius: 13).fill()
                }
                if c.hair == "ベリーショート" || c.hair == "刈り上げ" {
                    skin.setFill(); UIBezierPath(roundedRect: CGRect(x: 105, y: 88, width: 110, height: 34), cornerRadius: 8).fill()
                }
                if c.hair == "モヒカン" { ellipse(CGRect(x: 144, y: 12, width: 38, height: 88), hair) }
                if c.hair == "外はね" {
                    for x in [CGFloat(75), CGFloat(219)] { ellipse(CGRect(x: x, y: 173, width: 29, height: 41), hair) }
                }
                if c.hair == "サイド分け" { stroke([CGPoint(x: 118, y: 62), CGPoint(x: 130, y: 88)], color: skin, width: 5) }
                if c.hair == "センター分け" {
                    stroke([CGPoint(x: 160, y: 59), CGPoint(x: 160, y: 93)], color: skin, width: 7)
                }
                if c.hair == "ウェーブ" {
                    for x in stride(from: 97, through: 202, by: 21) { ellipse(CGRect(x: CGFloat(x), y: 77, width: 35, height: 37), hair) }
                }
                if c.hair == "カール" {
                    for x in stride(from: 92, through: 212, by: 24) { ellipse(CGRect(x: CGFloat(x), y: CGFloat(49 + (x % 3) * 5), width: 39, height: 47), hair) }
                }
            }
            let browWidth: CGFloat = c.eyebrows == "太め" ? 7 : c.eyebrows == "細い" ? 2 : 4
            let rise: CGFloat = c.eyebrows == "きりっと" ? 6 : 0
            if c.eyebrows == "アーチ" || c.eyebrows == "困り眉" {
                let d: CGFloat = c.eyebrows == "アーチ" ? -8 : 8
                stroke([CGPoint(x: 115, y: 130), CGPoint(x: 126, y: 126 + d), CGPoint(x: 137, y: 130)], color: hair, width: browWidth)
                stroke([CGPoint(x: 183, y: 130), CGPoint(x: 194, y: 126 + d), CGPoint(x: 205, y: 130)], color: hair, width: browWidth)
            } else {
            stroke([CGPoint(x: 115, y: 130 + rise), CGPoint(x: 137, y: 127)], color: hair, width: browWidth)
            stroke([CGPoint(x: 183, y: 127), CGPoint(x: 205, y: 130 + rise)], color: hair, width: browWidth)
            }
            for x in [CGFloat(160 - 35 * c.eyeSpacing), CGFloat(160 + 35 * c.eyeSpacing)] {
                if c.eyes == "にこにこ" || (c.expression == "ウインク" && x > 160) {
                    stroke([CGPoint(x: x - 8, y: 151), CGPoint(x: x, y: 145), CGPoint(x: x + 8, y: 151)], color: ink, width: 4)
                } else {
                    let width: CGFloat = (c.eyes == "まるい" ? 15 : c.eyes == "細め" ? 8 : 10) * CGFloat(c.eyeScale)
                    let height: CGFloat = (c.eyes == "細め" ? 8 : c.eyes == "まるい" ? 18 : 14) * CGFloat(c.eyeScale)
                    if ["たれ目", "つり目"].contains(c.eyes) {
                        let delta: CGFloat = c.eyes == "たれ目" ? 4 : -4
                        stroke([CGPoint(x: x - 7, y: 148 - delta), CGPoint(x: x + 7, y: 148 + delta)], color: ink, width: 4)
                    } else if c.eyes == "ぱっちり" || c.eyes == "まつげ" {
                        ellipse(CGRect(x: x - 8, y: 138, width: 16, height: 22), .white)
                        ellipse(CGRect(x: x - 5, y: 141, width: 10, height: 16), ink)
                        if c.eyes == "まつげ" { stroke([CGPoint(x: x - 8, y: 142), CGPoint(x: x - 13, y: 136)], color: ink, width: 2) }
                    } else if c.dimensional {
                        let w: CGFloat = (c.eyes == "細め" ? 28.0 : 36.0) * CGFloat(c.eyeScale)
                        let h: CGFloat = (c.eyes == "細め" ? 20.0 : 37.0) * CGFloat(c.eyeScale)
                        let rect = CGRect(x: x - w / 2, y: 150 - h / 2, width: w, height: h)
                        ellipse(rect.insetBy(dx: -1, dy: -2), skin.withAlphaComponent(0.6))
                        ellipse(rect, .white)
                        ellipse(CGRect(x: x - w * 0.28, y: 150 - h * 0.45, width: w * 0.56, height: h * 0.9), UIColor(red: 0.22, green: 0.13, blue: 0.09, alpha: 1))
                        ellipse(CGRect(x: x - w * 0.16, y: 150 - h * 0.28, width: w * 0.32, height: h * 0.56), ink)
                        ellipse(CGRect(x: x - 3, y: 140, width: 6, height: 7), .white)
                    } else {
                        ellipse(CGRect(x: x - width / 2, y: 150 - height / 2, width: width, height: height), ink)
                    }
                }
            }
            if c.dimensional {
                ellipse(CGRect(x: 148, y: 166, width: 25, height: 21), skin)
                ellipse(CGRect(x: 107, y: 172, width: 22, height: 10), UIColor.systemPink.withAlphaComponent(0.08))
                ellipse(CGRect(x: 192, y: 172, width: 22, height: 10), UIColor.systemPink.withAlphaComponent(0.08))
            } else {
                if c.nose == "まるい" { ellipse(CGRect(x: 153, y: 165, width: 14, height: 12), ink.withAlphaComponent(0.18)) }
                else {
                    let length: CGFloat = c.nose == "小さめ" ? 12 : c.nose == "すっきり" ? 26 : 23
                    stroke([CGPoint(x: 160, y: 153), CGPoint(x: 154, y: 153 + length), CGPoint(x: 165, y: 153 + length)], color: ink.withAlphaComponent(0.35), width: c.nose == "すっきり" ? 2 : 3)
                }
            }
            g.saveGState()
            g.translateBy(x: 160, y: 199); g.scaleBy(x: CGFloat(c.mouthScale), y: 1); g.translateBy(x: -160, y: -199)
            if c.expression == "への字" {
                stroke([CGPoint(x: 144, y: 204), CGPoint(x: 160, y: 194), CGPoint(x: 176, y: 204)], color: ink, width: 4)
            } else if c.expression == "口を結ぶ" {
                stroke([CGPoint(x: 151, y: 198), CGPoint(x: 169, y: 198)], color: ink, width: 3)
            } else if c.expression == "にやり" {
                stroke([CGPoint(x: 143, y: 199), CGPoint(x: 166, y: 202), CGPoint(x: 180, y: 191)], color: ink, width: 4)
            } else if c.expression == "大笑い" {
                ellipse(CGRect(x: 138, y: 187, width: 44, height: 31), ink)
                UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 143, y: 188, width: 34, height: 8), cornerRadius: 3).fill()
            } else if c.expression == "おだやか" {
                stroke([CGPoint(x: 145, y: 199), CGPoint(x: 175, y: 199)], color: ink, width: 4)
            } else if c.expression == "びっくり" {
                ellipse(CGRect(x: 150, y: 188, width: 20, height: 25), ink)
            } else if c.expression == "にっこり" {
                ellipse(CGRect(x: 139, y: 187, width: 42, height: 25), ink)
                UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 143, y: 188, width: 34, height: 8), cornerRadius: 3).fill()
            } else {
                let p = UIBezierPath(); p.move(to: CGPoint(x: 140, y: 191))
                p.addQuadCurve(to: CGPoint(x: 180, y: 191), controlPoint: CGPoint(x: 160, y: 218))
                p.lineWidth = 4; p.lineCapStyle = .round; ink.setStroke(); p.stroke()
            }
            g.restoreGState()
            if c.beard == "フル" { stroke([CGPoint(x: 119, y: 199), CGPoint(x: 134, y: 223), CGPoint(x: 160, y: 232), CGPoint(x: 186, y: 223), CGPoint(x: 201, y: 199)], color: hair, width: 10) }
            if c.beard == "無精ひげ" { for x in stride(from: 136, through: 184, by: 8) { stroke([CGPoint(x: x, y: 218), CGPoint(x: x - 2, y: 223)], color: hair, width: 1) } }
            if c.beard == "ちょびひげ" { stroke([CGPoint(x: 154, y: 183), CGPoint(x: 166, y: 183)], color: hair, width: 5) }
            if c.beard == "口ひげ" {
                ellipse(CGRect(x: 140, y: 181, width: 22, height: 8), hair)
                ellipse(CGRect(x: 158, y: 181, width: 22, height: 8), hair)
            } else if c.beard == "あごひげ" {
                ellipse(CGRect(x: 144, y: 215, width: 32, height: 17), hair)
            }
            if c.accessory == "リボン" { ellipse(CGRect(x: 100, y: 69, width: 25, height: 17), .systemPink); ellipse(CGRect(x: 121, y: 69, width: 25, height: 17), .systemPink) }
            if c.accessory == "ヘッドバンド" { stroke([CGPoint(x: 100, y: 103), CGPoint(x: 130, y: 85), CGPoint(x: 188, y: 85), CGPoint(x: 220, y: 103)], color: outfits[c.outfit], width: 9) }
            if c.accessory == "そばかす" { for x in [112, 121, 130, 190, 199, 208] { ellipse(CGRect(x: x, y: x % 2 == 0 ? 169 : 174, width: 2, height: 2), .brown) } }
            if c.accessory == "ピアス" {
                for x in [CGFloat(89), CGFloat(231)] { ellipse(CGRect(x: x - 4, y: 161, width: 8, height: 11), .systemYellow) }
            } else if c.accessory == "ヘアピン" {
                stroke([CGPoint(x: 105, y: 99), CGPoint(x: 127, y: 87)], color: .systemPink, width: 7)
            }
            if c.glasses {
                for x in [CGFloat(107), CGFloat(177)] {
                    let rect = CGRect(x: x, y: 137, width: 37, height: 30)
                    let p = c.glassesShape == "まる" ? UIBezierPath(ovalIn: rect) : UIBezierPath(roundedRect: rect, cornerRadius: 6)
                    if c.glassesShape == "サングラス" { ink.withAlphaComponent(0.85).setFill(); p.fill() }
                    p.lineWidth = c.glassesShape == "細フレーム" ? 1.5 : 3; ink.setStroke(); p.stroke()
                    if c.glassesShape == "大きめ" { let outer = UIBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 9); outer.lineWidth = 2; outer.stroke() }
                    if c.glassesShape == "ハーフリム" { skin.setStroke(); let bottom = UIBezierPath(); bottom.move(to: CGPoint(x: x + 5, y: 167)); bottom.addLine(to: CGPoint(x: x + 32, y: 167)); bottom.lineWidth = 4; bottom.stroke() }
                }
                stroke([CGPoint(x: 144, y: 147), CGPoint(x: 177, y: 147)], color: ink, width: 3)
            }
        }
    }
}

struct StaffAvatarCreator: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: StaffAvatarConfiguration
    @State private var saveError = false
    @State private var copied = false
    @State private var sourceItem: PhotosPickerItem?
    @State private var analysing = false
    @State private var analysisError: String?
    @State private var analysisNotice: String?
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisRequest = UUID()
    let sourcePhoto: Data?
    let onUse: (StaffAvatarConfiguration, Data) -> Void
    init(initial: StaffAvatarConfiguration, sourcePhoto: Data?, onUse: @escaping (StaffAvatarConfiguration, Data) -> Void) {
        _configuration = State(initialValue: StaffAvatarDrawing.restored(from: sourcePhoto) ?? initial)
        self.sourcePhoto = sourcePhoto; self.onUse = onUse
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if usesSideBySide(in: geometry.size) {
                    HStack(spacing: 0) {
                        avatarPreview
                            .frame(width: min(420, max(180, geometry.size.width * 0.38)))
                        Divider()
                        settingsForm.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        avatarPreview.frame(height: min(330, geometry.size.height * 0.37))
                        Divider()
                        settingsForm.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onChange(of: sourceItem) { _, item in
                guard let item else { return }
                startAnalysis {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw StaffAvatarPhotoError.unreadable }
                    return data
                }
            }
            .onDisappear { analysisTask?.cancel(); analysisRequest = UUID() }
            .onChange(of: configuration) { _, _ in copied = false }
            .navigationTitle("アバターを作成").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("このアバターを使う") {
                        guard let data = StaffAvatarDrawing.png(configuration) else { saveError = true; return }
                        onUse(configuration, data); dismiss()
                    }.disabled(analysing)
                }
            }
            .alert("アバターを作成できません", isPresented: Binding(
                get: { analysisError != nil || saveError },
                set: { if !$0 { analysisError = nil; saveError = false } }
            )) {
                Button("OK", role: .cancel) { analysisError = nil; saveError = false }
            } message: { Text(analysisError ?? "画像を作成できませんでした。もう一度お試しください。") }
        }
    }
    private func usesSideBySide(in size: CGSize) -> Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad && size.width > size.height
        #endif
    }
    private var avatarPreview: some View {
        GeometryReader { geometry in
            let side = max(48, min(360, min(geometry.size.width - 32, geometry.size.height - 110)))
            VStack(spacing: 12) {
                Text("プレビュー").appFont(.headline)
                Image(uiImage: StaffAvatarDrawing.render(configuration, size: 640))
                    .resizable().scaledToFit().frame(width: side, height: side)
                    .clipShape(Circle())
                    .accessibilityLabel("作成中のアバター")
                Button {
                    guard let data = StaffAvatarDrawing.png(configuration) else { saveError = true; return }
                    UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
                    copied = true
                } label: {
                    Label(copied ? "画像をコピーしました" : "画像をコピー", systemImage: "doc.on.doc")
                        .frame(minHeight: 44)
                }.buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
    private var settingsForm: some View {
            Form {
                Section("写真から作成・端末内処理") {
                    PhotosPicker(selection: $sourceItem, matching: .images) {
                        Label("顔写真を選んでアバター化", systemImage: "person.crop.rectangle")
                    }.disabled(analysing)
                    if let sourcePhoto, StaffAvatarDrawing.restored(from: sourcePhoto) == nil {
                        Button("登録中の写真から作成") { startAnalysis { sourcePhoto } }.disabled(analysing)
                    }
                    if analysing { ProgressView("顔の特徴を読み取り中…") }
                    if let analysisNotice { Text(analysisNotice).appFont(.footnote).foregroundStyle(.secondary) }
                    Text("顔が1人、正面に写った写真を選んでください。輪郭・目・口と肌色の目安を反映します。写真をサーバーへ送信しません。髪型などは下で調整できます。")
                        .appFont(.footnote).foregroundStyle(.secondary)
                }.buttonStyle(.borderless)
                Section {
                    Button { randomize() } label: {
                        Label("おまかせで組み合わせる", systemImage: "shuffle")
                    }.buttonStyle(.borderless)
                }
                Section("顔と表情") {
                    VStack(alignment: .leading) {
                        Text("目の大きさ"); Slider(value: $configuration.eyeScale, in: 0.8...1.3)
                        Text("目の間隔"); Slider(value: $configuration.eyeSpacing, in: 0.85...1.15)
                        Text("口の幅"); Slider(value: $configuration.mouthScale, in: 0.8...1.2)
                    }
                    Picker("輪郭", selection: $configuration.face) {
                        ForEach(StaffAvatarDrawing.faces, id: \.self) { Text($0).tag($0) }
                    }
                    swatches("肌の色", colors: StaffAvatarDrawing.skins, selection: $configuration.skin)
                    Picker("表情", selection: $configuration.expression) {
                        ForEach(StaffAvatarDrawing.expressions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("鼻", selection: $configuration.nose) {
                        ForEach(StaffAvatarDrawing.noses, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("目", selection: $configuration.eyes) {
                        ForEach(StaffAvatarDrawing.eyeStyles, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("眉", selection: $configuration.eyebrows) {
                        ForEach(StaffAvatarDrawing.browStyles, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("ひげ", selection: $configuration.beard) {
                        ForEach(StaffAvatarDrawing.beardStyles, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("メガネ", isOn: $configuration.glasses)
                    if configuration.glasses {
                        Picker("メガネの形", selection: $configuration.glassesShape) {
                            ForEach(StaffAvatarDrawing.glassesStyles, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Picker("小物・かぶりもの", selection: $configuration.accessory) {
                        ForEach(StaffAvatarDrawing.accessories, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("髪") {
                    Picker("髪型", selection: $configuration.hair) {
                        ForEach(StaffAvatarDrawing.hairStyles, id: \.self) { Text($0).tag($0) }
                    }
                    swatches("髪の色", colors: StaffAvatarDrawing.hairs, selection: $configuration.hairColor)
                }.disabled(configuration.accessory == "ヒジャブ")
                if configuration.accessory == "ヒジャブ" {
                    Section("ヒジャブ") {
                        swatches("布の色", colors: StaffAvatarDrawing.outfits, selection: Binding(
                            get: { configuration.hijabColor ?? configuration.outfit },
                            set: { configuration.hijabColor = $0 }
                        ))
                    }
                }
                Section("服と背景") {
                    Picker("服装", selection: $configuration.clothing) {
                        ForEach(StaffAvatarDrawing.clothes, id: \.self) { Text($0).tag($0) }
                    }
                    swatches("服の色", colors: StaffAvatarDrawing.outfits, selection: $configuration.outfit)
                    swatches("背景色", colors: StaffAvatarDrawing.backgrounds, selection: $configuration.background)
                }
                Section {
                    Text("「このアバターを使う」でスタッフ写真に反映します。スタッフ情報の「保存」で登録が完了します。")
                        .appFont(.footnote).foregroundStyle(.secondary)
                }
            }
    }
    @MainActor private func startAnalysis(_ load: @escaping () async throws -> Data) {
        analysisTask?.cancel()
        let request = UUID(); analysisRequest = request
        analysing = true; analysisError = nil; analysisNotice = nil
        let original = configuration
        analysisTask = Task { @MainActor in
            defer { if analysisRequest == request { analysing = false; sourceItem = nil } }
            do {
                let bytes = try await load()
                let result = try await Task.detached(priority: .userInitiated) {
                    try StaffAvatarPhotoAnalysis.suggest(bytes, initial: original)
                }.value
                guard !Task.isCancelled, analysisRequest == request else { return }
                guard configuration == original else {
                    analysisNotice = "読み取り中に調整した内容を優先しました。写真から作り直す場合は再度選んでください。"
                    return
                }
                configuration = result
                analysisNotice = "写真から顔の特徴を反映しました。髪型・色・表情を確認して調整してください。"
            } catch {
                guard !Task.isCancelled, analysisRequest == request else { return }
                analysisError = (error as? StaffAvatarPhotoError)?.errorDescription ?? "写真を解析できませんでした。明るい場所で正面から写った写真をお試しください。"
            }
        }
    }
    private func randomize() {
        var next = StaffAvatarConfiguration()
        next.skin = Int.random(in: StaffAvatarDrawing.skins.indices)
        next.hairColor = Int.random(in: StaffAvatarDrawing.hairs.indices)
        next.background = Int.random(in: StaffAvatarDrawing.backgrounds.indices)
        next.outfit = Int.random(in: StaffAvatarDrawing.outfits.indices)
        next.face = StaffAvatarDrawing.faces.randomElement() ?? "まるい"
        next.hair = StaffAvatarDrawing.hairStyles.randomElement() ?? "ショート"
        next.expression = StaffAvatarDrawing.expressions.randomElement() ?? "笑顔"
        next.eyes = StaffAvatarDrawing.eyeStyles.randomElement() ?? "ふつう"
        next.eyebrows = StaffAvatarDrawing.browStyles.randomElement() ?? "ふつう"
        next.beard = StaffAvatarDrawing.beardStyles.randomElement() ?? "なし"
        next.accessory = StaffAvatarDrawing.accessories.randomElement() ?? "なし"
        next.hijabColor = Int.random(in: StaffAvatarDrawing.outfits.indices)
        next.clothing = StaffAvatarDrawing.clothes.randomElement() ?? "シンプル"
        next.nose = StaffAvatarDrawing.noses.randomElement() ?? "ふつう"
        next.glasses = Bool.random()
        next.glassesShape = StaffAvatarDrawing.glassesStyles.randomElement() ?? "スクエア"
        configuration = next
    }
    private func swatches(_ title: String, colors: [UIColor], selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(colors.indices, id: \.self) { index in
                    Button { selection.wrappedValue = index } label: {
                        Circle().fill(Color(uiColor: colors[index])).frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2)))
                            .overlay { if selection.wrappedValue == index { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .black) } }
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(title) \(index + 1)")
                        .accessibilityAddTraits(selection.wrappedValue == index ? .isSelected : [])
                }
            }
        }
    }
}

private enum StaffAvatarPhotoError: LocalizedError {
    case unreadable, noFace, multipleFaces, missingFeatures
    var errorDescription: String? {
        switch self {
        case .unreadable: return "画像を読み込めませんでした。別の写真を選んでください。"
        case .noFace: return "顔が見つかりませんでした。正面の顔が大きく写った写真を選んでください。"
        case .multipleFaces: return "複数の顔が見つかりました。1人だけ写った写真を選んでください。"
        case .missingFeatures: return "目や口を十分に読み取れませんでした。明るく、正面に近い写真を選んでください。"
        }
    }
}

private enum StaffAvatarPhotoAnalysis {
    // Vision and pixel sampling run locally; this path has no network calls.
    static func suggest(_ data: Data, initial: StaffAvatarConfiguration) throws -> StaffAvatarConfiguration {
        guard let image = thumbnail(data, maxPixels: 1200) else { throw StaffAvatarPhotoError.unreadable }
        let request = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { throw StaffAvatarPhotoError.noFace }
        guard faces.count == 1, let face = faces.first else { throw StaffAvatarPhotoError.multipleFaces }
        guard let features = face.landmarks,
              let left = features.leftEye, let right = features.rightEye,
              let lips = features.outerLips,
              left.pointCount >= 2, right.pointCount >= 2, lips.pointCount >= 4 else { throw StaffAvatarPhotoError.missingFeatures }
        func bounds(_ region: VNFaceLandmarkRegion2D) -> CGRect {
            let points = region.normalizedPoints
            let xs = points.map { CGFloat($0.x) }, ys = points.map { CGFloat($0.y) }
            return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                          width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
        }
        let box = face.boundingBox
        let width = box.width * CGFloat(image.width), height = box.height * CGFloat(image.height)
        guard width > 0, height > 0 else { throw StaffAvatarPhotoError.noFace }
        let l = bounds(left), r = bounds(right), mouth = bounds(lips)
        var result = initial
        let ratio = width / height
        result.face = ratio < 0.69 ? "面長" : ratio < 0.79 ? "すっきり" : ratio > 0.94 ? "ふっくら" : "まるい"
        let openness = ((l.height + r.height) * height) / max(1, (l.width + r.width) * width)
        result.eyeScale = min(1.3, max(0.8, 0.85 + Double(openness) * 0.7))
        result.eyeSpacing = min(1.15, max(0.85, Double(abs(l.midX - r.midX)) / 0.42))
        result.mouthScale = min(1.2, max(0.8, Double(mouth.width) / 0.4))
        result.eyes = "ふつう"
        result.expression = mouth.height * height / max(1, mouth.width * width) > 0.42 ? "にっこり" : "笑顔"
        // Cheek patches avoid hair, mouth and the eye area. Lighting remains a limitation.
        let samples = [CGFloat(0.25), CGFloat(0.75)].compactMap { x in
            sample(image, x: box.minX + box.width * x, y: box.minY + box.height * 0.36, radius: box.width * 0.045)
        }
        if !samples.isEmpty {
            let count = Double(samples.count)
            let rgb = (samples.reduce(0) { $0 + $1.0 } / count,
                       samples.reduce(0) { $0 + $1.1 } / count,
                       samples.reduce(0) { $0 + $1.2 } / count)
            result.skin = StaffAvatarDrawing.skins.indices.min { a, b in
                distance(rgb, StaffAvatarDrawing.skins[a]) < distance(rgb, StaffAvatarDrawing.skins[b])
            } ?? initial.skin
        }
        // Hair/eyewear/style are kept for the user to choose rather than guessed from landmarks.
        return result
    }
    /// 大きな写真を縮めて読む（向きも直す）
    private static func thumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
    private static func distance(_ rgb: (Double, Double, Double), _ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return pow(rgb.0 - Double(r), 2) + pow(rgb.1 - Double(g), 2) + pow(rgb.2 - Double(b), 2)
    }
    private static func sample(_ image: CGImage, x: CGFloat, y: CGFloat, radius: CGFloat) -> (Double, Double, Double)? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(x: (x - radius) * w, y: (1 - y - radius) * h,
                          width: radius * 2 * w, height: radius * 2 * h).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let patch = image.cropping(to: rect) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 8, height: 8)); return true
        }
        guard ok else { return nil }
        var sums = [Double](repeating: 0, count: 3)
        for pixel in 0..<64 { for channel in 0..<3 { sums[channel] += Double(bytes[pixel * 4 + channel]) / 255 } }
        return (sums[0] / 64, sums[1] / 64, sums[2] / 64)
    }
}
