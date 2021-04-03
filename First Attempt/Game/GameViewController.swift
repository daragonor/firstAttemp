//
//  GameViewController.swift
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
enum GameState {
    case menu
    case missions
    case lobby
}

typealias ActionStripBundle = (action: Action, options: [StripOption])

enum Action {
    case none, placing, undo, ready, tower(type: TowerType)
    var strip: ActionStripBundle {
        var options = [StripOption]()
        switch self {
        case .undo: options = [.undo]
        case .ready: options = [.undo, .start]
        case .placing: options = [.turret, .launcher, .barracks]
        case .tower(let type):
            switch type {
            case .turret, .rocket: options = [.upgrade, .sell]
            case .barracks: options = [.upgrade, .sell, .rotateLeft, .rotateRight]
            }
        case .none: options = []
        }
        return (self, options)
    }
}
enum Filter: Int {
    case placings, towers, creeps
    var group: CollisionGroup {
        return CollisionGroup(rawValue: UInt32(rawValue))
    }
}

class GameViewController: UIViewController {

    @IBOutlet var arView: ARView!
    
    @IBOutlet weak var coinsLabel: UILabel!
    @IBOutlet weak var hpLabel: UILabel!
    @IBOutlet weak var waveLabel: UILabel!
    @IBOutlet weak var stripTableView: UITableView!
    
    @IBOutlet weak var menuContainer: UIView!
    @IBOutlet weak var menuContainerHeight: NSLayoutConstraint!
    @IBOutlet weak var gameMenuView: UIView!
    @IBOutlet weak var gameInfoStackView: UIStackView!
    @IBOutlet weak var logoView: UIView!
    var menuViewController: MenuViewController!
    var arConfig: ARWorldTrackingConfiguration!
    
    var multipeerSession: MultipeerSession?
    let coachingOverlay = ARCoachingOverlayView()
    var peerSessionIDs = [MCPeerID: String]()
    var sessionIDObservation: NSKeyValueObservation?
    
    var mapTemplates = [String: Entity]()
    var unitTemplates = [String: Entity]()
    
    let gridDiameter: Float = 0.5
    let waveInterval: Float = 10.0
    var waveCount = 0
    var coins = 2000
    var mission = 0
    var playerHP = 20
    var usedMaps = 0
    var coinsTimer: Timer?
    var canStart: Bool { usedMaps == gameConfig.missions[mission].maps.count }
    var hasStarted: Bool = false
    var didMissionFinish = false
    
    var spawnPlaces = [SpawnBundle]()
    var glyphs = [UInt64: ModelEntity]()
    var usedGlyphs = [UInt64]()
    var creeps = [UInt64:CreepBundle]()
    var placings = [UInt64:PlacingBundle]()
    var towers = [UInt64:TowerBundle]()
    var troops = [UInt64:TroopBundle]()
    var bullets = [UInt64:BulletBundle]()
    
    var selectedPlacing: PlacingBundle?
    var strip: ActionStripBundle = (.none, [])
    var terrainAnchors = [AnchorEntity]()
    var loadingSubs: [AnyCancellable] = []
    var loadedModels = 0
    lazy var gameConfig: GameModel = {
        let filePath = Bundle.main.path(forResource: "config", ofType: "json")!
        let data = try! NSData(contentsOfFile: filePath) as Data
        return try! JSONDecoder().decode(GameModel.self, from: data)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        menuContainer.isHidden = false
        gameInfoStackView.isHidden = true
        gameMenuView.isHidden = false
        loadActionStrip()
    }


    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let menu = segue.destination as? MenuViewController else { return }
        menuViewController = menu
        menu.logoView = logoView
        menu.resize = { size in
            self.menuContainerHeight.constant = CGFloat(size)
        }
        
        menu.showMenu = {
            self.gameInfoStackView.isHidden = true
            self.loadDefaultValues()
            self.reloadActionStrip(with: Action.none.strip)
            let arConfig = ARWorldTrackingConfiguration()
            self.arView.session.run(arConfig, options: .removeExistingAnchors)
        }

