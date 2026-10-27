import SwiftUI
import UIKit

struct RootView: View {

    @StateObject private var store = SentinelStore()
    @State private var tab: SentinelTab = .realtime

    var body: some View {
        if #available(iOS 26.0, *) {
            nativeRoot
        } else {
            customRoot
        }
    }

    @available(iOS 26.0, *)
    private var nativeRoot: some View {
        TabView(selection: $tab) {
            ForEach(SentinelTab.allCases) { item in
                content(for: item)
                    .tag(item)
                    .tabItem {
                        Label(
                            item.title,
                            systemImage: tab == item ? item.selectedIcon : item.icon
                        )
                    }
            }
        }
        .tabViewStyle(.automatic)
        .background(AuroraBackdrop().ignoresSafeArea())
        .environmentObject(store)
        .preferredColorScheme(Aurora.isDark ? .dark : .light)
        .onAppear {
            store.start()
            if tab == .device, store.mode == .lan { store.startDiscovery() }
        }
    }

    private var customRoot: some View {
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

    @ViewBuilder
    private func content(for item: SentinelTab) -> some View {
        switch item {
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
}
