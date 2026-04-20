import Foundation

extension Round {
    /// Creates a new round.
    ///
    /// - Parameters:
    ///   - id: Stable identifier for this round. Defaults to a fresh UUID string.
    ///   - started: Start timestamp. Defaults to `.now`.
    ///   - players: 3-6 players with distinct IDs and colors. Seats/turn order follows array order.
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

        let baseMap: GameMap = cookedMap ?? (players.count >= Self.expansionThreshold ? .expansion() : .standard())

        // Assign number tokens to non-desert tiles, either from cooked order or shuffled.
        let tokenOrder: [Int] = cookedNumberTokenOrder ?? baseMap.numberTokenBag.shuffled()
        let nonDesertCount: Int = baseMap.tiles.filter { $0.type != .desert }.count
        guard tokenOrder.count == nonDesertCount else {
            throw PioneersModelError.invalidDiceTotal
        }
        var tokenIdx: Int = 0
        var assignedTiles: [Tile] = []
        for tile in baseMap.tiles {
            if tile.type == .desert {
                assignedTiles.append(tile)
            } else {
                let token: Int = tokenOrder[tokenIdx]
                tokenIdx += 1
                assignedTiles.append(Tile(
                    id: tile.id,
                    coord: tile.coord,
                    type: tile.type,
                    numberToken: token,
                    vertexIDs: tile.vertexIDs,
                    edgeIDs: tile.edgeIDs
                ))
            }
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
}
