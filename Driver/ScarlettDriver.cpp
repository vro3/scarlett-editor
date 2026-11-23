#include <DriverKit/IOLib.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IODispatchQueue.h>
#include <USBDriverKit/IOUSBHostInterface.h>
#include <USBDriverKit/IOUSBHostDevice.h>
#include <USBDriverKit/USBDriverKitDefs.h>
#include <USBDriverKit/AppleUSBDescriptorParsing.h>
#include <atomic>
#include <new>
#include "ScarlettDriver.h"
#include "ScarlettClient.h"
#include "Protocol.hpp"
#include "RouteSession.hpp"
#include "Mixer.hpp"
#include "InputExpansion.hpp"
using namespace Scarlett;
struct ScarlettDriver_IVars {
    IOUSBHostInterface* usb;
    IOUSBHostPipe* pipe;
    IOBufferMemoryDescriptor* buffer;
    IOBufferMemoryDescriptor* notificationBuffer;
    IODispatchQueue* queue;
    OSAction* action;
    uint8_t* bytes;
    uint8_t* notifications;
    std::atomic<bool> notified;
    std::atomic<uint32_t> notificationStatus;
    std::atomic<uint32_t> notificationSize;
    IOLock* lock;
    uint16_t sequence;
    uint8_t clockSource;
    uint16_t notificationCapacity;
    uint32_t endpointDiagnostic;
    bool opened, initialized, stopped;
    char serial[48];
    uint32_t firmware;
    uint32_t stage, lastError, startError;
    RouteSession session;
    MixSession mixes[MixCount];
};
bool ScarlettDriver::init() {
    if(!super::init()) return false;
    ivars=IONewZero(ScarlettDriver_IVars,1);
    if(!ivars) return false;
    new (ivars) ScarlettDriver_IVars{};
    ivars->lock=IOLockAlloc(); return ivars->lock!=nullptr;
}
void ScarlettDriver::free() {
    if(ivars) {
        if(ivars->pipe) ivars->pipe->Abort(kIOUSBAbortSynchronous,kIOReturnAborted,nullptr);
        if(ivars->opened && ivars->usb) ivars->usb->Close(this,0);
        OSSafeReleaseNULL(ivars->usb); OSSafeReleaseNULL(ivars->pipe);
        OSSafeReleaseNULL(ivars->buffer); OSSafeReleaseNULL(ivars->notificationBuffer);
        OSSafeReleaseNULL(ivars->action); OSSafeReleaseNULL(ivars->queue);
        IOLockFreeZero(ivars->lock); ivars->~ScarlettDriver_IVars(); IODelete(ivars,ScarlettDriver_IVars,1);
    }
    super::free();
}
kern_return_t ScarlettDriver::Start_Impl(IOService* provider) {
    auto r=Start(provider,SUPERDISPATCH); if(r) return r;
    auto setup=[&]() -> kern_return_t {
    ivars->stage=1;
    ivars->usb=OSDynamicCast(IOUSBHostInterface,provider); if(!ivars->usb) return kIOReturnBadArgument;
    ivars->usb->retain();
    ivars->stage=2;
    r=ivars->usb->Open(this,0,nullptr); if(r) return r; ivars->opened=true;
    // Read a bounded ASCII USB serial. No serial means recovery cannot be keyed safely.
    IOUSBHostDevice* device=nullptr;
    if(ivars->usb->CopyDevice(&device)==kIOReturnSuccess && device) {
        const auto descriptor=device->CopyDeviceDescriptor();
        if(descriptor) {
            if(descriptor->iSerialNumber) {
                const auto serial=ivars->usb->CopyStringDescriptor(descriptor->iSerialNumber);
                if(serial) {
                    const auto rawSerial=reinterpret_cast<const uint8_t*>(serial);
                    size_t count=rawSerial[0]>=2 ? (rawSerial[0]-2)/2 : 0;
                    bool valid=rawSerial[1]==3 && rawSerial[0]%2==0 && count>0 && count<sizeof(ivars->serial);
                    for(size_t i=0;valid && i<count;i++) {
                        auto c=u16(rawSerial+2+i*2);
                        if(c<33 || c>126) valid=false; else ivars->serial[i]=char(c);
                    }
                    if(!valid) memset(ivars->serial,0,sizeof(ivars->serial));
                    IOUSBHostFreeDescriptor(serial);
                }
            }
            IOUSBHostFreeDescriptor(descriptor);
        }
        device->release();
    }
    ivars->stage=3;
    auto config=ivars->usb->CopyConfigurationDescriptor(); if(!config) return kIOReturnError;
    // Find the standard UAC2 clock-source descriptor on audio control interface 0.
    // Only its frequency is read; this driver never sets the audio clock.
    const uint8_t* raw=(const uint8_t*)config;
    uint8_t interfaceNumber=255;
    for(size_t offset=0;offset+2<=config->wTotalLength;) {
        uint8_t length=raw[offset];
        if(length<2 || offset+length>config->wTotalLength) break;
        if(raw[offset+1]==4 && length>=9) interfaceNumber=raw[offset+2];
        if(interfaceNumber==0 && raw[offset+1]==0x24 && length>=8 && raw[offset+2]==0x0a) {
            if(ivars->clockSource) { ivars->clockSource=0; break; }
            ivars->clockSource=raw[offset+3];
        }
        offset+=length;
    }
    auto iface=ivars->usb->GetInterfaceDescriptor(config);
    uint8_t endpoint=0;
    if(iface && iface->bInterfaceNumber==3 && iface->bInterfaceClass==255) {
        auto ep=IOUSBGetNextEndpointDescriptor(config,iface,nullptr);
        while(ep) {
            ivars->endpointDiagnostic = uint32_t(ep->bEndpointAddress) | (uint32_t(ep->bmAttributes) << 8) | (uint32_t(ep->wMaxPacketSize) << 16);
            // An eight-byte notification need not have an eight-byte endpoint maximum.
            // Allocate the descriptor's bounded capacity, but still accept only eight-byte ACKs.
            if((ep->bEndpointAddress&0x80) && (ep->bmAttributes&3)==3 && ep->wMaxPacketSize>=8 && ep->wMaxPacketSize<=1024) {
                endpoint=ep->bEndpointAddress;
                ivars->notificationCapacity=ep->wMaxPacketSize;
                break;
            }
            ep=IOUSBGetNextEndpointDescriptor(config,iface,(const IOUSBDescriptorHeader*)ep);
        }
    }
    IOUSBHostFreeDescriptor(config);
    ivars->stage=4;
    if(!endpoint) return kIOReturnUnsupported;
    ivars->stage=41;
    if((r=ivars->usb->CopyPipe(endpoint,&ivars->pipe))) return r;
    ivars->stage=42;
    if((r=IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut,256,0,&ivars->buffer))) return r;
    if((r=IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut,ivars->notificationCapacity,0,&ivars->notificationBuffer))) return r;
    IOAddressSegment range={};
    if((r=ivars->buffer->GetAddressRange(&range))) return r; ivars->bytes=(uint8_t*)range.address;
    if((r=ivars->notificationBuffer->GetAddressRange(&range))) return r; ivars->notifications=(uint8_t*)range.address;
    ivars->stage=5;
    if((r=IODispatchQueue::Create("ScarlettNotifications",0,0,&ivars->queue))) return r;
    if((r=SetDispatchQueue("Notifications",ivars->queue))) return r;
    if((r=CreateActionNotification(0,&ivars->action))) return r;
    return kIOReturnSuccess;
    };
    ivars->startError=setup(); ivars->lastError=ivars->startError;
    if(ivars->startError && ivars->opened) { ivars->usb->Close(this,0); ivars->opened=false; }
    return RegisterService();
}
kern_return_t ScarlettDriver::Stop_Impl(IOService* provider) {
    IOLockLock(ivars->lock); ivars->stopped=true;
    if(ivars->pipe) ivars->pipe->Abort(kIOUSBAbortSynchronous,kIOReturnAborted,nullptr);
    if(ivars->opened) { ivars->usb->Close(this,0); ivars->opened=false; }
    IOLockUnlock(ivars->lock);
    return Stop(provider,SUPERDISPATCH);
}
kern_return_t ScarlettDriver::NewUserClient_Impl(uint32_t type,IOUserClient** client) {
    if(type!=0) return kIOReturnBadArgument;
    IOService* service=nullptr; auto r=Create(this,"UserClientProperties",&service);
    if(r) return r; *client=OSDynamicCast(ScarlettClient,service);
    if(!*client) { service->release(); return kIOReturnError; } return kIOReturnSuccess;
}
void ScarlettDriver::Notification_Impl(OSAction*,IOReturn status,uint32_t bytes,uint64_t) {
    ivars->notificationStatus.store(status); ivars->notificationSize.store(bytes);
    ivars->notified.store(true,std::memory_order_release);
}
kern_return_t ScarlettDriver::Control(uint8_t type,uint8_t req,uint16_t size) {
    auto r=ivars->buffer->SetLength(size); if(r) return r;
    uint16_t transferred=0;
    r=ivars->usb->DeviceRequest(type,req,0,3,size,ivars->buffer,&transferred,1000);
    return r ? r : transferred==size ? kIOReturnSuccess : kIOReturnUnderrun;
}
kern_return_t ScarlettDriver::Command(uint32_t cmd,const uint8_t* payload,uint16_t size,uint8_t* output,uint16_t outputSize) {
    auto transaction=[&]() -> kern_return_t {
    uint16_t seq=ivars->sequence++;
    auto n=request(cmd,seq,payload,size,ivars->bytes,256); if(!n || outputSize>84) return kIOReturnBadArgument;
    ivars->notified.store(false); ivars->notificationBuffer->SetLength(ivars->notificationCapacity);
    auto r=ivars->pipe->AsyncIO(ivars->notificationBuffer,ivars->notificationCapacity,ivars->action,0); if(r) return r;
    r=Control(0x21,2,n);
    if(r) { ivars->pipe->Abort(kIOUSBAbortSynchronous,kIOReturnAborted,nullptr); return r; }
    bool ack=false;
    for(unsigned elapsed=0;elapsed<1000;elapsed+=5) {
        if(ivars->notified.load(std::memory_order_acquire)) {
            r=ivars->notificationStatus.load(); if(r) return r;
            if(ivars->notificationSize.load()==8 && (u32(ivars->notifications)&1)) { ack=true; break; }
            ivars->notified.store(false);
            r=ivars->pipe->AsyncIO(ivars->notificationBuffer,ivars->notificationCapacity,ivars->action,0); if(r) return r;
        }
        IOSleep(5);
    }
    if(!ack) { ivars->pipe->Abort(kIOUSBAbortSynchronous,kIOReturnAborted,nullptr); return kIOReturnTimeout; }
    r=Control(0xa1,3,16+outputSize); if(r) return r;
    if(!response(ivars->bytes,16+outputSize,cmd,seq,outputSize)) return kIOReturnIOError;
    if(outputSize) memcpy(output,ivars->bytes+16,outputSize); return kIOReturnSuccess;
    };
    auto result=transaction();
    if(result) {
        ivars->pipe->Abort(kIOUSBAbortSynchronous,kIOReturnAborted,nullptr);
        ivars->initialized=false; // A subsequent read must re-handshake; writes never re-init implicitly.
    }
    return result;
}
kern_return_t ScarlettDriver::ReadRoutes(void* result) {
    uint8_t req[4]={0,0,18,0}, responseBytes[72]={};
    auto r=Command(0x3001,req,4,responseBytes,72); if(r) return r;
    return decode(responseBytes,72,*(Routes*)result) ? kIOReturnSuccess : kIOReturnUnsupported;
}
kern_return_t ScarlettDriver::Perform(uint64_t selector,uint64_t source,uint64_t* output) {
    IOLockLock(ivars->lock);
    auto perform=[&]() -> kern_return_t {
        if(selector==5) { memcpy(output,ivars->serial,sizeof(ivars->serial)); return kIOReturnSuccess; }
        if(selector==17) {
            ivars->stage=0;
            if(source || !ivars->initialized || ivars->stopped) return kIOReturnNotReady;
            Routes live; auto r=ReadRoutes(&live); if(r) return r;
            // Explicit read-only acknowledgement after app validates its expansion journal.
            ivars->session.observe(live); ivars->session.expected=live; ivars->session.uncertain=false;
            return kIOReturnSuccess;
        }
        if(selector==16) {
            if(source>2 || !ivars->initialized || ivars->stopped) return kIOReturnNotReady;
            Routes live; auto r=ReadRoutes(&live); if(r) return r;
            for(size_t i=0;i<6;i++) output[i]=live.words[source*6+i];
            return kIOReturnSuccess;
        }
        if(selector==7) {
            if(!ivars->session.captured || source>2) return kIOReturnBadArgument;
            for(size_t i=0;i<6;i++) output[i]=ivars->session.original.words[source*6+i];
            return kIOReturnSuccess;
        }
        ivars->stage = selector==3 ? ivars->stage : 0;
        if(selector==3) {
            output[0]=ivars->stage; output[1]=ivars->lastError;
            output[2]=ivars->startError; output[3]=ivars->firmware;
            output[4]=ivars->clockSource; output[5]=ivars->endpointDiagnostic;
            return kIOReturnSuccess;
        }
        if(ivars->startError) return ivars->startError;
        if(ivars->stopped || !ivars->opened) return kIOReturnNotAttached;
        unsigned outputIndex=2;
        if(selector==12 || selector==13) {
            if((source>>16)>=4) return kIOReturnBadArgument;
            outputIndex=unsigned(source>>16);
            if(outputIndex>=4) return kIOReturnBadArgument;
            source &= 0xffff;
            selector=selector==12 ? 1 : 6;
        }
        if(selector>7 || (selector==1 && (source>0xffff || !validSource(source))) || (selector==6 && (source>0xffff || !validSource(source)))) return kIOReturnBadArgument;
        if(!ivars->initialized) {
            if(selector!=0 && selector!=4) return kIOReturnNotReady;
            ivars->stage=10;
            auto r=Control(0xa1,0,24); if(r) return r;
            IOSleep(20); ivars->sequence=1;
            ivars->stage=11;
            if((r=Command(0,nullptr,0,nullptr,0))) return r;
            ivars->sequence=1; uint8_t info[84]={};
            ivars->stage=12;
            if((r=Command(2,nullptr,0,info,84))) return r;
            ivars->firmware=u32(info+8); ivars->initialized=true;
        }
        // Enforce bank 0 in the driver as well as the app, including on restore.
        ivars->stage=20;
        if(!ivars->clockSource) return kIOReturnUnsupported;
        uint16_t received=0;
        auto r=ivars->buffer->SetLength(4); if(r) return r;
        r=ivars->usb->DeviceRequest(0xa1,1,0x0100,uint16_t(ivars->clockSource)<<8,4,ivars->buffer,&received,1000);
        if(r) return r;
        if(received!=4) return kIOReturnUnderrun;
        auto rate=u32(ivars->bytes);
        if(rate!=44100 && rate!=48000) return kIOReturnUnsupported;
        ivars->stage=30;
        Routes current; r=ReadRoutes(&current); if(r) return r;
        if(selector==0) {
            ivars->session.observe(current);
        } else if(selector==4) {
            if(!ivars->session.rebaseline(current)) return kIOReturnNotReady;
        } else {
            if(!ivars->serial[0]) return kIOReturnNotPermitted;
            const bool restoring=selector==2 || selector==6;
            if(selector==1 && source>=0x300 && source<=0x305) {
                const unsigned mix=unsigned(source-0x300);
                if(!isolatedMix(current,mix,outputIndex)) return kIOReturnNotPermitted;
                if(!ivars->mixes[mix].captured || ivars->mixes[mix].uncertain) return kIOReturnNotReady;
                uint8_t mixRequest[4], mixReply[16]; put16(mixRequest,mix); put16(mixRequest+2,MixInputs);
                if((r=Command(0x2001,mixRequest,4,mixReply,16))) return r;
                MixRow actualMix;
                if(!decodeMix(mixReply,16,actualMix)) return kIOReturnUnsupported;
                if(!ivars->mixes[mix].canWrite(actualMix,current,mix,false,outputIndex)) return kIOReturnBusy;
            }
            Routes next;
            auto decision=ivars->session.prepare(current,selector==2 ? line3(ivars->session.original) : source,restoring,next,outputIndex);
            if(decision==RouteSession::drift) return kIOReturnBusy;
            if(decision!=RouteSession::ready) return kIOReturnNotReady;
            // Recheck immediately before SET_MUX; bank 0 remains the only write target.
            received=0;
            if((r=ivars->buffer->SetLength(4))) return r;
            r=ivars->usb->DeviceRequest(0xa1,1,0x0100,uint16_t(ivars->clockSource)<<8,4,ivars->buffer,&received,1000);
            if(r) return r;
            if(received!=4) return kIOReturnUnderrun;
            rate=u32(ivars->bytes);
            if(rate!=44100 && rate!=48000) return kIOReturnUnsupported;
            uint8_t payload[140]; setPayload(next,payload);
            ivars->session.beganWrite();
            ivars->stage=40;
            if((r=Command(0x3002,payload,140,nullptr,0))) return r;
            ivars->stage=50;
            Routes readback;
            if((r=ReadRoutes(&readback))) return r;
            if(!ivars->session.verify(next,readback)) return kIOReturnIOError;
            current=readback;
        }
        output[0]=ivars->firmware; output[1]=line3(ivars->session.original);
        for(size_t i=0;i<4;i++) output[i+2]=current.words[i+6];
        return kIOReturnSuccess;
    };
    auto result=perform(); if(selector!=3) ivars->lastError=result; IOLockUnlock(ivars->lock); return result;
}

