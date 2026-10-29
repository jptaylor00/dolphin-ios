// Copyright 2026
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import UIKit

// Each preset is an overlay on the stock sideways Wii Remote controller.
// The original controls are restored when preset 0 is selected.
class TCSidewaysWiiPad: TCWiiPad {
  private var preset = 0
  private var overlay: UIView?
  private var gasLocked = false
  private var gasHeld = false
  private var gasTouchStart: CGPoint?
  private var activeSMBButton: Int?
  private var lastLayoutSize: CGSize = .zero

  @objc func setPreset(_ value: Int) {
    if preset == value { return }
    releaseCustomInputs()
    preset = value
    rebuildOverlay()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if real_view?.bounds.size != lastLayoutSize && preset != 0 {
      rebuildOverlay()
    }
  }

  private func releaseCustomInputs() {
    for key in [101,105,106,107,108,109,110] {
      TCManagerInterface.setButtonStateFor(key, controller: port, state: false)
    }
    gasHeld = false
    gasLocked = false
    activeSMBButton = nil
  }

  private func rebuildOverlay() {
    overlay?.removeFromSuperview()
    overlay = nil
    guard let canvas = real_view else { return }
    lastLayoutSize = canvas.bounds.size
    for view in canvas.subviews { view.isHidden = preset != 0 }
    guard preset != 0 else { return }

    let layer = UIView(frame: canvas.bounds)
    layer.backgroundColor = .clear
    layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    canvas.addSubview(layer)
    overlay = layer
    let w = layer.bounds.width
    let h = layer.bounds.height
    let unit = min(w / 360, h / 190)
    // Reuse DolphiniOS's real Wii button images and their stock proportions.
    func button(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, action: Selector) {
      let key: Int
      switch text {
      case "1": key = 105
      case "2": key = 106
      case "B": key = 101
      case "A": key = 100
      case "+": key = 103
      case "−": key = 102
      default: key = 104
      }
      let b = TCButton(frame: CGRect(x:x, y:y, width:width, height:height))
      b.controllerButton = key
      b.port = port
      b.tag = key
      // TCButton installs its own touch actions, so replace them rather than
      // causing duplicate presses and releases.
      b.removeTarget(nil, action:nil, for:.allEvents)
      b.addTarget(self, action: action, for: .touchDown)
      b.addTarget(self, action: #selector(releaseMomentary(_:)),
                  for: [.touchUpInside,.touchUpOutside,.touchCancel])
      if key == 105 || key == 106 {
        let type = TCButtonType(rawValue:key)!
        b.setImage(b.getImage(named:type.getImageName(), scale:type.getButtonScale() * 2), for:.normal)
        b.setImage(b.getImage(named:type.getImageName()+"_pressed", scale:type.getButtonScale() * 2), for:.selected)
      }
      layer.addSubview(b)
    }
    // Controls are positioned relative to the landscape screen.
    if preset == 1 {
      // Recreate the ORIGINAL custom sideways arrangement, not a redesigned UI.
      // 128pt joystick at lower left; original Wii 1/2 artwork doubled at right.
      let joy = TCDirectionalPad(frame:CGRect(x:0,y:h-128*unit,width:128*unit,height:128*unit))
      joy.directionalPadType = 107
      joy.sidewaysJoystick = true
      joy.port = port
      joy.sharedInit()
      layer.addSubview(joy)
      button("1",x:w-170*unit,y:h-103*unit,width:86*unit,height:86*unit,action:#selector(pressSMB(_:)))
      button("2",x:w-87*unit,y:h-103*unit,width:86*unit,height:86*unit,action:#selector(pressSMB(_:)))
      let swipe = UIPanGestureRecognizer(target:self,action:#selector(swipeSMB(_:)))
      swipe.cancelsTouchesInView = false
      layer.addGestureRecognizer(swipe)
      button("−",x:w-54*unit,y:h-167*unit,width:26*unit,height:26*unit,action:#selector(pressMomentary(_:)))
      button("+",x:w-137*unit,y:h-108*unit-54*unit,width:26*unit,height:26*unit,action:#selector(pressMomentary(_:)))
      button("A",x:w-54*unit,y:h-146*unit,width:43*unit,height:43*unit,action:#selector(pressMomentary(_:)))
    } else if preset == 2 {
      // Same original artwork / proportions, rearranged for Mario Kart.
      // B moves into the old joystick area. +, -, A retain stock sizes.
      let left = 24*unit
      button("B",x:left,y:h-94*unit,width:77*unit,height:77*unit,action:#selector(pressMomentary(_:)))
      button("+",x:left,y:h-123*unit,width:26*unit,height:26*unit,action:#selector(pressMomentary(_:)))
      button("−",x:left+29*unit,y:h-123*unit,width:26*unit,height:26*unit,action:#selector(pressMomentary(_:)))
      button("A",x:left+59*unit,y:h-139*unit,width:43*unit,height:43*unit,action:#selector(pressMomentary(_:)))
      // Item D-pad directly above the lock lane, at the far right.
      let pad = TCDirectionalPad(frame:CGRect(x:w-75*unit,y:h-174*unit,width:66*unit,height:66*unit))
      pad.directionalPadType = 107
      pad.port = port
      pad.sharedInit()
      layer.addSubview(pad)
      // Reuse the large right-side button and add a distinct latch target.
      button("1",x:w-151*unit,y:h-103*unit,width:86*unit,height:86*unit,action:#selector(gasDown(_:)))
      let gas = layer.subviews.last as! TCButton
      gas.removeTarget(self, action:#selector(releaseMomentary(_:)), for:[.touchUpInside,.touchUpOutside,.touchCancel])
      gas.addTarget(self,action:#selector(gasUp(_:)),for:[.touchUpInside,.touchUpOutside,.touchCancel])
      let lock = UIButton(type:.system)
      lock.frame = CGRect(x:w-62*unit,y:h-91*unit,width:52*unit,height:62*unit)
      lock.setTitle("→ 🔒",for:.normal)
      lock.setTitleColor(.white,for:.normal)
      lock.backgroundColor = UIColor(white:0.24,alpha:0.65)
      lock.layer.cornerRadius = 10
      lock.addTarget(self,action:#selector(toggleGasLock(_:)),for:.touchUpInside)
      layer.addSubview(lock)
      let pan = UIPanGestureRecognizer(target:self,action:#selector(gasPan(_:)))
      pan.cancelsTouchesInView = false
      gas.addGestureRecognizer(pan)
    }
    button("HOME",x:w/2-17*unit,y:h-23*unit,width:34*unit,height:20*unit,action:#selector(pressMomentary(_:)))
    layer.subviews.last?.tag = 104
  }

  @objc private func pressMomentary(_ b: UIButton) {
    TCManagerInterface.setButtonStateFor(b.tag, controller:port,state:true)
  }
  @objc private func releaseMomentary(_ b: UIButton) {
    if b.tag == 105 || b.tag == 106 {
      TCManagerInterface.setButtonStateFor(b.tag,controller:port,state:false)
      activeSMBButton = nil
    } else if b.tag > 0 {
      TCManagerInterface.setButtonStateFor(b.tag,controller:port,state:false)
    }
  }
  @objc private func pressSMB(_ b:UIButton) { activateSMB(b.tag) }
  private func activateSMB(_ tag:Int?) {
    if activeSMBButton == tag { return }
    if let old = activeSMBButton {
      TCManagerInterface.setButtonStateFor(old,controller:port,state:false)
    }
    activeSMBButton = tag
    if let tag = tag {
      TCManagerInterface.setButtonStateFor(tag,controller:port,state:true)
    }
  }
  @objc private func swipeSMB(_ gesture:UIPanGestureRecognizer) {
    guard let layer = overlay else { return }
    if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
      activateSMB(nil); return
    }
    let p = gesture.location(in:layer)
    let b = layer.subviews.compactMap{$0 as? UIButton}.first{
      ($0.tag == 105 || $0.tag == 106) && $0.frame.contains(p)
    }
    if b != nil { activateSMB(b?.tag) }
  }
  @objc private func toggleGasLock(_ b:UIButton) {
    gasLocked = !gasLocked
    TCManagerInterface.setButtonStateFor(105,controller:port,state:gasLocked)
    b.setTitle(gasLocked ? "🔒" : "→ 🔒",for:.normal)
  }
  @objc private func gasDown(_ b:UIButton) {
    if gasLocked {
      gasLocked = false
      gasHeld = false
      TCManagerInterface.setButtonStateFor(105,controller:port,state:false)
    } else {
      gasHeld = true
      TCManagerInterface.setButtonStateFor(105,controller:port,state:true)
    }
  }
  @objc private func gasUp(_ b:UIButton) {
    if !gasLocked {
      gasHeld = false
      TCManagerInterface.setButtonStateFor(105,controller:port,state:false)
    }
  }
  @objc private func gasPan(_ g:UIPanGestureRecognizer) {
    // Touch-down already activates gas; avoid toggling it twice.
    if g.state == .began && !gasLocked {
      TCManagerInterface.setButtonStateFor(105,controller:port,state:true)
    }
    if g.state == .changed && g.translation(in:g.view).x > 35 {
      gasLocked = true
      gasHeld = true
      TCManagerInterface.setButtonStateFor(105,controller:port,state:true)
      overlay?.subviews.compactMap{$0 as? UIButton}.first(where: {$0.currentTitle == "→ 🔒"})?.setTitle("🔒",for:.normal)
    }
    if g.state == .ended || g.state == .cancelled {
      if !gasLocked { gasUp(g.view as! UIButton) }
    }
  }
}
