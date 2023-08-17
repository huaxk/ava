import { signal, useSignal } from "@preact/signals"
import { Button, Form, Layout, PageContent, PageHeader } from "../_components"
import { useGenerate } from "../_hooks"
import { ChatMessage } from "./ChatMessage"

export const Chat = ({ params }) => {
  // TODO: load by id

  return (
    <>
      <PageHeader title="Chat" description="Dialog-based interface" />

      <PageContent>
        <Layout scroll>
          <aside class="d-print-none">
            <div class="group">
              <div>Today</div>
              <ul class="list-unstyled">
                <li>
                  <a class="active" href="#">
                    Poem about JavaScript
                  </a>
                </li>
                <li>
                  <a href="#">Invoke Clang from Zig</a>
                </li>
              </ul>
            </div>
            <div class="group">
              <div>Yesterday</div>
              <ul class="list-unstyled">
                <li>
                  <a href="#">Trip to Italy</a>
                </li>
                <li>
                  <a href="#">Recipe for a cake</a>
                </li>
              </ul>
            </div>
            <div class="group">
              <div>Previous 7 days</div>
              <ul class="list-unstyled">
                <li>
                  <a href="#">How to make a website</a>
                </li>
              </ul>
            </div>
          </aside>

          <ChatSession />
        </Layout>
      </PageContent>
    </>
  )
}

const ChatSession = () => {
  const { generate, loading, abort } = useGenerate()
  const text = useSignal("")
  const messages = useSignal([
    {
      role: "system",
      content:
        "A chat between a curious user and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the user's questions.\n\n",
    } as any,
  ])

  const handleSubmit = async e => {
    const content = signal("")

    messages.value = [...messages.value, { role: "user", content: text.value.trim() }, { role: "assistant", content }]

    const prompt = messages.value.reduce(
      (res, m) => res + (m.role === "system" ? m.content : `${m.role.toUpperCase()}: ${m.content}\n`),
      ""
    )
    text.value = ""

    for await (const temp of generate(prompt.trimEnd())) {
      content.value = temp
    }
  }

  return (
    <>
      <header>
        <h2 class="mb-4">New Chat</h2>
      </header>

      <div>
        {messages.value.map(m => (
          <ChatMessage {...m} />
        ))}
      </div>

      <footer class="d-print-none">
        <Form onSubmit={handleSubmit}>
          <textarea
            autofocus
            class="form-control mb-2"
            rows={3}
            placeholder="Ask anything..."
            value={text.value}
            onInput={e => (text.value = e.target.value)}
            onKeyUp={e => e.key === "Enter" && !e.shiftKey && handleSubmit(e)}
          ></textarea>

          <div class="hstack gap-2">
            <Button submit>Send</Button>

            {loading && <Button onClick={abort}>Stop generation</Button>}
          </div>
        </Form>
      </footer>
    </>
  )
}
