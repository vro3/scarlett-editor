#include "Protocol.hpp"
#include <assert.h>
#include <stdio.h>
#include <random>
using namespace Scarlett;
int main() {
    Routes original; uint8_t wire[72]={};
    for(size_t i=0;i<RouteCount;i++) { original.words[i]=destination(i) | uint32_t(0x300+i%6)<<12; put32(wire+4*i,original.words[i]); }
    Routes parsed; assert(decode(wire,72,parsed)); assert(same(original,parsed));
    for(size_t n=0;n<72;n++) assert(!decode(wire,n,parsed));
    assert(!decode(wire,73,parsed));
    uint8_t bad[72]; memcpy(bad,wire,72); put32(bad+4,u32(bad)); assert(!decode(bad,72,parsed));
    memcpy(bad,wire,72); bad[3]=255; assert(!decode(bad,72,parsed));
    memcpy(bad,wire,72); put32(bad,0x123456); assert(!decode(bad,72,parsed));
    Routes changed=original; setLine3(changed,0x83); assert(line3(changed)==0x83);
    for(size_t i=0;i<RouteCount;i++) if(i!=8) assert(changed.words[i]==original.words[i]);
    uint8_t payload[140]; setPayload(changed,payload);
    assert(u32(payload)==0); assert(u32(payload+4+8*4)==0x83082);
    for(size_t i=76;i<140;i++) assert(payload[i]==0);
    setLine3(changed,line3(original)); assert(same(changed,original));
    uint8_t packet[256]; assert(request(0x3002,55,payload,140,packet,256)==156);
    assert(!request(0,1,nullptr,1,packet,256)); assert(!request(0,1,payload,141,packet,256)); assert(!request(0,1,payload,140,packet,155));
    assert(request(0x3001,2,wire,72,packet,256)==88); assert(response(packet,88,0x3001,2,72));
    for(size_t n=0;n<88;n++) assert(!response(packet,n,0x3001,2,72));
    assert(!response(packet,88,0x3001,3,72)); packet[8]=1; assert(!response(packet,88,0x3001,2,72));
    assert(request(0,1,nullptr,0,packet,256)==16); put16(packet+6,0); assert(response(packet,16,0,1,0));
    put32(packet,0x3001); assert(!response(packet,16,0x3001,1,0));
    for(unsigned s=0;s<=0xffff;s++) if(directSource(s)) assert(validSource(s));
    std::mt19937 random(42);
    for(int i=0;i<100000;i++) { for(auto& b:bad) b=random(); if(decode(bad,72,parsed)) { for(auto w:parsed.words) assert(validSource((w>>12)&0xfff)); } }
    puts("PASS: roundtrip, preservation, restore, truncated/oversize/duplicate/unknown routes, response identity/error/sequence, source whitelist, 100000 malformed routing tables");
}
