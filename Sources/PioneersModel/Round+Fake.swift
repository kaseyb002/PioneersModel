import Foundation

extension Round {
    /// Deterministic fake round for tests / previews. Uses cooked number tokens and dev deck so the
    /// board is reproducible; 3 players by default (standard map).
    public static func fake(
        id: String = "fake-round",
        started: Date = Date(timeIntervalSince1970: 0),
        players: [Player]? = nil,
        cookedDiceRolls: [Int] = []
    ) -> Round {
        let p: [Player] = players ?? defaultFakePlayers(count: 3)
        let map: GameMap = p.count >= Self.expansionThreshold ? .expansion() : .standard()
        do {
            return try Round(
                id: id,
                started: started,
                players: p,
                cookedMap: map,
                cookedNumberTokenOrder: map.numberTokenBag,
                cookedDevCardDeck: map.devCardDeck,
                cookedDiceRolls: cookedDiceRolls
            )
        } catch {
            preconditionFailure("Round.fake failed: \(error)")
        }
    }

    /// A mid-game fake round: every player has completed setup (placed 2 homesteads + 2 trails),
    /// the first player is at `.beforeRoll`, and each player has a small starting resource stash.
    public static func fakeInProgress(
        id: String = "fake-in-progress",
        players: [Player]? = nil
    ) -> Round {
        var round: Round = .fake(id: id, players: players)
        // Automate the setup phase: place homesteads on spread-apart vertices.
        _ = autoCompleteSetup(&round)
        // Give each player a comfortable starting bundle.
        for i in round.playerHands.indices {
            round.playerHands[i].resources = [
                .wood: 2,
                .brick: 2,
                .wheat: 2,
                .sheep: 1,
                .ore: 1,
            ]
        }
        return round
    }

    /// A completed fake round (game-over state) with the first player as winner.
    public static func fakeCompleted(
        id: String = "fake-completed",
        players: [Player]? = nil
    ) -> Round {
        var round: Round = .fakeInProgress(id: id, players: players)
        // Declare the first player the winner artificially.
        if let winner: Player = round.playerHands.first?.player {
            round.ended = Date(timeIntervalSince1970: 100_000)
            round.state = .gameComplete(winner: winner)
            round.logAction(playerID: winner.id, decision: .winnerDeclared(playerID: winner.id))
        }
        return round
    }

    static func defaultFakePlayers(count: Int) -> [Player] {
        let colors: [PlayerColor] = PlayerColor.allCases
        return (0..<count).map { i in
            Player(id: "p\(i + 1)", name: "Player \(i + 1)", color: colors[i % colors.count])
        }
    }

    /// Auto-completes setup on the given round by greedily placing legal homesteads and trails.
    /// Returns the round after all placements are done. Useful for tests and fakes.
    @discardableResult
    static func autoCompleteSetup(_ round: inout Round) -> Bool {
        while case .setup(let pending) = round.state, let next: SetupPlacement = pending.first {
            switch next.step {
            case .homestead:
                guard let vid: VertexID = round.vertices.first(where: { round.canPlaceHomestead(at: $0.id) })?.id else {
                    return false
                }
                do {
                    try round.placeInitialHomestead(playerID: next.playerID, vertexID: vid)
                } catch {
                    return false
                }
            case .trail:
                // Find most-recent placed homestead vertex for this player (in lap).
                let anchor: VertexID? = round.log.reversed().compactMap { action -> VertexID? in
                    guard action.playerID == next.playerID else { return nil }
                    if case .placedInitialHomestead(let v) = action.decision { return v }
                    return nil
                }.first
                guard let vid: VertexID = anchor, let v: Vertex = round.vertex(id: vid) else { return false }
                guard let eid: EdgeID = v.adjacentEdgeIDs.first(where: { round.trail(at: $0) == nil }) else {
                    return false
                }
                do {
                    try round.placeInitialTrail(playerID: next.playerID, edgeID: eid)
                } catch {
                    return false
                }
            }
        }
        return true
    }
}
