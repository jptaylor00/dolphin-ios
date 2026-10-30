// Copyright 2026
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

// A single continuous touch surface for Mario Kart's accelerate -> lock slide.
// Neither a separate button nor a pan recognizer can steal the moving finger.
private final class TCGasLockControl: UIView, TCCompositeCapture {
  func captureControls(in canvas:UIView) -> [TCControl] {
    let gasFrame = twoImage.convert(twoImage.bounds,to:canvas)
    let lockFrame = lockLabel.convert(lockLabel.bounds,to:canvas)
    return [TCControl(name:"Wii 2",frame:TCView.captureFrame(gasFrame,in:canvas),inputs:[TCInput(code:106)],artwork:"wiimote_two"),
      TCControl(name:"Lock",kind:.target,frame:TCView.captureFrame(lockFrame,in:canvas))]
  }
  var port: Int = 0
  private var locked = false
  private var trackingTwo = false
  private var unlocking = false
  private let haptics = UIImpactFeedbackGenerator(style: .medium)
  private let twoImage = UIImageView()
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

    twoImage.frame = CGRect(x: 0, y: 2, width: 84, height: 84)
    twoImage.contentMode = .scaleAspectFit
    twoImage.image = UIImage(named: "wiimote_two", in: Bundle(for: TCButton.self), compatibleWith: nil)
    twoImage.isUserInteractionEnabled = false
    addSubview(twoImage)

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
    TCManagerInterface.setButtonStateFor(106, controller: port, state: isDown)
  }

  private func updateAppearance() {
    lockLabel.text = locked ? "🔒" : "→ 🔒"
    lockLabel.layer.borderColor = UIColor.white.cgColor
    lockLabel.layer.borderWidth = locked ? 2 : 0
    twoImage.alpha = locked ? 0.8 : 1.0
  }

  func reset() {
    trackingTwo = false
    unlocking = false
    locked = false
    setGas(false)
    updateAppearance()
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    let x = touch.location(in: self).x
    trackingTwo = x < 94
    unlocking = !trackingTwo && locked
    if trackingTwo {
      haptics.impactOccurred() // Every 2 press, even before slide-to-lock.
      setGas(true)
    }
    // Touching Lock is NOT an unlock; only dragging Lock -> 2 can unlock.
    updateAppearance()
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    let x = touch.location(in: self).x
    if trackingTwo && !locked && x >= 94 {
      locked = true
      setGas(true)
      haptics.impactOccurred()
      updateAppearance()
    } else if unlocking && locked && x < 94 {
      locked = false
      unlocking = false
      setGas(false)
      haptics.impactOccurred()
      updateAppearance()
    }
  }

  private func finishTouch() {
    if !locked { setGas(false) }
    trackingTwo = false
    unlocking = false
    updateAppearance()
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouch()
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishTouch()
  }
}


private final class TCKartSteeringJoystick: UIView, TCCompositeCapture {
  func captureControls(in canvas:UIView) -> [TCControl] {
    [TCControl(name:"Steer",kind:.wheelJoystick,frame:TCView.captureFrame(convert(bounds,to:canvas),in:canvas),artwork:"gcwii_joystick_range")]
  }
  var port: Int = 4
  private let base = UIView()
  private let thumb = UIView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  private func setup() {
    base.frame = bounds
    base.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    base.layer.cornerRadius = bounds.width / 2
    base.backgroundColor = UIColor(white: 0.3, alpha: 0.7)
    base.layer.borderWidth = 1.5
    base.layer.borderColor = UIColor.white.cgColor
    base.isUserInteractionEnabled = false
    addSubview(base)
    thumb.frame = CGRect(x: 0, y: 0, width: bounds.width * 0.43, height: bounds.height * 0.43)
    thumb.center = CGPoint(x: bounds.midX, y: bounds.midY)
    thumb.layer.cornerRadius = thumb.bounds.width / 2
    thumb.backgroundColor = UIColor(white: 0.72, alpha: 0.9)
    thumb.isUserInteractionEnabled = false
    addSubview(thumb)
  }

