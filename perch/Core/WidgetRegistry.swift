import Foundation
import SwiftUI

struct AnyPerchWidget: Identifiable, @unchecked Sendable {
    let id: String
    let displayName: String
    let icon: String
    let supportedSizes: Set<WidgetSize>

    private let _body: (WidgetSize) -> AnyView

    init<W: PerchWidget>(_ widget: W) {
        id = widget.id
        displayName = widget.displayName
        icon = widget.icon
        supportedSizes = widget.supportedSizes
        _body = { size in widget.body(size: size) }
    }

    @MainActor func body(size: WidgetSize) -> AnyView {
        _body(size)
    }
}

@MainActor
@Observable
final class WidgetRegistry {
    private var storage: [String: AnyPerchWidget] = [:]
    private var insertionOrder: [String] = []

    var allWidgets: [AnyPerchWidget] {
        insertionOrder.compactMap { storage[$0] }
    }

    func register(_ widget: some PerchWidget) {
        if storage[widget.id] == nil {
            insertionOrder.append(widget.id)
        }
        storage[widget.id] = AnyPerchWidget(widget)
    }

    func widget(forId id: String) -> AnyPerchWidget? {
        storage[id]
    }
}
