#!/usr/bin/env python3
"""Draws the Telegram-style chat mockups used in the proposal (img/*.png)."""
from PIL import Image, ImageDraw, ImageFont
import os, textwrap
S=2; W=360*S
F="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"; FB="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
f=lambda n,b=False: ImageFont.truetype(FB if b else F, n*S)
BG=(223,231,214); OUT=(225,248,200); IN=(255,255,255); HDR=(81,125,162)
NAMEC={"Koen":(196,90,40),"Justice":(52,120,190),"Bot":(60,150,90),"IdeaSupport":(60,150,90)}
here=os.path.dirname(os.path.abspath(__file__))

def wrap(t,font,maxw,d):
    out=[]
    for para in t.split("\n"):
        line=""
        for w in para.split(" "):
            c=(line+" "+w).strip()
            if d.textlength(c,font=font)<=maxw: line=c
            else: out.append(line); line=w
        out.append(line)
    return out

def phone(title,sub,msgs,topic=None,typing=None):
    tmp=Image.new("RGB",(W,4000*S),BG); d=ImageDraw.Draw(tmp)
    y=0; d.rectangle([0,0,W,58*S],fill=HDR)
    d.text((16*S,10*S),title,font=f(15,True),fill="white"); d.text((16*S,32*S),sub,font=f(11),fill=(220,232,245))
    y=58*S
    if topic:
        d.rectangle([0,y,W,y+26*S],fill=(240,244,248)); d.text((16*S,y+6*S),"# "+topic,font=f(11,True),fill=(70,90,110)); y+=26*S
    y+=10*S; bw=250*S; fm=f(12); fn=f(11,True); ft=f(9)
    for m in msgs:
        if m.get("sys"):
            tw=d.textlength(m["sys"],font=f(10)); x=(W-tw)/2
            d.rounded_rectangle([x-10*S,y,x+tw+10*S,y+20*S],8*S,fill=(170,190,160)); d.text((x,y+4*S),m["sys"],font=f(10),fill="white"); y+=30*S; continue
        lines=wrap(m["text"],fm,bw-20*S,d); name=m.get("name")
        h=10*S+(16*S if name else 0)+len(lines)*17*S+16*S
        right=m.get("side")=="r"; x=W-bw-10*S if right else 10*S
        d.rounded_rectangle([x,y,x+bw,y+h],10*S,fill=OUT if right else IN)
        ty=y+8*S
        if name:
            key=name.split()[0].rstrip(":"); d.text((x+10*S,ty),name,font=fn,fill=NAMEC.get(key,(90,90,90))); ty+=16*S
        for ln in lines:
            if ln.startswith("Koen:") or ln.startswith("Justice:") or ln.startswith("Bot:"):
                p,r=ln.split(":",1); d.text((x+10*S,ty),p+":",font=f(12,True),fill=NAMEC[p]); d.text((x+10*S+d.textlength(p+":",font=f(12,True)),ty),r,font=fm,fill=(30,30,30))
            else: d.text((x+10*S,ty),ln,font=fm,fill=(30,30,30))
            ty+=17*S
        tt=m["time"]+("  ✓✓" if right else ""); d.text((x+bw-10*S-d.textlength(tt,font=ft),y+h-14*S),tt,font=ft,fill=(120,150,110) if right else (150,150,150))
        y+=h+6*S
        if m.get("buttons"):
            bs=m["buttons"]; gw=(bw-(len(bs)-1)*4*S)/len(bs)
            for i,b in enumerate(bs):
                bx=x+i*(gw+4*S); d.rounded_rectangle([bx,y,bx+gw,y+28*S],8*S,fill=(120,150,120))
                d.text((bx+(gw-d.textlength(b,font=f(11,True)))/2,y+7*S),b,font=f(11,True),fill="white")
            y+=34*S
        y+=4*S
    y+=6*S; d.rectangle([0,y,W,y+46*S],fill="white")
    d.text((16*S,y+15*S),typing or "Message",font=f(12),fill=(30,30,30) if typing else (160,160,160))
    if typing: d.ellipse([W-40*S,y+9*S,W-12*S,y+37*S],fill=HDR)
    y+=46*S
    return tmp.crop((0,0,W,y))

def save(name,*phones,labels=None):
    gap=30*S; lab=26*S if labels else 0
    H=max(p.height for p in phones)+lab; tot=sum(p.width for p in phones)+gap*(len(phones)-1)
    if len(phones)==1: tot=W*2+gap   # same scale as pairs; phone left-aligned... centre it
    im=Image.new("RGB",(tot,H),"white"); d=ImageDraw.Draw(im)
    x=(tot-phones[0].width)//2 if len(phones)==1 else 0
    for i,p in enumerate(phones):
        if labels: d.text((x,0),labels[i],font=f(13,True),fill=(60,60,60))
        im.paste(p,(x,lab)); d.rectangle([x,lab,x+p.width-1,lab+p.height-1],outline=(190,190,190),width=S); x+=p.width+gap
    im.save(os.path.join(here,"img",name+".png"))

