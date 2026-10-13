import Foundation

extension PlayerHand {
    public func resources(using map: [ResourceID: Resource]) -> [Resource: Int] {
        resourceIDs.reduce(into: [:]) { counts, id in
            if let resource = map[id] { counts[resource, default: 0] += 1 }
        }
    }

    public func heldDevCards(using map: [DevCardID: DevCard]) -> [DevCard] {
        heldDevCardIDs.compactMap { map[$0] }
    }

    public func playedDevCards(using map: [DevCardID: DevCard]) -> [DevCard] {
        playedDevCardIDs.compactMap { map[$0] }
    }

    public func rangersPlayed(using map: [DevCardID: DevCard]) -> Int {
        playedDevCards(using: map).filter { $0.kind == .ranger }.count
    }

    public func landmarksHeld(using map: [DevCardID: DevCard]) -> Int {
        heldDevCards(using: map).filter { $0.kind == .landmark }.count
    }
}
