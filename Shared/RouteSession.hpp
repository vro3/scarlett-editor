#pragma once
#include "Protocol.hpp"
namespace Scarlett {
// Hardware-independent transaction policy, shared by the driver and host tests.
struct RouteSession {
    Routes original{}, expected{};
    bool captured=false, uncertain=false;
    void observe(const Routes& routes) {
        if(!captured) { original=routes; expected=routes; captured=true; }
    }
    bool rebaseline(const Routes& routes) {
        if(uncertain) return false;
        original=routes; expected=routes; captured=true; return true;
    }
    enum Decision { ready, unread, recoveryRequired, drift };
    Decision prepare(const Routes& current, uint16_t source, bool restoring, Routes& next,unsigned output=2) const {
        if(!captured || output>=4) return unread;
        if(uncertain && !restoring) return recoveryRequired;
        // Explicit restore changes only Line 3, preserving current unrelated routing.
        if(!restoring && !same(current,expected)) return drift;
        next=current; setOutput(next,output,source); return ready;
    }
    void beganWrite() { uncertain=true; }
    bool verify(const Routes& intended,const Routes& actual) {
        if(!same(intended,actual)) return false;
        expected=actual; uncertain=false; return true;
    }
};
}
