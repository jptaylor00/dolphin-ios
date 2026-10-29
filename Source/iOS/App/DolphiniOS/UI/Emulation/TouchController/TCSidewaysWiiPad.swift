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
    func button(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, action: Selector) {
      let b = UIButton(type: .custom)
      b.frame = CGRect(x:x, y:y, width:width, height:height)
      b.setTitle(text, for: .normal)
      b.setTitleColor(.white, for: .normal)
      b.titleLabel?.font = .boldSystemFont(ofSize: min(30, height * 0.45))
      b.backgroundColor = UIColor(white: 0.23, alpha: 0.65)
      b.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
      b.layer.borderWidth = 1
      b.layer.cornerRadius = min(14, height * 0.2)
      b.addTarget(self, action: action, for: .touchDown)
      b.addTarget(self, action: #selector(releaseMomentary(_:)), for: [.touchUpInside,.touchUpOutside,.touchCancel])
      layer.addSubview(b)
    }
    // Controls are positioned relative to the landscape screen.
    if preset == 1 {
      let joy = TCDirectionalPad(frame:CGRect(x:24*unit,y:h-150*unit,width:104*unit,height:104*unit))
      joy.directionalPadType = 107
      joy.sidewaysJoystick = true
      joy.port = port
      joy.sharedInit()
      layer.addSubview(joy)
      button("1",x:w-148*unit,y:h-100*unit,width:65*unit,height:65*unit,action:#selector(pressSMB(_:)))
      button("2",x:w-76*unit,y:h-100*unit,width:65*unit,height:65*unit,action:#selector(pressSMB(_:)))
      (layer.subviews.suffix(2)).enumerated().forEach { i,v in
        if let b = v as? UIButton { b.tag = i == 0 ? 105 : 106 }
      }
      let swipe = UIPanGestureRecognizer(target:self,action:#selector(swipeSMB(_:)))
      layer.addGestureRecognizer(swipe)
      button("−",x:w-112*unit,y:h-142*unit,width:22*unit,height:22*unit,action:#selector(pressMomentary(_:)))
      layer.subviews.last?.tag = 102
      button("+",x:w-81*unit,y:h-142*unit,width:22*unit,height:22*unit,action:#selector(pressMomentary(_:)))
      layer.subviews.last?.tag = 103
      button("A",x:w-50*unit,y:h-142*unit,width:30*unit,height:30*unit,action:#selector(pressMomentary(_:)))
      layer.subviews.last?.tag = 100
    } else if preset == 2 {
      let left = 24*unit
      for (i, label) in ["+","−","A"].enumerated() {
        button(label,x:left+CGFloat(i)*23*unit,y:h-99*unit,width:19*unit,height:20*unit,action:#selector(pressMomentary(_:)))
        layer.subviews.last?.tag = [103,102,100][i]
      }
      button("B",x:left,y:h-75*unit,width:59*unit,height:59*unit,action:#selector(pressMomentary(_:)))
      layer.subviews.last?.tag = 101
      // Small item D-pad, adjacent to the accelerate / lock area.
      let pad = TCDirectionalPad(frame:CGRect(x:w-66*unit,y:h-133*unit,width:55*unit,height:55*unit))
      pad.directionalPadType = 107
      pad.port = port
      pad.sharedInit()
      layer.addSubview(pad)
      let throttle = UIButton(type:.custom)
      throttle.frame = CGRect(x:w-100*unit,y:h-72*unit,width:93*unit,height:58*unit)
      throttle.setTitle("2    →   🔒",for:.normal)
      throttle.backgroundColor = UIColor(white:0.24,alpha:0.7)
      throttle.layer.cornerRadius = 12
      throttle.addTarget(self,action:#selector(gasDown(_:)),for:.touchDown)
      throttle.addTarget(self,action:#selector(gasUp(_:)),for:[.touchUpInside,.touchUpOutside,.touchCancel])
      throttle.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(gasPan(_:))))
      layer.addSubview(throttle)
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
  @objc private func gasDown(_ b:UIButton) {
    if gasLocked {
      gasLocked = false
      gasHeld = false
      TCManagerInterface.setButtonStateFor(106,controller:port,state:false)
    } else {
      gasHeld = true
      TCManagerInterface.setButtonStateFor(106,controller:port,state:true)
    }
  }
  @objc private func gasUp(_ b:UIButton) {
    if !gasLocked {
      gasHeld = false
      TCManagerInterface.setButtonStateFor(106,controller:port,state:false)
    }
  }
  @objc private func gasPan(_ g:UIPanGestureRecognizer) {
    if g.state == .began { gasDown(g.view as! UIButton) }
    if g.state == .changed && g.translation(in:g.view).x > 35 {
      gasLocked = true
      gasHeld = true
      TCManagerInterface.setButtonStateFor(106,controller:port,state:true)
      (g.view as? UIButton)?.setTitle("2    🔒",for:.normal)
    }
    if g.state == .ended || g.state == .cancelled {
      if !gasLocked { gasUp(g.view as! UIButton) }
    }
  }
}
