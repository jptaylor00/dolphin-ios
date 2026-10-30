// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

// No UIKit or emulator dependency: input ownership and gesture transitions are testable on macOS.
final class TCGestureEngine {
  struct Contact {
    var source: String
    var startX: Double
    var startY: Double
    var x: Double
    var y: Double
    var visited = Set<String>()
    var replaced = false
    var additions: [TCInput] = []
  }
  var layout: TCLayout
  var width: Double = 1
  var height: Double = 1
  var output: (TCInput, Float) -> Void = { _,_ in }
  var haptic: () -> Void = {}
  var command: (TCControlKind) -> Void = { _ in }
  private(set) var contacts: [Int: Contact] = [:]
  private(set) var locked: [String: [TCInput]] = [:]
  private var sent: [TCInput: Float] = [:]
  private var pulses: [String: [TCInput]] = [:]
  init(layout: TCLayout) { self.layout = layout }
  private func hit(_ x: Double, _ y: Double) -> TCControl? {
    layout.controls.reversed().first { $0.frame.contains(x,y,canvasWidth:width,canvasHeight:height) }
  }
  func begin(_ id: Int, x: Double, y: Double) {
    guard let control = hit(x,y), contacts[id] == nil else { return }
    // A control has one touch owner; other controls remain independently usable.
    guard !contacts.values.contains(where: { $0.source == control.id }) else { return }
    if control.kind == .mode || control.kind == .recenter { command(control.kind); return }
    contacts[id] = Contact(source:control.id,startX:x,startY:y,x:x,y:y)
    if control.haptic { haptic() }
    publish()
  }
  func move(_ id: Int, x: Double, y: Double) {
    guard var contact = contacts[id] else { return }
    contact.x = x; contact.y = y
    contact.additions = []
    let distance = hypot(x-contact.startX,y-contact.startY)
    for rule in layout.gestures where rule.source == contact.source && rule.action != .tap {
      guard let target = layout.controls.first(where: { $0.id == rule.target }),
            target.frame.contains(x,y,canvasWidth:width,canvasHeight:height), distance >= 18 else { continue }
      let firstVisit = !contact.visited.contains(rule.id)
      switch rule.action {
      case .addWhileHolding: contact.additions += rule.inputs
      case .replace: contact.replaced = true; contact.additions += rule.inputs
      case .lock: if firstVisit { locked[rule.source] = rule.inputs }
      case .unlock:
        if firstVisit {
          let removing = Set(rule.inputs)
          for key in Array(locked.keys) {
            locked[key] = locked[key]?.filter { !removing.contains($0) }
            if locked[key]?.isEmpty == true { locked.removeValue(forKey:key) }
          }
          // Deliberate reverse slide does not immediately re-press the accelerator.
          contact.replaced = true
        }
      case .pulse: if firstVisit { pulses[rule.id] = rule.inputs }
      case .tap: break
      }
      if firstVisit && rule.haptic { haptic() }
      contact.visited.insert(rule.id)
    }
    contacts[id] = contact
    publish()
  }
  func end(_ id: Int, cancelled: Bool = false) {
    guard let contact = contacts.removeValue(forKey:id) else { return }
    if !cancelled && hypot(contact.x-contact.startX,contact.y-contact.startY) < 18 {
      for rule in layout.gestures where rule.source == contact.source && rule.action == .tap {
        pulses[rule.id] = rule.inputs
        if rule.haptic { haptic() }
      }
    }
    if cancelled { locked.removeAll(); pulses.removeAll() }
    publish()
  }
  func expirePulses() { pulses.removeAll(); publish() }
  func reset() { contacts.removeAll(); locked.removeAll(); pulses.removeAll(); publish() }
  private func values(_ c: TCControl, _ t: Contact) -> [(TCInput,Float)] {
    if t.replaced { return [] }
    let dx = t.x-c.frame.x*width, dy = t.y-c.frame.y*height
    switch c.kind {
    case .dpad:
      let vertical = dy < -c.frame.height/6 ? 0 : (dy > c.frame.height/6 ? 1 : -1)
      let horizontal = dx < -c.frame.width/6 ? 2 : (dx > c.frame.width/6 ? 3 : -1)
      return [vertical,horizontal].filter { c.inputs.indices.contains($0) }.map { (c.inputs[$0],1) }
    case .joystick:
      let radius = max(1,min(c.frame.width,c.frame.height)*0.35)
      let distance = hypot(dx,dy)
      guard distance > radius*0.15 else { return [] }
      let factor = max(radius,distance)
      let x = Float(dx/factor), y = Float(dy/factor)
      return zip(c.inputs,[min(y,0),max(y,0),min(x,0),max(x,0)]).map { ($0,$1) }
    case .button, .target: return c.inputs.map { ($0,1) }
    default: return []
    }
  }
  var wheelValue: Float {
    for contact in contacts.values {
      guard let c = layout.controls.first(where: { $0.id == contact.source && $0.kind == .wheelJoystick }) else { continue }
      return Float(max(-1,min(1,(contact.x-c.frame.x*width)/max(1,c.frame.width*0.34))))
    }
    return 0
  }
  private func publish() {
    var next: [TCInput: Float] = [:]
    func merge(_ input: TCInput, _ value: Float) {
      if abs(value) > abs(next[input] ?? 0) { next[input] = value }
    }
    for contact in contacts.values {
      if let c = layout.controls.first(where: { $0.id == contact.source }) {
        for (input,value) in values(c,contact) { merge(input,value) }
      }
      for input in contact.additions { merge(input,1) }
    }
    for inputs in Array(locked.values) + Array(pulses.values) { for input in inputs { merge(input,1) } }
    for input in Set(sent.keys).union(next.keys) {
      let value = next[input] ?? 0
      if value != (sent[input] ?? 0) { output(input,value) }
    }
    sent = next
  }
}
