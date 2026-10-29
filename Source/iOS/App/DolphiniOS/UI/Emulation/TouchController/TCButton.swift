// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

class TCButton: UIButton
{
  let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
  @IBInspectable var controllerButton: Int = 0 // default: GC A button
  {
    didSet
    {
      updateImage()
    }
  }
  
  // Only the SIDEWAYS Wii Remote's 1/2 buttons use cross-button dragging.
  // Upright Wii Remote (including Nunchuk mode) must retain UIKit's native
  // touchDown/touchUpInside events rather than intercepting touchesBegan.
  @IBInspectable var sidewaysSlideEnabled: Bool = false {
    didSet { updateImage() }
  }

  @IBInspectable var isAxis: Bool = false
  
  var port: Int = 0
  var useHapicTouch: Bool = true
  var lastForce: CGFloat = CGFloat.zero
  
  override init(frame: CGRect)
  {
    super.init(frame: frame)
    sharedInit()
  }
  
  required init?(coder: NSCoder)
  {
    super.init(coder: coder)
    sharedInit()
  }
  
  func sharedInit()
  {
    self.setTitle("", for: .normal)
    self.addTarget(self, action: #selector(buttonPressed), for: .touchDown)
    self.addTarget(self, action: #selector(buttonReleased), for: .touchUpInside)
    
    // TODO: Setting for hapic touch analog triggers enabled
    self.useHapicTouch = self.traitCollection.forceTouchCapability == .available
  }
  
  func updateImage()
  {
    let buttonType = TCButtonType(rawValue: controllerButton)!
    
    let buttonImage = getImage(named: buttonType.getImageName(), scale: buttonType.getButtonScale())
    self.setImage(buttonImage, for: .normal)
    
    let buttonPressedImage = getImage(named: buttonType.getImageName() + "_pressed", scale: buttonType.getButtonScale())
    self.setImage(buttonPressedImage, for: .selected)
    // Scale only the sideways SMB buttons. In the upright Nunchuk layout
    // global 2x transforms overlap neighboring buttons and steal touches.
    transform = sidewaysSlideEnabled && (controllerButton == 105 || controllerButton == 106)
      ? CGAffineTransform(scaleX: 2, y: 2) : .identity
  }
  
  func getImage(named: String, scale: CGFloat) -> UIImage
  {
    // In Interface Builder, the default bundle is not Dolphin's, so we must specify
    // the bundle for the image to load correctly
    let image = UIImage(named: named, in: Bundle(for: type(of: self)), compatibleWith: nil)!
    
    // Create a new CGSize with the new scale
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    
    // Render the image into a context
    UIGraphicsBeginImageContext(newSize)
    image.draw(in: CGRect(origin: CGPoint.zero, size: newSize))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    return newImage.withRenderingMode(.alwaysOriginal)
  }
  
  @objc func buttonPressed()
  {
    if (isAxis && useHapicTouch)
    {
      return
    }
    
    hapticGenerator.impactOccurred()
    
    if (isAxis)
    {
      TCManagerInterface.setAxisValueFor(controllerButton, controller: port, value: 1.0)
    }
    else
    {
      TCManagerInterface.setButtonStateFor(controllerButton, controller: port, state: true)
    }
  }
  
  @objc func buttonReleased()
  {
    if (isAxis)
    {
      TCManagerInterface.setAxisValueFor(controllerButton, controller: port, value: 0.0)
    }
    else
    {
      TCManagerInterface.setButtonStateFor(controllerButton, controller: port, state: false)
    }
  }
  

  private var activeSlideButton: TCButton?
  private var isSlideButton: Bool {
    sidewaysSlideEnabled && (controllerButton == 105 || controllerButton == 106)
  }
  private func slideTarget(_ touch: UITouch) -> TCButton? {
    guard let parent = superview else { return nil }
    let location = touch.location(in: parent)
    return parent.subviews.compactMap { $0 as? TCButton }.first {
      ($0.controllerButton == 105 || $0.controllerButton == 106) &&
      $0.port == port && !$0.isHidden && $0.isEnabled && $0.frame.contains(location)
    }
  }
  private func activate(_ next: TCButton?) {
    if activeSlideButton === next { return }
    if let previous = activeSlideButton {
      TCManagerInterface.setButtonStateFor(previous.controllerButton, controller: previous.port, state: false)
      previous.isSelected = false
    }
    activeSlideButton = next
    if let next = next {
      TCManagerInterface.setButtonStateFor(next.controllerButton, controller: next.port, state: true)
      next.isSelected = true
      next.hapticGenerator.impactOccurred()
    }
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    if isSlideButton, let touch = touches.first { activate(slideTarget(touch)) }
    else { super.touchesBegan(touches, with: event) }
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if isSlideButton { activate(nil) }
    else { super.touchesEnded(touches, with: event) }
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    if isSlideButton { activate(nil) }
    else { super.touchesCancelled(touches, with: event) }
  }

  @objc override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
  {
    if isSlideButton, let touch = touches.first {
      activate(slideTarget(touch))
      return
    }

    if (!isAxis || !useHapicTouch)
    {
      return
    }
    
    let touch = touches.first!
    let force = touch.force
    let maxForce = touch.maximumPossibleForce
    let percentage: Float = Float(force / maxForce);
    
    TCManagerInterface.setAxisValueFor(controllerButton, controller: port, value: percentage)
    
    if (self.lastForce != force && force == maxForce)
    {
      hapticGenerator.impactOccurred()
    }
    
    self.lastForce = force;
  }
  
}
