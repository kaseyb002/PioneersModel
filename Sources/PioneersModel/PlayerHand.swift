import Foundation

/// Per-player mutable state during a round: hand resources, dev cards, piece inventory.
public struct PlayerHand: Equatable, Codable, Sendable {
    public var player: Player
    public var resources: [Resource: Int]
    /// Dev cards held in hand (face-down). Not visible to opponents.
    public var heldDevCards: [DevCard]
    /// Dev cards already played (public).
    public var playedDevCards: [DevCard]
    /// IDs of dev cards purchased on the current turn (can't be played until next turn).
    public var devCardIDsPurchasedThisTurn: [DevCardID]
    public var remainingHomesteads: Int
    public var remainingTowns: Int
    public var remainingTrails: Int

    public init(
        player: Player,
        resources: [Resource: Int] = [:],
        heldDevCards: [DevCard] = [],
        playedDevCards: [DevCard] = [],
        devCardIDsPurchasedThisTurn: [DevCardID] = [],
        remainingHomesteads: Int = Round.homesteadsPerPlayer,
        remainingTowns: Int = Round.townsPerPlayer,
        remainingTrails: Int = Round.trailsPerPlayer
    ) {
        self.player = player
        self.resources = resources
        self.heldDevCards = heldDevCards
        self.playedDevCards = playedDevCards
        self.devCardIDsPurchasedThisTurn = devCardIDsPurchasedThisTurn
        self.remainingHomesteads = remainingHomesteads
        self.remainingTowns = remainingTowns
        self.remainingTrails = remainingTrails
    }

    public var totalResourceCount: Int {
        resources.values.reduce(0, +)
    }

    public var rangersPlayed: Int {
        playedDevCards.filter { $0.kind == .ranger }.count
    }

    public var landmarksHeld: Int {
        heldDevCards.filter { $0.kind == .landmark }.count
    }
}

extension PlayerHand {
    public static func fake(
        player: Player = .fake(),
        resources: [Resource: Int] = [:],
        heldDevCards: [DevCard] = [],
        playedDevCards: [DevCard] = [],
        devCardIDsPurchasedThisTurn: [DevCardID] = [],
        remainingHomesteads: Int = Round.homesteadsPerPlayer,
        remainingTowns: Int = Round.townsPerPlayer,
        remainingTrails: Int = Round.trailsPerPlayer
    ) -> PlayerHand {
        PlayerHand(
            player: player,
            resources: resources,
            heldDevCards: heldDevCards,
            playedDevCards: playedDevCards,
            devCardIDsPurchasedThisTurn: devCardIDsPurchasedThisTurn,
            remainingHomesteads: remainingHomesteads,
            remainingTowns: remainingTowns,
            remainingTrails: remainingTrails
        )
    }
}
