import SwiftUI
import AVFAudio

struct InterfaceDevice: Identifiable {
    let id: String
    let name: String
    let detail: String
    let registryID: UInt64?
    let serial: String?
}
struct RoutingView: View {
    @StateObject private var model = RoutingModel()
    @State private var diagnostics = false
    @State private var directRouting = false
    @State private var confirmRecovery = false
    @State private var confirmMixBaseline = false
    @State private var rebaselineConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scarlett Editor").font(EditorStyle.font(24)).bold()
                    Text("Performance Percussion").foregroundStyle(EditorStyle.muted)
                }.padding(.top, 16)
                HStack { Text("Interfaces").bold(); Spacer(); Button { model.discover() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Refresh interfaces") }.disabled(model.busy || model.testingAudio)
                ScrollView {
                    VStack(spacing: 8) {
                        if model.devices.isEmpty { Text("Connect an interface, then refresh.").foregroundStyle(EditorStyle.muted).padding(.vertical) }
                        ForEach(model.devices) { device in
                            Button {
                                model.selectDevice(device.id)
                                if device.registryID != nil { model.run(0) { ok in if ok { model.loadOutputMix() } } }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "hifispeaker.fill").padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(device.name).bold()
                                        Text(device.detail).font(EditorStyle.font(13)).foregroundStyle(EditorStyle.muted)

                                        if model.devices.filter({ $0.registryID != nil }).count > 1, let id = device.registryID { Text("Connection \(id)").font(.caption.monospaced()) }
                                    }
                                    Spacer(minLength: 0)
                                    if model.deviceID == device.id { Image(systemName: "checkmark") }
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(model.deviceID == device.id ? EditorStyle.accent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.deviceID == device.id ? EditorStyle.accent : EditorStyle.edge))
                            }.buttonStyle(.plain).disabled(model.busy || model.testingAudio)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("iPad audio output").font(EditorStyle.font(13)).foregroundStyle(EditorStyle.muted)
                    Text(model.audioOutput)

                }
                Button("Driver settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.frame(minHeight: 44)
                Button("Connection details", systemImage: "info.circle") { diagnostics = true }.frame(minHeight: 44)
            }.padding(20).background(EditorStyle.sidebar).navigationBarHidden(true)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 340)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.selectedDevice?.registryID != nil { routing } else { unavailable }
                }.padding(28).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
            }.background(EditorStyle.canvas)
                .navigationTitle("Mixer").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Details", systemImage: "info.circle") { diagnostics = true } }
                }
        }
        .font(EditorStyle.font(17)).foregroundStyle(Color.white).tint(.white).preferredColorScheme(.dark)
        .sheet(isPresented: $diagnostics) { details }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in model.recordAudioRoute() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.discover() } else { model.suspend() } }
        .task {
            model.discover()
            if model.selectedDevice?.registryID != nil { model.run(0) { ok in if ok { model.loadOutputMix() } } }
            #if DEBUG
            if ProcessInfo.processInfo.environment["SCARLETT_CAPTURE_UI"] == "1" {
                try? await Task.sleep(for: .seconds(4))
                if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow),
                   let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    try? image.pngData()?.write(to: cache.appendingPathComponent("RoutingScreen.png"))
                }
            }
            #endif
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.selectedDevice?.name ?? "Your sound. Your route.").font(EditorStyle.font(32)).bold()
            Text("Choose an output. Choose what it hears.").foregroundStyle(EditorStyle.muted)
            HStack(alignment: .top, spacing: 10) {
                if model.busy { ProgressView() } else { Image(systemName: model.ready ? "checkmark.circle.fill" : "info.circle").foregroundStyle(model.ready ? Color.green : EditorStyle.muted) }
                Text(model.status).font(EditorStyle.font(15)).accessibilityIdentifier("hardwareStatus")
            }.padding(.top, 8)
        }
    }
    private var routing: some View {
        VStack(alignment:.leading,spacing:16) {
            OutputSelector(selected:model.selectedOutput,busy:model.busy,choose:{model.selectOutput($0)})
            mixerControls
        }
        .sheet(isPresented:$directRouting) {
            NavigationStack {
                ScrollView { directRoutingControls.padding(24) }
                    .background(EditorStyle.canvas)
                    .navigationTitle("Direct routing · Output \(model.selectedOutput+1)")
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { directRouting=false } } }
            }.preferredColorScheme(.dark)
        }
    }
    private var directRoutingControls: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("What should Output \(model.selectedOutput+1) hear?").font(EditorStyle.font(24)).bold()
                Text("App audio").bold()
                Text("Sound sent to the Scarlett by music apps on your iPad.").font(EditorStyle.font(15)).foregroundStyle(EditorStyle.muted)
                LazyVGrid(columns: columns, spacing: 12) { ForEach(0..<4) { index in sourceButton(UInt64(0x600 + index), title: "Playback \(index + 1)", icon: "waveform") } }
                Text("Physical inputs").bold()
                LazyVGrid(columns: columns, spacing: 12) { ForEach(0..<4) { index in sourceButton(UInt64(0x80 + index), title: "Input \(index + 1)", icon: "cable.connector") } }
                sourceButton(0, title: "Off · no source", icon: "speaker.slash")
                Divider()
                Text("\(sourceName(model.selected))  →  Output \(model.selectedOutput+1)").font(EditorStyle.font(20)).bold().accessibilityIdentifier("pendingRoute")
            Toggle("My speaker / headphone level is down", isOn: $model.confirmed).tint(EditorStyle.accent)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { applyButton; restoreButton }
                    VStack(alignment: .leading, spacing: 12) { applyButton; restoreButton }
                }
                if let block = model.writeBlock { Text(block).font(EditorStyle.font(14)).foregroundStyle(EditorStyle.muted) }
                if model.recoveryPending { Text("Recovery snapshot saved. Restore before another change. If disconnected or above 48 kHz, reconnect this serial-numbered interface at 44.1 / 48 kHz first.").font(EditorStyle.font(14)).foregroundStyle(.orange) }
                Button("Use current routing as baseline") { rebaselineConfirmation = true }
                    .disabled(model.busy || !model.ready || model.recoveryPending)
                    .confirmationDialog("Replace the saved baseline with current routing?", isPresented: $rebaselineConfirmation, titleVisibility: .visible) {
                        Button("Read and accept current routing") { model.run(4) }
                    } message: { Text("This replaces the saved recovery snapshot for this interface. It does not change hardware routing.") }
                Text("Outputs 3–4 also feed the headphones.").font(EditorStyle.font(14)).foregroundStyle(EditorStyle.muted)
                Text("Nothing changes until you tap Apply. Every change is read back from the interface.").font(EditorStyle.font(14)).foregroundStyle(EditorStyle.muted)
            }.padding(24).background(EditorStyle.panel, in: RoundedRectangle(cornerRadius: 8))
    }
    private var mixerControls: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("Output \(model.selectedOutput+1)").font(EditorStyle.font(24)).bold()
                Spacer()
                if model.busy { ProgressView() }
                Button(model.mixerArmed ? "Lock" : model.startsSilent ? "Start mixer" : "Edit") {
                    if model.mixerArmed { model.mixerArmed=false } else { model.explicitlySelected=true; model.enableOutputMixer() }
                }.disabled(model.busy || model.mixFrame == nil)
                Menu {
                    Button("Direct routing…") { directRouting=true }
                    Button("Refresh levels") { model.run(0) { ok in if ok { model.loadOutputMix() } } }
                    Button("Enable recovery…") { confirmRecovery=true }
                    Button("Restore levels") { model.restoreMix() }.disabled(!model.canRestoreMix)
                    Button("Restore output source") { model.run(2) { ok in if ok { model.loadOutputMix() } } }
                        .disabled(!model.confirmed || model.writeBlock != nil)
                    Button("Use current levels as baseline") { confirmMixBaseline=true }.disabled(model.mixFrame == nil)
                    Button("Details") { diagnostics=true }
                } label: { Image(systemName:"ellipsis.circle").frame(width:44,height:44) }.disabled(model.busy)
            }
            MixerPanel(frame:model.mixFrame,draft:$model.mixDraft,armed:$model.mixerArmed,busy:model.busy,
                       block:model.mixerBlock,status:model.mixerStatus,changed:{model.sendMix()},restore:{model.restoreMix()},canRestore:model.canRestoreMix)
                .overlay {
                    if !model.mixerArmed && model.mixFrame != nil && !model.busy {
                        Button { model.explicitlySelected=true; model.enableOutputMixer() } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius:12)
                                    .fill(EditorStyle.canvas.opacity(0.65))
                                    .overlay(RoundedRectangle(cornerRadius:12).stroke(EditorStyle.accent.opacity(0.7),lineWidth:2))
                                Label("Enable faders",systemImage:"lock.open")
                                    .font(EditorStyle.font(26)).bold()
                                    .padding(24)
                            }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Enable faders for selected Scarlett, Output \(model.selectedOutput+1)")
                    }
                }
            Text(model.mixerStatus).font(EditorStyle.font(13)).foregroundStyle(EditorStyle.muted).lineLimit(2)
            if !model.ready {
                Button("Load interface") {
                    model.selectDevice(model.deviceID)
                    model.run(0) { ok in if ok { model.loadOutputMix() } }
                }.disabled(model.busy)
            } else if model.mixerArmed, let block=model.mixerBlock {
                Text(block).font(EditorStyle.font(14)).foregroundStyle(.orange)
            }
        }
        .confirmationDialog("Keep monitoring low during recovery.",isPresented:$confirmRecovery,titleVisibility:.visible) {
            Button("Enable recovery controls") { model.confirmed=true; model.mixerArmed=false }
        } message: { Text("This enables recovery controls only. No hardware settings change.") }
        .confirmationDialog("Replace the saved level baseline?",isPresented:$confirmMixBaseline,titleVisibility:.visible) {
            Button("Accept current levels") { model.acceptMixBaseline() }
        } message: { Text("The previous recovery snapshot is archived. Hardware levels stay unchanged.") }
        .onAppear { if model.mixFrame == nil && model.ready { model.loadOutputMix() } }
    }
    private func sourceButton(_ value: UInt64, title: String, icon: String) -> some View {
        Button { model.selected = value } label: {
            HStack { Image(systemName: icon); Text(title); Spacer(minLength: 4); if model.selected == value { Image(systemName: "checkmark.circle.fill") } }
                .padding(14).frame(minHeight: 52).frame(maxWidth: .infinity)
                .background(model.selected == value ? EditorStyle.accent : EditorStyle.canvas, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.selected == value ? EditorStyle.accent : EditorStyle.muted.opacity(0.6)))
        }.buttonStyle(.plain).disabled(model.busy || model.testingAudio || !model.ready)
            .accessibilityAddTraits(model.selected == value ? .isSelected : [])
    }
    private var applyButton: some View {
        Button { model.run(1) { ok in if ok { model.loadOutputMix() } } } label: { Label("Apply route", systemImage: "arrow.right").bold().padding(.horizontal, 20).frame(minHeight: 50).background(EditorStyle.accent, in: RoundedRectangle(cornerRadius: 6)) }
            .buttonStyle(.plain).opacity(canApply ? 1 : 0.4).disabled(!canApply)
    }
    private var canApply: Bool { !model.busy && !model.testingAudio && model.ready && model.confirmed && model.current != model.selected && !model.recoveryPending && model.writeBlock == nil }
    private var restoreButton: some View {
        Button("Restore original", systemImage: "arrow.uturn.backward") { model.run(2) { ok in if ok { model.loadOutputMix() } } }.frame(minHeight: 50)
            .disabled(model.busy || model.testingAudio || model.original == nil || !model.confirmed || !model.ready || model.writeBlock != nil)
    }
    private var unavailable: some View {
        VStack(spacing:20) {
            if model.selectedDevice?.name.localizedCaseInsensitiveContains("4i4") == true {
                ContentUnavailableView("Enable the Scarlett driver",systemImage:"gearshape",description:Text("Your Scarlett is connected for audio. Turn on Scarlett Direct’s driver to use the mixer."))
                Button("Open driver settings",systemImage:"gearshape") {
                    if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(.borderedProminent).tint(EditorStyle.accent)
                Button("Check connection",systemImage:"arrow.clockwise") { model.discover() }
            } else {
                ContentUnavailableView(model.selectedDevice == nil ? "Connect your interface" : "Audio connection",systemImage:"cable.connector",description:Text(model.selectedDevice == nil ? "Connect a Scarlett and enable its driver in Settings." : "No compatible control driver is connected for this interface."))
            }
        }
    }
    private var details: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Direct USB control").font(.title2).bold()
                    Text("The selected interface receives commands directly from this iPad.")
                    Button("Open driver settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    Text(model.log).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    ShareLink("Share connection log", item: model.log)
                }.padding(24)
            }.navigationTitle("Connection details").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { diagnostics = false } } }
        }.preferredColorScheme(.dark)
    }
}
