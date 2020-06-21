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

typealias EmbeddedModel = (model: ModelEntity, entity: Entity)

class ViewController: UIViewController {
    let towerTemplate = try! Entity.load(named: "turret_gun")

    enum TowerType: CaseIterable {
        case turret, rocket, fighters
    }
    enum TowerStates: CaseIterable {
        case empty, phase1, phase2
    }
    
    typealias SpawnPlace = (entity: Entity, position: Position, map: Int)
    @IBOutlet var arView: ARView!
    
    @IBOutlet weak var coinsLabel: UILabel!
    @IBOutlet weak var lifePointsStack: UIStackView!
    @IBOutlet weak var collectionView: UICollectionView!
    
    var defensors = Defensor.getDefensors()
    
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
    var glyphModels = [(model: ModelEntity, canShow: Int?)]()
    var terrainAnchors = [AnchorEntity]()
    var creepIDs = [UInt64]()
    var selectedPlacing: Entity?
    var placings = [(EmbeddedModel,TowerStates)]()
    
    lazy var gameConfig: GameModel = {
        let filePath = Bundle.main.path(forResource: "config", ofType: "json")!
        let data = try! NSData(contentsOfFile: filePath) as Data
        return try! JSONDecoder().decode(GameModel.self, from: data)
    }()

    let pathTemplate = try! Entity.load(named: "creep_path")
    let pathDownwardsTemplate = try! Entity.load(named: "creep_path_downwards")
    let pathUpwardsTemplate = try! Entity.load(named: "creep_path_upwards")

    let placingTemplate = try! Entity.load(named: "tower_placing")
    let creepTemplate = try! Entity.load(named: "mech_drone")
    let lifeCreepTemplate = try! Entity.load(named: "lifebar")
    let runeTemplate = try! Entity.load(named: "placing_glyph")
    let portalTemplate = try! Entity.load(named: "map_icon")
    let spawnTemplate = try! Entity.load(named: "spawn_station")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        loadAnchorConfiguration()
        loadAnchorTemplates()
        loadActionStrip()
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
    
