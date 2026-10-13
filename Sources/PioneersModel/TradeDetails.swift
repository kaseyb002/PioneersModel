/// An immutable snapshot of a trade's terms for the action log.
/// `give` and `receive` are always from the offer creator's perspective.
public struct TradeDetails: Equatable, Codable, Sendable {
    public let fromPlayerID: PlayerID
    public let give: [Resource: Int]
    public let receive: [Resource: Int]

    public enum CodingKeys: String, CodingKey {
        case fromPlayerID = "fromPlayerId"
        case give
        case receive
    }

    public init(fromPlayerID: PlayerID, give: [Resource: Int], receive: [Resource: Int]) {
        self.fromPlayerID = fromPlayerID
        self.give = give
        self.receive = receive
    }

    public init(offer: TradeOffer) {
        self.init(fromPlayerID: offer.fromPlayerID, give: offer.give, receive: offer.receive)
    }
}
