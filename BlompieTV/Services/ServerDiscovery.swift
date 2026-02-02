//
//  ServerDiscovery.swift
//  BlompieTV
//
//  Bonjour/mDNS service discovery for finding Ollama and OpenWebUI servers
//  Created by Jordan Koch on 2/2/2026.
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import Foundation
import Network

struct DiscoveredServer: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int
    let type: AIServerType

    func hash(into hasher: inout Hasher) {
        hasher.combine(host)
        hasher.combine(port)
    }

    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
        lhs.host == rhs.host && lhs.port == rhs.port
    }
}

@MainActor
class ServerDiscovery: ObservableObject {
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var isSearching: Bool = false

    private var browser: NWBrowser?
    private var connections: [NWConnection] = []

    // Common ports to scan
    private let ollamaPorts = [11434]
    private let openwebuiPorts = [3000, 8080, 8000]

    func startDiscovery() {
        isSearching = true
        discoveredServers = []

        // Start Bonjour discovery for HTTP services
        let parameters = NWParameters()
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("Bonjour browser ready")
                case .failed(let error):
                    print("Bonjour browser failed: \(error)")
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                for result in results {
                    self?.resolveService(result)
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser

        // Also try common local network addresses
        scanCommonAddresses()

        // Stop searching after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopDiscovery()
        }
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isSearching = false
    }

    private func resolveService(_ result: NWBrowser.Result) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }

        // Check if it might be an Ollama or OpenWebUI service
        let lowerName = name.lowercased()
        if lowerName.contains("ollama") || lowerName.contains("openwebui") || lowerName.contains("llm") {
            let connection = NWConnection(to: result.endpoint, using: .tcp)

            connection.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    if let endpoint = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = endpoint {
                        Task { @MainActor in
                            let hostString = "\(host)"
                            let serverType: AIServerType = lowerName.contains("openwebui") ? .openwebui : .ollama
                            let server = DiscoveredServer(
                                name: name,
                                host: hostString,
                                port: Int(port.rawValue),
                                type: serverType
                            )
                            if !self!.discoveredServers.contains(server) {
                                self?.discoveredServers.append(server)
                            }
                        }
                    }
                }
            }

            connection.start(queue: .main)
            connections.append(connection)
        }
    }

    private func scanCommonAddresses() {
        // Try common local addresses
        let commonHosts = [
            "localhost",
            "127.0.0.1",
            "192.168.1.1",
            "192.168.0.1",
            "10.0.0.1"
        ]

        // Also try to find addresses in the local network range
        Task {
            for host in commonHosts {
                await checkHost(host)
            }

            // Try scanning common local network patterns
            for i in 1...20 {
                await checkHost("192.168.1.\(i)")
                await checkHost("192.168.0.\(i)")
                await checkHost("10.0.0.\(i)")
            }
        }
    }

    private func checkHost(_ host: String) async {
        // Check Ollama ports
        for port in ollamaPorts {
            if await isServerReachable(host: host, port: port) {
                let server = DiscoveredServer(
                    name: "Ollama on \(host)",
                    host: host,
                    port: port,
                    type: .ollama
                )
                if !discoveredServers.contains(server) {
                    discoveredServers.append(server)
                }
            }
        }

        // Check OpenWebUI ports
        for port in openwebuiPorts {
            if await isServerReachable(host: host, port: port) {
                let server = DiscoveredServer(
                    name: "OpenWebUI on \(host)",
                    host: host,
                    port: port,
                    type: .openwebui
                )
                if !discoveredServers.contains(server) {
                    discoveredServers.append(server)
                }
            }
        }
    }

    private func isServerReachable(host: String, port: Int) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode < 500
            }
            return false
        } catch {
            return false
        }
    }
}
