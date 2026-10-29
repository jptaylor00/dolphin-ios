// Copyright 2026
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

// A single continuous touch surface for Mario Kart's accelerate -> lock slide.
// Neither a separate button nor a pan recognizer can steal the moving finger.
private final class TCGasLockControl: UIView {
  var port: Int = 0
  private var locked = false
  private var trackingOne = false
  private let oneImage = UIImageView()
  private let lockLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  private func setup() {
    isMultipleTouchEnabled = false
    backgroundColor = .clear

    oneImage.frame = CGRect(x: 0, y: 2, width: 84, height: 84)
    oneImage.contentMode = .scaleAspectFit
    oneImage.image = UIImage(named: "wiimote_one", in: Bundle(for: TCButton.self), compatibleWith: nil)
    oneImage.isUserInteractionEnabled = false
    addSubview(oneImage)

    lockLabel.frame = CGRect(x: 94, y: 13, width: 70, height: 60)
    lockLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    lockLabel.textAlignment = .center
    lockLabel.textColor = .white
    lockLabel.backgroundColor = UIColor(white: 0.23, alpha: 0.72)
    lockLabel.layer.cornerRadius = 12
    lockLabel.clipsToBounds = true
    lockLabel.isUserInteractionEnabled = false
    addSubview(lockLabel)
    updateAppearance()
  }

  private func setGas(_ isDown: Bool) {
    TCManagerInterface.setButtonStateFor(105, controller: port, state: isDown)
  }

  private func updateAppearance() {
    lockLabel.text = locked ? "🔒" : "→ 🔒"
    lockLabel.layer.borderColor = UIColor.white.cgColor
    lockLabel.layer.borderWidth = locked ? 2 : 0
    oneImage.alpha = locked ? 0.8 : 1.0
  }

  func reset() {
    trackingOne = false
    locked = false
    setGas(false)
    updateAppearance()
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    // The lock region is part of THIS view, not a separate UIButton.
    let x = touch.location(in: self).x
    trackingOne = x < 94
    if !trackingOne {
      locked.toggle() // Also allow an accessible tap to lock/unlock.
      setGas(locked)
    } else {
      // Touching 1 while latched unlatches, but still holds gas until lift.
      locked = false
      setGas(true)
    }
    updateAppearance()
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard trackingOne, !locked, let touch = touches.first else { return }
    if touch.location(in: self).x >= 94 {
      locked = true
      setGas(true)
      updateAppearance()
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
  }

  private func finishTouch() {
    if !locked { setGas(false) }
    trackingOne = false
    updateAppearance()
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouch()
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouch()
  }
}

// Super Mario Bros and the standard sideways remote use the ORIGINAL nib,
// button transforms and finger-tracking code from the first custom build.
// Only Mario Kart gets a custom overlay. Never redraw the SMB controls.
class TCSidewaysWiiPad: TCWiiPad {
  private var preset = 0
  private var overlay: UIView?
  private var gasControl: TCGasLockControl?
  private var lastLayoutSize: CGSize = .zero

  @objc func setPreset(_ value: Int) {
    guard preset != value else { return }
    releaseInputs()
    preset = value
    rebuildOverlay()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if preset == 2, let canvas = real_view, canvas.bounds.size != lastLayoutSize {
      rebuildOverlay()
    }
  }

  private func releaseInputs() {
    gasControl?.reset()
    for key in 100...110 {
      TCManagerInterface.setButtonStateFor(key, controller: port, state: false)
    }
  }

  private func rebuildOverlay() {
    gasControl?.reset()
    gasControl = nil
    overlay?.removeFromSuperview()
    overlay = nil

    guard let canvas = real_view else { return }
    lastLayoutSize = canvas.bounds.size

    // Do not replace or reposition any original control for SMB.
    for view in canvas.subviews {
      view.isHidden = preset == 2
    }
    guard preset == 2 else { return }

    let layer = UIView(frame: canvas.bounds)
    layer.backgroundColor = .clear
    layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    canvas.addSubview(layer)
    overlay = layer
    let w = layer.bounds.width
    let h = layer.bounds.height

    // iOS points, NOT proportional 360x190 units. The old overlay doubled
    // physical button sizes on landscape iPhones.
    func button(_ key: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
      let b = TCButton(frame: CGRect(x: x, y: y, width: width, height: height))
      b.controllerButton = key
      b.port = port
      b.addTarget(b, action: #selector(TCButton.buttonReleased),
                  for: [.touchUpOutside, .touchCancel])
      layer.addSubview(b)
    }

    // Original Mario Kart controls: B moved down, + / - / A directly above.
    // Native images and original sizes, rather than stretched custom images.
    button(101, x: 24, y: h - 94, width: 77, height: 77)  // B
    button(103, x: 24, y: h - 127, width: 26, height: 26) // +
    button(102, x: 53, y: h - 127, width: 26, height: 26) // -
    button(100, x: 83, y: h - 143, width: 43, height: 43) // A

    // Item directional pad is at the far right, ABOVE the accelerator.
    let pad = TCDirectionalPad(frame: CGRect(x: w - 78, y: h - 185,
                                             width: 66, height: 66))
    pad.directionalPadType = 107
    pad.port = port
    layer.addSubview(pad)
    pad.sharedInit() // needs a superview for correct coordinate conversion

    // "1 -> lock" is one continuous view. Swiping RIGHT latches the same
    // Wii 1 input; it cannot hit the B button across the screen.
    let gas = TCGasLockControl(frame: CGRect(x: w - 181, y: h - 108,
                                             width: 169, height: 88))
    gas.port = port
    layer.addSubview(gas)
    gasControl = gas

    // Leave the original HOME icon/position in place, but in the overlay
    // so it remains tappable above the otherwise hidden nib.
    button(104, x: w / 2 - 16, y: h - 32, width: 32, height: 32)
  }
}
