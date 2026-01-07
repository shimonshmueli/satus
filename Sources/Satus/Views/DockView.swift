import SwiftUI
import UniformTypeIdentifiers

struct DockDragItem: Codable, Transferable {
    let id: String
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

struct DockView: View {
    @EnvironmentObject var appService: AppService
    
    // Grid Configuration
    let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 120), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(appService.dockItems) { item in
                    DockItemView(item: item)
                        .draggable(DockDragItem(id: item.id))
                }
            }
            .padding()
            .frame(minHeight: 400) // Ensure drop area
            .onDrop(of: [.url], isTargeted: nil) { providers in
                // Handle drop from "All Apps" (File URLs)
                Task {
                    for provider in providers {
                        if let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? URL {
                            if let app = appService.apps.first(where: { $0.url.path == url.path }) {
                                await MainActor.run {
                                    if !appService.dockItems.contains(where: { $0.id == app.id }) {
                                        appService.dockItems.append(.app(id: app.id))
                                    }
                                }
                            }
                        }
                    }
                }
                return true
            }
        }
    }
}

struct DockItemView: View {
    let item: DockItem
    @EnvironmentObject var appService: AppService
    @State private var isTargeted = false
    
    var body: some View {
        Group {
            switch item {
            case .app(let id):
                if let app = appService.apps.first(where: { $0.id == id }) {
                    DockAppIcon(app: app)
                } else {
                     // Placeholder
                     Color.gray.opacity(0.3)
                         .frame(width: 64, height: 64)
                         .cornerRadius(12)
                }
            case .group(let id, let items):
                DockGroupView(groupId: id, itemIDs: items)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle()) // Ensure hit test works on entire area
        .dropDestination(for: DockDragItem.self) { items, _ in
             guard let source = items.first else { return false }
             if source.id == item.id { return false } // Can't drop on self
             
             // Check source item existence (it must be in Dock)
             guard let sourceItem = appService.dockItems.first(where: { $0.id == source.id }) else { return false }
             
             // Handle by Type
             switch item {
             case .app(let myId):
                 // I am an App. Dropping something on me creates a New Group.
                 withAnimation {
                     appService.groupDockItems(targetId: myId, sourceId: sourceItem.id)
                 }
                 return true
                 
             case .group(let myId, _):
                 // I am a Group. Dropping something on me adds it to me.
                 // Only supports adding Apps to Groups for now (no nested groups)
                 if case .app(let sourceAppId) = sourceItem {
                     withAnimation {
                         appService.addAppToGroup(groupId: myId, appId: sourceAppId)
                     }
                     return true
                 } else if case .group(_, let sourceItems) = sourceItem {
                     // OPTIONAL: Merge Groups?
                     // Currently ignoring group-on-group
                 }
             }
             return false
        } isTargeted: { targeted in
            withAnimation {
                isTargeted = targeted
            }
        }
    }
}

struct DockAppIcon: View {
    let app: AppItem
    
    var body: some View {
        VStack {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
            // No Text
        }
        .help(app.name)
        .padding(8)
        .contentShape(Rectangle())
    }
}

struct DockGroupView: View {
    let groupId: UUID
    let itemIDs: [String]
    @EnvironmentObject var appService: AppService
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(itemIDs, id: \.self) { id in
                if let app = appService.apps.first(where: { $0.id == id }) {
                    DockAppIcon(app: app)
                        .scaleEffect(0.8) // Smaller in group?
                        .frame(width: 50, height: 50)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
