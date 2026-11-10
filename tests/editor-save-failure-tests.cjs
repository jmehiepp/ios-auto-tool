const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
let reject=true;const requests=[],logs=[],nodes=new Map();
const context=vm.createContext({
  document:{addEventListener(){},querySelectorAll(){return [];},getElementById(id){if(!nodes.has(id)) nodes.set(id,{});return nodes.get(id);}},
  appendLog(level,message){logs.push(message);},clearLog(){},
  async fetch(path){requests.push(path);return {ok:!reject,status:reject?400:200,async json(){return reject?{error:'fixture disk failure'}:{ok:true};}};},
});
for(const path of ['file-manager.js','editor.js'])vm.runInContext(fs.readFileSync('webide/frontend/'+path,'utf8'),context);
vm.runInContext("editor={getValue:()=>\"log('ready')\"};currentFile='test.lua';isDirty=true",context);
(async()=>{
  await context.runScript();assert.deepEqual(requests,['/api/files/test.lua']);
  assert(vm.runInContext('isDirty',context));assert(logs.some(message=>message.includes('fixture disk failure')));
  reject=false;requests.length=0;await context.runScript();
  assert.deepEqual(requests,['/api/files/test.lua','/api/run']);assert.equal(vm.runInContext('isDirty',context),false);
  console.log('Editor save failure prevents execution tests passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
