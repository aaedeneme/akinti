// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Akinti",
    platforms: [.macOS(.v13)],
    targets: [
        // libtorrent-rasterbar (C++) için Objective-C++ köprüsü
        .target(
            name: "CTorrent",
            cxxSettings: [
                .unsafeFlags(["-std=c++17", "-I/opt/homebrew/include", "-I/usr/local/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-L/usr/local/lib", "-ltorrent-rasterbar"])
            ]
        ),
        .executableTarget(name: "Akinti", dependencies: ["CTorrent"]),
    ],
    cxxLanguageStandard: .cxx17
)
