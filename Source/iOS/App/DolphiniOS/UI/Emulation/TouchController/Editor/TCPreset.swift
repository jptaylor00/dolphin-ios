// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

struct TCFrame: Codable, Equatable {
  // Center as a fraction of the canvas; physical dimensions remain in points.
  var x: Double
  var y: Double
  var width: Double
  var height: Double
  func contains(_ x: Double, _ y: Double, canvasWidth: Double, canvasHeight: Double) -> Bool {
    abs(x - self.x * canvasWidth) <= width / 2 && abs(y - self.y * canvasHeight) <= height / 2
  }
}
struct TCInput: Codable, Hashable {
  var code: Int
  var axis: Bool = false
}
enum TCControlKind: String, Codable { case button, pulse, dpad, joystick, wheelJoystick, target, mode, recenter }
struct TCControl: Codable, Equatable {
  var id: String = UUID().uuidString
  var name: String
  var kind: TCControlKind = .button
  var frame: TCFrame
  var inputs: [TCInput] = []
  var opacity: Double = 1
  var haptic: Bool = true
  var tapOnly: Bool = false
  var releaseOutside: Bool = false
  var artwork: String? = nil
  var artworkWidth: Double? = nil
  var artworkHeight: Double? = nil
}
enum TCGestureAction: String, Codable, CaseIterable {
  case addWhileHolding, replace, lock, unlock, pulse, tap
}
struct TCGestureRule: Codable, Equatable {
  var id: String = UUID().uuidString
  var source: String
  var target: String
  var action: TCGestureAction
  var inputs: [TCInput]
  var haptic: Bool = true
}
struct TCLayout: Codable, Equatable {
  var name: String
  var controls: [TCControl]
  var gestures: [TCGestureRule] = []
}
struct TCMotionSettings: Codable, Equatable {
  var sensitivity: Double = 1
  var inverted: Bool = true
  var phoneShake: Bool = true
}
struct TCPreset: Codable, Equatable {
  static let currentVersion = 1
  var version: Int = currentVersion
  var id: String = UUID().uuidString
  var name: String
  var context: String
  var gameID: String = ""
  var layouts: [TCLayout]
  var motion = TCMotionSettings()

