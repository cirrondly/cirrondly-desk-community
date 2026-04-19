import SwiftUI

struct WeeklyProgressBar: View {
    let window: Window

    var body: some View {
        SessionProgressBar(title: window.kind.title, window: window)
    }
}