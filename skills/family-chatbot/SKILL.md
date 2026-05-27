---
name: family-chatbot
description: Walk a student through building a personalized family chatbot web app with Claude API and ngrok. This skill should be used when a student wants to create a family chatbot.
user-invocable: true
---

# Family Chatbot Builder

You are guiding a student through building a personalized family chatbot web app. Be friendly, clear, and assume the student has no prior experience with APIs, Python servers, or ngrok.

This is a teaching exercise. At each step, explain what you're doing and why — help the student understand how chatbots work, not just get one running. After each explanation, ask the student if the explanation is clear, if they have any questions, or if they'd like anything explained again. Wait for the student to confirm before moving on.

## Environment detection

At the start, detect whether you're running on the AI Lab or on the student's personal computer. Check if the path `/home` exists on Linux and the `ANTHROPIC_API_KEY` environment variable is already set — if both are true, you're on the AI Lab.

If on the AI Lab:
- Skip Step 3 (API key) — it's already configured. Instead, briefly explain that the API key is pre-configured in the lab environment, then give the same explanation of what an API key is and why it matters (the block quote in Step 3 starting with "Let me explain what just happened").
- In Step 2, create the app in `~/workspace/{family_name}-chatbot/` instead of `~/repos/{family_name}-chatbot/`.
- In Step 4, use this command to start the app: `uvicorn app:app --host 0.0.0.0 --port 8000`
- Skip Step 5 (ngrok) entirely. Instead, tell the student:
  > Your chatbot is running! Click the "App" tab in the left pane of your workspace to see it.
  >
  > In this lab environment, your app is already accessible through the lab's web interface. On your own computer at home, you could use a tool called ngrok to make a locally-running app accessible to anyone on the internet — ask me if you'd like to learn how that works.

If on the student's personal computer (`APP_PORT` is not set), follow the full Steps 0–5 as written below.

## Step 0: Introduce the plan

Start by explaining what you'll build together and what the student will need to do themselves vs. what you'll do for them:

> Here's what we're going to build: a chatbot web app personalized for your family. When someone visits the app, the chatbot will greet them and ask which family member they are, then have a conversation with them.
>
> Here's the plan:
> 1. I'll ask you a few questions about your family to personalize the app.
> 2. I'll build the app for you — a single Python file.
> 3. I'll walk you through getting an Anthropic API key (you'll need to do this yourself — it takes about 2 minutes). *(AI Lab: skip — already configured)*
> 4. I'll help you run the app.
> 5. I'll walk you through setting up ngrok so anyone on the internet can access your chatbot via a public URL. *(AI Lab: skip — already accessible via the App tab)*
>
> Let's get started!

When on the AI Lab, omit the italicized items from the plan — just show steps 1, 2, and 4 (renumbered as 1, 2, 3).

## Step 1: Gather family information

Ask the student for:
1. Their family name (e.g., "Johnson")
2. The first names of family members the chatbot should recognize (e.g., "Mom, Dad, Emma, Jake")
3. (Optional) Whether they'd like a family image displayed in the header. If yes, ask them to provide an image file path.

Wait for the student to answer before proceeding.

## Step 2: Create the app

Create a project folder and write `app.py` using the template below. Customize:
- Replace `FAMILY_NAME` with the student's family name
- Replace the `FAMILY_MEMBERS` list with their family member names
- If they provided an image, encode it as base64 and embed it in the HTML as a data URI in the header (small, round, next to the title). If no image, omit the image element entirely.

Create the file at `~/repos/{family_name}-chatbot/app.py` (lowercase, hyphenated).

### App template

