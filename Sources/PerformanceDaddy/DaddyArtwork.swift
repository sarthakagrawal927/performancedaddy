import AppKit
import SwiftUI

/// Original Daddy-series assets reused unchanged with the owner's approval.
struct DaddyArtwork: View {
    var brand = false
    var topic = 5
    private static let mark = Bundle.module.url(forResource: "PerformanceDaddy", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    private static let sheet = Bundle.module.url(forResource: "PageDoodles", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    var body: some View {
        GeometryReader { geometry in
            if brand, let image = Self.mark {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let image = Self.sheet {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: geometry.size.width * 3, height: geometry.size.height * 3)
                    .offset(x: -CGFloat(topic % 3) * geometry.size.width,
                            y: -CGFloat(topic / 3) * geometry.size.height)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
