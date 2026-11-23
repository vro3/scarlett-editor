#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

// Wire-format facts: Linux sound/usb/mixer_scarlett2.c (4i4 Gen 3).
// Independently written, deliberately limited to the 44.1/48 kHz routing bank.
namespace Scarlett {
constexpr size_t RouteCount = 18;
constexpr uint16_t Line3 = 0x082;
inline uint16_t u16(const uint8_t* p) { return uint16_t(p[0]) | uint16_t(p[1]) << 8; }
inline uint32_t u32(const uint8_t* p) { return uint32_t(u16(p)) | uint32_t(u16(p+2)) << 16; }
inline void put16(uint8_t* p, uint16_t v) { p[0]=v; p[1]=v>>8; }
inline void put32(uint8_t* p, uint32_t v) { put16(p,v); put16(p+2,v>>16); }
inline bool validSource(uint16_t s) { return s==0 || (s>=0x80 && s<=0x83) || (s>=0x300 && s<=0x305) || (s>=0x600 && s<=0x603); }
inline bool directSource(uint16_t s) { return s==0 || (s>=0x80 && s<=0x83) || (s>=0x600 && s<=0x603); }
inline uint16_t destination(size_t i) { return i<6 ? 0x600+i : i<10 ? 0x80+i-6 : 0x300+i-10; }
struct Routes { uint32_t words[RouteCount] = {}; };
inline bool decode(const uint8_t* p, size_t n, Routes& out) {
    if(n!=RouteCount*4) return false;
    bool seen[RouteCount]={}; Routes parsed;
    for(size_t i=0;i<RouteCount;i++) {
        uint32_t w=u32(p+i*4); uint16_t dst=w&0xfff, src=(w>>12)&0xfff;
        if((w>>24) || !validSource(src)) return false;
        size_t j=0; while(j<RouteCount && destination(j)!=dst) j++;
        if(j==RouteCount || seen[j]) return false;
        seen[j]=true; parsed.words[j]=w;
    }
    out=parsed; return true;
}
inline uint16_t line3(const Routes& r) { return (r.words[8]>>12)&0xfff; }
inline bool same(const Routes& a,const Routes& b) { return memcmp(a.words,b.words,sizeof(a.words))==0; }
inline void setOutput(Routes& r,unsigned output,uint16_t s) { if(output<4) r.words[6+output]=destination(6+output) | uint32_t(s)<<12; }
inline void setLine3(Routes& r,uint16_t s) { r.words[8]=Line3 | uint32_t(s)<<12; }
inline void setPayload(const Routes& r,uint8_t (&p)[140]) {
    memset(p,0,sizeof(p)); // pad=0, bank=0; 18 routes + 16 empty slots
    for(size_t i=0;i<RouteCount;i++) put32(p+4+i*4,r.words[i]);
}
inline size_t request(uint32_t cmd,uint16_t seq,const uint8_t* payload,size_t size,uint8_t* out,size_t capacity) {
    if(size>140 || capacity<size+16 || (size && !payload)) return 0;
    memset(out,0,16); put32(out,cmd); put16(out+4,size); put16(out+6,seq);
    if(size) memcpy(out+16,payload,size); return size+16;
}
inline bool response(const uint8_t* p,size_t n,uint32_t cmd,uint16_t seq,size_t payloadSize) {
    return n==16+payloadSize && u32(p)==cmd && u16(p+4)==payloadSize &&
        (u16(p+6)==seq || (cmd<=2 && seq==1 && u16(p+6)==0)) && u32(p+8)==0 && u32(p+12)==0;
}
}
