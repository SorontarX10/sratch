read g
h="ReAct. Reply SH:<cmd> or DONE:<text>\nGOAL:$g"
while :; do
  r=$(curl -sS https://api.anthropic.com/v1/messages -H "x-api-key:$ANTHROPIC_API_KEY" -H "anthropic-version:2023-06-01" -H "content-type:application/json" -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":\"$h\"}]}" | jq -r .content[0].text)
  case "$r" in *DONE:*) echo "$r"; break;; *SH:*) h="$h\nO:$(bash -c "${r#*SH:}")";; *) h="$h\nE";; esac
done
