import Foundation

enum LayoutMode { case grid, relationships }

/// A value-only proposal; creating or discarding it cannot write the model or storage.
struct LayoutPreview: Identifiable {
    let id = UUID()
    let original: ProjectGroup
    let proposed: ProjectGroup
}

enum ProjectLayout {
    static func preview(_ group: ProjectGroup, mode: LayoutMode) -> LayoutPreview {
        var proposed = group
        let ordered = group.cards.map(\.id).sorted { $0.uuidString < $1.uuidString }
        var positions: [UUID: (Double, Double)] = [:]
        switch mode {
        case .grid:
            for (i, card) in group.cards.enumerated() { positions[card.id] = (96 + Double(i % 6) * 300, 96 + Double(i / 6) * 168) }
        case .relationships:
            proposed.showsConnections = true
            let ids = Set(ordered)
            var edges: [UUID: Set<UUID>] = [:]
            for edge in group.connections where ids.contains(edge.fromCardID) && ids.contains(edge.toCardID) {
                edges[edge.fromCardID, default: []].insert(edge.toCardID)
            }
            // Iterative reachability avoids recursion limits and identifies strongly connected components.
            var reachable: [UUID: Set<UUID>] = [:]
            for id in ordered {
                var seen: Set<UUID> = [id], pending = [id]
                while let next = pending.popLast() {
                    for destination in edges[next] ?? [] where seen.insert(destination).inserted { pending.append(destination) }
                }
                reachable[id] = seen
            }
            var components: [[UUID]] = [], componentOf: [UUID: Int] = [:]
            for id in ordered where componentOf[id] == nil {
                let members = ordered.filter { reachable[id]!.contains($0) && reachable[$0]!.contains(id) }
                for member in members { componentOf[member] = components.count }
                components.append(members)
            }
            var successors = Array(repeating: Set<Int>(), count: components.count)
            var indegree = Array(repeating: 0, count: components.count)
            for edge in group.connections {
                guard let a = componentOf[edge.fromCardID], let b = componentOf[edge.toCardID], a != b else { continue }
                if successors[a].insert(b).inserted { indegree[b] += 1 }
            }
            var layers = Array(repeating: 0, count: components.count)
            var pending = indegree.indices.filter { indegree[$0] == 0 }
            while !pending.isEmpty {
                let current = pending.removeFirst()
                for next in successors[current].sorted() {
                    layers[next] = max(layers[next], layers[current] + 1)
                    indegree[next] -= 1
                    if indegree[next] == 0 { pending.append(next); pending.sort() }
                }
            }
            var rows: [Int: Int] = [:]
            for index in components.indices {
                for id in components[index] {
                    let layer = layers[index], row = rows[layer, default: 0]
                    positions[id] = (96 + Double(layer) * 320, 96 + Double(row) * 168)
                    rows[layer] = row + 1
                }
            }
        }
        for i in proposed.cards.indices {
            if let (x, y) = positions[proposed.cards[i].id] { proposed.cards[i].x = x; proposed.cards[i].y = y }
        }
        return LayoutPreview(original: group, proposed: proposed)
    }
}