        menu.loadMission = { mission in
            self.gameMenuView.isHidden = true
            self.loadMission(mission: mission)
            self.configureMultipeer()
        }
    }
    
    func showLoadingAssets() {
        let alert = UIAlertController(title: nil, message: "Loading assets...", preferredStyle: .alert)

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = UIActivityIndicatorView.Style.medium
        loadingIndicator.startAnimating();

        alert.view.addSubview(loadingIndicator)
        present(alert, animated: true, completion: nil)
    }
    
    func hideLoadingAssets() {
        dismiss(animated: false, completion: nil)
    }
    
    func loadDefaultValues() {
        self.waveCount = 0
        self.coins = 2000
        self.mission = 0
        self.playerHP = 20
        self.usedMaps = 0
    }
    
    func loadMission(mission: Int) {
        self.mission = mission
        self.gameInfoStackView.isHidden = false
        coinsLabel.text = "\(coins)"
        hpLabel.text = "\(playerHP)"
        waveLabel.text = "0/\(gameConfig.missions[mission].waves)"
        
        if loadedModels == .zero {
            showLoadingAssets()
            var modelNames = ModelType.allCases.map { $0.key }
            modelNames += CreepType.allCases.map { $0.key }
            modelNames += TowerType.allCases.map { $0.key(.lvl1) }
            modelNames += TowerType.allCases.map { $0.key(.lvl2) }
            modelNames += TowerType.allCases.map { $0.key(.lvl3) }

            for name in modelNames {
                loadingSubs.append(
                    ModelEntity.loadAsync(named: name)
                        .sink(receiveCompletion: { error in
                            print(error)
                        }, receiveValue: { entity in
                            self.loadedModels += 1
                            if self.loadedModels == modelNames.count {
                                for lifepoint in Lifepoints.allCases {
                                    self.mapTemplates[lifepoint.key] = ModelEntity(mesh: .generateBox(size: SIMD3(x: 0.003, y: 0.0005, z: 0.0005), cornerRadius: 0.0002), materials: [SimpleMaterial(color: lifepoint.color, isMetallic: false)])
                                }
                                self.hideLoadingAssets()
                                self.loadAnchorConfiguration()
                            }
                            
                            if let factor = ModelType(rawValue: name)?.scalingFactor {
                                entity.setScale(SIMD3(repeating: factor), relativeTo: nil)
                                self.mapTemplates[name] = entity
                            } else if let factor = CreepType(rawValue: name)?.scalingFactor {
                                entity.setScale(SIMD3(repeating: factor), relativeTo: nil)
                                self.unitTemplates[name] = entity
                            } else {
                                entity.setScale(SIMD3(repeating: TowerType.scalingFactor), relativeTo: nil)
                                self.unitTemplates[name] = entity
                            }
                        })
                )
            }
        } else  {
            self.loadAnchorConfiguration()
        }
    }
    
    func loadActionStrip() {
        stripTableView.transform = CGAffineTransform(rotationAngle: -(CGFloat)(Double.pi))
        stripTableView.showsVerticalScrollIndicator = false
    }
    
    func loadAnchorConfiguration() {
        arConfig = ARWorldTrackingConfiguration()
        arConfig.planeDetection = [.horizontal, .vertical]
        arConfig.isCollaborationEnabled = true
        arConfig.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            arConfig.frameSemantics.insert(.personSegmentationWithDepth)
        }
        arView.renderOptions.insert(.disableMotionBlur)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        arView.session.run(arConfig)
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap(_:))))
    }
    
    func checkMissionCompleted() {
        if creeps.isEmpty, self.waveCount == self.gameConfig.missions[self.mission].waves {
            didMissionFinish = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = UIAlertController(title: nil, message: "Mission Completed", preferredStyle: .alert)
                self.present(alert, animated: true) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.dismiss(animated: true) {
//                            self.terrainAnchors.forEach { terrain in terrain.removeFromParent() }
//                            self.loadDefaultValues()
                            self.menuViewController.state = .missions
                            self.menuViewController.tableView.reloadData()
                            self.gameMenuView.isHidden = false
                        }
                    }
                }
            }
        }
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
    
    func sendTower(type: String, lvl: String) {
        guard let multipeerSession = multipeerSession else { return }
        if let data = "\(type)+\(lvl)".data(using: .utf8) {
            multipeerSession.sendToPeers(data, reliably: true, peers: multipeerSession.connectedPeers)
        }
    }
    
    func sendAction(option: StripOption) {
        guard let multipeerSession = multipeerSession else { return }
        if let data = option.key.data(using: .utf8) {
            multipeerSession.sendToPeers(data, reliably: true, peers: multipeerSession.connectedPeers)
        }
    }
    
    func sendSelectedPlacing(position: Position) {
        guard let multipeerSession = multipeerSession else { return }
        if let data = "\(position.row),\(position.column)".data(using: .utf8) {
            multipeerSession.sendToPeers(data, reliably: true, peers: multipeerSession.connectedPeers)
        }
    }
    
    func reloadActionStrip(with newStrip: ActionStripBundle) {
        strip = newStrip
        stripTableView.reloadSections([0], with: .fade)
    }
    
    func startMission() {
        didMissionFinish = false
        var timeRemaining: Float = 0
        coinsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
        //agregar tiempo de espera entre waves
            if timeRemaining == 0, self.waveCount < self.gameConfig.missions[self.mission].waves {
                timeRemaining = self.waveInterval
                self.sendWave()
                self.waveCount += 1
                self.waveLabel.text = "\(self.waveCount)/\(self.gameConfig.missions[self.mission].waves)"
            } else { timeRemaining -= 1 }
            
            self.coins += 5
            self.coinsLabel.text = "\(self.coins)"
        }
        coinsTimer?.fire()
        reloadActionStrip(with: Action.none.strip)
        hasStarted = true
    }
    
    func sendWave() {
        guard canStart else { return }
        glyphs.forEach { _, model in model.removeFromParent() }
        for spawn in spawnPlaces {
            let paths = gameConfig.missions[mission].maps[spawn.map].creepPathsCoordinates(at: spawn.position,diameter: gridDiameter)
            var count = 0
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                guard count < 2 else { timer.invalidate() ; return }
                count += 1
                print(self.waveCount % CreepType.allCases.count)
                let creepType = CreepType.allCases[self.waveCount % CreepType.allCases.count]
                let creep: EmbeddedModel = self.unitTemplates[creepType.key]!.embeddedModel(at: spawn.model.transform.translation)
                creep.model.position.y += 0.03
                let bounds = creep.entity.visualBounds(relativeTo: creep.model)
                creep.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3(repeating: 0.0015))], mode: .trigger, filter: CollisionFilter(group: Filter.creeps.group, mask: Filter.towers.group))
                spawn.model.anchor?.addChild(creep.model)
                let creepHPbar = self.mapTemplates[Lifepoints.full.key]!.clone(recursive: true)
                creep.model.addChild(creepHPbar)
                creepHPbar.position.y = (bounds.extents.y / 2) + 0.003
                self.creeps[creep.model.id] = CreepBundle(hpBarId: creepHPbar.id, type: creepType, animation: nil, subscription: nil)
                creep.entity.playAnimation(creep.entity.availableAnimations[0].repeat())
                self.deployUnit(creep.model, type: creepType,speed: creepType.speed, on: paths[self.waveCount % paths.count], setScale: 10)
            }
            timer.fire()
        }
    }
    
    func deployUnit(_ creep: ModelEntity, type: CreepType, speed: Float, to index: Int = 0, on path: [OrientedCoordinate], baseHeight: Float? = nil, setScale: Float? = nil) {
        
        var unitTransform = creep.transform
        let move = path[index]
        ///Set new move
        let height = baseHeight ?? unitTransform.translation.y
        unitTransform.translation = move.coordinate
        unitTransform.translation.y += height
        unitTransform.rotation = simd_quatf(angle: move.angle + type.angleOffset, axis: [0, 1, 0])
        if let scale = setScale { unitTransform.scale = SIMD3(repeating: scale) }
        ///Start moving
        let animation = creep.move(to: unitTransform, relativeTo: creep.anchor, duration: TimeInterval(speed), timingFunction: .linear)
        creeps[creep.id]?.animation = animation
        let subscription = arView.scene.publisher(for: AnimationEvents.PlaybackCompleted.self)
            .filter { $0.playbackController == animation }
            .sink(receiveValue: { event in
                if move.mapLegend == .goal {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        creep.removeFromParent()
                    }
                    self.creeps.removeValue(forKey: creep.id)
                    self.playerHP -= 1
                    self.hpLabel.text = String(self.playerHP)
                    self.checkMissionCompleted()
                } else if move.mapLegend == .zipLineOut {
                    
                } else {
                    self.deployUnit(creep, type: type, speed: speed, to: index + 1, on: path, baseHeight: height)
                }
            })
        creeps[creep.id]?.subscription = subscription
        
    }
    
    func undoPlacing() {
        if let lastMap = terrainAnchors.last {
            lastMap.removeFromParent()
            usedMaps -= 1
            let lastGlyphId = usedGlyphs.removeLast()
            glyphs[lastGlyphId]?.isEnabled = true
        }
    }
    
    @objc func onTap(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: arView)
        let entities = arView.entities(at: tapLocation)
        guard let entity = entities.first else { return }
        if hasStarted, let tappedPlacing = placings.first(where: { id, _ in entities.contains(where: {$0.id == id}) }) {
            if tappedPlacing.key == selectedPlacing?.model.id {
                sendSelectedPlacing(position: (-1, -1))
                selectedPlacing = nil
                towers.forEach { $1.accessory.isEnabled = false }
                reloadActionStrip(with: Action.none.strip)
            } else {
                sendSelectedPlacing(position: tappedPlacing.value.position)
                selectedPlacing = tappedPlacing.value
                towers.forEach { $1.accessory.isEnabled = false }
                if let tappedTowerId = tappedPlacing.value.towerId {
                    guard let towerBundle = towers.first(where: { id, _ in id == tappedTowerId })?.value else { return }
                    towerBundle.accessory.isEnabled = true
                    reloadActionStrip(with: Action.tower(type: towerBundle.type).strip)
                } else {
                    reloadActionStrip(with: Action.placing.strip)
                }
            }
        } else {
            glyphs[entity.id]?.isEnabled = false
            usedGlyphs.append(entity.id)
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
                    let portal = mapTemplates[ModelType.goal.key]!.embeddedModel(at: [x, 0.03, z])
                    anchor.addChild(portal.model)
                    portal.model.orientation = Direction.right.orientation
                    portal.entity.playAnimation(portal.entity.availableAnimations[0].repeat())
                    fallthrough
                case .lowerPath:
                    var floor: EmbeddedModel {
                        for direction in Direction.allCases {
                            let (nextRow, nextColumn) = (row + direction.offset.row, column + direction.offset.column)
                            if nextRow >= 0 && nextRow < rows,
                                nextColumn >= 0 && nextColumn < columns {
                                if  MapLegend.allCases[map.matrix[nextRow][nextColumn]] == .higherPath {
                                    let floor = mapTemplates[ModelType.pathUpwards.key]!.embeddedModel(at: [x, 0.001, z])
                                    floor.entity.transform.rotation = simd_quatf(angle: direction.angle, axis: [0, 1, 0])
                                    return floor
                                }
                            }
                        }
                        return mapTemplates[ModelType.path.key]!.embeddedModel(at: [x, 0.001, z])
                    }
                    anchor.addChild(floor.model)
                case .higherPath:
                    var floor: EmbeddedModel {
                        for direction in Direction.baseMoves {
                            let (nextRow, nextColumn) = (row + direction.offset.row, column + direction.offset.column)
                            if nextRow >= 0 && nextRow < rows,
                                nextColumn >= 0 && nextColumn < columns {
                                if  MapLegend.allCases[map.matrix[nextRow][nextColumn]] == .lowerPath {
                                    let floor = mapTemplates[ModelType.pathDownwards.key]!.embeddedModel(at: [x, 0.1, z])
                                    floor.entity.transform.rotation = simd_quatf(angle: direction.angle + .pi, axis: [0, 1, 0])
                                    return floor
                                }
                            }
                        }
                        return mapTemplates[ModelType.path.key]!.embeddedModel(at: [x, 0.1, z])
                    }
                    anchor.addChild(floor.model)
                case .lowerPlacing:
                    let placing = mapTemplates[ModelType.towerPlacing.key]!.embeddedModel(at: [x, 0.005, z])
                    let bounds = placing.entity.visualBounds(relativeTo: placing.model)
                    placing.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)])
                    anchor.addChild(placing.model)
                    placings[placing.model.id] = PlacingBundle(model: placing.model, position: (row,column), towerId: nil)
                case .higherPlacing:
                    let placing = mapTemplates[ModelType.towerPlacing.key]!.embeddedModel(at: [x, 0.102, z])
                    let bounds = placing.entity.visualBounds(relativeTo: placing.model)
                    placing.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)])
                    anchor.addChild(placing.model)
                    placings[placing.model.id] = PlacingBundle(model: placing.model, position: (row,column), towerId: nil)
                case .spawn:
                    let station = mapTemplates[ModelType.spawnPort.key]!.embeddedModel(at: [x, 0.001, z])
                    spawnPlaces.append(SpawnBundle(model: station.model, position: (row, column), map: usedMaps))
                    anchor.addChild(station.model)
                }
            }
        }
    }
    
    func insertTower(towerType: TowerType, towerLvl: TowerLevel) {
        guard let placingPosition = selectedPlacing?.model.position, let anchor = selectedPlacing?.model.anchor as? AnchorEntity else { return }
        
        coins -= towerType.cost(lvl: towerLvl)
        let tower: EmbeddedModel = unitTemplates[towerType.key(towerLvl)]!.embeddedModel(at: placingPosition)
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
                let troop: EmbeddedModel = unitTemplates[CreepType.regular.key]!.embeddedModel(at: unitOffset)
                troop.model.scale = (SIMD3(repeating: 10))
                let bounds = troop.entity.visualBounds(relativeTo: troop.model)
                troop.model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents)], mode: .trigger, filter: CollisionFilter(group: Filter.towers.group, mask: Filter.creeps.group))
                tower.model.addChild(troop.model)
                let troopHPbar = mapTemplates[Lifepoints.full.key]!.clone(recursive: true)
                troop.model.addChild(troopHPbar)
                troopHPbar.position.y = (bounds.extents.y / 2) + 0.003
                troop.entity.playAnimation(troop.entity.availableAnimations[0].repeat())
                
                let endSubs = arView.scene.subscribe(to: CollisionEvents.Ended.self, on: tower.model) {
                    event in
                    guard let creep = event.entityB as? ModelEntity else { return }
                    self.troops[troop.model.id]?.enemiesIds.removeAll(where: { $0 == creep.id })
                }
                let beganSubs = arView.scene.subscribe(to: CollisionEvents.Began.self, on: troop.model) {
                    event in
                    switch towerType {
                    case .turret, .rocket: break
                    case .barracks:
                        guard let creepModel = event.entityB as? ModelEntity, let creepBundle = self.creeps[creepModel.id] else { return }
                        guard let troopModel = event.entityA as? ModelEntity else { return }
                        self.troops[troopModel.id]?.enemiesIds.append(creepModel.id)
                        self.creeps[creepModel.id]?.animation?.pause()
                        
                        let towerTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(towerType.cadence(lvl: towerLvl)), repeats: true) { timer in
                            guard self.troops[troopModel.id]?.enemiesIds.contains(creepModel.id) ?? false else { timer.invalidate() ; return }
                            
                            self.damageCreep(creepModel: creepModel, towerId: troopModel.id, attack: towerType.attack(lvl: towerLvl))
                        }
                        towerTimer.fire()
                        let creepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(creepBundle.type.cadence), repeats: true) { timer in
                            guard self.creeps.keys.contains(creepModel.id) else { timer.invalidate() ; return }
                            self.damageTroop(troopModel: troopModel, creepId: creepModel.id, attack: creepBundle.type.attack)
                        }
                        creepTimer.fire()
                    }
                }
                towerSubscriptions = [beganSubs, endSubs]
                troops[troop.model.id] = TroopBundle(hpBarId: troopHPbar.id,maxHP: towerType.maxHP(lvl: towerLvl), towerId: tower.model.id)
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
                case .turret:
                    guard let enemyID = self.towers[tower.model.id]?.enemiesIds.first, let creepModel = event.entityB as? ModelEntity, creepModel.id == enemyID else { return }
                    guard let _ = event.entityA as? ModelEntity else { return }
                    //                self.rotateTower(towerId: towerModel.id, creep: creepModel)
                    break
                case .barracks, .rocket: break
                }
            }
            
            let beganSubs = arView.scene.subscribe(to: CollisionEvents.Began.self, on: tower.model) {
                event in
                guard let creepModel = event.entityB as? ModelEntity, let creepBundle = self.creeps[creepModel.id] else { return }
                guard let towerModel = event.entityA as? ModelEntity else { return }
                
                self.towers[towerModel.id]?.enemiesIds.append(creepModel.id)
                let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(towerType.cadence(lvl: towerLvl)), repeats: true) { timer in
                    guard self.towers[towerModel.id]?.enemiesIds.contains(creepModel.id) ?? false else { timer.invalidate() ; return }
                    self.fireBullet(towerId: towerModel.id, towerType: towerType, towerLvl: towerLvl, creepModel: creepModel, anchor: anchor, placingPosition: placingPosition, creepBundle: creepBundle)
                }
                timer.fire()
            }
            towerSubscriptions = [beganSubs, updateSubs, endSubs]
        }
        towers[tower.model.id] = TowerBundle(model: tower.model, type: towerType, lvl: towerLvl, accessory: rangeAccessory, collisionSubs: towerSubscriptions)
    }
    
    
    func rotateTower(towerId: UInt64, creep: ModelEntity){
        print(creep.position)
        let tower = self.towers[towerId]!.model
        let vectorProduct = creep.position.x * tower.position.x + creep.position.y * tower.position.y + creep.position.z * tower.position.z
        let vectorAModule = sqrtf(powf(creep.position.x, 2.0) + powf(creep.position.y, 2.0) + powf(creep.position.z, 2.0))
        let vectorBModule = sqrtf(powf(tower.position.x, 2.0) + powf(tower.position.y, 2.0) + powf(tower.position.z, 2.0))
        let angle = acosf(vectorProduct / (vectorAModule * vectorBModule))
        
        let sinTower = sinf(angle * 0.5)
        let cosTower = cosf(angle * 0.5)
        
        let q0 = simd_quatf(ix: 0.0, iy: sinTower, iz: 0.0, r: cosTower)
        
        self.towers[towerId]?.model.setOrientation(q0, relativeTo: creep
            .anchor)
    }
    
    func fireBullet(towerId: UInt64, towerType: TowerType, towerLvl: TowerLevel, creepModel: ModelEntity, anchor: AnchorEntity, placingPosition: SIMD3<Float>, creepBundle: CreepBundle) {
        guard let enemiesCount = self.towers[towerId]?.enemiesIds.count else { return }
        let capacity = min(enemiesCount, towerType.capacity(lvl: towerLvl))
        
        towers[towerId]?.enemiesIds[0..<capacity].forEach { id in
            guard id == creepModel.id else { return }
            let bullet = mapTemplates[ModelType.bullet.key]!.embeddedModel(at: placingPosition)
            bullet.model.transform.translation.y += 0.015
            anchor.addChild(bullet.model)
            var bulletTransform = bullet.model.transform
            bulletTransform.translation = creepModel.position
//            bullet.model.orientation = orientato(to: creepModel)
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
                    self.damageCreep(creepModel: creepModel, towerId: towerId, attack: towerType.attack(lvl: towerLvl))
                })
            self.bullets[bullet.model.id] = BulletBundle(model: bullet.model, animation: animation,subscription: subscription)
        }
    }
    
    func damageTroop(troopModel: ModelEntity, creepId: UInt64, attack: Float) {
        guard let troopBundle = troops[troopModel.id], let (childIndex, child) = troopModel.children.enumerated().first(where: { $1.id == troops[troopModel.id]?.hpBarId }) else { return }
        troops[troopModel.id]?.hp -= attack
        if troopBundle.hp < 0 {
            creeps[creepId]?.animation?.resume()
            troopModel.removeFromParent()
            troops[troopModel.id]?.enemiesIds.removeAll()
            troops.removeValue(forKey: troopModel.id)
        }
        let hpPercentage = troopBundle.hp / troopBundle.maxHP
        let hpBar = mapTemplates[Lifepoints.status(hp: hpPercentage).key]!.clone(recursive: true)
        hpBar.scale = [hpPercentage, 1.0, 1.0]
        troopModel.children[childIndex] = hpBar
        hpBar.position = child.position
        child.removeFromParent()
        troops[troopModel.id]?.hpBarId = hpBar.id
    }
    
    func damageCreep(creepModel: ModelEntity, towerId: UInt64, attack: Float) {
        guard let creepBundle = creeps[creepModel.id], let (childIndex, child) = creepModel.children.enumerated().first(where: { $1.id == creeps[creepModel.id]?.hpBarId }) else { return }
        creeps[creepModel.id]?.hp -= attack
        if creepBundle.hp < 0 {
            coins += creepBundle.type.reward
            towers[towerId]?.enemiesIds.removeAll(where: { id in id == creepModel.id })
            creepModel.removeFromParent()
            creeps.removeValue(forKey: creepModel.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkMissionCompleted()
            }
        }
        let hpPercentage = creepBundle.hp / creepBundle.maxHP
        let hpBar = mapTemplates[Lifepoints.status(hp: hpPercentage).key]!.clone(recursive: true)
        hpBar.scale = [hpPercentage, 1.0, 1.0]
        creepModel.children[childIndex] = hpBar
        hpBar.position = child.position
        child.removeFromParent()
        creeps[creepModel.id]?.hpBarId = hpBar.id
    }
}

