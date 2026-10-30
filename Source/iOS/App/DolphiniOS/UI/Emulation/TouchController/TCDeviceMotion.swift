// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import CoreMotion
import Foundation
import UIKit
private extension Float {
  func clamped(to range: ClosedRange<Float>) -> Float {
    min(range.upperBound, max(range.lowerBound, self))
  }
}

@objc public class TCDeviceMotion: NSObject {
  @objc public static let shared = TCDeviceMotion()
  
  private let motionManager = CMMotionManager()
  private let operationQueue = OperationQueue()
  
  private var orientation: UIInterfaceOrientation = .portrait
  private var motionEnabled = false
  private var port = 0

  // Mario Kart Wii's Wii Wheel uses tilt, not the D-pad, for steering.
  // Use relative phone rotation around the screen normal so a phone held
  // upright does not constantly steer due to its absolute gravity vector.
  private let wheelLock = NSLock()
  private var wheelMode = false
  private var wheelNeedsCenter = true
  private var wheelReferenceQuaternion: CMQuaternion?
  private var wheelLastSampleAt: TimeInterval = 0
  private var wheelSteeringDegrees = 0.0
  private var wheelRecoveryTimer: Timer?
  private var wheelInvert = true
  private var wheelSensitivity = 1.0
  private var joystickActive = false
  private var phoneShakeEnabled = true
  @objc var controllerPhoneShakeEnabled: Bool {
    get { wheelLock.lock(); defer { wheelLock.unlock() }; return phoneShakeEnabled }
    set { wheelLock.lock(); phoneShakeEnabled = newValue; wheelLock.unlock() }
  }
  // Detect a short physical shake from the phone's acceleration magnitude.
  // A per-shake pulse is sent to Dolphin, not a continuously held button.
  private var lastPhoneShakeAt: TimeInterval = 0
  private var phoneShakeReleaseWork: DispatchWorkItem?
  private let phoneShakeThreshold = 2.25 // G, removes constant gravity and steering
  private let phoneShakeCooldown = 0.6

  @objc func cancelControllerShake() { clearPhoneShake() }

  private func clearPhoneShake() {
    phoneShakeReleaseWork?.cancel()
    phoneShakeReleaseWork = nil
    for key in [TCButtonType.wiiShakeX, .wiiShakeY, .wiiShakeZ] {
      TCInputRouter.set(port:port,source:"phone-shake",input:TCInput(code:key.rawValue),value:0)
    }
  }

