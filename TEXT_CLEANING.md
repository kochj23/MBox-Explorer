# Text Cleaning for RAG Export

MBox Explorer now performs comprehensive text cleaning to ensure your exported emails are optimized for AI/RAG systems.

## What Gets Cleaned

### 1. HTML Content ✅

**Before:**
```html
<html>
<body>
<p>Hello <b>John</b>,</p>
<div>Let&rsquo;s meet at 3pm&nbsp;tomorrow.</div>
<script>trackEmail();</script>
</body>
</html>
```

**After:**
```
Hello John,

Let's meet at 3pm tomorrow.
```

**Removes:**
- All HTML tags (`<p>`, `<div>`, `<span>`, etc.)
- Script and style blocks completely
- HTML entities (`&nbsp;`, `&amp;`, `&quot;`, etc.)
- Converts `<br>` to newlines
- Converts `</p>` to paragraph breaks

### 2. RTF Formatting ✅

**Before:**
```
{\rtf1\ansi\deff0
{\fonttbl{\f0 Times New Roman;}}
{\colortbl;\red0\green0\blue0;}
\f0\fs24 Hello World\par
This is \b bold\b0 text.
}
```

**After:**
```
Hello World
This is bold text.
```

**Removes:**
- RTF header (`{\rtf1...}`)
- Font tables (`{\fonttbl...}`)
- Color tables (`{\colortbl...}`)
- Control words (`\par`, `\b`, `\i`, `\fs24`, etc.)
- All curly braces and backslashes

### 3. Binary Content ✅

**Removes:**
- Base64-encoded attachments
- Image data (inline images)
- Application attachments (PDFs, Word docs, etc.)
- Audio/video files
- Long base64 strings (40+ characters)

**Replaces with markers:**
```
[Binary content removed]
[Image removed]
[Attachment removed]
```

### 4. Email Boilerplate ✅

**Signatures:**
```
--
John Smith
Senior Developer
```

**Footers:**
```
This email and any attachments are confidential...
CONFIDENTIALITY NOTICE: This message...
Please consider the environment before printing...
```

**Sent-from lines:**
```
Sent from my iPhone
Get Outlook for iOS
```

**All removed automatically!**

### 5. Quoted Text ✅

**Before:**
```
Thanks for the update.

> On Jan 1, John wrote:
> > What about the deadline?
> The deadline is Feb 1.
```

**After:**
```
Thanks for the update.
```

All lines starting with `>` (reply quotes) are removed.

### 6. Non-Printable Characters ✅

Removes:
- Control characters
- Zero-width spaces
- Binary garbage characters
- Weird encoding artifacts

Keeps:
- Letters and numbers
- Punctuation
- Spaces, tabs, newlines
- Unicode characters (for international text)

### 7. Excessive Whitespace ✅

**Before:**
```
Hello



World     test
```

**After:**
```
Hello

World test
```

- Multiple newlines → max 2 newlines (paragraph break)
- Multiple spaces → single space

## Processing Order

The cleaning happens in this order for best results:

1. **HTML → Plain text** (convert first, so later steps can process)
2. **RTF → Plain text** (strip RTF control codes)
3. **Binary content removal** (remove attachments)
4. **Email signatures** (chop off signatures)
5. **Quoted text** (remove reply chains)
6. **Whitespace normalization** (clean up formatting)
7. **Email footers** (remove disclaimers)
8. **Non-printable chars** (final cleanup)

## When Cleaning Happens

Text cleaning only happens when **"Clean Text for RAG"** is enabled in the Export Options dialog.

If you want the raw email text with all formatting intact, disable this option.

## Examples

### HTML Email

**Original:**
```html
<html><head><style>body{font-family:Arial;}</style></head>
<body>
<p>Hi Team,</p>
<div>The project is on <b>track</b>.</div>
<p>Thanks,<br>John</p>
<div style="font-size:8pt;color:#999">
This email contains confidential information.
</div>
</body></html>
```

**Cleaned:**
```
Hi Team,

The project is on track.

Thanks,
John
```

### RTF Email

**Original:**
```
{\rtf1\ansi
{\fonttbl\f0\fswiss Arial;}
\f0\fs20 Meeting at \b 2pm\b0\par
--\par
Sent from my iPhone
}
```

**Cleaned:**
```
Meeting at 2pm
```

### Email with Attachment

**Original:**
```
Please review the attached document.

Content-Type: application/pdf
Content-Transfer-Encoding: base64

JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PC9UeXBlL0NhdGFsb2cvUGFnZXMgMiAwIFI+PgplbmRvYmoKMiAwIG9i...
[1000+ lines of base64]

Let me know your thoughts.
```

**Cleaned:**
```
Please review the attached document.

[Binary content removed]

Let me know your thoughts.
```

## Technical Details

### HTML Conversion
- Uses regex to remove tags while preserving text
- Converts common entities (nbsp, amp, lt, gt, etc.)
- Handles nested tags properly
- Removes JavaScript and CSS completely

### RTF Parsing
- Detects RTF by `{\rtf` header
- Strips control words using regex
- Removes formatting groups (fonts, colors, styles)
- Extracts plain text content only

### Binary Detection
- Identifies MIME content types
- Detects base64-encoded content
- Removes long base64 strings (40+ chars)
- Preserves file-type markers for context

### Signature Detection
Recognizes common patterns:
- `--` (standard email signature delimiter)
- `___` (underscores)
- "Sent from my..."
- "Get Outlook for..."
- "Regards," / "Thanks,"

### Quote Detection
- Lines starting with `>` (standard email quotes)
- Removes entire quote block
- Handles nested quotes (`> >`)

## Performance

Text cleaning is fast:
- **HTML**: ~1ms per email
- **RTF**: ~2ms per email
- **Binary removal**: ~3ms per email
- **Total overhead**: ~5-10ms per email

For 1000 emails, cleaning adds about 5-10 seconds to export time.

## Disable Cleaning

If you need raw email content:

1. Open Export Options
2. Uncheck **"Clean Text for RAG"**
3. Export will contain original HTML/RTF/binary content

This is useful if:
- You want to process formatting yourself
- You need to preserve attachments
- You're debugging email parsing

## Benefits for AI/RAG

Clean text provides:
- **Better embeddings** (no noise from formatting)
- **Accurate search** (no HTML tags matching queries)
- **Token efficiency** (less garbage tokens)
- **Better understanding** (AI sees actual content)

Example token savings:
- HTML email: 500 tokens → 200 tokens (60% reduction)
- RTF email: 300 tokens → 100 tokens (67% reduction)
- Email with signature: 400 tokens → 250 tokens (37% reduction)

## Future Enhancements

Potential improvements:
- [ ] Extract attachment filenames/metadata
- [ ] Preserve important formatting (bullet points, headings)
- [ ] Convert tables to markdown
- [ ] Extract URLs and keep them readable
- [ ] Language detection and handling
- [ ] Custom cleaning rules (user-defined patterns)