extension GameViewController: ARSessionDelegate {
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            
            if let _ = anchor as? ARParticipantAnchor {
                
            } else if anchor.name == "Terrain" {
                let terrainAnchor = AnchorEntity(anchor: anchor)
                terrainAnchor.name = "TerrainAnchorEntity"
                arView.scene.addAnchor(terrainAnchor)
                terrainAnchors.append(terrainAnchor)
                let maps = gameConfig.missions[mission].maps
                if usedMaps < maps.count {
                    insertMap(anchor: terrainAnchor, map: maps[usedMaps])
                    usedMaps += 1
                    maps.count == usedMaps ?
                        reloadActionStrip(with: Action.ready.strip) : reloadActionStrip(with: Action.undo.strip)
                }
                
            } else {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                let model = ModelEntity()
                let glyph = mapTemplates[ModelType.here.key]!.clone(recursive: true)
                model.addChild(glyph)
                let anchorEntity = AnchorEntity(anchor: planeAnchor)
                anchorEntity.addChild(model)
                arView.scene.addAnchor(anchorEntity)
                glyphs[model.id] = model
                glyph.playAnimation(glyph.availableAnimations[0].repeat())
                let entityBounds = glyph.visualBounds(relativeTo: model)
                model.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: entityBounds.extents).offsetBy(translation: entityBounds.center)])
                arView.installGestures([.rotation, .translation] ,for: model)
                //añadir rotation al anchor
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
extension GameViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch strip.action {
        case .none: break
        case .ready:
            switch Action.ready.strip.options[indexPath.row] {
            case .undo:
                undoPlacing()
                sendAction(option: StripOption.undo)
            case .start:
                startMission()
                sendAction(option: StripOption.start)
            default: break
            }
        case .undo:
            undoPlacing()
            sendAction(option: StripOption.undo)
        case .placing:
            let towerType = TowerType.allCases[indexPath.row]
            guard towerType.cost(lvl: .lvl1) <= coins else { return }
            insertTower(towerType: towerType, towerLvl: .lvl1)
            sendTower(type: towerType.rawValue, lvl: TowerLevel.lvl1.rawValue)
            reloadActionStrip(with: Action.tower(type: towerType).strip)
        case .tower:
            guard let towerId = selectedPlacing?.towerId, let placingId = selectedPlacing?.model.id, let tower = towers[towerId] else { break }
            switch strip.options[indexPath.row] {
            case .upgrade:
                guard let tower = towers[towerId], tower.lvl.nextLevel != tower.lvl, tower.type.cost(lvl: tower.lvl.nextLevel) <= coins  else { break }
                towers.removeValue(forKey: towerId)
                tower.model.removeFromParent()
                insertTower(towerType: tower.type, towerLvl: tower.lvl.nextLevel)
                reloadActionStrip(with: Action.tower(type: tower.type).strip)
            case .sell:
                placings[placingId]?.towerId = nil
                towers.removeValue(forKey: towerId)
                tower.model.removeFromParent()
                coins += Int(Float(tower.type.cost(lvl: tower.lvl)) * 0.5)
                reloadActionStrip(with: Action.placing.strip)
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
            case .launcher: return "\(TowerType.rocket.cost(lvl: .lvl1))"
            case .barracks: return "\(TowerType.barracks.cost(lvl: .lvl1))"
            case .undo, .start, .rotateRight, .rotateLeft:
                label?.isHidden = true
                return nil
            }
        }()
        cell.contentView.layer.cornerRadius = 30.0
        cell.contentView.layer.masksToBounds = true
        cell.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
        return cell
    }
    func receivedData(_ data: Data, from peer: MCPeerID) {
        
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            arView.session.update(with: collaborationData)
            return
        } else if let data = String(data: data, encoding: .utf8), data.contains("+") {
            DispatchQueue.main.async {
                let data = data.split(separator: "+").map { return String($0) }
                let towerType = TowerType.init(rawValue: data.first!)!
                let towerLvl = TowerLevel.init(rawValue: data.last!)!
                self.insertTower(towerType: towerType, towerLvl: towerLvl)
            }
        } else if let data = String(data: data, encoding: .utf8), data.contains(",") {
            DispatchQueue.main.async {
                let position = data.split(separator: ",").map { return Int($0) }
                self.selectedPlacing = self.placings.values.first(where: { $0.position.row == position.first && $0.position.column == position.last })
            }
        } else if let data = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                switch data {
                case StripOption.start.key: self.startMission()
                case StripOption.undo.key: self.undoPlacing()
                default: return
                }
            }
        }
//         
//                let sessionIDCommandString = "SessionID:"
//                if let commandString = String(data: data, encoding: .utf8), commandString.starts(with: sessionIDCommandString) {
//                    let newSessionID = String(commandString[commandString.index(commandString.startIndex,
//                                                                                offsetBy: sessionIDCommandString.count)...])
//                    // If this peer was using a different session ID before, remove all its associated anchors.
//                    // This will remove the old participant anchor and its geometry from the scene.
//                    if let oldSessionID = peerSessionIDs[peer] {
//                        removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
//                    }
//        
//                    peerSessionIDs[peer] = newSessionID
//                }
    }
}