  func validated() throws -> TCPreset {
    guard version == Self.currentVersion else { throw TCPresetError.invalid("Unsupported preset version \(version)") }
    guard UUID(uuidString: id) != nil, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          name.count <= 100, gameID.count <= 64, context.count <= 100,
          (1...2).contains(layouts.count), motion.sensitivity.isFinite,
          (0.4...2.5).contains(motion.sensitivity) else { throw TCPresetError.invalid("Invalid preset metadata") }
    for layout in layouts {
      let ids = Set(layout.controls.map { $0.id })
      guard ids.count == layout.controls.count, layout.controls.count <= 80, layout.gestures.count <= 160 else {
        throw TCPresetError.invalid("Too many or duplicate controls")
      }
      for c in layout.controls {
        let f = c.frame
        guard !c.id.isEmpty, c.id.count <= 100, c.name.count <= 100,
          [f.x, f.y, f.width, f.height, c.opacity].allSatisfy({ $0.isFinite }),
          (0...1).contains(f.x), (0...1).contains(f.y), (16...600).contains(f.width),
          (16...600).contains(f.height), (0.05...1).contains(c.opacity),
          c.inputs.allSatisfy(TCInputCatalog.supports),
          c.kind != .dpad || c.inputs.count == 4,
          c.kind != .joystick || (c.inputs.count == 4 && c.inputs.allSatisfy({ $0.axis })),
          c.artworkWidth.map({ $0.isFinite && (1...1000).contains($0) }) ?? true,
          c.artworkHeight.map({ $0.isFinite && (1...1000).contains($0) }) ?? true else {
          throw TCPresetError.invalid("Invalid control: \(c.name)")
        }
      }
      for r in layout.gestures {
        guard ids.contains(r.source), ids.contains(r.target), r.inputs.allSatisfy(TCInputCatalog.supports),
              !r.inputs.isEmpty else { throw TCPresetError.invalid("Invalid gesture references or inputs") }
      }
    }
    return self
  }
  static func decode(_ data: Data) throws -> TCPreset {
    guard data.count <= 1_048_576 else { throw TCPresetError.invalid("Preset exceeds 1 MB") }
    // Version 1 is the first public format. Unknown versions are rejected, never silently rewritten.
    return try JSONDecoder().decode(Self.self, from: data).validated()
  }
  func encoded() throws -> Data {
    _ = try validated()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
enum TCPresetError: LocalizedError {
  case invalid(String)
  var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
struct TCInputChoice {
  var name: String
  var inputs: [TCInput]
  var kind: TCControlKind = .button
}
enum TCInputCatalog {
  static let buttonCodes: [Int] = {
    var codes = Array(0...9)
    codes += Array(100...110)
    codes += [132,133,134,200,201]
    codes += Array(300...312)
    return codes
  }()
  static let axisCodes: [Int] = {
    var codes = [20,21,323,324]
    for range in [11...14,16...19,112...117,120...125,127...130,203...206,314...317,319...322] {
      codes.append(contentsOf:range)
    }
    return codes
  }()
  static func supports(_ input: TCInput) -> Bool { (input.axis ? axisCodes : buttonCodes).contains(input.code) }
  static let names: [Int: String] = [0:"GC A",1:"GC B",2:"GC Start",3:"GC X",4:"GC Y",5:"GC Z",6:"GC Up",7:"GC Down",8:"GC Left",9:"GC Right",20:"GC L",21:"GC R",100:"Wii A",101:"Wii B",102:"Wii −",103:"Wii +",104:"Wii Home",105:"Wii 1",106:"Wii 2",107:"Wii raw Up",108:"Wii raw Down",109:"Wii raw Left",110:"Wii raw Right",132:"Shake X",133:"Shake Y",134:"Shake Z",200:"Nunchuk C",201:"Nunchuk Z",300:"Classic A",301:"Classic B",302:"Classic X",303:"Classic Y",304:"Classic −",305:"Classic +",306:"Classic Home",307:"Classic ZL",308:"Classic ZR",309:"Classic Up",310:"Classic Down",311:"Classic Left",312:"Classic Right",323:"Classic L",324:"Classic R"]
  static var choices: [TCInputChoice] {
    var result = (buttonCodes + [20,21,323,324]).map { TCInputChoice(name: names[$0] ?? "Input \($0)", inputs: [TCInput(code: $0, axis:[20,21,323,324].contains($0))]) }
    result += [TCInputChoice(name:"Shake", inputs:[132,133,134].map { TCInput(code:$0) },kind:.pulse)]
    for (name, base) in [("GC D-pad",6),("Wii D-pad (upright)",107),("Classic D-pad",309)] {
      result.append(TCInputChoice(name:name, inputs:(base...base+3).map { TCInput(code:$0) }, kind:.dpad))
    }
    result.append(TCInputChoice(name:"Mario Kart D-pad (latest layout)", inputs:sidewaysDirections, kind:.dpad))
    for (name, base) in [("GC Main stick",10),("GC C stick",15),("Nunchuk stick",202),("Classic Left stick",313),("Classic Right stick",318)] {
      result.append(TCInputChoice(name:name, inputs:(base+1...base+4).map { TCInput(code:$0,axis:true) }, kind:.joystick))
    }
    result += [TCInputChoice(name:"Wheel steering stick",inputs:[],kind:.wheelJoystick), TCInputChoice(name:"Gesture target / Lock",inputs:[],kind:.target),TCInputChoice(name:"Wheel / Stick",inputs:[],kind:.mode),TCInputChoice(name:"Center",inputs:[],kind:.recenter)]
    return result
  }
  // Preserve the direct visible-direction mapping from fix/mario-kart-dpad-ccw.
  // Serialized user mappings remain explicit and are not rewritten on load.
  static let sidewaysDirections = [107,108,109,110].map { TCInput(code:$0) }
  static func kartTilt(_ value:Float) -> (left:Float,right:Float) {
    let clamped = max(-1,min(1,value))
    return (min(0,clamped),max(0,clamped))
  }
}
