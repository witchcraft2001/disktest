'use strict';
const fs = require('fs'), assert = require('assert');
global.window = {};
const Z80 = require('./Z80core');
const symbols = Object.fromEntries(fs.readFileSync(process.env.DISKTEST_SYM || 'build/disktest.sym','utf8').trim().split('\n').map(l=>{const m=l.match(/^(.*): EQU 0x([0-9a-f]+)/i);return m?[m[1],parseInt(m[2],16)]:[];}));
assert(symbols.EXEend < 0xbb80, 'test return address must be outside program and SRAM');
const bin = fs.readFileSync(process.env.DISKTEST_EXE || 'DISKTEST.EXE');
function machine(options={}) {
 const ram=new Uint8Array(65536), cache=new Uint8Array(16384).fill(0xa6), pages=Array.from({length:32},()=>new Uint8Array(16384));
 ram.set(bin,0x80ea); let injectedCTC=false,injectedDSS=false;let nested=false;let createNames=[],deleteNames=[];let passes=[];let on=false, win0=0x40, page=255, nextPage=0, allocations={}, nextMem=1, steps=0, io=[], text='', file=[], pos=0, deletes=0, closed=0, status=0x40, fifo=[], cmdCount=0, lba=0, multi=0, reads=0, dataReads=0;
 const addr = a=>a&65535;
 const rd = a=>{a=addr(a);return on&&a<16384?cache[a]:a>=0x4000&&a<0x8000&&page<pages.length?pages[page][a-0x4000]:ram[a];};
 const wr = (a,v)=>{a=addr(a);if(on&&a<16384)cache[a]=v;else if(a>=0x4000&&a<0x8000&&page<pages.length)pages[page][a-0x4000]=v;else ram[a]=v;};
 const word=(name,v)=>{let a=typeof name==='string'?symbols[name]:name;if(v===undefined)return rd(a)|rd(a+1)<<8;wr(a,v);wr(a+1,v>>8);};
 const byte=(name,v)=>{let a=symbols[name];if(v===undefined)return rd(a);wr(a,v);};
 function dataSector(n) {return options.disk?options.disk(n):Uint8Array.from({length:512},(_,i)=>(n*17+i*7+(i>>8)*19)&255);}
 const cpu=new Z80({mem_read:rd,mem_write:wr,io_read:p=>{
  if((p&255)===0xfb){on=true;return 0;} if((p&255)===0x7b){on=false;return 0;} if((p&255)===0x82)return win0; if((p&255)===0xa2)return page;
  if(p===0x4053)return options.status??status;
  if(p===0x0051)return 4;
  if((p&255)===0x50){assert(fifo.length,'unexpected data read');dataReads++;let v=fifo.shift();if(!fifo.length)status=options.errorDrq?0x41:0x40;return v;}
  if(p===symbols.CMOS_DRD)return options.stoppedRtc?0:Math.floor(steps/10000)%60;
  return 0;
 },io_write:(p,v)=>{
  if((p&255)===0x82){win0=v;return;} if((p&255)===0xa2){page=v;return;} io.push([p,v]);
  if(p===0x152)cmdCount=v;
  if(p===0x153)lba=(lba&0xffff00)|v;
  if(p===0x154)lba=(lba&0xff00ff)|(v<<8);
  if(p===0x155)lba=(lba&0x00ffff)|(v<<16);
  if(p===0x4153){
   if(v===0x20||v===0xc4){fifo=[];for(let i=0;i<(options.errorDrq?Math.min(cmdCount,4):cmdCount);i++)fifo.push(...dataSector(lba+i));status=options.errorDrq?0x49:0x48;}
   if(v===0xc6){multi=cmdCount;status=options.rejectSet?0x41:0x40;}
   if(v===0xec){fifo=Array(512).fill(0);fifo[94]=options.multiMax??4;fifo[99]=2;fifo[118]=options.restoreMismatch?multi+1:multi;fifo[119]=1;status=0x48;}
  }
 }});
 const hl=s=>s.h<<8|s.l, de=s=>s.d<<8|s.e;
 const setde=(s,v)=>{s.d=v>>8;s.e=v&255;};
 const ret=s=>{s.pc=word(s.sp);s.sp+=2;cpu.setState(s);};
 function syscall(s) {
  assert.equal(win0,0x40,"DSS entered with corrupted WIN0 mapping");
  s.flags.C=0;
  switch(s.c){
   case 0x41:s.pc=0xbb80;cpu.setState(s);return;
   case 0x5c: {let a=hl(s);while(rd(a))text+=String.fromCharCode(rd(a++));break;}
   case 0x0b: {let a=hl(s),name='';while(rd(a))name+=String.fromCharCode(rd(a++));createNames.push(name);
    if(options.conflict||createNames.length<=(options.occupiedNames||0)){s.flags.C=1;s.a=options.createError??(options.occupiedNames?7:0);}else {s.a=0;file=[];}break;}

   case 0x11:s.a=options.openError||0;s.flags.C=options.openError?1:0;pos=0;break;
   case 0x12:closed++;s.a=options.closeError||0;s.flags.C=options.closeError?1:0;break;
   case 0x0e:deletes++;{let a=hl(s),name='';while(rd(a))name+=String.fromCharCode(rd(a++));deleteNames.push(name);}break;
   case 0x14:{if(options.writeError){s.a=options.writeError;s.flags.C=1;break;}let n=de(s);if(options.shortWrite)n--;for(let i=0;i<n;i++)file.push(rd(hl(s)+i));pos+=n;setde(s,options.writeDE??0);break;}
   case 0x15:{const offset=(hl(s)*65536+s.ix)>>>0;const origin=s.b===0?0:s.b===1?pos:file.length;pos=(origin+offset)>>>0;s.h=pos>>>24;s.l=(pos>>>16)&255;s.ix=pos&65535;break;}
   case 0x13:{let n=Math.min(de(s),file.length-pos);if(options.shortRead&&pos===0)n=1;for(let i=0;i<n;i++)wr(hl(s)+i,file[pos+i]);pos+=n;setde(s,n);reads++;break;}
   case 0x31:s.flags.Z=(options.cancel||options.key!==undefined)?0:1;s.a=options.key??(options.cancel?0x1b:0x1b);break;
   case 0x21:s.h=options.badTime?25:0;s.l=0;s.b=Math.floor(steps/10000)%60;s.flags.C=options.timeError?1:0;break;
   case 0x3d:if(options.noMemory||nextMem===options.failAllocation){s.flags.C=1;s.a=0x0a;break;}allocations[nextMem]=nextPage;nextPage+=s.b;s.a=nextMem++;break;
   case 0x39:{const old=page;page=allocations[s.a]+s.b;s.a=old;break;}
   case 0x19: {let a=de(s);for(let i=0;i<44;i++)wr(a+i,0);word(a+26,options.firstCluster||2);word(a+28,(word('FileBlocks')*512)&65535);word(a+30,word('FileBlocks')>>7);break;}
   default:throw new Error('unhandled DSS '+s.c.toString(16));
  }ret(s);
 }
 function call(name,regs={},limit=10000000){let s=cpu.getState();Object.assign(s,{pc:symbols[name],sp:0xbf00},regs);word(0xbf00,0xbb80);cpu.setState(s);
  for(let n=0;n<limit;n++){s=cpu.getState();if(s.pc===0xbb80)return s;
   if([symbols.FileReadPass,symbols.BiosReadPass,symbols.AtaReadPass].includes(s.pc))passes.push([byte('VerifyPass'),byte('SeriesIndex'),byte('PeerNow')]);
   if(on&&byte('CacheActive')&&((options.injectCTC&&!injectedCTC&&dataReads>0)||(options.injectDSS&&!injectedDSS&&dataReads>2))){
    const ctc=options.injectCTC&&!injectedCTC;
    if(ctc)injectedCTC=true;else injectedDSS=true;
    s.sp-=2;word(s.sp,s.pc);s.pc=symbols[ctc?'TickHandler':'DefaultHandler'];cpu.setState(s);continue;
   }
   steps++; if(steps%100===0){const t=word('Ticks')+1;word('Ticks',t);}
   if(s.pc===0x10)syscall(s);
   else if(s.pc===8){assert.equal(s.c,0x55);let n=(hl(s)*65536+s.ix)>>>0;for(let k=0;k<s.b;k++){const dat=dataSector(n+k);for(let j=0;j<512;j++)wr(de(s)+k*512+j,dat[j]);}s.flags.C=0;ret(s);}
   else if(s.pc===0x38){assert(!on, "DSS IRQ entered with SRAM mapped");
    if(options.nestedIRQ&&!nested){nested=true;s.sp-=2;word(s.sp,0x38);s.pc=symbols.DefaultHandler;cpu.setState(s);}
    else ret(s);
   }
   else cpu.run_instruction();
  }throw Error(name+' instruction limit pc='+cpu.getState().pc.toString(16));
 }
 word('TicksPerSec',100);byte('VerboseOutput',options.compact?0:1);return {ram,cache,pages,rd,wr,word,byte,call,get interrupts(){return [injectedCTC,injectedDSS];},get createNames(){return createNames;},get deleteNames(){return deleteNames;},get passes(){return passes;},get text(){return text;},get deletes(){return deletes;},get file(){return file;},get win0(){return win0;},get page(){return page;},get on(){return on;},set on(v){on=v;},get io(){return io;},get reads(){return reads;},get dataReads(){return dataReads;}};
}
function check(name,fn){if(process.env.TEST_FILTER&&!new RegExp(process.env.TEST_FILTER).test(name))return;fn();console.log('PASS '+name);}
check('temporary file ownership and handle zero',()=>{let m=machine({conflict:true});assert(m.call('CreateFile').flags.C);m.call('DeleteTestFile');assert.equal(m.deletes,0);m=machine();m.word('FileBlocks',8);assert(!m.call('CreateFile').flags.C);assert.equal(m.file.length,4096);assert.equal(m.byte('FileOpen'),1);m.call('DeleteTestFile');m.call('DeleteTestFile');assert.equal(m.deletes,1);});
check('short write fails',()=>{const m=machine({shortWrite:true});m.word('FileBlocks',8);assert(m.call('CreateFile').flags.C);});
check('file warmup + 1/3/5 samples, all block sizes',()=>{for(const repeat of [1,3,5])for(const size of [512,2048,4096,8192,16384]){let m=machine();m.word('FileBlocks',40);assert(!m.call('CreateFile').flags.C);m.byte('RepeatCount',repeat);const s=m.call('TestConsistentRead',{h:symbols.TestSize512BStr>>8,l:symbols.TestSize512BStr&255,d:size>>8,e:0});assert(!s.flags.C,m.text);assert(m.text.includes('Median:'),m.text);assert(!m.text.includes('MISMATCH'));}});
check('full pattern detects half swap',()=>{const m=machine();m.call('FillPattern');const a=m.ram.slice(0xc000,0xc100);m.ram.copyWithin(0xc000,0xc100,0xc200);m.ram.set(a,0xc100);m.byte('VerifyPass',1);m.byte('VerifyFile',1);assert(m.call('VerifyBlock',{a:1}).flags.C);});
check('SRAM restore exact',()=>{const m=machine();for(let i=0;i<m.cache.length;i++)m.cache[i]=(i*71^(i>>8))&255;const before=m.cache.slice();assert(!m.call('CacheInit').flags.C);assert(!m.on);assert.notDeepEqual(m.cache,before);m.call('CacheDeinit');assert.deepEqual(m.cache,before);assert(!m.on);});
check('DRAM/SRAM ATA transfer byte equality, all sizes/modes',()=>{for(const cache of [0,1])for(const count of [1,4,8,16,32])for(const mode of [0,1]){const m=machine();if(cache)m.call('CacheInit');m.byte('UseCache',cache);m.byte('AtaMultiN',4);m.byte('AtaMode',mode);m.byte('AtaLeft',count);m.word('CurLBA',7);const s=m.call('AtaTransfer',{a:mode?0xc4:0x20,b:count});assert(!s.flags.C);for(let i=0;i<count*512;i++)assert.equal(m.rd(0xc000+i),((7+(i>>9))*17+(i%512)*7+((i%512)>>8)*19)&255);assert(!m.on);}});
check('LBA28 wrap rejected before command',()=>{const m=machine();m.word('CurLBA',0xfff0);m.word('CurLBA+2' in symbols?'CurLBA+2':symbols.CurLBA+2,0x0fff);assert(m.call('AtaTransfer',{a:0x20,b:32}).flags.C);assert(!m.io.some(([p])=>p===0x4153));});
check('MULTIPLE disabled state restored',()=>{const m=machine();m.word('AtaMultiOld',0x0100);assert(!m.call('AtaRestoreMultiple').flags.C,m.text);});
function fatFixture(type, count, spc=1, fragmented=true) {
 const total=type===12?3000:type===16?50000*spc:100000, fatSize=type===12?9:type===16?196:782, reserved=type===32?32:1, root=type===32?0:1;
 const active=type===32?1:0, fats=type===32?2:1, start=reserved+fatSize*fats+root;
 const boot=new Uint8Array(512), fat=new Uint8Array(fatSize*512);const w=(a,v)=>{boot[a]=v;boot[a+1]=v>>8;},dw=(a,v)=>{w(a,v);w(a+2,v>>>16);};
 w(11,512);boot[13]=spc;w(14,reserved);boot[16]=fats;w(17,type===32?0:16);dw(32,total);w(510,0xaa55);
 if(type===32){dw(36,fatSize);w(40,0x81);}else w(22,fatSize);
 const n=Math.ceil(count/spc), clusters=Array.from({length:n},(_,i)=>2+i*(fragmented?2:1));
 for(let i=0;i<n;i++){let c=clusters[i],v=i+1<n?clusters[i+1]:type===12?0xfff:type===16?0xffff:0x0fffffff;
  if(type===12){let p=c+(c>>1);let x=fat[p]|fat[p+1]<<8;x=c&1?(x&15)|(v<<4):(x&0xf000)|v;fat[p]=x;fat[p+1]=x>>8;}
  else {let p=c*(type/8);for(let j=0;j<type/8;j++)fat[p+j]=v>>>(j*8);}
 }
 const index=new Map(clusters.map((c,i)=>[c,i]));
 const disk=lba=>{if(lba===0)return boot;if(lba>=reserved+active*fatSize&&lba<reserved+(active+1)*fatSize)return fat.slice((lba-reserved-active*fatSize)*512,(lba-reserved-active*fatSize+1)*512);
  const c=2+Math.floor((lba-start)/spc),ix=index.get(c),sector=ix*spc+(lba-start)%spc;
  return Uint8Array.from({length:512},(_,i)=>i&1?sector>>8:(sector^(i>>1))&255);
 };return {disk,total,clusters,start,fat,boot};
}
check('fragmented FAT12/16/32 including active FAT32 and mapped reads',()=>{for(const type of [12,16,32]){const f=fatFixture(type,40);const m=machine({disk:f.disk});m.word('FileBlocks',40);m.word('PartSize',f.total);m.word(symbols.PartSize+2,f.total>>>16);m.byte('RepeatCount',1);assert(!m.call('MapPrepare').flags.C,`FAT${type}: ${m.text}`);assert(m.byte('MapValid'));assert(!m.call('MapRun').flags.C,`FAT${type}: ${m.text}`);assert(!m.text.includes('MISMATCH'),m.text);}});
check('map page crossing and short last cluster',()=>{for(const [count,spc] of [[4104,1],[40,16]]){const f=fatFixture(16,count,spc);const m=machine({disk:f.disk});m.word('FileBlocks',count);m.word('PartSize',f.total);m.word(symbols.PartSize+2,f.total>>>16);assert(!m.call('MapPrepare',{},50000000).flags.C,m.text);m.byte('RepeatCount',1);assert(!m.call('MapRun',{},250000000).flags.C,m.text);}});
check('cyclic FAT chain rejected',()=>{const f=fatFixture(16,40);f.fat[4]=2;f.fat[5]=0;const m=machine({disk:f.disk});m.word('FileBlocks',40);m.word('PartSize',f.total);assert(m.call('MapPrepare').flags.C);assert(!m.byte('MapValid'));});
check('paired file/BIOS alternating series',()=>{const f=fatFixture(16,40,4);const m=machine({disk:f.disk});m.word('FileBlocks',40);m.word('PartSize',f.total);m.word(symbols.PartSize+2,f.total>>>16);assert(!m.call('CreateFile').flags.C);assert(!m.call('MapPrepare').flags.C);const label=symbols.TestSize4KBStr;assert(!m.call('TestConsistentRead',{h:label>>8,l:label&255,d:16,e:0}).flags.C,m.text);assert.equal((m.text.match(/Median:/g)||[]).length,2,m.text);assert(m.byte('MapPaired'));assert.deepEqual(m.passes,[[1,0,0],[1,0,1],[0,0,0],[0,0,1],[0,1,1],[0,1,0],[0,2,0],[0,2,1]]);});
check('paired DRAM/SRAM alternating series',()=>{const m=machine();m.word('BiosSectors',40);m.byte('AtaMultiN',4);assert(!m.call('CacheInit').flags.C);const label=symbols.TestSize4KBStr;assert(!m.call('TestAtaRead',{h:label>>8,l:label&255,e:8,c:1}).flags.C,m.text);assert.equal((m.text.match(/Median:/g)||[]).length,2,m.text);assert.deepEqual(m.passes,[[1,0,0],[1,0,1],[0,0,0],[0,0,1],[0,1,1],[0,1,0],[0,2,0],[0,2,1]]);assert(!m.on);});
check('partial byte read and premature EOF fail',()=>{const m=machine({shortRead:true});m.word('FileBlocks',8);m.call('CreateFile');m.byte('RepeatCount',1);const label=symbols.TestSize512BStr;assert(m.call('TestConsistentRead',{h:label>>8,l:label&255,d:2,e:0}).flags.C);const n=machine();n.word('FileBlocks',8);n.call('CreateFile');n.word('FileBlocks',16);assert(n.call('TestConsistentRead',{h:label>>8,l:label&255,d:2,e:0}).flags.C);});
check('DF/ERR recognized, BSY masks other bits',()=>{for(const status of [0x20,0x41,0xc9]){const m=machine({status});assert(m.call('AtaWaitDrq').flags.C);assert.equal(m.byte('AtaStatus'),status);}});
check('unavailable timer prints no speed; zero duration prints no speed',()=>{let m=machine();m.byte('TimerMode',2);m.call('PrintResult',{h:0,l:8});assert(!m.text.includes('KiB/s'));m=machine({stoppedRtc:true});m.byte('TimerMode',1);m.call('PrintResult',{h:0,l:8});assert(!m.text.includes('KiB/s'));});

