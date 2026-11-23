#include <DriverKit/IOLib.h>
#include "ScarlettClient.h"
#include "ScarlettDriver.h"
struct ScarlettClient_IVars { ScarlettDriver* driver; };
bool ScarlettClient::init() { if(!super::init()) return false; ivars=IONewZero(ScarlettClient_IVars,1); return ivars!=nullptr; }
void ScarlettClient::free() { if(ivars) { OSSafeReleaseNULL(ivars->driver); IODelete(ivars,ScarlettClient_IVars,1); } super::free(); }
kern_return_t ScarlettClient::Start_Impl(IOService* provider) {
    auto result=Start(provider,SUPERDISPATCH); if(result) return result;
    ivars->driver=OSDynamicCast(ScarlettDriver,provider);
    if(!ivars->driver) return kIOReturnBadArgument;
    ivars->driver->retain(); return kIOReturnSuccess;
}
kern_return_t ScarlettClient::Stop_Impl(IOService* provider) { OSSafeReleaseNULL(ivars->driver); return Stop(provider,SUPERDISPATCH); }
kern_return_t ScarlettClient::ExternalMethod(uint64_t selector,IOUserClientMethodArguments* a,const IOUserClientMethodDispatch*,OSObject*,void*) {
    if(!a || selector>17 || a->completion || a->scalarInputCount!=(selector==15 ? 16u : (selector==9 || selector==10 || selector==14) ? 3u : 1u) || a->scalarOutputCount!=6 || !a->scalarInput || !a->scalarOutput || a->structureInput || a->structureInputDescriptor || a->structureOutputDescriptor || a->structureOutputMaximumSize) return kIOReturnBadArgument;
    if(!ivars->driver) return kIOReturnNotAttached;
    if(selector==15) return ivars->driver->ExpandInputs(a->scalarInput,a->scalarOutput);
    return ((selector>=8 && selector<=11) || selector==14) ? ivars->driver->PerformMix(selector,a->scalarInput,a->scalarOutput) : ivars->driver->Perform(selector,a->scalarInput[0],a->scalarOutput);
}
