import Foundation

#if canImport(AudioToolbox)
import AudioToolbox
#elseif canImport(AppKit)
import AppKit
#endif

enum NFReinforcementFeedback {
    static func playSound(success: Bool) {
        #if canImport(AudioToolbox)
        AudioServicesPlaySystemSound(success ? 1_104 : 1_053)
        #elseif canImport(AppKit)
        let name = NSSound.Name(success ? "Glass" : "Basso")
        NSSound(named: name)?.play()
        #endif
    }
}
