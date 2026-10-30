// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#import "EmulationiOSViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <array>
#include <string>
#include <string_view>

#import "Common/IOFile.h"

#import "Core/ConfigManager.h"
#import "Core/Config/iOSSettings.h"
#import "Core/Config/MainSettings.h"
#import "Core/Config/WiimoteSettings.h"
#import "Core/HW/GCPad.h"
#import "Core/HW/SI/SI_Device.h"
#import "Core/HW/Wiimote.h"
#import "Core/HW/WiimoteEmu/WiimoteEmu.h"
#import "TouchController/TCManagerInterface.h"
#import "Core/IOS/USB/Emulated/Skylanders/Skylander.h"
#import "Core/State.h"
#import "Core/System.h"

#import "InputCommon/InputConfig.h"
#import "InputCommon/ControllerEmu/ControllerEmu.h"
#import "InputCommon/ControllerEmu/Control/Control.h"
#import "InputCommon/ControllerEmu/ControlGroup/Attachments.h"
#import "InputCommon/ControllerEmu/Setting/NumericSetting.h"

#import "VideoCommon/Present.h"

#import "EmulationCoordinator.h"
#import "HostNotifications.h"
#import "HostQueue.h"
#import "LocalizationUtil.h"
#import "VirtualMFiControllerManager.h"

typedef NS_ENUM(NSInteger, DOLEmulationVisibleTouchPad) {
  DOLEmulationVisibleTouchPadNone,
  DOLEmulationVisibleTouchPadGameCube,
  DOLEmulationVisibleTouchPadWiimote,
  DOLEmulationVisibleTouchPadSidewaysWiimote,
  DOLEmulationVisibleTouchPadClassic
};

@interface EmulationiOSViewController ()

@end

@implementation EmulationiOSViewController {
  DOLEmulationVisibleTouchPad _visibleTouchPad;
  int _stateSlot;
  NSInteger _sidewaysPreset;

  // Temporary Mario Kart-only input settings, restored when that preset ends.
  // Do not modify saved mappings or Super Mario Bros controls.
  BOOL _marioKartWheelInputConnected;
  std::array<std::string, 6> _previousMarioKartIMUBindings;
  std::array<std::string, 2> _previousMarioKartTiltBindings;
  unsigned int _previousMarioKartExtension;
  bool _previousMarioKartSidewaysValue;
  std::string _previousMarioKartSidewaysExpression;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];

    if (i + 1 == DOLEmulationVisibleTouchPadGameCube) {
      padView.port = 0;
    } else {
      // Wii pads are mapped to touchscreen device 4
      padView.port = 4;
    }
  }

  if (@available(iOS 15.0, *)) {
    // Stupidity - iOS 15 now uses the scrollEdgeAppearance when the UINavigationBar is off screen.
    // https://developer.apple.com/forums/thread/682420
    UINavigationBar* bar = self.navigationController.navigationBar;
    bar.scrollEdgeAppearance = bar.standardAppearance;

    VirtualMFiControllerManager* virtualMfi = [VirtualMFiControllerManager shared];
    if (virtualMfi.shouldConnectController) {
      [virtualMfi connectControllerToView:self.view];
    }
  }

  _stateSlot = Config::GetBase(Config::MAIN_SELECTED_STATE_SLOT);
  
  // On iPadOS 26, the pull down button in the upper left can be blocked by window controls.
  if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
    self.pullDownLeftConstraint.active = false;
    self.pullDownCenterConstraint.active = true;
  }
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveTitleChangedNotificationiOS) name:DOLHostTitleChangedNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveRequestRenderWindowSizeNotificationiOS) name:DOLHostRequestRenderWindowSizeNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveEmulationEndNotificationiOS) name:DOLEmulationDidEndNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(marioKartModeChanged:) name:@"DOLMarioKartSteeringModeDidChange" object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controllerConfigurationsChanged:) name:@"DOLControllerConfigurationsDidChange" object:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
  for (TCView* pad in self.touchPads) [pad releaseControllerInputs];
  [[TCDeviceMotion shared] setMarioKartJoystickMode:NO];
  [self setMarioKartWheelInputConnected:NO];
  [[TCDeviceMotion shared] setMarioKartWheelSteering:NO];
  [TCManagerInterface setButtonStateFor:118 controller:4 state:NO];
  [super viewDidDisappear:animated];

  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLHostTitleChangedNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLHostRequestRenderWindowSizeNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:DOLEmulationDidEndNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:@"DOLMarioKartSteeringModeDidChange" object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:@"DOLControllerConfigurationsDidChange" object:nil];
}

