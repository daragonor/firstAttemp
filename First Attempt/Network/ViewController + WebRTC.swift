//
//  ViewController + WebRTC.swift
//  First Attempt
//
//  Created by Daniel Aragon on 4/7/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import Foundation
import WebRTC

extension ViewController: SignalClientDelegate {
    
    func signalClientDidConnect(_ signalClient: SignalingClient) {
        self.signalingConnected = true
    }

    func signalClientDidDisconnect(_ signalClient: SignalingClient) {
        self.signalingConnected = false
    }

    func signalClient(_ signalClient: SignalingClient, didReceiveRemoteSdp sdp: RTCSessionDescription) {
        print("Received remote sdp")
        self.webRTCClient.set(remoteSdp: sdp) { (error) in
            if let error = error { print(error) }
        }
    }

    func signalClient(_ signalClient: SignalingClient, didReceiveCandidate candidate: RTCIceCandidate) {
        print("Received remote candidate")
        self.webRTCClient.set(remoteCandidate: candidate)
    }
}

extension ViewController: WebRTCClientDelegate {
    
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        print("discovered local candidate")
        self.signalClient.send(candidate: candidate)
    }

    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        let textColor: UIColor
        switch state {
        case .connected, .completed:
            textColor = .green
        case .disconnected:
            textColor = .orange
        case .failed, .closed:
            textColor = .red
        case .new, .checking, .count:
            textColor = .black
        @unknown default:
            textColor = .black
        }
        DispatchQueue.main.async {
            self.webRTCStatusLabel?.text = state.description.capitalized
            self.webRTCStatusLabel?.textColor = textColor
        }
    }

    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {

        if let position = try? JSONDecoder().decode([String: Float].self, from: data) {
            insertTower(at: SIMD3<Float>(position["x"]!, position["y"]!, position["z"]! ))
        }
    }
}
