// SPDX-License-Identifier: GPL-2.0-or-later
import UIKit

enum TCInputRouter {
  private static var mixers: [Int:TCInputMixer] = [:]
  static func set(port:Int,source:String,input:TCInput,value:Float) {
    if mixers[port] == nil {
      let mixer = TCInputMixer()
      mixer.output = { input,value in
        if input.axis { TCManagerInterface.setAxisValueFor(input.code,controller:port,value:value) }
        else { TCManagerInterface.setButtonStateFor(input.code,controller:port,state:value != 0) }
      }
      mixers[port] = mixer
    }
    mixers[port]?.set(source:source,input:input,value:value)
  }
}

final class TCLayoutView: UIView {
  let engine: TCGestureEngine
  var command: ((TCControlKind) -> Void)?
  private var touchIDs: [ObjectIdentifier: Int] = [:]
  private var serial = 0
  private var pulseTimer: Timer?
  private var pulseGeneration = 0
  private let port: Int
  private var controls: [String:UIView] = [:]
  init(layout: TCLayout, port: Int) {
    self.engine = TCGestureEngine(layout:layout)
    self.port = port
    super.init(frame:.zero)
    isMultipleTouchEnabled = true
    backgroundColor = .clear
    let source = UUID().uuidString
    engine.output = { input,value in
      TCInputRouter.set(port:port,source:source,input:input,value:value)
    }
    engine.haptic = { UIImpactFeedbackGenerator(style:.medium).impactOccurred() }
    engine.command = { [weak self] kind in self?.command?(kind) }
    for control in layout.controls {
      let view = TCLayoutView.artwork(control)
      view.isUserInteractionEnabled = false
      controls[control.id] = view
      addSubview(view)
    }
    NotificationCenter.default.addObserver(self,selector:#selector(resetInputs),name:UIApplication.willResignActiveNotification,object:nil)
  }
  required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit { NotificationCenter.default.removeObserver(self); pulseTimer?.invalidate() }
  static func artwork(_ c: TCControl) -> UIView {
    let box = UIView(frame:CGRect(x:0,y:0,width:CGFloat(c.frame.width),height:CGFloat(c.frame.height)))
    box.alpha = CGFloat(c.opacity)
    if c.kind == .wheelJoystick {
      box.backgroundColor = UIColor(white:0.3,alpha:0.7)
      box.layer.cornerRadius = CGFloat(c.frame.width)/2
      box.layer.borderWidth = 1.5; box.layer.borderColor = UIColor.white.cgColor
      let thumb = UIView(frame:CGRect(x:0,y:0,width:CGFloat(c.frame.width)*0.43,height:CGFloat(c.frame.height)*0.43))
      thumb.backgroundColor = UIColor(white:0.72,alpha:0.9)
      thumb.layer.cornerRadius = thumb.bounds.width/2
      thumb.tag = 701
      thumb.center = CGPoint(x:CGFloat(c.frame.width)/2,y:CGFloat(c.frame.height)/2)
      box.addSubview(thumb)
    } else if let name = c.artwork, let image = UIImage(named:name,in:Bundle(for:TCView.self),compatibleWith:nil) {
      let iv = UIImageView(image:image)
      iv.contentMode = .scaleAspectFit
      let w = CGFloat(c.artworkWidth ?? c.frame.width), h = CGFloat(c.artworkHeight ?? c.frame.height)
      iv.frame = CGRect(x:(CGFloat(c.frame.width)-w)/2,y:(CGFloat(c.frame.height)-h)/2,width:w,height:h)
      iv.autoresizingMask = [.flexibleLeftMargin,.flexibleRightMargin,.flexibleTopMargin,.flexibleBottomMargin]
      box.addSubview(iv)
    } else {
      box.backgroundColor = UIColor(white:0.23,alpha:0.72)
      box.layer.cornerRadius = 12
      box.layer.borderColor = UIColor.white.cgColor
      box.layer.borderWidth = 1
      let label = UILabel(frame:CGRect(x:0,y:0,width:CGFloat(c.frame.width),height:CGFloat(c.frame.height)))
      label.text = c.name
      label.textAlignment = .center
      label.textColor = .white
      label.font = .systemFont(ofSize:14,weight:.semibold)
      label.numberOfLines = 2
      label.autoresizingMask = [.flexibleWidth,.flexibleHeight]
      box.addSubview(label)
    }
    if c.kind == .joystick {
      let thumb = UIImageView(image:UIImage(named:"gcwii_joystick",in:Bundle(for:TCView.self),compatibleWith:nil))
      thumb.frame.size = CGSize(width:CGFloat(c.frame.width)*0.48,height:CGFloat(c.frame.height)*0.48)
      thumb.center = CGPoint(x:CGFloat(c.frame.width)/2,y:CGFloat(c.frame.height)/2)
      thumb.tag = 701; thumb.contentMode = .scaleAspectFit; box.addSubview(thumb)
    }
    box.bounds.size = CGSize(width:CGFloat(c.frame.width),height:CGFloat(c.frame.height))
    return box
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    engine.width = Double(bounds.width); engine.height = Double(bounds.height)
    for c in engine.layout.controls {
      controls[c.id]?.frame = CGRect(x:CGFloat(c.frame.x)*bounds.width-CGFloat(c.frame.width)/2,
        y:CGFloat(c.frame.y)*bounds.height-CGFloat(c.frame.height)/2,width:CGFloat(c.frame.width),height:CGFloat(c.frame.height))
    }
  }
  @objc func resetInputs() {
    pulseTimer?.invalidate(); pulseTimer = nil
    engine.reset(); touchIDs.removeAll(); refreshFeedback()
    TCDeviceMotion.shared.setMarioKartJoystickValue(0)
  }
  override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { resetInputs() } }
  private func refreshFeedback() {
    for c in engine.layout.controls {
      guard let art = controls[c.id] else { continue }
      let contact = engine.contacts.values.first { $0.source == c.id }
      let locked = engine.locked[c.id] != nil || engine.layout.gestures.contains {
        $0.action == .lock && $0.target == c.id && engine.locked[$0.source] != nil
      }
      if locked {
        art.layer.borderColor = UIColor.systemGreen.cgColor; art.layer.borderWidth = 2
      } else if c.kind != .wheelJoystick {
        art.layer.borderWidth = contact == nil ? 0 : 2
        art.layer.borderColor = UIColor.white.cgColor
      }
      if let thumb = art.viewWithTag(701) {
        let center = CGPoint(x:art.bounds.midX,y:art.bounds.midY)
        let dx = contact.map { CGFloat($0.x-c.frame.x*engine.width) } ?? 0
        let dy = contact.map { CGFloat($0.y-c.frame.y*engine.height) } ?? 0
        let radius = max(1,min(art.bounds.width,art.bounds.height)*0.34)
        let distance = sqrt(dx*dx+dy*dy)
        let factor = distance > radius ? radius/distance : 1
        thumb.center = CGPoint(x:center.x+dx*factor,y:center.y+dy*factor)
      }
    }
  }
  private func update() {
    refreshFeedback()
    TCDeviceMotion.shared.setMarioKartJoystickValue(engine.wheelValue)
    // Pulse lifetime is bounded even if a touch never ends. Do not extend an earlier pulse.
    if engine.pulseGeneration != pulseGeneration {
      pulseGeneration = engine.pulseGeneration
      pulseTimer?.invalidate()
      pulseTimer = Timer.scheduledTimer(withTimeInterval:0.12,repeats:false) { [weak self] _ in
        self?.engine.expirePulses(); self?.pulseTimer = nil
      }
    }
  }
  override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
    for touch in touches {
      serial += 1; touchIDs[ObjectIdentifier(touch)] = serial
      let p = touch.location(in:self)
      engine.begin(serial,x:Double(p.x),y:Double(p.y))
    }
    update()
  }
  override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
    for touch in touches {
      guard let id = touchIDs[ObjectIdentifier(touch)] else { continue }
      let p = touch.location(in:self); engine.move(id,x:Double(p.x),y:Double(p.y))
    }
    update()
  }
  private func finish(_ touches:Set<UITouch>,cancelled:Bool) {
    for touch in touches { if let id = touchIDs.removeValue(forKey:ObjectIdentifier(touch)) { engine.end(id,cancelled:cancelled) } }
    update()
  }
  override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) { finish(touches,cancelled:false) }
  override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) { finish(touches,cancelled:true) }
}
