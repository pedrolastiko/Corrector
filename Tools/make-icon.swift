#!/usr/bin/env swift
//
// Generates Corrector's app icon from scratch with Core Graphics.
//
// The mark is an original drawing: a rounded tile carrying a caret (the editor's
// insertion mark) crossed by a tick (the accepted suggestion), over a teal→violet
// gradient taken from Corrector's own palette. It is drawn by this code, so no
// third-party artwork is involved.
//
// swift Tools/make-icon.swift Assets
//
import AppKit
import Foundation

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]: "Assets"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

let teal   = NSColor(srgbRed: 0.055, green: 0.549, blue: 0.498, alpha: 1)  // #0E8C7F
let violet = NSColor(srgbRed: 0.416, green: 0.329, blue: 0.788, alpha: 1)  // #6A54C9
let amber  = NSColor(srgbRed: 0.769, green: 0.498, blue: 0.090, alpha: 1)  // #C47F17

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current? .cgContext else {
        image.unlockFocus(); return image
    }
    context.setAllowsAntialiasing(true)
    let s = size / 1024.0   // design on a 1024 grid, scale down

    // Rounded tile with a diagonal gradient.
    let inset = 72.0 * s
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = CGPath(roundedRect: tile,
                          cornerWidth: 200 * s, cornerHeight: 200 * s, transform: nil)
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [teal.cgColor, violet.cgColor] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: tile.minX, y: tile.maxY),
                               end: CGPoint(x: tile.maxX, y: tile.minY),
                               options: [])
    context.restoreGState()

    // The caret: a tall insertion bar with serifs, left of centre.
    context.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    let caretX = 360.0 * s
    let caretTop = 300.0 * s, caretBottom = 724.0 * s
    let stem = CGRect(x: caretX - 26 * s, y: caretTop,
                      width: 52 * s, height: caretBottom - caretTop)
    context.addPath(CGPath(roundedRect: stem, cornerWidth: 26 * s,
                           cornerHeight: 26 * s, transform: nil))
    for y in [caretTop, caretBottom - 44 * s] {
        let serif = CGRect(x: caretX - 96 * s, y: y, width: 192 * s, height: 44 * s)
        context.addPath(CGPath(roundedRect: serif, cornerWidth: 22 * s,
                               cornerHeight: 22 * s, transform: nil))
    }
    context.fillPath()

    // The tick: an accepted suggestion, sweeping up and to the right.
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(76 * s)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 512 * s, y: 452 * s))
    context.addLine(to: CGPoint(x: 606 * s, y: 348 * s))
    context.addLine(to: CGPoint(x: 788 * s, y: 648 * s))
    context.strokePath()

    // The underline: the suggestion marker, in the style-guide amber.
    context.setStrokeColor(amber.cgColor)
    context.setLineWidth(44 * s)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: 332 * s, y: 236 * s))
    context.addLine(to: CGPoint(x: 788 * s, y: 236 * s))
    context.strokePath()

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, size: Int) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using:.png, properties: [:])
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("Corrector.iconset")
try? fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    guard let data = png(drawIcon(size: CGFloat(size)), size: size) else { continue }
    let scale = size >= 64 ? "\(size / 2)x\(size / 2)@2x": "\(size)x\(size)"
    try data.write(to: iconset.appendingPathComponent("icon_\(scale).png"))
    if size <= 512 {
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    }
    print("  icon_\(size)x\(size).png")
}

// A standalone 512px mark for documentation.
if let data = png(drawIcon(size: 512), size: 512) {
    try data.write(to: URL(fileURLWithPath: outputDirectory)
.appendingPathComponent("corrector-icon.png"))
    print("  corrector-icon.png")
}
print("icon set written to \(iconset.path)")
