// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

final class TCPresetStore {
  static let shared = TCPresetStore()
  let directory: URL
  init(directory: URL? = nil) {
    self.directory = directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
      .appendingPathComponent("ControllerPresets",isDirectory:true)
  }
  func list(context: String, gameID: String) throws -> [TCPreset] {
    guard FileManager.default.fileExists(atPath:directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
      .filter { $0.pathExtension == "json" }.compactMap { url in
        // One damaged file must not hide the remaining user presets. Never overwrite it.
        guard let data = try? Data(contentsOf:url), let p = try? TCPreset.decode(data),
              p.context == context, p.gameID.isEmpty || p.gameID == gameID else { return nil }
        return p
      }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  func save(_ preset: TCPreset) throws {
    let data = try preset.encoded()
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try data.write(to:directory.appendingPathComponent(preset.id + ".json"),options:.atomic)
  }
  func delete(_ preset: TCPreset) throws {
    _ = try preset.validated()
    try FileManager.default.removeItem(at:directory.appendingPathComponent(preset.id + ".json"))
  }
  func importPreset(_ data: Data, context: String, gameID: String) throws -> TCPreset {
    var preset = try TCPreset.decode(data)
    guard preset.context == context else { throw TCPresetError.invalid("Choose the matching controller layout before importing this preset") }
    // Import always creates a new user copy, never overwrites an existing ID or default.
    preset.id = UUID().uuidString
    preset.gameID = gameID
    try save(preset)
    return preset
  }
}
