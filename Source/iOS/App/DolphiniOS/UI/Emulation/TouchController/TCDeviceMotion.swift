// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import CoreMotion
import Foundation

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
  private var wheelCenterAngle = 0.0
  private var wheelInvert = false

  @objc func setMarioKartWheelSteering(_ enabled: Bool) {
    wheelLock.lock()
    if enabled && !wheelMode {
      wheelNeedsCenter = true
    }
    wheelMode = enabled
    wheelLock.unlock()
  }

  @objc func recenterMarioKartWheelSteering() {
    wheelLock.lock()
    wheelNeedsCenter = true
    wheelLock.unlock()
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
      
      var x, y: Double
      var z = acceleration.z
      var customWheelAngle: Double? = nil

      self.wheelLock.lock()
      if self.wheelMode {
        // Detect physical rotation of the phone in the screen plane. When the
        // phone is nearly flat this projection is too small to be reliable;
        // use neutral steering until it is held like an upright Wii Wheel.
        let planarGravity = sqrt(acceleration.x * acceleration.x +
                                 acceleration.y * acceleration.y)
        if planarGravity >= 0.22 {
          let phoneAngle = atan2(acceleration.y, acceleration.x)
          if self.wheelNeedsCenter {
            self.wheelCenterAngle = phoneAngle
            self.wheelNeedsCenter = false
          }
          var relativeAngle = phoneAngle - self.wheelCenterAngle
          while relativeAngle > .pi { relativeAngle -= 2 * .pi }
          while relativeAngle < -.pi { relativeAngle += 2 * .pi }
          relativeAngle = min(0.85, max(-0.85, relativeAngle))
          customWheelAngle = relativeAngle * (self.wheelInvert ? -1.0 : 1.0)
        } else {
          customWheelAngle = 0
        }
      }
      self.wheelLock.unlock()

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

      if let angle = customWheelAngle {
        // A Wii Wheel is held sideways with its face toward the player.
        // At neutral, gravity is in the controller's face plane, not the
        // face-up +Z direction. Turning the phone rotates gravity in X/Y,
        // which is how Mario Kart detects steering from an accelerometer.
        // Dolphin's Sideways Wii Remote option handles the 90-degree rotation.
        x = -cos(angle)
        y = sin(angle)
        z = 0
      }
      
      // CMAccelerationData's units are G's
      // Each Wii Remote IMU channel is mapped twice (positive/negative
      // controls), and each pair is subtracted by Dolphin. With the signed
      // input axes this doubles the measured value; compensate ONLY in the
      // Mario Kart synthetic wheel path. Other games retain their inputs.
      let gravity = customWheelAngle == nil ? -9.81 : -9.81 / 2.0
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
    if (self.motionEnabled == mode) {
      return
    }
    
    self.motionEnabled = mode
    
    if (self.motionEnabled) {
      self.registerMotionHandlers()
    } else {
      self.motionManager.stopAccelerometerUpdates()
      self.motionManager.stopGyroUpdates()
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
