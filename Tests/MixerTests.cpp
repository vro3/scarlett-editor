#include "Mixer.hpp"
#include "InputExpansion.hpp"
#include "RouteSession.hpp"
#include <cassert>
#include <cstdio>
using namespace Scarlett;
int main() {
    {
        Routes input; for(unsigned i=0;i<RouteCount;i++) input.words[i]=destination(i);
        const uint16_t sources[]={0x80,0x81,0x600,0x601,0,0,0,0};
        for(unsigned i=0;i<8;i++) input.words[10+i]|=uint32_t(sources[i])<<12;
        setOutput(input,0,0x300); setOutput(input,3,0x305);
        MixRow rows[6]; for(unsigned m=0;m<6;m++) for(unsigned i=0;i<8;i++) rows[m].gain[i]=1000+m*100+i;
        uint64_t args[16];
        for(unsigned i=0;i<4;i++) args[i]=packInputRoutes(input,i);
        for(unsigned m=0;m<6;m++) { args[4+m*2]=packMix(rows[m].gain); args[5+m*2]=packMix(rows[m].gain+4); }
        assert(expansionMatches(args,input,rows));
        for(unsigned i=0;i<18;i++) { Routes changed=input; changed.words[i]^=1u<<12; assert(!expansionMatches(args,changed,rows)); }
        for(unsigned m=0;m<6;m++) for(unsigned i=0;i<8;i++) { rows[m].gain[i]++; assert(!expansionMatches(args,input,rows)); rows[m].gain[i]--; }
        InputExpansion plan; assert(expandInputs(input,rows,plan)); assert(plan.added==0xf0);
        for(unsigned i=0;i<10;i++) assert(plan.routes.words[i]==input.words[i]);
        for(unsigned m=0;m<6;m++) for(unsigned i=0;i<8;i++) assert(plan.rows[m].gain[i]==(i<4 ? rows[m].gain[i] : 0));
        const uint16_t expected[]={0x80,0x81,0x600,0x601,0x82,0x83,0x602,0x603};
        for(unsigned i=0;i<8;i++) assert((plan.routes.words[10+i]>>12)==expected[i]);
        InputExpansion again; assert(expandInputs(plan.routes,plan.rows,again)); assert(again.added==0);
        // Full/duplicate or internal-mix assignments are not evicted to make space.
        Routes full=input; for(unsigned i=4;i<8;i++) full.words[10+i]|=uint32_t(0x300)<<12;
        assert(!expandInputs(full,rows,again));
        rows[5].gain[7]=65535; assert(!expandInputs(input,rows,again));
        puts("PASS: shared input expansion preserves occupied slots and silences new columns on all six rows");
    }

    MixRow row; row.gain[0]=8192; row.gain[1]=4096; row.gain[2]=32612;
    uint8_t payload[18]; assert(mixPayload(5,row,payload));
    assert(u16(payload)==5 && u16(payload+2)==8192 && u16(payload+4)==4096 && u16(payload+6)==32612);
    MixRow decoded; assert(decodeMix(payload+2,16,decoded)); assert(sameMix(row,decoded));
    assert(!decodeMix(payload+2,15,decoded)); assert(!decodeMix(payload+2,17,decoded));
    assert(!mixPayload(6,row,payload));
    MixRow invalid=row; invalid.gain[7]=32613; assert(!mixPayload(0,invalid,payload));
    assert(sameMix(row,unpackMix(packMix(row.gain),packMix(row.gain+4))));
    Routes routes; for(unsigned i=0;i<RouteCount;i++) routes.words[i]=destination(i);
    routes.words[10]=0x80000 | destination(10);
    MixSession session; assert(!session.canWrite(row,routes,0,false)); session.observe(row,routes);
    assert(session.canWrite(row,routes,0,false));
    // Assigning this mix to Line 3 is allowed; other outputs/loopback/mixer inputs are not.
    setLine3(routes,0x300); assert(session.canWrite(row,routes,0,false));
    for(unsigned i=0;i<RouteCount;i++) if(i!=8) {
        auto shared=routes; shared.words[i]=uint32_t(0x300)<<12 | destination(i);
        assert(!session.canWrite(row,shared,0,false)); assert(!session.canWrite(row,shared,0,true));
    }
    auto reassigned=routes; reassigned.words[10]=uint32_t(0x81)<<12 | destination(10);
    assert(!session.canWrite(row,reassigned,0,false)); assert(!session.canWrite(row,reassigned,0,true));
    MixRow muted=row; muted.gain[0]=0;
    for(unsigned i=1;i<8;i++) assert(muted.gain[i]==row.gain[i]);
    session.uncertain=true; // Simulated uncertain state, not a transport/ACK test.
    assert(!session.canWrite(muted,routes,0,false)); assert(session.canWrite(muted,routes,0,true));
    assert(!session.verify(row,muted,routes,routes)); assert(session.uncertain);
    auto changedRoutes=routes; changedRoutes.words[6]^=0x1000;
    assert(!session.verify(muted,muted,routes,changedRoutes));
    assert(session.verify(muted,muted,routes,routes)); assert(!session.uncertain);

    assert(!session.canWrite(row,routes,0,false)); // External gain drift.
    assert(session.canWrite(row,routes,0,true));
    session.rebaseline(muted,reassigned);
    assert(session.canWrite(muted,reassigned,0,false));
    assert(!session.uncertain);
    for(unsigned output=0;output<4;output++) {
        Routes base; for(unsigned i=0;i<RouteCount;i++) base.words[i]=destination(i);
        setOutput(base,output,0x300);
        assert(isolatedMix(base,0,output));
        for(unsigned other=0;other<4;other++) if(other!=output) assert(!isolatedMix(base,0,other));
        RouteSession routeSession; routeSession.observe(base); Routes next;
        assert(routeSession.prepare(base,0x81,false,next,output)==RouteSession::ready);
        for(unsigned i=0;i<RouteCount;i++) assert(next.words[i]==(i==6+output ? (uint32_t(0x81)<<12)|destination(i) : base.words[i]));
    }
    Routes unused; for(unsigned i=0;i<RouteCount;i++) unused.words[i]=destination(i);
    assert(unusedMix(unused,0));
    for(unsigned i=0;i<RouteCount;i++) {
        auto attached=unused; attached.words[i]=uint32_t(0x300)<<12|destination(i);
        assert(!unusedMix(attached,0)); // Detached-only restore refuses every destination, including selected output.
    }
    puts("PASS: GET/SET_MIX layout, bounds, packing, shared-destination and remap guards, simulated uncertainty/drift, verification policy and explicit rebaseline");
}
