import Foundation

extension RoutingModel {
    var mixerBlock: String? {
        if let block=writeBlock { return block }
        guard ready && confirmed else { return "Read routing and confirm low speaker/headphone levels first." }
        guard let frame=mixFrame, let saved=mixRecovery else { return "Read this mix first." }
        if !frame.isolated { return MixerError.shared.localizedDescription }
        if frame.sources != saved.sources { return MixerError.sourceChanged.localizedDescription }
        if !saved.permits(frame, restoring:false) { return MixerError.recovery.localizedDescription }
        return nil
    }
    var canRestoreMix: Bool {
        guard !busy, ready, confirmed, writeBlock == nil, let frame=mixFrame, let saved=mixRecovery else { return false }
        return saved.permits(frame,restoring:true)
    }
    func acceptMixBaseline() { mixOperation(restoring:false, write:false, baseline:true) }
    func chooseMix(_ index: Int) {
        guard !busy, (0..<6).contains(index) else { return }
        mixIndex=index; mixFrame=nil; mixRecovery=nil; mixerArmed=false; mixDraft=MixerDraft()
        readMix()
    }
    func readMix() { mixOperation(restoring:false, write:false) }
    func sendMix() { mixOperation(restoring:false, write:true) }
    func restoreMix() {
        guard canRestoreMix else { return }
        let bus=mixIndex
        if savedOutputMix == bus, mixFrame?.feedsOutput == true {
            // Detach the allocated row before restoring its old, potentially loud contents.
            mixerArmed=false
            run(2) { detached in
                guard detached else { self.mixerStatus=self.status; return }
                self.mixIndex=bus
                self.mixOperation(restoring:false,write:false) { read in
                    if read { self.mixOperation(restoring:true,write:true) }
                }
            }
        } else { mixOperation(restoring:true,write:true) }
    }
    func mixOperation(restoring: Bool, write: Bool, baseline: Bool = false, completion: ((Bool)->Void)? = nil) {
        guard !busy, ready, let target=selectedDevice, let serial=target.serial else { mixerStatus="Select the interface and read routing first."; completion?(false); return }
        let bus=mixIndex, previous=mixRecovery
        let targetOutput=selectedOutput
        let allocated=savedOutputMix == bus
        let busArgument=UInt64(bus) | UInt64(targetOutput+1)<<8
        let gains=restoring ? (mixRecovery?.original ?? []) : mixDraft.gains
        do {
            if write {
                discover()
                guard selectedDevice?.id == target.id, selectedDevice?.serial == serial else { throw MixerError.invalid }
                if let block=writeBlock { throw HardwareFailure(message:block,mayHaveWritten:false) }
                guard confirmed, restoring || mixerArmed, let frame=mixFrame, var saved=mixRecovery else { throw MixerError.invalid }
                guard saved.permits(frame,restoring:restoring) else { throw frame.isolated ? MixerError.recovery : MixerError.shared }
                guard !restoring || !allocated || frame.destinations == 0 else { throw MixerError.detachFirst }
                guard gains.count == 8 else { throw MixerError.invalid }
                saved.pending=true; saved.uncertain=true; saved.audible=mixDraft.audible
                try mixStore.save(saved) // Persist before the first SET_MIX.
                mixRecovery=saved
            }
        } catch { if preparedGains != nil { mixFrame=nil; mixDraft=MixerDraft() } else if let frame=mixFrame { mixDraft.load(frame,remembered:previous?.audible) }; mixerStatus="No mixer write sent. " + error.localizedDescription; mixerArmed=false; completion?(false); return }
        busy=true
        let device=hardware
        queue.async { [weak self] in
            let result=Result { () -> MixerFrame in
                guard try device.serial() == serial else { throw HardwareFailure(message:"Selected serial changed. No mixer write sent.",mayHaveWritten:false) }
                let reply: [UInt64]
                if write { reply=try device.callInputs(restoring ? (allocated ? 14 : 10) : 9,inputs:[busArgument,MixerMath.pack(Array(gains[0..<4])),MixerMath.pack(Array(gains[4..<8]))]) }
                else { reply=try device.call(baseline ? 11 : 8,source:busArgument) }
                var frame=try MixerFrame(reply:reply)
                frame.output=targetOutput
                guard frame.bus==bus else { throw MixerError.invalid }
                if write && frame.gains != gains { throw HardwareFailure(message:"Mixer read-back differs from requested levels. Restore saved levels.",mayHaveWritten:true) }
                return frame
            }
            Task { @MainActor in
                guard let self else { return }
                self.busy=false
                switch result {
                case .success(let frame):
                    do {
                        var saved=try self.mixStore.load(serial:serial,bus:bus) ?? MixerRecovery(serial:serial,bus:bus,original:frame.gains,sources:frame.sources,verified:frame.gains,audible:frame.gains,pending:false,uncertain:false)
                        if baseline {
                            saved=MixerRecovery(serial:serial,bus:bus,original:frame.gains,sources:frame.sources,verified:frame.gains,audible:frame.gains,pending:false,uncertain:false)
                            try self.mixStore.replaceBaseline(saved)
                            self.mixerArmed=false
                        }
                        if write {
                            saved.verified=frame.gains; saved.uncertain=false; saved.pending = !restoring
                            if restoring { saved.audible=frame.gains; self.mixerArmed=false }
                        }
                        try self.mixStore.save(saved)
                        self.mixRecovery=saved; self.mixFrame=frame; self.mixDraft.load(frame,remembered:saved.audible)
                        self.mixerStatus=baseline ? "Current mix accepted as baseline. Previous recovery archived; no hardware levels changed." : write ? (restoring ? "Original mix levels restored and read back." : "Levels read back from the Scarlett.") : "Output \(targetOutput+1) levels loaded."
                        if !saved.permits(frame,restoring:false) { self.mixerArmed=false; self.mixerStatus=MixerError.recovery.localizedDescription }
                        if restoring && allocated {
                            self.mixFrame=nil; self.mixDraft=MixerDraft(); self.preparedGains=nil
                            self.mixerStatus="Saved levels recovered on the disconnected row. Refresh to edit."
                        }
                    } catch { self.mixerArmed=false; self.mixFrame=nil; self.mixerStatus=(write ? "Hardware levels were written and verified, but recovery storage failed. Read levels before recovery. " : "No hardware levels changed. Mixer recovery storage failed. ") + error.localizedDescription }
                case .failure(let error):
                    if write, let failure=error as? HardwareFailure, !failure.mayHaveWritten, let previous {
                        do { try self.mixStore.save(previous); self.mixRecovery=previous } catch { self.log += "\nMixer recovery marker retained: \(error.localizedDescription)" }
                    }
                    self.mixerArmed=false; self.mixFrame=nil
                    self.mixerStatus=error.localizedDescription
                }
                completion?(self.mixFrame != nil)
                self.log += "\nMix \(bus+1): " + self.mixerStatus
            }
        }
    }
}

