// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "tiptap_view",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "tiptap-view", targets: ["tiptap_view"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "tiptap_view",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
