' fetch a page and summarize it with the LLM
u=#in()
p=#get(u)
s=@"Summarize in 3 bullets:\n"+p
>s