check('IRQ bridge restores CACHE and registers',()=>{for(const active of [0,1]){const m=machine();m.byte('CacheActive',active);m.on=!!active;const s=m.call('DefaultHandler',{a:0x51,b:0x12,c:0x34,d:0x56,e:0x78,h:0x9a,l:0xbc});assert.equal(m.on,!!active);assert.equal(s.a,0x51);assert.equal(s.b,0x12);assert.equal(s.l,0xbc);}});
check('read-only/help modes and startup failure do not delete',()=>{for(const arg of ['/H','/B','/A','/C','/?']){const m=machine();const a=0x6000;m.ram.set(Buffer.from('xx'+arg+'\0'),a);m.call('ParseArguments',{h:a>>8,l:a&255});m.call('Exit');assert.equal(m.deletes,0);}const m=machine({conflict:true});m.call('CreateFile');m.call('Exit');assert.equal(m.deletes,0);});
check('unsigned 32-bit sample median and extrema',()=>{const m=machine();m.byte('RepeatCount',5);const times=[0x10002,200,0x10001,0x20000,400];times.forEach((t,i)=>{m.word(symbols.SeriesTimes+i*4,t);m.word(symbols.SeriesTimes+i*4+2,t>>>16);});m.word('SeriesSectors',8);m.call('SeriesSummary');const actual=times.map((_,i)=>m.word(symbols.SeriesTimes+i*4)+65536*m.word(symbols.SeriesTimes+i*4+2));assert.deepEqual(actual,[200,400,0x10001,0x10002,0x20000]);});