- (void)controllerConfigurationsChanged:(NSNotification*)notification {
  [self recreateMenu];
}

- (void)marioKartModeChanged:(NSNotification*)notification {
  if ([notification.object isKindOfClass:[TCSidewaysWiiPad class]]) {
    _sidewaysPreset = ((TCSidewaysWiiPad*)notification.object).selectedNativePreset;
  }
  [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadSidewaysWiimote];
  [self recreateMenu];
}

- (void)recreateMenu {
  NSMutableArray<UIMenuElement*>* controllerActions = [[NSMutableArray alloc] init];

  NSMutableArray<UIMenuElement*>* visibleControllerActions = [[NSMutableArray alloc] init];

  bool wiimoteTouchPadAttached = [self isWiimoteTouchPadAttached] && Core::System::GetInstance().IsWii();
  bool gamecubeTouchPadAttached = [self isGameCubeTouchPadAttached];

  if (wiimoteTouchPadAttached) {
    UIAction* wiimoteAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"Wii Remote") image:nil identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadToWii];
      [self recreateMenu];

      [self.navigationController setNavigationBarHidden:true animated:true];
    }];

    if (_visibleTouchPad == DOLEmulationVisibleTouchPadWiimote ||
        _visibleTouchPad == DOLEmulationVisibleTouchPadSidewaysWiimote ||
        _visibleTouchPad == DOLEmulationVisibleTouchPadClassic) {
      wiimoteAction.state = UIMenuElementStateOn;
    } else {
      wiimoteAction.state = UIMenuElementStateOff;
    }

    [visibleControllerActions addObject:wiimoteAction];
  }

  if (wiimoteTouchPadAttached) {
    NSArray<NSString*>* names = @[@"Sideways Wii Remote", @"Super Mario Bros Configuration", @"Mario Kart Configuration"];
    NSMutableArray<UIMenuElement*>* layouts = [NSMutableArray array];
    TCSidewaysWiiPad* sidewaysPad = nil;
    for (TCView* pad in self.touchPads) {
      if ([pad isKindOfClass:[TCSidewaysWiiPad class]]) {
        sidewaysPad = (TCSidewaysWiiPad*)pad;
        break;
      }
    }
    for (NSInteger index = 0; index < names.count; ++index) {
      NSInteger selected = index;
      UIAction* action = [UIAction actionWithTitle:names[index] image:nil identifier:nil handler:^(UIAction*) {
        self->_sidewaysPreset = selected;
        for (TCView* pad in self.touchPads) {
          if ([pad isKindOfClass:[TCSidewaysWiiPad class]]) {
            [(TCSidewaysWiiPad*)pad setPreset:(int)selected];
          }
        }
        [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadSidewaysWiimote];
        [self updatePointerValuesOnWiiTouchPads];
        [self recreateMenu];
        [self.navigationController setNavigationBarHidden:true animated:true];
      }];
      action.state = (_sidewaysPreset == index && sidewaysPad.activeControllerConfigurationID == nil) ? UIMenuElementStateOn : UIMenuElementStateOff;
      [layouts addObject:action];
    }
    if (sidewaysPad) {
      NSString* gameID = [NSString stringWithUTF8String:SConfig::GetInstance().GetGameID().c_str()];
      [layouts addObjectsFromArray:[sidewaysPad controllerConfigurationActionsFrom:self gameID:gameID]];
    }
    [controllerActions addObject:[UIMenu menuWithTitle:@"Sideways Controller Layout" image:nil identifier:nil options:0 children:layouts]];

    if (_sidewaysPreset == 2) {
      UIAction* recenterWheel = [UIAction actionWithTitle:@"Recenter Mario Kart Steering"
        image:[UIImage systemImageNamed:@"scope"] identifier:nil handler:^(UIAction*) {
        [[TCDeviceMotion shared] recenterMarioKartWheelSteering];
      }];
      UIAction* invertWheel = [UIAction actionWithTitle:@"Invert Mario Kart Steering"
        image:nil identifier:nil handler:^(UIAction*) {
        TCDeviceMotion* motion = [TCDeviceMotion shared];
        motion.marioKartSteeringInverted = !motion.marioKartSteeringInverted;
        [motion recenterMarioKartWheelSteering];
        [self recreateMenu];
      }];
      invertWheel.state = [TCDeviceMotion shared].marioKartSteeringInverted
        ? UIMenuElementStateOn : UIMenuElementStateOff;
      UIAction* wheelDiagnostic = [UIAction actionWithTitle:@"Steering Diagnostics"
        image:[UIImage systemImageNamed:@"waveform.path"] identifier:nil handler:^(UIAction*) {
        NSString* info = [TCDeviceMotion shared].marioKartSteeringDebugInfo;
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Mario Kart Steering"
          message:info preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
          style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
      }];
      UIAction* sensitivity = [UIAction actionWithTitle:@"Steering Sensitivity"
        image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil handler:^(UIAction*) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Steering Sensitivity"
          message:@"Adjust wheel response (0.4x – 2.5x)." preferredStyle:UIAlertControllerStyleAlert];
        UISlider* slider = [[UISlider alloc] initWithFrame:CGRectMake(20, 65, 230, 32)];
        slider.minimumValue = 0.4f;
        slider.maximumValue = 2.5f;
        slider.value = [TCDeviceMotion shared].marioKartSteeringSensitivity;
        [slider addAction:[UIAction actionWithHandler:^(UIAction* _) {
          [TCDeviceMotion shared].marioKartSteeringSensitivity = slider.value;
        }] forControlEvents:UIControlEventValueChanged];
        UIViewController* holder = [[UIViewController alloc] init];
        holder.preferredContentSize = CGSizeMake(270, 105);
        [holder.view addSubview:slider];
        [alert setValue:holder forKey:@"contentViewController"];
        [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
      }];
      [controllerActions addObject:[UIMenu menuWithTitle:@"Mario Kart Wheel"
        image:[UIImage systemImageNamed:@"steeringwheel"] identifier:nil options:0
        children:@[recenterWheel, invertWheel, sensitivity, wheelDiagnostic]]];
    }
  }

  if (gamecubeTouchPadAttached) {
    UIAction* gamecubeAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"GameCube Controller") image:nil identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadToGameCube];
      [self recreateMenu];

      [self.navigationController setNavigationBarHidden:true animated:true];
    }];

    if (_visibleTouchPad == DOLEmulationVisibleTouchPadGameCube) {
      gamecubeAction.state = UIMenuElementStateOn;
    } else {
      gamecubeAction.state = UIMenuElementStateOff;
    }

    [visibleControllerActions addObject:gamecubeAction];
  }

  if (wiimoteTouchPadAttached || gamecubeTouchPadAttached) {
    UIAction* noneAction = [UIAction actionWithTitle:DOLCoreLocalizedString(@"Hide") image:nil identifier:nil handler:^(UIAction*) {
      [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadNone];
      [self recreateMenu];

      [self.navigationController setNavigationBarHidden:true animated:true];
    }];

    if (_visibleTouchPad == DOLEmulationVisibleTouchPadNone) {
      noneAction.state = UIMenuElementStateOn;
    } else {
      noneAction.state = UIMenuElementStateOff;
    }

    [visibleControllerActions addObject:noneAction];
  }

  UIMenu* visibleControllerMenu = [UIMenu menuWithTitle:@"Touch Controller" image:[UIImage systemImageNamed:@"gamecontroller"] identifier:nil options:0 children:visibleControllerActions];
  [controllerActions addObject:visibleControllerMenu];

  if (_visibleTouchPad != DOLEmulationVisibleTouchPadNone) {
    NSInteger activeIndex = _visibleTouchPad - 1;
    if (activeIndex >= 0 && activeIndex < self.touchPads.count) {
      TCView* activePad = self.touchPads[activeIndex];
      if (![activePad isKindOfClass:[TCSidewaysWiiPad class]]) {
        NSString* gameID = [NSString stringWithUTF8String:SConfig::GetInstance().GetGameID().c_str()];
        [controllerActions addObject:[UIMenu menuWithTitle:@"Controller Configurations" children:[activePad controllerConfigurationActionsFrom:self gameID:gameID]]];
      }
    }
    [controllerActions addObject:[UIAction actionWithTitle:@"Controller Editor / Presets"
      image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil handler:^(UIAction*) {
      NSInteger index = self->_visibleTouchPad - 1;
      if (index >= 0 && index < self.touchPads.count) {
        TCView* pad = self.touchPads[index];
        NSString* gameID = [NSString stringWithUTF8String:SConfig::GetInstance().GetGameID().c_str()];
        [pad presentControllerEditorFrom:self gameID:gameID];
      }
    }]];
  }

  if (wiimoteTouchPadAttached) {
    TCWiiTouchIRMode irMode = (TCWiiTouchIRMode)Config::Get(Config::MAIN_TOUCH_PAD_IR_MODE);

    UIMenu* menu = [UIMenu menuWithTitle:@"Touch IR Pointer" image:[UIImage systemImageNamed:@"hand.point.up.left"] identifier:nil options:0 children:@[
      [UIAction actionWithTitle:@"Disabled" image:nil identifier:nil handler:^(UIAction*) {
        Config::SetBaseOrCurrent(Config::MAIN_TOUCH_PAD_IR_MODE, TCWiiTouchIRModeNone);

        [self updatePointerValuesOnWiiTouchPads];
        [self recreateMenu];

        [self.navigationController setNavigationBarHidden:true animated:true];
      }],
      [UIAction actionWithTitle:@"Follow" image:nil identifier:nil handler:^(UIAction*) {
        Config::SetBaseOrCurrent(Config::MAIN_TOUCH_PAD_IR_MODE, TCWiiTouchIRModeFollow);

        [self updatePointerValuesOnWiiTouchPads];
        [self recreateMenu];

        [self.navigationController setNavigationBarHidden:true animated:true];
      }],
      [UIAction actionWithTitle:@"Drag" image:nil identifier:nil handler:^(UIAction*) {
        Config::SetBaseOrCurrent(Config::MAIN_TOUCH_PAD_IR_MODE, TCWiiTouchIRModeDrag);

        [self updatePointerValuesOnWiiTouchPads];
        [self recreateMenu];

        [self.navigationController setNavigationBarHidden:true animated:true];
      }]
    ]];

    UIAction* selectedAction = (UIAction*)menu.children[(int)irMode];
    selectedAction.state = UIMenuElementStateOn;

    [controllerActions addObject:menu];
  }

  NSMutableArray<UIMenuElement*>* stateSlotActions = [[NSMutableArray alloc] init];

  for (int i = 1; i <= State::NUM_STATES; i++) {
    [stateSlotActions addObject:[UIAction actionWithTitle:[NSString stringWithFormat:@"Slot %d", i] image:nil identifier:nil handler:^(UIAction* action) {
      self->_stateSlot = i;
      Config::SetBase(Config::MAIN_SELECTED_STATE_SLOT, i);

      [self recreateMenu];
    }]];
  }

  UIAction* selectedSlotElement = (UIAction*)[stateSlotActions objectAtIndex:Config::GetBase(Config::MAIN_SELECTED_STATE_SLOT) - 1];
  selectedSlotElement.state = UIMenuElementStateOn;
  
  NSMutableArray<UIMenuElement*>* menuItems = [[NSMutableArray alloc] init];
  [menuItems addObject:[UIMenu menuWithTitle:DOLCoreLocalizedString(@"Controllers") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:controllerActions]];
  [menuItems addObject:[UIMenu menuWithTitle:DOLCoreLocalizedString(@"Save State") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
    [UIMenu menuWithTitle:DOLCoreLocalizedString(@"Select State Slot") image:nil identifier:nil options:0 children:stateSlotActions],
    [UIAction actionWithTitle:DOLCoreLocalizedString(@"Load State") image:[UIImage systemImageNamed:@"tray.and.arrow.down"] identifier:nil handler:^(UIAction*) {
      DOLHostQueueRunAsync(^{
        State::Load(Core::System::GetInstance(), self->_stateSlot);
      });

      [self.navigationController setNavigationBarHidden:true animated:true];
    }],
    [UIAction actionWithTitle:DOLCoreLocalizedString(@"Save State") image:[UIImage systemImageNamed:@"tray.and.arrow.up"] identifier:nil handler:^(UIAction*) {
      DOLHostQueueRunAsync(^{
        State::Save(Core::System::GetInstance(), self->_stateSlot);
      });

      [self.navigationController setNavigationBarHidden:true animated:true];
    }]
  ]]];
  
  if ([self emulateSkylanderPortal] && Core::System::GetInstance().IsWii()) {
    [menuItems addObject:[UIMenu menuWithTitle:DOLCoreLocalizedString(@"Tools") image:nil identifier:nil options:UIMenuOptionsDisplayInline
                 children:@[
        [UIAction actionWithTitle:DOLCoreLocalizedString(@"Skylanders Portal") image:[UIImage systemImageNamed:@"externalDrive"] identifier:nil handler:^(UIAction*) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Skylanders Manager"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* loadAction = [UIAlertAction actionWithTitle:@"Load" style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction* action) {
            NSArray<UTType*>* types = @[
                [UTType exportedTypeWithIdentifier:@"me.oatmealdome.dolphinios.skylander-dumps"]
              ];
            UIDocumentPickerViewController* pickerController = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types];
            pickerController.delegate = self;
            pickerController.modalPresentationStyle = UIModalPresentationPageSheet;
            pickerController.allowsMultipleSelection = false;

            [self presentViewController:pickerController animated:true completion:nil];

        }];
        UIAlertAction* clearAction = [UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction* action) {
            auto& system = Core::System::GetInstance();
            if (self.skylanderSlot) {
              bool removed = system.GetSkylanderPortal().RemoveSkylander(self.skylanderSlot - 1);
              if (removed && self.skylanderSlot != 0) {
                  self.skylanderSlot--;
              }
            }
        }];
        UIAlertAction* clearAllAction = [UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction* action) {
            auto& system = Core::System::GetInstance();
            if (self.skylanderSlot) {
              for (int i = 0; i < 16; i++) {
                  system.GetSkylanderPortal().RemoveSkylander(i);
              }
            }
            self.skylanderSlot = 0;
        }];
        [alert addAction:loadAction];
        [alert addAction:clearAction];
        [alert addAction:clearAllAction];
        [self presentViewController:alert animated:YES completion:nil];
    }]
    ]]];
  }

  self.navigationItem.leftBarButtonItem.menu = [UIMenu menuWithChildren:menuItems];
}