  private func steer(_ point: CGPoint?) {
    let radius = max(1, bounds.width * 0.34)
    let dx = point.map { $0.x - bounds.midX } ?? 0
    let dy = point.map { $0.y - bounds.midY } ?? 0
    let length = sqrt(dx * dx + dy * dy)
    let factor = length > radius ? radius / length : 1
    thumb.center = CGPoint(x: bounds.midX + dx * factor,
                           y: bounds.midY + dy * factor)
    TCDeviceMotion.shared.setMarioKartJoystickValue(Float(dx * factor / radius))
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    steer(touches.first?.location(in: self))
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    steer(touches.first?.location(in: self))
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { steer(nil) }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { steer(nil) }
}

// Allows one sustained finger from B to the D-pad's up arrow while drifting.
private final class TCKartDriftThrow: UIView, TCCompositeCapture {
  func captureControls(in canvas:UIView) -> [TCControl] {
    [TCControl(name:"Wii B",frame:TCView.captureFrame(convert(bounds,to:canvas),in:canvas),inputs:[TCInput(code:101)],artwork:"wiimote_b",artworkWidth:image.image.map { Double($0.size.width) },artworkHeight:image.image.map { Double($0.size.height) })]
  }
  var port: Int = 4
  var upwardTarget = CGRect.zero
  private var throwing = false
  private let image = UIImageView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    isMultipleTouchEnabled = false
    image.frame = bounds
    image.contentMode = .scaleAspectFit
    image.isUserInteractionEnabled = false
    let type = TCButtonType(rawValue: 101)!
    let scale = type.getButtonScale() * 1.5
    let helper = TCButton(frame: bounds)
    image.image = helper.getImage(named: type.getImageName(), scale: scale)
    addSubview(image)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func end() {
    TCManagerInterface.setButtonStateFor(101, controller: port, state: false)
    TCManagerInterface.setButtonStateFor(109, controller: port, state: false)
    throwing = false
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    end()
    TCManagerInterface.setButtonStateFor(101, controller: port, state: true)
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    let p = touch.location(in: superview)
    let now = upwardTarget.contains(p)
    if now != throwing {
      throwing = now
      // In sideways mode Core maps input 109 to physical UP.
      TCManagerInterface.setButtonStateFor(109, controller: port, state: now)
      if now { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end() }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end() }
}

// Super Mario Bros and the standard sideways remote use the ORIGINAL nib,
// button transforms and finger-tracking code from the first custom build.
// Only Mario Kart gets a custom overlay. Never redraw the SMB controls.
class TCSidewaysWiiPad: TCWiiPad {
  private var preset = 0
  private var joystickMode = false
  @objc var marioKartJoystickMode: Bool {
    guard let custom = customPreset, custom.layouts.indices.contains(customLayoutIndex) else { return joystickMode }
    return custom.layouts[customLayoutIndex].controls.contains { $0.kind == .wheelJoystick }
  }
  @objc var selectedNativePreset:Int { preset }
  override var editorContext: String { "Sideways-\(preset)" }
  override func editorDefaultLayouts() -> [TCLayout] {
    guard preset == 2 else { return super.editorDefaultLayouts() }
    let previous = joystickMode
    releaseInputs()
    joystickMode = false; rebuildOverlay()
    let wheel = captureLayout("Wheel")
    joystickMode = true; rebuildOverlay()
    let stick = captureLayout("Joystick")
    joystickMode = previous; rebuildOverlay()
    return [wheel,stick]
  }
  override func releaseControllerInputs() {
    releaseInputs()
    super.releaseControllerInputs()
  }
  private var overlay: UIView?
  private var gasControl: TCGasLockControl?
  private var lastLayoutSize: CGSize = .zero

  @objc func setPreset(_ value: Int) {
    guard preset != value || customPreset != nil else { return }
    applyCustomPreset(nil,notify:false)
    releaseInputs()
    if value != 2 { joystickMode = false }
    preset = value
    rebuildOverlay()
    NotificationCenter.default.post(name:Notification.Name("DOLMarioKartSteeringModeDidChange"),object:self)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if preset == 2, let canvas = real_view, canvas.bounds.size != lastLayoutSize {
      rebuildOverlay()
    }
  }

