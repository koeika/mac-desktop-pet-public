// Extract explicit fields only; arbitrary page text must not become a guessed definition.
export function parseCopiedEntry(text, term) {
  const result = {};
  for (const [key, pattern] of [["phoneticUS", /(?:US|美)\s*([/\[][^\n/\]]+[/\]])/i], ["phoneticUK", /(?:UK|英)\s*([/\[][^\n/\]]+[/\]])/i]]) {
    const match = text.match(pattern); if (match) result[key] = match[1];
  }
  const lines = text.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
  const meaningIndex = lines.findIndex(line=>/^(?:adv|adj|n|v|vt|vi|prep|pron|conj|interj)\./i.test(line));
  if (meaningIndex >= 0) {
    const meaning = lines[meaningIndex];
    result.meaning = /^[a-z]+\.$/i.test(meaning) && /[\u3400-\u9fff]/u.test(lines[meaningIndex + 1] || "")
      ? meaning + " " + lines[meaningIndex + 1] : meaning;
  }
  const exampleIndex = term ? lines.findIndex(line => line.toLowerCase().includes(term.toLowerCase())
    && /[.!?]$/.test(line) && !/(?:US|UK)\s*[/\[]/.test(line)) : -1;
  if (exampleIndex >= 0) {
    result.example = lines[exampleIndex];
    if (/[\u3400-\u9fff]/u.test(lines[exampleIndex + 1] || "")) result.exampleTranslation = lines[exampleIndex + 1];
  }
  if(term && !term.includes("\n"))result.term=term;
  return result;
}
