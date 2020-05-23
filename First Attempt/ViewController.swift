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
import Combine

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
    var planeEntities = [UUID: PlaneEntiy]()
    var terrainEntities = [Entity]()
    
    var coins = 150
    var level = 0
    var subscriptions: [Cancellable] = []
    
    var gameConfig: GameModel?
    var usedMaps = [MapModel]()
    
    let terrainTemplate = try! Entity.load(named: "tower_placing")
    let creepTemplate = try! Entity.load(named: "mech_drone")
    let towerTemplate = try! Entity.load(named: "turret_gun")
    let runeTemplate = try! Entity.load(named: "placing_glyph")
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        loadAnchorTemplates()
        configureMultipeer()
        
        coinsLabel.text = "\(coins)"
        _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.coins += 5
            self.coinsLabel.text = "\(self.coins)"
        }
        if let filePath = Bundle.main.path(forResource: "config", ofType: "json"),
           let data = try? NSData(contentsOfFile: filePath) as Data {
            gameConfig = try? JSONDecoder().decode(GameModel.self, from: data)
            
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)
        loadAnchorConfiguration()
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
        //Terrains
        let terrainFactor: Float = 0.0001
        terrainTemplate.setScale(SIMD3(repeating: terrainFactor), relativeTo: nil)
        terrainTemplate.generateCollisionShapes(recursive: true)
        ///Runess
        let runeFactor: Float = 0.0001
        runeTemplate.setScale(SIMD3(repeating: runeFactor), relativeTo: nil)
        runeTemplate.generateCollisionShapes(recursive: true)
        ///Towers
        let towerFactor: Float = 0.0003
        towerTemplate.setScale(SIMD3(repeating: towerFactor), relativeTo: nil)
        towerTemplate.generateCollisionShapes(recursive: true)
        ///Creeps
        let creepFactor: Float = 0.0001
        creepTemplate.setScale(SIMD3(repeating: creepFactor), relativeTo: nil)
        creepTemplate.generateCollisionShapes(recursive: true)
        
    }
    
    func configureMultipeer() {
        sessionIDObservation = observe(\.arView.session.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            guard let multipeerSession = self.multipeerSession else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        setupCoachingOverlay()
        
        multipeerSession = MultipeerSession(receivedDataHandler: receivedData, peerJoinedHandler:
            peerJoined, peerLeftHandler: peerLeft, peerDiscoveredHandler: peerDiscovered)
    }
    
    @IBAction func onStart(_ sender: Any) {

        creepEntities.forEach { creep in
            var transform = creep.transform
            transform.translation = SIMD3<Float>(x: 0.15, y: transform.translation.y, z: 0.25)
            creep.move(to: transform, relativeTo: creep.anchor, duration: 5)
        }

    }
    
    @objc func onTap(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: arView)
        guard let entity = arView.entity(at: tapLocation),
            let anchor = entity.anchor as? AnchorEntity else { return }
        
        if anchor.name == "TerrainAnchorEntity" {
            insertTower(on: entity, anchor: anchor)
        } else {
            arView.session.add(anchor: ARAnchor(name: "Terrain", transform: entity.transformMatrix(relativeTo: nil)))
        }
    }
    
    func insertTerrain(anchor: AnchorEntity, map: MapModel) {
        let rows = map.matrix.count
        let columns = map.matrix.first!.count
        for row in 0...rows {
            for column in 0...columns {
                let rowDistance = Float(rows / 2) - 0.5
                let columnDistance = Float(columns / 2) - 0.5
                let x = Float(row % rows) - rowDistance
                let z = Float(column / columns) - columnDistance
                let mapCode = map.matrix[row][column]
                let mapType = MapLegend.allCases[mapCode]
                switch mapType {
                case .neutral, .zipLineIn, .zipLineOut, .creepPath, .highCreepPath:
                    break
                case .goal:
                    break
                case .tower:
                    let model = ModelEntity()
                    let terrain = terrainTemplate.clone(recursive: true)
                    model.addChild(terrain)
                    terrain.position = [x * 0.1 , 0.02, z * 0.1]
                    terrain.generateCollisionShapes(recursive: true)
                    anchor.addChild(model)
                    terrainEntities.append(terrain)
                    insertDebugInfo(on: terrain)
                case .spawn:
                    let model = ModelEntity()
                    let creep = creepTemplate.clone(recursive: true)
                    model.addChild(creep)
                    creep.position = [x * 0.1 , 0.03, z * 0.1]
                    creep.generateCollisionShapes(recursive: true)
                    anchor.addChild(model)
                    insertDebugInfo(on: creep)
                    creepEntities.append(creep)
                    creep.playAnimation(creep.availableAnimations[0].repeat())
                }
            }
        }
        usedMaps.append(map)
    }
    
    func insertTower(on referenceEntity: Entity, anchor: AnchorEntity) {
        let model = ModelEntity()
        let tower = towerTemplate.clone(recursive: true)
        model.addChild(tower)
        anchor.addChild(model)
        let position = referenceEntity.transformMatrix(relativeTo: anchor).toTranslation()
        tower.position = SIMD3(x: position.x, y: position.y + 0.003, z: position.z)
        towerEntities.append(tower)
        
        let bounds = tower.visualBounds(relativeTo: model)
        tower.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)]))
        tower.playAnimation(tower.availableAnimations[0].repeat())

        let subscription = arView.scene.subscribe(to: CollisionEvents.Began.self, on: tower) {
            event in
            let tower = event.entityA
            let object = event.entityB
            if self.creepEntities.contains(object) {
                tower.playAnimation(tower.availableAnimations[0].repeat())
            }
        }
        subscriptions.append(subscription)
    }
    func insertDebugInfo(on parentEntity: Entity) {
        let model = parentEntity.parent
        let (x, y, z) = (parentEntity.position.x, parentEntity.position.y, parentEntity.position.z)
        let mesh = MeshResource.generateText(
            "(X:\(String(format:"%.2f", x)), Y:\(String(format:"%.2f", y)), Z:\(String(format:"%.2f", z)))",
            extrusionDepth: 0.1,
            font: .systemFont(ofSize: 2),
            containerFrame: .zero,
            alignment: .left,
            lineBreakMode: .byTruncatingTail)
        let entity = Entity()
        entity.components[ModelComponent] = ModelComponent.init(mesh: mesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
        model?.addChild(entity)
        entity.scale = SIMD3(repeating: 0.01)
        entity.setPosition(SIMD3(x: x - entity.visualBounds(relativeTo: model).extents.x / 2, y: y + 0.05, z: z), relativeTo: model)
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
                if let maps = gameConfig?.levels[0].maps, maps.count >= 1 {
                    insertTerrain(anchor: terrainAnchor, map: gameConfig!.levels[level].maps.removeFirst())
                }
                
            } else {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                let model = ModelEntity()
                let glyph = runeTemplate.clone(recursive: true)
                model.addChild(glyph)
                
                let anchorEntity = AnchorEntity(anchor: planeAnchor)
                anchorEntity.addChild(model)
                arView.scene.addAnchor(anchorEntity)
                glyph.playAnimation(glyph.availableAnimations[0].repeat())
                let entityBounds = glyph.visualBounds(relativeTo: model)
                model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: entityBounds.extents).offsetBy(translation: entityBounds.center)])
                arView.installGestures([.rotation, .translation] ,for: model)
                insertDebugInfo(on: glyph)
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
