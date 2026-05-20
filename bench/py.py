import anthropic, subprocess
c=anthropic.Anthropic()
h="ReAct. Reply SH:<cmd> or DONE:<text>\nGOAL:"+input()
while True:
    r=c.messages.create(model="claude-haiku-4-5",max_tokens=1024,messages=[{"role":"user","content":h}]).content[0].text
    if "DONE:" in r: print(r); break
    if "SH:" in r:
        h+="\nO:"+subprocess.run(r.split("SH:")[1],shell=True,capture_output=True,text=True).stdout
    else: h+="\nE"
