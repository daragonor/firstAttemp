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
import MultipeerConnectivity

struct PlaneEntiy {
    var entity: ModelEntity
    var hasContent: Bool = false
    var anchor: ARAnchor
}

class ViewController: UIViewController {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var coinsLabel: UILabel!
    
    var config: ARWorldTrackingConfiguration!
    
    var multipeerSession: MultipeerSession?
    
    let coachingOverlay = ARCoachingOverlayView()
    
    var peerSessionIDs = [MCPeerID: String]()
    
    var sessionIDObservation: NSKeyValueObservation?
    
    var towerEntities = [Entity]()
    var creepEntities = [Entity]()
    /// Terrain disposable anchors
    var planeEntities = [UUID: PlaneEntiy]()
    var terrainEntities = [Entity]()
    
    
    
    let terrainTemplate = try! Entity.load(named: "stone_floor")
    let creepTemplate = try! Entity.load(named: "mech_drone")
    let towerTemplate = try! Entity.load(named: "turret_gun")
    let runeTemplate = try! Entity.load(named: "placing_glyph")
    override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        loadAnchorTemplates()
        loadAnchorConfiguration()
        configureMultipeer()
        coinsLabel.text = "\(150)"
    }
    
    func loadAnchorConfiguration() {
        config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isCollaborationEnabled = true
        config.environmentTexturing = .automatic
        
        arView.automaticallyConfigureSession = false
        arView.debugOptions = [.showFeaturePoints]
        arView.session.delegate = self
        arView.session.run(config)
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap(_:))))
    }
    
    func loadAnchorTemplates() {
        //for robots 0.005
        let terrainFactor: Float = 1
        terrainTemplate.setScale(SIMD3(repeating: terrainFactor), relativeTo: nil)
        terrainTemplate.generateCollisionShapes(recursive: true)
        let runeFactor: Float = 0.0001
        runeTemplate.setScale(SIMD3(repeating: runeFactor), relativeTo: nil)
        runeTemplate.generateCollisionShapes(recursive: true)
        let towerFactor: Float = 0.001
        towerTemplate.setScale(SIMD3(repeating: towerFactor), relativeTo: nil)
        towerTemplate.generateCollisionShapes(recursive: true)
        let creepFactor: Float = 0.0005
        creepTemplate.setScale(SIMD3(repeating: creepFactor), relativeTo: nil)
        creepTemplate.generateCollisionShapes(recursive: true)
        
    }
    
    func configureMultipeer() {
        sessionIDObservation = observe(\.arView.session.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            // Tell all other peers about your ARSession's changed ID, so
            // that they can keep track of which ARAnchors are yours.
            guard let multipeerSession = self.multipeerSession else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        setupCoachingOverlay()
        
        multipeerSession = MultipeerSession(receivedDataHandler: receivedData, peerJoinedHandler:
            peerJoined, peerLeftHandler: peerLeft, peerDiscoveredHandler: peerDiscovered)
    }
    
    @IBAction func onStart(_ sender: Any) {
        creepEntities[0].move(to: terrainEntities[30].transform, relativeTo: terrainEntities[30].anchor, duration: 5)
        creepEntities[1].move(to: creepEntities[0].transformMatrix(relativeTo: nil), relativeTo: nil, duration: 5)
        //        robotEntities[0].move(to: robotEntities.last!.transformMatrix(relativeTo: nil), relativeTo: nil, duration: 3)
        //        robotEntities[1].move(to: robotEntities[0].transformMatrix(relativeTo: nil), relativeTo: nil, duration: 8)
    }
    
    @objc func onTap(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: arView)
        guard let entity = arView.entity(at: tapLocation),
            let anchor = entity.anchor as? AnchorEntity else { return }
        
        if anchor.name == "TerrainAnchorEntity" {
            let position = SIMD3<Float>(entity.position.x, entity.position.y + 0.02, entity.position.z)
            ///▿ SIMD3<Float>(0.019324303, 0.02, 0.0)
            insertTower(at: position, anchor: anchor)
        } else {
            arView.session.add(anchor: ARAnchor(name: "Terrain", transform: entity.transformMatrix(relativeTo: nil)))
        }
        
    }
    func insertTerrain(anchor: AnchorEntity) {
        for i in 0..<36 {
            let terrain = terrainTemplate.clone(recursive: true)
            let x = Float(i % 6) - 2.5
            let z = Float(i / 6) - 2.5
            terrain.position = [x * 0.1 , 0.02, z * 0.1]
            terrain.generateCollisionShapes(recursive: true)
            anchor.addChild(terrain)
            terrainEntities.append(terrain)
            
            if i == 0 || i == 5 {
                let creep = creepTemplate.clone(recursive: true)
                creep.position = [x * 0.1 , 0.03, z * 0.1]
                anchor.addChild(creep)
                creepEntities.append(creep)
                creep.playAnimation(creep.availableAnimations[0].repeat())
                //                let _ = arView.scene.subscribe(to: CollisionEvents.Began.self, on: creep) {
                //                    event in
                //                    let creep = event.entityA
                //                    let tower = event.entityB
                //                    creep.move(to: tower.transformMatrix(relativeTo: nil), relativeTo: nil, duration: 1)
                //                }
            }
        }
    }
    func insertTower(at position: SIMD3<Float>, anchor: AnchorEntity) {
        let tower = towerTemplate.clone(recursive: true)
        anchor.addChild(tower)
        tower.position = position
        towerEntities.append(tower)
        tower.playAnimation(tower.availableAnimations[0].repeat())
    }
    
}