- (void)viewDidLayoutSubviews {
  if (g_presenter) {
    g_presenter->ResizeSurface();
  }

  [[TCDeviceMotion shared] statusBarOrientationChanged];

  [self updatePointerValuesOnWiiTouchPads];
}

- (BOOL)prefersHomeIndicatorAutoHidden {
  return true;
}

- (void)receiveTitleChangedNotificationiOS {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (Core::System::GetInstance().IsWii()) {
      [self updateVisibleTouchPadToWii];
    } else {
      [self updateVisibleTouchPadToGameCube];
    }

    [self recreateMenu];
  });
}

- (void)receiveRequestRenderWindowSizeNotificationiOS {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (Core::System::GetInstance().IsWii()) {
      [self updatePointerValuesOnWiiTouchPads];
    }
  });
}

- (bool)isWiimoteTouchPadAttached {
  if (Config::Get(Config::GetInfoForWiimoteSource(0)) != WiimoteSource::Emulated) {
    // Nothing is plugged in to this port.
    return false;
  }

  const auto wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(0));

  if (wiimote->GetDefaultDevice().source != "iOS") {
    // A real controller is mapped to this port.
    return false;
  }

  return true;
}

- (bool)emulateSkylanderPortal {
  return Config::Get(Config::MAIN_EMULATE_SKYLANDER_PORTAL);
}

