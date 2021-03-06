
--# FileAccess


DropboxReader = class()

function DropboxReader:read(name) 
   return readText("Dropbox:"..name)
end

function DropboxReader:write(name, data)
   return false
end

NullIO = class()

function NullIO:read(name)
   return ""
end

function NullIO:write(name, data)
   return false
end

ProjectIO = class()
function ProjectIO:init(prefix)
   self.prefix = prefix
end

function ProjectIO:read(name)
   return readProjectData(self:rackPrefix()..self.prefix..name)
end

function ProjectIO:write(name, data)
   saveProjectData(self:rackPrefix()..self.prefix..name, data)
   return true;
end

function ProjectIO:rackPrefix()
   local rackPrefix = ""
   if (rackNumber > 1) then
       rackPrefix = string.format("rk%d_", rackNumber)
   end
   return rackPrefix
end

--# Main
-- PDP8
-- Test on other ipads.

backingMode(RETAINED)

function dummy()
   readText("Dropbox:listing")
end

function setup()
   supportedOrientations(LANDSCAPE_ANY)
   showKeyboard()
   displayMode(FULLSCREEN_NO_BUTTONS)
   tics = 0
   initAscii()
   rightFrame = WIDTH-557
   midFrame = rightFrame-110
   leftFrame = 0
   controlPanel = ControlPanel(rightFrame,80)
   tty = Teletype(rightFrame, 90+controlPanel.height, controlPanel.width, HEIGHT-(90+controlPanel.height)-10)

   punch = Punch(midFrame, HEIGHT-210)
   punchSpeed = Button(midFrame-40, punch.bottom+130, "FAST", setPunchSpeed)
   punchFast = 0
   punchClear = MomentaryButton(midFrame-40, punch.bottom+65, "JUNK", clearPunch)
   punchLeaderButton = MomentaryButton(midFrame-40, punch.bottom, "LEAD", punchLeader)

   tapeReader = TapeReader(midFrame, 350)
   readerSpeed = Button(midFrame-40, tapeReader.bottom+130, "FAST", setReaderSpeed)
   readerFast = 0
   readerAutoButton = Button(midFrame-40, tapeReader.bottom+65, "AUTO", setReaderAuto)

   rimPanel = RimPanel(midFrame,90)    

   rack = Rack(0,100,midFrame-leftFrame)
   rackControls = RackControls(0,40,Shelf.width*2)
   rackNumber = 1
   racks = {}
   racks[1] = rack
   loadRack()

   test = MomentaryButton(midFrame, 10, "Test", testAll)
   ttySpeed = Button(midFrame+50, 10, "TTY FAST", setTtySpeed)
   ttyFast = 0

   instructionsPerSecond = 0
   framesPerSecond = 0
   lastFrameCount = 0
   lastTimePeriod = 0    

   statsPanel = StatsPanel(WIDTH-StatsPanel.width-10, 10)

   quitButton = MomentaryButton(rightFrame+100, 10, "QuitX2", quitProgram)

   saveListingButton = MomentaryButton(rightFrame+200, 10, "Save TTY", saveListing)
   junkTtyButton =  MomentaryButton(rightFrame+300, 10, "Junk TTY", junkTty)
   quitTime = 0
end

function draw()
   local time = os.time()
   if time ~= lastTimePeriod then
       lastTimePeriod = time
       instructionsPerSecond = controlPanel.instructions
       controlPanel.instructions = 0
       framesPerSecond = tics-lastFrameCount
       lastFrameCount = tics
   end    
   tics = tics + 1
   if tics < 5 then
       background(0,0,0,255)
   end
   controlPanel:draw()
   tty:draw()

   punch:draw()  
   tapeReader:draw()

   test:draw()
   rimPanel:draw()

   rack:draw()
   rackControls:draw()
   statsPanel:draw()
   readerSpeed:draw()
   readerAutoButton:draw()
   punchSpeed:draw()
   punchClear:draw()
   punchLeaderButton:draw()
   ttySpeed:draw()
   quitButton:draw()
   saveListingButton:draw()
   junkTtyButton:draw()
end

function touched(t)
   controlPanel:touched(t)
   tapeReader:touched(t)
   punch:touched(t)
   tty:touched(t)

   test:touched(t)
   statsPanel:touched(t)
   punchSpeed:touched(t)
   punchClear:touched(t)
   punchLeaderButton:touched(t)
   readerSpeed:touched(t)
   readerAutoButton:touched(t)
   ttySpeed:touched(t)
   quitButton:touched(t)
   saveListingButton:touched(t)
   junkTtyButton:touched(t)

   Shelf.wasTouched = false
   rackControls:touched(t)
   rack:touched(t)
   if Shelf.wasTouched == false and selectedShelf ~= nil and t.state==BEGAN then
       selectedShelf:unselect()
       selectedShelf = nil
   end
end

function setupText()
   fill(255,255,255,255)
   fontSize(12)
   textMode(CORNER)
   font("ArialMT")
end

function keyboard(key)
   if selectedShelf == nil then
       sendToTTY(key)
   else
       selectedShelf:key(key)
   end
end

function sendToTTY(key)
   local code = 0
   if (key == "«") then -- RUBOUT
       code = Processor.octal(377)
   elseif (key == "¬") then -- CTRL-L FORM-FEED
       code = Processor.octal(214)
   elseif (key == "©") then -- CTRL-G BELL
       code = Processor.octal(207)
   elseif (key == "ç") then -- CTRL-C
       code = Processor.octal(203)
   elseif (key:byte(1) == nil) then -- CTRL-M CR
       code = Processor.octal(215) 
   else
       key = string.upper(key)
       code =128+(key:byte(1))
   end

   controlPanel.processor.device[3].buffer = code
   controlPanel.processor.device[3].ready = 1 
end

function checkReader()
   local reader = controlPanel.processor.device[1]
   if (tapeReader.buffer:len() > 0) then
       if (readerAuto==1) then
           sendToTTY(string.char(tapeReader:read()))
       elseif (reader.ready == 0) then
           reader.ready = 1
           reader.buffer = tapeReader:read()
       end
   end
end

function checkTTY()
   local dev = controlPanel.processor.device[4]
   if dev.ready == 0 and dev.operating then
       tty:type(dev.buffer)
       dev.ready = 1
       dev.operating = false
   end
end

function checkPunch()
   local dev = controlPanel.processor.device[2]
   if dev.ready == 0 and dev.operating then
       punch:punch(dev.buffer)
       dev.ready = 1
       dev.operating = false
   end
end

function save()
   local name = "Core."..os.clock()
   local shelf = findEmptyShelf()
   shelf.type = Shelf.CORE
   shelf.io = ProjectIO("cr_")
   shelf.name = name

   data = ""
   for addr=0,4095,1 do
       data = data..controlPanel.processor.memory[addr]..':'
   end
   shelf.io:write(name, data) 
   Rack.drawCount = 1
end

function load()
   if selectedShelf ~= nil and selectedShelf.type == Shelf.CORE then
       data = selectedShelf.io:read(selectedShelf.name)

       local pos = 1
       for addr=0,4095,1 do
           local colon = string.find(data, ':', pos, true)
           local token = string.sub(data, pos, colon-1)
           controlPanel.processor.memory[addr]=0+token
           pos = colon+1
       end
   end
end

function loadRack() 
   loadRackFromDropbox()  
   loadRackFromProject()
end

function loadRackFromDropbox()
   local tapes = assetList("Dropbox")
   for i=1,#tapes do
       local shelf = findEmptyShelf()
       shelf.type = Shelf.TAPE
       shelf.name = tapes[i]
       shelf.io = DropboxReader()
   end
end

function loadRackFromProject()
   local files = listProjectData()
   for i=1, #files do
       local rackNo, name = extractRackFromFileName(files[i])
       if (rackNo ~= nil) then
           rackNumber = rackNo
           if racks[rackNo] == nil then
               racks[rackNo] = Rack(0, 100, midFrame-leftFrame)
           end
           loadShelf(racks[rackNo]:findEmptyShelf(), name)
       else
           loadShelf(findEmptyShelf(), files[i])
       end
   end
   rackNumber = 1
   rack = racks[1]
end

function extractRackFromFileName(fileName)
   local rackNumber,name = string.match(fileName, "^rk(%d+)_(.+)$")
   if rackNumber == nil then
       return nil,nil
   end
   return rackNumber+0,name
end

function loadShelf(shelf, fileName)
   local prefix = fileName:sub(1,3)
   local name = fileName:sub(4,-1)
   if prefix=="pt_" then
       shelf.type = Shelf.TAPE
       shelf.io = ProjectIO(prefix)
       shelf.name = name
   elseif prefix=="cr_" then
       shelf.type = Shelf.CORE
       shelf.io = ProjectIO(prefix)
       shelf.name = name
   end
