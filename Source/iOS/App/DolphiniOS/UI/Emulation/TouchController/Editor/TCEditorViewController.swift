// SPDX-License-Identifier: GPL-2.0-or-later
import UIKit
import UniformTypeIdentifiers

private final class TCChoiceController: UITableViewController {
  let options:[String]
  let choose:(Int)->Void
  init(title:String,options:[String],choose:@escaping(Int)->Void) {
    self.options = options; self.choose = choose
    super.init(style:.plain); self.title = title
  }
  required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem:.cancel,target:self,action:#selector(close))
  }
  @objc private func close() { dismiss(animated:true) }
  override func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int { options.count }
  override func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell {
    let cell = UITableViewCell(style:.default,reuseIdentifier:nil)
    cell.textLabel?.text = options[indexPath.row]; cell.textLabel?.numberOfLines = 2
    return cell
  }
  override func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath) {
    dismiss(animated:true) { self.choose(indexPath.row) }
  }
}

private final class TCEditCanvas:UIView {
  var layout = TCLayout(name:"",controls:[]) { didSet { redraw() } }
  var selected:String? { didSet { redraw() } }
  var changed:((TCLayout)->Void)?
  private var start:CGPoint?
  private var original:TCControl?
  private var resizing = false
  override func layoutSubviews() { super.layoutSubviews(); redraw() }
  private func rect(_ c:TCControl)->CGRect {
    CGRect(x:CGFloat(c.frame.x)*bounds.width-CGFloat(c.frame.width)/2,y:CGFloat(c.frame.y)*bounds.height-CGFloat(c.frame.height)/2,
           width:CGFloat(c.frame.width),height:CGFloat(c.frame.height))
  }
  func redraw() {
    subviews.forEach { $0.removeFromSuperview() }
    for c in layout.controls {
      let art = TCLayoutView.artwork(c); art.frame = rect(c); art.isUserInteractionEnabled = false
      addSubview(art)
      if selected == c.id {
        art.layer.borderWidth = 2; art.layer.borderColor = UIColor.systemYellow.cgColor
        let handle = UIView(frame:CGRect(x:art.frame.maxX-18,y:art.frame.maxY-18,width:36,height:36))
        handle.backgroundColor = .systemYellow; handle.layer.cornerRadius = 18
        handle.isUserInteractionEnabled = false; addSubview(handle)
      }
    }
  }
  override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
    guard let p = touches.first?.location(in:self) else { return }
    resizing = false
    if let c = layout.controls.first(where: { $0.id == selected }),
       CGRect(x:rect(c).maxX-28,y:rect(c).maxY-28,width:56,height:56).contains(p) {
      resizing = true; original = c
    } else {
      original = layout.controls.reversed().first { rect($0).contains(p) }
      selected = original?.id
    }
    start = p
  }
  override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
    guard let p = touches.first?.location(in:self), let start = start, var c = original,
          let index = layout.controls.firstIndex(where: { $0.id == c.id }) else { return }
    let dx = Double(p.x-start.x), dy = Double(p.y-start.y)
    if resizing {
      let newWidth = max(16,min(600,c.frame.width+dx)), newHeight = max(16,min(600,c.frame.height+dy))
      if let w = c.artworkWidth { c.artworkWidth = w*newWidth/c.frame.width }
      if let h = c.artworkHeight { c.artworkHeight = h*newHeight/c.frame.height }
      c.frame.x += (newWidth-c.frame.width)/2/Double(max(1,bounds.width))
      c.frame.y += (newHeight-c.frame.height)/2/Double(max(1,bounds.height))
      c.frame.width = newWidth; c.frame.height = newHeight
    } else {
      c.frame.x += dx/Double(max(1,bounds.width)); c.frame.y += dy/Double(max(1,bounds.height))
    }
    c.frame.x = max(0,min(1,c.frame.x)); c.frame.y = max(0,min(1,c.frame.y))
    layout.controls[index] = c
    changed?(layout)
  }
  override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) { start = nil; original = nil }
  override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) { start = nil; original = nil }
}