- (bool)isGameCubeTouchPadAttached {
  if (Config::Get(Config::GetInfoForSIDevice(0)) == SerialInterface::SIDEVICE_NONE) {
    // Nothing is plugged in to this port.
    return false;
  }

  const auto device = Pad::GetConfig()->GetController(0);

  if (device->GetDefaultDevice().source != "iOS") {
    // A real controller is mapped to this port.
    return false;
  }

  return true;
}

- (void)updateVisibleTouchPadToWii {
  if (![self isWiimoteTouchPadAttached]) {
    // Fallback to GameCube in case port 1 is bound to the touchscreen.
    [self updateVisibleTouchPadToGameCube];

    return;
  }

  DOLEmulationVisibleTouchPad targetTouchPad;

  const auto wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(0));

  if (wiimote->GetActiveExtensionNumber() == WiimoteEmu::ExtensionNumber::CLASSIC) {
    targetTouchPad = DOLEmulationVisibleTouchPadClassic;
  } else if (wiimote->IsSideways()) {
    targetTouchPad = DOLEmulationVisibleTouchPadSidewaysWiimote;
  } else {
    targetTouchPad = DOLEmulationVisibleTouchPadWiimote;
  }

  [self updateVisibleTouchPadWithType:targetTouchPad];

  [self updatePointerValuesOnWiiTouchPads];
}