end

function findEmptyShelf()
   local shelf = rack:findEmptyShelf()
   if shelf == nil then
       rackNumber = #racks+1
       racks[rackNumber] = Rack(0, 100, midFrame-leftFrame)
       rack = racks[rackNumber]
       Rack.drawCount = 1
       shelf = rack:findEmptyShelf()
   end
   return shelf
end

function nextRack()
   rackNumber = rackNumber+1
   if racks[rackNumber] == nil then
       racks[rackNumber] = Rack(0,100,midFrame-leftFrame)
   end
   rack = racks[rackNumber]
   Rack.drawCount = 1
end

function prevRack()
   if rackNumber > 1 then
       rackNumber = rackNumber-1
       rack = racks[rackNumber]
       Rack.drawCount = 1
   end
end

function setReaderSpeed(speed)
   readerFast = speed
end

function setReaderAuto(auto)
   readerAuto = auto   
end

function setPunchSpeed(speed)
   punchFast = speed
end

function clearPunch()
   punch.buffer = ""
   punch.drawCount = 1
   sound("Game Sounds One:Land")
end

function punchLeader()
   local leader = ""
   for i=1,15 do
       leader=leader..string.char(Processor.octal(200))
   end
   punch.buffer = punch.buffer..leader
   punch.drawCount = 1
end

function setTtySpeed(speed)
   ttyFast = speed
end

function quitProgram() 
   now = os.clock()
   if now-quitTime < 1 then
       sound("Game Sounds One:Assembly 5")
       while os.clock() - now < 0.5 do end
       close()
   end
   quitTime = now
end

function saveListing() 
   saveText("Dropbox:listing", makeTextFromTty())
end

function makeTextFromTty()
   s = ""
   for i,c in pairs(tty.chars) do
       if c == Processor.octal(12) then
           -- ignore
       elseif c == Processor.octal(14) then
           s = s.."\n\n----------------\n\n"
       else
           s = s..ASCII[c]
       end
   end
   return s
end

function junkTty() 
   tty:clear()
end

function testAll() 
   local t = Test()
   mainTest(t)
   ControlPanel.test(t)
end

function mainTest(t)
   t:assertEquals(nil, extractRackFromFileName("fileName"), "ExtractRack1")
   t:assertEquals(1, extractRackFromFileName("rk01_name"), "ExtractRack2")
   local rackNumber, name = extractRackFromFileName("rk99_cr_name")
   t:assertEquals(99, rackNumber, "ExtractRack3")
   t:assertEquals("cr_name", name, "ExtractRack4")
end

--# Bit
Bit = class()
Bit.width = 35
Bit.height = Bit.width

function Bit:init(x,y)
   self.x = x
   self.y = y
   self.value = 0
   self.locked = false
   self.drawCount = 5
end

function Bit:draw()
   if self.drawCount > 0 then
       self:drawBit()
       self.drawCount = self.drawCount-1
   end
end

function Bit:drawBit()
   stroke(255, 255, 255, 255)
   strokeWidth(2)
   if (self.value == 1) then
       fill(255, 255, 255, 255)
   else
       fill(0,0,0,255)
   end
   rect(self.x,self.y, Bit.width, Bit.height)
end

function Bit:setValue(v)
   local newValue = math.floor(v)
   if self.value ~= newValue then
       self.value = newValue
       self.drawCount = 1
   end
end

function Bit:touched(t)
   if (t.state == ENDED) then
       self.locked = false
       return false
   end

   if (self.locked) then
       return false
   end

   if (self:isWithin(t)) then
       self.value = self.value==1 and 0 or 1
       self.lastTouch = t.state
       self.locked = true
       self.drawCount = 1
       self:sound()
       return true
   else
       return false
   end
end

function Bit:sound()
   sound("Game Sounds One:Wall Bounce 1")   
end

function Bit:isWithin(t)
   local dx = t.x - self.x
   local dy = t.y - self.y
   return dx >= 0 and dx <= Bit.width and dy >= 0 and dy <= Bit.width
end

SwitchBit = class(Bit)

function SwitchBit:drawBit() 
   switchColor = color(128)
   gapColor = color(64)
   stroke(0)
   strokeWidth(4)
   local y = self.y
   local gap = y+Bit.height/2
   if (self.value == 1) then
       switchColor = color(255)
       y = y + Bit.height/2
       gap = gap-Bit.height/2
   end
   fill(switchColor)
   rect(self.x,y,Bit.width,Bit.height/2)
   noStroke()
   fill(gapColor)
   rect(self.x, gap, Bit.width, Bit.height/2)
end

function SwitchBit:sound()
   sound("Game Sounds One:Assembly 3")
end

RoundBit = class(Bit)

function RoundBit:drawBit() 
   stroke(255, 255, 255, 255)
   strokeWidth(2)
   if (self.value == 1) then
       fill(255, 255, 255, 255)
   else
       fill(0,0,0,255)
   end
   ellipseMode(CORNER)
   ellipse(self.x,self.y, Bit.width, Bit.height)    
end

--# Button
Button = class()

function Button:init(x,y,name, f)
   self.x = x
   self.y = y
   self.name = name
   self.f = f
   setupText()
   local w,h = textSize(name)
   local bitLeft = (w - Bit.width)/2
   local bitBottom = h+5    
   self.bit = self:makeBit(self.x + bitLeft, self.y + bitBottom)   
   self.width = math.max(Bit.width, w)
end

function Button:draw()
   self.bit:draw()
   setupText()
   text(self.name, self.x, self.y)
end

function Button:touched(touch)
   if (self.bit:touched(touch)) then
       self:hit()
   end
end

function Button:hit()
   sound("Game Sounds One:Knock 2")
   self.f(self.bit.value)
end

function Button:off()
   self.bit:setValue(0)
end

function Button:makeBit(x,y)
   return Bit(x,y)
end

MomentaryButton = class(Button)

function MomentaryButton:hit()
   self._base.hit(self)
   self:off()
end

function MomentaryButton:makeBit(x,y)
   return RoundBit(x,y)
end

RoundButton = class(Button)

function RoundButton:makeBit(x,y)
   return RoundBit(x,y)
end


--# ControlPanel
ControlPanel = class()

ControlPanel.frame = 10

function ControlPanel:init(x,y)
   cp = self -- singleton.
   self.x = x
   self.y = y
   local left = x + ControlPanel.frame
   local bottom = y + ControlPanel.frame
   local regBottom = bottom + 130
   local buttonSpace = 80
   local buttonLeft = left+250
   self.pc = Register(left,regBottom+150, "PC")
   self.ma = Register(left,regBottom+100, "MA")
   self.mb = Register(left,regBottom+50, "MB")
   self.ac = Register(left,regBottom, "AC")
   self.sr = SwitchRegister(left,bottom+80, "SR")
   self.run = RoundButton(buttonLeft, bottom, "RUN", ControlPanel.run)
   self.deposit = MomentaryButton(buttonLeft+buttonSpace, bottom, "DEP", ControlPanel.deposit)
   self.exam = MomentaryButton(buttonLeft+2*buttonSpace, bottom, "EXAM", ControlPanel.examine)
   self.step = MomentaryButton(buttonLeft+3*buttonSpace, bottom, "STEP", ControlPanel.step)
   self.link = Button(left+5, bottom, "LINK")
   self.ion = Button(left+65, bottom, "ION")
   self.kbf = Button(left+105, bottom, "KBD")
   self.tpf = Button(left+145, bottom, "TTY")

   self.processor = Processor(self.sr, self.run)
   self.width = self.ac:width() + ControlPanel.frame*2
   self.height = 330+ControlPanel.frame
   instructionsPerSecond = 0
   self.instructions = 0
   self.drawCount = 4
   lastTtyTime = 0
   lastReadTime = 0
   lastPunchTime = 0
end

function ControlPanel:draw()
   if (self.drawCount > 0) then
       fill(115, 76, 50, 255)
       strokeWidth(2)
       stroke(255,255,255,255)
       rectMode(CORNER)
       rect(self.x,self.y, self.width, self.height)
       self.drawCount = self.drawCount - 1
   end
   self.pc:draw()
   self.ma:draw()
   self.mb:draw()
   self.ac:draw()
   self.sr:draw()
   self.run:draw()
   self.deposit:draw()
   self.exam:draw()
   self.step:draw()
   self.link:draw()
   self.ion:draw()
   self.kbf:draw()
   self.tpf:draw()

   if (self.run.bit.value > 0) then
       cp.processor.pc = cp.pc:value()
       cp.processor.ac = cp.ac:value()
       cp.processor.link = cp.link.bit.value
       for i=1,cyclesPerFrame do
           cp.processor:step()
           self.instructions = self.instructions + 1
           if self.run.bit.value == 0 then
               break
           end
           self:checkDevs()
       end
       cp.loadLightsFromProcessor()
   end