```python
import os
import uuid
import base64
from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import anthropic

app = FastAPI()
client = anthropic.Anthropic()

FAMILY_NAME = "REPLACE"
FAMILY_MEMBERS = ["REPLACE", "REPLACE"]
WELCOME_MESSAGE = f"Welcome! Are you {', '.join(FAMILY_MEMBERS[:-1])}, or {FAMILY_MEMBERS[-1]}?"

# Per-session conversations
sessions: dict[str, list] = {}


def get_session_id(request: Request) -> str:
    return request.cookies.get("session_id", "")


def get_or_create_session(request: Request, response: Response) -> tuple[str, list]:
    sid = get_session_id(request)
    if sid and sid in sessions:
        return sid, sessions[sid]
    sid = str(uuid.uuid4())
    sessions[sid] = []
    response.set_cookie("session_id", sid)
    return sid, sessions[sid]


class ChatRequest(BaseModel):
    message: str


@app.get("/", response_class=HTMLResponse)
async def index():
    return """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The FAMILY_NAME Family Chatbot</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f0f2f5; height: 100vh; display: flex; flex-direction: column; }
  header { background: #2c3e50; color: white; padding: 16px 24px; text-align: center; font-size: 1.4rem; font-weight: 600; display: flex; align-items: center; justify-content: center; gap: 12px; }
  header img { width: 48px; height: 48px; border-radius: 50%; object-fit: cover; }
  #chat { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 12px; }
  .msg { max-width: 75%; padding: 10px 16px; border-radius: 16px; line-height: 1.5; word-wrap: break-word; }
  .user { align-self: flex-end; background: #3498db; color: white; border-bottom-right-radius: 4px; }
  .assistant { align-self: flex-start; background: white; color: #333; border-bottom-left-radius: 4px; box-shadow: 0 1px 2px rgba(0,0,0,0.1); }
  #input-area { display: flex; padding: 16px; background: white; border-top: 1px solid #ddd; gap: 10px; }
  #input { flex: 1; padding: 12px 16px; border: 1px solid #ccc; border-radius: 24px; font-size: 1rem; outline: none; }
  #input:focus { border-color: #3498db; }
  #send { padding: 12px 24px; background: #3498db; color: white; border: none; border-radius: 24px; font-size: 1rem; cursor: pointer; }
  #send:hover { background: #2980b9; }
  #send:disabled { background: #95a5a6; cursor: not-allowed; }
</style>
</head>
<body>
<header>IMAGE_PLACEHOLDER<span>The FAMILY_NAME Family Chatbot</span></header>
<div id="chat"></div>
<div id="input-area">
  <input id="input" type="text" placeholder="Type a message..." autocomplete="off">
  <button id="send">Send</button>
</div>
<script>
const chat = document.getElementById('chat');
const input = document.getElementById('input');
const send = document.getElementById('send');

function addMsg(role, text) {
  const div = document.createElement('div');
  div.className = 'msg ' + role;
  div.textContent = text;
  chat.appendChild(div);
  chat.scrollTop = chat.scrollHeight;
}

async function loadHistory() {
  const res = await fetch('api/history');
  const data = await res.json();
  data.messages.forEach(m => addMsg(m.role, m.content));
}

async function sendMsg() {
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  addMsg('user', text);
  send.disabled = true;
  try {
    const res = await fetch('api/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({message: text})
    });
    const data = await res.json();
    addMsg('assistant', data.reply);
  } catch (e) {
    addMsg('assistant', 'Error: ' + e.message);
  }
  send.disabled = false;
  input.focus();
}

send.addEventListener('click', sendMsg);
input.addEventListener('keydown', e => { if (e.key === 'Enter') sendMsg(); });
loadHistory();
</script>
</body>
</html>"""


@app.get("/api/history")
async def history(request: Request, response: Response):
    sid = get_session_id(request)
    msgs = sessions.get(sid, [])
    return {"messages": msgs}


@app.post("/api/chat")
async def chat(req: ChatRequest, request: Request, response: Response):
    sid, messages = get_or_create_session(request, response)
    messages.append({"role": "user", "content": req.message})

    if len(messages) == 1:
        reply = WELCOME_MESSAGE
    else:
        api_response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1024,
            system=f"You are The {FAMILY_NAME} Family Chatbot, a friendly assistant for the {FAMILY_NAME} family. The family members are: {', '.join(FAMILY_MEMBERS)}. Keep responses concise and helpful.",
            messages=messages,
        )
        reply = api_response.content[0].text

    messages.append({"role": "assistant", "content": reply})
    return {"reply": reply}
```

When writing the actual file:
- Replace every occurrence of `FAMILY_NAME` with the student's family name.
- Replace `FAMILY_MEMBERS` list contents with the actual names.
- Replace `IMAGE_PLACEHOLDER` with an `<img>` tag using a base64 data URI if they provided an image, or remove it if they didn't.
- If the family has only two members, adjust the WELCOME_MESSAGE to say "Are you X or Y?" instead of using the comma-separated format.

After creating the file, walk the student through how the app works. Explain:

1. The app is a web server (using FastAPI) that runs on their computer. When someone visits the app in a browser, the server sends them an HTML page with a chat interface.
2. When a user types a message and clicks Send, the browser sends that message to the server (to the `/api/chat` endpoint).
3. The server takes the message, sends it to Claude (via the Anthropic API), and returns Claude's response to the browser, which displays it in the chat.
4. Each visitor gets their own private conversation using a session cookie — so if two people visit at the same time, they each have a separate chat.
5. The system prompt tells Claude who the family members are and how to behave, so Claude stays in character as the family's chatbot.

After this explanation, ask the student if everything makes sense or if they have questions about how any part works. Wait for their response before continuing.

## Step 3: Get an Anthropic API key

Walk the student through getting an API key. Tell them:

> Now you need an Anthropic API key so the chatbot can talk to Claude. Here's how:
>
> 1. Go to https://console.anthropic.com/
> 2. Create an account (or sign in if you have one).
> 3. Go to https://console.anthropic.com/settings/keys
> 4. Click "Create Key", give it any name (e.g., "family-chatbot"), and copy the key.
> 5. You'll need to add a payment method and put a small amount of credit on your account (even $5 is plenty for this project).
>
> Once you have the key, paste it here and I'll set it up for you.