// Mixer operations do not alter the mux or automatically attach a bus to an output.
kern_return_t ScarlettDriver::PerformMix(uint64_t selector,const uint64_t* input,uint64_t* output) {
    IOLockLock(ivars->lock);
    auto perform=[&]() -> kern_return_t {
        ivars->stage=0;
        if(selector<8 || (selector>11 && selector!=14) || (input[0]&255)>=MixCount || (input[0]>>8)>4) return kIOReturnBadArgument;
        if(ivars->startError) return ivars->startError;
        if(ivars->stopped || !ivars->opened) return kIOReturnNotAttached;
        if(!ivars->initialized) return kIOReturnNotReady; // Explicit routing Read re-handshakes.
        const unsigned mix=unsigned(input[0]&255);
        const unsigned outputIndex=(input[0]>>8) ? unsigned((input[0]>>8)-1) : 2;
        auto clock=[&]() -> kern_return_t {
            if(!ivars->clockSource) return kIOReturnUnsupported;
            uint16_t count=0;
            auto r=ivars->buffer->SetLength(4); if(r) return r;
            r=ivars->usb->DeviceRequest(0xa1,1,0x0100,uint16_t(ivars->clockSource)<<8,4,ivars->buffer,&count,1000);
            if(r) return r;
            if(count!=4) return kIOReturnUnderrun;
            const auto rate=u32(ivars->bytes);
            return rate==44100 || rate==48000 ? kIOReturnSuccess : kIOReturnUnsupported;
        };
        auto read=[&](MixRow& row) -> kern_return_t {
            uint8_t req[4], reply[16]; put16(req,mix); put16(req+2,MixInputs);
            auto r=Command(0x2001,req,4,reply,16); if(r) return r;
            return decodeMix(reply,16,row) ? kIOReturnSuccess : kIOReturnUnsupported;
        };
        ivars->stage=20;
        auto r=clock(); if(r) return r;
        Routes routes; if((r=ReadRoutes(&routes))) return r;
        MixRow current; if((r=read(current))) return r;
        auto& session=ivars->mixes[mix];
        if(selector==11) session.rebaseline(current,routes); // Explicit read-only acknowledgement; no SET_MIX.
        else if(selector==8) session.observe(current,routes);
        else {
            const MixRow wanted=unpackMix(input[1],input[2]);
            if(!validMix(wanted)) return kIOReturnBadArgument;
            if(!ivars->serial[0]) return kIOReturnNotPermitted;
            if(!session.captured) return kIOReturnNotReady;
            if(!isolatedMix(routes,mix,outputIndex) || !session.sameSources(routes)) return kIOReturnNotPermitted;
            if(selector==14 && !unusedMix(routes,mix)) return kIOReturnNotPermitted;
            if(!session.canWrite(current,routes,mix,selector==10 || selector==14,outputIndex)) return session.uncertain ? kIOReturnNotReady : kIOReturnBusy;
            if((r=clock())) return r;
            uint8_t payload[18]; if(!mixPayload(mix,wanted,payload)) return kIOReturnBadArgument;
            session.uncertain=true;
            ivars->stage=40;
            if((r=Command(0x2002,payload,18,nullptr,0))) return r;
            ivars->stage=50;
            MixRow actual; Routes after;
            if((r=read(actual))) return r;
            if((r=ReadRoutes(&after))) return r;
            if(!session.verify(wanted,actual,routes,after)) return kIOReturnIOError;
            current=actual;
        }
        uint16_t sources[8]; for(unsigned i=0;i<8;i++) sources[i]=(routes.words[10+i]>>12)&0xfff;
        output[0]=mix; output[1]=packMix(current.gain); output[2]=packMix(current.gain+4);
        output[3]=packMix(sources); output[4]=packMix(sources+4); output[5]=mixDestinations(routes,mix);
        return kIOReturnSuccess;
    };
    auto result=perform(); ivars->lastError=result;
    IOLockUnlock(ivars->lock); return result;
}

