import Foundation

extension Round {
    public var bankResourceCounts: [Resource: Int] {
        bankResourceIDs.reduce(into: [:]) { counts, id in
            if let resource = resourcesMap[id] { counts[resource, default: 0] += 1 }
        }
    }

    static func makeResourceBank(countPerResource: Int) -> (map: [ResourceID: Resource], ids: [ResourceID]) {
        // Store an independent shuffled draw order so grants do not preferentially
        // issue the lowest IDs (which are used for deterministic theft).
        var map: [ResourceID: Resource] = [:]
        for resource in Resource.allCases {
            for _ in 0..<countPerResource { map[UUID().uuidString] = resource }
        }
        return (map, map.keys.shuffled())
    }

    /// Select exact cards consistently on client and server, independently of dictionary order.
    func resourceIDs(for bundle: [Resource: Int], from ids: [ResourceID]) throws -> [ResourceID] {
        guard bundle.values.allSatisfy({ $0 >= 0 }) else { throw PioneersModelError.invalidResourceCount }
        var selected: [ResourceID] = []
        for resource in Resource.allCases {
            let count = bundle[resource] ?? 0
            let candidates = ids.filter { resourcesMap[$0] == resource }.sorted()
            guard candidates.count >= count else { throw PioneersModelError.insufficientResources }
            selected.append(contentsOf: candidates.prefix(count))
        }
        return selected
    }

    mutating func spendResources(_ cost: [Resource: Int], fromPlayerID playerID: PlayerID) throws {
        guard let index = playerIndex(of: playerID) else { throw PioneersModelError.playerNotFound }
        let ids = try resourceIDs(for: cost, from: playerHands[index].resourceIDs)
        let selected = Set(ids)
        playerHands[index].resourceIDs.removeAll { selected.contains($0) }
        bankResourceIDs.append(contentsOf: ids)
    }

    /// Production and setup may take only the available cards. Trades/Harvest validate first.
    @discardableResult
    mutating func grantResources(_ bundle: [Resource: Int], toPlayerID playerID: PlayerID) -> [Resource: Int] {
        guard let index = playerIndex(of: playerID) else { return [:] }
        var granted: [Resource: Int] = [:]
        for resource in Resource.allCases {
            let requested = max(0, bundle[resource] ?? 0)
            let ids = Array(bankResourceIDs.filter { resourcesMap[$0] == resource }.prefix(requested))
            if !ids.isEmpty {
                let selected = Set(ids)
                bankResourceIDs.removeAll { selected.contains($0) }
                playerHands[index].resourceIDs.append(contentsOf: ids)
                granted[resource] = ids.count
            }
        }
        return granted
    }
}