check('DRQ+ERR drains the erroneous MULTIPLE block before reporting',()=>{for(const n of [3,8]){const m=machine({errorDrq:true});m.byte('AtaMultiN',4);m.byte('AtaMode',1);m.byte('AtaLeft',n);assert(m.call('AtaTransfer',{a:0xc4,b:n}).flags.C);assert.equal(m.dataReads,Math.min(n,4)*512);m.call('AtaRecover');assert.equal(m.dataReads,Math.min(n,4)*512);}});
check('SET MULTIPLE rejection and restore mismatch are reported',()=>{let m=machine({rejectSet:true});assert(m.call('AtaSetMultiple',{a:4}).flags.C);m=machine({restoreMismatch:true});m.word('AtaMultiOld',0x0100);assert(m.call('AtaRestoreMultiple').flags.C);assert(m.text.includes('restore/verify failed'));});
check('stopped RTC calibration is bounded',()=>{const m=machine({stoppedRtc:true});m.call('TimerCalibrate',{},60000000);assert.equal(m.byte('TimerMode'),2);});

check('FAT12 packed entry crossing and maximum 64KiB map',()=>{for(const [type,count] of [[12,400],[16,16384]]){const f=fatFixture(type,count);const m=machine({disk:f.disk});m.word('FileBlocks',count);m.word('PartSize',f.total);assert(!m.call('MapPrepare',{},100000000).flags.C,m.text);for(const i of [0,Math.min(count-1,341),count-1]){const pg=i>>12,a=(i&4095)*4;const actual=m.pages[pg][a]|m.pages[pg][a+1]<<8|m.pages[pg][a+2]<<16|m.pages[pg][a+3]<<24;assert.equal(actual,f.start+(f.clusters[i]-2));}}});

