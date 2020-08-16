//
//  Utils.swift
//  First Attempt
//
//  Created by Daniel Aragon on 5/1/20.
//  Copyright © 2020 Daniel Aragon. All rights reserved.
//

import ARKit
import RealityKit

extension Entity {
    func embeddedModel(at position: SIMD3<Float>) -> EmbeddedModel {
        let model = ModelEntity()
        let entity = self.clone(recursive: true)
        model.addChild(entity)
        model.position = position
        return (model, entity)
    }
}
extension StringProtocol {
    var firstUppercased: String { return prefix(1).uppercased() + dropFirst() }
}

extension float4x4 {
    /// Returns the translation components of the matrix
    func toTranslation() -> SIMD3<Float> {
      return [self[3,0], self[3,1], self[3,2]]
    }
    /// Returns a quaternion representing the
    /// rotation component of the matrix
    func toQuaternion() -> simd_quatf {
        return simd_quatf(self)
    }
}

extension UUID {
    /**
     - Tag: ToRandomColor
    Pseudo-randomly return one of several fixed standard colors, based on this UUID's first four bytes.
    */
    func toRandomColor() -> UIColor {
        var firstFourUUIDBytesAsUInt32: UInt32 = 0
        let data = withUnsafePointer(to: self) {
            return Data(bytes: $0, count: MemoryLayout.size(ofValue: self))
        }
        _ = withUnsafeMutableBytes(of: &firstFourUUIDBytesAsUInt32, { data.copyBytes(to: $0) })

        let colors: [UIColor] = [.red, .green, .blue, .yellow, .magenta, .cyan, .purple,
        .orange, .white]
        
        let randomNumber = Int(firstFourUUIDBytesAsUInt32) % colors.count
        return colors[randomNumber]
    }
}

extension UIView {

    @IBInspectable var cornerRadius: CGFloat {
        get {
            return layer.cornerRadius
        }
        set {
            layer.cornerRadius = newValue
            layer.masksToBounds = newValue > 0
        }
    }

    @IBInspectable var borderWidth: CGFloat {
        get {
            return layer.borderWidth
        }
        set {
            layer.borderWidth = newValue
        }
    }

    @IBInspectable var borderColor: UIColor? {
        get {
            return UIColor(cgColor: layer.borderColor!)
        }
        set {
            layer.borderColor = newValue?.cgColor
        }
    }
}
