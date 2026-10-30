import { readFile, writeFile } from "node:fs/promises";

const source = new URL("../public/audio/narration.vtt", import.meta.url);
const destination = new URL("../public/audio/captions.json", import.meta.url);
const raw = await readFile(source, "utf8");

const parseTime = (value) => {
  const [hours, minutes, rest] = value.replace(",", ".").split(":");
  return Math.round(
    (Number(hours) * 3600 + Number(minutes) * 60 + Number(rest)) * 1000,
  );
};

const splitText = (text) => {
  return text
    .split(/(?<=[，。；：！？])/u)
    .map((part) => part.trim())
    .filter(Boolean);
};

const blocks = raw
  .trim()
  .split(/\n\s*\n/u)
  .filter((block) => block.includes("-->"));

const captions = [];
for (const block of blocks) {
  const lines = block.split("\n").map((line) => line.trim());
  const timingIndex = lines.findIndex((line) => line.includes("-->"));
  const [from, to] = lines[timingIndex].split("-->").map((part) => part.trim());
  const startMs = parseTime(from);
  const endMs = parseTime(to);
  const text = lines.slice(timingIndex + 1).join(" ").trim();
  const chunks = splitText(text);
  const totalCharacters = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  let cursor = startMs;

  chunks.forEach((chunk, index) => {
    const isLast = index === chunks.length - 1;
    const share = chunk.length / totalCharacters;
    const chunkEnd = isLast
      ? endMs
      : Math.round(cursor + (endMs - startMs) * share);
    captions.push({
      text: chunk,
      startMs: cursor,
      endMs: chunkEnd,
      timestampMs: null,
      confidence: null,
    });
    cursor = chunkEnd;
  });
}

await writeFile(destination, `${JSON.stringify(captions, null, 2)}\n`);
console.log(`Wrote ${captions.length} captions to ${destination.pathname}`);