end

function ControlPanel:checkDevs()
   local ttyDelay = .1
   local punchDelay = .1
   local readerDelay = .1

   if ttyFast == 1 then
       ttyDelay = 0
   end

   if punchFast == 1 then
       punchDelay = 0.02
   end

   if readerFast == 1 then
       readerDelay = .01
   end

   local now = os.clock()
   if (now-lastTtyTime >= ttyDelay) then
       checkTTY()
       lastTtyTime = now
   end

   if now-lastReadTime >= readerDelay then
       checkReader()
       lastReadTime = now
   end

   if now-lastPunchTime >= punchDelay then
       checkPunch()
       lastPunchTime = now
   end
end

function ControlPanel:touched(touch)
   self.pc:touched(touch)
   self.ma:touched(touch)
   self.mb:touched(touch)
   self.ac:touched(touch)
   self.sr:touched(touch)
   self.run:touched(touch)
   self.deposit:touched(touch)
   self.exam:touched(touch)
   self.step:touched(touch)
   self.link.bit:touched(touch)
end

function ControlPanel.run(state)
   hideKeyboard()
   showKeyboard()
end

function ControlPanel.deposit(state)
   local ma = cp.ma:value()
   local mb = cp.mb:value()
   cp.processor:store(ma, mb)
   cp.ma:setValue(ma+1)
   cp.mb:setValue(0)
   cp.deposit:off()
end

function ControlPanel.examine(state)
   local ma = cp.ma:value()
   local mb = cp.processor:get(ma)
   cp.mb:setValue(cp.processor:get(ma))
   cp.ma:setValue(ma+1)
   cp.exam:off()
end

function ControlPanel.step(state)
   cp.processor.pc = cp.pc:value()
   cp.processor.ac = cp.ac:value()
   cp.processor.link = cp.link.bit.value
   cp.processor:step()
   cp.loadLightsFromProcessor()
   cp.step:off()
end

function ControlPanel.loadLightsFromProcessor()
   cp.ac:setValue(cp.processor.ac)
   cp.pc:setValue(cp.processor.pc)
   cp.ma:setValue(cp.processor.ma)
   cp.mb:setValue(cp.processor.mb)
   cp.link.bit:setValue(cp.processor.link)
   cp.ion.bit:setValue((cp.processor.ion and 1) or 0)
   cp.kbf.bit:setValue(cp.processor.device[3].ready)
   cp.tpf.bit:setValue(cp.processor.device[4].ready)
end

function ControlPanel.test(t)
   local register = Register(0,0,"TEST")
   register:test(t)
   local processor = Processor(cp.mb, cp.run)
   processor:test(t)
   t:report()
end

--# Device
Device = class()

function Device:init(processor)
   self.processor = processor
   self.ready = 0
   self.buffer = 0
   self.operating = false
end

function Device:io(flags)
   if Processor.mask(1, flags) > 0 and self.ready == 1 then
       self:skipIfReady()
   end
   if Processor.mask(2, flags) > 0 then
       self:clearFlag()
   end
   if Processor.mask(4, flags) > 0 then       
       self:operate()
   end
end

function Device:skipIfReady()
   self.processor.pc = self.processor.pc + 1
end

function Device:clearFlag() 
   self.ready = 0
end

Teleprinter = class(Device)

function Teleprinter:operate()
   self.buffer = self.processor.ac
   self.operating = true        
end

Keyboard = class(Device)

function Keyboard:clearFlag()
   self.ready = 0;
   self.processor.ac = 0;
end

function Keyboard:operate()
   self.processor.ac = Processor.ior(self.processor.ac, self.buffer)
end

TapePunch = class(Teleprinter)

PaperTapeReader = class(Device)

function PaperTapeReader:io(flags)
   if Processor.mask(1, flags) > 0 and self.ready == 1 then
       self:skipIfReady()
   end
   if Processor.mask(2, flags) > 0 then
       self.processor.ac = Processor.ior(self.processor.ac, self.buffer)
   end
   if Processor.mask(4, flags) > 0 then       
       self.ready = 0
   end
end


--# OctalDigit
OctalDigit = class()
OctalDigit.spacing = 5

function OctalDigit:init(x,y)
   self.x = x
   self.y = y
   self.bits = {}
   for i=1,3 do
       local n=i-1
       self.bits[i] = self:makeBit(x + (n * (Bit.width + OctalDigit.spacing)), y)
   end
end

function OctalDigit:draw()
   for i,bit in ipairs(self.bits) do
       bit:draw()
   end
end

function OctalDigit:touched(touch)
   for i,bit in ipairs(self.bits) do
       bit:touched(touch)
   end
end

function OctalDigit:value() 
   return self.bits[3].value + self.bits[2].value * 2 + self.bits[1].value * 4
end

function OctalDigit:setValue(v)
   self.bits[1]:setValue(v/4)
   v = v%4
   self.bits[2]:setValue(v/2)
   v = v%2
   self.bits[3]:setValue(v)    
end

function OctalDigit:width()
   return 3*Bit.width + 2*OctalDigit.spacing
end

function OctalDigit:height()
   return Bit:height()
end

function OctalDigit:makeBit(x,y)
   return Bit(x,y)
end

OctalSwitch = class(OctalDigit)

function OctalSwitch:makeBit(x,y)
   return SwitchBit(x,y)
end

--# PaperTape
PaperTape = class()
PaperTape.color = color(221, 207, 10, 255)

function PaperTape:init(device)
   self.device = device
   self.holeSize = 6
   self.rowGap = 2
   self.sprocketHoleSize = 4
   self.holeGap = 2
   self.sprocketMargin = 1
   self.tapeMargin = 4
   self.sprocketHoleWidth = self.sprocketHoleSize+2*self.sprocketMargin
   self.tapeWidth = 8*(self.holeSize+self.holeGap)+self.sprocketHoleWidth+self.tapeMargin
   self.tapeLeft = self.device.left+self.device.width/2-self.tapeWidth/2
   self.tapeColor = PaperTape.color
end

function PaperTape:draw()  
   self.frameLength = math.min(21, string.len(self.device.buffer))
   local tapeHeight=self.frameLength*(self.holeSize+self.rowGap)
   noStroke()
   fill(self.tapeColor)
   local tapeBottom = self.device.bottom+self.device.height-30-tapeHeight
   rect(self.tapeLeft, tapeBottom, self.tapeWidth, tapeHeight)

   noStroke()
   ellipseMode(CORNER)

   for i=0,self.frameLength-1,1 do
       local bytex = self.tapeLeft+self.tapeMargin/2
       local bytey = tapeBottom+(i*(self.holeSize + self.rowGap))
       self:drawByte(bytex, bytey, self:getByte(i))
   end
end

function PaperTape:drawByte(x, y, byte)
   for i=0,4,1 do
       local bitx = x+(i*(self.holeSize+self.holeGap))
       local bit = Processor.mask(2^(7-i), byte)
       self:drawHole(bitx, y, bit)
   end
   fill(0,0,0,255)
   ellipse(x+(5*(self.holeSize+self.holeGap)+self.sprocketMargin-self.holeGap/2), y, self.sprocketHoleSize)
   for i=5,7,1 do
       local bitx = x+(i*(self.holeSize+self.holeGap)+self.sprocketHoleWidth)
       local bit = Processor.mask(2^(7-i), byte)
       self:drawHole(bitx, y, bit)
   end
end

function PaperTape:drawHole(x,y,bit)
   if (bit > 0) then
       fill(0, 0, 0, 255)  
   else
       fill(self.tapeColor)
   end
   ellipse(x, y, self.holeSize)
end

PaperTapeEnd = class(PaperTape)

function PaperTapeEnd:getByte(i)
   return self.device.buffer:byte(i+1+self.device.buffer:len()-self.frameLength)
end

PaperTapeStart = class(PaperTape)

function PaperTapeStart:getByte(i)
   return self.device.buffer:byte(self.frameLength-i)
end


--# Punch
Punch = class()

function Punch:init(x,y)
   self.left = x
   self.bottom = y
   self.height = 200
   self.width = 100
   self.buffer = ""
   self.drawCount = 4
   self.paperTape = PaperTapeEnd(self)
end

