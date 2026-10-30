// Type-checks UIKit integration before the expensive emulator archive.
// This file is never linked into the app; the archive uses the real Objective-C++ bridge.
import Foundation
@objc class TCManagerInterface: NSObject {
  @objc static func setButtonStateFor(_ button:Int,controller:Int,state:Bool) {}
  @objc static func setAxisValueFor(_ axis:Int,controller:Int,value:Float) {}
}
