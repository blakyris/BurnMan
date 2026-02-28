import SwiftUI

/// Data DVD section — thin wrapper around the shared `DataDiscSection`.
struct DataDVDSection: View {
    var body: some View {
        DataDiscSection(targetMedia: .dvd)
    }
}
