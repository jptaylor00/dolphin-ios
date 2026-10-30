import Foundation

var checks = 0
func check(_ condition: Bool, _ message:String) {
  checks += 1
  if !condition { fatalError(message) }
}
func control(_ id:String,_ x:Double,_ inputs:[Int],kind:TCControlKind = .button)->TCControl {
  TCControl(id:id,name:id,kind:kind,frame:TCFrame(x:x,y:0.5,width:60,height:60),inputs:inputs.map { TCInput(code:$0) })
}
let gas = control("gas",0.15,[106])
let lock = control("lock",0.4,[],kind:.target)
let b = control("b",0.65,[101])
let up = control("up",0.85,[109])
let shake = control("shake",0.95,[132,133,134])
let rules = [TCGestureRule(source:"gas",target:"lock",action:.lock,inputs:gas.inputs),
             TCGestureRule(source:"lock",target:"gas",action:.unlock,inputs:gas.inputs),
             TCGestureRule(source:"b",target:"up",action:.addWhileHolding,inputs:up.inputs),
             TCGestureRule(source:"gas",target:"shake",action:.pulse,inputs:shake.inputs)]
let layout = TCLayout(name:"Wheel",controls:[gas,lock,b,up,shake],gestures:rules)
let preset = TCPreset(name:"Test",context:"Sideways-2",gameID:"RMCE01",layouts:[layout])
let decoded = try TCPreset.decode(preset.encoded())
check(decoded == preset,"JSON round trip must preserve IDs, frames, mappings and defaults")
let protected = preset
var copy = preset; copy.id = UUID().uuidString; copy.layouts[0].controls[0].frame.width = 84
check(protected.layouts[0].controls[0].frame.width == 60,"Editing a copy must not mutate default")
var invalid = preset; invalid.version = 999
check((try? invalid.encoded()) == nil,"Reject unknown versions")
invalid = preset; invalid.layouts[0].controls[0].inputs = [TCInput(code:99999)]
check((try? invalid.encoded()) == nil,"Reject unmapped codes")
invalid = preset; invalid.layouts[0].gestures[0].target = "missing"
check((try? invalid.encoded()) == nil,"Reject dangling references")
check(TCInputCatalog.sidewaysDirections.map { $0.code } == [109,110,108,107],"Explicit Mario Kart rotation convention")
check(TCInputCatalog.choices.flatMap { $0.inputs }.allSatisfy(TCInputCatalog.supports),"Every editor mapping is bridge compatible")
let engine = TCGestureEngine(layout:layout)
engine.width = 1000; engine.height = 200
var state:[TCInput:Float] = [:]
var transitions:[String] = []
engine.output = { input,value in state[input] = value; transitions.append("\(input.code):\(value)") }
func down(_ code:Int)->Bool { state[TCInput(code:code)] == 1 }
engine.begin(1,x:150,y:100); check(down(106),"Gas press")
engine.move(1,x:400,y:100); engine.end(1); check(down(106),"Gas locks after swipe and lift")
engine.begin(2,x:400,y:100); engine.end(2); check(down(106),"A tap on Lock must not unlock")
engine.begin(3,x:400,y:100); engine.move(3,x:150,y:100); check(!down(106),"Deliberate reverse slide unlocks")
engine.end(3); check(!down(106),"Unlock remains released")
engine.begin(4,x:650,y:100); engine.begin(5,x:850,y:100)
engine.move(4,x:850,y:100); check(down(101) && down(109),"B holds while adding Up")
let before = transitions.count
engine.end(5); check(down(109),"Another touch releasing Up must not release drift throw ownership")
check(transitions.count == before,"No redundant release when another owner remains")
engine.move(4,x:700,y:100); check(down(101) && !down(109),"Leaving Up releases only secondary input")
engine.end(4); check(!down(101),"Ending drift releases B")
engine.begin(6,x:150,y:100); engine.move(6,x:950,y:100)
check(down(106) && down(132),"2 to Shake pulse preserves gas")
engine.expirePulses(); check(!down(132) && down(106),"Pulse expires without releasing gas")
engine.end(6); check(!down(106),"Gas releases after shake slide")
engine.begin(7,x:150,y:100); engine.move(7,x:400,y:100); engine.end(7,cancelled:true)
check(!down(106) && engine.locked.isEmpty,"Cancellation clears locks")
engine.begin(8,x:650,y:100); engine.reset(); check(!down(101) && engine.contacts.isEmpty,"Exit/mode reset clears contacts")
var wheel = control("wheel",0.5,[],kind:.wheelJoystick)
wheel.frame.width = 120
let stickEngine = TCGestureEngine(layout:TCLayout(name:"Stick",controls:[wheel]))
stickEngine.width = 1000; stickEngine.height = 200
stickEngine.begin(1,x:540,y:100); check(stickEngine.wheelValue > 0.9,"Stick right steers positive")
stickEngine.reset(); check(stickEngine.wheelValue == 0,"Wheel/stick switch recenters")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at:directory) }
let store = TCPresetStore(directory:directory)
try store.save(preset)
check(try store.list(context:"Sideways-2",gameID:"RMCE01").count == 1,"Persistent save/load")
check(try store.list(context:"Sideways-2",gameID:"OTHER").isEmpty,"Game association")
let imported = try store.importPreset(preset.encoded(),context:preset.context,gameID:preset.gameID)
check(imported.id != preset.id,"Import creates copy")
try store.delete(imported)
check(try store.list(context:preset.context,gameID:preset.gameID).count == 1,"Delete preserves other presets")
var tap = gas; tap.tapOnly = true
let tapEngine = TCGestureEngine(layout:TCLayout(name:"Tap",controls:[tap]))
tapEngine.width = 1000; tapEngine.height = 200
var tapped:Float = 0
tapEngine.output = { _,value in tapped = value }
tapEngine.begin(1,x:150,y:100); check(tapped == 0,"Tap does not act on touch down")
tapEngine.end(1); check(tapped == 1,"Tap pulses on release")
tapEngine.expirePulses(); check(tapped == 0,"Tap pulse releases")
let padControl = TCControl(id:"pad",name:"Pad",kind:.dpad,frame:TCFrame(x:0.5,y:0.5,width:120,height:120),inputs:TCInputCatalog.sidewaysDirections)
let dpadEngine = TCGestureEngine(layout:TCLayout(name:"Pad",controls:[padControl]))
dpadEngine.width = 1000; dpadEngine.height = 200
var directions = Set<Int>()
dpadEngine.output = { input,value in if value == 0 { directions.remove(input.code) } else { directions.insert(input.code) } }
dpadEngine.begin(1,x:500,y:50); check(directions == [109],"Kart screen Up maps to raw Left")
dpadEngine.move(1,x:550,y:100); check(directions == [107],"Kart screen Right maps to raw Up")
dpadEngine.end(1,cancelled:true); check(directions.isEmpty,"D-pad cancellation releases directions")
let analog = TCControl(id:"analog",name:"Analog",kind:.joystick,frame:padControl.frame,inputs:(11...14).map { TCInput(code:$0,axis:true) })
let analogEngine = TCGestureEngine(layout:TCLayout(name:"Analog",controls:[analog]))
analogEngine.width = 1000; analogEngine.height = 200
var axes:[Int:Float] = [:]
analogEngine.output = { input,value in axes[input.code] = value }
analogEngine.begin(1,x:450,y:100)
check((axes[13] ?? 0) < -0.9 && (axes[14] ?? 0) == 0,"Left axis uses backend's negative sign")
analogEngine.reset(); check(axes.values.allSatisfy { $0 == 0 },"Analog mode switch releases all axes")
let mixer = TCInputMixer()
var mixed:Float = 0
mixer.output = { _,value in mixed = value }
let shakeInput = TCInput(code:132)
mixer.set(source:"touch",input:shakeInput,value:1)
mixer.set(source:"phone",input:shakeInput,value:1)
mixer.set(source:"phone",input:shakeInput,value:0)
check(mixed == 1,"Phone shake expiry cannot release a held Shake button")
mixer.set(source:"touch",input:shakeInput,value:0)
check(mixed == 0,"Last producer release neutralizes Shake")
print("Passed \(checks) controller model and input-state checks")
