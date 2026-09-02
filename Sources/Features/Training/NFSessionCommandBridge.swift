import Foundation
import Observation

/// The exact set of app-menu commands that the visible universal session can
/// consume. Keeping this separate from `activeSessionRequest` prevents a
/// presented confidence or summary screen from swallowing an advance command
/// that has no meaning in that phase, while feedback can still consume Next and
/// every non-summary phase can pause or show scratch work.
struct NFSessionCommandCapabilities: Equatable, Sendable {
    let canAdvance: Bool
    let canTogglePause: Bool
    let canShowScratchpad: Bool

    static let inactive = NFSessionCommandCapabilities(
        canAdvance: false,
        canTogglePause: false,
        canShowScratchpad: false
    )

    static func resolve(
        stage: NFSessionStage,
        isPaused: Bool,
        canSubmit: Bool
    ) -> NFSessionCommandCapabilities {
        if stage == .summary {
            return .inactive
        }
        if isPaused {
            return NFSessionCommandCapabilities(
                canAdvance: false,
                canTogglePause: true,
                canShowScratchpad: false
            )
        }

        switch stage {
        case .item, .selfCheckComparison:
            return NFSessionCommandCapabilities(
                canAdvance: canSubmit,
                canTogglePause: true,
                canShowScratchpad: true
            )
        case .confidence, .reflection:
            return NFSessionCommandCapabilities(
                canAdvance: false,
                canTogglePause: true,
                canShowScratchpad: true
            )
        case .feedback:
            return NFSessionCommandCapabilities(
                canAdvance: true,
                canTogglePause: true,
                canShowScratchpad: true
            )
        case .summary:
            // Handled before paused-state resolution so an inconsistent stale
            // pause flag can never re-enable a command after completion.
            return .inactive
        }
    }
}

enum NFSessionCommand: Equatable, Sendable {
    case advance
    case togglePause
    case showScratchpad
}

@MainActor
@Observable
final class NFSessionCommandBridge {
    private(set) var activeRequestID: UUID?
    private(set) var capabilities: NFSessionCommandCapabilities = .inactive

    var hasConsumer: Bool { activeRequestID != nil }

    func activate(
        requestID: UUID,
        capabilities: NFSessionCommandCapabilities
    ) {
        activeRequestID = requestID
        self.capabilities = capabilities
    }

    func update(
        requestID: UUID,
        capabilities: NFSessionCommandCapabilities
    ) {
        guard activeRequestID == requestID else { return }
        self.capabilities = capabilities
    }

    func deactivate(requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        capabilities = .inactive
    }

    @discardableResult
    func send(
        _ command: NFSessionCommand,
        center: NotificationCenter = .default
    ) -> Bool {
        guard let activeRequestID, permits(command) else { return false }
        center.post(
            name: notificationName(for: command),
            object: activeRequestID
        )
        return true
    }

    private func permits(_ command: NFSessionCommand) -> Bool {
        switch command {
        case .advance: capabilities.canAdvance
        case .togglePause: capabilities.canTogglePause
        case .showScratchpad: capabilities.canShowScratchpad
        }
    }

    private func notificationName(for command: NFSessionCommand) -> Notification.Name {
        switch command {
        case .advance: .neuroForgeAdvanceUniversalSession
        case .togglePause: .neuroForgeTogglePause
        case .showScratchpad: .neuroForgeShowScratchpad
        }
    }
}