check('mapped partition offset and 16-bit LBA carry',()=>{const f=fatFixture(16,40,4),base=0x1fffe;const m=machine({disk:lba=>f.disk(lba-base)});m.word('FileBlocks',40);m.word('PartSize',f.total);m.word(symbols.PartSize+2,f.total>>>16);m.word('PartStart',base);m.word(symbols.PartStart+2,base>>>16);assert(!m.call('MapPrepare').flags.C,m.text);m.byte('RepeatCount',1);assert(!m.call('MapRun').flags.C,m.text);});
check('SRAM cancellation/error exit restores bytes and mapping',()=>{for(const options of [{cancel:true},{status:0x20}]){const m=machine(options),before=m.cache.slice();m.call('CacheInit');m.byte('UseCache',1);m.word('BiosSectors',128);const label=symbols.TestSize16KBStr;const s=m.call('TestAtaRead',{h:label>>8,l:label&255,e:32,c:0});assert(s.flags.C);assert(!m.on);m.call('Exit');assert.deepEqual(m.cache,before);assert(!m.on);}});

check('nested DSS interrupt keeps CACHE off until outer handler returns',()=>{const m=machine({nestedIRQ:true});m.byte('CacheActive',1);m.on=true;m.call('DefaultHandler');assert(m.on);assert.equal(m.byte('CacheActive'),1);});
check('32-bit wrap and out-of-range LBA rejected before issuing command',()=>{for(const [hi,lo,n] of [[0xffff,0xffff,2],[0x1000,0,1],[0x0fff,0xffff,2]]){const m=machine();m.word('CurLBA',lo);m.word(symbols.CurLBA+2,hi);assert(m.call('AtaTransfer',{a:0x20,b:n}).flags.C);assert(!m.io.some(([p])=>p===0x4153));}});
check('FAT reserved cluster markers rejected independently of BPB count',()=>{for(const [type,cluster] of [[12,0xff0],[12,0xff7],[16,0xfff0],[16,0xfff7],[32,0xffffff0],[32,0xffffff7]]){const m=machine();m.byte('MapFatType',type);m.word('MapCluster',cluster);m.word(symbols.MapCluster+2,cluster>>>16);m.word('MapClusters',0xffff);m.word(symbols.MapClusters+2,0xffff);assert(m.call('MapClusterLba').flags.C);}});
check('coarse RTC provenance is isolated for each paired implementation',()=>{const m=machine();m.byte('VerifyPass',0);m.byte('PeerNow',1);m.byte('TimerMode',1);m.call('SeriesFinish',{h:0,l:8});assert.equal(m.byte('SeriesPeerRtc'),1);assert.equal(m.byte('SeriesRtc'),0);m.byte('PeerNow',0);m.byte('TimerMode',0);m.call('SeriesFinish',{h:0,l:8});assert.equal(m.byte('SeriesRtc'),0);});

