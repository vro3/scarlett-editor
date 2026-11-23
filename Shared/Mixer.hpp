#pragma once
#include "Protocol.hpp"
namespace Scarlett {
constexpr unsigned MixCount=6, MixInputs=8;
constexpr uint16_t MaximumMixGain=32612; // floor(8192 * 10^(12/20)); unity = 8192
struct MixRow { uint16_t gain[MixInputs]={}; };
inline bool validMix(const MixRow& row) { for(auto g:row.gain) if(g>MaximumMixGain) return false; return true; }
inline bool sameMix(const MixRow& a,const MixRow& b) { return memcmp(a.gain,b.gain,sizeof(a.gain))==0; }
inline bool decodeMix(const uint8_t* bytes,size_t size,MixRow& row) {
    if(size!=16) return false;
    MixRow parsed; for(unsigned i=0;i<MixInputs;i++) parsed.gain[i]=u16(bytes+2*i);
    if(!validMix(parsed)) return false; row=parsed; return true;
}
inline bool mixPayload(unsigned mix,const MixRow& row,uint8_t (&bytes)[18]) {
    if(mix>=MixCount || !validMix(row)) return false;
    put16(bytes,mix); for(unsigned i=0;i<MixInputs;i++) put16(bytes+2+i*2,row.gain[i]); return true;
}
inline uint64_t packMix(const uint16_t* values) { uint64_t packed=0; for(unsigned i=0;i<4;i++) packed|=uint64_t(values[i])<<(i*16); return packed; }
inline MixRow unpackMix(uint64_t a,uint64_t b) { MixRow row; for(unsigned i=0;i<4;i++) { row.gain[i]=a>>(i*16); row.gain[i+4]=b>>(i*16); } return row; }
inline uint32_t mixDestinations(const Routes& routes,unsigned mix) {
    uint32_t mask=0; for(unsigned i=0;i<RouteCount;i++) if(((routes.words[i]>>12)&0xfff)==0x300+mix) mask|=1u<<i; return mask;
}
inline bool unusedMix(const Routes& routes,unsigned mix) { return mix<6 && mixDestinations(routes,mix)==0; }
inline bool isolatedMix(const Routes& routes,unsigned mix,unsigned output=2) { return output<4 && !(mixDestinations(routes,mix)&~(1u<<(6+output))); }
struct MixSession {
    MixRow expected{};
    uint16_t sources[MixInputs]={};
    bool captured=false, uncertain=false;
    void observe(const MixRow& row,const Routes& routes) {
        if(captured) return;
        expected=row; captured=true;
        for(unsigned i=0;i<MixInputs;i++) sources[i]=(routes.words[10+i]>>12)&0xfff;
    }
    void rebaseline(const MixRow& row,const Routes& routes) { captured=false; uncertain=false; observe(row,routes); }
    bool sameSources(const Routes& routes) const {
        for(unsigned i=0;i<MixInputs;i++) if(sources[i]!=((routes.words[10+i]>>12)&0xfff)) return false;
        return true;
    }
    bool canWrite(const MixRow& current,const Routes& routes,unsigned mix,bool restore,unsigned output=2) const {
        return captured && isolatedMix(routes,mix,output) && sameSources(routes) && (restore || (!uncertain && sameMix(current,expected)));
    }
    bool verify(const MixRow& wanted,const MixRow& actual,const Routes& before,const Routes& after) {
        if(!sameMix(wanted,actual) || !same(before,after)) return false;
        expected=actual; uncertain=false; return true;
    }
};
}
