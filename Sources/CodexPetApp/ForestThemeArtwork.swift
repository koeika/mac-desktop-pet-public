import AppKit
import SwiftUI

enum ForestThemeArtwork {
    static let clearing = load("forest-clearing")
    static let ferns = load("forest-ferns")

    private static func load(_ name: String) -> NSImage? {
        AppResourceLocator.file(named: "Themes/\(name)", extension: "png").flatMap { NSImage(contentsOf: $0) }
    }
}

struct ForestPetStage<Pet: View>: View {
    @ViewBuilder var pet: Pet

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = ForestThemeArtwork.clearing {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().accessibilityHidden(true)
                }
                pet
                    .frame(width: min(geometry.size.width * 0.5, geometry.size.height * 0.8),
                           height: geometry.size.height * 0.64)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.47)
            }
        }
        .clipped()
    }
}