extension RoutingModel {
    func selectOutput(_ output: Int) {
        guard !busy, (0..<4).contains(output) else { return }
        clearOutputState()
        selectedOutput=output; mixFrame=nil; mixRecovery=nil; mixerArmed=false; preparedGains=nil; startsSilent=false
        run(0) { ok in if ok { self.loadOutputMix() } }
    }
    func loadOutputMix(completion: ((Bool)->Void)? = nil) {
        guard !busy, ready, let source=current, let serial=selectedDevice?.serial else { completion?(false); return }
        let output=selectedOutput, device=hardware
        let preferred=savedOutputMix
        busy=true; mixFrame=nil; mixerArmed=false; preparedGains=nil; startsSilent=false
        queue.async { [weak self] in
            let result=Result { () -> OutputMixPlan in
                guard try device.serial()==serial else { throw MixerError.invalid }
                let rows=try (0..<6).map { try MixerFrame(reply:device.call(8,source:UInt64($0)|UInt64(output+1)<<8)) }
                return try OutputMixPlan.make(output:output,source:source,rows:rows,preferredBus:preferred)
            }
            Task { @MainActor in
                guard let self else { return }; self.busy=false
                switch result {
                case .success(let plan):
                    self.mixIndex=plan.frame.bus; self.preparedGains=plan.initialGains; self.startsSilent=plan.replacesUnavailableSource
                    self.mixOperation(restoring:false,write:false) { loaded in
                        if loaded, let frame=self.mixFrame, self.mixRecovery?.permits(frame,restoring:false)==true, let gains=plan.initialGains {
                            self.mixDraft.gains=gains
                            self.mixDraft.audible=gains
                            self.mixerStatus=plan.replacesUnavailableSource ? "Available inputs shown. Start mixer to replace the direct feed; all faders start muted." : "Ready to enable Output \(output+1)."
                        }
                        completion?(loaded)
                    }
                case .failure(let error): self.mixerStatus=error.localizedDescription; completion?(false)
                }
            }
        }
    }
    func enableOutputMixer() {
        guard !busy, let frame=mixFrame else { return }
        do {
            let pending = try mixStore.loadInputs(selectedDevice?.serial ?? "")?.pending == true
            if !InputExpansionJournal.allSources.allSatisfy(frame.sources.contains) || pending {
                expandMixerInputs(); return
            }
        } catch { mixerStatus="Input recovery could not be read. No write sent."; return }
        confirmed=true; mixerArmed=true
        guard !frame.feedsOutput else { return }
        guard let gains=preparedGains else { mixerArmed=false; return }
        if recoveryPending {
            mixerArmed=false; mixerStatus="Restore the output source before enabling faders. No levels changed."; return
        }
        if let block=mixerBlock { mixerArmed=false; mixerStatus=block; return }
        do { try rememberOutputMix(mixIndex) } catch { mixerArmed=false; mixerStatus="Could not save output recovery: " + error.localizedDescription; return }
        mixDraft.gains=gains
        mixOperation(restoring:false,write:true) { ok in
            guard ok else { return }
            self.selected=UInt64(0x300+self.mixIndex)
            self.run(1) { connected in
                guard connected else { self.mixerArmed=false; return }
                self.mixOperation(restoring:false,write:false) { read in
                    self.mixerArmed=read
                    if read { self.preparedGains=nil; self.startsSilent=false }
                }
            }
        }
    }
}