  private func releaseInputs() {
    TCDeviceMotion.shared.setMarioKartJoystickValue(0)
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
    if preset != 2 {
      // Keep the original Super Mario Bros 1/2 buttons and their 43pt size.
      // Add an independent shake control without replacing the nib controls.
      let shake = UIButton(type: .system)
      shake.frame = CGRect(x: canvas.bounds.width - 95,
                           y: max(0, canvas.bounds.height - 143),
                           width: 76, height: 32)
      shake.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
      shake.setTitle("SHAKE", for: .normal)
      shake.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
      shake.setTitleColor(.white, for: .normal)
      shake.backgroundColor = UIColor(white: 0.24, alpha: 0.85)
      shake.layer.cornerRadius = 9
      shake.addAction(UIAction { _ in
        TCDeviceMotion.shared.triggerMarioKartShake()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }, for: .touchDown)
      canvas.addSubview(shake)
      overlay = shake
      return
    }

    let layer = UIView(frame: canvas.bounds)
    layer.backgroundColor = .clear
    layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    canvas.addSubview(layer)
    overlay = layer
    let w = layer.bounds.width
    let h = layer.bounds.height

    // iOS points, NOT proportional 360x190 units. The old overlay doubled
    // physical button sizes on landscape iPhones.
    func button(_ key: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, imageScale: CGFloat = 1) {
      let b = TCButton(frame: CGRect(x: x, y: y, width: width, height: height))
      b.controllerButton = key
      b.port = port
      // Enlarging only the frame expands the hit box, not the Wii artwork.
      // Re-render the image at the same 1.5x factor as B's frame.
      if imageScale != 1, let type = TCButtonType(rawValue: key) {
        let scale = type.getButtonScale() * imageScale
        b.setImage(b.getImage(named: type.getImageName(), scale: scale), for: .normal)
        b.setImage(b.getImage(named: type.getImageName() + "_pressed", scale: scale), for: .selected)
      }
      b.addTarget(b, action: #selector(TCButton.buttonReleased),
                  for: [.touchUpOutside, .touchCancel])
      layer.addSubview(b)
    }

    // Mario Kart-only dedicated shake button, independent of physical shaking.
    func shakeButton(x: CGFloat, y: CGFloat) {
      let shake = UIButton(type: .system)
      shake.frame = CGRect(x: x, y: y, width: 76, height: 32)
      shake.setTitle("SHAKE", for: .normal)
      shake.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
      shake.setTitleColor(.white, for: .normal)
      shake.backgroundColor = UIColor(white: 0.24, alpha: 0.85)
      shake.layer.cornerRadius = 9
      shake.addAction(UIAction { _ in
        TCDeviceMotion.shared.triggerMarioKartShake()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }, for: .touchDown)
      layer.addSubview(shake)
    }

    // Keep EVERY existing control at its original physical size in both modes.
    // Wheel mode remains the existing button layout.
    if joystickMode {
      // +, -, A have their original 26/26/43-point sizes in the top-left.
      button(103, x: 18, y: 12, width: 26, height: 26)
      button(102, x: 47, y: 12, width: 26, height: 26)
      button(100, x: 78, y: 4, width: 43, height: 43)
      let stick = TCKartSteeringJoystick(
        frame: CGRect(x: 24, y: h - 132.5, width: 115.5, height: 115.5))
      stick.port = port
      layer.addSubview(stick)
      // Locked gas bar moves ABOVE the left joystick, its size unchanged.
      let gas = TCGasLockControl(frame: CGRect(x: 14, y: h - 238, width: 169, height: 88))
      gas.port = port
      layer.addSubview(gas)
      gasControl = gas

      // B replaces the old 99-point item pad without shrinking B.
      let bFrame = CGRect(x: w - 127.5, y: h - 234.5,
                          width: 115.5, height: 115.5)
      let drift = TCKartDriftThrow(frame: bFrame)
      drift.port = port
      // D-pad keeps its original 99x99 size at old gas-button location.
      let dpadFrame = CGRect(x: w - 111, y: h - 108, width: 99, height: 99)
      drift.upwardTarget = CGRect(x: dpadFrame.midX - 22,
                                 y: dpadFrame.minY, width: 44, height: 34)
      layer.addSubview(drift)
      shakeButton(x: w - 108, y: h - 270)
      let pad = TCDirectionalPad(frame: dpadFrame)
      pad.directionalPadType = 107
      pad.sidewaysWiiDPad = true
      pad.port = port
      layer.addSubview(pad)
      pad.sharedInit()
    } else {
      button(101, x: 24, y: h - 132.5, width: 115.5, height: 115.5, imageScale: 1.5)
      // Move the three small controls to upper-left to clear space above B.
      button(103, x: 18, y: 12, width: 26, height: 26)
      button(102, x: 47, y: 12, width: 26, height: 26)
      button(100, x: 78, y: 4, width: 43, height: 43)
      shakeButton(x: 43, y: h - 174)

      let pad = TCDirectionalPad(frame: CGRect(x: w - 111, y: h - 218,
                                               width: 99, height: 99))
      pad.directionalPadType = 107
      pad.sidewaysWiiDPad = true
      pad.port = port
      layer.addSubview(pad)
      pad.sharedInit()

      let gas = TCGasLockControl(frame: CGRect(x: w - 181, y: h - 108,
                                               width: 169, height: 88))
      gas.port = port
      layer.addSubview(gas)
      gasControl = gas

      // Small in-game recenter button BELOW lock; not a resized existing button.
      let center = UIButton(type: .system)
      center.frame = CGRect(x: w - 85, y: h - 20, width: 70, height: 19)
      center.setTitle("Center", for: .normal)
      center.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
      center.setTitleColor(.white, for: .normal)
      center.backgroundColor = UIColor(white: 0.25, alpha: 0.75)
      center.layer.cornerRadius = 6
      center.addAction(UIAction { _ in
        TCDeviceMotion.shared.recenterMarioKartWheelSteering()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      }, for: .touchUpInside)
      layer.addSubview(center)
    }

    // HOME stays original 32x32; MODE is a small NEW button beside HOME.
    button(104, x: w / 2 - 16, y: h - 32, width: 32, height: 32)
    let mode = UIButton(type: .system)
    mode.frame = CGRect(x: w / 2 + 19, y: h - 26, width: 39, height: 23)
    mode.setTitle(joystickMode ? "WHEEL" : "STICK", for: .normal)
    mode.titleLabel?.font = .systemFont(ofSize: 9, weight: .semibold)
    mode.setTitleColor(.white, for: .normal)
    mode.backgroundColor = UIColor(white: 0.25, alpha: 0.8)
    mode.layer.cornerRadius = 6
    mode.addAction(UIAction { [weak self] _ in
      guard let self = self else { return }
      self.releaseInputs()
      self.joystickMode.toggle()
      self.rebuildOverlay()
      NotificationCenter.default.post(
        name: Notification.Name("DOLMarioKartSteeringModeDidChange"),
        object: self)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }, for: .touchUpInside)
    layer.addSubview(mode)
  }
}