- (void)updateVisibleTouchPadToGameCube {
  if (![self isGameCubeTouchPadAttached]) {
    return;
  }

  [self updateVisibleTouchPadWithType:DOLEmulationVisibleTouchPadGameCube];
}

// Bind only the Mario Kart Wii Wheel controls. Do not modify the saved
// Wiimote configuration or the Super Mario Bros controller inputs.
// Restore both the player's previous Nunchuk choice and IMU mappings on exit.
- (void)setMarioKartWheelInputConnected:(BOOL)enabled {
  if (_marioKartWheelInputConnected == enabled)
    return;

  if (![self isWiimoteTouchPadAttached])
    return;

  auto* wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(0));
  auto* imu = wiimote->GetWiimoteGroup(WiimoteEmu::WiimoteGroup::IMUAccelerometer);
  auto* tilt = wiimote->GetWiimoteGroup(WiimoteEmu::WiimoteGroup::Tilt);
  auto* options = wiimote->GetWiimoteGroup(WiimoteEmu::WiimoteGroup::Options);
  auto* attachments = static_cast<ControllerEmu::Attachments*>(
      wiimote->GetWiimoteGroup(WiimoteEmu::WiimoteGroup::Attachments));

  if (!imu || imu->controls.size() != 6 || !tilt || tilt->controls.size() < 4 ||
      !attachments || !options)
    return;

  // Only touch the sideways setting used by this Wii Remote. Preserve any
  // user-defined expression so leaving Mario Kart returns to EXACT settings.
  ControllerEmu::NumericSetting<bool>* sideways = nullptr;
  for (auto& setting : options->numeric_settings) {
    if (std::string_view(setting->GetININame()) == WiimoteEmu::Wiimote::SIDEWAYS_OPTION) {
      sideways = static_cast<ControllerEmu::NumericSetting<bool>*>(setting.get());
      break;
    }
  }
  if (!sideways)
    return;

  const auto lock = ControllerEmu::EmulatedController::GetStateLock();
  if (enabled) {
    _previousMarioKartExtension = attachments->GetSelectedAttachment();
    _previousMarioKartSidewaysValue = sideways->GetValue();
    _previousMarioKartSidewaysExpression =
        sideways->GetInputReference().GetExpression();

    // Wii Wheel steering requires a sideways remote with no extension.
    attachments->SetSelectedAttachment(WiimoteEmu::ExtensionNumber::NONE);
    sideways->SetValue(true);
  } else {
    attachments->SetSelectedAttachment(_previousMarioKartExtension);
    sideways->SetValue(_previousMarioKartSidewaysValue);
    if (!_previousMarioKartSidewaysExpression.empty()) {
      auto* reference = &sideways->GetInputReference();
      reference->SetExpression(_previousMarioKartSidewaysExpression);
      wiimote->UpdateSingleControlReference(g_controller_interface, reference);
    }
  }

  // Remove IMU overrides while using synthetic tilt. With no IMU input bound,
  // Dolphin supplies default neutral gravity and uses its own Tilt simulation.
  for (size_t i = 0; i != imu->controls.size(); ++i) {
    auto* ref = imu->controls[i]->control_ref.get();
    if (enabled)
      _previousMarioKartIMUBindings[i] = ref->GetExpression();
    ref->SetExpression(enabled ? "" : _previousMarioKartIMUBindings[i]);
    wiimote->UpdateSingleControlReference(g_controller_interface, ref);
  }

  // Force ONLY Mario Kart's motion-simulation left/right controls to
  // the two touchscreen axes driven by TCDeviceMotion. All other layouts
  // regain their original bindings when this preset is no longer visible.
  static constexpr const char* kWheelTiltAxes[2] = {"`Axis 129`", "`Axis 130`"};
  for (size_t i = 0; i != 2; ++i) {
    auto* ref = tilt->controls[i + 2]->control_ref.get(); // Left, Right
    if (enabled)
      _previousMarioKartTiltBindings[i] = ref->GetExpression();
    ref->SetExpression(enabled ? kWheelTiltAxes[i] : _previousMarioKartTiltBindings[i]);
    wiimote->UpdateSingleControlReference(g_controller_interface, ref);
  }
  _marioKartWheelInputConnected = enabled;
}

