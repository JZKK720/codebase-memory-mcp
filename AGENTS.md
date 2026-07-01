# AGENTS.md — codebase-memory-mcp

> **Pure C11 MCP server** that indexes codebases into a persistent SQLite-backed
> knowledge graph via 158 vendored tree-sitter grammars + Hybrid LSP type resolution
> for 9 languages. Single static binary, zero runtime dependencies. Exposes 14 MCP tools
> over JSON-RPC 2.0 stdio. See [README.md](README.md) for full feature list.

## Quick Reference

| Task | Command |
|------|---------|
| **Build (prod)** | `scripts/build.sh` |
| **Build (with UI)** | `scripts/build.sh --with-ui` |
| **Run tests** | `scripts/test.sh` (ASan + UBSan, ~5600 cases) |
| **Foundation tests only** | `make -f Makefile.cbm test-foundation` |
| **Lint** | `scripts/lint.sh` (clang-tidy + cppcheck + clang-format) |
| **Security audit** | `make -f Makefile.cbm security` (8 layers) |
| **Clean** | `scripts/clean.sh` or `make -f Makefile.cbm clean-c` |
| **Binary output** | `build/c/codebase-memory-mcp` |

## Critical Rules

1. **C code only.** This project was rewritten from Go in v0.5.0. Go PRs cannot be merged.
2. **`-Werror` is on** for all production code. Fix warnings, don't suppress them.
3. **One issue per PR.** PRs must reference a tracking issue (`Fixes #N`). Keep PRs < 500 lines.
4. **DCO sign-off required** on every commit: `git commit -s`.
5. **Never add `system()`, `popen()`, `fork()`, or network calls** without justification + adding to `scripts/security-allowlist.txt`.
6. **Activate git hooks**: `git config core.hooksPath scripts/hooks` (pre-commit security checks).
7. **Conventional commits**: `type(scope): description` — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Coding Guidelines (Karpathy)