  private func sendPhoneShakeIfNeeded(_ acceleration: CMAcceleration) {
    wheelLock.lock()
    let active = (wheelMode || joystickActive) && phoneShakeEnabled
    if !active { wheelLock.unlock(); return }
    // Gravity gives ~1G at rest. A genuine shake has short higher-G peaks.
    let g = sqrt(acceleration.x * acceleration.x +
                 acceleration.y * acceleration.y + acceleration.z * acceleration.z)
    let now = Date().timeIntervalSince1970
    let trigger = g > phoneShakeThreshold && now - lastPhoneShakeAt >= phoneShakeCooldown
    if trigger { lastPhoneShakeAt = now }
    wheelLock.unlock()
    guard trigger else { return }
    DispatchQueue.main.async {
      self.wheelLock.lock()
      let stillActive = (self.wheelMode || self.joystickActive) && self.phoneShakeEnabled
      self.wheelLock.unlock()
      guard stillActive, self.motionEnabled, UIApplication.shared.applicationState == .active else { return }
      self.clearPhoneShake()
      for key in [TCButtonType.wiiShakeX, .wiiShakeY, .wiiShakeZ] {
        TCInputRouter.set(port:self.port,source:"phone-shake",input:TCInput(code:key.rawValue),value:1)
      }
      let release = DispatchWorkItem { [weak self] in self?.clearPhoneShake() }
      self.phoneShakeReleaseWork = release
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: release)
    }
  }
  @objc var marioKartSteeringSensitivity: Double {
    get { wheelLock.lock(); defer { wheelLock.unlock() }; return wheelSensitivity }
    set { wheelLock.lock(); wheelSensitivity = max(0.4, min(2.5, newValue)); wheelLock.unlock() }
  }
  @objc func setMarioKartJoystickMode(_ active: Bool) {
    wheelLock.lock()
    joystickActive = active
    if active { setWheelTilt(0) }
    wheelLock.unlock()
  }
  @objc func setMarioKartJoystickValue(_ value: Float) {
    wheelLock.lock()
    if joystickActive { setWheelTilt(max(-0.5, min(0.5, value * 0.5))) }
    wheelLock.unlock()
  }

  // A Wii Wheel is turned around the phone's screen normal, so use
  // Core Motion's fused quaternion instead of accelerometer X/Y gravity.
  // This also works when the phone is nearly flat.
  private func setWheelTilt(_ value: Float) {
    TCManagerInterface.setAxisValueFor(
      TCButtonType.wiiTiltLeft.rawValue, controller: port, value: value)
    TCManagerInterface.setAxisValueFor(
      TCButtonType.wiiTiltRight.rawValue, controller: port, value: value)
  }

  private func startWheelAttitudeUpdatesIfNeeded() {
    guard motionEnabled, motionManager.isDeviceMotionAvailable,
          !motionManager.isDeviceMotionActive else { return }
    wheelLock.lock()
    let active = wheelMode
    wheelLock.unlock()
    guard active else { return }
    motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
    motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical,
      to: operationQueue) { [weak self] sample, error in
      guard let self = self, let sample = sample, error == nil else { return }
      let q = sample.attitude.quaternion
      self.wheelLock.lock()
      guard self.wheelMode else {
        self.wheelLock.unlock()
        return
      }
      if self.wheelNeedsCenter || self.wheelReferenceQuaternion == nil {
        self.wheelReferenceQuaternion = q
        self.wheelNeedsCenter = false
      }
      let r = self.wheelReferenceQuaternion!
      // Inverse(reference) * current, in local device coordinates.
      // Keep the local Z twist; global yaw depends on phone position.
      let qw = r.w*q.w + r.x*q.x + r.y*q.y + r.z*q.z
      let qz = r.w*q.z - r.x*q.y + r.y*q.x - r.z*q.w
      var angle = 2.0 * atan2(qz, qw)
      if angle > .pi { angle -= 2.0 * .pi }
      if angle < -.pi { angle += 2.0 * .pi }
      angle = max(-0.85, min(0.85, angle))
      if self.wheelInvert { angle = -angle }
      self.wheelSteeringDegrees = angle * 180.0 / .pi
      self.wheelLastSampleAt = Date().timeIntervalSince1970
      // Axis pairs are complementary: ±0.5 maps to Dolphin Tilt x ±1.
      if !self.joystickActive {
        self.setWheelTilt(Float(angle / 0.85 * self.wheelSensitivity).clamped(to: -1...1) * 0.5)
      }
      self.wheelLock.unlock()
    }
  }

  @objc private func checkWheelAttitudeStream() {
    wheelLock.lock()
    let active = wheelMode
    let lastTime = wheelLastSampleAt
    wheelLock.unlock()
    guard active, motionEnabled, UIApplication.shared.applicationState == .active
      else { return }
    if !motionManager.isDeviceMotionActive ||
       (lastTime > 0 && Date().timeIntervalSince1970 - lastTime > 2.0) {
      motionManager.stopDeviceMotionUpdates()
      wheelLock.lock()
      wheelNeedsCenter = true
      wheelReferenceQuaternion = nil
      wheelLastSampleAt = 0
      setWheelTilt(0)
      wheelLock.unlock()
      startWheelAttitudeUpdatesIfNeeded()
    }
  }

  @objc func setMarioKartWheelSteering(_ enabled: Bool) {
    wheelLock.lock()
    if enabled && !wheelMode {
      wheelNeedsCenter = true
      wheelReferenceQuaternion = nil
      wheelLastSampleAt = 0
    }
    wheelMode = enabled
    if !enabled {
      wheelReferenceQuaternion = nil
      wheelSteeringDegrees = 0
      setWheelTilt(0)
    }
    wheelLock.unlock()
    if enabled {
      startWheelAttitudeUpdatesIfNeeded()
      if wheelRecoveryTimer == nil {
        wheelRecoveryTimer = Timer.scheduledTimer(timeInterval: 1.0,
          target: self, selector: #selector(checkWheelAttitudeStream),
          userInfo: nil, repeats: true)
        RunLoop.main.add(wheelRecoveryTimer!, forMode: .common)
      }
    } else {
      wheelRecoveryTimer?.invalidate()
      wheelRecoveryTimer = nil
      motionManager.stopDeviceMotionUpdates()
    }
  }

  @objc func recenterMarioKartWheelSteering() {
    wheelLock.lock()
    wheelNeedsCenter = true
    wheelReferenceQuaternion = nil
    wheelLock.unlock()
  }

  @objc var marioKartSteeringDebugInfo: String {
    wheelLock.lock()
    let enabled = wheelMode
    let centered = !wheelNeedsCenter
    let degrees = wheelSteeringDegrees
    let last = wheelLastSampleAt
    wheelLock.unlock()
    let age = last == 0 ? "No updates yet" :
      String(format: "Last update %.1f sec ago",
             Date().timeIntervalSince1970 - last)
    return """
    Mode: \(enabled ? "Mario Kart active" : "inactive")
    Motion available: \(motionManager.isDeviceMotionAvailable)
    Motion running: \(motionManager.isDeviceMotionActive)
    Calibrated: \(centered)
    Wheel angle: \(String(format: "%.1f", degrees)) degrees
    \(age)
    """
  }

  @objc var marioKartSteeringInverted: Bool {
    get {
      wheelLock.lock()
      defer { wheelLock.unlock() }
      return wheelInvert
    }
    set {
      wheelLock.lock()
      wheelInvert = newValue
      wheelLock.unlock()
    }
  }
  
  override required init() {
    //
  }
  
  @objc func registerMotionHandlers() {
    // Set our orientation properly
    self.statusBarOrientationChanged()
    
    // Set the sensor update times
    // 200Hz is the Wiimote update interval
    let updateInterval: Double = 1.0 / 200.0
    self.motionManager.accelerometerUpdateInterval = updateInterval
    self.motionManager.gyroUpdateInterval = updateInterval
    
    // Register the handlers
    self.motionManager.startAccelerometerUpdates(to: operationQueue) { (data, error) in
      if (error != nil) {
        return
      }
      
      // Get the data
      let acceleration = data!.acceleration
      self.sendPhoneShakeIfNeeded(acceleration)
      
      var x, y: Double
      var z = acceleration.z
      switch (self.orientation) {
      case .portrait, .unknown:
        x = -acceleration.x
        y = -acceleration.y
      case .landscapeRight:
        x = acceleration.y
        y = -acceleration.x
      case .portraitUpsideDown:
        x = acceleration.x
        y = acceleration.y
      case .landscapeLeft:
        x = -acceleration.y
        y = acceleration.x
      @unknown default:
        return
      }

      // Leave original phone-to-Wii motion processing untouched for all games.
      let gravity = -9.81
      x *= gravity
      y *= gravity
      z *= gravity
      
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelLeft.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelRight.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelForward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelBackward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelUp.rawValue, controller: self.port, value: Float(z))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiAccelDown.rawValue, controller: self.port, value: Float(z))
      
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelLeft.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelRight.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelForward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelBackward.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelUp.rawValue, controller: self.port, value: Float(z))
      TCManagerInterface.setAxisValueFor(TCButtonType.nunchukAccelDown.rawValue, controller: self.port, value: Float(z))
    }
    
    self.motionManager.startGyroUpdates(to: operationQueue) { (data, error) in
      if (error != nil) {
        return
      }
      
      // Get the data
      let rotation_rate = data!.rotationRate
      
      var x, y: Double
      var z = rotation_rate.z

      self.wheelLock.lock()
      let wheelActive = self.wheelMode
      self.wheelLock.unlock()
      
      switch (self.orientation) {
      case .portrait, .unknown:
        x = -rotation_rate.x
        y = -rotation_rate.y
      case .landscapeRight:
        x = rotation_rate.y
        y = -rotation_rate.x
      case .portraitUpsideDown:
        x = rotation_rate.x
        y = rotation_rate.y
      case .landscapeLeft:
        x = -rotation_rate.y
        y = rotation_rate.x
      @unknown default:
        return
      }

      // Relative steering is driven by calibrated gravity, not a second,
      // independently rotated gyro stream (which also drifted the pointer).
      if wheelActive {
        x = 0
        y = 0
        z = 0
      }
      
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroPitchUp.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroPitchDown.rawValue, controller: self.port, value: Float(x))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroRollLeft.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroRollRight.rawValue, controller: self.port, value: Float(y))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroYawLeft.rawValue, controller: self.port, value: Float(z))
      TCManagerInterface.setAxisValueFor(TCButtonType.wiiGyroYawRight.rawValue, controller: self.port, value: Float(z))
    }
  }
  
  @objc func setMotionEnabled(_ mode: Bool) {
    if self.motionEnabled == mode {
      if mode { startWheelAttitudeUpdatesIfNeeded() }
      return
    }
    self.motionEnabled = mode
    if mode {
      self.registerMotionHandlers()
      startWheelAttitudeUpdatesIfNeeded()
    } else {
      self.motionManager.stopAccelerometerUpdates()
      self.motionManager.stopGyroUpdates()
      self.motionManager.stopDeviceMotionUpdates()
      DispatchQueue.main.async { self.clearPhoneShake() }
      wheelLock.lock()
      setWheelTilt(0)
      wheelLock.unlock()
    }
  }
  
  @objc func setPort(_ port: Int) {
    self.port = port
  }
  
  // UIApplicationDidChangeStatusBarOrientationNotification is deprecated...
  @objc func statusBarOrientationChanged() {
    self.orientation = UIApplication.shared.statusBarOrientation
  }
}

