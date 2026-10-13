import Foundation
import CryptoKit

extension Round {
    enum CodingKeys: String, CodingKey {
        case id
        case started
        case ended
        case selectedExpansionRuleSet
        case pairedTurnOriginatingPlayerID
        case tiles
        case vertices
        case edges
        case ports
        case playerHands
        case buildings
        case trails
        case outlawTileID
        case devCardDeck
        case openTradeOffer
        case longestRoadHolder
        case largestArmyHolder
        case nextTradeOfferID
        case hasPlayedDevCardThisTurn
        case hasRolledDiceThisTurn
        case lastDiceTotal
        case cookedDiceRolls
        case cookedStealChoices
        case state
        case log
        case resourcesMap
        case bankResourceIDs
        case devCardsMap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.started = try container.decode(Date.self, forKey: .started)
        self.ended = try container.decodeIfPresent(Date.self, forKey: .ended)
        self.selectedExpansionRuleSet = try container.decodeIfPresent(ExpansionRuleSet.self, forKey: .selectedExpansionRuleSet)
        self.pairedTurnOriginatingPlayerID = try container.decodeIfPresent(PlayerID.self, forKey: .pairedTurnOriginatingPlayerID)
        self.tiles = try container.decode([Tile].self, forKey: .tiles)
        self.vertices = try container.decode([Vertex].self, forKey: .vertices)
        self.edges = try container.decode([Edge].self, forKey: .edges)
        self.ports = try container.decode([Port].self, forKey: .ports)
        self.buildings = try container.decode([Building].self, forKey: .buildings)
        self.trails = try container.decode([Trail].self, forKey: .trails)
        self.outlawTileID = try container.decode(TileID.self, forKey: .outlawTileID)
        self.openTradeOffer = try container.decodeIfPresent(TradeOffer.self, forKey: .openTradeOffer)
        self.longestRoadHolder = try container.decodeIfPresent(PlayerID.self, forKey: .longestRoadHolder)
        self.largestArmyHolder = try container.decodeIfPresent(PlayerID.self, forKey: .largestArmyHolder)
        self.nextTradeOfferID = try container.decode(TradeOfferID.self, forKey: .nextTradeOfferID)
        self.hasPlayedDevCardThisTurn = try container.decode(Bool.self, forKey: .hasPlayedDevCardThisTurn)
        self.hasRolledDiceThisTurn = try container.decode(Bool.self, forKey: .hasRolledDiceThisTurn)
        self.lastDiceTotal = try container.decodeIfPresent(Int.self, forKey: .lastDiceTotal)
        self.cookedDiceRolls = try container.decode([Int].self, forKey: .cookedDiceRolls)
        self.cookedStealChoices = try container.decode([Resource].self, forKey: .cookedStealChoices)
        self.state = try container.decode(State.self, forKey: .state)
        self.log = try container.decode([Action].self, forKey: .log)
        if container.contains(.resourcesMap) {
            self.resourcesMap = try container.decode([ResourceID: Resource].self, forKey: .resourcesMap)
            self.bankResourceIDs = try container.decode([ResourceID].self, forKey: .bankResourceIDs)
            self.devCardsMap = try container.decode([DevCardID: DevCard].self, forKey: .devCardsMap)
            self.devCardDeck = try container.decode([DevCardID].self, forKey: .devCardDeck)
            self.playerHands = try container.decode([PlayerHand].self, forKey: .playerHands)
        } else {
            let hands = try container.decode([LegacyPlayerHand].self, forKey: .playerHands)
            let deck = try container.decode([DevCard].self, forKey: .devCardDeck)
            self.resourcesMap = [:]
            self.bankResourceIDs = []
            self.devCardsMap = [:]
            self.devCardDeck = deck.map(\.id)
            self.playerHands = hands.map { hand in
                PlayerHand(player: hand.player,
                           heldDevCardIDs: hand.heldDevCards.map(\.id),
                           playedDevCardIDs: hand.playedDevCards.map(\.id),
                           devCardIDsPurchasedThisTurn: hand.devCardIDsPurchasedThisTurn,
                           remainingHomesteads: hand.remainingHomesteads,
                           remainingTowns: hand.remainingTowns,
                           remainingTrails: hand.remainingTrails)
            }
            for card in deck + hands.flatMap({ $0.heldDevCards + $0.playedDevCards }) {
                if let existing = devCardsMap[card.id], existing != card {
                    throw DecodingError.dataCorruptedError(forKey: .devCardDeck, in: container, debugDescription: "Conflicting development card identities")
                }
                devCardsMap[card.id] = card
            }
            // Migration is deterministic so decoding the same saved round on two
            // machines produces the same card identities. Preserve existing hands,
            // even if the old unlimited bank issued more than the physical supply.
            let supply = hands.count >= Self.expansionThreshold ? 24 : 19
            for resource in Resource.allCases {
                var ordinal = 0
                for index in hands.indices {
                    let count = hands[index].resources[resource] ?? 0
                    guard count >= 0 else {
                        throw DecodingError.dataCorruptedError(forKey: .playerHands, in: container, debugDescription: "Negative resource count")
                    }
                    for _ in 0..<count {
                        let resourceID = Self.legacyResourceID(roundID: id, resource: resource, ordinal: ordinal)
                        resourcesMap[resourceID] = resource
                        playerHands[index].resourceIDs.append(resourceID)
                        ordinal += 1
                    }
                }
                while ordinal < supply {
                    let resourceID = Self.legacyResourceID(roundID: id, resource: resource, ordinal: ordinal)
                    resourcesMap[resourceID] = resource
                    bankResourceIDs.append(resourceID)
                    ordinal += 1
                }
            }
        }
    }

    private static func legacyResourceID(roundID: String, resource: Resource, ordinal: Int) -> ResourceID {
        let seed = "\(roundID.utf8.count):\(roundID):\(resource.rawValue):\(ordinal)"
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LegacyPlayerHand: Decodable {
    let player: Player
    let resources: [Resource: Int]
    let heldDevCards: [DevCard]
    let playedDevCards: [DevCard]
    let devCardIDsPurchasedThisTurn: [DevCardID]
    let remainingHomesteads: Int
    let remainingTowns: Int
    let remainingTrails: Int
}
