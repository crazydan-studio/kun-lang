module.exports = {
  names: ["no-html-entity-pipe"],
  description: "Table pipes must use backslash escaping (\\|), not HTML entities (&#124;)",
  information: new URL("https://opencode.ai/docs"),
  tags: ["tables", "formatting"],
  function: (params, onError) => {
    const pattern = /&#(?:124|x7[cC]);/g;
    params.lines.forEach((line, lineIndex) => {
      let match;
      while ((match = pattern.exec(line)) !== null) {
        onError({
          lineNumber: lineIndex + 1,
          detail: "Use backslash escaping (\\|) instead of HTML entity for pipe",
          context: line.slice(Math.max(0, match.index - 10), match.index + 20)
        });
      }
    });
  }
};
