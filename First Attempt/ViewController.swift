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
        case upgrade, sell, turret, launcher, barracks, moveRight, moveLeft, rotateRight, rotateLeft

        var iconImage: UIImage {
            switch self {
            case .upgrade: return #imageLiteral(resourceName: "upgrade")
            case .sell: return #imageLiteral(resourceName: "coins")
            case .turret: return #imageLiteral(resourceName: "turret")
            case .launcher: return #imageLiteral(resourceName: "missile-swarm")
            case .barracks: return #imageLiteral(resourceName: "cryo-chamber")
            case .moveRight: return #imageLiteral(resourceName: "plain-arrow-roght")
            case .moveLeft: return #imageLiteral(resourceName: "plain-arrow-left")
            case .rotateRight: return #imageLiteral(resourceName: "clockwise-rotation")
            case .rotateLeft: return #imageLiteral(resourceName: "anticlockwise-rotation")
            }
        }
    }
    enum ActionStrip {
        case none, placing, map, tower
        func options(for type: Any? = nil) -> ActionStripBundle {
            var options = [StripOptions]()
            switch self {
            case .map: options = [.rotateLeft, .rotateRight]
            case .placing: options = [.turret, .launcher, .barracks]
            case .tower:
                guard let tower = type as? TowerType else { options = []; break}
                switch tower {
                case .turret, .rocketLauncher: options = [.upgrade, .sell]
                case .barracks: options = [.upgrade, .sell, .moveLeft, .moveRight]
                }
            case .none: options = []
            }
            return (self, options)
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
    @IBOutlet weak var tableView: UITableView!
    
    var config: ARWorldTrackingConfiguration!
    
    var multipeerSession: MultipeerSession?
    let coachingOverlay = ARCoachingOverlayView()
    var peerSessionIDs = [MCPeerID: String]()
    var sessionIDObservation: NSKeyValueObservation?
    
    let gridDiameter: Float = 0.5
    var coins = 2000
    var level = 0
    var usedMaps = 0
    var coinsTimer: Timer?
    var canStart: Bool {
        return usedMaps == gameConfig.levels[level].maps.count
    }
    
    typealias SpawnBundle = (model: ModelEntity, position: Position, map: Int)
    typealias PlacingBundle = (model: ModelEntity, position: Position, towerId: UInt64?)
    typealias TowerBundle = (model: ModelEntity, type: TowerType, lvl: TowerLevel, accesory: Entity, enemiesIds: [UInt64], collisionSubs: [Cancellable])
    typealias UnitBundle = (hpBarId: UInt64, hp: Float, maxHP: Float, enemiesIds: [UInt64])
    typealias CreepBundle = (unit: UnitBundle, type: CreepType, animation: AnimationPlaybackController?, subscription: Cancellable?)
    typealias TroopBundle = (unit: UnitBundle, towerId: UInt64)
    typealias BulletBundle = (model: ModelEntity, animation: AnimationPlaybackController, subscription: Cancellable?)
    typealias ActionStripBundle = (action: ActionStrip, options: [StripOptions])
    var spawnPlaces = [SpawnBundle]()
    var glyphModels = [(model: ModelEntity, canShow: Int?)]()
    var creeps = [UInt64:CreepBundle]()
    var placings = [UInt64:PlacingBundle]()
    var towers = [UInt64:TowerBundle]()
    var troops = [UInt64:TroopBundle]()
    var bullets = [UInt64:BulletBundle]()
    var selectedPlacing: PlacingBundle?
    var strip: ActionStripBundle = (.none, [])
    var terrainAnchors = [AnchorEntity]()
    
    lazy var gameConfig: GameModel = {
        let filePath = Bundle.main.path(forResource: "config", ofType: "json")!
        let data = try! NSData(contentsOfFile: filePath) as Data
        return try! JSONDecoder().decode(GameModel.self, from: data)
    }()
    
    let pathTemplate = try! Entity.load(named: "creep_path")
    let pathDownwardsTemplate = try! Entity.load(named: "creep_path_downwards")
    let pathUpwardsTemplate = try! Entity.load(named: "creep_path_upwards")
    let turretLvl1Template = try! Entity.load(named: "turret_lvl1")
    let turretLvl2Template = try! Entity.load(named: "turret_lvl2")
    let rocketLauncherLvl1Template = try! Entity.load(named: "rocket_launcher_lvl1")
    let rocketLauncherLvl2Template = try! Entity.load(named: "rocket_launcher_lvl2")
    let barracksTemplate = try! Entity.load(named: "barracks")

    let placingTemplate = try! Entity.load(named: "tower_placing")
    let regularCreep = try! Entity.load(named: "regular_creep")
    let flyingCreep = try! Entity.load(named: "flying_creep")
    let runeTemplate = try! Entity.load(named: "here")
    let portalTemplate = try! Entity.load(named: "gate")
    let spawnTemplate = try! Entity.load(named: "spawn_port")
    let bulletTemplate = try! Entity.load(named: "bullet")
    let fullHPBarTemplate = ModelEntity(mesh: .generateBox(size: SIMD3(x: 0.003, y: 0.0005, z: 0.0005), cornerRadius: 0.0002), materials: [SimpleMaterial(color: .green, isMetallic: false)])
    let halfHPBarTemplate = ModelEntity(mesh: .generateBox(size: SIMD3(x: 0.003, y: 0.0005, z: 0.0005), cornerRadius: 0.0002), materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
    let lowHPBarTemplate = ModelEntity(mesh: .generateBox(size: SIMD3(x: 0.003, y: 0.0005, z: 0.0005), cornerRadius: 0.0002), materials: [SimpleMaterial(color: .red, isMetallic: false)])
//    let neutralFloorTemplate = try! Entity.load(named: "neutral_floor_1x1")
//    let neutralTankTemplate = try! Entity.load(named: "neutral_tank")
//    let neutralBarrelTemplate = try! Entity.load(named: "neutral_barrel")
//    let rangeTemplate = try! Entity.load(named: "circle_effect")
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
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
//        arView.debugOptions = [.showPhysics]
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
        turretLvl1Template.setScale(SIMD3(repeating: 0.0005), relativeTo: nil)
        turretLvl2Template.setScale(SIMD3(repeating: 0.00017), relativeTo: nil)
        rocketLauncherLvl1Template.setScale(SIMD3(repeating: 0.0002), relativeTo: nil)
        rocketLauncherLvl2Template.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
        barracksTemplate.setScale(SIMD3(repeating: 0.0002), relativeTo: nil)
        ///Creep
        regularCreep.setScale(SIMD3(repeating: 0.00001), relativeTo: nil)
        flyingCreep.setScale(SIMD3(repeating: 0.00001), relativeTo: nil)
        ///Path
        pathTemplate.setScale(SIMD3(repeating: 0.000027), relativeTo: nil)
        pathUpwardsTemplate.setScale(SIMD3(repeating: 0.0125), relativeTo: nil)
        pathDownwardsTemplate.setScale(SIMD3(repeating: 0.125), relativeTo: nil)
        ///Neutral
//        neutralFloorTemplate.setScale(SIMD3(repeating: 0.1), relativeTo: nil)
//        neutralTankTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
//        neutralBarrelTemplate.setScale(SIMD3(repeating: 0.0003), relativeTo: nil)
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
    
    func reloadActionStrip(with newStrip: ActionStripBundle) {
        strip = newStrip
        tableView.reloadSections([0], with: .fade)
    }
    
    @IBAction func onStart(_ sender: Any) {
        guard canStart else { return }
        glyphModels.forEach { glyph in glyph.model.removeFromParent() }
        for spawn in spawnPlaces {
            let map = gameConfig.levels[level].maps[spawn.map]
            let paths = map.creepPathsCoordinates(at: spawn.position,diameter: gridDiameter, aditionalRotationOffset: .pi)
            var counter = 0
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                guard counter < 1 else { timer.invalidate() ; return }
                counter += 1
                let creepType = CreepType.allCases[Int.random(in: 0..<CreepType.allCases.count)]
                let creep: EmbeddedModel = {
                    switch creepType {
                    case .regular: return self.regularCreep.embeddedModel(at: spawn.model.transform.translation)
                    case .flying: return self.flyingCreep.embeddedModel(at: spawn.model.transform.translation)
                    }
                }()
                creep.model.position.y += 0.03
                let bounds = creep.entity.visualBounds(relativeTo: creep.model)
                creep.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3(repeating: 0.0015)).offsetBy(translation: bounds.center)], mode: .trigger, filter: CollisionFilter(group: Filter.creeps.group, mask: Filter.towers.group))
                spawn.model.anchor?.addChild(creep.model)
                let creepHPbar = self.fullHPBarTemplate.clone(recursive: true)
                creep.model.addChild(creepHPbar)
                creepHPbar.position.y = (bounds.extents.y / 2) + 0.003
                self.creeps[creep.model.id] = ((creepHPbar.id, creepType.maxHP, creepType.maxHP, []), creepType, nil, nil)
                creep.entity.playAnimation(creep.entity.availableAnimations[0].repeat())
                self.deployUnit(creep.model, speed: creepType.speed, on: paths[Int.random(in: 0..<paths.count)], setScale: 10)
            }
            timer.fire()
        }
    }
    
    func deployUnit(_ creep: ModelEntity, speed: Float, to index: Int = 0, on path: [OrientedCoordinate], baseHeight: Float? = nil, setScale: Float? = nil) {
        
        var unitTransform = creep.transform
        if index < path.count {
            let move = path[index]
            ///Set new move
            let height = baseHeight ?? unitTransform.translation.y
            unitTransform.translation = move.coordinate
            unitTransform.translation.y += height
            unitTransform.rotation = move.rotation
            if let scale = setScale { unitTransform.scale = SIMD3(repeating: scale) }
            ///Start moving
            let animation = creep.move(to: unitTransform, relativeTo: creep.anchor, duration: TimeInterval(speed), timingFunction: .linear)
            creeps[creep.id]?.animation = animation
            let subscription = arView.scene.publisher(for: AnimationEvents.PlaybackCompleted.self)
                .filter { $0.playbackController == animation }
                .sink(receiveValue: { event in
                    self.deployUnit(creep, speed: speed, to: index + 1, on: path, baseHeight: height)
                })
            creeps[creep.id]?.subscription = subscription
        } else if index == path.count {
            creep.removeFromParent()
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
        if let tappedPlacing = placings.first(where: { id, _ in entities.contains(where: {$0.id == id}) }) {
            if tappedPlacing.key == selectedPlacing?.model.id {
                selectedPlacing = nil
                towers.forEach { $1.accesory.isEnabled = false }
                reloadActionStrip(with: ActionStrip.none.options())
            } else {
                selectedPlacing = tappedPlacing.value
                towers.forEach { $1.accesory.isEnabled = false }
                if let tappedTowerId = tappedPlacing.value.towerId {
                    guard let towerBundle = towers.first(where: { id, _ in id == tappedTowerId })?.value else { return }
                    towerBundle.accesory.isEnabled = true
                    reloadActionStrip(with: ActionStrip.tower.options(for: towerBundle.type))
                } else {
                    reloadActionStrip(with: ActionStrip.placing.options())
                }
            }
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
//                let floor = neutralFloorTemplate.embeddedModel(at: [x, 0.005, z])
//                anchor.addChild(floor.model)
                switch mapType {
                case .neutral: break
//                    let chance = Int.random(in: 1...10)
//                    let rotation = Direction.baseMoves[Int.random(in: 0...3)].rotation()
//                    switch chance {
//                    case 7...8:
//                        let floor = neutralTankTemplate.embeddedModel(at: [x, 0.003, z])
//                        floor.model.transform.rotation = rotation
//                        anchor.addChild(floor.model)
//                    case 10:
//                        let floor = neutralBarrelTemplate.embeddedModel(at: [x, 0.003, z])
//                        floor.model.transform.rotation = rotation
//                        anchor.addChild(floor.model)
//                    default: break
//                    }
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
                    placings[placing.model.id] = (placing.model, (row,column), nil)
                case .higherPlacing:
                    let placing = placingTemplate.embeddedModel(at: [x, 0.102, z])
                    let bounds = placing.entity.visualBounds(relativeTo: placing.model)
                    placing.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)])
                    anchor.addChild(placing.model)
                    placings[placing.model.id] = (placing.model, (row,column), nil)
                case .spawn:
                    let station = spawnTemplate.embeddedModel(at: [x, 0.001, z])
                    spawnPlaces.append((station.model, (row, column), usedMaps))
                    anchor.addChild(station.model)
                }
            }
        }
    }
    
    func insertTower(towerType: TowerType, towerLvl: TowerLevel) {
        guard let placingPosition = selectedPlacing?.model.position, let anchor = selectedPlacing?.model.anchor as? AnchorEntity else { return }
        
        coins -= towerType.cost(lvl: towerLvl)
        let tower: EmbeddedModel = {
            switch towerLvl {
            case .lvl1:
                switch towerType{
                case .turret: return turretLvl1Template.embeddedModel(at: placingPosition)
                case .rocketLauncher: return rocketLauncherLvl1Template.embeddedModel(at: placingPosition)
                case .barracks: return barracksTemplate.embeddedModel(at: placingPosition)
                }
            case .lvl2, .lvl3:
                switch towerType{
                case .turret: return turretLvl2Template.embeddedModel(at: placingPosition)
                case .rocketLauncher: return rocketLauncherLvl2Template.embeddedModel(at: placingPosition)
                case .barracks: return barracksTemplate.embeddedModel(at: placingPosition)
                }
            }
        }()
        placings.keys.forEach { id in
            if id == selectedPlacing?.model.id {
                placings[id]?.towerId = tower.model.id
                selectedPlacing?.towerId = tower.model.id
            }
        }
        tower.model.position.y += 0.003
        anchor.addChild(tower.model)
        ///Tower range accesorry
        let diameter = 2.0 * gridDiameter * towerType.range * 0.1
        let rangeAccessory = ModelEntity(mesh: .generateBox(size: SIMD3(x: diameter, y: 0.02, z: diameter), cornerRadius: 0.025), materials: [SimpleMaterial(color: UIColor.red.withAlphaComponent(0.05), isMetallic: false)])
        tower.model.addChild(rangeAccessory)
        rangeAccessory.position.y += 0.02
        var towerSubscriptions = [Cancellable]()
        
        if towerType == .barracks {
            rangeAccessory.position.z += diameter
            let unitOffset: SIMD3<Float> = [0, 0.02, diameter]
            for _ in (0..<towerType.capacity(lvl: towerLvl)) {
                let troop: EmbeddedModel = regularCreep.embeddedModel(at: unitOffset)
                troop.model.scale = (SIMD3(repeating: 10))
                let bounds = troop.entity.visualBounds(relativeTo: troop.model)
                troop.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents)], mode: .trigger, filter: CollisionFilter(group: Filter.towers.group, mask: Filter.creeps.group))
                tower.model.addChild(troop.model)
                let troopHPbar = self.fullHPBarTemplate.clone(recursive: true)
                troop.model.addChild(troopHPbar)
                troopHPbar.position.y = (bounds.extents.y / 2) + 0.003
                troop.entity.playAnimation(troop.entity.availableAnimations[0].repeat())

                let endSubs = arView.scene.subscribe(to: CollisionEvents.Ended.self, on: tower.model) {
                    event in
                    guard let creep = event.entityB as? ModelEntity else { return }
                    self.troops[troop.model.id]?.unit.enemiesIds.removeAll(where: { $0 == creep.id })
                }
                let beganSubs = arView.scene.subscribe(to: CollisionEvents.Began.self, on: troop.model) {
                    event in
                    switch towerType {
                    case .turret, .rocketLauncher: break
                    case .barracks:
                        guard let creepModel = event.entityB as? ModelEntity, let creepBundle = self.creeps[creepModel.id] else { return }
                        guard let troopModel = event.entityA as? ModelEntity else { return }
                        self.troops[troopModel.id]?.unit.enemiesIds.append(creepModel.id)
                        self.creeps[creepModel.id]?.animation?.pause()
                        
                        let towerTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(towerType.cadence(lvl: towerLvl)), repeats: true) { timer in
                            guard self.troops[troopModel.id]?.unit.enemiesIds.contains(creepModel.id) ?? false else { timer.invalidate() ; return }
                            
                            self.damageUnit(unitModel: creepModel, unitBundle: &self.creeps[creepModel.id]!.unit, attack: towerType.attack(lvl: towerLvl)) {
                                self.coins += creepBundle.type.reward
                                self.troops[troopModel.id]?.unit.enemiesIds.removeAll(where: { id in id == creepModel.id })
                                creepModel.removeFromParent()
                            }
                        }
                        towerTimer.fire()
                        let creepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(creepBundle.type.cadence), repeats: true) { timer in
                            guard self.creeps.keys.contains(creepModel.id) else { timer.invalidate() ; return }
                            
                            self.damageUnit(unitModel: troopModel, unitBundle: &self.troops[troopModel.id]!.unit, attack: creepBundle.type.attack) {
                                self.creeps[creepModel.id]?.animation?.resume()
                                troopModel.removeFromParent()
                            }
                        }
                        creepTimer.fire()
                    }
                }
                towerSubscriptions = [beganSubs, endSubs]
                troops[troop.model.id] = ((troopHPbar.id, towerType.maxHP(lvl: towerLvl), towerType.maxHP(lvl: towerLvl), []), tower.model.id)
            }
            
        } else {
            let collisionOffset: SIMD3<Float> = [0, 0.02, 0]
            let collisionSize: SIMD3<Float> = [diameter, 0.02, diameter]
            tower.model.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: collisionSize).offsetBy(translation: collisionOffset)], mode: .trigger, filter: CollisionFilter.init(group: Filter.towers.group, mask: Filter.creeps.group)))
            
            let endSubs = arView.scene.subscribe(to: CollisionEvents.Ended.self, on: tower.model) {
                event in
                guard let creep = event.entityB as? ModelEntity else { return }
                self.towers[tower.model.id]?.enemiesIds.removeAll(where: { $0 == creep.id })
            }
            
            let updateSubs = arView.scene.subscribe(to: CollisionEvents.Updated.self, on: tower.model) {
                event in
                switch towerType {
                case .turret: break
//                guard let enemyID = self.towers[tower.model.id]?.enemiesIds.first, let creep = event.entityB as? ModelEntity, creep.id == enemyID else { return }
//                let angle = atan2(event.position.z - placingPosition.z, event.position.x - placingPosition.x)
//                let orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
//                let orientation = simd_quatf(from: selectedPlacing.model.position, to: event.position)
//                tower.model.setOrientation(orientation, relativeTo: anchor)
                case .barracks, .rocketLauncher: break
                }
            }
            
            let beganSubs = arView.scene.subscribe(to: CollisionEvents.Began.self, on: tower.model) {
                event in
                guard let creepModel = event.entityB as? ModelEntity, let creepBundle = self.creeps[creepModel.id] else { return }
                guard let towerModel = event.entityA as? ModelEntity else { return }
                switch towerType {
                case .turret, .rocketLauncher:
                    self.towers[towerModel.id]?.enemiesIds.append(creepModel.id)
                    let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(towerType.cadence(lvl: towerLvl)), repeats: true) { timer in
                        guard self.towers[towerModel.id]?.enemiesIds.contains(creepModel.id) ?? false else { timer.invalidate() ; return }
                        self.fireBullet(towerId: towerModel.id, towerType: towerType, towerLvl: towerLvl, creepModel: creepModel, anchor: anchor, placingPosition: placingPosition, creepBundle: creepBundle)
                    }
                    timer.fire()
                case .barracks: break
                }
            }
            
            towerSubscriptions = [beganSubs, updateSubs, endSubs]
        }
        towers[tower.model.id] = (tower.model, towerType, towerLvl, rangeAccessory, [], towerSubscriptions)
    }
    
    func fireBullet(towerId: UInt64, towerType: TowerType, towerLvl: TowerLevel, creepModel: ModelEntity, anchor: AnchorEntity, placingPosition: SIMD3<Float>, creepBundle: CreepBundle) {
        guard let enemiesCount = self.towers[towerId]?.enemiesIds.count else { return }
        let capacity = min(enemiesCount, towerType.capacity(lvl: towerLvl))
        towers[towerId]?.enemiesIds[0..<capacity].forEach { id in
            guard id == creepModel.id else { return }
            let bullet = self.bulletTemplate.embeddedModel(at: placingPosition)
            bullet.model.transform.translation.y += 0.015
            anchor.addChild(bullet.model)
            var bulletTransform = bullet.model.transform
            bulletTransform.translation = creepModel.position
            let animation = bullet.model.move(to: bulletTransform, relativeTo: bullet.model.anchor, duration: 0.2, timingFunction: .linear)
            let subscription = arView.scene.publisher(for: AnimationEvents.PlaybackCompleted.self)
                .filter { $0.playbackController == animation }
                .sink( receiveValue: { event in
                    self.bullets.forEach { id, bulletBundle in
                        if bulletBundle.animation.isComplete {
                            bulletBundle.subscription?.cancel()
                            self.bullets.removeValue(forKey: id)
                        }
                    }
                    self.bullets[bullet.model.id]?.model.removeFromParent()
                    self.damageUnit(unitModel: creepModel, unitBundle: &self.creeps[creepModel.id]!.unit, attack: towerType.attack(lvl: towerLvl)) {
                        self.coins += creepBundle.type.reward
                        self.towers[towerId]?.enemiesIds.removeAll(where: { id in id == creepModel.id })
                        creepModel.removeFromParent()
                    }
                })
            self.bullets[bullet.model.id] = (bullet.model, animation,subscription)
        }
    }
    func damageUnit(unitModel: ModelEntity, unitBundle: inout UnitBundle, attack: Float, handler: (() -> Void)? = nil) {
        guard let (childIndex, child) = unitModel.children.enumerated().first(where: { $1.id == unitBundle.hpBarId }) else { return }
        unitBundle.hp -= attack
        if unitBundle.hp < 0 { handler?(); unitBundle.enemiesIds.removeAll() }
        let hpPercentage = unitBundle.hp / unitBundle.maxHP
        let newHPBar: ModelEntity = {
            switch hpPercentage {
            case (0.00...0.32): return self.lowHPBarTemplate.clone(recursive: true)
            case (0.33...0.64): return self.halfHPBarTemplate.clone(recursive: true)
            default: return self.fullHPBarTemplate.clone(recursive: true)
            }
        }()
        newHPBar.scale = [hpPercentage, 1.0, 1.0]
        unitModel.children[childIndex] = newHPBar
        newHPBar.position = child.position
        child.removeFromParent()
        unitBundle.hpBarId = newHPBar.id
        
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
        switch strip.action {
        case .none: break
        case .map: break
        case .placing:
            let towerType = TowerType.allCases[indexPath.row]
            if towerType.cost(lvl: .lvl1) <= coins {
                insertTower(towerType: towerType, towerLvl: .lvl1)
                reloadActionStrip(with: ActionStrip.tower.options(for: towerType))
            }
        case .tower:
            guard let towerId = selectedPlacing?.towerId, let placingId = selectedPlacing?.model.id, let tower = towers[towerId] else { break }
            switch strip.options[indexPath.row] {
            case .upgrade:
                guard let tower = towers[towerId], tower.lvl.nextLevel != tower.lvl, tower.type.cost(lvl: tower.lvl.nextLevel) <= coins  else { break }
                towers.removeValue(forKey: towerId)
                tower.model.removeFromParent()
                insertTower(towerType: tower.type, towerLvl: tower.lvl.nextLevel)
                reloadActionStrip(with: ActionStrip.tower.options(for: tower.type))
            case .sell:
                placings[placingId]?.towerId = nil
                towers.removeValue(forKey: towerId)
                tower.model.removeFromParent()
                coins += Int(Float(tower.type.cost(lvl: tower.lvl)) * 0.5)
                reloadActionStrip(with: ActionStrip.placing.options())
            default: break
            }
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return strip.options.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Action Strip Cell", for: indexPath)
        let imageView = cell.contentView.viewWithTag(10) as? UIImageView
        let label = cell.contentView.viewWithTag(11) as? UILabel
        let option = strip.options[indexPath.row]
        imageView?.image = option.iconImage
        label?.text = {
            label?.isHidden = false
            switch strip.options[indexPath.row] {
            case .upgrade:
                guard let towerId = selectedPlacing?.towerId, let tower = towers[towerId] else { return nil }
                return tower.lvl == tower.lvl.nextLevel ? "MAX" : "\(tower.type.cost(lvl: tower.lvl.nextLevel))"
            case .sell:
                guard let towerId = selectedPlacing?.towerId, let tower = towers[towerId] else { return nil }
                return "\(Int(Float(tower.type.cost(lvl: tower.lvl)) * 0.5))"
            case .turret: return "\(TowerType.turret.cost(lvl: .lvl1))"
            case .launcher: return "\(TowerType.rocketLauncher.cost(lvl: .lvl1))"
            case .barracks: return "\(TowerType.barracks.cost(lvl: .lvl1))"
            case .moveRight, .moveLeft, .rotateRight, .rotateLeft:
                label?.isHidden = true
                return nil
            }
        }()
        cell.contentView.layer.cornerRadius = 30.0
        cell.contentView.layer.masksToBounds = true
        cell.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
        return cell
    }
}
