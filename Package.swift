// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GmailBox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GmailBox", targets: ["GmailBox"])
    ],
    targets: [
        .executableTarget(
            name: "GmailBox",
            exclude: [
                "Config/GoogleOAuthClient.example.json"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
