#!/usr/bin/env swift
import SwiftUI
import AppKit

struct MeuCleanerAppIconView: View {
    var body: some View {
        ZStack {
            // Outer macOS Squircle Base with Deep Navy/Cyan Liquid Glass Gradient
            RoundedRectangle(cornerRadius: 228, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.09, blue: 0.22),
                            Color(red: 0.04, green: 0.16, blue: 0.36),
                            Color(red: 0.02, green: 0.07, blue: 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 896, height: 896)
                .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 18)

            // Ambient Inner Glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(0.35),
                            Color.blue.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 390
                    )
                )
                .frame(width: 780, height: 780)

            // Outer Space Lens Track Ring
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 54)
                .frame(width: 640, height: 640)

            // Outer Space Lens Active Arcs
            Circle()
                .trim(from: 0.04, to: 0.46)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.04, green: 0.52, blue: 1.0),
                            Color(red: 0.35, green: 0.82, blue: 0.98)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 54, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 640, height: 640)
                .shadow(color: .cyan.opacity(0.45), radius: 18)

            Circle()
                .trim(from: 0.52, to: 0.78)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.62, blue: 0.04),
                            Color(red: 1.0, green: 0.27, blue: 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 54, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 640, height: 640)

            Circle()
                .trim(from: 0.84, to: 0.97)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.35, blue: 0.95),
                            Color(red: 0.37, green: 0.36, blue: 0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 54, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 640, height: 640)

            // Inner Ring Track
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 42)
                .frame(width: 470, height: 470)

            Circle()
                .trim(from: 0.0, to: 0.66)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.39, green: 0.86, blue: 1.0),
                            Color(red: 0.19, green: 0.82, blue: 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 42, lineCap: .round)
                )
                .rotationEffect(.degrees(-110))
                .frame(width: 470, height: 470)

            // Center Frosted Glass Medallion
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.22, blue: 0.45),
                            Color(red: 0.05, green: 0.11, blue: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 310, height: 310)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.cyan.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            // Central Sparkle Emblem
            Image(systemName: "sparkles")
                .font(.system(size: 156, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white,
                            Color(red: 0.65, green: 0.93, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .cyan.opacity(0.7), radius: 16)

            // Specular Liquid Glass Border on Outer Squircle
            RoundedRectangle(cornerRadius: 228, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.10),
                            Color.cyan.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 6
                )
                .frame(width: 896, height: 896)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func generateIcons() throws {
    let fm = FileManager.default
    let rootDir = URL(fileURLWithPath: fm.currentDirectoryPath)
    let iconsetDir = rootDir.appendingPathComponent("build/AppIcon.iconset")
    let resourcesDir = rootDir.appendingPathComponent("Resources")
    let docsImagesDir = rootDir.appendingPathComponent("docs/images")

    try? fm.removeItem(at: iconsetDir)
    try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: docsImagesDir, withIntermediateDirectories: true)

    let sizes: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]

    for (pixelSize, filename) in sizes {
        let scale = CGFloat(pixelSize) / 1024.0
        let renderer = ImageRenderer(content: MeuCleanerAppIconView())
        renderer.scale = scale
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to render \(filename)")
        }
        let fileURL = iconsetDir.appendingPathComponent(filename)
        try pngData.write(to: fileURL)

        if pixelSize == 512 && filename == "icon_256x256@2x.png" {
            try pngData.write(to: docsImagesDir.appendingPathComponent("app-icon.png"))
        }
    }

    let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
    try process.run()
    process.waitUntilExit()
    print("✅ Generated \(icnsURL.path) and docs/images/app-icon.png")
}

try MainActor.assumeIsolated {
    try generateIcons()
}