When they provide the key, set it as an environment variable for the session. On Windows use `set ANTHROPIC_API_KEY=their-key-here`. On Mac/Linux use `export ANTHROPIC_API_KEY="their-key-here"`. Detect the OS from the environment and use the correct command.

Verify it works:
```bash
python -c "import anthropic; c = anthropic.Anthropic(); r = c.messages.create(model='claude-sonnet-4-20250514', max_tokens=50, messages=[{'role':'user','content':'Say hello'}]); print(r.content[0].text)"
```

If it works, tell the student. If it fails, help them troubleshoot.

After the key is set up and verified, explain how the API key is used and why it matters:

> Let me explain what just happened and why the API key matters.
>
> Your chatbot app doesn't have AI built into it — it's a web app that talks to Claude over the internet. When someone sends a message in your chatbot, your app sends that message to Anthropic's servers (via the API), Claude generates a response, and your app sends that response back to the user's browser.
>
> The API key is how Anthropic knows who is making the request. It's like a password that identifies your account. Every time your app calls Claude, it includes the API key so Anthropic can authenticate the request and charge the usage to your account. That's why you added credit — each conversation costs a small amount (typically fractions of a cent per message).
>
> The key is stored in an environment variable (`ANTHROPIC_API_KEY`) rather than written directly in the code. This is a best practice — you never want to put secret keys directly in your code, especially if you might share the code or post it online. The `anthropic` Python library automatically looks for this environment variable when it needs the key.

Ask the student if this makes sense or if they have questions before continuing.

## Step 4: Install dependencies and run the app

Install the required packages and start the app:

```bash
pip install fastapi uvicorn anthropic
```

Then start the app:

```bash
cd ~/repos/{family_name}-chatbot
uvicorn app:app --host 127.0.0.1 --port 8000
```

Run uvicorn in the background. Then verify with:
```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/
```

Tell the student:

> Your chatbot is running! You can try it now by opening http://localhost:8000 in your browser. Go ahead and test it — send a message and make sure it responds.
>
> Here's what's happening right now: your computer is running a web server (uvicorn) that listens for requests on port 8000. When your browser goes to `localhost:8000`, it's connecting to that server on your own machine. "localhost" is just a name that always means "this computer." So right now, only you can use the chatbot — no one else can reach `localhost` on your machine.
>
> When you're ready, we'll fix that by making it accessible to anyone on the internet with ngrok.

Ask the student if that makes sense and if the chatbot is working. Wait for their response before proceeding.

## Step 5: Set up ngrok

First explain what ngrok does and why it's needed:

> Right now your chatbot only works on your computer — when you go to `localhost:8000`, your browser is talking directly to the server running on your machine. Nobody else can reach it because "localhost" means "this computer" and your computer isn't set up to accept connections from the internet.
>
> ngrok solves this problem. It creates a tunnel between a public URL on the internet and your local server. When someone visits the ngrok URL, their request travels through ngrok's servers and gets forwarded to your computer. Your server responds, and ngrok sends the response back to the visitor. The visitor doesn't need to know your computer's address — they just use the ngrok URL.
>
> Think of it like this: your chatbot is running in your house, and ngrok opens a door from the internet into your house so visitors can reach it.

Ask if this makes sense, then walk them through setup:

> Here's what you need to do:
>
> 1. Go to https://ngrok.com/ and create a free account.
> 2. Go to https://dashboard.ngrok.com/get-started/setup and follow the instructions to download and install ngrok for your operating system.
> 3. On that same page, you'll see an auth token. Copy the `ngrok config add-authtoken YOUR_TOKEN` command and run it in your terminal.
>
> Once you've done that, tell me and I'll start the tunnel for you.

When the student confirms ngrok is installed and authenticated, run:

```bash
ngrok http 8000
```

Run this in the background. Then query the ngrok local API to get the public URL:

```bash
curl -s http://127.0.0.1:4040/api/tunnels | python -c "import sys,json; t=json.load(sys.stdin)['tunnels'][0]; print(t['public_url'])"
```

Tell the student their public URL:

> Your chatbot is now live on the internet! Here's your public URL:
>
> **{the URL from the tunnels API}**
>
> This is an ngrok URL — it will end in `.ngrok-free.app`. Yours will have different letters and numbers, but it will look something like `https://3ecf-2606-a300-9008-3b1d-143f-d869-aa07-2f01.ngrok-free.app/`.
>
> Share this URL with your family and friends! Anyone who opens it in their browser can chat with your family's chatbot. Each person gets their own private conversation.
>
> A few things to know:
> - The first time someone opens the URL, they'll see a page from ngrok asking them to click "Visit Site" — that's normal, just click through.
> - The URL only works while ngrok is running on your computer. If you close your terminal or restart your computer, you'll need to start the app and ngrok again.
> - Each time you restart ngrok, you'll get a new URL.

## Important notes

- ALWAYS use relative paths for fetch calls in the JavaScript (`'api/chat'` not `'/api/chat'`).
- If port 8000 is already in use, try 8001, 8002, etc. and adjust the ngrok command accordingly.
- If the student encounters errors, help them troubleshoot step by step.
