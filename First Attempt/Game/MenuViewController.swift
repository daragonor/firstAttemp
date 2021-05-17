//
//  MenuViewController.swift
//  First Attempt
//
//  Created by Daniel Aragon on 7/12/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import UIKit

class MenuViewController: UIViewController {
    enum MenuState: String, CaseIterable {
        case menu, missions, lobby, settings, enciclopedia
        var contentHeight: CGFloat {
            switch self {
            case .menu: return 50.0
            case .missions: return 50.0
            case . lobby: return 50.0
            default: return 0.0
            }
        }
        static var identifier: String { "menuCell" }
    }
    enum MenuOptions: String, CaseIterable {
        case start, multiplayer, settings, enciclopedia
    }
    
    enum LobbyOptions: String, CaseIterable {
        case spectate, cooperative
    }
    
    enum EnciclopediaOptions: String, CaseIterable {
        case towers, creeps
    }
    
    var resize: ((CGFloat) -> Void)?
    var loadMission: ((Int) -> Void)?
    var showMenu: (() -> Void)?

    var state: MenuState = .menu
    var logoView: UIView?
    lazy var gameConfig: GameModel = {
        let filePath = Bundle.main.path(forResource: "config", ofType: "json")!
        let data = try! NSData(contentsOfFile: filePath) as Data
        return try! JSONDecoder().decode(GameModel.self, from: data)
    }()
    
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
    }
    
}

extension MenuViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var rows = 0
        switch state {
        case .menu:
            rows = MenuOptions.allCases.count
        case .missions:
            rows = gameConfig.missions.count
        case .lobby:
            rows = LobbyOptions.allCases.count
        case .settings:
            rows = 2
        case .enciclopedia:
            rows = EnciclopediaOptions.allCases.count
        }
        resize?(CGFloat(rows) * state.contentHeight)
        return rows
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MenuState.identifier, for: indexPath)
        let imageView = cell.contentView.viewWithTag(11) as? UIImageView
        imageView?.image = #imageLiteral(resourceName: "menu-button")
        let titleLabel = cell.contentView.viewWithTag(12) as? UILabel
        switch state {
        case .menu:
            logoView?.isHidden = false
            showMenu?()
            titleLabel?.text = MenuOptions.allCases[indexPath.row].rawValue.firstUppercased
            return cell
        case .missions:
            showMenu?()
            titleLabel?.text = "Mission \(indexPath.row + 1)"
            return cell
        case .lobby:
            titleLabel?.text = LobbyOptions.allCases[indexPath.row].rawValue.firstUppercased

        case .settings:
            if indexPath.row == 0 {
                return  UITableViewCell()
            } else {
                titleLabel?.text = "Return"
            }
        case .enciclopedia:
            titleLabel?.text = LobbyOptions.allCases[indexPath.row].rawValue.firstUppercased
        }
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch state {
        case .menu:
            switch MenuOptions.allCases[indexPath.row] {
            case .start:
                logoView?.isHidden = true
                state = .missions
            case .multiplayer:
                state = .lobby
            case .settings:
                state = .settings
            case .enciclopedia:
                state = .enciclopedia
            }
            tableView.reloadData()
        case .missions:
            loadMission?(indexPath.row)
        case .lobby:
            break
        case .settings:
             break
        case .enciclopedia:
            break
        }
    }
}
