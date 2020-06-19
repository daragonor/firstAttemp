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
    enum StripOptions {
        case upgrade, sell, turret, rocketlauncher, barracks, moveRight, moveLeft, rotateRight, rotateLeft
        var iconImage: UIImage {
            switch self {
            case .upgrade: return #imageLiteral(resourceName: "upgrade")
            case .sell: return #imageLiteral(resourceName: "coins")
            case .turret: return #imageLiteral(resourceName: "turret")
            case .rocketlauncher: return #imageLiteral(resourceName: "missile-swarm")
            case .barracks: return #imageLiteral(resourceName: "cryo-chamber")
            case .moveRight: return #imageLiteral(resourceName: "plain-arrow-roght")
            case .moveLeft: return #imageLiteral(resourceName: "plain-arrow-left")
            case .rotateRight: return #imageLiteral(resourceName: "clockwise-rotation")
            case .rotateLeft: return #imageLiteral(resourceName: "anticlockwise-rotation")
            }
        }
    }
    enum ActionStrip {
        case placing, map, tower
        static func options(tower: TowerType) -> [StripOptions] {
            switch tower {
            case .turret, .rocketLauncher: return [.upgrade, .sell]
            case .barracks: return [.upgrade, .sell, .moveLeft, .moveRight]
            }
        }
        var options: [StripOptions] {
            switch self {
            case .map: return[.rotateLeft, .rotateRight]
            case .placing: return [.turret, .rocketlauncher, .barracks]
            default: return []
            }
        }
    }
    
    enum Filter {
        case placings, towers, creeps
        var group: CollisionGroup {
            switch self {
            case .placings: return CollisionGroup.init(rawValue: 0)
            case .towers: return CollisionGroup.init(rawValue: 1)
            case .creeps: return CollisionGroup.init(rawValue: 2)
            }
        }
    }
    
    @IBOutlet var arView: ARView!
    
    @IBOutlet weak var coinsLabel: UILabel!
    @IBOutlet weak var lifePointsStack: UIStackView!
