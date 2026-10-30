// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

final class TCPresetStore {
  static let shared = TCPresetStore()
  let directory: URL
  init(directory: URL? = nil) {
    self.directory = directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
      .appendingPathComponent("ControllerPresets",isDirectory:true)
  }
  func all() throws -> [TCPreset] {
    guard FileManager.default.fileExists(atPath:directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
      .filter { $0.pathExtension == "json" }.compactMap { url -> TCPreset? in
        // Keep damaged files intact, without hiding the other configurations.
        guard let data = try? Data(contentsOf:url) else { return nil }
        return try? TCPreset.decode(data)
      }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  func list(context: String, gameID: String) throws -> [TCPreset] {
    try all().filter { $0.context == context && ($0.gameID.isEmpty || $0.gameID == gameID) }
  }
  // Built-in sideways layouts and all their user copies share one in-game list.
  // Keep other games' configurations available, prioritizing the running game.
  func configurations(context:String,gameID:String) throws -> [TCPreset] {
    try all().filter { preset in
      if TCPreset.sidewaysIndex(for:context) != nil { return preset.sidewaysIndex != nil }
      return preset.context == context
    }.sorted { lhs,rhs in
      let left = lhs.gameID == gameID || lhs.gameID.isEmpty
      let right = rhs.gameID == gameID || rhs.gameID.isEmpty
      if left != right { return left }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }
  func save(_ preset: TCPreset) throws {
    let data = try preset.encoded()
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try data.write(to:directory.appendingPathComponent(preset.id + ".json"),options:.atomic)
  }
  func duplicate(_ source:TCPreset,name:String,gameID:String) throws -> TCPreset {
    var copy = source
    copy.id = UUID().uuidString
    copy.name = name
    copy.gameID = gameID
    try save(copy)
    return copy
  }
  func delete(_ preset: TCPreset) throws {
    _ = try preset.validated()
    try FileManager.default.removeItem(at:directory.appendingPathComponent(preset.id + ".json"))
  }
  func importPreset(_ data: Data, context: String, gameID: String) throws -> TCPreset {
    var preset = try TCPreset.decode(data)
    guard preset.context == context else { throw TCPresetError.invalid("Choose the matching controller layout before importing this preset") }
    preset.id = UUID().uuidString
    preset.gameID = gameID
    try save(preset)
    return preset
  }
}

extension TCPreset {
  static func sidewaysIndex(for context:String) -> Int? {
    switch context {
    case "Sideways-0": return 0
    case "Sideways-1": return 1
    case "Sideways-2": return 2
    default: return nil
    }
  }
  var sidewaysIndex:Int? { Self.sidewaysIndex(for:context) }
  func configurationTitle(gameID:String) -> String {
    gameID.isEmpty || self.gameID.isEmpty || self.gameID == gameID ? name : "\(name) · \(self.gameID)"
  }
}
