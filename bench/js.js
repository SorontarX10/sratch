import Anthropic from "@anthropic-ai/sdk";
import {execSync} from "child_process";
import readline from "readline";
const rl=readline.createInterface({input:process.stdin});
const c=new Anthropic();
let h="ReAct. Reply SH:<cmd> or DONE:<text>\nGOAL:";
rl.once("line",async g=>{h+=g;while(1){const m=await c.messages.create({model:"claude-haiku-4-5",max_tokens:1024,messages:[{role:"user",content:h}]});const r=m.content[0].text;if(r.includes("DONE:")){console.log(r);break}if(r.includes("SH:")){h+="\nO:"+execSync(r.split("SH:")[1]).toString()}else h+="\nE"}});