- (void)updateVisibleTouchPadWithType:(DOLEmulationVisibleTouchPad)touchPad {
  // Selecting a controller layout is not the same as changing the emulated
  // Wii Remote's extension/orientation. Only enable the wheel behavior when
  // the custom Mario Kart touch layout is actually visible.
  const bool marioKartMode =
      touchPad == DOLEmulationVisibleTouchPadSidewaysWiimote && _sidewaysPreset == 2;
  [self setMarioKartWheelInputConnected:marioKartMode];
  BOOL joystick = NO;
  for (TCView* pad in self.touchPads) {
    if ([pad isKindOfClass:[TCSidewaysWiiPad class]]) {
      joystick = ((TCSidewaysWiiPad*)pad).marioKartJoystickMode;
    }
  }
  [[TCDeviceMotion shared] setMarioKartWheelSteering:marioKartMode && !joystick];
  [[TCDeviceMotion shared] setMarioKartJoystickMode:marioKartMode && joystick];
  [TCManagerInterface setButtonStateFor:118 controller:4 state:marioKartMode];
  if (_visibleTouchPad == touchPad) {
    return;
  }

  TCDeviceMotion* motion = [TCDeviceMotion shared];

  if (touchPad == DOLEmulationVisibleTouchPadWiimote || touchPad == DOLEmulationVisibleTouchPadSidewaysWiimote || touchPad == DOLEmulationVisibleTouchPadClassic) {
    [motion setMotionEnabled:true];
    [motion setPort:4]; // Touchscreen device 4 is used for the Wiimote
  } else {
    [motion setMotionEnabled:false];
  }

  for (TCView* pad in self.touchPads) [pad releaseControllerInputs];

  NSInteger targetIdx = touchPad - 1;

  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];
    padView.userInteractionEnabled = i == targetIdx;
  }

  const float targetOpacity = Config::Get(Config::MAIN_TOUCH_PAD_OPACITY);

  [UIView animateWithDuration:0.5f animations:^{
    for (int i = 0; i < [self.touchPads count]; i++) {
      TCView* padView = self.touchPads[i];
      padView.alpha = i == targetIdx ? targetOpacity : 0.0f;
    }
  }];

  _visibleTouchPad = touchPad;
  [self updatePointerValuesOnWiiTouchPads];
}