J="Justice"; B="IdeaSupport"
# --- (e) hybrid
jp=phone("IdeaSupport","bot",[
 {"sys":"Today"},
 {"side":"r","text":"Hi, at Mutare Primary. The Console won't open on the teachers' laptops.","time":"09:12"},
 {"name":B,"text":"Thanks Justice. Are the laptops on the Wi-Fi called IDEA-Mutare? It's on the sticker of the router.","time":"09:12"},
 {"side":"r","text":"They were on the school Wi-Fi. Switched, still nothing.","time":"09:15"},
 {"name":B,"text":"OK. Restart the Engine: unplug its power, wait 10 s, plug it back in. After 2 minutes open http://idea.local again. (Install manual, section 6)","time":"09:15"},
 {"side":"r","text":"Works now, thanks! Another thing: Kolibri shows an error after I copied it to the second disk.","time":"09:24"},
 {"name":B,"text":"That one may need a software fix, so I've asked Koen. I'll come back to you here.","time":"09:25"},
 {"name":B,"text":"Koen: Hi Justice, known problem with the copy. Leave the first disk as it is, teachers can use that one today. I'll send a fix this week.","time":"09:31"},
 {"side":"r","text":"Great, thank you Koen.","time":"09:32"},
])
kp=phone("IDEA Support Monitor","group · Koen, IdeaSupport",[
 {"name":"Bot","text":"Justice: Hi, at Mutare Primary. The Console won't open on the teachers' laptops.\nBot: Are the laptops on the Wi-Fi called IDEA-Mutare? …","time":"09:12"},
 {"name":"Bot","text":"Justice: Works now, thanks! Another thing: Kolibri shows an error after I copied it to the second disk.","time":"09:24"},
 {"name":"Bot","text":"⚑ Escalation: Kolibri error after copy to second disk. Needs a code fix (known issue, Engine copy). Draft: \"Use the first disk for now, a fix follows this week.\"","time":"09:25","buttons":["Approve draft","Reply myself"]},
 {"sys":"Koen chose: Reply myself"},
 {"side":"r","name":"Koen","text":"Hi Justice, known problem with the copy. Leave the first disk as it is, teachers can use that one today. I'll send a fix this week.","time":"09:31"},
 {"name":"Bot","text":"Sent to Justice as \"Koen: …\" ✓","time":"09:31"},
 {"side":"r","name":"Koen","text":"/pause","time":"09:33"},
 {"name":"Bot","text":"Paused: I won't answer Justice myself. Everything he writes is shown here; you reply here.","time":"09:33"},
 {"side":"r","name":"Koen","text":"/resume","time":"09:50"},
 {"name":"Bot","text":"Resumed: I answer obvious questions again.","time":"09:50"},
],topic="Justice",typing="Can you send a photo of the error screen?")
save("e-hybrid",jp,kp,labels=["Justice's phone (private chat with the bot)","Koen's phone (monitor group, topic 'Justice')"])
# --- (a) private only
ja=phone("IdeaSupport","bot",[
 {"side":"r","text":"Kolibri shows an error after I copied it to the second disk.","time":"09:24"},
 {"name":B,"text":"That one may need a software fix, so I've asked Koen. I'll come back to you here.","time":"09:25"},
 {"name":B,"text":"Koen says: use the first disk for now, a fix follows this week.","time":"09:40"},
])
ka=phone("IdeaSupport","bot",[
 {"name":B,"text":"⚑ Escalation from Justice: Kolibri error after copy to second disk. Draft: \"Use the first disk for now, a fix follows this week.\"","time":"09:25","buttons":["Approve draft","Reply myself"]},
 {"sys":"Koen tapped: Approve draft"},
 {"name":B,"text":"Sent to Justice ✓","time":"09:40"},
])
save("a-private",ja,ka,labels=["Justice's phone","Koen's phone (his own private chat with the bot)"])
# --- (c) group per person
jc=phone("IDEA Support · Justice","group · Koen, Justice, IdeaSupport",[
 {"side":"r","name":"Justice","text":"Kolibri shows an error after I copied it to the second disk.","time":"09:24"},
 {"name":B,"text":"That one may need a software fix. @Koen, can you look?","time":"09:25"},
 {"name":"Koen","text":"Hi Justice, known problem with the copy. Use the first disk today, I'll send a fix this week.","time":"09:31"},
 {"side":"r","name":"Justice","text":"Great, thank you Koen.","time":"09:32"},
])
save("c-group-per-person",jc,labels=["Justice's phone (Koen appears as himself)"])
# --- (d) shared topics group
jd=phone("IDEA Field Support","group · Koen, Justice, Tendai, IdeaSupport",[
 {"name":"Justice","text":"Kolibri shows an error after I copied it to the second disk.","time":"09:24"},
 {"name":B,"text":"That one may need a software fix. @Koen, can you look?","time":"09:25"},
 {"side":"r","name":"Koen","text":"Known problem with the copy. Use the first disk today, a fix follows this week.","time":"09:31"},
],topic="Justice · Mutare Primary")
save("d-topics",jd,labels=["Koen's phone (topic 'Justice'; other staff can open it too)"])
