// Extract explicit fields only; arbitrary page text must not become a guessed definition.
export function parseCopiedEntry(text, term) {
  const result = {};
  for (const [key, pattern] of [["phoneticUS", /(?:US|美)\s*([/\[][^\n/\]]+[/\]])/i], ["phoneticUK", /(?:UK|英)\s*([/\[][^\n/\]]+[/\]])/i]]) {
    const match = text.match(pattern); if (match) result[key] = match[1];
  }
  const lines = text.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
  const meaning = lines.find(line=>/^(?:adv|adj|n|v|vt|vi|prep|pron|conj|interj)\./i.test(line));
  if(meaning)result.meaning=meaning;
  if(term && !term.includes("\n"))result.term=term;
  return result;
}
