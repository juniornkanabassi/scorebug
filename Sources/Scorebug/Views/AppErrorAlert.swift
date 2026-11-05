import SwiftUI

extension View {
    func appErrorAlert(model: AppModel) -> some View {
        alert(ErrorPresentation.title(for: model.lastError ?? ""), isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
