import Foundation

extension AppStore {
    /// Single app boundary for any adaptive question-population provider. It
    /// cannot produce a payload until the installed offline bank verifies at
    /// 1,000 unique contracts in every lab, and PCC additionally requires the
    /// caller to supply current explicit off-device consent.
    func adaptiveQuestionPopulationDecision(
        destination: NFAdaptiveGenerationDestination,
        sourceContext: NFAdaptiveSourceContext = .sourceFree,
        offDeviceConsent: NFOffDevicePersonalizationConsent? = nil,
        referenceDate: Date = .now
    ) -> NFAdaptiveQuestionPopulationDecision {
        NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: destination,
            profile: profileSnapshot,
            attempts: attempts,
            bundledFloor: NFOfflineQuestionBank.adaptivePopulationFloorEvidence,
            sourceContext: sourceContext,
            offDeviceConsent: offDeviceConsent,
            referenceDate: referenceDate
        )
    }
}
