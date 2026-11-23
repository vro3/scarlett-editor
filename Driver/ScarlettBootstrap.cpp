#include "ScarlettBootstrap.h"
kern_return_t ScarlettBootstrap::Start_Impl(IOService* provider) {
    auto result=Start(provider,SUPERDISPATCH); if(result) return result;
    return RegisterService();
}
kern_return_t ScarlettBootstrap::Stop_Impl(IOService* provider) { return Stop(provider,SUPERDISPATCH); }
