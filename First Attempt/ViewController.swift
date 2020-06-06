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


class ViewController: UIViewController {
    
    typealias SpawnPlace = (entity: Entity, position: Position, map: Int)

    @IBOutlet var arView: ARView!
    
    @IBOutlet weak var coinsLabel: UILabel!
    @IBOutlet weak var lifePointsStack: UIStackView!
    
    var config: ARWorldTrackingConfiguration!
    
    var multipeerSession: MultipeerSession?
    let coachingOverlay = ARCoachingOverlayView()
    var peerSessionIDs = [MCPeerID: String]()
    var sessionIDObservation: NSKeyValueObservation?
    
    let gridDiameter: Float = 0.5
    var coins = 150
    var level = 0
    var subscriptions: [Cancellable] = []
    var usedMaps = 0
    var coinsTimer: Timer?
    var canStart: Bool {
        return usedMaps == gameConfig.levels[level].maps.count
    }
    var spawnPlaces = [SpawnPlace]()
    var glyphModels = [ModelEntity]()
    
    lazy var gameConfig: GameModel = {
        let filePath = Bundle.main.path(forResource: "config", ofType: "json")!
        let data = try! NSData(contentsOfFile: filePath) as Data
        return try! JSONDecoder().decode(GameModel.self, from: data)
    }()

    let pathTemplate = try! Entity.load(named: "floor_asset")
    let placingTemplate = try! Entity.load(named: "tower_placing")
    let creepTemplate = try! Entity.load(named: "mech_drone")
    let towerTemplate = try! Entity.load(named: "turret_gun")
    let runeTemplate = try! Entity.load(named: "placing_glyph")
    let portalTemplate = try! Entity.load(named: "map_icon")
    let spawnTemplate = try! Entity.load(named: "spawn_station")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        loadAnchorConfiguration()
        loadAnchorTemplates()
        configureMultipeer()

