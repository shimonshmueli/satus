import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("ZoneKey Help")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)
                
                Group {
                    SectionHeader(title: "Overview")
                    Text("ZoneKey is an app launcher and switcher designed for speed and efficiency.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    SectionHeader(title: "Navigation")
                    HelpRow(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "Arrow Keys", description: "Navigate between apps and the sidebar.")
                    HelpRow(icon: "return", title: "Enter", description: "Launch the selected app.")
                    HelpRow(icon: "escape", title: "Escape", description: "Hide ZoneKey.")
                    
                    SectionHeader(title: "Search")
                    HelpRow(icon: "magnifyingglass", title: "Type to Search", description: "Just start typing to filter your apps instantly.")
                    
                    SectionHeader(title: "Drag & Drop")
                    HelpRow(icon: "arrow.down.doc", title: "Add to Dock", description: "Drag an app icon to the Dock to keep it there.")
                    HelpRow(icon: "tag", title: "Assign Tags", description: "Drag an app to a tag in the sidebar to assign it.")
                    
                    SectionHeader(title: "Organization")
                    HelpRow(icon: "tag", title: "Tags", description: "Right-click an app to assign tags. Filter by tags using the sidebar.")
                    HelpRow(icon: "plus.circle", title: "Add Tag", description: "Create new tags via the sidebar 'Add New Tag...' button.")
                    
                    SectionHeader(title: "App Switcher")
                    HelpRow(icon: "macwindow", title: "Open Apps", description: "View and switch between currently running applications.")
                }
            }
            .padding(32)
        }
        .frame(width: 500, height: 600)
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .padding(.top, 8)
    }
}

struct HelpRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
