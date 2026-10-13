import Foundation

/// Per-player mutable state during a round: hand resources, dev cards, piece inventory.
public struct PlayerHand: Equatable, Codable, Sendable {
    public var player: Player
    public var resourceIDs: [ResourceID]
    /// Dev cards held in hand (face-down). Not visible to opponents.
    public var heldDevCardIDs: [DevCardID]
    /// Dev cards already played (public).
    public var playedDevCardIDs: [DevCardID]
    /// IDs of dev cards purchased on the current turn (can't be played until next turn).
    public var devCardIDsPurchasedThisTurn: [DevCardID]
    public var remainingHomesteads: Int
    public var remainingTowns: Int
    public var remainingTrails: Int

    public init(
        player: Player,
        resourceIDs: [ResourceID] = [],
        heldDevCardIDs: [DevCardID] = [],
        playedDevCardIDs: [DevCardID] = [],
        devCardIDsPurchasedThisTurn: [DevCardID] = [],
        remainingHomesteads: Int = Round.homesteadsPerPlayer,
        remainingTowns: Int = Round.townsPerPlayer,
        remainingTrails: Int = Round.trailsPerPlayer
    ) {
        self.player = player
        self.resourceIDs = resourceIDs
        self.heldDevCardIDs = heldDevCardIDs
        self.playedDevCardIDs = playedDevCardIDs
        self.devCardIDsPurchasedThisTurn = devCardIDsPurchasedThisTurn
        self.remainingHomesteads = remainingHomesteads
        self.remainingTowns = remainingTowns
        self.remainingTrails = remainingTrails
    }

    public var totalResourceCount: Int {
        resourceIDs.count
    }
}

extension PlayerHand {
    public static func fake(
        player: Player = .fake(),
        resourceIDs: [ResourceID] = [],
        heldDevCardIDs: [DevCardID] = [],
        playedDevCardIDs: [DevCardID] = [],
        devCardIDsPurchasedThisTurn: [DevCardID] = [],
        remainingHomesteads: Int = Round.homesteadsPerPlayer,
        remainingTowns: Int = Round.townsPerPlayer,
        remainingTrails: Int = Round.trailsPerPlayer
    ) -> PlayerHand {
        PlayerHand(
            player: player,
            resourceIDs: resourceIDs,
            heldDevCardIDs: heldDevCardIDs,
            playedDevCardIDs: playedDevCardIDs,
            devCardIDsPurchasedThisTurn: devCardIDsPurchasedThisTurn,
            remainingHomesteads: remainingHomesteads,
            remainingTowns: remainingTowns,
            remainingTrails: remainingTrails
        )
    }
}
