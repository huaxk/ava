export async function* jsonLines(reader: ReadableStreamDefaultReader<Uint8Array>) {
  let buf = ""

  for await (let chunk of chunks(reader)) {
    if (buf) chunk = buf + chunk
    const lines = chunk.split("\n")
    buf = lines.pop()!

    for (const line of lines) {
      if (line) yield JSON.parse(line)
    }
  }
}

async function* chunks(reader: ReadableStreamDefaultReader<Uint8Array>, decoder = new TextDecoder()) {
  for (let res; !(res = await reader.read()).done; ) {
    yield decoder.decode(res.value, { stream: !res.done })
  }
}