check('failed or invalid SysTime suppresses speed',()=>{for(const options of [{badTime:true},{timeError:true}]){const m=machine(options);m.call('TimerStart');assert.equal(m.byte('TimerMode'),2);m.call('PrintResult',{h:0,l:8});assert(!m.text.includes('KiB/s'));}});
check('write benchmark restored with generated pattern outside measured I/O',()=>{const m=machine();m.word('FileBlocks',16);assert(!m.call('CreateFile').flags.C);assert(m.text.includes('Write 4KB:'));assert(m.text.includes('KiB/s'));assert.equal(m.file.length,8192);const n=machine();n.byte('TimerMode',1);n.word('FileBlocks',8);assert(!n.call('CreateFile').flags.C);assert(n.text.includes('speed omitted'));assert(!n.text.includes('KiB/s'));});
check('mapped partition wrapping absolute LBA is rejected',()=>{const f=fatFixture(16,40);const base=0xffff0000,m=machine({disk:lba=>f.disk((lba-base)>>>0)});m.word('FileBlocks',40);m.word('PartSize',f.total);m.word('PartStart',0xfff0);m.word(symbols.PartStart+2,0xffff);assert(m.call('MapPrepare').flags.C);});

check('CTC and DSS interrupts during SRAM PIO preserve transfer and CACHE',()=>{const m=machine({injectCTC:true,injectDSS:true});m.call('CacheInit');m.byte('UseCache',1);m.byte('AtaLeft',4);m.word('CurLBA',7);assert(!m.call('AtaTransfer',{a:0x20,b:4}).flags.C);assert.deepEqual(m.interrupts,[true,true]);for(let i=0;i<2048;i++)assert.equal(m.rd(0xc000+i),((7+(i>>9))*17+(i%512)*7+((i%512)>>8)*19)&255);assert(!m.on);});