extension RoutingModel {
    // Invoked only by the user's Enable tap, never by discovery or a routing read.
    func expandMixerInputs() {
        guard !busy, ready, let target=selectedDevice, let serial=target.serial else { return }
        discover()
        guard selectedDevice?.id==target.id, let _=selectedDevice?.registryID else { return }
        if let block=targetWriteBlock { mixerStatus=block; return }
        busy=true; mixerArmed=false
        let device=hardware, store=mixStore, output=selectedOutput
        queue.async { [weak self] in
            let result=Result { () -> Void in
                guard try device.serial()==serial else { throw MixerError.invalid }
                func readRows() throws -> [MixerFrame] {
                    try (0..<6).map { try MixerFrame(reply:device.call(8,source:UInt64($0)|UInt64(output+1)<<8)) }
                }
                let routes=try device.liveRoutes(), rows=try readRows()
                var journal: InputExpansionJournal
                if let previous=try store.loadInputs(serial), previous.pending {
                    journal=previous
                    guard journal.acceptsProgress(routes:routes,rows:rows) else { throw MixerError.recovery }
                    // Only the journal's known original/partial-zero state may be resumed.
                    // These are read-only acknowledgements after a strict full-state check.
                    _ = try device.call(0)
                    _ = try device.call(17)
                    for bus in 0..<6 { _ = try device.call(11,source:UInt64(bus)|UInt64(output+1)<<8) }
                } else {
                    let sources=rows[0].sources
                    guard rows.allSatisfy({$0.sources==sources}) else { throw MixerError.invalid }
                    let expanded=try InputExpansionJournal.expandedSources(sources)
                    var saved: [MixerRecovery]=[]
                    for row in rows {
                        let recovery=try store.load(serial:serial,bus:row.bus) ?? MixerRecovery(serial:serial,bus:row.bus,original:row.gains,sources:sources,verified:row.gains,audible:row.gains,pending:false,uncertain:false)
                        guard !recovery.uncertain, recovery.sources==sources, recovery.verified==row.gains else { throw MixerError.recovery }
                        saved.append(recovery)
                    }
                    journal=InputExpansionJournal(serial:serial,routes:routes,rows:rows.map(\.gains),recoveries:saved,sources:sources,expanded:expanded,pending:true)
                    guard journal.valid else { throw MixerError.invalid }
                    try store.saveInputs(journal) // All six original rows reach disk before any write.
                }
                let routeArguments = InputExpansionJournal.routeArguments(routes)
                let rowArguments = rows.flatMap { [MixerMath.pack(Array($0.gains[0..<4])),MixerMath.pack(Array($0.gains[4..<8]))] }
                _ = try device.callInputs(15,inputs:routeArguments+rowArguments)
                let afterRoutes=try device.liveRoutes(), after=try readRows()
                guard afterRoutes==journal.expandedRoutes,
                      journal.acceptsProgress(routes:afterRoutes,rows:after) else { throw MixerError.recovery }
                // Preserve each existing baseline; new columns must also restore to silence.
                for bus in 0..<6 { try store.save(journal.migrated(bus)) }
                journal.pending=false
                try store.saveInputs(journal) // Clear last, so interruption resumes migration safely.
            }
            Task { @MainActor in
                guard let self else { return }; self.busy=false
                switch result {
                case .success:
                    self.mixFrame=nil; self.mixRecovery=nil; self.preparedGains=nil
                    self.mixerStatus="All eight inputs ready. Added channels are muted."
                    self.log += "\nInput expansion: all 18 routes and six mixer rows verified."
                    // Continue the same explicit Enable action after verified input setup.
                    self.run(0) { ok in if ok { self.loadOutputMix { loaded in if loaded { self.enableOutputMixer() } } } }
                case .failure(let error):
                    self.mixFrame=nil; self.mixerStatus="Input setup stopped. Recovery saved; refresh and enable to retry. " + error.localizedDescription
                    self.log += "\nInput expansion: " + self.mixerStatus
                }
            }
        }
    }
}