        coinsLabel.text = "\(coins)"
        coinsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.coins += 5
            self.coinsLabel.text = "\(self.coins)"
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
        placingTemplate.setScale(SIMD3(repeating: 0.0001), relativeTo: nil)
        ///Runess
        runeTemplate.setScale(SIMD3(repeating: 0.0001), relativeTo: nil)
        ///Towers
        towerTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
        ///Creeps
        creepTemplate.setScale(SIMD3(repeating: 0.00001), relativeTo: nil)
        ///Floor
        pathTemplate.setScale(SIMD3(repeating: 0.00035), relativeTo: nil)
        ///Goal
        portalTemplate.setScale(SIMD3(repeating: 0.0005), relativeTo: nil)
        ///Spawn
        spawnTemplate.setScale(SIMD3(repeating: 0.00007), relativeTo: nil)
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
        guard canStart else { return }
        glyphModels.forEach { model in model.removeFromParent() }
        for spawn in spawnPlaces {
            let map = gameConfig.levels[level].maps[spawn.map]
            let paths = map.creepPathsCoordinates(at: spawn.position,diameter: gridDiameter, aditionalRotationOffset: .pi)
            var counter = 0
            var spawnPosition =  spawn.entity.transform.translation
            _ = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
                guard counter < 5 else { timer.invalidate() ; return }
                counter += 1
                spawnPosition.y = 0.03
                let creep = self.creepTemplate.modelEmbedded(at: spawnPosition, debugInfo: true)
                spawn.entity.anchor?.addChild(creep.model)
                creep.entity.playAnimation(creep.entity.availableAnimations[0].repeat())
                self.deployUnit(creep.entity, on: paths[Int.random(in: 0..<paths.count)], setScale: 0.0001)
            }
        }
    }
    
    func deployUnit(_ entity: Entity, to index: Int = 0, on path: [OrientedCoordinate], baseHeight: Float? = nil, setScale: Float? = nil) {
        var transform = entity.transform
        if index < path.count {
            let move = path[index]
            let height = baseHeight ?? transform.translation.y
            transform.translation = SIMD3<Float>(x: move.coordinate.x, y: height + move.coordinate.y, z: move.coordinate.z)
            transform.rotation = move.rotation
            if let scale = setScale { transform.scale = SIMD3(repeating: scale) }
            let animation = entity.move(to: transform, relativeTo: entity.anchor, duration: 1, timingFunction: .linear)
            let subscription = arView.scene.publisher(for: AnimationEvents.PlaybackCompleted.self)
            .filter { $0.playbackController == animation }
            .sink(receiveValue: { event in
                self.deployUnit(entity, to: index + 1, on: path, baseHeight: height)
            })
            subscriptions.append(subscription)
        } else if index == path.count {
            entity.parent?.removeFromParent()
            lifePointsStack.arrangedSubviews.last?.removeFromSuperview()
        }
    }
    @IBAction func onUndo(_ sender: Any) {
        //deleteTowersfromArray
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
        for row in 0..<rows {
            for column in 0..<columns {
                let rowDistance = Float(rows / 2) - gridDiameter
                let columnDistance = Float(columns / 2) - gridDiameter
                let x = (Float(row) - rowDistance ) * 0.1
                let z = (Float(column) - columnDistance) * 0.1
                let mapCode = map.matrix[row][column]
                let mapType = MapLegend.allCases[mapCode]
                switch mapType {
                case .neutral, .zipLineIn, .zipLineOut:
                    break
                case .goal:
                    let portal = portalTemplate.modelEmbedded(at: [x, 0.0, z])
                    portal.entity.transform.rotation = simd_quatf(angle: .pi/2, axis: [0, 1, 0])
                    anchor.addChild(portal.model)
                    portal.entity.playAnimation(portal.entity.availableAnimations.first!.repeat())
                case .lowerPath:
                    let floor = pathTemplate.modelEmbedded(at: [x, 0.001, z])
                    anchor.addChild(floor.model)
                case .higherPath:
                    let floor = pathTemplate.modelEmbedded(at: [x, 0.101, z])
                    anchor.addChild(floor.model)
                case .lowerTower:
                    let towerPlacing = placingTemplate.modelEmbedded(at: [x, 0.0, z], debugInfo: true)
                    anchor.addChild(towerPlacing.model)
                case .higherTower:
                    let towerPlacing = placingTemplate.modelEmbedded(at: [x, 0.1, z], debugInfo: true)
                    anchor.addChild(towerPlacing.model)
                case .spawn:
                    let station = spawnTemplate.modelEmbedded(at: [x, 0.0, z])
                    spawnPlaces.append((station.entity, (row, column), usedMaps))
                    anchor.addChild(station.model)
                }
            }
        }
    }

    func insertTower(on referenceEntity: Entity, anchor: AnchorEntity) {
        let position = referenceEntity.transformMatrix(relativeTo: anchor).toTranslation()

        let model = ModelEntity()
        let tower = towerTemplate.clone(recursive: true)
        model.addChild(tower)
        tower.position = SIMD3(x: position.x, y: position.y + 0.003, z: position.z)
        anchor.addChild(model)
        
//        let bounds = tower.visualBounds(relativeTo: model)
//        tower.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)]))
        tower.playAnimation(tower.availableAnimations[0].repeat())

//        let subscription = arView.scene.subscribe(to: CollisionEvents.Began.self, on: tower) {
//            event in
//            let tower = event.entityA
//            let object = event.entityB
//
//        }
//        subscriptions.append(subscription)
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
                let maps = gameConfig.levels[level].maps
                if usedMaps < maps.count {
                    insertTerrain(anchor: terrainAnchor, map: maps[usedMaps])
                    usedMaps += 1
                }
                
            } else {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                let model = ModelEntity()
                let glyph = runeTemplate.clone(recursive: true)
                model.addChild(glyph)
                let anchorEntity = AnchorEntity(anchor: planeAnchor)
                anchorEntity.addChild(model)
                arView.scene.addAnchor(anchorEntity)
                glyphModels.append(model)
                glyph.playAnimation(glyph.availableAnimations[0].repeat())
                let entityBounds = glyph.visualBounds(relativeTo: model)
                model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: entityBounds.extents).offsetBy(translation: entityBounds.center)])
                arView.installGestures([.rotation, .translation] ,for: model)
            }
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
