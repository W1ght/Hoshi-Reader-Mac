//
//  ColorHexCodec.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

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
