import Foundation

extension Round {
    /// Creates a new round.
    ///
    /// - Parameters:
    ///   - id: Stable identifier for this round. Defaults to a fresh UUID string.
    ///   - started: Start timestamp. Defaults to `.now`.
    ///   - players: 3-6 players with distinct IDs and colors. Seats/turn order follows array order.
    ///   - numberTokenLayout: Number-token placement policy. Defaults to the official spiral setup.
    ///   - expansionRuleSet: Five/six-player turn rules. Defaults to revised paired players.
    ///     Choose `.specialBuilding` for the original rules. Has no effect at three/four players.
    ///   - cookedMap: When non-nil, use this GameMap exactly (no selection between standard/expansion).
    ///   - cookedNumberTokenOrder: Non-nil disables number-token shuffling; list must contain one
    ///     token per non-desert tile (in the order those tiles appear in `tiles`).
    ///   - cookedDevCardDeck: Non-nil disables dev-card shuffling.
    ///   - cookedDiceRolls: Non-empty queue consumed by `rollDice` in order (then RNG takes over).
    ///   - cookedStealChoices: Non-empty queue consumed by steal resolution in order.
    public init(
        id: String = UUID().uuidString,
        started: Date = .now,
        players: [Player],
        numberTokenLayout: NumberTokenLayout = .standardSpiral,
        expansionRuleSet: ExpansionRuleSet = .pairedPlayers,
        cookedMap: GameMap? = nil,
        cookedNumberTokenOrder: [Int]? = nil,
        cookedDevCardDeck: [DevCard]? = nil,
        cookedDiceRolls: [Int] = [],
        cookedStealChoices: [Resource] = []
    ) throws {
        guard players.count >= Self.minPlayers else { throw PioneersModelError.notEnoughPlayers }
        guard players.count <= Self.maxPlayers else { throw PioneersModelError.tooManyPlayers }
        let ids: Set<PlayerID> = Set(players.map(\.id))
        guard ids.count == players.count else { throw PioneersModelError.duplicatePlayerIDs }
        let colors: Set<PlayerColor> = Set(players.map(\.color))
        guard colors.count == players.count else { throw PioneersModelError.duplicatePlayerColors }

        let template: GameMap = cookedMap ?? (players.count >= Self.expansionThreshold ? .expansion() : .standard())
        // Cooked maps keep a fixed terrain layout for tests and previews. Live games shuffle hex types.
        let baseMap: GameMap = cookedMap == nil ? template.shufflingTileTypes() : template

        let nonDesertCount: Int = baseMap.tiles.filter { $0.type != .desert }.count
        guard cookedNumberTokenOrder?.count ?? nonDesertCount == nonDesertCount else {
            throw PioneersModelError.invalidDiceTotal
        }
        let tokenAssignments: [TileID: Int]
        if let cookedNumberTokenOrder {
            let nonDesertTiles: [Tile] = baseMap.tiles.filter { $0.type != .desert }
            tokenAssignments = Dictionary(uniqueKeysWithValues: zip(nonDesertTiles.map(\.id), cookedNumberTokenOrder))
        } else {
            tokenAssignments = Self.numberTokenAssignments(for: baseMap, layout: numberTokenLayout)
        }
        let assignedTiles: [Tile] = baseMap.tiles.map { tile in
            Tile(
                id: tile.id,
                coord: tile.coord,
                type: tile.type,
                numberToken: tokenAssignments[tile.id],
                vertexIDs: tile.vertexIDs,
                edgeIDs: tile.edgeIDs
            )
        }

        // Outlaw starts on the first desert (there is always at least one on either map).
        let desertTileID: TileID = assignedTiles.first(where: { $0.type == .desert })?.id ?? 0

        // Build setup queue: snake order, homestead then trail for each placement.
        var pendingPlacements: [SetupPlacement] = []
        for player in players {
            pendingPlacements.append(SetupPlacement(playerID: player.id, lap: 1, step: .homestead))
            pendingPlacements.append(SetupPlacement(playerID: player.id, lap: 1, step: .trail))
        }
        for player in players.reversed() {
            pendingPlacements.append(SetupPlacement(playerID: player.id, lap: 2, step: .homestead))
            pendingPlacements.append(SetupPlacement(playerID: player.id, lap: 2, step: .trail))
        }

        let deck: [DevCard] = cookedDevCardDeck ?? baseMap.devCardDeck.shuffled()

        self.selectedExpansionRuleSet = expansionRuleSet
        self.pairedTurnOriginatingPlayerID = nil
        self.id = id
        self.started = started
        self.ended = nil
        self.tiles = assignedTiles
        self.vertices = baseMap.vertices
        self.edges = baseMap.edges
        self.ports = baseMap.ports
        self.playerHands = players.map { PlayerHand(player: $0) }
        self.buildings = []
        self.trails = []
        self.outlawTileID = desertTileID
        self.devCardDeck = deck
        self.openTradeOffer = nil
        self.longestRoadHolder = nil
        self.largestArmyHolder = nil
        self.nextTradeOfferID = 1
        self.hasPlayedDevCardThisTurn = false
        self.hasRolledDiceThisTurn = false
        self.lastDiceTotal = nil
        self.cookedDiceRolls = cookedDiceRolls
        self.cookedStealChoices = cookedStealChoices
        self.state = .setup(pendingPlacements: pendingPlacements)
        self.log = []
    }

    private static func numberTokenAssignments(
        for map: GameMap,
        layout: NumberTokenLayout
    ) -> [TileID: Int] {
        switch layout {
        case .standardSpiral:
            let tokens: [Int]
            switch map.numberTokenBag.count {
            case GameMap.standardNumberTokens.count:
                tokens = GameMap.standardSpiralNumberTokens
            case GameMap.expansionNumberTokens.count:
                tokens = GameMap.expansionSpiralNumberTokens
            default:
                tokens = map.numberTokenBag
            }
            let tileIDs: [TileID] = map.spiralTileIDs().filter { id in
                map.tiles.first(where: { $0.id == id })?.type != .desert
            }
            precondition(tileIDs.count == tokens.count, "Number-token count must match non-desert tile count")
            return Dictionary(uniqueKeysWithValues: zip(tileIDs, tokens))

        case .randomSeparatedRed:
            let nonDesertTiles: [Tile] = map.tiles.filter { $0.type != .desert }
            for _ in 0..<10_000 {
                let tokens: [Int] = map.numberTokenBag.shuffled()
                let hasAdjacentRedNumbers: Bool = zip(nonDesertTiles, tokens).contains { tile, token in
                    guard token == 6 || token == 8 else { return false }
                    return zip(nonDesertTiles, tokens).contains { otherTile, otherToken in
                        otherTile.id != tile.id
                            && (otherToken == 6 || otherToken == 8)
                            && map.areAdjacent(tile, otherTile)
                    }
                }
                if !hasAdjacentRedNumbers {
                    return Dictionary(uniqueKeysWithValues: zip(nonDesertTiles.map(\.id), tokens))
                }
            }
            preconditionFailure("Unable to produce a number-token layout with separated red numbers")
        }
    }
}
