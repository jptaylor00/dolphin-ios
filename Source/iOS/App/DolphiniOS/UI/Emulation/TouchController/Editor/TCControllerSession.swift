// SPDX-License-Identifier: GPL-2.0-or-later
import UIKit

// Geometry capture reuses the original controls. Protected defaults never enter the new renderer.
protocol TCCompositeCapture {
  func captureControls(in canvas:UIView) -> [TCControl]
}
extension TCView {
  static func captureFrame(_ rect:CGRect,in canvas:UIView) -> TCFrame {
    TCFrame(x:Double(rect.midX/max(1,canvas.bounds.width)),y:Double(rect.midY/max(1,canvas.bounds.height)),
            width:Double(rect.width),height:Double(rect.height))
  }
  func captureLayout(_ name:String) -> TCLayout {
    guard let canvas = real_view else { return TCLayout(name:name,controls:[]) }
    canvas.layoutIfNeeded()
    var result: [TCControl] = []
    func walk(_ parent:UIView) {
      for view in parent.subviews where !view.isHidden {
        let rect = view.convert(view.bounds,to:canvas)
        let f = TCView.captureFrame(rect,in:canvas)
        if let composite = view as? TCCompositeCapture { result += composite.captureControls(in:canvas) }
        else if let b = view as? TCButton {
          guard let type = TCButtonType(rawValue:b.controllerButton) else { continue }
          let image = b.image(for:.normal)
          result.append(TCControl(name:TCInputCatalog.names[b.controllerButton] ?? "Button",frame:f,
            inputs:[TCInput(code:b.controllerButton,axis:b.isAxis)],releaseOutside:b.sidewaysSlideEnabled,artwork:type.getImageName(),
            artworkWidth:image.map { Double($0.size.width * abs(b.transform.a)) },
            artworkHeight:image.map { Double($0.size.height * abs(b.transform.d)) }))
        } else if let pad = view as? TCDirectionalPad {
          let codes = pad.sidewaysWiiDPad ? TCInputCatalog.sidewaysDirections : (pad.sidewaysJoystick ? [110,109,107,108].map { TCInput(code:$0) } :
            (pad.directionalPadType...pad.directionalPadType+3).map { TCInput(code:$0) })
          result.append(TCControl(name:"D-pad",kind:.dpad,frame:f,inputs:codes,artwork:pad.sidewaysJoystick ? "gcwii_joystick_range" : "gcwii_dpad"))
        } else if let stick = view as? TCJoystick {
          result.append(TCControl(name:"Stick",kind:.joystick,frame:f,
            inputs:(stick.joystickType+1...stick.joystickType+4).map { TCInput(code:$0,axis:true) },artwork:"gcwii_joystick_range"))
        } else if let b = view as? UIButton {
          let isMode = b.currentTitle == "WHEEL" || b.currentTitle == "STICK"
          if isMode || b.currentTitle == "Center" {
            result.append(TCControl(name:b.currentTitle ?? "",kind:isMode ? .mode : .recenter,frame:f))
          }
        } else { walk(view) }
      }
    }
    walk(canvas)
    // IDs are stable within the captured layout and serialized along with gesture references.
    var layout = TCLayout(name:name,controls:result)
    if let gas = result.first(where: { $0.name == "Wii 2" }), let lock = result.first(where: { $0.kind == .target && $0.name.contains("Lock") }) {
      layout.gestures += [TCGestureRule(source:gas.id,target:lock.id,action:.lock,inputs:gas.inputs),
                         TCGestureRule(source:lock.id,target:gas.id,action:.unlock,inputs:gas.inputs)]
    }
    if self is TCSidewaysWiiPad, editorContext == "Sideways-2", let drift = result.first(where: { $0.name == "Wii B" }), let pad = result.first(where: { $0.kind == .dpad }) {
      // A separate target matches the existing 44x34 item Up hit region.
      var up = TCControl(name:"Item Up",kind:.target,frame:pad.frame,opacity:0.15)
      up.frame.width = 44; up.frame.height = 34
      up.frame.y -= (pad.frame.height/2-17)/Double(max(1,canvas.bounds.height))
      up.inputs = Array(pad.inputs.prefix(1))
      layout.controls.append(up)
      layout.gestures.append(TCGestureRule(source:drift.id,target:up.id,action:.addWhileHolding,inputs:up.inputs))
    }
    if editorContext == "Sideways-0" || editorContext == "Sideways-1" {
      let sliding = result.filter { $0.releaseOutside }
      for source in sliding {
        for target in sliding {
          layout.gestures.append(TCGestureRule(source:source.id,target:target.id,action:.replace,inputs:target.inputs))
        }
      }
    }
    if editorContext == "Sideways-2" {
      let shake = TCControl(name:"Shake",frame:TCFrame(x:0.5,y:0.5,width:64,height:44),inputs:[132,133,134].map { TCInput(code:$0) })
      layout.controls.append(shake)
      if let gas = result.first(where: { $0.name == "Wii 2" }) {
        layout.gestures.append(TCGestureRule(source:gas.id,target:shake.id,action:.pulse,inputs:shake.inputs))
      }
    }
    return layout
  }
  @objc func presentControllerEditor(from presenter:UIViewController,gameID:String) {
    releaseControllerInputs()
    let editor = TCEditorViewController(pad:self,gameID:gameID)
    editor.modalPresentationStyle = .fullScreen
    presenter.present(editor,animated:true)
  }
  func applyCustomPreset(_ preset:TCPreset?,index:Int = 0) {
    releaseControllerInputs()
    if preset != nil && legacyMotionSettings == nil {
      legacyMotionSettings = TCMotionSettings(sensitivity:TCDeviceMotion.shared.marioKartSteeringSensitivity,
        inverted:TCDeviceMotion.shared.marioKartSteeringInverted,phoneShake:TCDeviceMotion.shared.controllerPhoneShakeEnabled)
    }
    customLayoutView?.removeFromSuperview(); customLayoutView = nil
    customPreset = preset
    customLayoutIndex = index
    real_view?.isHidden = preset != nil
    if let preset = preset, preset.layouts.indices.contains(index) {
      let layout = TCLayoutView(layout:preset.layouts[index],port:port)
      layout.frame = bounds
      layout.autoresizingMask = [.flexibleWidth,.flexibleHeight]
      layout.command = { [weak self] kind in
        guard let self = self else { return }
        if kind == .recenter { TCDeviceMotion.shared.recenterMarioKartWheelSteering() }
        if kind == .mode, preset.layouts.count == 2 {
          self.applyCustomPreset(preset,index:1-self.customLayoutIndex)
        }
      }
      customLayoutView = layout; addSubview(layout)
      TCDeviceMotion.shared.marioKartSteeringSensitivity = preset.motion.sensitivity
      TCDeviceMotion.shared.marioKartSteeringInverted = preset.motion.inverted
      TCDeviceMotion.shared.controllerPhoneShakeEnabled = preset.motion.phoneShake
    } else {
      if let previous = legacyMotionSettings {
        TCDeviceMotion.shared.marioKartSteeringSensitivity = previous.sensitivity
        TCDeviceMotion.shared.marioKartSteeringInverted = previous.inverted
        TCDeviceMotion.shared.controllerPhoneShakeEnabled = previous.phoneShake
        legacyMotionSettings = nil
      }
    }
    if self is TCSidewaysWiiPad {
      NotificationCenter.default.post(name:Notification.Name("DOLMarioKartSteeringModeDidChange"),object:self)
    }
  }
}
