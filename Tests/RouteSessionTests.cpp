#include "RouteSession.hpp"
#include <cassert>
#include <cstdio>
using namespace Scarlett;
struct FakeDevice {
    Routes routes;
    unsigned writes=0;
    bool write(const Routes& next, bool loseReply=false) { routes=next; ++writes; return !loseReply; }
};
int main() {
    FakeDevice device;
    for(size_t i=0;i<RouteCount;i++) device.routes.words[i]=destination(i) | uint32_t(0x600+i%4)<<12;
    RouteSession session; Routes next;
    assert(session.prepare(device.routes,0,false,next)==RouteSession::unread);
    session.observe(device.routes);
    const Routes original=device.routes;
    // External edits: reads do not silently grant permission, Apply must refuse.
    device.routes.words[6]=0x80080;
    session.observe(device.routes);
    assert(session.prepare(device.routes,0,false,next)==RouteSession::drift);
    assert(device.writes==0);
    // Explicit baseline acknowledgement resolves drift without writing anything.
    assert(session.rebaseline(device.routes));
    assert(session.prepare(device.routes,0,false,next)==RouteSession::ready);
    session.beganWrite(); assert(!device.write(next,true));
    assert(session.uncertain);
    assert(!session.rebaseline(device.routes));
    assert(session.prepare(device.routes,0x601,false,next)==RouteSession::recoveryRequired);
    // Recovery uses current unrelated routes, even after drift while uncertain.
    device.routes.words[9]=0x83083;
    const auto unrelated=device.routes.words[9];
    assert(session.prepare(device.routes,line3(original),true,next)==RouteSession::ready);
    assert(next.words[9]==unrelated);
    session.beganWrite(); device.write(next);
    Routes wrong=device.routes; wrong.words[0]^=0x1000;
    assert(!session.verify(next,wrong)); assert(session.uncertain);
    assert(session.verify(next,device.routes)); assert(!session.uncertain);
    assert(line3(device.routes)==line3(original));
    // Driver restart + durable app source restores against a newly read table.
    RouteSession restarted; restarted.observe(device.routes);
    assert(restarted.prepare(device.routes,line3(original),true,next)==RouteSession::ready);
    assert(next.words[9]==unrelated);
    puts("PASS: fake-device unread/drift/rebaseline/lost-reply/recovery/full-readback/restart policy");
}
