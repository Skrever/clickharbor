import SwiftUI

@main
struct AiroxUtilityApp: App {
    @StateObject private var model = AiroxModel()

    var body: some Scene {
        Window("ClickHarbor", id: "airox") {
            AiroxView(model: model)
                .task { await model.watchConnection() }
        }
        .defaultSize(width: 910, height: 690)
        .windowResizability(.contentMinSize)
    }
}
