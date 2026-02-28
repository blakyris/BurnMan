import SwiftUI

/// Data Blu-ray section — thin wrapper around the shared `DataDiscSection`.
struct DataBluraySection: View {
    var body: some View {
        DataDiscSection(targetMedia: .bluray)
    }
}
