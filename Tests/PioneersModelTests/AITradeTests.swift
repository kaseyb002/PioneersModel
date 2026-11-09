import Testing
@testable import PioneersModel

struct AITradeTests {
    /// Isolate town savings from expansion goals, using actual cards and completed setup.
    private func round(
        bot: [Resource: Int],
        proposer: [Resource: Int],
        port: Port.Kind? = nil
    ) throws -> Round {
        let standard = GameMap.standard()
        let firstVertex = try #require(standard.vertices.first)
        let neighbor = try #require(firstVertex.adjacentVertexIDs.first)
        let map = GameMap(
            tiles: standard.tiles, vertices: standard.vertices, edges: standard.edges,
            ports: port.map { [Port(id: 0, kind: $0, vertexIDs: [firstVertex.id, neighbor])] } ?? [],
            numberTokenBag: standard.numberTokenBag, devCardDeck: standard.devCardDeck
        )
        let players = [
            Player(id: "bot", name: "Bot", color: PlayerColor.allCases[0]),
            Player(id: "human", name: "Human", color: PlayerColor.allCases[1]),
            Player(id: "other", name: "Other", color: PlayerColor.allCases[2]),
        ]
        var round = try Round(players: players, cookedMap: map, cookedNumberTokenOrder: map.numberTokenBag)
        #expect(Round.autoCompleteSetup(&round))
        for index in round.playerHands.indices { round.setTestResources([:], at: index) }
        round.setTestResources(bot, at: 0)
        round.setTestResources(proposer, at: 1)
        round.playerHands[0].remainingTrails = 0
        round.playerHands[0].remainingHomesteads = 0
        round.state = .waitingForPlayer(id: "human", phase: .main)
        return round
    }

    @Test(arguments: AIDifficulty.allCases)
    func rejectsExploitativeRatio(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.ore: 5], proposer: [.wood: 1])
        try round.postTradeOffer(give: [.wood: 1], receive: [.ore: 5])
        #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
    }

    @Test(arguments: AIDifficulty.allCases)
    func rejectsUnaffordableOffer(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.wood: 1], proposer: [.ore: 2])
        try round.postTradeOffer(give: [.ore: 2], receive: [.wood: 2])
        #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
    }

    @Test(arguments: AIDifficulty.allCases)
    func acceptsTradeCompletingTownAndAppliesIt(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.wheat: 2, .ore: 2, .wood: 1], proposer: [.ore: 1])
        let offer = try round.postTradeOffer(give: [.ore: 1], receive: [.wood: 1])
        let engine = AIEngine(difficulty: difficulty)
        #expect(try engine.makeMove(on: &round, playerID: "bot") == .acceptTradeOffer(offerID: offer.id))
        #expect(round.openTradeOffer == nil)
        #expect(round.playerHand(for: "bot")?.resources(using: round.resourcesMap) == Round.townCost)
    }

    @Test(arguments: AIDifficulty.allCases)
    func rejectsUnneededResources(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.wheat: 2, .ore: 3, .sheep: 1, .wood: 1], proposer: [.wheat: 1])
        try round.postTradeOffer(give: [.wheat: 1], receive: [.wood: 1])
        #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
    }

    @Test(arguments: [AIDifficulty.medium, .hard])
    func protectsAffordableTownDespiteCompletingDevelopmentCard(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.wheat: 2, .ore: 3], proposer: [.sheep: 1])
        try round.postTradeOffer(give: [.sheep: 1], receive: [.ore: 1])
        #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
    }

    @Test(arguments: AIDifficulty.allCases)
    func acceptsUsefulTrailTrade(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.brick: 1, .sheep: 2], proposer: [.wood: 1])
        round.playerHands[0].remainingTrails = 1
        let offer = try round.postTradeOffer(give: [.wood: 1], receive: [.sheep: 1])
        #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .acceptTradeOffer(offerID: offer.id))
    }

    @Test(arguments: [AIDifficulty.medium, .hard])
    func protectsAffordableTrailDespiteCompletingDevelopmentCard(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.wood: 1, .brick: 1, .ore: 1, .sheep: 1], proposer: [.wheat: 1])
        round.playerHands[0].remainingTrails = 1
        try round.postTradeOffer(give: [.wheat: 1], receive: [.wood: 1])
        #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
    }

    @Test(arguments: AIDifficulty.allCases)
    func overlappingTermsDoNotCountAsProgress(difficulty: AIDifficulty) throws {
        var round = try round(bot: [.ore: 1, .wood: 1], proposer: [.ore: 1, .wood: 1])
        try round.postTradeOffer(give: [.ore: 1, .wood: 1], receive: [.ore: 1, .wood: 1])
        #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
    }

    @Test
    func hardRequiresMoreThanSmallProgress() throws {
        var round = try round(bot: [.wood: 1], proposer: [.ore: 1])
        let offer = try round.postTradeOffer(give: [.ore: 1], receive: [.wood: 1])
        for difficulty in [AIDifficulty.easy, .medium] {
            #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .acceptTradeOffer(offerID: offer.id))
        }
        #expect(AIEngine(difficulty: .hard).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
    }

    @Test
    func ignoresBuildGoalsWithNoAvailablePieces() throws {
        var round = try round(bot: [.wheat: 2, .ore: 2, .wood: 1], proposer: [.ore: 1])
        round.playerHands[0].remainingTowns = 0
        round.devCardDeck = []
        try round.postTradeOffer(give: [.ore: 1], receive: [.wood: 1])
        for difficulty in AIDifficulty.allCases {
            #expect(AIEngine(difficulty: difficulty).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
        }
    }

    @Test
    func hardDemandsFavorableTermsNearVictory() throws {
        var round = try round(bot: [.wheat: 2, .ore: 2, .wood: 1], proposer: [.ore: 1, .sheep: 1])
        // Two towns plus both public awards put the proposer at eight public points.
        round.buildings = round.buildings.map {
            $0.ownerID == "human" ? Building(kind: .town, ownerID: $0.ownerID, vertexID: $0.vertexID) : $0
        }
        round.longestRoadHolder = "human"
        round.largestArmyHolder = "human"
        #expect(round.publicVictoryPoints(for: "human") == 8)
        let fair = try round.postTradeOffer(give: [.ore: 1], receive: [.wood: 1])
        #expect(AIEngine(difficulty: .medium).chooseAction(for: round, playerID: "bot") == .acceptTradeOffer(offerID: fair.id))
        #expect(AIEngine(difficulty: .hard).chooseAction(for: round, playerID: "bot") == .declineTradeOffer)
        let favorable = try round.postTradeOffer(give: [.ore: 1, .sheep: 1], receive: [.wood: 1])
        #expect(AIEngine(difficulty: .hard).chooseAction(for: round, playerID: "bot") == .acceptTradeOffer(offerID: favorable.id))
    }

    @Test
    func hardAccountsForPortBuyingPower() throws {
        for port in [nil, Port.Kind.generic, .specific(.wood), .specific(.ore)] {
            var round = try round(bot: [.wheat: 2, .ore: 1, .wood: 2], proposer: [.ore: 1, .sheep: 1], port: port)
            round.devCardDeck = []
            let offer = try round.postTradeOffer(give: [.ore: 1, .sheep: 1], receive: [.wood: 2])
            #expect(round.ports(ownedBy: "bot").count == (port == nil ? 0 : 1))
            let action = AIEngine(difficulty: .hard).chooseAction(for: round, playerID: "bot")
            #expect(action == (port == .specific(.wood) ? .declineTradeOffer : .acceptTradeOffer(offerID: offer.id)))
        }
    }
}
