import SwiftUI

extension View {
    /// Settings and the main window use separate ownership, so they do not both present the same error.
    func appErrorAlert(model: AppModel, inSettings: Bool = false) -> some View {
        alert(model.lastErrorTitle.rawValue, isPresented: Binding(
            get: { model.lastError != nil && model.errorInSettings == inSettings },
            set: { if !$0 { model.dismissError(inSettings: inSettings) } }
        )) {
            Button("OK") { model.dismissError(inSettings: inSettings) }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