Derived from [Karpathy's LLM coding guidelines](https://github.com/karpathy). Adapted for this repo's C-only / `-Werror` / test-first workflow.

### 1. Think before coding

- Surface assumptions about the C11 build system, `-Werror` constraints, and tree-sitter grammar behavior explicitly.
- If multiple interpretations of a grammar change or pipeline pass exist, present them — don't pick silently.
- If a simpler approach exists (e.g., a single `pass_*.c` change vs. refactoring the pipeline orchestrator), say so.
- If something is unclear about `Makefile.cbm` source groups or `internal/cbm/` extraction logic, stop and ask.

### 2. Simplicity first

- No speculative abstractions in pipeline passes — each `pass_*.c` does one thing.
- No "flexibility" or "configurability" that wasn't requested.
- If you write 200 lines and it could be 50, rewrite.
- Ask: "Would a senior C engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical changes

- Touch only what you must in `Makefile.cbm` / `internal/cbm/` — these have large blast radius.
- Don't "improve" adjacent code, comments, or formatting in C files.
- Match existing C style (snake_case, `cbm_` prefix, arena allocation pattern).
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that YOUR changes made unused. Don't remove pre-existing dead code.
- Every changed line should trace directly to the user's request.

### 4. Goal-driven execution

Transform tasks into verifiable goals:
- "Fix the bug" → "Write a test in `tests/test_pipeline.c` that reproduces it, then make it pass"
- "Add language X" → "Add grammar shim, add lang_specs row, verify extraction test passes"
- "Refactor pass_Y" → "Ensure `scripts/test.sh` passes before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

## Frontend Design Rules (graph-ui/)

When touching `graph-ui/` (the React/Three.js 3D graph visualization), follow anti-slop design rules. Distilled from `taste-skill` (Leonxlnx's anti-slop design rules).

### Stack

- **Framework**: Vite + React (not Next.js)
- **3D**: Three.js for graph layout
- **Styling**: CSS variables for tokens, no hardcoded hex outside token files
- **Icons**: Single icon set — do not mix Material, Lucide, Phosphor, and emoji

### Three-dial system

Set these before designing UI changes to `graph-ui/`:

| Dial | Range | Meaning |
|------|-------|---------|
| **DESIGN_VARIANCE** | 1–10 | 1 = Perfect Symmetry, 10 = Artsy Chaos |
| **MOTION_INTENSITY** | 1–10 | 1 = Static, 10 = Cinematic / Physics |
| **VISUAL_DENSITY** | 1–10 | 1 = Airy, 10 = Packed Data |

Baseline for the graph UI: **6 / 4 / 7** (moderate variance, minimal motion, high data density — it's a developer tool, not a marketing page).

### Forbidden patterns

- **No AI-purple** (`#7c3aed`, `#8b5cf6`) as primary accent.
- **No pure black** (`#000000`) on white. Use charcoal (`#18181B`) or zinc-900.
- **No three-equal-card grids** as the only layout pattern.
- **No emoji bullets** in feature lists.
- **No animation without motivation** — every animation must justify itself in one sentence.
- **No `!important`** in the final stylesheet.
- **Animate via `transform` and `opacity` only** — never `width`, `height`, `top`, `left`.

### Pre-flight checklist

Before shipping `graph-ui/` changes:
- [ ] `prefers-reduced-motion` respected
- [ ] Dark mode looks designed, not inverted
- [ ] 3D viewport stable at `min-h-[100dvh]`, never `h-screen`
- [ ] `useEffect` animations have strict cleanup functions
- [ ] No AI slop tells (generic hero, "supercharge", "unleash")
- [ ] Real type, not system default sans-serif

## Architecture (layered)

```
foundation/    → Arena allocator, hash table, string interning, platform compat, logging
discover/      → File discovery, language detection (158 langs), gitignore matching
internal/cbm/  → Tree-sitter extraction (64 grammar shims), Hybrid LSP type resolution (9 langs)
graph_buffer/  → In-memory graph (RAM during indexing, dumped to SQLite at end)
pipeline/      → Multi-pass indexing orchestrator (~30 pass_*.c files, worker pool)
store/         → SQLite graph store (WAL mode, FTS5, prepared-statement cache)
cypher/        → Cypher-subset query engine → SQL translation
mcp/           → JSON-RPC 2.0 over stdio, 14 tools, single-threaded event loop
cli/           → install/uninstall/update/config/hook-augment subcommands
ui/            → Graph visualization HTTP server (127.0.0.1, port 9749)
watcher/       → Git-based adaptive polling auto-reindex (5s base, capped 60s)
git/           → Git context resolution (worktree, HEAD, branch)
traces/        → OTLP/OpenTelemetry trace processing
semantic/      → 11-signal code embeddings (768d, nomic-embed-code), SEMANTICALLY_RELATED edges
simhash/       → MinHash (K=64) + LSH (32 bands) near-clone detection, SIMILAR_TO edges
```

### Key design decisions

- **RAM-first pipeline**: All indexing in memory (LZ4 HC compressed), single SQLite dump at end. Memory released after.
- **Single-threaded MCP server**: One event loop, read line → parse → dispatch → respond. Store connection cached per project, evicted after 60s idle.
- **mimalloc global override** (prod only): Static-link-order on Unix, `MI_MALLOC_OVERRIDE=1` on Windows. Tree-sitter allocator bound to mimalloc via `-DCBM_BIND_TS_ALLOCATOR=1`. Disabled in test builds (ASan alloc/free mismatch).
- **Pre-tool hook** (`src/cli/hook_augment.c`): Claude Code PreToolUse augmenter for Grep/Glob. **Never blocks** — every error path exits 0 with no stdout. Hard 300ms SIGALRM deadline.
- **Incremental indexing**: `pipeline_incremental.c` compares file mtime+size, re-parses only changed files, merges into existing DB.

## Build System

`Makefile.cbm` is the core. No CMake, no Meson.

| Build type | Target | Flags |
|------------|--------|-------|
| Production | `make -f Makefile.cbm cbm` | `-O2 -Werror -DCBM_BIND_TS_ALLOCATOR=1` + mimalloc |
| With UI | `make -f Makefile.cbm cbm-with-ui` | Above + embedded React frontend |
| Test | `make -f Makefile.cbm test` | `-g -O1 -fsanitize=address,undefined` |
| TSan | `make -f Makefile.cbm test-tsan` | `-g -O1 -fsanitize=thread` |
| Static (portable) | `make -f Makefile.cbm cbm STATIC=1` | `-static` (Alpine/musl) |

**Optional libgit2**: Auto-detected via `pkg-config`. Install `libgit2-dev` + `pkg-config` for faster git history parsing. Falls back to `popen("git log ...")`.

**Windows (MinGW)**: Links `ws2_32`, `psapi`, `--allow-multiple-definition`, `--stack,8388608`, `-static`. Uses vendored TRE regex instead of system `<regex.h>`.

## Vendored Dependencies (all in `vendored/`)

| Library | Purpose | Notes |
|---------|---------|-------|
| `sqlite3/` | Graph store + FTS5 search | `-DSQLITE_ENABLE_FTS5 -DSQLITE_THREADSAFE=1 -DSQLITE_DQS=0` |
| `yyjson/` | JSON parse/build (MCP server) | |
| `mimalloc/` | Global allocator override | Prod only; link-order on Unix, `MI_MALLOC_OVERRIDE=1` on MinGW |
| `xxhash/` | Fast hashing for MinHash | |
| `tre/` | POSIX regex for Windows | Unix uses system `<regex.h>` |
| `nomic/` | Pretrained code embeddings (40K tokens, 768d int8) | Assembler blob, no API key needed |

Tree-sitter runtime + 64 grammars are in `internal/cbm/vendored/ts_runtime/` and `internal/cbm/grammar_*.c`.

## Testing

- **~5600 test cases** across ~80 C test files in `tests/`
- `scripts/test.sh` is CI's single source of truth: clean → build with ASan+UBSan → run all → watchdog regression → security-strings regression
- `tests/repro/` contains ~50 RED-by-design bug reproduction tests (run via `make test-repro`, not gating)
- Docker images in `test-infrastructure/` mirror CI exactly (Ubuntu Noble, Alpine, MinGW cross-compile)

## Installation Options (for local runtime)

### Recommended: Build from source (best optimization)

```bash
# Prerequisites: C compiler (gcc/clang), make, zlib, git
# Optional: libgit2-dev + pkg-config (faster git history), Node.js 22+ (for UI)

git clone https://github.com/DeusData/codebase-memory-mcp.git
cd codebase-memory-mcp
scripts/build.sh              # standard binary → build/c/codebase-memory-mcp
scripts/build.sh --with-ui    # with embedded 3D graph visualization
```

**Why build from source is best for optimization:**
- `-O2` compiler optimization tuned for your exact CPU
- mimalloc global allocator override (link-order, not DLL preload)
- Tree-sitter allocator bound to mimalloc (`-DCBM_BIND_TS_ALLOCATOR=1`)
- Optional libgit2 auto-detected (faster git history vs `popen`)
- All vendored libs compiled fresh with production flags
- Can customize `CC`/`CXX`/`CFLAGS` for platform-specific tuning

**Windows build from source:**
- Native: requires MinGW-w64 + zlib. `scripts/build.sh` auto-detects MinGW.
- WSL2: `scripts/setup-windows.ps1 -FromSource` builds inside WSL, wraps with `wsl.exe`.

### Fastest setup: Pre-built binary

| Platform | Command |
|----------|---------|
| macOS/Linux | `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh \| bash` |
| Windows | `irm https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1 \| iex` |
| npm | `npm install -g codebase-memory-mcp` |
| PyPI | `pipx install codebase-memory-mcp` |
| Homebrew | `brew install codebase-memory-mcp` |
| Scoop | `scoop install codebase-memory-mcp` |
| Winget | `winget install DeusData.CodebaseMemoryMcp` |
| AUR | `yay -S codebase-memory-mcp-bin` |
| Go | `go install github.com/DeusData/codebase-memory-mcp/pkg/go/cmd/codebase-memory-mcp@latest` |
| Nix | `nix build` (uses same Makefile, reproducible) |

Pre-built binaries use the same `-O2` + mimalloc flags from CI. Linux releases are `-portable` (static musl). The only advantage of building from source is libgit2 acceleration and custom compiler tuning.

### Post-install

```bash
codebase-memory-mcp install -y    # auto-configure all detected agents
codebase-memory-mcp config set auto_index true   # auto-index on session start
codebase-memory-mcp update        # check for updates
```

### Optimization knobs (environment variables)

| Variable | Default | Purpose |
|----------|---------|---------|
| `CBM_CACHE_DIR` | `~/.cache/codebase-memory-mcp` | SQLite database storage location |
| `CBM_WORKERS` | auto-detected | Override parallel indexing worker count (useful in containers) |
| `CBM_LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error`/`none` |
| `CBM_DIAGNOSTICS` | `false` | Set `1` for memory trajectory logging to `/tmp/cbm-diagnostics-<pid>.ndjson` |
| `CBM_SQLITE_MMAP_SIZE` | 64MB | SQLite memory-mapped I/O size |
| `CBM_SEMANTIC_THRESHOLD` | 0.75 | Semantic edge similarity threshold |
| `CBM_SEMANTIC_ENABLED` | `true` | Toggle semantic edge computation |

## Key Files to Know

| File | Why it matters |
|------|----------------|
| `Makefile.cbm` | Build system core — all targets, flags, source groups |
| `scripts/build.sh` | Release build wrapper (single source of truth) |
| `scripts/test.sh` | CI test runner (single source of truth) |
| `src/main.c` | Entry point: MCP server / CLI / UI mode dispatch |
| `src/mcp/mcp.c` | MCP server: JSON-RPC loop, 14 tool dispatch (~5000 lines) |
| `src/pipeline/pipeline.c` | Indexing orchestrator, pass registration, global lock |
| `src/store/store.c` | SQLite graph store, all CRUD + search + BFS |
| `src/cypher/cypher.c` | Cypher → SQL query engine |
| `internal/cbm/cbm.h` | `CBMLanguage` enum (158+ langs), core extraction types |
| `internal/cbm/lang_specs.c` | Per-language tree-sitter AST node-type configuration |
| `src/cli/hook_augment.c` | Claude Code PreToolUse hook (never blocks, 300ms deadline) |
| `server.json` | MCP server manifest (name, version, transport, packages) |

## Adding Language Support

1. Add `CBM_LANG_<NAME>` to enum in `internal/cbm/cbm.h`
2. Add row in language table in `internal/cbm/lang_specs.c`
3. Add grammar shim in `internal/cbm/grammar_<name>.c`
4. Add extraction logic in `internal/cbm/extract_*.c` if needed
5. Add tests in `tests/test_pipeline.c`
6. See [CONTRIBUTING.md](CONTRIBUTING.md) § "Adding or Fixing Language Support"

**Infrastructure languages** (Dockerfile, K8s, Kustomize) don't need a tree-sitter grammar — they follow the infra-pass pattern using the existing YAML grammar. See `pass_infrascan.c` and `extract_k8s.c`.

## Docker Runtime

Run the MCP server in a container — no C toolchain needed on the host.

### Quick start

```bash
# Pull and run (standard variant)
docker compose up -d

# With 3D graph visualization UI (port 9749)
docker compose --profile ui up -d
```

### Pull from GHCR (for other machines)

```bash
# Standard image (~25MB)
docker pull ghcr.io/jzkk720/codebase-memory-mcp:latest

# With graph UI (~40MB)
docker pull ghcr.io/jzkk720/codebase-memory-mcp:latest-ui
```

### Configuration

- **Persistent data**: Volume `cbm-data` mounted at `/data` (`CBM_CACHE_DIR=/data`)
- **MCP stdio**: `stdin_open: true` + `tty: true` in compose for JSON-RPC over stdin/stdout
- **UI port**: 9749 exposed only when using the `:latest-ui` image
- **Environment**: Set `CBM_WORKERS`, `CBM_LOG_LEVEL`, etc. in `compose.yaml`

### Configure MCP clients for containerized server

```json
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "-v", "cbm-data:/data",
               "ghcr.io/jzkk720/codebase-memory-mcp:latest"]
    }
  }
}
```

### Building locally

```bash
# Standard image
docker build -t cbm .

# With UI
docker build --build-arg WITH_UI=true -t cbm-ui .
```

## Iterative Refinement (Chronicle)

After significant work sessions, use `/chronicle improve` to iteratively refine these instructions:

1. **Run `/chronicle improve`** — analyzes past session history for friction patterns: repeated errors, failed approaches, common clarifications needed.
2. **Review findings** — identify which `AGENTS.md` sections are unclear, missing, or causing agents to make mistakes.
3. **Update instructions** — remove what's not needed, add what agents keep getting wrong, sharpen ambiguous guidance.
4. **Verify** — the next session should hit fewer friction points.

No session history exists yet for this repo — this is forward-looking guidance. As sessions accumulate, `/chronicle improve` becomes increasingly valuable for keeping these instructions sharp.

## Documentation

- [README.md](README.md) — features, quick start, full tool reference, configuration
- [CONTRIBUTING.md](CONTRIBUTING.md) — build/test/lint workflow, PR guidelines, DCO
- [SECURITY.md](SECURITY.md) — security policy, runtime network behavior, SLSA/Sigstore
- [docs/BENCHMARK.md](docs/BENCHMARK.md) — performance benchmarks across 63 languages
- [docs/EVALUATION_PLAN.md](docs/EVALUATION_PLAN.md) — evaluation methodology for 159 languages