    func loadActionStrip() {
        let layout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.scrollDirection = .horizontal
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isHidden = true
        collectionView.collectionViewLayout = layout
        collectionView.showsHorizontalScrollIndicator = false
    }
    func loadAnchorConfiguration() {
        config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isCollaborationEnabled = true
        config.environmentTexturing = .automatic
//        arView.debugOptions = [.showPhysics]
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.run(config)
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap(_:))))
    }
    
    func loadAnchorTemplates() {
        ///Tower Placing
        placingTemplate.setScale(SIMD3(repeating: 0.025), relativeTo: nil)
        ///Runes
        runeTemplate.setScale(SIMD3(repeating: 0.0001), relativeTo: nil)
        ///Towers
        towerTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
        ///Creeps
        //0.00001
        creepTemplate.setScale(SIMD3(repeating: 0.000015), relativeTo: nil)
        //lifeBar
        lifeCreepTemplate.setScale(SIMD3(repeating: 0.000115), relativeTo: nil)
        ///Path
        pathTemplate.setScale(SIMD3(repeating: 0.000027), relativeTo: nil)
        pathUpwardsTemplate.setScale(SIMD3(repeating: 0.0125), relativeTo: nil)
        pathDownwardsTemplate.setScale(SIMD3(repeating: 0.0125), relativeTo: nil)
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
        glyphModels.forEach { glyph in glyph.model.removeFromParent() }
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
                var lifeCreepPosition = spawnPosition
                lifeCreepPosition.y = 0.13
                let lifeCreep = self.lifeCreepTemplate.modelEmbedded(at: lifeCreepPosition, debugInfo: true)
                spawnPosition.y = 0.03
                self.creepIDs.append(creep.model.id)
                spawn.entity.anchor?.addChild(creep.model)
                spawn.entity.anchor?.addChild(lifeCreep.model)
                creep.model.generateCollisionShapes(recursive: true)
//                let bounds = creep.entity.visualBounds(relativeTo: creep.model)
//                creep.model.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)]))
                creep.entity.playAnimation(creep.entity.availableAnimations[0].repeat())
                if lifeCreep.entity.availableAnimations.count > 0 {
                    lifeCreep.entity.playAnimation(lifeCreep.entity.availableAnimations[0].repeat())
                }
                let randomPathIndx = Int.random(in: 0..<paths.count)
                self.deployUnit(creep, on: paths[randomPathIndx], setScale: 0.00015)
                self.deployUnit(lifeCreep, on: paths[randomPathIndx], setScale: 0.00015)
            }
        }
    }
    
    func deployUnit(_ creep: EmbeddedModel, to index: Int = 0, on path: [OrientedCoordinate], baseHeight: Float? = nil, setScale: Float? = nil) {
        var transform = creep.entity.transform
        if index < path.count {
            let move = path[index]
            let height = baseHeight ?? transform.translation.y
            transform.translation = move.coordinate
            transform.translation.y += height
            transform.rotation = move.rotation
            if let scale = setScale { transform.scale = SIMD3(repeating: scale) }
            let animation = creep.entity.move(to: transform, relativeTo: creep.entity.anchor, duration: 1, timingFunction: .linear)
            ///arView.scene.subscribe(to:on:completion:)
            subscriptions.append(arView.scene.publisher(for: AnimationEvents.PlaybackCompleted.self)
                .filter { $0.playbackController == animation }
                .sink(receiveValue: { event in
                    self.deployUnit(creep, to: index + 1, on: path, baseHeight: height)
                }))
        } else if index == path.count {
            creep.model.removeFromParent()
            lifePointsStack.arrangedSubviews.last?.removeFromSuperview()
        }
    }
    @IBAction func onUndo(_ sender: Any) {
        if let lastMap = terrainAnchors.last {
            lastMap.removeFromParent()
            usedMaps -= 1
            for (index, glyph) in glyphModels.enumerated() {
                glyph.model.isEnabled = glyph.canShow ?? 0 == usedMaps
                glyphModels[index].canShow = nil
            }
        }
    }
    
    @objc func onTap(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: arView)
        guard let entity = arView.entity(at: tapLocation),
            let anchor = entity.anchor as? AnchorEntity else { return }
        
        if anchor.name == "TerrainAnchorEntity" {
            collectionView.isHidden = false
            selectedPlacing = entity
        } else {
            for (index, glyph) in glyphModels.enumerated() {
                if entity.id == glyph.model.id {
                    entity.isEnabled = false
                    glyphModels[index].canShow = usedMaps
                }
            }
            arView.session.add(anchor: ARAnchor(name: "Terrain", transform: entity.transformMatrix(relativeTo: nil)))
        }
    }
    
    func insertMap(anchor: AnchorEntity, map: MapModel) {
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
                case .zipLineIn, .zipLineOut, .neutral:
                    break
                case .goal:
                    let portal = portalTemplate.modelEmbedded(at: [x, 0.05, z])
                    portal.entity.transform.rotation = simd_quatf(angle: .pi/2, axis: [0, 1, 0])
                    anchor.addChild(portal.model)
                    portal.entity.playAnimation(portal.entity.availableAnimations.first!.repeat())
                case .lowerPath:
                    var floor: (model: ModelEntity, entity: Entity) {
                        for direction in Direction.allCases {
                            let (nextRow, nextColumn) = (row + direction.offset.row, column + direction.offset.column)
                            if nextRow >= 0 && nextRow < rows,
                                nextColumn >= 0 && nextColumn < columns {
                                if  MapLegend.allCases[map.matrix[nextRow][nextColumn]] == .higherPath {
                                    let floor = pathUpwardsTemplate.modelEmbedded(at: [x, 0.001, z])
                                    floor.entity.transform.rotation = simd_quatf(angle: direction.baseRotation, axis: [0, 1, 0])
                                    return floor
                                }
                            }
                        }
                        return pathTemplate.modelEmbedded(at: [x, 0.001, z])
                    }
                    anchor.addChild(floor.model)
                case .higherPath:
                    var floor: (model: ModelEntity, entity: Entity) {
                        for direction in Direction.allCases {
                            let (nextRow, nextColumn) = (row + direction.offset.row, column + direction.offset.column)
                            if nextRow >= 0 && nextRow < rows,
                                nextColumn >= 0 && nextColumn < columns {
                                if  MapLegend.allCases[map.matrix[nextRow][nextColumn]] == .lowerPath {
                                    let floor = pathDownwardsTemplate.modelEmbedded(at: [x, 0.101, z])
                                    floor.entity.transform.rotation = simd_quatf(angle: direction.baseRotation + .pi, axis: [0, 1, 0])
                                    return floor
                                }
                            }
                        }
                        return pathTemplate.modelEmbedded(at: [x, 0.101, z])
                    }
                    anchor.addChild(floor.model)
                case .lowerTower:
                    let towerPlacing = placingTemplate.modelEmbedded(at: [x, 0.003, z], debugInfo: true)
                    towerPlacing.model.generateCollisionShapes(recursive: true)
                    placings.append((towerPlacing, .empty))
                    anchor.addChild(towerPlacing.model)
                case .higherTower:
                    let towerPlacing = placingTemplate.modelEmbedded(at: [x, 0.103, z], debugInfo: true)
                    towerPlacing.model.generateCollisionShapes(recursive: true)
                    placings.append((towerPlacing, .empty))
                    anchor.addChild(towerPlacing.model)
                case .spawn:
                    let station = spawnTemplate.modelEmbedded(at: [x, 0.001, z])
                    spawnPlaces.append((station.entity, (row, column), usedMaps))
                    anchor.addChild(station.model)
                }
            }
        }
    }

    func insertTower(template: Entity, range: Float, cost: Int) {
        guard let referenceEntity = selectedPlacing,
            let anchor = referenceEntity.anchor as? AnchorEntity,
            cost <= coins else { return }
        coins -= cost
        let position = referenceEntity.transformMatrix(relativeTo: anchor).toTranslation()
        let model = ModelEntity()
        let tower = template.clone(recursive: true)
        model.addChild(tower)
        tower.position = SIMD3(x: position.x, y: position.y + 0.003, z: position.z)
        anchor.addChild(model)
        ///Tower range
        let box = MeshResource.generatePlane(width: range, depth: range, cornerRadius: range/2)
        let material = SimpleMaterial(color: UIColor.red.withAlphaComponent(0.2), isMetallic: true)
        let rangeModel = ModelEntity(mesh: box, materials: [material])
        anchor.addChild(rangeModel)
        rangeModel.generateCollisionShapes(recursive: true)
        rangeModel.position = tower.position
        rangeModel.position.y += 0.05
        ///Tower collision
//        let bounds = rangeEntity.visualBounds(relativeTo: model)
//        tower.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)]))
//        tower.playAnimation(tower.availableAnimations[0].repeat())
        subscriptions.append(arView.scene.subscribe(to: CollisionEvents.Began.self, on: rangeModel) {
            event in
//            let range = event.entityA
//            let object = event.entityB
                tower.playAnimation(tower.availableAnimations[0].repeat())
        })
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
                terrainAnchors.append(terrainAnchor)
                let maps = gameConfig.levels[level].maps
                if usedMaps < maps.count {
                    insertMap(anchor: terrainAnchor, map: maps[usedMaps])
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
                glyphModels.append((model,nil))
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
extension ViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        switch TowerType.allCases[indexPath.row] {
        case .turret: insertTower(template: towerTemplate, range: 0.25, cost: 50)
        case .rocket: insertTower(template: portalTemplate, range: 0.3, cost: 100)
        case .fighters: insertTower(template: creepTemplate, range: 0.1, cost: 150)
        }
        selectedPlacing = nil
        collectionView.isHidden = true
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.frame.size.height, height: collectionView.frame.size.height)
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return defensors.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "DefensorCollectionViewCell", for: indexPath) as! DefensorCollectionViewCell
        let defensor = defensors[indexPath.item]
        
        cell.defensor = defensor
        
        return cell
    }
}
