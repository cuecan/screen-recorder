import ProjectKit
import SwiftUI

extension EditAuthor {
    var symbol: String {
        switch self { case .app: "person.fill"; case .agent: "sparkles"; case .commandLine: "terminal"; case .system: "gearshape" }
    }
    var color: Color { if case .agent = self { .purple } else { .secondary } }
}