extension ViewController: ARSessionDelegate {
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            
            if let _ = anchor as? ARParticipantAnchor {
                
            } else if anchor.name == "Terrain" {
                let terrainAnchor = AnchorEntity(anchor: anchor)
                terrainAnchor.name = "TerrainAnchorEntity"
                arView.scene.addAnchor(terrainAnchor)
                insertTerrain(anchor: terrainAnchor)
                
            } else {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                let model = ModelEntity()
                let entity = runeTemplate.clone(recursive: true)
                model.addChild(entity)
                
                let anchorEntity = AnchorEntity(anchor: planeAnchor)
                anchorEntity.addChild(model)
                arView.scene.addAnchor(anchorEntity)
                entity.playAnimation(entity.availableAnimations[0])
                let entityBounds = entity.visualBounds(relativeTo: model)
                model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: entityBounds.extents).offsetBy(translation: entityBounds.center)])
                
                arView.installGestures([.rotation, .translation] ,for: model)
            }
        }
    }
    class GlyphEntity: Entity, HasModel, HasAnchoring, HasCollision {
        
        required init(color: UIColor) {
            super.init()
            self.components[ModelComponent] = ModelComponent(
                mesh: .generateBox(size: 0.1),
                materials: [SimpleMaterial(
                    color: color,
                    isMetallic: false)
                ]
            )
        }
        
        convenience init(color: UIColor, position: SIMD3<Float>) {
            self.init(color: color)
            self.position = position
        }
        
        required init() {
            fatalError("init() has not been implemented")
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            //            guard let planeAnchor = anchor as? ARPlaneAnchor,
            //                var planeEntity = planeEntities[planeAnchor.identifier]?.entity else { continue }
            if anchor.name == "Terrain" {
                
            }
            
            //            let orientation = planeAnchor.transform.toQuaternion()
            //            let rotatedCenter = orientation.act(planeAnchor.center)
            //            let mesh = MeshResource.generatePlane(width: 0.5    , depth: 0.5, cornerRadius: 0.05)
            //            planeEntity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: anchor.sessionIdentifier!.toRandomColor(), isMetallic: true)])
            ////            planeEntity.transform.translation = rotatedCenter
            ////            planeEntity.transform.rotation = orientation
            ////
            ////            switch planeAnchor.alignment {
            ////            case .horizontal:
            ////                planeEntity.model?.mesh = MeshResource.generatePlane( width: planeAnchor.extent.x, depth: planeAnchor.extent.z)
            ////            case .vertical:
            ////                planeEntity.model?.mesh = MeshResource.generatePlane( width: planeAnchor.extent.x, depth: 1)
            ////            @unknown default: return
            ////            }
            ////
            ////            planeEntity.model?.materials = [SimpleMaterial(color: anchor.sessionIdentifier!.toRandomColor(),isMetallic: true)]
            //            planeEntity.generateCollisionShapes(recursive: true)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present the error that occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
}
