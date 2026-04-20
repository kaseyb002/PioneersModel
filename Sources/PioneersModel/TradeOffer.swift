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
    public let posted: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case fromPlayerID = "fromPlayerId"
        case give
        case receive
        case eligibleAcceptors
        case posted
    }

    public init(
        id: TradeOfferID,
        fromPlayerID: PlayerID,
        give: [Resource: Int],
        receive: [Resource: Int],
        eligibleAcceptors: Set<PlayerID>,
        posted: Date = .now
    ) {
        self.id = id
        self.fromPlayerID = fromPlayerID
        self.give = give
        self.receive = receive
        self.eligibleAcceptors = eligibleAcceptors
        self.posted = posted
    }
}

extension TradeOffer {
    public static func fake(
        id: TradeOfferID = 1,
        fromPlayerID: PlayerID = "p1",
        give: [Resource: Int] = [.wood: 1],
        receive: [Resource: Int] = [.brick: 1],
        eligibleAcceptors: Set<PlayerID> = ["p2"],
        posted: Date = .now
    ) -> TradeOffer {
        TradeOffer(
            id: id,
            fromPlayerID: fromPlayerID,
            give: give,
            receive: receive,
            eligibleAcceptors: eligibleAcceptors,
            posted: posted
        )
    }
}
