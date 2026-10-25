import AppKit
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus();NSColor.clear.setFill();NSRect(x:0,y:0,width:1024,height:1024).fill()
let tile=NSBezierPath(roundedRect:NSRect(x:100,y:100,width:824,height:824),xRadius:180,yRadius:180)
NSGradient(starting:NSColor(srgbRed:0.17,green:0.58,blue:0.52,alpha:1),ending:NSColor(srgbRed:0.09,green:0.35,blue:0.33,alpha:1))!.draw(in:tile,angle:-90)
NSGraphicsContext.saveGraphicsState();let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.25);shadow.shadowBlurRadius=24;shadow.shadowOffset=NSSize(width:0,height:-15);shadow.set()
let paper=NSBezierPath(roundedRect:NSRect(x:283,y:231,width:458,height:562),xRadius:43,yRadius:43)
NSColor(srgbRed:0.94,green:0.91,blue:0.83,alpha:1).setFill();paper.fill();NSGraphicsContext.restoreGraphicsState()
NSColor(srgbRed:0.13,green:0.25,blue:0.23,alpha:1).setStroke()
let n=NSBezierPath();n.move(to:NSPoint(x:367,y:588));n.line(to:NSPoint(x:367,y:715));n.line(to:NSPoint(x:468,y:588));n.line(to:NSPoint(x:468,y:715));n.lineWidth=21;n.lineCapStyle = .round;n.lineJoinStyle = .round;n.stroke()
for (y,w) in [(512.0,290.0),(449.0,290.0),(386.0,220.0)]{let p=NSBezierPath();p.move(to:NSPoint(x:367,y:y));p.line(to:NSPoint(x:367+w,y:y));p.lineWidth=13;p.lineCapStyle = .round;NSColor(srgbRed:0.26,green:0.35,blue:0.31,alpha:0.7).setStroke();p.stroke()}
image.unlockFocus();let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!;try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
