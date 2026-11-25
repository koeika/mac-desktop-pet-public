// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexDesktopPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexPetCore", targets: ["CodexPetCore"]),
        .executable(name: "whiskycolin", targets: ["CodexPetApp"]),
        .executable(name: "CodexPetApp", targets: ["CodexPetApp"]),
        .executable(name: "petctl", targets: ["PetCTL"]),
        .executable(name: "codex-pet-selftest", targets: ["CodexPetSelfTest"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs.git", exact: "6.0.0")
    ],
    targets: [
        .target(name: "CodexPetCore", dependencies: [.product(name: "FSRS", package: "swift-fsrs")]),
        .testTarget(name: "CodexPetCoreTests", dependencies: ["CodexPetCore"]),
        .testTarget(name: "CodexPetAppTests", dependencies: ["CodexPetApp"]),
        .executableTarget(
            name: "CodexPetApp",
            dependencies: ["CodexPetCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "PetCTL",
            dependencies: ["CodexPetCore"]
        ),
        .executableTarget(
            name: "CodexPetSelfTest",
            dependencies: ["CodexPetCore"]
        )
    ]
)
