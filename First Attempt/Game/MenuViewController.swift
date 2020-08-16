//
//  MenuViewController.swift
//  First Attempt
//
//  Created by Daniel Aragon on 7/12/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import UIKit

class MenuViewController: UIViewController {
    enum Action: String {
        case menu
        var contentHeight: CGFloat {
            switch self {
            case .menu: return 50.0
            }
        }
        var identifier: String { "\(self.rawValue)Cell" }
    }
    var resize: ((CGFloat) -> Void)?
    var start: (() -> Void)?
    var action: Action = .menu
    enum Menu: String, CaseIterable {
        case start, multiplayer, settings, enciclopedia
    }
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
        switch action {
        case .menu:
            let rows = Menu.allCases.count
            resize?(CGFloat(rows) * action.contentHeight)
            return rows
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch action {
        case .menu:
            let cell = tableView.dequeueReusableCell(withIdentifier: action.identifier, for: indexPath)
            let imageView = cell.contentView.viewWithTag(11) as? UIImageView
            imageView?.image = #imageLiteral(resourceName: "menu-button")
            let titleLabel = cell.contentView.viewWithTag(12) as? UILabel
            titleLabel?.text = Menu.allCases[indexPath.row].rawValue.firstUppercased
            return cell
        }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch action {
        case .menu:
            switch Menu.allCases[indexPath.row] {
            case .start:
                start?()
            default:
                break
            }
        }
    }
}
