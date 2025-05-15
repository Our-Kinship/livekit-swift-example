/*
 * Copyright 2025 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import LiveKit
import SFSafeSymbols
import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var appCtx: AppContext
    @EnvironmentObject var roomCtx: RoomContext
    @EnvironmentObject var room: Room

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .center, spacing: 40.0) {
                    VStack(spacing: 10) {
                        Image("logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 30)
                            .padding(.bottom, 10)
                        Text("SDK Version \(LiveKitSDK.version)")
                            .opacity(0.5)
                        Text("Example App Version \(Bundle.main.appVersionLong) (\(Bundle.main.appBuild))")
                            .opacity(0.5)
                    }

                    VStack(spacing: 15) {
                        LKTextField(title: "Server URL", text: $roomCtx.url, type: .URL)
                        LKTextField(title: "Token", text: $roomCtx.token, type: .secret)
                        LKTextField(title: "E2EE Key", text: $roomCtx.e2eeKey, type: .secret)

                        HStack {
                            Menu {
                                Toggle("Auto-Subscribe", isOn: $roomCtx.autoSubscribe)
                                Toggle("Enable E2EE", isOn: $roomCtx.isE2eeEnabled)
                            } label: {
                                Image(systemSymbol: .boltFill)
                                    .renderingMode(.original)
                                Text("Connect Options")
                            }
                            #if os(macOS)
                            .menuIndicator(.visible)
                            .menuStyle(BorderlessButtonMenuStyle())
                            #elseif os(iOS)
                            .menuStyle(BorderlessButtonMenuStyle())
                            #endif
                            .fixedSize()

                            Menu {
                                Toggle("Simulcast", isOn: $roomCtx.simulcast)
                                Toggle("AdaptiveStream", isOn: $roomCtx.adaptiveStream)
                                Toggle("Dynacast", isOn: $roomCtx.dynacast)
                                Toggle("Report stats", isOn: $roomCtx.reportStats)
                            } label: {
                                Image(systemSymbol: .gear)
                                    .renderingMode(.original)
                                Text("Room Options")
                            }
                            #if os(macOS)
                            .menuIndicator(.visible)
                            .menuStyle(BorderlessButtonMenuStyle())
                            #elseif os(iOS)
                            .menuStyle(BorderlessButtonMenuStyle())
                            #endif
                            .fixedSize()
                        }
                    }.frame(maxWidth: 350)

                    if case .connecting = room.connectionState {
                        HStack(alignment: .center) {
                            ProgressView()

                            LKButton(title: "Cancel") {
                                roomCtx.cancelConnect()
                            }
                        }
                    } else {
                        HStack(alignment: .center) {
                            Spacer()

                            LKButton(title: "Connect", action: connectButtonAction)

                            if !appCtx.connectionHistory.isEmpty {
                                Menu {
                                    ForEach(appCtx.connectionHistory.sortedByUpdated) { entry in
                                        Button {
                                            Task { @MainActor in
                                                let room = try await roomCtx.connect(entry: entry)
                                                appCtx.connectionHistory.update(room: room, e2ee: roomCtx.isE2eeEnabled, e2eeKey: roomCtx.e2eeKey)
                                            }
                                        } label: {
                                            Image(systemSymbol: .boltFill)
                                                .renderingMode(.original)
                                            Text(String(describing: entry))
                                        }
                                    }

                                    Divider()

                                    Button {
                                        appCtx.connectionHistory.removeAll()
                                    } label: {
                                        Image(systemSymbol: .xmarkCircleFill)
                                            .renderingMode(.original)
                                        Text("Clear history")
                                    }

                                } label: {
                                    Image(systemSymbol: .clockFill)
                                        .renderingMode(.original)
                                    Text("Recent")
                                }
                                #if os(macOS)
                                .menuIndicator(.visible)
                                .menuStyle(BorderlessButtonMenuStyle())
                                #elseif os(iOS)
                                .menuStyle(BorderlessButtonMenuStyle())
                                #endif
                                .fixedSize()
                            }

                            Spacer()
                        }
                    }
                }
                .padding()
                .frame(width: geometry.size.width) // Make the scroll view full-width
                .frame(minHeight: geometry.size.height) // Set the content’s min height to the parent
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
        .alert(isPresented: $roomCtx.shouldShowDisconnectReason) {
            Alert(title: Text("Disconnected"),
                  message: Text("Reason: " + String(describing: roomCtx.latestError)))
        }
        .task {
            roomCtx.url = ""
            roomCtx.token = ""
            try? await Task.sleep(for: .seconds(10))
            
            if let details = try? await fetchConnectionDetails() {
                roomCtx.url = details.serverUrl
                roomCtx.token = details.participantToken
                connectButtonAction()
            }
        }
    }
    
    private func connectButtonAction() {
        Task { @MainActor in
            let room = try await roomCtx.connect()
            appCtx.connectionHistory.update(room: room, e2ee: roomCtx.isE2eeEnabled, e2eeKey: roomCtx.e2eeKey)
        }
    }

    private func fetchConnectionDetails() async throws -> ConnectionDetails {
        // Create URL for the request
        let url = URL(string: "https://cloud-api.livekit.io/api/sandbox/connection-details")!
        
        // Create URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("YOUR_SANDBOX_ID", forHTTPHeaderField: "X-Sandbox-ID")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{ \"roomName\": \"test-room\" }".data(using: .utf8)
        
        // Perform the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check HTTP status code
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ConnectionTesterError",
                          code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Decode the response
        return try JSONDecoder().decode(ConnectionDetails.self, from: data)
    }
}

private struct ConnectionDetails: Codable {
    let serverUrl: String
    let participantToken: String
}
