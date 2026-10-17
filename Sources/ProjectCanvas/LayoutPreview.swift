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
            // Iterative Kosaraju: linear graph traversal, without recursive stack growth.
            var reverse: [UUID: [UUID]] = [:]
            for (source, destinations) in edges {
                for destination in destinations { reverse[destination, default: []].append(source) }
            }
            var seen = Set<UUID>(), finished: [UUID] = []
            for id in ordered where !seen.contains(id) {
                var stack: [(UUID, Bool)] = [(id, false)]
                while let (node, exiting) = stack.popLast() {
                    if exiting { finished.append(node); continue }
                    guard seen.insert(node).inserted else { continue }
                    stack.append((node, true))
                    for next in edges[node] ?? [] where !seen.contains(next) { stack.append((next, false)) }
                }
            }
            var rawComponent: [UUID: Int] = [:]
            var componentCount = 0
            for id in finished.reversed() where rawComponent[id] == nil {
                var stack = [id]
                rawComponent[id] = componentCount
                while let node = stack.popLast() {
                    for next in reverse[node] ?? [] where rawComponent[next] == nil {
                        rawComponent[next] = componentCount
                        stack.append(next)
                    }
                }
                componentCount += 1
            }
            var components: [[UUID]] = [], componentOf: [UUID: Int] = [:]
            var canonical: [Int: Int] = [:]
            for id in ordered {
                let raw = rawComponent[id]!
                if canonical[raw] == nil { canonical[raw] = components.count; components.append([]) }
                let index = canonical[raw]!
                components[index].append(id)
                componentOf[id] = index
            }
            var successors = Array(repeating: Set<Int>(), count: components.count)
            var indegree = Array(repeating: 0, count: components.count)
            for edge in group.connections {
                guard let a = componentOf[edge.fromCardID], let b = componentOf[edge.toCardID], a != b else { continue }
                if successors[a].insert(b).inserted { indegree[b] += 1 }
            }
            var layers = Array(repeating: 0, count: components.count)
            var pending = indegree.indices.filter { indegree[$0] == 0 }
            var head = 0
            while head < pending.count {
                let current = pending[head]
                head += 1
                for next in successors[current].sorted() {
                    layers[next] = max(layers[next], layers[current] + 1)
                    indegree[next] -= 1
                    if indegree[next] == 0 { pending.append(next) }
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
