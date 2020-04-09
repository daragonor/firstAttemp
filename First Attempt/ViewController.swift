//
//  ViewController.swift
//  First Attempt
//
//  Created by Daniel Aragon on 3/23/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import UIKit
import ARKit
import RealityKit

class ViewController: UIViewController {
    
    var signalClient: SignalingClient!
    var webRTCClient: WebRTCClient!
    let config = Config.default
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var webRTCStatusLabel: UILabel?
    @IBOutlet weak var signalingStatusLabel: UILabel?
    @IBOutlet var arView: ARView!
    @IBOutlet weak var coachingOverlay: ARCoachingOverlayView!
    
    let anchor = AnchorEntity(plane: [.vertical, .horizontal], minimumBounds: [0.2, 0.2])
    let terrainTemplate = try! Entity.loadModel(named: "stone_floor")
    let robotTemplate = try! Entity.loadModel(named: "toy_robot_vintage")

    override func viewDidLoad() {
        super.viewDidLoad()
       
        loadConnectivity()
        loadARView()
        
    }
    
    func loadConnectivity() {
        signalingConnected = false
        signalClient = SignalingClient(webSocket: NativeWebSocket(url: config.signalingServerUrl))
        webRTCClient = WebRTCClient(iceServers: config.webRTCIceServers)
        webRTCClient.delegate = self
        signalClient.delegate = self
        signalClient.connect()
    }
    
    func loadARView() {
        arView.scene.addAnchor(anchor)
        var terrains: [Entity] = []
        robotTemplate.setScale(SIMD3<Float>(0.005, 0.005, 0.005), relativeTo: nil)
        terrainTemplate.generateCollisionShapes(recursive: true)
        for _ in 1...16 {
            terrains.append(terrainTemplate.clone(recursive: true))
        }
        for (index, terrain) in terrains.enumerated() {
            let x = Float(index % 4) - 1.5
            let z = Float(index / 4) - 1.5
            terrain.position = [x * 0.1 , 0, z * 0.1]
            anchor.addChild(terrain)
        }
    }
    
    @IBAction func onTap(_ sender: UITapGestureRecognizer) {
        
        let tapLocation = sender.location(in: arView)
        if let terrain = arView.entity(at: tapLocation) {
            let position: SIMD3<Float> = [terrain.position.x, terrain.position.y, terrain.position.z]
            insertTower(at: position)
            insertTowerOnPeer(at: position)
        } else {
            arView.scene.addAnchor(anchor.clone(recursive: true))
        }
    }
    
    func insertTowerOnPeer(at position: SIMD3<Float>) {
        let array: [String: Float] = ["x": position.x, "y": position.y, "z": position.z]
        guard let data = try? JSONEncoder().encode(array) else { return }
        webRTCClient.sendData(data)
    }
    func insertAnchor() {
        
    }
    func insertTower(at position: SIMD3<Float>) {
        let robot = robotTemplate.clone(recursive: true)
        robot.position = position
        anchor.addChild(robot)
        
    }
    
    @IBAction func onConnect(_ sender: Any) {
        
        self.webRTCClient.offer { (sdp) in
            self.signalClient.send(sdp: sdp)
        }
        
        self.webRTCClient.answer { (localSdp) in
            self.signalClient.send(sdp: localSdp)
        }
    }
    
    var signalingConnected: Bool = false {
        didSet {
            DispatchQueue.main.async {
                if self.signalingConnected {
                    self.signalingStatusLabel?.text = "Connected"
                    self.signalingStatusLabel?.textColor = UIColor.green
                }
                else {
                    self.signalingStatusLabel?.text = "Not connected"
                    self.signalingStatusLabel?.textColor = UIColor.red
                }
            }
        }
    }
    
    func presentCoachingOverlay() {
        coachingOverlay.session = arView.session
        coachingOverlay.delegate = self
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.activatesAutomatically = false
        self.coachingOverlay.setActive(true, animated: true)
    }
}


