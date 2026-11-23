#pragma once
#include "Mixer.hpp"
namespace Scarlett {
// Five 12-bit sources per scalar; four scalars cover all 18 canonical destinations.
inline uint64_t packInputRoutes(const Routes& routes,unsigned group) {
    uint64_t packed=0;
    for(unsigned i=0;i<5 && group*5+i<RouteCount;i++) packed|=uint64_t((routes.words[group*5+i]>>12)&0xfff)<<(i*12);
    return packed;
}
inline bool expansionMatches(const uint64_t* input,const Routes& routes,const MixRow (&rows)[MixCount]) {
    for(unsigned i=0;i<4;i++) if(input[i]!=packInputRoutes(routes,i)) return false;
    for(unsigned m=0;m<MixCount;m++) if(input[4+m*2]!=packMix(rows[m].gain) || input[5+m*2]!=packMix(rows[m].gain+4)) return false;
    return true;
}
struct InputExpansion {
    Routes routes;
    MixRow rows[MixCount];
    uint8_t added=0;
};
// Keep every occupied input in place. Fill only Off slots with missing direct sources.
inline bool expandInputs(const Routes& before,const MixRow (&rows)[MixCount],InputExpansion& plan) {
    plan={}; plan.routes=before;
    for(unsigned m=0;m<MixCount;m++) { if(!validMix(rows[m])) return false; plan.rows[m]=rows[m]; }
    const uint16_t wanted[]={0x80,0x81,0x82,0x83,0x600,0x601,0x602,0x603};
    for(auto source:wanted) {
        bool present=false;
        for(unsigned i=0;i<MixInputs;i++) if(((plan.routes.words[10+i]>>12)&0xfff)==source) present=true;
        if(present) continue;
        unsigned slot=0;
        while(slot<MixInputs && (plan.routes.words[10+slot]>>12)) slot++;
        if(slot==MixInputs) return false; // Never evict an existing source or duplicate.
        plan.routes.words[10+slot]=destination(10+slot)|(uint32_t(source)<<12);
        plan.added|=1u<<slot;
        for(auto& row:plan.rows) row.gain[slot]=0;
    }
    return true;
}
}