function Punch:draw()
   if self.drawCount > 0 then
       self:drawPunchBackground()
       self.paperTape:draw()
       self:drawStack()
       self.drawCount = self.drawCount - 1
   end
end

function Punch:drawPunchBackground()
   rectMode(CORNER)
   fill(155, 140, 97, 255)
   stroke(255)
   strokeWidth(2)
   rect(self.left, self.bottom, self.width, self.height)
   fill(0, 0, 0, 255)
   noStroke()
   rect(self.left+5, self.bottom+self.height-30, self.width-10, 10)
   textMode(CENTER)
   fill(0)
   font("Arial-BoldMT")
   fontSize(12)
   text("PUNCH", self.left + self.width/2, self.bottom+self.height-10)
end

function Punch:drawStack()
   local stackHeight = math.min(30, self.buffer:len()/25)
   noStroke()
   fill(221, 207, 10, 255)
   rect(self.left+5, self.bottom+1, self.width-10, stackHeight)
end

function Punch:punch(byte)
   byte = Processor.mask(255, byte)
   self.buffer = self.buffer..string.char(byte)
   self.drawCount = 1
   sound("Game Sounds One:Pistol")
end

function Punch:touched(t)
   if (t.state == BEGAN and t.x > self.left and t.x < self.left+self.width and
   t.y > self.bottom and t.y < self.bottom+self.height) then
       self:hit()
   end
end

