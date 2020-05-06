/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Methods on the main view controller for conforming to the ARCoachingOverlayViewDelegate protocol.
*/

import UIKit
import ARKit

extension ViewController: ARCoachingOverlayViewDelegate {
    
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {

    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {

    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
    }

    func setupCoachingOverlay() {
        // Set up coaching view
        coachingOverlay.session = arView.session
        coachingOverlay.delegate = self
        coachingOverlay.goal = .tracking
        
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coachingOverlay)
        
        NSLayoutConstraint.activate([
            coachingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coachingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            coachingOverlay.widthAnchor.constraint(equalTo: view.widthAnchor),
            coachingOverlay.heightAnchor.constraint(equalTo: view.heightAnchor)
            ])
    }
}
