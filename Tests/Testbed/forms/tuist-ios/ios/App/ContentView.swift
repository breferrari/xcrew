import SwiftUI

enum Greeting {
    static let text = "Hello"
}

struct ContentView: View {
    var body: some View {
        Text(Greeting.text)
    }
}