check('unsupported MULTIPLE is skipped and nonzero original setting restored',()=>{let m=machine({multiMax:0});m.word('BiosSectors',8);m.byte('RepeatCount',1);assert(!m.call('AtaTests').flags.C,m.text);assert(!m.io.some(([p,v])=>p===0x4153&&(v===0xc4||v===0xc6)));m=machine();m.word('AtaMultiOld',0x0102);assert(!m.call('AtaRestoreMultiple').flags.C,m.text);assert(m.io.some(([p,v])=>p===0x152&&v===2));});

check('file diagnostics preserve exact operation and DSS error code',()=>{for(const [options,stage,code] of [[{conflict:true,createError:6},'create','06'],[{writeError:10},'write','0A'],[{closeError:5},'close','05'],[{openError:8},'open for reading','08']]){const m=machine(options);m.word('FileBlocks',8);const s=m.call('CreateFile');assert(s.flags.C);assert.equal(s.a,2);assert(m.text.includes('File error: '+stage+' DISKTEST.$$$: DSS #'+code),m.text);}});
check('short write diagnostic reports actual byte count',()=>{const m=machine({shortWrite:true});m.word('FileBlocks',8);assert(m.call('CreateFile').flags.C);assert(m.text.includes('Written file length: #00000FFF bytes, expected #00001000'),m.text);});
check('occupied temporary names preserved and unused exclusive name chosen',()=>{const m=machine({occupiedNames:2});m.word('FileBlocks',8);assert(!m.call('CreateFile').flags.C,m.text);assert.deepEqual(m.createNames,['DISKTEST.$$$','DISKT000.$$$','DISKT001.$$$']);m.call('Exit');assert.deepEqual(m.deleteNames,['DISKT001.$$$']);});
check('non-collision creation failure is not retried',()=>{const m=machine({conflict:true,createError:10});assert(m.call('CreateFile').flags.C);assert.equal(m.createNames.length,1);assert.equal(m.byte('FileOwned'),0);m.call('Exit');assert.equal(m.deletes,0);});

