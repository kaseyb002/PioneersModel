import Foundation

public typealias TradeOfferID = Int

/// A single structured trade offer posted by the active player. Exactly one may be open at a time;
/// replacing the terms requires posting a new offer (the old one is dropped).
public struct TradeOffer: Equatable, Codable, Identifiable, Sendable {
    public let id: TradeOfferID
    public let fromPlayerID: PlayerID
    /// Resources the active player is giving up (keys with positive counts).
    public let give: [Resource: Int]
    /// Resources the active player wants in return (keys with positive counts).
    public let receive: [Resource: Int]
    /// Non-active players who are eligible to accept this offer.
    public let eligibleAcceptors: Set<PlayerID>
    /// Players who declined. Declining does not remove eligibility to accept later.
    public var declines: Set<PlayerID>
    public let posted: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case fromPlayerID = "fromPlayerId"
        case give
        case receive
        case eligibleAcceptors
        case declines
        case posted
    }

    public init(
        id: TradeOfferID,
        fromPlayerID: PlayerID,
        give: [Resource: Int],
        receive: [Resource: Int],
        eligibleAcceptors: Set<PlayerID>,
        declines: Set<PlayerID> = [],
        posted: Date = .now
    ) {
        self.id = id
        self.fromPlayerID = fromPlayerID
        self.give = give
        self.receive = receive
        self.eligibleAcceptors = eligibleAcceptors
        self.declines = declines
        self.posted = posted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TradeOfferID.self, forKey: .id)
        fromPlayerID = try container.decode(PlayerID.self, forKey: .fromPlayerID)
        give = try container.decode([Resource: Int].self, forKey: .give)
        receive = try container.decode([Resource: Int].self, forKey: .receive)
        eligibleAcceptors = try container.decode(Set<PlayerID>.self, forKey: .eligibleAcceptors)
        declines = try container.decodeIfPresent(Set<PlayerID>.self, forKey: .declines) ?? []
        posted = try container.decode(Date.self, forKey: .posted)
    }
}

extension TradeOffer {
    public static func fake(
        id: TradeOfferID = 1,
        fromPlayerID: PlayerID = "p1",
        give: [Resource: Int] = [.wood: 1],
        receive: [Resource: Int] = [.brick: 1],
        eligibleAcceptors: Set<PlayerID> = ["p2"],
        declines: Set<PlayerID> = [],
        posted: Date = .now
    ) -> TradeOffer {
        TradeOffer(
            id: id,
            fromPlayerID: fromPlayerID,
            give: give,
            receive: receive,
            eligibleAcceptors: eligibleAcceptors,
            declines: declines,
            posted: posted
        )
    }
}