//    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var tableView: UITableView!
    
    var config: ARWorldTrackingConfiguration!
    
    var multipeerSession: MultipeerSession?
    let coachingOverlay = ARCoachingOverlayView()
    var peerSessionIDs = [MCPeerID: String]()
    var sessionIDObservation: NSKeyValueObservation?
    
    let gridDiameter: Float = 0.5
    var coins = 600
    var level = 0
    var subscriptions: [Cancellable] = []
    var usedMaps = 0
    var coinsTimer: Timer?
    var canStart: Bool {
        return usedMaps == gameConfig.levels[level].maps.count
    }
    
    typealias SpawnBundle = (model: ModelEntity, position: Position, map: Int)
    typealias PlacingBundle = (model: ModelEntity, position: Position, type: TowerType?, accesory: Entity?)
    typealias TowerBundle = (model: ModelEntity, type: TowerType, enemiesIDs: [UInt64])
    typealias CreepBundle = (id: UInt64, type: CreepType, hp: Int)
    var spawnPlaces = [SpawnBundle]()
    var glyphModels = [(model: ModelEntity, canShow: Int?)]()
    var terrainAnchors = [AnchorEntity]()
    
    var creeps = [CreepBundle]()
    var placings = [PlacingBundle]()
    var towers = [TowerBundle]()
    var selectedPlacing: PlacingBundle?
    var actionStrip = [StripOptions]()
    
    lazy var gameConfig: GameModel = {
        let filePath = Bundle.main.path(forResource: "config", ofType: "json")!
        let data = try! NSData(contentsOfFile: filePath) as Data
        return try! JSONDecoder().decode(GameModel.self, from: data)
    }()
    
    let pathTemplate = try! Entity.load(named: "creep_path")
    let pathDownwardsTemplate = try! Entity.load(named: "creep_path_downwards")
    let pathUpwardsTemplate = try! Entity.load(named: "creep_path_upwards")
    let turretTemplate = try! Entity.load(named: "turret")
    let rocketLauncherTemplate = try! Entity.load(named: "rocket_launcher")
    let barracksTemplate = try! Entity.load(named: "barracks")

    let placingTemplate = try! Entity.load(named: "tower_placing")
    let creepTemplate = try! Entity.load(named: "mech_drone")
    let runeTemplate = try! Entity.load(named: "here")
    let portalTemplate = try! Entity.load(named: "gate")
    let spawnTemplate = try! Entity.load(named: "spawn_port")
    let bulletTemplate = try! Entity.load(named: "bullet")
    let neutralFloorTemplate = try! Entity.load(named: "neutral_floor_1x1")
    let neutralTankTemplate = try! Entity.load(named: "neutral_tank")
    let neutralBarrelTemplate = try! Entity.load(named: "neutral_barrel")
    let rangeTemplate = try! Entity.load(named: "hud")
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
        layout.scrollDirection = .vertical
        tableView.delegate = self
        tableView.dataSource = self
        tableView.transform = CGAffineTransform(rotationAngle: -(CGFloat)(Double.pi))
        tableView.showsVerticalScrollIndicator = false
    }
    func loadAnchorConfiguration() {
        config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isCollaborationEnabled = true
        config.environmentTexturing = .automatic
        arView.renderOptions.insert(.disableMotionBlur)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.run(config)
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap(_:))))
    }
    
    func loadAnchorTemplates() {
        ///Tower Placing
        placingTemplate.setScale(SIMD3(repeating: 0.025), relativeTo: nil)
        ///Runes
        runeTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
        ///Towers
        turretTemplate.setScale(SIMD3(repeating: 0.00017), relativeTo: nil)
        rocketLauncherTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
        barracksTemplate.setScale(SIMD3(repeating: 0.0001), relativeTo: nil)
        ///Creep
        creepTemplate.setScale(SIMD3(repeating: 0.00001), relativeTo: nil)
        ///Path
        pathTemplate.setScale(SIMD3(repeating: 0.000027), relativeTo: nil)
        pathUpwardsTemplate.setScale(SIMD3(repeating: 0.0125), relativeTo: nil)
        pathDownwardsTemplate.setScale(SIMD3(repeating: 0.125), relativeTo: nil)
        ///Neutral
        neutralFloorTemplate.setScale(SIMD3(repeating: 0.1), relativeTo: nil)
        neutralTankTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
        neutralBarrelTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
        ///Goal
        portalTemplate.setScale(SIMD3(repeating: 0.0006), relativeTo: nil)
        ///Spawn
        spawnTemplate.setScale(SIMD3(repeating: 0.0002), relativeTo: nil)
        ///Bullet
        bulletTemplate.setScale(SIMD3(repeating: 0.002), relativeTo: nil)
        ///Range
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
    
    func reloadActionStrip(with options: [StripOptions]) {
        if actionStrip != options {
            actionStrip = options
            tableView.reloadSections([0], with: .fade)
        }
    }
    
    @IBAction func onStart(_ sender: Any) {
        guard canStart else { return }
        glyphModels.forEach { glyph in glyph.model.removeFromParent() }
        for spawn in spawnPlaces {
            let map = gameConfig.levels[level].maps[spawn.map]
            let paths = map.creepPathsCoordinates(at: spawn.position,diameter: gridDiameter, aditionalRotationOffset: .pi)
            var counter = 0
            var spawnPosition =  spawn.model.transform.translation
            _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                guard counter < 3 else { timer.invalidate() ; return }
                counter += 1
                spawnPosition.y = 0.03
                let creep = self.creepTemplate.embeddedModel(at: spawnPosition)
                let creepType = CreepType.common
                self.creeps.append((creep.model.id, creepType, creepType.lifepoints))
                let bounds = creep.entity.visualBounds(relativeTo: creep.model)
                creep.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)], mode: .trigger, filter: CollisionFilter(group: Filter.creeps.group, mask: Filter.towers.group))
                spawn.model.anchor?.addChild(creep.model)
                creep.entity.playAnimation(creep.entity.availableAnimations[0].repeat())
                self.deployUnit(creep, on: paths[Int.random(in: 0..<paths.count)], setScale: 10)
            }
        }
    }
    
    func deployUnit(_ creep: EmbeddedModel, to index: Int = 0, on path: [OrientedCoordinate], baseHeight: Float? = nil, setScale: Float? = nil) {
        
        var unitTransform = creep.model.transform
        if index < path.count {
            let move = path[index]
            ///Set new move
            let height = baseHeight ?? unitTransform.translation.y
            unitTransform.translation = move.coordinate
            unitTransform.translation.y += height
            unitTransform.rotation = move.rotation
            if let scale = setScale { unitTransform.scale = SIMD3(repeating: scale) }
            ///Start moving
            let animation = creep.model.move(to: unitTransform, relativeTo: creep.model.anchor, duration: 2, timingFunction: .linear)
            //arView.scene.subscribe(to:on:completion:)
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
        let entities = arView.entities(at: tapLocation)
        guard let entity = entities.first else { return }
        
        if let placing = placings.first(where: { model, _, _, _ in entities.contains(where: {$0.id == model.id}) }) {
            var options = ActionStrip.placing.options == actionStrip ? [] : ActionStrip.placing.options
            selectedPlacing = placing
            placings.forEach { model, _, type, accesory in
                if let accesory = accesory, model.id == placing.model.id, let type = type {
                    accesory.isEnabled.toggle()
                    options = accesory.isEnabled ? ActionStrip.options(tower: type) : []
                    selectedPlacing = accesory.isEnabled ? selectedPlacing : nil
                } else { accesory?.isEnabled = false }
            }
            reloadActionStrip(with: options)
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
                let floor = neutralFloorTemplate.embeddedModel(at: [x, 0.005, z])
                anchor.addChild(floor.model)
                switch mapType {
                case .neutral:
                    let chance = Int.random(in: 1...10)
                    let rotation = Direction.baseMoves[Int.random(in: 0...3)].rotation()
                    switch chance {
                    case 7...8:
                        let floor = neutralTankTemplate.embeddedModel(at: [x, 0.003, z])
                        floor.model.transform.rotation = rotation
                        anchor.addChild(floor.model)
                    case 10:
                        let floor = neutralBarrelTemplate.embeddedModel(at: [x, 0.003, z])
                        floor.model.transform.rotation = rotation
                        anchor.addChild(floor.model)
                    default: break
                    }
                case .zipLineIn, .zipLineOut:
                    break
                case .goal:
                    let portal = portalTemplate.embeddedModel(at: [x, 0.03, z])
                    anchor.addChild(portal.model)
                    portal.model.orientation = Direction.right.rotation()
                    portal.entity.playAnimation(portal.entity.availableAnimations[0].repeat())
                    fallthrough
                case .lowerPath:
                    var floor: EmbeddedModel {
                        for direction in Direction.allCases {
                            let (nextRow, nextColumn) = (row + direction.offset.row, column + direction.offset.column)
                            if nextRow >= 0 && nextRow < rows,
                                nextColumn >= 0 && nextColumn < columns {
                                if  MapLegend.allCases[map.matrix[nextRow][nextColumn]] == .higherPath {
                                    let floor = pathUpwardsTemplate.embeddedModel(at: [x, 0.001, z])
                                    floor.entity.transform.rotation = simd_quatf(angle: direction.angle, axis: [0, 1, 0])
                                    return floor
                                }
                            }
                        }
                        return pathTemplate.embeddedModel(at: [x, 0.001, z])
                    }
                    anchor.addChild(floor.model)
                case .higherPath:
                    var floor: EmbeddedModel {
                        for direction in Direction.baseMoves {
                            let (nextRow, nextColumn) = (row + direction.offset.row, column + direction.offset.column)
                            if nextRow >= 0 && nextRow < rows,
                                nextColumn >= 0 && nextColumn < columns {
                                if  MapLegend.allCases[map.matrix[nextRow][nextColumn]] == .lowerPath {
                                    let floor = pathDownwardsTemplate.embeddedModel(at: [x, 0.1, z])
                                    floor.entity.transform.rotation = simd_quatf(angle: direction.angle + .pi, axis: [0, 1, 0])
                                    return floor
                                }
                            }
                        }
                        return pathTemplate.embeddedModel(at: [x, 0.1, z])
                    }
                    anchor.addChild(floor.model)
                case .lowerPlacing:
                    let placing = placingTemplate.embeddedModel(at: [x, 0.005, z])
                    let bounds = placing.entity.visualBounds(relativeTo: placing.model)
                    placing.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)])
                    anchor.addChild(placing.model)
                    placings.append((placing.model, (row,column), nil, nil))
                case .higherPlacing:
                    let placing = placingTemplate.embeddedModel(at: [x, 0.102, z])
                    let bounds = placing.entity.visualBounds(relativeTo: placing.model)
                    placing.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)])
                    anchor.addChild(placing.model)
                    placings.append((placing.model, (row,column), nil, nil))
                case .spawn:
                    let station = spawnTemplate.embeddedModel(at: [x, 0.001, z])
                    spawnPlaces.append((station.model, (row, column), usedMaps))
                    anchor.addChild(station.model)
                }
            }
        }
    }
    
    func insertTower(towerType: TowerType) {
        guard let selectedPlacing = selectedPlacing,
            let anchor = selectedPlacing.model.anchor as? AnchorEntity,
            towerType.cost <= coins else { return }
        coins -= towerType.cost
        let placingIndex = placings.enumerated().first( where: { index, placing in placing.model.id == selectedPlacing.model.id })!.0
        placings[placingIndex].type = towerType
        let tower: EmbeddedModel = {
             switch towerType{
            case .turret: return turretTemplate.embeddedModel(at: selectedPlacing.model.position)
            case .rocketLauncher: return rocketLauncherTemplate.embeddedModel(at: selectedPlacing.model.position)
            case .barracks: return barracksTemplate.embeddedModel(at: selectedPlacing.model.position)
            }
        }()
        tower.model.position.y += 0.003
        anchor.addChild(tower.model)
        var priorityList = [UInt64]()
        towers.append((tower.model, towerType, priorityList))
        reloadActionStrip(with: ActionStrip.options(tower: towerType))
        ///Tower range
        let diameter = 2.0 * gridDiameter * towerType.range * 0.1
        let range = rangeTemplate.clone(recursive: true)
        tower.model.addChild(range)
        let rangeBounds = range.visualBounds(relativeTo: anchor)
        let scaleDiameter = diameter / rangeBounds.extents.x * 0.01
        let scaleHeight = 0.03 / rangeBounds.extents.y * 0.01
        range.setScale([scaleDiameter, scaleHeight, scaleDiameter], relativeTo: nil)
        range.playAnimation(range.availableAnimations[0].repeat())
        range.position.y += 0.04
        if towerType == .barracks { range.position.z += diameter }
        placings[placingIndex].accesory = range
        ///Set range
        tower.model.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(width: diameter, height: 0.02, depth: diameter).offsetBy(translation: SIMD3<Float>(0, 0.02, 0))], mode: .trigger, filter: CollisionFilter.init(group: Filter.towers.group, mask: Filter.creeps.group)))
        
        subscriptions.append(arView.scene.subscribe(to: CollisionEvents.Ended.self, on: tower.model) {
            event in
            guard let creep = event.entityB as? ModelEntity else { return }
            switch towerType {
            case .turret:
                priorityList.removeAll(where: { id in id == creep.id })
            case .rocketLauncher: break
            case .barracks: break
            }
        })
        
        subscriptions.append(arView.scene.subscribe(to: CollisionEvents.Updated.self, on: tower.model) {
            event in
            guard let enemyID = priorityList.first, let creep = event.entityB as? ModelEntity, creep.id == enemyID else { return }
            switch towerType {
            case .turret:
                let angle = atan2(event.position.z - tower.model.position.z, event.position.x - tower.model.position.x)
                let orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
//                let orientation = simd_quatf(from: selectedPlacing.model.position, to: event.position)
                tower.model.setOrientation(orientation, relativeTo: nil)
            case .rocketLauncher: break
            case .barracks: break
            }
        })
        
        subscriptions.append(arView.scene.subscribe(to: CollisionEvents.Began.self, on: tower.model) {
            event in
            guard let creep = event.entityB as? ModelEntity else { return }
            switch towerType {
            case .turret:
                priorityList.append(creep.id)
                _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    guard priorityList.contains(creep.id) else { timer.invalidate() ; return }
                    guard let id = priorityList.first, id == creep.id else { return }
                    let bullet = self.bulletTemplate.embeddedModel(at: selectedPlacing.model.position)
                    bullet.model.transform.translation.y += 0.015
                    anchor.addChild(bullet.model)
                    var bulletTransform = bullet.model.transform
                    bulletTransform.translation = creep.transformMatrix(relativeTo: anchor).toTranslation()
                    let animation = bullet.model.move(to: bulletTransform, relativeTo: bullet.model.anchor, duration: 0.4, timingFunction: .easeOut)
                    self.subscriptions.append(self.arView.scene.publisher(for: AnimationEvents.PlaybackCompleted.self)
                        .filter { $0.playbackController == animation }
                        .sink(receiveValue: { event in
                            bullet.model.removeFromParent()
                            if let index = self.creeps.firstIndex(where: {$0.id == creep.id}) {
                                self.creeps[index].hp -= towerType.attack
                                //Add lifebar reduction here
                                if self.creeps[index].hp < 0 {
                                    priorityList.removeAll(where: { id in id == creep.id })
                                    creep.removeFromParent()
                                }
                            }
                        }))
                }
            case .rocketLauncher: break
            case .barracks: break
            }
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
extension ViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        insertTower(towerType: TowerType.allCases[indexPath.row])
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return actionStrip.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Action Strip Cell", for: indexPath)
        let imageView = cell.contentView.viewWithTag(10) as? UIImageView
        imageView?.image = actionStrip[indexPath.row].iconImage
        imageView?.layer.cornerRadius = 30.0
        imageView?.layer.masksToBounds = true
        cell.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
        return cell
    }
}
