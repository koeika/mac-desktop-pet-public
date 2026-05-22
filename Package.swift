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
    targets: [
        .target(name: "CodexPetCore"),
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
