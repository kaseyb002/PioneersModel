import Foundation

public struct Round: Equatable, Codable, Sendable {
    // MARK: - Constants

    public static let maxLogActions: Int = 100
    public static let victoryPointsToWin: Int = 10
    public static let maxHandSizeBeforeDiscard: Int = 7
    public static let longestRoadMin: Int = 5
    public static let largestArmyMin: Int = 3
    public static let initialHomesteadsPerPlayer: Int = 2
    public static let initialTrailsPerPlayer: Int = 2
    public static let homesteadsPerPlayer: Int = 5
    public static let townsPerPlayer: Int = 4
    public static let trailsPerPlayer: Int = 15
    public static let minPlayers: Int = 3
    public static let maxPlayers: Int = 6
    public static let expansionThreshold: Int = 5
    public static let longestRoadVictoryPoints: Int = 2
    public static let largestArmyVictoryPoints: Int = 2

    // MARK: - Costs

    public static let trailCost: [Resource: Int] = [.wood: 1, .brick: 1]
    public static let homesteadCost: [Resource: Int] = [.wood: 1, .brick: 1, .wheat: 1, .sheep: 1]
    public static let townCost: [Resource: Int] = [.wheat: 2, .ore: 3]
    public static let devCardCost: [Resource: Int] = [.wheat: 1, .sheep: 1, .ore: 1]

    // MARK: - Identity

    public let id: String
    public let started: Date
    public internal(set) var ended: Date?

    // MARK: - Board (from GameMap at init time)

    public let tiles: [Tile]
    public let vertices: [Vertex]
    public let edges: [Edge]
    public let ports: [Port]

    // MARK: - Dynamic game state

    public internal(set) var playerHands: [PlayerHand]
    public internal(set) var buildings: [Building]
    public internal(set) var trails: [Trail]
    public internal(set) var outlawTileID: TileID
    public internal(set) var devCardDeck: [DevCard]
    public internal(set) var openTradeOffer: TradeOffer?
    public internal(set) var longestRoadHolder: PlayerID?
    public internal(set) var largestArmyHolder: PlayerID?

    /// Monotonically increasing TradeOffer id.
    public internal(set) var nextTradeOfferID: TradeOfferID
    /// Flag reset each turn; true after the active player plays any non-landmark dev card.
    public internal(set) var hasPlayedDevCardThisTurn: Bool
    /// Has the active player rolled dice this turn yet? Reset at `endTurn`.
    public internal(set) var hasRolledDiceThisTurn: Bool
    /// The most recently rolled dice total (for display / log inspection). Nil before the first roll.
    public internal(set) var lastDiceTotal: Int?
    /// Dice rolls remaining in the cooked queue (consumed by `rollDice`); empty means use RNG.
    internal var cookedDiceRolls: [Int]
    /// Pending random resources for stealing during testing (consumed by steal if non-empty).
    internal var cookedStealChoices: [Resource]

    // MARK: - State

    public internal(set) var state: State
    public internal(set) var log: [Action]

    // MARK: - State machine

    public enum State: Equatable, Codable, Sendable {
        /// Snake-order setup: each player places 2 homesteads + 2 trails.
        case setup(pendingPlacements: [SetupPlacement])
        case waitingForPlayer(id: PlayerID, phase: TurnPhase)
        /// Between turns at >=5 players: non-active players take a single build/pass each in rotation.
        case specialBuildPhase(originatingPlayerID: PlayerID, pending: [PlayerID])
        case gameComplete(winner: Player)

        public var logValue: String {
            switch self {
            case .setup:
                "Setting up the board"
            case .waitingForPlayer(let id, let phase):
                "Waiting for \(id) (\(phase))"
            case .specialBuildPhase(_, let pending):
                "Special Build Phase (pending: \(pending.count))"
            case .gameComplete(let winner):
                "\(winner.name) won the round"
            }
        }
    }

    public enum TurnPhase: Equatable, Codable, Sendable {
        /// Turn just started; the active player must roll the dice.
        case beforeRoll
        /// 7 was rolled; players with >7 resources must discard half (rounded down).
        case discardingAfterSeven(pendingPlayerIDs: [PlayerID])
        /// Outlaw must be moved (either from a 7 roll or from a Ranger play).
        case movingOutlaw(reason: OutlawReason)
        /// After moving the outlaw, if at least one opponent has a building adjacent to the new tile,
        /// the active player picks one to steal from.
        case stealingAfterOutlaw(candidates: [PlayerID], reason: OutlawReason)
        /// Main action phase: build, trade, buy / play dev card, end turn.
        case main
        /// Resolving a Pathfinder dev card; place `remainingTrails` free trails.
        case playingPathfinder(remainingTrails: Int)
        /// Resolving a Bountiful Harvest dev card; choose 2 resources from the bank.
        case playingBountifulHarvest
        /// Resolving a Roundup dev card; choose one resource to take from all opponents.
        case playingRoundup
    }

    public enum OutlawReason: Equatable, Codable, Sendable {
        case rolledSeven
        case playedRanger(devCardID: DevCardID)
    }

    // MARK: - Setup placements

    public struct SetupPlacement: Equatable, Codable, Sendable {
        public let playerID: PlayerID
        public let lap: Int // 1 or 2 (snake order: up then down)
        public let step: Step

        public enum Step: String, Equatable, Codable, CaseIterable, Sendable {
            case homestead
            case trail
        }

        public enum CodingKeys: String, CodingKey {
            case playerID = "playerId"
            case lap
            case step
        }

        public init(playerID: PlayerID, lap: Int, step: Step) {
            self.playerID = playerID
            self.lap = lap
            self.step = step
        }
    }

    // MARK: - Action log

    public struct Action: Equatable, Codable, Sendable {
        public let playerID: PlayerID
        public let decision: Decision
        public let timestamp: Date

        public enum CodingKeys: String, CodingKey {
            case playerID = "playerId"
            case decision
            case timestamp
        }

        public init(
            playerID: PlayerID,
            decision: Decision,
            timestamp: Date = .now
        ) {
            self.playerID = playerID
            self.decision = decision
            self.timestamp = timestamp
        }
    }

    public enum Decision: Equatable, Codable, Sendable {
        case placedInitialHomestead(vertexID: VertexID)
        case placedInitialTrail(edgeID: EdgeID)
        case rolledDice(total: Int)
        case collectedResources(perPlayer: [PlayerID: [Resource: Int]])
        case discardedResources(resources: [Resource: Int])
        case movedOutlaw(toTileID: TileID)
        case stoleResource(from: PlayerID, resource: Resource?)
        case builtHomestead(vertexID: VertexID)
        case upgradedToTown(vertexID: VertexID)
        case builtTrail(edgeID: EdgeID)
        case boughtDevCard
        case playedDevCard(DevCardPlay)
        case postedTradeOffer(id: TradeOfferID)
        case cancelledTradeOffer(id: TradeOfferID)
        case acceptedTradeOffer(id: TradeOfferID, acceptorID: PlayerID)
        case bankTrade(give: [Resource: Int], receive: [Resource: Int])
        case portTrade(portID: PortID, give: [Resource: Int], receive: [Resource: Int])
        case longestRoadAwarded
        case largestArmyAwarded
        case endedTurn
        case specialBuildPass
        case winnerDeclared(playerID: PlayerID)
    }

    public enum DevCardPlay: Equatable, Codable, Sendable {
        case ranger
        case pathfinder
        case roundup(resource: Resource, collected: Int)
        case bountifulHarvest(resources: [Resource])
    }
}
