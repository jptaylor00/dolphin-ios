// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

class TCDirectionalPad: UIView
{
  let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

  var dpadNoPressed: UIImage? = nil
  var dpadOnePressed: UIImage? = nil
  var dpadTwoPressed: UIImage? = nil
  
  @IBInspectable var directionalPadType: Int = 6 // default: GC D-Pad
  
  @IBInspectable var sidewaysJoystick: Bool = false
  // Only Mario Kart's item D-pad needs sideways mapping. Upright/Nunchuk
  // retains the original unrotated physical controller directions.
  var sidewaysWiiDPad: Bool = false
  private var joystickThumb: UIImageView?
  var port: Int = 0
  var isPressed: Bool = false
  
  override init(frame: CGRect)
  {
    super.init(frame: frame)
  }
  
  required init?(coder: NSCoder)
  {
    super.init(coder: coder)
  }
  
  override func awakeFromNib()
  {
    super.awakeFromNib()
    sharedInit()
  }
  
  func sharedInit()
  {
    if sidewaysJoystick {
      let bg = UIImageView(frame: bounds)
      bg.image = getImage(imageName: "gcwii_joystick_range")
      bg.contentMode = .scaleAspectFit
      addSubview(bg)
      let knob = UIImageView(frame: CGRect(x: 0, y: 0,
                        width: bounds.width * 0.48, height: bounds.height * 0.48))
      knob.image = getImage(imageName: "gcwii_joystick")
      knob.contentMode = .scaleAspectFit
      knob.center = CGPoint(x: bounds.midX, y: bounds.midY)
      addSubview(knob)
      joystickThumb = knob
      addGestureRecognizer(UIPanGestureRecognizer(target: self,
                           action: #selector(handleSidewaysJoystick)))
      return
    }
    // Load image
    dpadNoPressed = getImage(imageName: "gcwii_dpad")
    dpadOnePressed = getImage(imageName: "gcwii_dpad_pressed_one_direction")
    dpadTwoPressed = getImage(imageName: "gcwii_dpad_pressed_two_directions")
    
    // Create the image view
    let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height))
    imageView.image = dpadNoPressed
    imageView.center = self.convert(self.center, from: self.superview)
    imageView.isUserInteractionEnabled = true
      
    let pressHandler = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
    pressHandler.minimumPressDuration = 0
    imageView.addGestureRecognizer(pressHandler)
    
    self.addSubview(imageView)
    
    // Set background color to transparent
    self.backgroundColor = UIColor.clear
  }
  
  func getImage(imageName: String) -> UIImage
  {
    // In Interface Builder, the default bundle is not Dolphin's, so we must specify
    // the bundle for the image to load correctly
    return UIImage(named: imageName, in: Bundle(for: type(of: self)), compatibleWith: nil)!
  }
  
  @objc func handleSidewaysJoystick(_ gesture: UIPanGestureRecognizer) {
    let done = gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let point = done ? center : gesture.location(in: self)
    let dx = point.x - center.x
    let dy = point.y - center.y
    let radius = max(1, min(bounds.width, bounds.height) * 0.35)
    let length = sqrt(dx * dx + dy * dy)
    let scale = length > radius ? radius / length : 1
    joystickThumb?.center = CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    let deadzone = radius * 0.23
    // Dolphin rotates D-pad bits in sideways mode. The previous mapping
    // reversed both axes in Super Mario Bros on the device. Invert its sign,
    // while keeping the sideways rotation (physical layout is unchanged).
    // Wii input order: Up, Down, Left, Right.
    let pressed = [dx < -deadzone, dx > deadzone, dy > deadzone, dy < -deadzone]
    for (i, value) in pressed.enumerated() {
      TCManagerInterface.setButtonStateFor(directionalPadType + i, controller: port, state: value)
    }
  }

  @objc func handleLongPress(gesture: UILongPressGestureRecognizer)
  {
    let imageView = gesture.view as! UIImageView
    let point = gesture.location(in: self)
    var buttonPresses: [Bool] = [ false, false, false, false ]
    
    if (gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed)
    {
      imageView.image = dpadNoPressed
      self.isPressed = false
    }
    else
    {
      if (!self.isPressed)
      {
        hapticGenerator.impactOccurred()
        self.isPressed = true
      }
      
      // Get button boundary
      let buttonBounds = gesture.view!.frame.width / 3
      
      // Up
      if (point.y <= buttonBounds)
      {
        buttonPresses[0] = true;
      }
      else if (point.y >= buttonBounds * 2) // Down
      {
        buttonPresses[1] = true;
      }
      
      // Left
      if (point.x <= buttonBounds)
      {
        buttonPresses[2] = true;
      }
      else if (point.x >= buttonBounds * 2) // Right
      {
        buttonPresses[3] = true;
      }
      
      var rotation: CGFloat = 0
      
      // TODO: is there a better way to structure this?
      // Left and Up
      if (buttonPresses[2] && buttonPresses[0])
      {
        imageView.image = dpadTwoPressed
        rotation = 0
      }
      else if (buttonPresses[0] && buttonPresses[3]) // Up and Right
      {
        imageView.image = dpadTwoPressed
        rotation = 90
      }
      else if (buttonPresses[3] && buttonPresses[1]) // Right and Down
      {
        imageView.image = dpadTwoPressed
        rotation = 180
      }
      else if (buttonPresses[1] && buttonPresses[2]) // Down and Left
      {
        imageView.image = dpadTwoPressed
        rotation = 270
      }
      else if (buttonPresses[0]) // Up
      {
        imageView.image = dpadOnePressed
        rotation = 0
      }
      else if (buttonPresses[1]) // Down
      {
        imageView.image = dpadOnePressed
        rotation = 180
      }
      else if (buttonPresses[2]) // Left
      {
        imageView.image = dpadOnePressed
        rotation = 270
      }
      else if (buttonPresses[3]) // Right
      {
        imageView.image = dpadOnePressed
        rotation = 90
      }
      else
      {
        imageView.image = dpadNoPressed
      }
      
      let radians = rotation * (CGFloat.pi / 180)
      imageView.transform = CGAffineTransform.identity.rotated(by: radians)
    }
    
    // Mario Kart's item D-pad is on a sideways Wii Remote. Translate the
    // onscreen physical directions into Dolphin's rotated Wii input names.
    // Same direction convention as the SMB sideways joystick above.
    // Other D-pads (including the upright/Nunchuk pad) are left untouched.
    let mappedPresses = sidewaysWiiDPad && directionalPadType == 107
      ? [buttonPresses[3], buttonPresses[2], buttonPresses[0], buttonPresses[1]]
      : buttonPresses
    for (i, press) in mappedPresses.enumerated()
    {
      TCManagerInterface.setButtonStateFor(directionalPadType + i, controller: port, state: press)
    }
  }
  
}

