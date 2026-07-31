// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HotkeyManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HotkeyManager",
            path: "Sources/HotkeyManager"
        )
    ]
)
