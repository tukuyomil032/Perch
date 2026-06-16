import Foundation
import SwiftUI

protocol PerchWidget: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }
    var supportedSizes: Set<WidgetSize> { get }

    @MainActor func body(size: WidgetSize) -> AnyView
}