final class TCEditorViewController:UIViewController,UIDocumentPickerDelegate {
  private let pad:TCView
  private let gameID:String
  private var preset:TCPreset
  private let defaults:[TCLayout]
  private var layoutIndex = 0
  private let canvas = TCEditCanvas()
  private let toolbar = UIScrollView()
  private let status = UILabel()
  private let initial:TCPreset?
  private let motionWasEnabled:Bool
  init(pad:TCView,gameID:String) {
    self.pad = pad; self.gameID = gameID
    motionWasEnabled = TCDeviceMotion.shared.controllerMotionEnabled
    initial = pad.customPreset
    let captured = pad.editorDefaultLayouts()
    defaults = captured
    preset = pad.customPreset ?? TCPreset(name:"My Controller",context:pad.editorContext,gameID:gameID,layouts:captured)
    super.init(nibName:nil,bundle:nil)
    TCDeviceMotion.shared.setMotionEnabled(false)
  }
  required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var supportedInterfaceOrientations:UIInterfaceOrientationMask { .landscape }
  override var prefersHomeIndicatorAutoHidden:Bool { true }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(white:0.06,alpha:1)
    // A neutral canvas avoids ghost copies of controls in a game screenshot.
    canvas.frame = view.bounds; canvas.autoresizingMask = [.flexibleWidth,.flexibleHeight]
    canvas.alpha = max(0.05,pad.alpha)
    canvas.layout = preset.layouts[layoutIndex]
    canvas.changed = { [weak self] layout in guard let self = self else { return }; self.preset.layouts[self.layoutIndex] = layout }
    view.addSubview(canvas)
    toolbar.backgroundColor = UIColor(white:0.12,alpha:0.96)
    view.addSubview(toolbar)
    let items:[(String,Selector)] = [("Cancel",#selector(cancel)),("Save & Play",#selector(save)),("Presets",#selector(presets)),("Add",#selector(addControl)),("Properties",#selector(properties)),("Gestures",#selector(gestures)),("Motion",#selector(motion)),("Wheel / Stick",#selector(switchLayout))]
    var x:CGFloat = 8
    for (title,action) in items {
      let button = UIButton(type:.system); button.setTitle(title,for:.normal)
      button.frame = CGRect(x:x,y:0,width:110,height:44)
      button.addTarget(self,action:action,for:.touchUpInside); toolbar.addSubview(button); x += 114
    }
    toolbar.contentSize = CGSize(width:x,height:44)
    status.textColor = .systemYellow; status.font = .systemFont(ofSize:12,weight:.medium)
    status.textAlignment = .center; status.isUserInteractionEnabled = false
    view.addSubview(status); updateStatus()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    toolbar.frame = CGRect(x:view.safeAreaInsets.left,y:view.safeAreaInsets.top,width:view.bounds.width-view.safeAreaInsets.left-view.safeAreaInsets.right,height:44)
    status.frame = CGRect(x:0,y:toolbar.frame.maxY,width:view.bounds.width,height:24)
  }
  private func updateStatus() {
    status.text = "EDIT MODE • \(preset.name) • \(preset.layouts[layoutIndex].name) • Drag a control; drag its yellow handle to resize"
  }
  private func refresh() { canvas.layout = preset.layouts[layoutIndex]; updateStatus() }
  private func pick(_ title:String,_ options:[String],_ action:@escaping(Int)->Void) {
    let list = TCChoiceController(title:title,options:options,choose:action)
    let nav = UINavigationController(rootViewController:list)
    nav.modalPresentationStyle = .formSheet
    present(nav,animated:true)
  }
  private func error(_ error:Error) {
    let alert = UIAlertController(title:"Controller Presets",message:error.localizedDescription,preferredStyle:.alert)
    alert.addAction(UIAlertAction(title:"OK",style:.default)); present(alert,animated:true)
  }
  private func text(_ title:String,value:String,done:@escaping(String)->Void) {
    let alert = UIAlertController(title:title,message:nil,preferredStyle:.alert)
    alert.addTextField { $0.text = value; $0.autocorrectionType = .no }
    alert.addAction(UIAlertAction(title:"Cancel",style:.cancel))
    alert.addAction(UIAlertAction(title:"Done",style:.default) { _ in
      let value = alert.textFields?[0].text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
      if !value.isEmpty { done(String(value.prefix(100))) }
    }); present(alert,animated:true)
  }
  private func finish(_ value:TCPreset?) {
    dismiss(animated:true) {
      self.pad.applyCustomPreset(value,index:self.layoutIndex)
      TCDeviceMotion.shared.setMotionEnabled(self.motionWasEnabled)
    }
  }
  @objc private func cancel() { layoutIndex = min(pad.customLayoutIndex,(initial?.layouts.count ?? 1)-1); finish(initial) }
  @objc private func save() {
    text("Save Preset",value:preset.name) { name in
      self.preset.name = name
      do { try TCPresetStore.shared.save(self.preset); self.finish(self.preset) } catch { self.error(error) }
    }
  }
  @objc private func switchLayout() {
    guard preset.layouts.count == 2 else { return }
    layoutIndex = 1-layoutIndex; canvas.selected = nil; refresh()
  }
  @objc private func presets() {
    do {
      let saved = try TCPresetStore.shared.list(context:pad.editorContext,gameID:gameID)
      pick("Presets",["Protected default — Play", "New copy of default", "New empty preset", "Import JSON from Files"] + saved.map { $0.name }) { index in
        if index == 0 { self.layoutIndex = 0; self.finish(nil) }
        else if index == 1 {
          self.preset = TCPreset(name:"Default Copy",context:self.pad.editorContext,gameID:self.gameID,layouts:self.defaults)
          self.layoutIndex = 0; self.refresh()
        } else if index == 2 {
          self.preset = TCPreset(name:"New Controller",context:self.pad.editorContext,gameID:self.gameID,layouts:self.pad.editorContext == "Sideways-2" ? [TCLayout(name:"Wheel",controls:[]),TCLayout(name:"Joystick",controls:[])] : [TCLayout(name:"Controls",controls:[])])
          self.layoutIndex = 0; self.refresh()
        } else if index == 3 {
          let picker = UIDocumentPickerViewController(forOpeningContentTypes:[.json],asCopy:true)
          picker.delegate = self; self.present(picker,animated:true)
        } else { self.presetActions(saved[index-4]) }
      }
    } catch { self.error(error) }
  }
  private func presetActions(_ saved:TCPreset) {
    pick(saved.name,["Load & Play","Edit","Rename","Duplicate","Export JSON","Delete"]) { index in
      switch index {
      case 0: self.layoutIndex = 0; self.finish(saved)
      case 1: self.preset = saved; self.layoutIndex = 0; self.refresh()
      case 2:
        self.text("Rename",value:saved.name) { name in var p = saved; p.name = name
          do { try TCPresetStore.shared.save(p); if self.preset.id == p.id { self.preset = p; self.refresh() } } catch { self.error(error) }
        }
      case 3:
        var p = saved; p.id = UUID().uuidString; p.name += " Copy"
        do { try TCPresetStore.shared.save(p); self.preset = p; self.layoutIndex = 0; self.refresh() } catch { self.error(error) }
      case 4:
        do {
          let url = FileManager.default.temporaryDirectory.appendingPathComponent("Controller-\(saved.id).json")
          try saved.encoded().write(to:url,options:.atomic)
          let share = UIActivityViewController(activityItems:[url],applicationActivities:nil)
          share.popoverPresentationController?.sourceView = self.toolbar
          share.popoverPresentationController?.sourceRect = self.toolbar.bounds
          self.present(share,animated:true)
        } catch { self.error(error) }
      default:
        let alert = UIAlertController(title:"Delete \(saved.name)?",message:"This deletes this user preset.",preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"Cancel",style:.cancel))
        alert.addAction(UIAlertAction(title:"Delete",style:.destructive) { _ in
          do { try TCPresetStore.shared.delete(saved) } catch { self.error(error) }
        }); self.present(alert,animated:true)
      }
    }
  }
  func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
    guard let url = urls.first else { return }
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
      guard size <= 1_048_576 else { throw TCPresetError.invalid("Preset exceeds 1 MB") }
      preset = try TCPresetStore.shared.importPreset(Data(contentsOf:url),context:pad.editorContext,gameID:gameID)
      layoutIndex = 0; refresh()
    } catch { self.error(error) }
  }
  @objc private func addControl() {
    let choices = availableChoices
    pick("Add Control",choices.map { $0.name }) { index in
      let choice = choices[index]
      let size:Double = [.button,.pulse,.target].contains(choice.kind) ? 64 : 110
      let control = TCControl(name:choice.name,kind:choice.kind,frame:TCFrame(x:0.5,y:0.45,width:size,height:size),inputs:choice.inputs)
      self.preset.layouts[self.layoutIndex].controls.append(control)
      self.canvas.selected = control.id; self.refresh()
    }
  }
  private var availableChoices: [TCInputChoice] {
    TCInputCatalog.choices.filter { choice in
      if [.wheelJoystick,.mode,.recenter].contains(choice.kind) { return pad.editorContext == "Sideways-2" }
      return choice.inputs.allSatisfy { pad.port == 0 ? $0.code < 100 : $0.code >= 100 }
    }
  }
  private func selectedIndex()->Int? { preset.layouts[layoutIndex].controls.firstIndex { $0.id == canvas.selected } }
  @objc private func properties() {
    guard let index = selectedIndex() else { return }
    let control = preset.layouts[layoutIndex].controls[index]
    pick(control.name,["Rename","Input mapping","Opacity","Haptics: \(control.haptic ? "On" : "Off")","Activation: \(control.tapOnly ? "Tap" : "Hold")","Remove control"]) { choice in
      switch choice {
      case 0: self.text("Control Name",value:control.name) { self.preset.layouts[self.layoutIndex].controls[index].name = $0; self.refresh() }
      case 1:
        let choices = self.availableChoices.filter { $0.kind == control.kind }
        self.pick("Map \(control.name)",choices.map { $0.name }) { selected in
          self.preset.layouts[self.layoutIndex].controls[index].inputs = choices[selected].inputs
          self.preset.layouts[self.layoutIndex].controls[index].artwork = nil
          self.preset.layouts[self.layoutIndex].controls[index].name = choices[selected].name; self.refresh()
        }
      case 2:
        self.pick("Opacity",["20%","40%","60%","80%","100%"]) { selected in
          self.preset.layouts[self.layoutIndex].controls[index].opacity = Double(selected+1)*0.2; self.refresh()
        }
      case 3: self.preset.layouts[self.layoutIndex].controls[index].haptic.toggle(); self.refresh()
      case 4: self.preset.layouts[self.layoutIndex].controls[index].tapOnly.toggle(); self.refresh()
      default:
        self.preset.layouts[self.layoutIndex].controls.remove(at:index)
        self.preset.layouts[self.layoutIndex].gestures.removeAll { $0.source == control.id || $0.target == control.id }
        self.canvas.selected = nil; self.refresh()
      }
    }
  }
  @objc private func gestures() {
    guard let index = selectedIndex() else { return }
    let source = preset.layouts[layoutIndex].controls[index]
    let rules = preset.layouts[layoutIndex].gestures.filter { $0.source == source.id }
    pick("\(source.name) — hold is automatic",["Add gesture"] + rules.map { "Remove \($0.action.rawValue)" }) { selected in
      if selected > 0 {
        self.preset.layouts[self.layoutIndex].gestures.removeAll { $0.id == rules[selected-1].id }; return
      }
      let targets = self.preset.layouts[self.layoutIndex].controls
      self.pick("Slide / tap target",targets.map { $0.name }) { target in
        let actions = TCGestureAction.allCases
        let labels = ["Hold first + activate second","Drag to replace first","Swipe to lock","Reverse swipe to unlock","Swipe to pulse (shake)","Tap on release"]
        self.pick("Action",labels) { action in
          let choices = self.availableChoices.filter { $0.kind == .button || $0.kind == .pulse }
          self.pick("Action input",choices.map { $0.name }) { mapping in
            self.pick("Action Haptic",["On","Off"]) { haptic in
              self.preset.layouts[self.layoutIndex].gestures.append(TCGestureRule(source:source.id,target:targets[target].id,
                action:actions[action],inputs:choices[mapping].inputs,haptic:haptic == 0))
            }
          }
        }
      }
    }
  }
  @objc private func motion() {
    pick("Motion",["Steering Sensitivity","Invert: \(preset.motion.inverted ? "On" : "Off")","Phone Shake: \(preset.motion.phoneShake ? "On" : "Off")","Recenter when returning to play"]) { selected in
      switch selected {
      case 0:
        self.pick("Sensitivity",["0.4x","0.7x","1.0x","1.3x","1.6x","2.0x","2.5x"]) { self.preset.motion.sensitivity = [0.4,0.7,1.0,1.3,1.6,2.0,2.5][$0] }
      case 1: self.preset.motion.inverted.toggle()
      case 2: self.preset.motion.phoneShake.toggle()
      default: TCDeviceMotion.shared.recenterMarioKartWheelSteering()
      }
    }
  }
}

