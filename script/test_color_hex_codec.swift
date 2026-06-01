import CoreGraphics
import Foundation

enum ColorHexCodec {
    static func hexString(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> String {
        let redByte = byte(red)
        let greenByte = byte(green)
        let blueByte = byte(blue)
        let alphaByte = byte(alpha)

        if alphaByte == 255 {
            return String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
        }
        return String(format: "#%02X%02X%02X%02X", redByte, greenByte, blueByte, alphaByte)
    }

    static func components(hexString: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        switch hex.count {
        case 3, 4:
            hex = hex.map { "\($0)\($0)" }.joined()
        case 6, 8:
            break
        default:
            return nil
        }

        guard let rawValue = UInt64(hex, radix: 16) else {
            return nil
        }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if hex.count == 6 {
            red = CGFloat((rawValue >> 16) & 0xff) / 255
            green = CGFloat((rawValue >> 8) & 0xff) / 255
            blue = CGFloat(rawValue & 0xff) / 255
            alpha = 1
        } else {
            red = CGFloat((rawValue >> 24) & 0xff) / 255
            green = CGFloat((rawValue >> 16) & 0xff) / 255
            blue = CGFloat((rawValue >> 8) & 0xff) / 255
            alpha = CGFloat(rawValue & 0xff) / 255
        }
        return (red, green, blue, alpha)
    }

    private static func byte(_ component: CGFloat) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

private func assertClose(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
    guard abs(actual - expected) <= (0.5 / 255.0) else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

private func assertComponents(_ hex: String, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, _ message: String) {
    guard let components = ColorHexCodec.components(hexString: hex) else {
        fatalError("\(message): failed to parse \(hex)")
    }
    assertClose(components.red, red, "\(message) red")
    assertClose(components.green, green, "\(message) green")
    assertClose(components.blue, blue, "\(message) blue")
    assertClose(components.alpha, alpha, "\(message) alpha")
}

assertEqual(ColorHexCodec.hexString(red: 1, green: 0, blue: 0, alpha: 1), "#FF0000", "opaque red")
assertEqual(ColorHexCodec.hexString(red: 0, green: 0.5, blue: 1, alpha: 0.4), "#0080FF66", "alpha is preserved")
assertEqual(ColorHexCodec.hexString(red: -1, green: 2, blue: 0.5, alpha: 1.5), "#00FF80", "components are clamped")
assertEqual(ColorHexCodec.hexString(red: 0, green: 0, blue: 0, alpha: 0), "#00000000", "transparent black")

assertComponents("#FF0000", red: 1, green: 0, blue: 0, alpha: 1, "six digit hex")
assertComponents("  #0080FF66\n", red: 0, green: 128 / 255, blue: 1, alpha: 102 / 255, "eight digit hex with whitespace")
assertComponents("#0F8", red: 0, green: 1, blue: 136 / 255, alpha: 1, "short RGB hex")
assertComponents("#0F8C", red: 0, green: 1, blue: 136 / 255, alpha: 204 / 255, "short RGBA hex")
assertEqual(ColorHexCodec.components(hexString: "#XYZ") == nil, true, "invalid digits fail")
assertEqual(ColorHexCodec.components(hexString: "#12345") == nil, true, "invalid length fails")

print("ColorHexCodec tests passed")
