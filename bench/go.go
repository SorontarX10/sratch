package main
import("bufio";"bytes";"encoding/json";"fmt";"io";"net/http";"os";"os/exec";"strings")
type M struct{Role,Content string}
type Req struct{Model string `json:"model"`;Max int `json:"max_tokens"`;Msgs []M `json:"messages"`}
type Res struct{Content []struct{Text string `json:"text"`} `json:"content"`}
func main(){
  s,_:=bufio.NewReader(os.Stdin).ReadString('\n')
  h:="ReAct. Reply SH:<cmd> or DONE:<text>\nGOAL:"+strings.TrimSpace(s)
  k:=os.Getenv("ANTHROPIC_API_KEY")
  for{
    b,_:=json.Marshal(Req{"claude-haiku-4-5",1024,[]M{{"user",h}}})
    rq,_:=http.NewRequest("POST","https://api.anthropic.com/v1/messages",bytes.NewReader(b))
    rq.Header.Set("x-api-key",k);rq.Header.Set("anthropic-version","2023-06-01");rq.Header.Set("content-type","application/json")
    rp,_:=http.DefaultClient.Do(rq);d,_:=io.ReadAll(rp.Body);var R Res;json.Unmarshal(d,&R);r:=R.Content[0].Text
    if strings.Contains(r,"DONE:"){fmt.Println(r);return}
    if strings.Contains(r,"SH:"){o,_:=exec.Command("sh","-c",strings.SplitN(r,"SH:",2)[1]).Output();h+="\nO:"+string(o)}else{h+="\nE"}
  }
}
