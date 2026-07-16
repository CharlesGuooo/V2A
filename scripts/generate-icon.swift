#!/usr/bin/env swift

// Generates V2A.app's 1024x1024 AppIcon as a PNG.
// Design: "Icon H" — indigo gradient bg + white outer ring + 5 white audio bars.
// Usage: swift generate-icon.swift <output.png>

import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output.png>\n", stderr)
    exit(1)
}
let outPath = CommandLine.arguments[1]
let size: CGFloat = 1024

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fputs("Failed to get CGContext\n", stderr)
    exit(1)
}

// macOS CoreGraphics origin is bottom-left, so the 135deg gradient runs
// top-left -> bottom-right. Color stops match the CSS:
//   linear-gradient(135deg, #818CF8 0%, #5E6AD2 60%, #4F46E5 100%)
let bgColors = [
    NSColor(srgbRed: 0x81/255, green: 0x8C/255, blue: 0xF8/255, alpha: 1).cgColor,
    NSColor(srgbRed: 0x5E/255, green: 0x6A/255, blue: 0xD2/255, alpha: 1).cgColor,
    NSColor(srgbRed: 0x4F/255, green: 0x46/255, blue: 0xE5/255, alpha: 1).cgColor,
] as CFArray
let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: bgColors,
                            locations: [0, 0.6, 1])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// All foreground marks are white.
let white = NSColor.white.cgColor
ctx.setStrokeColor(white)
ctx.setFillColor(white)

// Source SVG used a 0..80 viewBox; scale up to 1024.
let scale = size / 80.0
let center = CGPoint(x: size / 2, y: size / 2)

// === Outer ring ===
// Center 40,40, radius 30, stroke 2.5, opacity 0.35.
ctx.saveGState()
ctx.setAlpha(0.35)
ctx.setLineWidth(2.5 * scale)
ctx.strokeEllipse(in: CGRect(
    x: center.x - 30 * scale,
    y: center.y - 30 * scale,
    width: 60 * scale,
    height: 60 * scale
))
ctx.restoreGState()

// === 5 audio bars ===
// SVG bars (in the 80-unit viewBox):
//   x=22.00, y=34, w=3.5, h=12, opacity 0.60
//   x=30.00, y=28, w=3.5, h=24, opacity 0.85
//   x=38.25, y=22, w=3.5, h=36, opacity 1.00
//   x=46.50, y=28, w=3.5, h=24, opacity 0.85
//   x=54.75, y=34, w=3.5, h=12, opacity 0.60
// SVG y grows down; macOS CG y grows up. Flip with y = size - (svgY + h) * scale.
struct Bar { let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat; let alpha: CGFloat }
let bars: [Bar] = [
    Bar(x: 22.00, y: 34, w: 3.5, h: 12, alpha: 0.60),
    Bar(x: 30.00, y: 28, w: 3.5, h: 24, alpha: 0.85),
    Bar(x: 38.25, y: 22, w: 3.5, h: 36, alpha: 1.00),
    Bar(x: 46.50, y: 28, w: 3.5, h: 24, alpha: 0.85),
    Bar(x: 54.75, y: 34, w: 3.5, h: 12, alpha: 0.60),
]
let barRadius: CGFloat = 1.75 * scale  // rx=1.75 in source SVG

for bar in bars {
    let rect = CGRect(
        x: bar.x * scale,
        y: size - (bar.y + bar.h) * scale,
        width: bar.w * scale,
        height: bar.h * scale
    )
    let path = CGPath(roundedRect: rect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
    ctx.saveGState()
    ctx.setAlpha(bar.alpha)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

img.unlockFocus()

// Write PNG (no alpha; iOS app icons must be opaque).
guard let tiff = img.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath) (\(png.count) bytes)")
} catch {
    fputs("Write error: \(error)\n", stderr)
    exit(1)
}