// Expands only empty input slots. Newly connected columns are silenced on ALL rows first.
kern_return_t ScarlettDriver::ExpandInputs(const uint64_t* input,uint64_t* output) {
    IOLockLock(ivars->lock);
    auto perform=[&]() -> kern_return_t {
        ivars->stage=0;
        if(ivars->startError) return ivars->startError;
        if(ivars->stopped || !ivars->opened) return kIOReturnNotAttached;
        if(!ivars->initialized || !ivars->serial[0] || !ivars->session.captured || ivars->session.uncertain) return kIOReturnNotReady;
        auto clock=[&]() -> kern_return_t {
            if(!ivars->clockSource) return kIOReturnUnsupported;
            uint16_t count=0;
            auto r=ivars->buffer->SetLength(4); if(r) return r;
            r=ivars->usb->DeviceRequest(0xa1,1,0x0100,uint16_t(ivars->clockSource)<<8,4,ivars->buffer,&count,1000);
            if(r) return r;
            return count==4 && (u32(ivars->bytes)==44100 || u32(ivars->bytes)==48000) ? kIOReturnSuccess : kIOReturnUnsupported;
        };
        auto readRow=[&](unsigned bus,MixRow& row) -> kern_return_t {
            uint8_t req[4],reply[16]; put16(req,bus); put16(req+2,MixInputs);
            auto r=Command(0x2001,req,4,reply,16); if(r) return r;
            return decodeMix(reply,16,row) ? kIOReturnSuccess : kIOReturnUnsupported;
        };
        auto r=clock(); if(r) return r;
        Routes before; if((r=ReadRoutes(&before))) return r;
        if(!same(before,ivars->session.expected)) return kIOReturnBusy;
        MixRow rows[MixCount];
        for(unsigned m=0;m<MixCount;m++) {
            if((r=readRow(m,rows[m]))) return r;
            auto& session=ivars->mixes[m];
            if(!session.captured || session.uncertain || !session.sameSources(before) || !sameMix(rows[m],session.expected)) return kIOReturnBusy;
        }
        // Compare the complete state saved by the app, including after resume acknowledgements.
        if(!expansionMatches(input,before,rows)) return kIOReturnBusy;
        InputExpansion plan;
        if(!expandInputs(before,rows,plan)) return kIOReturnNoSpace;
        output[0]=plan.added;
        if(!plan.added) return kIOReturnSuccess;
        // From here, partial writes are possible. App has already saved all routes and rows.
        ivars->stage=40; ivars->session.beganWrite();
        for(auto& session:ivars->mixes) session.uncertain=true;
        for(unsigned m=0;m<MixCount;m++) {
            if(sameMix(rows[m],plan.rows[m])) continue;
            if((r=clock())) return r;
            Routes check; if((r=ReadRoutes(&check))) return r;
            if(!same(before,check)) return kIOReturnBusy;
            MixRow fresh; if((r=readRow(m,fresh))) return r;
            if(!sameMix(fresh,rows[m])) return kIOReturnBusy;
            uint8_t payload[18]; mixPayload(m,plan.rows[m],payload);
            if((r=Command(0x2002,payload,18,nullptr,0))) return r;
            if((r=readRow(m,fresh))) return r;
            if(!sameMix(fresh,plan.rows[m])) return kIOReturnIOError;
        }
        // Verify all six rows before connecting new sources, including unchanged rows.
        for(unsigned m=0;m<MixCount;m++) { MixRow fresh; if((r=readRow(m,fresh))) return r; if(!sameMix(fresh,plan.rows[m])) return kIOReturnIOError; }
        Routes check; if((r=ReadRoutes(&check))) return r;
        if(!same(before,check)) return kIOReturnBusy;
        if((r=clock())) return r;
        uint8_t mux[140]; setPayload(plan.routes,mux);
        if((r=Command(0x3002,mux,140,nullptr,0))) return r;
        ivars->stage=50;
        Routes after; if((r=ReadRoutes(&after))) return r;
        if(!same(after,plan.routes)) return kIOReturnIOError;
        for(unsigned m=0;m<MixCount;m++) { MixRow fresh; if((r=readRow(m,fresh))) return r; if(!sameMix(fresh,plan.rows[m])) return kIOReturnIOError; }
        ivars->session.verify(plan.routes,after);
        for(unsigned m=0;m<MixCount;m++) ivars->mixes[m].rebaseline(plan.rows[m],after);
        return kIOReturnSuccess;
    };
    auto result=perform(); ivars->lastError=result; IOLockUnlock(ivars->lock); return result;
}
