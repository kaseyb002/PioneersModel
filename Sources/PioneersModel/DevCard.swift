import Foundation

public typealias DevCardID = Int

public struct DevCard: Equatable, Codable, Identifiable, Sendable {
    public let id: DevCardID
    public let kind: Kind

    public enum Kind: String, Equatable, Codable, CaseIterable, Sendable {
        /// Equivalent to Catan's "Knight": move the outlaw and steal a resource. Counts toward largest army.
        case ranger
        /// Secret +1 victory point (Catan's "Victory Point" card).
        case landmark
        /// Place 2 trails for free (Catan's "Road Building").
        case pathfinder
        /// Name a resource; take all of it from every opponent (Catan's "Monopoly").
        case roundup
        /// Draw 2 resources of your choice from the bank (Catan's "Year of Plenty").
        case bountifulHarvest

        public var displayableName: String {
            switch self {
            case .ranger: "Ranger"
            case .landmark: "Landmark"
            case .pathfinder: "Pathfinder"
            case .roundup: "Roundup"
            case .bountifulHarvest: "Bountiful Harvest"
            }
        }
    }

    public init(id: DevCardID, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

extension DevCard {
    public static func fake(
        id: DevCardID = 1,
        kind: Kind = .ranger
    ) -> DevCard {
        DevCard(id: id, kind: kind)
    }
}