check('successful writes ignore zero or arbitrary DE returned by DSS',()=>{for(const writeDE of [0,0xdead,0x1000]){const m=machine({writeDE});m.word('FileBlocks',136);assert(!m.call('CreateFile').flags.C,m.text);assert.equal(m.file.length,136*512);assert.equal(m.word('WritePosition'),0x1000);assert.equal(m.word(symbols.WritePosition+2),1);}});
check('short write still detected when DE falsely claims full transfer',()=>{const m=machine({shortWrite:true,writeDE:0x1000});m.word('FileBlocks',8);assert(m.call('CreateFile').flags.C);assert(m.text.includes('Written file length: #00000FFF'),m.text);});
check('table CRC32 matches independent bitwise CRC across full blocks',()=>{for(const sectors of [1,4,32]){const m=machine();let crc=0xffffffff;for(let i=0;i<sectors*512;i++){const v=(i*37+(i>>8)*13)&255;m.wr(0xc000+i,v);crc^=v;for(let j=0;j<8;j++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}m.byte('VerifyPass',1);m.byte('VerifyFile',0);m.call('VerifyInit');assert(!m.call('VerifyBlock',{a:sectors}).flags.C);const actual=(m.word('VerifyCrc')+65536*m.word(symbols.VerifyCrc+2))>>>0;assert.equal(actual,crc>>>0);}});
check('map skip explains unsupported pairing without claiming disk damage',()=>{const m=machine();m.byte('MapStage',3);assert(m.call('MapSkip').flags.C);assert(m.text.includes('map stage 03'));assert(!m.text.includes('invalid'));});

check('only Esc cancels keyboard polling',()=>{for(const key of [0x1b,0x20,0x0d,0x41,0x00]){const m=machine({key});m.byte('KeyCount',127);const s=m.call('PollKey',{a:1});assert.equal(s.flags.Z,key===0x1b?0:1);}const m=machine();m.byte('KeyCount',127);assert(m.call('PollKey',{a:1}).flags.Z);});
check('compact summary shows both implementations on one row',()=>{const m=machine({compact:true});m.byte('PairType',1);m.byte('RepeatCount',3);m.word(symbols.SeriesWorker+1,symbols.FileReadPass);m.word('SeriesArgs',symbols.TestSize512BStr);m.word('SeriesSectors',8);[100,200,300].forEach((t,i)=>m.word(symbols.SeriesTimes+i*4,t));[50,100,150].forEach((t,i)=>m.word(symbols.SeriesPeerTimes+i*4,t));assert(!m.call('CompactSummary').flags.C);const line=m.text.replace(/\r/g,'').trimEnd();assert(line.length<80,line);assert(/FILE  512B\s+2 \[\s*1\.\.\s*4\]/.test(line),line);assert(/BIOS\s+4 \[\s*2\.\.\s*8\]/.test(line),line);assert.equal((m.text.match(/\n/g)||[]).length,1);assert(!m.text.includes('Elapsed:'));});
check('compact file series uses progress line and one result row',()=>{const m=machine({compact:true});m.word('FileBlocks',8);m.call('CreateFile');const start=m.text.length;const label=symbols.TestSize512BStr;assert(!m.call('TestConsistentRead',{h:label>>8,l:label&255,d:2,e:0}).flags.C);const output=m.text.slice(start);assert(output.includes('FILE  512B'),output);assert(!output.includes('Median:'));assert(!output.includes('full warmup verified'));assert.equal((output.match(/\n/g)||[]).length,1);});
check('verbose switch enables detailed output',()=>{const m=machine({compact:true});m.ram.set(Buffer.from('xx/V\0'),0x6000);m.call('ParseArguments',{h:0x60,l:0});assert.equal(m.byte('VerboseOutput'),1);});

check('compact default read groups fit a 32-line screen',()=>{const m=machine({compact:true});m.word('FileBlocks',8);m.word('BiosSectors',8);m.byte('RepeatCount',1);assert(!m.call('CreateFile').flags.C);for(const [label,bytes] of [['TestSize512BStr',512],['TestSize2KBStr',2048],['TestSize4KBStr',4096],['TestSize8KBStr',8192],['TestSize16KBStr',16384]]){const p=symbols[label];assert(!m.call('TestConsistentRead',{h:p>>8,l:p&255,d:bytes>>8,e:0}).flags.C);assert(!m.call('TestBiosRead',{h:p>>8,l:p&255,e:bytes/512}).flags.C);}m.call('CacheInit');m.call('SramIoInit');assert(!m.call('AtaTests').flags.C,m.text);const lines=m.text.split('\n');assert(lines.length+7<=32,'rows including seven header/map lines: '+(lines.length+7));assert.equal((m.text.match(/ATA-[RM] /g)||[]).length,10);let col=0;for(const c of m.text){if(c==='\r'||c==='\n')col=0;else {col++;assert(col<80,'line wraps');}}});
function enableSramIo(m){assert(!m.call('CacheInit').flags.C,m.text);assert(!m.call('SramIoInit').flags.C,m.text);m.byte('UseCache',1);m.byte('TargetSram',1);m.word('AtaBuffer',symbols.SramIoBuffer);}
check('SRAM code receives every command size into SRAM ring without touching DRAM buffer',()=>{for(const count of [1,3,4,8,16,32])for(const mode of [0,1]){const m=machine();enableSramIo(m);m.ram.fill(0x5a,0xc000);m.byte('AtaLeft',count);m.byte('AtaMultiN',4);m.byte('AtaMode',mode);m.word('CurLBA',7);assert(!m.call('AtaTransfer',{a:mode?0xc4:0x20,b:count}).flags.C);assert.equal(m.dataReads,count*512);for(let i=0;i<512;i++)assert.equal(m.cache[symbols.SramIoBuffer+i],((7+count-1)*17+i*7+(i>>8)*19)&255);assert(m.ram.slice(0xc000).every(v=>v===0x5a));assert(!m.on);}});
check('SRAM receive warmup CRC covers every sector before ring overwrite',()=>{const m=machine();enableSramIo(m);m.byte('VerifyPass',1);m.call('VerifyInit');m.byte('AtaLeft',32);m.byte('AtaMultiN',4);m.byte('AtaMode',1);m.word('CurLBA',7);assert(!m.call('AtaTransfer',{a:0xc4,b:32}).flags.C);let crc=0xffffffff;for(let n=7;n<39;n++)for(let i=0;i<512;i++){crc^=(n*17+i*7+(i>>8)*19)&255;for(let j=0;j<8;j++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}assert.equal((m.word('VerifyCrc')+65536*m.word(symbols.VerifyCrc+2))>>>0,crc>>>0);});
check('SRAM code and buffer restored after normal exit, Esc, and error',()=>{for(const options of [{},{cancel:true},{errorDrq:true}]){const m=machine(options);for(let i=0;i<m.cache.length;i++)m.cache[i]=(i*37+(i>>8)*7)&255;const before=m.cache.slice();enableSramIo(m);m.byte('AtaMultiN',4);m.word('BiosSectors',128);m.byte('RepeatCount',1);const label=symbols.TestSize16KBStr;m.call('TestAtaRead',{h:label>>8,l:label&255,e:32,c:1});m.call('Exit');assert.deepEqual(m.cache,before);assert(!m.on);assert.equal(m.byte('SramIoReady'),0);}});
check('three ATA implementations rotate order and share full-stream CRC',()=>{const m=machine({compact:true});m.call('CacheInit');m.call('SramIoInit');m.word('BiosSectors',40);const label=symbols.TestSize4KBStr;assert(!m.call('TestAtaRead',{h:label>>8,l:label&255,e:8,c:0}).flags.C,m.text);assert.deepEqual(m.passes,[[1,0,0],[1,0,1],[1,0,2],[0,0,0],[0,0,1],[0,0,2],[0,1,1],[0,1,2],[0,1,0],[0,2,2],[0,2,0],[0,2,1]]);assert(m.text.includes('|SS '),m.text);assert(!m.text.includes('MISMATCH'));assert.equal(m.byte('TargetSram'),0);assert.equal(m.word('AtaBuffer'),0xc000);});
check('CTC and DSS interrupts during SRAM-to-SRAM transfer',()=>{const m=machine({injectCTC:true,injectDSS:true});enableSramIo(m);m.byte('AtaLeft',32);m.word('CurLBA',7);assert(!m.call('AtaTransfer',{a:0x20,b:32}).flags.C);assert.deepEqual(m.interrupts,[true,true]);assert(!m.on);});
check('SRAM backup allocation failure skips without modifying SRAM',()=>{const m=machine({noMemory:true}),before=m.cache.slice();assert(m.call('CacheInit').flags.C);assert.deepEqual(m.cache,before);assert(!m.on);assert.equal(m.byte('CacheReady'),0);});

check('missing SRAM ring backup retains original SRAM/DRAM test',()=>{const m=machine({failAllocation:2}),before=m.cache.slice();assert(!m.call('CacheInit').flags.C);assert(m.call('SramIoInit').flags.C);assert.equal(m.byte('CacheReady'),1);assert.equal(m.byte('SramIoReady'),0);m.call('CacheDeinit');assert.deepEqual(m.cache,before);assert(!m.on);});

check('D selects standalone SRAM-code/SRAM-buffer mode',()=>{const m=machine();m.ram.set(Buffer.from('xx/D\0'),0x6000);m.call('ParseArguments',{h:0x60,l:0});assert.equal(m.byte('TestMask'),symbols.TEST_SRAM_IO);enableSramIo(m);m.word('BiosSectors',40);m.byte('RepeatCount',1);assert(!m.call('AtaTests',{},30000000).flags.C,m.text);assert(!m.text.includes('MISMATCH'));m.call('Exit');assert(!m.on);});

check('WIN1 backups preserve independent WIN0 and WIN1 selectors',()=>{const m=machine(), original=m.cache.slice();assert(!m.call('CacheInit').flags.C);assert.equal(m.win0,0x40);assert.equal(m.page,255);assert(!m.call('SramIoInit').flags.C);assert.equal(m.win0,0x40);assert.equal(m.page,255);m.call('CacheDeinit');assert.equal(m.win0,0x40);assert.equal(m.page,255);assert.deepEqual(m.cache,original);});