function Punch:hit()
   if (self.buffer == nil or #self.buffer == 0) then
       sound("Game Sounds One:Wrong")
   else
       local shelf = findEmptyShelf()
       shelf.name = "Tape:"..os.clock()
       shelf.type = Shelf.TAPE
       shelf.io = ProjectIO("pt_")

       local ptText = self:toPt(self.buffer)
       shelf.io:write(shelf.name, ptText)
       self.buffer = ""
       self.drawCount = self.drawCount + 1
       Rack.drawCount = 1
   end
end

function Punch:toPt(buffer)
   local tapeImage = ""
   for i=1,buffer:len() do
       local byte = buffer:byte(i)
       local textByte = ""..string.format("%03d",Processor.asOctal(byte))
       tapeImage = tapeImage..textByte.."\n"
   end
   return tapeImage
end

--# Rack
Rack = class()
Rack.vGap = 1
Rack.hGap = 1
Rack.drawCount = 5
function Rack:init(x,y,width)
   self.x = x
   self.y = y
   self.shelves = {}
   local vShelves = math.floor((HEIGHT-y)/(Shelf.height + Rack.vGap))
   local hShelves = math.floor(width/(Shelf.width+Rack.hGap))
   self.width = hShelves*(Shelf.width+Rack.hGap)
   for i=1,vShelves do
       for j=1,hShelves do
           table.insert(self.shelves, 
               Shelf(x+(j-1)*(Shelf.width+Rack.hGap),y+((i-1)*Shelf.height+Rack.vGap)))
       end
   end

end

function Rack:draw()
   if (Rack.drawCount > 0) then
       Rack.drawCount = Rack.drawCount - 1
       for _,shelf in pairs(self.shelves) do
           shelf:draw()
       end
   end
end

function Rack:touched(touch)
   for _,shelf in pairs(self.shelves) do
       shelf:touched(touch)
   end
end

function Rack:findEmptyShelf() 
   for shelfNo, shelf in pairs(self.shelves) do
       if (shelf.type == Shelf.EMPTY) then
           return shelf
       end
   end
   return nil
end

--# RackControls
RackControls = class()

function RackControls:init(x, y, width)
   self.x = x
   self.y = y
   self.width = width
   self.prevButton = MomentaryButton(x+5, y, "Prev", prevRack)
   self.loadButton = MomentaryButton(x+(width/3)-self.prevButton.width, y, "Load", load)
   self.saveButton = MomentaryButton(x+(2*width/3), y, "Save", save)
   self.nextButton = MomentaryButton(x+width-self.prevButton.width, y, "Next", nextRack)    
end

function RackControls:draw()
   self.prevButton:draw()
   textMode(CORNER)
   font("Courier")
   fontSize(15)
   local label = "Rack:"..rackNumber
   local w,h = textSize(label)
   fill(0)
   stroke(0)
   local textx = self.x+(self.width/2)-w/2
   local texty = self.y+h/2+20-h/2
   rect(textx,texty,w,h)
   fill(255)
   text(label, textx, texty)
   self.nextButton:draw()
   self.loadButton:draw()
   self.saveButton:draw()
end

function RackControls:touched(touch)
   self.prevButton:touched(touch)
   self.nextButton:touched(touch)
   self.loadButton:touched(touch)
   self.saveButton:touched(touch)
end

--# Register
Register = class()
Register.spacing = 15

function Register:init(x,y, name)
   self.x = x
   self.y = y
   self.name = name
   self.digits = {}
   for i=1,4 do
       local n=i-1
       self.digits[i] = self:makeOctalDigit(x + (n*(OctalDigit:width() + Register.spacing)), self.y)
   end
end

function Register:draw()
   for i,digit in ipairs(self.digits) do
       digit:draw()
   end
   setupText()
   local w,h = textSize(self.name)
   text(self.name, 
       (self.x + Register:widthOfBits()) + Register.spacing, 
       self.y + Bit.height/2 - h/2)
end

function Register:touched(touch)
   for i,digit in ipairs(self.digits) do
       digit:touched(touch)
   end
end

function Register:value()
   return 
   self.digits[1]:value() * 512 + 
   self.digits[2]:value() * 64 + 
   self.digits[3]:value() * 8 + 
   self.digits[4]:value()
end

function Register:setValue(v)
   self.digits[1]:setValue(Processor.mask(7, Processor.shiftRight(v, 9)))
   self.digits[2]:setValue(Processor.mask(7, Processor.shiftRight(v, 6)))
   self.digits[3]:setValue(Processor.mask(7, Processor.shiftRight(v, 3)))
   self.digits[4]:setValue(Processor.mask(7, v))
end

function Register:widthOfBits()
   return 4*OctalDigit:width() + 3*Register.spacing
end

function Register:width()
   local w,h = textSize(self.name)
   return Register:widthOfBits() + w + Register.spacing
end

function Register:height()
   return OctalDigit:height()
end

function Register:test(t)
   self:setValue(Processor.octal(724))
   t:octalEquals(724, self:value(), "setValue")
end

function Register:makeOctalDigit(x,y)
   return OctalDigit(x,y)
end

SwitchRegister = class(Register)

function SwitchRegister:makeOctalDigit(x,y)
   return OctalSwitch(x,y)
end

--# Shelf
Shelf = class()

Shelf.width = 150
Shelf.height= 30
Shelf.CORE=1
Shelf.TAPE=2
Shelf.EMPTY=3
Shelf.iconWidth=20
Shelf.wasTouched = false

function Shelf:init(x,y)
   self.x = x
   self.y = y
   self.name=""
   self.prevName = ""
   self.nameChanged = false
   self.type = Shelf.EMPTY
   self.io = NullIO()
end

function Shelf:draw()
   fill(0)
   if (self == selectedShelf) then
       stroke(255,0,0)
   else
       stroke(255)
   end
   strokeWidth(2)
   rect(self.x,self.y,Shelf.width, Shelf.height)
   fill(255)
   font("Courier")
   fontSize(12)
   textMode(CENTER)
   text(self.name, self.x + Shelf.width/2 + Shelf.iconWidth/2, self.y + Shelf.height/2)

   if self.type == Shelf.CORE then
       self:drawCoreIcon()
   elseif self.type == Shelf.TAPE then
       self:drawTapeIcon()
   end
end

function Shelf:drawCoreIcon()
   fill(128);
   noStroke()
   rect(self.x+1, self.y+1, Shelf.iconWidth-1, Shelf.height-2)
   stroke(255, 255, 255, 255)
   strokeWidth(4)
   noFill()
   ellipseMode(CENTER)
   ellipse(self.x + Shelf.iconWidth/2, self.y + Shelf.height/2, Shelf.iconWidth-2)
end

function Shelf:drawTapeIcon()
   local bits = math.pi
   fill(PaperTape.color)
   noStroke()
   rect(self.x+1, self.y+1, Shelf.iconWidth-1, Shelf.height-2)    

   fill(0)
   noStroke()
   ellipseMode(CORNER)

   local holes = 5
   local gap = 1
   local margin = 2
   local holeWidth = (Shelf.iconWidth-(2*margin)-((holes-1)*gap))/holes
   local rowy = self.y+margin
   while rowy < self.y + Shelf.height - margin do
       for i=1,holes do
           bits = bits*10
           bit = math.floor(bits)
           bits = bits-bit
           if bit > 5 then
               ellipse(self.x+margin+(i-1)*(holeWidth+gap), rowy, holeWidth)
           end
       end
       rowy = rowy + holeWidth + gap
   end

end

function Shelf:touched(touch)
   if (touch.x > self.x and touch.x < self.x+Shelf.width and 
       touch.y > self.y and touch.y < self.y+Shelf.height and 
       touch.state == BEGAN) then
       Shelf.wasTouched = true;
       Rack.drawCount = 1
       if selectedShelf ~= nil then
           selectedShelf:unselect()
       end
       if (selectedShelf == self) then
           selectedShelf = nil
       else
           selectedShelf = self
           self:select()
       end
   end
end

function Shelf:key(key)
   self.nameChanged = true
   if key == BACKSPACE then
       self.name = self.name:sub(1,-2)
   elseif key == "¥" then -- OPT-Y
       self.name = ""
   else
       self.name = self.name..key
   end
   Rack.drawCount = 1
end

function Shelf:select()
   self.prevName = self.name
end

function Shelf:unselect()
   Rack.drawCount = 1
   if self.nameChanged then
       if self.name=="" or self.name==nil then
           if (self.io:write(self.prevName, nil) == false) then
               self.name = self.prevName
               sound("Game Sounds One:Wrong")
           else
               self.type = Shelf.EMPTY
               self.io = NullIO()
           end
       else
           if self.io:read(self.name) ~= nil then
               self.name = self.prevName
               sound("Game Sounds One:Wrong")
           else
               if (self.io:write(self.name, self.io:read(self.prevName)) == false) then
                   self.name = self.prevName
               else
                   self.io:write(self.prevName, nil)
               end
           end
       end
   end
   self.nameChanged = false;
end

--# StatsPanel
StatsPanel = class()
StatsPanel.width=130

function StatsPanel:init(x,y)
   self.x = x
   self.y = y
   self.speed = MomentaryButton(x+10,y,"Speed", cycleSpeed)
end

function StatsPanel:draw()
   local msg=string.format("%4d fps\n%4d ips\n%4d ipf",framesPerSecond ,instructionsPerSecond, cyclesPerFrame)
   font("Courier")
   fontSize(15)
   local w,h=textSize(msg)
   fill(0)
   stroke(255)
   local x = self.speed.width+20+self.x
   rect(x,self.y,w+10, h+10)
   fill(255)
   text(msg, x+5, self.y+5)
   self.speed:draw()
end

function StatsPanel:touched(touch)
   self.speed:touched(touch)
end

speedSelections = {1,11,101,401}
speedSelection = 4
cyclesPerFrame=401

function cycleSpeed()
   speedSelection=speedSelection+1
   if speedSelection>#speedSelections then
       speedSelection = 1
   end
   cyclesPerFrame=speedSelections[speedSelection]
end

--# TapeReader
TapeReader = class()

function TapeReader:init(x,y)
   self.left = x
   self.bottom = y    
   self.height = 200
   self.width = 100
   self.buffer = ""
   self.paperTape = PaperTapeStart(self)
   self.drawCount = 5
end

function TapeReader:draw()
   if self.drawCount > 0 then
       self:drawReaderBackground()
       self.paperTape:draw()
       self:drawStack()
       self.paperTape:drawByte(self.paperTape.tapeLeft+self.paperTape.tapeMargin/2,self.bottom+self.height-28, controlPanel.processor.device[1].buffer)
       self.drawCount = self.drawCount - 1
   end
end

function TapeReader:drawReaderBackground()
   rectMode(CORNER)
   stroke(255, 255, 255, 255)
   strokeWidth(2)
   fill(121, 119, 133, 255)
   rect(self.left, self.bottom, self.width, self.height)
   fill(self.paperTape.tapeColor)
   stroke(0)
   rect(self.left+5, self.bottom+self.height-30, self.width-10, 10)
   textMode(CENTER)
   font("Arial-BoldMT")
   fill(0)
   fontSize(12)
   text("READER", self.left + self.width/2, self.bottom+self.height-10)
end

function TapeReader:drawStack()
   local stackHeight = math.min(30, self.buffer:len()/25)
   noStroke()
   fill(221, 207, 10, 255)
   rect(self.left+5, self.bottom+1, self.width-10, stackHeight)
end

function TapeReader:read()
   self.drawCount = self.drawCount+1
   c = self.buffer:byte(1)
   self.buffer = self.buffer:sub(2,-1)
   sound("Game Sounds One:Throw")
   return c
end

function TapeReader:touched(t)
   if (t.state == BEGAN and t.x > self.left and 
   t.x < self.left+self.width and
   t.y > self.bottom and t.y < self.bottom+self.height) then
       self:hit()
   end
end

function TapeReader:hit()
   if selectedShelf == nil then
       self.buffer = ""
   else
       local ptText = selectedShelf.io:read(selectedShelf.name)
       self.buffer = self:ptToBinary(ptText)
   end
   self.drawCount = self.drawCount + 1
end

function TapeReader:ptToBinary(s)
   local len = s:len()
   local buffer = ""
   for pos=1,len,4 do
       local char = Processor.mask(7, s:byte(pos))*64
       + Processor.mask(7, s:byte(pos+1))*8
       + Processor.mask(7, s:byte(pos+2))
       buffer = buffer..string.char(char)
   end
   return buffer
end

--# Test
Test = class()

function Test:init() 
   self.tests = 0
   self.errors = 0
   print("Test begins.")
end

function Test:assertEquals(a,b,s)
   if (a == b) then
       self:pass()
   else
       self:fail(string.format("expected %s got %s -- %s.", a, b, s))
   end
end

function Test:assertTrue(p,s)
   if p then
       self:pass()
   else
       self:fail("expected true, was false -- "..s..".")
   end
end

function Test:assertFalse(p, s)
   if p then
       self:fail("expected false, was true -- "..s..".")
   else
       self:pass()
   end
end

function Test:pass() 
   self.tests = self.tests + 1
   io.write(".")
end

function Test:fail(s)
   self.tests = self.tests + 1
   self.errors = self.errors + 1
   io.write("X")
   print("\n",s)
end

function Test:report()
   print(string.format("%d failures in %d tests.", self.errors, self.tests))
end

--# Processor
Processor = class()
Processor.I = 2^8
Processor.C = 2^7

function Processor:init(switchRegister, run)
   self.run = run
   self.sr = switchRegister
   self.ac = 0
   self.pc = 0
   self.ma = 0
   self.mb = 0
   self.link = 0
   self.memory = {}
   self.memory[0] = 0
   for i=1,4095 do 
       self.memory[i] = 0
   end
   self.device = {}
   self.device[1] = PaperTapeReader(self)
   self.device[2] = TapePunch(self)
   self.device[3] = Keyboard(self)
   self.device[4] = Teleprinter(self)
   self.ion = false
   self.ionPending = 0
end

function Processor:store(ma, mb)
   self.memory[ma]=mb%4096
end

function Processor:get(ma)
   return self.memory[ma]
end

function Processor.mask(a,b)
   local result = 0
   for i=1,12 do
       result = result / 2
       if a%2 ~= 0 and b%2 ~= 0 then
           result = result + 2048
       end
       a = math.floor(a/2)
       b = math.floor(b/2)
   end
   return result
end

function Processor.ior(a,b)
   local result = 0
   for i=1,12 do
       result = result / 2
       if a%2 ~= 0 or b%2 ~= 0 then
           result = result + 2048
       end
       a = math.floor(a/2)
       b = math.floor(b/2)
   end
   return result
end

function Processor.shiftRight(value, bits)
   local divisor = 2^bits
   return math.floor(value/divisor)
end

function Processor.shiftLeft(value, bits)
   return (value*2^bits) % 4096
end

function Processor:step()
   if (self.ionPending > 0) then
       self.ionPending = self.ionPending - 1
       if self.ionPending == 0 then
           self.ion = true
       end
   end

   if self.ion and (self.device[3].ready == 1 or self.device[4].ready == 1) then
       self.memory[0] = self.pc
       self.pc = 1
       self.ion = false
   end
   self:executeInstructionAtPc()
end

function Processor:executeInstructionAtPc() 
   local instruction = self.memory[self.pc] 

   local opCode = Processor.shiftRight(instruction, 9)
   if (opCode <=5) then
       self:mriInstruction(opCode, instruction)
   elseif (opCode == 7) then
       self:operateMicroInstruction(instruction)
   elseif (opCode == 6) then
       self:iot(instruction)
   end

   self.pc = (self.pc+1)%4096
end

function Processor:mriInstruction(opCode, instruction)
   self.ma = self:getEffectiveAddress(instruction)
   if (opCode == 0) then -- AND
       self.mb = self.memory[self.ma]
       self.ac = Processor.mask(self.ac, self.mb)
   elseif (opCode == 1) then -- TAD
       self.mb = self.memory[self.ma]
       self:addToAcLink(self.mb)
   elseif (opCode == 2) then -- ISZ
       self.mb = (self.memory[self.ma] + 1)%4096
       self:store(self.ma, self.mb)
       if (self.mb == 0) then
           self.pc = self.pc + 1
       end
   elseif (opCode == 4) then -- JMS
       self.mb = self.pc + 1
       self:store(self.ma, self.mb)
       self.pc = self.ma -- it will be incremented by step
   elseif (opCode == 3) then -- DCA
       self.mb = self.ac
       self:store(self.ma, self.mb)
       self.ac = 0
   elseif (opCode == 5) then -- JMP
       self.pc = self.ma-1
   end
end

function Processor:addToAcLink(m)
   self.ac = (self.ac + m)
   if (self.ac > 4095) then
       self.ac = self.ac % 4096
       self.link = (self.link + 1)%2
   end
end

function Processor:operateMicroInstruction(instruction)
   if (Processor.mask(instruction, Processor.octal(0400)) == 0) then
       self:group1MicroInstructions(instruction)
   elseif (Processor.mask(instruction, Processor.octal(401)) == Processor.octal(0400)) then
       self:group2Skips(instruction)
   end
end

function Processor:group1MicroInstructions(instruction)
   --seq1
   if (Processor.mask(instruction, 2^7) > 0) then -- CLA
       self.ac = 0
   end

   if (Processor.mask(instruction, 2^6) > 0) then -- CLL
       self.link = 0
   end

   --seq2
   if (Processor.mask(instruction, 2^5) > 0) then -- CMA
       self.ac = (4096 - self.ac)-1
   end

   if (Processor.mask(instruction, 2^4) > 0) then -- CLL
       self.link = (self.link > 0) and 0 or 1
   end

   --seq3

   if (Processor.mask(instruction, 1) > 0) then  -- IAC
       self:addToAcLink(1)
   end

   --seq4

   if (Processor.mask(instruction, 2^3) > 0) then -- RAR
       self:rar()
       if (Processor.mask(instruction, 2) > 0) then -- RTR
           self:rar()
       end
   end

   if (Processor.mask(instruction, 2^2) > 0) then -- RAL
       self:ral()
       if (Processor.mask(instruction, 2) > 0) then -- RTL
           self:ral()
       end
   end
end

function Processor:group2Skips(instruction) 
   local sma = (Processor.mask(64, instruction) > 0) and (Processor.mask(2048, self.ac) > 0)
   local sza = (Processor.mask(32, instruction) > 0) and self.ac == 0
   local snl = (Processor.mask(16, instruction) > 0) and self.link > 0
   local skip = sma or sza or snl
   if (Processor.mask(8, instruction) > 0) then
       skip = not skip
   end
   self.pc = skip and self.pc + 1 or self.pc

   if (Processor.mask(128, instruction) > 0) then
       self.ac = 0
   end

   if (Processor.mask(4, instruction) > 0) then -- OSR
       local cSR = (4096-self.sr:value()) - 1
       local cAc = (4096-self.ac)-1
       local cOsr = Processor.mask(cAc, cSR)
       self.ac = (4096 - cOsr) - 1
   end

   if (Processor.mask(2, instruction) > 0) then -- HLT
       self.run.bit:setValue(0);
   end
end

function Processor:rar()
   local l = self.link
   self.link = Processor.mask(self.ac, 1)
   self.ac = Processor.shiftRight(self.ac, 1)
   self.ac = self.ac + 2048 * l
end

function Processor:ral()
   local l = self.link
   self.link = (self.ac >= 2048) and 1 or 0
   self.ac = Processor.shiftLeft(self.ac, 1) + l
end

function Processor:getEffectiveAddress(instruction)
   local page = 0
   if (Processor.isCurrentPage(instruction)) then 
       page = Processor.getPage(self.pc)
   end
   local addr = (page + Processor.mask(instruction, 127))%4096
   if (Processor.isIndirect(instruction)) then
       if (addr >= 8 and addr <= 15) then -- autoindex
           self.memory[addr] = self.memory[addr] + 1
       end
       addr = self.memory[addr]
   end
   return addr%4096
end

function Processor.getPage(pc)
   return Processor.mask(pc, 4095-127)
end

function Processor.getOpCode(instruction)
   return Processor.shiftRight(instruction, 9)
end

function Processor.isIndirect(instruction)
   return Processor.shiftRight(instruction, 8)%2>0
end

function Processor.isCurrentPage(instruction)
   return Processor.shiftRight(instruction,7)%2>0
end

function Processor:iot(instruction)
   local device = Processor.mask(Processor.octal(770), instruction)
   device = Processor.shiftRight(device, 3)
   local command = Processor.mask(7, instruction)
   if (device == 0) then
       self:handleInterruptInstruction(command)
   else
       local dev = self.device[device]
       if (dev ~= nil) then
           self.device[device]:io(command)
       end
   end
end

function Processor:handleInterruptInstruction(command)
   if (command == 1) then
       self.ionPending = 30
   elseif (command == 2) then
       self.ion = false
   end
end

function Processor.octal(o)
   local d0 = o%10
   local d1 = math.floor(o/10)%10
   local d2 = math.floor(o/100)%10
   local d3 = math.floor(o/1000)%10
   return d3*512+d2*64+d1*8+d0
end

function Processor.asOctal(o)
   local d0 = o%8
   local d1 = math.floor(o/8)%8
   local d2 = math.floor(o/64)%8
   local d3 = math.floor(o/512)%8
   return d3*1000+d2*100+d1*10+d0
end

--# Ascii

function setAscii(code, char)
   code = Processor.mask(Processor.octal(177), Processor.octal(code))
   ASCII[code] = char
   ASCII[code + Processor.octal(200)] = char
end

function initAscii()
   ASCII = {}
   for i=1,256 do
       ASCII[i]=""
   end
   setAscii(301, "A")
   setAscii(302, "B")
   setAscii(303, "C")
   setAscii(304, "D")
   setAscii(305, "E")
   setAscii(306, "F")
   setAscii(307, "G")
   setAscii(310, "H")
   setAscii(311, "I")
   setAscii(312, "J")
   setAscii(313, "K")
   setAscii(314, "L")
   setAscii(315, "M")
   setAscii(316, "N")
   setAscii(317, "O")
   setAscii(320, "P")
   setAscii(321, "Q")
   setAscii(322, "R")
   setAscii(323, "S")
   setAscii(324, "T")
   setAscii(325, "U")
   setAscii(326, "V")
   setAscii(327, "W")
   setAscii(330, "X")
   setAscii(331, "Y")
   setAscii(332, "Z")

   setAscii(260, "0")
   setAscii(261, "1")
   setAscii(262, "2")
   setAscii(263, "3")
   setAscii(264, "4")
   setAscii(265, "5")
   setAscii(266, "6")
   setAscii(267, "7")
   setAscii(270, "8")
   setAscii(271, "9")

   setAscii(240, " ")
   setAscii(241, "!")
   setAscii(242, '"')
   setAscii(243, "#")
   setAscii(244, "$")
   setAscii(245, "%")
   setAscii(246, "&")
   setAscii(247, "'")
   setAscii(250, "(")
   setAscii(251, ")")
   setAscii(252, "*")
   setAscii(253, "+")
   setAscii(254, ",")
   setAscii(255, "-")
   setAscii(256, ".")
   setAscii(257, "/")

   setAscii(272, ":")
   setAscii(273, ";")
   setAscii(274, "<")
   setAscii(275, "=")
   setAscii(276, ">")
   setAscii(277, "?")
   setAscii(300, "@")

   setAscii(333, "[")
   setAscii(334, "\\")
   setAscii(335, "]")
   setAscii(336, "^")
   setAscii(337, "~")

   setAscii(215, "\r")
   setAscii(212, "\n")
   setAscii(211, " ")

   setAscii(0, "")
end



--# Teletype
Teletype = class()

function Teletype:init(x,y,w,h)
   self.x = x
   self.y = y
   self.height = h
   self.width = w
   self:clear()
   self.margin = 10
   self.charMask = Processor.octal(177)
   self.LF = Processor.octal(12)
   self.CR = Processor.octal(15)
   self.BEL = Processor.octal(07)
   self.FF = Processor.octal(14)
   self.scrollBottom = 1
   self.scrollStart = 0
   self.scrolling = false
end

function Teletype:clear()
   self.charCount = 0
   self.chars = {}
   self.charPos = 0
   self.line = 1
   self.lines = {}
   self.lines[1] = 1
   self.lineStartPos = {}
   self.lineStartPos[1] = 0
   self.lastLineDrawn = 0
   self.lastCharDrawn = 0
   self.drawCount = 5
end

function Teletype:draw()
   if self.drawCount > 0 then
       self:drawPaper()
   end
   self.drawCount = math.max(0, self.drawCount-1)

end

function Teletype:drawPaper()
   local justDrawOneChar = (self.line == self.lastLineDrawn) and (not self.scrolling)
   if (not justDrawOneChar) or self.drawCount > 1 then
       fill(255, 227, 0, 255)
       rect(self.x, self.y, self.width, self.height)
   end

   self:setupFont()

   self.screeny = 0
   self.screenx = 0
   if (self.scrolling) then
       local oldestLineToDraw = math.max(self.scrollBottom-30, 1)
       for lineToDraw = self.scrollBottom, oldestLineToDraw, -1 do
           self:drawLine(lineToDraw, false)
       end
   else
       local oldestLineToDraw = math.max(self.line-30,1)
       if (justDrawOneChar) then
           oldestLineToDraw = self.line
       end
       for lineToDraw = self.line, oldestLineToDraw, -1 do
           self:drawLine(lineToDraw, justDrawOneChar)
       end
       self.lastLineDrawn = self.line
   end
end

function Teletype:setupFont()
   font("Courier")
   fontSize(10)
   textAlign(LEFT)
   textMode(CORNER)
   fill(0,0,0,200)
   self.cw, self.ch = textSize("A")    
end

function Teletype:drawLine(lineToDraw, justDrawOneChar)
   local lastCharToDraw = self.charCount
   if (lineToDraw < self.line) then
       lastCharToDraw = self.lines[lineToDraw+1]-1
   end
   self.screenx = self.lineStartPos[lineToDraw]
   for charIndex = self.lines[lineToDraw],lastCharToDraw do
       self:drawChar(charIndex, justDrawOneChar)
   end
   self.screeny = self.screeny+1
end

function Teletype:drawChar(charIndex, justDrawOneChar)
   local char = self.chars[charIndex]
   if (char == self.CR) then
       self.screenx = 0
   elseif (char == self.LF) or (char == self.BEL) or (char == self.FF) or (char == 0) then
       -- nothing to do.
   else
       if (not justDrawOneChar) or (charIndex > self.lastCharDrawn) then
           self.lastCharDrawn = charIndex
           local charx = self.screenx*self.cw+self.x+self.margin
           local chary = self.screeny*self.ch+self.y+self.margin
           text(ASCII[char], charx, chary)
       end
       self.screenx = math.min(72,self.screenx+1)
   end
end

function Teletype:touched(touch) 
   if touch.x > self.x and touch.x < (self.x + self.width) and
   touch.y > self.y and touch.y < (self.y + self.height) then
       self:hit(touch)
   end
end

function Teletype:hit(touch)
   if touch.state == BEGAN then
       if self.scrolling == false then
           self.scrollStart = self.line
           self.scrolling = true;
       else
           self.scrollStart = self.scrollBottom
       end
       self.scrolly = touch.y

   elseif touch.state == ENDED then
       if self.scrollBottom==self.line then
           self.scrolling = false
       end
   else -- MOVING
       local delta = touch.y - self.scrolly
       if delta ~= 0 then
           self.drawCount = 1
       end
       self.scrollBottom = self.scrollStart + math.floor(delta/10)
       self.scrollBottom = math.min(self.scrollBottom, self.line)
       self.scrollBottom = math.max(self.scrollBottom, 1)
   end
end

function Teletype:type(c)
   if not self.scrolling then
       self.drawCount = 1
   end
   c = Processor.mask(self.charMask, c)    
   self.charCount = self.charCount + 1
   self.chars[self.charCount] = c

   if (c == self.LF) then
       self:startNextLine()
       sound("Game Sounds One:Kick")
   elseif (c == self.CR) then
       self.charPos = 0
       sound("Game Sounds One:Assembly 6")
   elseif (c == self.BEL) then
       sound("Game Sounds One:Bell 2")
   elseif (c == self.FF) then
       self:startNextLine()
       self:startNextLine()
       self.charPos = 0
       sound("Game Sounds One:Assembly 5")
   elseif(c == 0) then
       -- Nothing to do.
   else
       self.charPos = self.charPos + 1
       sound("Game Sounds One:Punch 2")
       if self.charPos > 72 then
           self.charPos = 72
           sound("Game Sounds One:Bell 2")
       end
   end
end

function Teletype:startNextLine()
   self.line = self.line + 1
   self.lines[self.line]=self.charCount
   self.lineStartPos[self.line] = self.charPos
end

--# ProcessorTest
function Processor:test(t)
   t:assertEquals(0, Processor.shiftRight(0,0), "shiftRight(0,0)")
   t:assertEquals(1, Processor.shiftRight(2,1), "shiftRight(2,1)")
   t:assertEquals(7, Processor.shiftRight(7*512, 9), "shiftRight(7*512, 9)")
   t:assertEquals(0, Processor.shiftRight(4095, 12), "shiftRight(4095,12)")

   t:assertEquals(5*512, Processor.shiftLeft(5,9), "ShiftLeft(5,9)")

   t:assertEquals(2, Processor.mask(7,2), "mask(7,2)")
   t:assertEquals(5, Processor.mask(4093, 7), "mask(4093,7)")
   t:assertEquals(128, Processor.mask(4095, 128), "mask(4095,128)")
   t:assertEquals(256, Processor.mask(4095, 256), "mask(4095,256)")

   t:octalEquals(7777, Processor.ior(Processor.octal(5555), Processor.octal(2222)), "ior1")
   t:octalEquals(7777, Processor.ior(Processor.octal(7700), Processor.octal(777)), "ior2")

   t:assertEquals(256, Processor.getPage(257), "getPage(257)")
   t:assertEquals(512+256, Processor.getPage(512+256+127), "getPage(big)")

   t:assertEquals(5, Processor.getOpCode(5*512+127), "getOpCode1")

   t:assertEquals(true, Processor.isIndirect(256+127), "isIndirect1")
   t:assertEquals(false, Processor.isIndirect(127), "isIndirect2")

   t:assertEquals(true, Processor.isCurrentPage(4095), "isCurrentPage1")
   t:assertEquals(false, Processor.isCurrentPage(4095-128), "isCurrentPage2")

   t:assertEquals(4095, Processor.octal(7777), "octal")

   self.pc=Processor.octal(5000)
   t:octalEquals(0, self:getEffectiveAddress(0), "getEffectiveAddress1")
   t:octalEquals(5000, self:getEffectiveAddress(Processor.C), "getEffectiveAddress2")
   self:setMemory(5001, 3000)
   t:octalEquals(3000, self:getEffectiveAddress(Processor.C + Processor.I+1), "getEffectiveAddress3")

   -- Autoindexing

   for addr = 8,15 do
       self.memory[addr] = Processor.octal(1000)
       t:octalEquals(1001, self:getEffectiveAddress(Processor.I + addr), 
           "autoindex1-"..Processor.asOctal(addr))
       t:octalEquals(1001, self.memory[addr], "autoindex2-"..Processor.asOctal(addr))
   end

   self.memory[7] = Processor.octal(1000)
   t:octalEquals(1000, self:getEffectiveAddress(Processor.I + 7), "autoIndex3")

   self.memory[16] = Processor.octal(1000)
   t:octalEquals(1000, self:getEffectiveAddress(Processor.I + 16), "autoIndex3")

   -- Instructions.

   self:setMemory(1001, 707)
   self:setAc(5423)
   self:testExecute(0201) -- AND C 1
   t:octalEquals(403, self.ac, "AND")

   self:setMemory(1001, 25)
   self:setAc(752)
   self:testExecute(1201) -- TAD C 1
   t:octalEquals(777, self.ac, "TAD 1")

   self:setMemory(1002, 7777)
   self.ac = 1
   self:testExecute(1202) -- TAD C 2
   t:octalEquals(0, self.ac, "TAD 2")
   t:octalEquals(1, self.link, "TAD 3")

   self.ac = 1
   self:testExecute(1202) -- TAD C 2
   t:octalEquals(0, self.link, "TAD 4")

   self:setAc(77)
   self:testExecute(3201) -- DCA C 1
   t:octalEquals(0, self.ac, "DCA1")
   t:octalEquals(77, self:getMemory(1001))

   self:testExecute(5244) -- JMP C 44
   t:octalEquals(1044, self.pc, "JMP1")

   self:setMemory(1001, 42)
   self:testExecute(2201) -- ISZ C 01
   t:octalEquals(43, self:getMemory(1001), "ISZ1")
   t:octalEquals(1011, self.pc, "ISZ2")

   self:setMemory(1001, 7777) -- -1
   self:testExecute(2201) -- ISZ C 01
   t:octalEquals(0, self:getMemory(1001), "ISZ3")
   t:octalEquals(1012, self.pc, "ISZ4")    

   self:testExecute(4220) -- JMS C 20
   t:octalEquals(1021, self.pc, "JMS1")
   t:octalEquals(1011, self:getMemory(1020), "JMS2")

   self:setAc(7777)
   self:testExecute(7200) -- CLA
   t:octalEquals(0, self.ac, "CLA")

   self.link = 1
   self:testExecute(7100) -- CLL
   t:octalEquals(0, self.link, "cll")

   self:setAc(5555)
   self:testExecute(7040) -- CMA
   t:octalEquals(2222, self.ac, "CMA")

   self.link = 1
   self:testExecute(7020) -- CML
   t:octalEquals(0, self.link, "CML-1")

   self.link = 0
   self:testExecute(7020) -- CML
   t:octalEquals(1, self.link, "CML-2")

   self:setAc(0)
   self:testExecute(7001) -- IAC
   t:octalEquals(0001, self.ac, "IAC1")

   self.link = 0
   self:setAc(7777)
   self:testExecute(7001) -- IAC
   t:octalEquals(0000, self.ac, "IAC2")
   t:octalEquals(1, self.link, "IAC3")

   self.link = 1
   self:setAc(5252)
   self:testExecute(7010) -- RAR
   t:octalEquals(6525, self.ac, "RAR1")
   t:octalEquals(0, self.link, "RAR2")

   self.link = 0
   self:setAc(0001)
   self:testExecute(7010) -- RAR
   t:octalEquals(0000, self.ac, "RAR3")
   t:octalEquals(1, self.link, "RAR4")

   self.link = 1
   self:setAc(0000)
   self:testExecute(7004) -- RAL
   t:octalEquals(0001, self.ac, "RAL1")
   t:octalEquals(0, self.link, "RAL2")

   self.link = 0;
   self:setAc(5252)
   self:testExecute(7004) -- RAL
   t:octalEquals(2524, self.ac, "RAL3")
   t:octalEquals(1, self.link, "RAL4")

   self.link = 1
   self:setAc(2525)
   self:testExecute(7012) -- RTR
   t:octalEquals(0, self.link, "RTR1")
   t:octalEquals(6525, self.ac, "RTR2")

   self.link = 1
   self:setAc(2525)
   self:testExecute(7006) -- RTL
   t:octalEquals(1, self.link, "RTL1")
   t:octalEquals(2526, self.ac, "RTL2")

   self:testExecute(7240) -- CLA CMA
   t:octalEquals(7777, self.ac, "CLA CMA")

   self:setAc(4000) -- -2048
   self:testExecute(7500) -- SMA
   self:assertSkip(t, "SMA1")

   self:setAc(3777) -- 2047
   self:testExecute(7500) -- SMA
   self:assertNoSkip(t, "SMA2")

   self:setAc(0000)
   self:testExecute(7440) -- SZA
   self:assertSkip(t, "SZA1")

   self:setAc(1)
   self:testExecute(7440) -- SZA
   self:assertNoSkip(t, "SZA2")

   self.link = 1
   self:testExecute(7420) -- SNL
   self:assertSkip(t, "SNL1")

   self.link = 0
   self:testExecute(7420) -- SNL
   self:assertNoSkip(t, "SNL2")

   self:setAc(1)
   self.link = 0
   self:testExecute(7570) -- SPA SNA SZL
   self:assertSkip(t, "SPA-SNA-SZL 1")

   self.link = 1
   self:testExecute(7570) -- SPA SNA SZL
   self:assertNoSkip(t, "SPA SNA SZL 2")

   self.ac = 99
   self:testExecute(7600) -- CLA
   t:octalEquals(0, self.ac, "CLA2 1")

   self.sr:setValue(Processor.octal(1234))
   self:setAc(5)
   self:testExecute(7404)  -- OSR
   t:octalEquals(1235, self.ac, "OSR1")

   self.run.bit:setValue(1)
   self:testExecute(7402) -- HLT
   t:octalEquals(0, self.run.bit.value, "HLT1")

   -- Interrupts

   self.device[3].ready = 0
   self.device[4].ready = 0
   self.ion = false
   self:testExecute(6001) -- ION
   t:assertTrue(self.ionPending > 0, "IONPending1")
   self.ionPending=1
   t:assertFalse(self.ion, "ION1")
   self.ac = 1
   self:testExecute(7600) -- CLA
   t:assertTrue(self.ac == 0, "CLA EXECUTED")
   t:octalEquals(1011, self.pc, "ION no int")
   t:assertEquals(0, self.ionPending, "IONPending2")
   t:assertTrue(self.ion, "ION2")

   self.ion = true
   self:testExecute(6002) -- IOF
   t:assertFalse(self.ion, "IOF1")

   self.device[3].ready = 1 -- keyboard ready
   self.memory[1] = Processor.octal(7000) -- NOP
   self:testExecute(6001) -- ION
   self.ionPending=2
   self:testExecute(7000) -- NOP
   t:assertEquals(1, self.ionPending, "Interrupt 0")
   self:setAc(1)
   self:testExecute(7600) -- CLA
   t:assertFalse(self.ion, "Interrupt 0.01")
   t:assertEquals(0, self.ionPending, "Interrupt 0.1")
   t:assertEquals(1, self.ac, "Interrupt 1")
   t:octalEquals(0002, self.pc, "Interrupt 2")
   t:octalEquals(1010, self:getMemory(0000), "Interrupt 3")
   t:assertFalse(self.ion, "Interrupt 4")

   --- Keyboard ---
   self:setAc(7777)
   self.device[3].ready = 1
   self:testExecute(6032) -- KCC
   t:assertEquals(0, self.ac, "KCC1")
   t:assertEquals(0, self.device[3].ready, "KCC2")

   self:setAc(7700)
   self.device[3].buffer = 2
   self:testExecute(6034) -- KRS
   t:octalEquals(7702, self.ac, "KRS1")
end

function Processor:assertSkip(t, s) 
   t:octalEquals(1012, self.pc, s)
end

function Processor:assertNoSkip(t, s)
   t:octalEquals(1011, self.pc, s)
end

function Test:octalEquals(a, b, s)
   a = Processor.octal(a)
   if (a == b) then
       self:pass()
   else
       self:fail(string.format("expected %s got %s -- %s.", 
       Processor.asOctal(a),Processor.asOctal(b),s))
   end
end

function Processor:getMemory(addr)
   return self.memory[Processor.octal(addr)]
end

function Processor:setMemory(addr, value)
   self.memory[Processor.octal(addr)] = Processor.octal(value)
end

function Processor:testExecute(instruction)
   self.pc = Processor.octal(1010)
   self.memory[self.pc] = Processor.octal(instruction)
   self:step()
end

function Processor:setAc(value)
   self.ac = Processor.octal(value)
end

function Processor:setMem(address, value)
   self.memory[Processor.octal(address)] = Processor.octal(value)
end

--# TextPanel
TextPanel = class()

function TextPanel:init(x,y)
   self.left = x
   self.bottom = y
   self.drawCount = 5
end

function TextPanel:draw()
   if (self.drawCount > 0) then
       local textMargin = 6
       local txt = self:getText()
       font("Courier")
       fontSize(14)
       local tw,th = textSize(txt)
       noFill()
       stroke(255, 255, 255, 255)
       strokeWidth(2)
       rect(self.left, self.bottom, tw+textMargin*2, th+textMargin*2)
       fill(255)
       text(txt, self.left+textMargin, self.bottom+textMargin)
       self.drawCount = self.drawCount-1
   end
end

function TextPanel:touched(touch)
   -- Codea does not automatically call this method
end

RimPanel = class(TextPanel)

function RimPanel:getText()
   return
   "RIM LOADER\n"..
   "7756  7200\n"..
   "7757  6011\n"..
   "7760  5357\n"..
   "7761  6016\n"..
   "7762  7106\n"..
   "7763  7006\n"..
   "7764  7510\n"..
   "7765  5357\n"..
   "7766  7006\n"..
   "7767  6011\n"..
   "7770  5367\n"..
   "7771  6016\n"..
   "7772  7420\n"..
   "7773  3776\n"..
   "7774  3376\n"..
   "7775  5356"
end
