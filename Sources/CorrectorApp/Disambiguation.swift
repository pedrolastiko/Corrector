import CorrectorCore
import CorrectorAppCore

/// SwiftUI declares its own `Alert` (the deprecated modal presentation type),
/// which collides with the suggestion model whenever a file imports both.
/// A module-scope alias resolves it once: declarations in the current module
/// take precedence over imported ones.
typealias Alert = CorrectorCore.Alert
