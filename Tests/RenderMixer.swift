import SwiftUI
import AppKit
import CoreText

@main struct RenderMixer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let fontURL=URL(fileURLWithPath:CommandLine.arguments[2])
        CTFontManagerRegisterFontsForURL(fontURL as CFURL,.process,nil)
        let gains: [UInt16]=[8192,4096,2057,0,0,0,0,0]
        let inputs: [UInt16] = CommandLine.arguments.contains("--eight") ? [0x80,0x81,0x600,0x601,0x82,0x83,0x602,0x603] : [0x80,0x81,0x600,0x601,0,0,0,0]
        let frame=MixerFrame(bus:0,gains:gains,sources:inputs,destinations:1<<8)
        var draft=MixerDraft(); draft.load(frame,remembered:[8192,4096,2057,4096,0,0,0,0])
        let panel=MixerPanel(frame:frame,draft:.constant(draft),armed:.constant(true),busy:false,block:nil,status:"Preview data · no hardware connected",changed:{},restore:{},canRestore:true)
        let width=Double(CommandLine.arguments[3]) ?? 900
        let view=VStack(alignment:.leading,spacing:20) { OutputSelector(selected:2,busy:false,choose:{_ in}); panel }.padding(24).frame(width:width).background(EditorStyle.canvas).environment(\.colorScheme,.dark)
        let hosting=NSHostingView(rootView:view)
        hosting.frame=NSRect(x:0,y:0,width:width,height:hosting.fittingSize.height)
        let window=NSWindow(contentRect:hosting.frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView=hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.frame.size=hosting.fittingSize
        hosting.displayIfNeeded()
        guard let rep=hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) else { fatalError("No bitmap") }
        hosting.cacheDisplay(in:hosting.bounds,to:rep)
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
