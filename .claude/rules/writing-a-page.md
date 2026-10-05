```xml
<tier0>
<fact id="this-repos-own-copy" source="operator" date="2026-10-05" where="all">These rules are this repo's own, copied on 2026-10-05 from the brain's `.claude/rules/writing-a-page.md` under VH-D185, keeping only what applies to a file written in this repo. The rest of that file governs vault pages - templates, wikilinks, record tokens, aliases - and is read in the brain when writing there.</fact>
<fact id="filename-is-plain-ascii" source="operator" date="2026-09-06" where="all">A filename is plain ASCII: no emoji, no character Windows cannot write, and no square bracket or hash. Its separator is a hyphen, never a dash.</fact>
<fact id="body-any-language-no-emoji" source="operator" date="2026-09-06" where="all">A body may quote any language and any name as it is actually written. Emoji are the exception: none in new content, because they are decoration rather than quotation; pre-existing ones stay.</fact>
<exception id="one-line-paragraphs" decision="VH-D126" date="2026-09-26">A paragraph is one line. Never hard-wrap prose at a column, inside a comment or anywhere else, and never mirror the wrapping of the text around it: a wrapped paragraph cannot be matched as an edit anchor, and the operator rejoins it by hand.</exception>
</tier0>
```
