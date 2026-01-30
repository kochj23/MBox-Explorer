# MBox Explorer

**AI-Powered Email Archive Analysis with Native RAG Pipeline**

![Platform](https://img.shields.io/badge/platform-macOS%2013.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-Production-success)
![AI](https://img.shields.io/badge/AI-RAG%20Pipeline-purple)
![Ethics](https://img.shields.io/badge/Ethics-Protected-green)

---

## ✨ Latest Update: January 30, 2026

### 🎉 Major Enhancements:

#### 🤖 Native RAG Pipeline (NEW)
- **Retrieval-Augmented Generation** built entirely in Swift
- **Vector database** with SQLite + FTS5 full-text search
- **Semantic search** via Ollama embeddings
- **Smart question routing** for optimal context selection
- **Conversation memory** for follow-up questions
- **Custom system prompts** for personalized AI behavior

#### 💬 Ask AI Interface (NEW)
- Natural language queries about your email archive
- Real-time AI responses with source citations
- Debug panel to inspect AI prompts
- Export conversations to Markdown/JSON
- Temperature controls to reduce hallucinations

#### ☁️ Cloud AI Integration (5 Providers)
- **OpenAI API** - GPT-4o for advanced capabilities
- **Google Cloud AI** - Vertex AI, Vision, Speech
- **Microsoft Azure** - Cognitive Services
- **AWS AI Services** - Bedrock, Rekognition, Polly
- **IBM Watson** - NLU, Speech, Discovery

#### 🛡️ Ethical AI Safeguards
- Comprehensive content monitoring
- Prohibited use detection (100+ patterns)
- Automatic blocking of illegal/harmful content
- Crisis resource referrals
- Legal compliance (CSAM reporting, etc.)

---

## 🧠 RAG Pipeline Architecture

MBox Explorer includes a **native RAG (Retrieval-Augmented Generation) pipeline** - no external frameworks required.

### Pipeline Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        RAG PIPELINE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │  Query   │───▶│ Question │───▶│ Retrieve │───▶│ Augment  │  │
│  │  Input   │    │  Router  │    │ Context  │    │  Prompt  │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│                                         │              │        │
│                                         ▼              ▼        │
│                                  ┌──────────┐    ┌──────────┐  │
│                                  │  Vector  │    │   LLM    │  │
│                                  │    DB    │    │ Generate │  │
│                                  └──────────┘    └──────────┘  │
│                                                        │        │
│                                                        ▼        │
│                                                 ┌──────────┐   │
│                                                 │ Response │   │
│                                                 │ + Sources│   │
│                                                 └──────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 1. Document Store (`VectorDatabase.swift`)

| Feature | Implementation |
|---------|----------------|
| Storage | SQLite database (`~/Library/Application Support/MBoxExplorer/vectors.db`) |
| Full-text search | FTS5 with ranking |
| Vector storage | Float arrays as BLOBs |
| Indexing | Batch processing with progress |

### 2. Embedding Generation

MBox Explorer supports **4 embedding providers** - choose based on your needs:

#### Embedding Provider Comparison

| Provider | Cost | Privacy | Speed | Quality | Setup |
|----------|------|---------|-------|---------|-------|
| **Ollama** | Free | 100% Local | Fast | Good | `brew install ollama && ollama pull nomic-embed-text` |
| **MLX** | Free | 100% Local | Very Fast | Good | Built-in (Apple Silicon only) |
| **OpenAI** | $0.02/1M tokens | Cloud | Fast | Excellent | API key required |
| **Sentence Transformers** | Free | 100% Local | Medium | Excellent | `pip install sentence-transformers` |

#### Detailed Provider Analysis

**1. Ollama Embeddings** (Recommended for most users)
| Aspect | Details |
|--------|---------|
| Pros | Free, private, runs locally, easy setup, multiple models |
| Cons | Requires Ollama daemon running |
| Models | `nomic-embed-text` (768d), `all-minilm` (384d), `mxbai-embed-large` (1024d) |
| Best for | Users who want local, private semantic search |

**2. MLX Embeddings** (Best for Apple Silicon users)
| Aspect | Details |
|--------|---------|
| Pros | Native Apple Silicon, fastest inference, no external dependencies |
| Cons | macOS only, Apple Silicon required, model download on first use |
| Models | `all-MiniLM-L6-v2` (384d), `nomic-embed-text-v1.5` (768d), `bge-small-en-v1.5` (384d) |
| Best for | M1/M2/M3 Mac users wanting maximum performance |

**3. OpenAI Embeddings** (Best quality)
| Aspect | Details |
|--------|---------|
| Pros | Highest quality, well-documented, reliable |
| Cons | Costs money, data sent to cloud, requires API key |
| Models | `text-embedding-3-small` (1536d, $0.02/1M), `text-embedding-3-large` (3072d, $0.13/1M) |
| Best for | Users who prioritize quality and don't mind cloud processing |

**4. Sentence Transformers** (Best flexibility)
| Aspect | Details |
|--------|---------|
| Pros | Excellent quality, huge model selection, local processing |
| Cons | Requires Python, slower startup, larger disk footprint |
| Models | Any HuggingFace sentence-transformers model |
| Best for | ML enthusiasts who want model flexibility |

#### Configuration

- **Storage**: Embeddings stored in SQLite as binary data
- **Chunking strategy**: Subject + first 500 characters of body
- **Dimension tracking**: Automatically tracked per provider
- **Provider switching**: Change in Settings → AI → Embedding Provider

### 3. Retrieval Methods

```swift
// Three search modes with automatic fallback:

1. Semantic Search (if Ollama available)
   → Generate query embedding
   → Cosine similarity against stored embeddings
   → Return top 20 results

2. Keyword Search (FTS5 fallback)
   → FTS5 MATCH query
   → Ranked by relevance
   → Snippet extraction

3. Direct Search (no indexing required)
   → In-memory text matching
   → Score by term frequency
   → Bonus for subject/sender matches
```

### 4. Smart Question Routing

The pipeline automatically detects question types and optimizes context:

| Question Type | Example | Context Used |
|---------------|---------|--------------|
| `STATISTICS` | "How many emails?" | Metadata only |
| `TOP_LIST` | "Who sent the most?" | Metadata + samples |
| `DATE_RANGE` | "What's the date range?" | Metadata only |
| `CONTENT_SEARCH` | "Find emails about project X" | Full RAG search |
| `SUMMARY` | "Summarize main themes" | Extended context (15 emails) |
| `FOLLOW_UP` | "Tell me more" | Previous conversation + search |

### 5. Context Augmentation

The prompt sent to the LLM includes:

```
MAILBOX STATISTICS:
- Total emails: [count]
- Date range: [start] - [end]
- Total threads: [count]
- Unique senders: [count]
- Top senders: [list with counts]

PREVIOUS CONVERSATION: (if memory enabled)
[Recent Q&A turns for context]

RETRIEVED EMAILS:
From: [sender]
Subject: [subject]
Date: [date]
Content: [snippet]
---
[...more relevant emails...]

USER QUESTION: [query]
```

### 6. Generation Settings

| Setting | Default | Purpose |
|---------|---------|---------|
| Q&A Temperature | 0.2 | Low for factual accuracy |
| Summary Temperature | 0.3 | Slightly higher for synthesis |
| Creative Temperature | 0.7 | Higher for varied output |
| Max Conversation History | 10 turns | Follow-up context |

---

## 🎯 Features

### Ask AI Interface

- **Natural language queries** - Ask questions about your emails in plain English
- **Source citations** - See which emails were used to generate answers
- **Debug panel** - Inspect the full prompt sent to the AI
- **Conversation memory** - Follow-up questions maintain context
- **Export conversations** - Save Q&A sessions as Markdown or JSON
- **Custom system prompts** - Modify AI behavior in settings

### Email Analysis

- **Smart filters** - Filter by sender, date, size, attachments
- **Thread detection** - Group related emails
- **Duplicate finder** - Identify duplicate messages
- **Statistics dashboard** - Email counts, top senders, date ranges
- **Network visualization** - See communication patterns
- **Attachment browser** - Browse and export attachments

### AI Backend Support

#### LLM Providers (Text Generation)

| Backend | Type | Cost | Features |
|---------|------|------|----------|
| Ollama | Local | Free | LLM + Embeddings |
| MLX | Local | Free | Apple Silicon optimized LLM |
| TinyLLM | Local | Free | Lightweight LLM |
| OpenWebUI | Self-hosted | Free | Web interface |
| OpenAI | Cloud | Paid | GPT-4o |
| Google Cloud | Cloud | Paid | Vertex AI |
| Azure | Cloud | Paid | Cognitive Services |
| AWS | Cloud | Paid | Bedrock |
| IBM Watson | Cloud | Paid | NLU |

#### Embedding Providers (Semantic Search)

| Provider | Type | Cost | Dimensions | Speed |
|----------|------|------|------------|-------|
| Ollama | Local | Free | 384-1024 | Fast |
| MLX | Local | Free | 384-768 | Very Fast |
| OpenAI | Cloud | Paid | 1536-3072 | Fast |
| Sentence Transformers | Local | Free | 384-768+ | Medium |

---

## 📦 Installation

### From DMG
```bash
open MBox-Explorer-latest.dmg
# Drag to Applications
```

### From Source
```bash
cd "/Volumes/Data/xcode/MBox Explorer"
xcodebuild -scheme "MBox Explorer" -configuration Release build
cp -R build/Release/*.app ~/Applications/
```

### AI Backend Setup (Recommended)

**Option 1: Ollama (Recommended - easiest)**
```bash
# Install Ollama for local, private AI
brew install ollama
ollama serve

# Pull models for RAG
ollama pull mistral:latest        # For chat/Q&A
ollama pull nomic-embed-text      # For embeddings (semantic search)
```

**Option 2: MLX (Apple Silicon - fastest)**
```bash
# Built-in! Just select MLX in Settings → AI → Embedding Provider
# Models download automatically on first use
```

**Option 3: OpenAI (Cloud - best quality)**
```bash
# Get API key from platform.openai.com
# Enter key in Settings → AI → Cloud API Keys → OpenAI
```

**Option 4: Sentence Transformers (Most flexible)**
```bash
# Requires Python 3.8+
pip install sentence-transformers
# Select Sentence Transformers in Settings → AI → Embedding Provider
```

---

## 🎓 Usage

### Basic Workflow

1. **Launch** MBox Explorer
2. **Open** an MBOX file (File → Open or ⌘O)
3. **Browse** emails in the list view
4. **Ask AI** - Click "Ask AI" in sidebar for natural language queries

### Ask AI Tips

- **Statistics questions**: "How many emails?", "Who are the top senders?"
- **Content search**: "Find emails about [topic]"
- **Summaries**: "Summarize the main themes"
- **Follow-ups**: "Tell me more about that" (uses conversation memory)

### Indexing (Optional but Recommended)

Click "Index Emails" for:
- Faster searches on large archives
- Semantic search (finds conceptually related emails)
- Better relevance ranking

Without indexing, basic text search still works.

---

## 🔧 Configuration

### RAG Pipeline Settings

Access via gear icon (⚙️) in Ask AI view:

- **Conversation Memory**: Enable/disable, set history length
- **Custom System Prompt**: Modify AI instructions
- **Debug Mode**: See full prompts sent to AI

### Temperature Settings

Access via AI Settings:

- **Q&A Temperature** (0.0-1.0): Lower = more factual
- **Summary Temperature**: For email summaries
- **Creative Temperature**: For open-ended tasks

---

## 🔒 Security & Ethics

### Ethical AI Guardian

All AI operations are monitored for:
- ✅ Legal compliance
- ✅ Ethical use
- ✅ Safety
- ✅ Privacy protection

### Data Privacy

- **Local processing**: Ollama/MLX run entirely on your Mac
- **No cloud required**: Cloud AI is optional
- **Your data stays yours**: Emails never leave your device unless you choose cloud AI

---

## 🛠️ Development

**Author:** Jordan Koch ([@kochj23](https://github.com/kochj23))

**Built with:**
- SwiftUI
- SQLite (FTS5 + Vector storage)
- Ollama API
- Native macOS APIs

**Architecture:**
- MVVM pattern
- Native RAG pipeline
- Multi-backend AI support
- Ethical safeguards

---

## 📊 Version History

### v2.1 - Multi-Provider Embeddings (January 30, 2026)
- **4 Embedding Providers**: Ollama, MLX, OpenAI, Sentence Transformers
- Provider comparison table with pros/cons
- Automatic provider detection and fallback
- MLX native Apple Silicon embeddings
- OpenAI text-embedding-3-small/large support
- Python bridge for sentence-transformers
- Unified EmbeddingManager for all providers

### v2.0 - RAG Edition (January 30, 2026)
- Native RAG pipeline implementation
- Ask AI interface with conversation memory
- Smart question routing
- Debug panel for prompt inspection
- Export conversations
- Direct search fallback (no indexing required)
- Temperature controls
- Custom system prompts

### v1.5 - Cloud AI Edition (January 26, 2026)
- Added 5 cloud AI providers
- Added ethical safeguards
- AI backend status menu
- Auto-fallback system

### v1.0 - Initial Release
- MBOX file parsing
- Email browsing and search
- Export capabilities
- Basic AI integration

---

## 🆘 Support

### App Support
- GitHub Issues: [Report bugs](https://github.com/kochj23/MBox-Explorer/issues)
- Documentation: See project files

### Crisis Resources
- **988** - Suicide Prevention Lifeline
- **741741** - Crisis Text Line (text HOME)
- **1-800-799-7233** - Domestic Violence Hotline

---

## 📄 License

MIT License - See LICENSE file

**Ethical Usage Required** - See ETHICAL_AI_TERMS_OF_SERVICE.md

---

**MBox Explorer - AI-Powered Email Archive Analysis**

© 2026 Jordan Koch. All rights reserved.
