#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSlot {
    let name: String
    let pixels: Int
}

let slots = [
    IconSlot(name: "icon_16x16.png", pixels: 16),
    IconSlot(name: "icon_16x16@2x.png", pixels: 32),
    IconSlot(name: "icon_32x32.png", pixels: 32),
    IconSlot(name: "icon_32x32@2x.png", pixels: 64),
    IconSlot(name: "icon_128x128.png", pixels: 128),
    IconSlot(name: "icon_128x128@2x.png", pixels: 256),
    IconSlot(name: "icon_256x256.png", pixels: 256),
    IconSlot(name: "icon_256x256@2x.png", pixels: 512),
    IconSlot(name: "icon_512x512.png", pixels: 512),
    IconSlot(name: "icon_512x512@2x.png", pixels: 1024)
]

func renderMasterIcon(dimension: CGFloat = 1024) -> NSImage {
    let image = NSImage(size: NSSize(width: dimension, height: dimension))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("无法获取 CGContext")
    }

    let scale = dimension / 1024.0
    func s(_ val: CGFloat) -> CGFloat { val * scale }

    // 1. Clear background
    ctx.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))

    // 2. Base squircle path (Apple macOS App Icon standard proportions: 824x824 inside 1024x1024 canvas)
    let squircleRect = CGRect(x: s(100), y: s(100), width: s(824), height: s(824))
    let cornerRadius: CGFloat = s(185)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Shadow behind squircle
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s(-22)), blur: s(38), color: NSColor(red: 0, green: 0, blue: 0, alpha: 0.60).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for inner content
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Background Gradient: Deep Midnight Space Obsidian
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGrad, start: CGPoint(x: s(512), y: s(924)), end: CGPoint(x: s(512), y: s(100)), options: [])
    }

    // Top-left cyber ambient lighting
    let ambientColors = [
        NSColor(red: 0.18, green: 0.45, blue: 0.95, alpha: 0.28).cgColor,
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).cgColor
    ] as CFArray
    if let ambGrad = CGGradient(colorsSpace: colorSpace, colors: ambientColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(ambGrad, startCenter: CGPoint(x: s(320), y: s(720)), startRadius: 0, endCenter: CGPoint(x: s(320), y: s(720)), endRadius: s(520), options: [])
    }

    // Center circular token dial
    let center = CGPoint(x: s(512), y: s(512))
    let outerRadius: CGFloat = s(265)

    // Token outer glowing halo
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s(45), color: NSColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 0.45).cgColor)
    let haloPath = CGMutablePath()
    haloPath.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.addPath(haloPath)
    ctx.setLineWidth(s(10))
    ctx.setStrokeColor(NSColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.7).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Token Outer Bevel Ring (Gradient Stroke)
    ctx.saveGState()
    let ringColors = [
        NSColor(red: 0.22, green: 0.82, blue: 0.98, alpha: 0.95).cgColor, // Cyan
        NSColor(red: 0.49, green: 0.45, blue: 0.98, alpha: 0.90).cgColor, // Indigo
        NSColor(red: 0.96, green: 0.76, blue: 0.22, alpha: 0.95).cgColor  // Gold
    ] as CFArray
    let ringPath = CGMutablePath()
    ringPath.addArc(center: center, radius: outerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.addPath(ringPath)
    ctx.setLineWidth(s(12))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    if let ringGrad = CGGradient(colorsSpace: colorSpace, colors: ringColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(ringGrad, start: CGPoint(x: s(280), y: s(740)), end: CGPoint(x: s(740), y: s(280)), options: [])
    }
    ctx.restoreGState()

    // Inner Disc Plate
    ctx.saveGState()
    let innerRadius = outerRadius - s(6)
    let innerDiscPath = CGMutablePath()
    innerDiscPath.addArc(center: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.addPath(innerDiscPath)
    ctx.clip()

    let discColors = [
        NSColor(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.96).cgColor,
        NSColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.98).cgColor
    ] as CFArray
    if let discGrad = CGGradient(colorsSpace: colorSpace, colors: discColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(discGrad, start: CGPoint(x: s(512), y: s(512) + innerRadius), end: CGPoint(x: s(512), y: s(512) - innerRadius), options: [])
    }

    // Oscilloscope / Telemetry Grid lines inside disc
    ctx.saveGState()
    ctx.setLineWidth(s(1))
    ctx.setStrokeColor(NSColor(red: 0.22, green: 0.6, blue: 0.9, alpha: 0.14).cgColor)
    let gridStep = s(42)
    for x in stride(from: center.x - innerRadius + gridStep, through: center.x + innerRadius - gridStep, by: gridStep) {
        ctx.move(to: CGPoint(x: x, y: center.y - innerRadius))
        ctx.addLine(to: CGPoint(x: x, y: center.y + innerRadius))
    }
    for y in stride(from: center.y - innerRadius + gridStep, through: center.y + innerRadius - gridStep, by: gridStep) {
        ctx.move(to: CGPoint(x: center.x - innerRadius, y: y))
        ctx.addLine(to: CGPoint(x: center.x + innerRadius, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Stylized Telemetry Curve & Agy "A"
    let curvePath = CGMutablePath()
    curvePath.move(to: CGPoint(x: s(340), y: s(405)))
    curvePath.addCurve(to: CGPoint(x: s(430), y: s(460)), control1: CGPoint(x: s(370), y: s(405)), control2: CGPoint(x: s(395), y: s(460)))
    curvePath.addCurve(to: CGPoint(x: s(512), y: s(640)), control1: CGPoint(x: s(470), y: s(460)), control2: CGPoint(x: s(482), y: s(640)))
    curvePath.addCurve(to: CGPoint(x: s(594), y: s(480)), control1: CGPoint(x: s(545), y: s(640)), control2: CGPoint(x: s(565), y: s(480)))
    curvePath.addCurve(to: CGPoint(x: s(684), y: s(555)), control1: CGPoint(x: s(625), y: s(480)), control2: CGPoint(x: s(655), y: s(555)))

    // Area fill under curve (Neon cyan-blue gradient with fading transparency)
    ctx.saveGState()
    let fillAreaPath = CGMutablePath()
    fillAreaPath.addPath(curvePath)
    fillAreaPath.addLine(to: CGPoint(x: s(684), y: s(360)))
    fillAreaPath.addLine(to: CGPoint(x: s(340), y: s(360)))
    fillAreaPath.closeSubpath()
    ctx.addPath(fillAreaPath)
    ctx.clip()
    let areaColors = [
        NSColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 0.35).cgColor,
        NSColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.02).cgColor
    ] as CFArray
    if let areaGrad = CGGradient(colorsSpace: colorSpace, colors: areaColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(areaGrad, start: CGPoint(x: s(512), y: s(640)), end: CGPoint(x: s(512), y: s(360)), options: [])
    }
    ctx.restoreGState()

    // Wide Glow for curve
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s(26), color: NSColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 0.90).cgColor)
    ctx.setLineWidth(s(13))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(curvePath)
    ctx.setStrokeColor(NSColor(red: 0.25, green: 0.85, blue: 1.0, alpha: 0.95).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Core bright line for curve
    ctx.saveGState()
    ctx.setLineWidth(s(6))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(curvePath)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Letter "A" horizontal crossbar (Token Telemetry Threshold)
    let barPath = CGMutablePath()
    barPath.move(to: CGPoint(x: s(438), y: s(496)))
    barPath.addLine(to: CGPoint(x: s(580), y: s(496)))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s(14), color: NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.85).cgColor)
    ctx.setLineWidth(s(6))
    ctx.setLineCap(.round)
    ctx.addPath(barPath)
    ctx.setStrokeColor(NSColor(red: 0.45, green: 0.92, blue: 1.0, alpha: 0.95).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Data nodes along the spline
    let nodes: [(pt: CGPoint, isPeak: Bool)] = [
        (CGPoint(x: s(340), y: s(405)), false),
        (CGPoint(x: s(430), y: s(460)), false),
        (CGPoint(x: s(512), y: s(640)), true),
        (CGPoint(x: s(594), y: s(480)), false),
        (CGPoint(x: s(684), y: s(555)), false)
    ]
    for node in nodes {
        ctx.saveGState()
        let r: CGFloat = node.isPeak ? s(14) : s(10)
        let glowColor = node.isPeak ? NSColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 0.95) : NSColor.cyan
        let coreColor = node.isPeak ? NSColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 1.0) : NSColor.white
        ctx.setShadow(offset: .zero, blur: s(18), color: glowColor.cgColor)
        ctx.addArc(center: node.pt, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.setFillColor(coreColor.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.restoreGState() // Inner Disc Plate clip

    // Top rim specular highlight for Apple Squircle
    ctx.saveGState()
    let rimRect = squircleRect.insetBy(dx: s(1.5), dy: s(1.5))
    let rimPath = CGPath(roundedRect: rimRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(rimPath)
    ctx.setLineWidth(s(2.5))
    let rimColors = [
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.38).cgColor,
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.06).cgColor,
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45).cgColor
    ] as CFArray
    if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 0.35, 1.0]) {
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(rimGrad, start: CGPoint(x: s(512), y: s(924)), end: CGPoint(x: s(512), y: s(100)), options: [])
    }
    ctx.restoreGState()

    ctx.restoreGState() // Squircle clip

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AgyTokenIcon", code: 1)
    }
    try pngData.write(to: url)
}

let rootDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let iconsetURL = URL(fileURLWithPath: rootDir).appendingPathComponent("NativeApp/AppIcon.iconset")
let icnsURL = URL(fileURLWithPath: rootDir).appendingPathComponent("NativeApp/AppIcon.icns")
let previewURL = URL(fileURLWithPath: rootDir).appendingPathComponent("NativeApp/AppIcon_Preview.png")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

print("🎨 正在渲染全尺寸矢量图标...")
let masterIcon = renderMasterIcon(dimension: 1024)
try writePNG(masterIcon, to: previewURL)

print("📦 正在生成 Apple Iconset (10 档分辨率)...")
for slot in slots {
    let slotImg = renderMasterIcon(dimension: CGFloat(slot.pixels))
    try writePNG(slotImg, to: iconsetURL.appendingPathComponent(slot.name))
}

print("⚙️ 编译生成 AppIcon.icns...")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("✅ 成功生成: \(icnsURL.path)")
} else {
    print("❌ iconutil 执行失败，状态码: \(proc.terminationStatus)")
    exit(proc.terminationStatus)
}