- (void)updatePointerValuesOnWiiTouchPads {
  if (!g_presenter) {
    return;
  }

  TCWiiTouchIRMode irMode = TCWiiTouchIRModeNone;
  // The in-game Wii pointer otherwise remains visible during Mario Kart.
  // Suppress BOTH the touch IR cursor and IMU pointer, restoring their
  // previous behavior as soon as Mario Kart's layout is hidden.
  const bool suppressMarioKartPointer =
      _visibleTouchPad == DOLEmulationVisibleTouchPadSidewaysWiimote && _sidewaysPreset == 2;
  [TCManagerInterface setButtonStateFor:118 controller:4 state:suppressMarioKartPointer];

  if ([self isWiimoteTouchPadAttached]) {
    irMode = (TCWiiTouchIRMode)Config::Get(Config::MAIN_TOUCH_PAD_IR_MODE);

    ControllerEmu::ControlGroup* group = Wiimote::GetWiimoteGroup(0, WiimoteEmu::WiimoteGroup::IMUPoint);
    group->enabled.SetValue(irMode == TCWiiTouchIRModeNone && !suppressMarioKartPointer);
  }

  for (int i = 0; i < [self.touchPads count]; i++) {
    TCView* padView = self.touchPads[i];

    if ([padView isKindOfClass:[TCWiiPad class]]) {
      TCWiiPad* wiiPadView = (TCWiiPad*)padView;

      [wiiPadView setTouchIRMode:suppressMarioKartPointer ? TCWiiTouchIRModeNone : irMode];
      [wiiPadView resetPointer];
      [wiiPadView recalculatePointerValuesWithNew_rect:self.rendererView.bounds game_aspect:g_presenter->CalculateDrawAspectRatio()];
    }
  }
}

