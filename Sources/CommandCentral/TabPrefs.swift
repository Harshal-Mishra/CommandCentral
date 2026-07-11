import Foundation

/// Which dashboard tabs are visible and in what order.
/// Home and Settings are always visible; everything is reachable via the ⋯ menu.
final class TabPrefs: ObservableObject {
    @Published private(set) var hidden: Set<String>
    @Published private(set) var order: [String]

    init() {
        hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenTabs") ?? [])
        var stored = UserDefaults.standard.stringArray(forKey: "tabOrder") ?? []
        // Migrate: append any tabs added in newer versions.
        for tab in DashboardTab.allCases where !stored.contains(tab.rawValue) {
            stored.append(tab.rawValue)
        }
        stored.removeAll { DashboardTab(rawValue: $0) == nil }
        order = stored
    }

    func isVisible(_ tab: DashboardTab) -> Bool {
        tab == .home || tab == .settings || !hidden.contains(tab.rawValue)
    }

    var orderedTabs: [DashboardTab] {
        order.compactMap { DashboardTab(rawValue: $0) }
    }

    var visibleTabs: [DashboardTab] {
        orderedTabs.filter(isVisible)
    }

    func toggle(_ tab: DashboardTab) {
        guard tab != .home, tab != .settings else { return }
        if hidden.contains(tab.rawValue) {
            hidden.remove(tab.rawValue)
        } else {
            hidden.insert(tab.rawValue)
        }
        UserDefaults.standard.set(Array(hidden), forKey: "hiddenTabs")
    }

    func move(_ tab: DashboardTab, by offset: Int) {
        guard let index = order.firstIndex(of: tab.rawValue) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        UserDefaults.standard.set(order, forKey: "tabOrder")
    }
}
