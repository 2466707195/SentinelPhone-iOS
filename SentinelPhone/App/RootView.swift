import SwiftUI
import UIKit

struct RootView: View {

    @StateObject private var store = SentinelStore()
    @State private var tab: SentinelTab = .realtime

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackdrop()
                .ignoresSafeArea()

            Group {
                switch tab {
                case .realtime:
                    RealtimeView(onOpenDevices: { tab = .device })
                case .playback:
                    PlaybackView()
                case .events:
                    EventsView { sessionID in
                        store.requestedSessionID = sessionID
                        tab = .playback
                    }
                case .device:
                    DeviceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(store)

            AuroraGlassTabBar(selection: $tab)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .preferredColorScheme(Aurora.isDark ? .dark : .light)
        .onAppear {
            store.start()
            if tab == .device, store.mode == .lan { store.startDiscovery() }
        }
    }
}
