import SwiftUI

struct MixerPanel: View {
    let frame: MixerFrame?
    @Binding var draft: MixerDraft
    @Binding var armed: Bool
    let busy: Bool
    let block: String?
    let status: String
    let changed: () -> Void
    let restore: () -> Void
    let canRestore: Bool
    private var enabled: Bool { armed && block == nil && !busy }
    var body: some View {
        VStack(spacing: 12) {
            if let frame, draft.gains.count == 8 {
                inputRow(frame, range: 0x80...0x83)
                inputRow(frame, range: 0x600...0x603)
            } else {
                ContentUnavailableView("No levels loaded", systemImage:"slider.vertical.3")
                    .frame(minWidth:280, minHeight:360)
            }
        }
        .font(EditorStyle.font(16)).foregroundStyle(.white)
    }
    private func inputRow(_ frame: MixerFrame, range: ClosedRange<UInt16>) -> some View {
        HStack(spacing: 12) {
            ForEach((0..<8).filter { range.contains(frame.sources[$0]) }.sorted { frame.sources[$0] < frame.sources[$1] }, id: \.self) { channel($0, frame:frame) }
        }
    }
    private func channel(_ index: Int, frame: MixerFrame) -> some View {
        let muted=draft.gains[index] == 0
        let title=sourceName(UInt64(frame.sources[index]))
        return VStack(spacing: 8) {
            Text(title).bold().lineLimit(2).frame(height:22)
            Text(MixerMath.label(draft.gains[index])).monospacedDigit().foregroundStyle(EditorStyle.muted)
            Slider(value:Binding(get:{ MixerMath.db(draft.gains[index]) },set:{ draft.setDB($0,channel:index) }),in:-80...12,onEditingChanged:{ editing in if !editing { changed() } })
                // Widen the native thumb and its touch area without stretching vertical travel.
                .frame(width:140,height:44).scaleEffect(x:1,y:2.5)
                .rotationEffect(.degrees(-90)).frame(width:110,height:160)
                .tint(EditorStyle.accent).disabled(!enabled)
                .accessibilityLabel("\(title) level").accessibilityValue(MixerMath.label(draft.gains[index]))
                .accessibilityAdjustableAction { direction in
                    guard enabled else { return }
                    switch direction {
                    case .increment: draft.adjust(index,increasing:true)
                    case .decrement: draft.adjust(index,increasing:false)
                    @unknown default: return
                    }
                    changed()
                }
            Button {
                draft.toggleMute(index); changed()
            } label: {
                Text(muted ? "MUTED" : "MUTE").bold().frame(maxWidth:.infinity,minHeight:44)
                    .background(muted ? EditorStyle.mute : EditorStyle.edge,in:RoundedRectangle(cornerRadius:6))
            }.buttonStyle(.plain).disabled(!enabled || (muted && draft.audible[index]==0))
                .accessibilityLabel("\(muted ? "Unmute" : "Mute") \(title)")
        }.padding(12).frame(maxWidth:.infinity).background(EditorStyle.panel,in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(EditorStyle.edge,lineWidth:1))
    }
}

struct OutputSelector: View {
    let selected: Int
    let busy: Bool
    let choose: (Int)->Void
    var body: some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:130),spacing:12)],spacing:12) {
            ForEach(0..<4) { output in
                Button { choose(output) } label: {
                    VStack(spacing:6) {
                        Text("Output \(output+1)").bold()
                        Text(output<2 ? "Line" : output==2 ? "Line + Headphones L" : "Line + Headphones R").font(EditorStyle.font(12))
                    }.frame(maxWidth:.infinity,minHeight:64)
                    .background(selected==output ? EditorStyle.accent : EditorStyle.panel,in:RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain).disabled(busy)
                .accessibilityAddTraits(selected==output ? .isSelected : [])
            }
        }.font(EditorStyle.font(16)).foregroundStyle(.white)
    }
}
