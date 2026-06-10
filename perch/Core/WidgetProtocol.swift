import Foundation
import SwiftUI

@MainActor
protocol PerchWidget: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }
    var supportedSizes: Set<WidgetSize> { get }

    func body(size: WidgetSize) -> AnyView
}