- (IBAction)pullDownPressed:(id)sender {
  [self updateNavigationBar:false];
}

- (void)receiveEmulationEndNotificationiOS {
  if (@available(iOS 15.0, *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[VirtualMFiControllerManager shared] disconnectController];
    });
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    for (TCView* pad in self.touchPads) [pad releaseControllerInputs];
    [[TCDeviceMotion shared] setMarioKartJoystickMode:NO];
    [[TCDeviceMotion shared] setMarioKartWheelSteering:NO];
    [[TCDeviceMotion shared] setMotionEnabled:false];
  });
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSString* sourcePath = [urls[0] path];
    std::string path = std::string([sourcePath UTF8String]);
    File::IOFile sky_file(path, "r+b");
    if (!sky_file)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Failed to Open Skylander File!"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    std::array<u8, 0x40 * 0x10> file_data;
    if (!sky_file.ReadBytes(file_data.data(), file_data.size()))
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Failed to Read Skylander File!"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    auto& system = Core::System::GetInstance();
    std::pair<u16, u16> id_var = system.GetSkylanderPortal().CalculateIDs(file_data);
    u8 portal_slot = system.GetSkylanderPortal().LoadSkylander(std::make_unique<IOS::HLE::USB::SkylanderFigure>(std::move(sky_file)));
    if (portal_slot == 0xFF)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Failed to Load Skylander File!"
                                       message:nil
                                       preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.skylanderSlot = portal_slot + 1;
}

@end


