import AppKit

enum AnimationFrames {
    static let frames = [
        "leaf.fill",
        "leaf.arrow.triangle.circlepath",
        "tree.fill",
        "sparkles",
    ]

    static func image(for index: Int) -> NSImage? {
        let name = frames[index % frames.count]
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Token Garden")
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return image?.withSymbolConfiguration(config)
    }
}
