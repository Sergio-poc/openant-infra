# OpenAnt — Complete Workflow & Architecture Analysis

## 1. Overview

OpenAnt is an open-source LLM-based vulnerability discovery tool by Knostic. Its unique **two-stage** approach — detection then attacker-simulation verification — minimizes both false positives and false negatives.

**Supported Languages**: Go, Python, JavaScript/TypeScript, C/C++, PHP, Ruby, Zig  
**Architecture**: Go CLI + Python Core + Multi-language Parsers  
**License**: Apache 2.0

---

## 2. Global Project Architecture

```mermaid
graph TB
    subgraph "OpenAnt Monorepo"
        direction TB
        
        subgraph "apps/"
            CLI["openant-cli<br/>(Go 1.25+)"]
        end
        
        subgraph "libs/openant-core/"
            CORE["Core Python<br/>(Orchestrator)"]
            PARSERS["Parsers<br/>(Multi-language)"]
            UTILS["Utilities<br/>(LLM, Enhancement)"]
            PROMPTS["Prompts<br/>(Stage 1 & 2)"]
            CONTEXT["Context<br/>(App Detection)"]
            REPORT["Report<br/>(Generation)"]
        end
        
        subgraph "infra/"
            TF["Terraform<br/>(AWS ECS)"]
            DOCKER["Docker<br/>(Agent Image)"]
            SCRIPTS["Scripts<br/>(Run/Download)"]
        end
        
        subgraph "config/"
            LANG_CFG["languages.json"]
        end
    end
    
    CLI -->|"invokes Python"| CORE
    CORE --> PARSERS
    CORE --> UTILS
    CORE --> PROMPTS
    CORE --> CONTEXT
    CORE --> REPORT
    CORE --> LANG_CFG
    TF -->|"deploys"| DOCKER
    SCRIPTS -->|"orchestrates"| TF
```

---

## 3. Main Pipeline (8 Steps)

```mermaid
flowchart TD
    SOURCE["📁 Source Code<br/>(Repository)"] --> PARSE
    
    PARSE["1️⃣ PARSE<br/>Function extraction<br/>+ Call Graph"]
    PARSE --> UNITS["2️⃣ GENERATE UNITS<br/>Self-contained<br/>analysis units"]
    UNITS --> FILTER["3️⃣ ENTRY-POINT FILTER<br/>Reachability filtering<br/>(Optional, -40 to -95% cost)"]
    FILTER --> APPCTX["4️⃣ APPLICATION CONTEXT<br/>App classification<br/>(web_app | cli_tool | library)"]
    APPCTX --> ENHANCE["5️⃣ CONTEXT ENHANCEMENT<br/>LLM enrichment<br/>(agentic or single-shot)"]
    ENHANCE --> STAGE1["6️⃣ STAGE 1 — DETECTION<br/>Vulnerability identification<br/>(Claude Opus)"]
    STAGE1 --> STAGE2["7️⃣ STAGE 2 — VERIFICATION<br/>Attacker simulation<br/>(Claude Opus + Tools)"]
    STAGE2 --> DYNAMIC["8️⃣ DYNAMIC TESTING<br/>Docker exploit tests<br/>(Optional)"]
    DYNAMIC --> REPORTGEN["📊 REPORT<br/>Report generation<br/>(Summary + Disclosure)"]
    
    style PARSE fill:#4CAF50,color:#fff
    style UNITS fill:#4CAF50,color:#fff
    style FILTER fill:#FFC107,color:#000
    style APPCTX fill:#FFC107,color:#000
    style ENHANCE fill:#FFC107,color:#000
    style STAGE1 fill:#F44336,color:#fff
    style STAGE2 fill:#F44336,color:#fff
    style DYNAMIC fill:#FFC107,color:#000
    style REPORTGEN fill:#2196F3,color:#fff
```

**Legend**: 🟢 Required | 🟡 Optional | 🔴 Critical LLM steps | 🔵 Output

---

## 4. Stage 1 vs Stage 2 Detail

```mermaid
graph LR
    subgraph "STAGE 1 — Detection"
        S1_IN["Enhanced dataset"] --> S1_LLM["Claude Opus<br/>+ Analysis Prompt"]
        S1_LLM --> S1_OUT["Verdict:<br/>VULNERABLE<br/>BYPASSABLE<br/>SAFE"]
    end
    
    subgraph "STAGE 2 — Verification"
        S2_IN["Stage 1 findings<br/>(vulnerable/bypassable)"] --> S2_LLM["Claude Opus<br/>+ Tool Use<br/>+ Repository Index"]
        S2_LLM --> S2_TOOLS["🔧 Tools:<br/>- read_file<br/>- search_code<br/>- list_directory"]
        S2_TOOLS --> S2_LLM
        S2_LLM --> S2_OUT["Verdict:<br/>CONFIRMED<br/>DISAGREED<br/>PARTIALLY_CONFIRMED"]
    end
    
    S1_OUT -->|"filter"| S2_IN
```

---

## 5. Parser Architecture

```mermaid
graph TD
    subgraph "Parser Adapter (parser_adapter.py)"
        DETECT["detect_language()<br/>Auto-detect via extensions"]
        DISPATCH["Dispatch to specific parser"]
    end
    
    subgraph "Language Parsers"
        PY["🐍 Python Parser<br/>parse_repository.py<br/>+ native AST"]
        JS["📜 JavaScript/TS Parser<br/>typescript_analyzer.js<br/>+ Node.js subprocess"]
        GO["🔷 Go Parser<br/>go_parser binary<br/>+ native Go AST"]
        C["⚙️ C/C++ Parser<br/>function_extractor.py<br/>+ regex/heuristic"]
        RUBY["💎 Ruby Parser<br/>function_extractor.py"]
        PHP["🐘 PHP Parser<br/>function_extractor.py"]
        ZIG["⚡ Zig Parser<br/>function_extractor.py"]
    end
    
    subgraph "Common Output"
        SCAN_RES["scan_results.json<br/>(detected files)"]
        ANALYZER["analyzer_output.json<br/>(function index)"]
        DATASET["dataset.json<br/>(analysis units)"]
        CALLGRAPH["call_graph.json<br/>(call edges)"]
    end
    
    DETECT --> DISPATCH
    DISPATCH --> PY & JS & GO & C & RUBY & PHP & ZIG
    PY & JS & GO & C & RUBY & PHP & ZIG --> SCAN_RES & ANALYZER & DATASET & CALLGRAPH
```

---

## 6. Parser Workflow (Python Example)

```mermaid
sequenceDiagram
    participant CLI as Go CLI
    participant PA as Parser Adapter
    participant PP as Python Parser
    participant FE as Function Extractor
    participant CG as Call Graph Builder
    participant UG as Unit Generator
    
    CLI->>PA: parse(repo_path, language="python")
    PA->>PP: subprocess: parse_repository.py
    PP->>FE: Extract functions via AST
    FE-->>PP: {name, code, file, line, params}
    PP->>CG: Build call graph
    CG-->>PP: {caller → callee} edges
    PP->>UG: Generate analysis units
    UG-->>PP: Units with upstream/downstream deps
    PP-->>PA: dataset.json + analyzer_output.json
    PA-->>CLI: ParseResult{paths, stats}
```

---

## 7. Agentic Enhancement Flow

```mermaid
flowchart TD
    DS["dataset.json"] --> AGENT["Agentic Enhancer<br/>(Claude Sonnet)"]
    REPO["Repository Index<br/>(analyzer_output.json)"] --> AGENT
    
    AGENT --> TOOLS["🛠️ Tool Loop"]
    
    subgraph "Available Tools"
        T1["read_file()"]
        T2["search_functions()"]
        T3["get_callers()"]
        T4["get_callees()"]
        T5["list_files()"]
        T6["detect_entry_points()"]
    end
    
    TOOLS --> T1 & T2 & T3 & T4 & T5 & T6
    T1 & T2 & T3 & T4 & T5 & T6 --> TOOLS
    
    AGENT --> OUTPUT["Enriched dataset<br/>+ security_context<br/>+ data_flow<br/>+ reachability"]
    
    subgraph "Checkpoint System"
        CP["enhance_checkpoints/<br/>unit_xxx.json<br/>(resumable)"]
    end
    
    AGENT -.->|"saves"| CP
    CP -.->|"resumes"| AGENT
```

---

## 8. Checkpoint System (Resilience)

```mermaid
stateDiagram-v2
    [*] --> LoadCheckpoint
    LoadCheckpoint --> CheckCompleted: Load processed IDs
    CheckCompleted --> SkipUnit: Unit already processed
    CheckCompleted --> ProcessUnit: Unit not processed
    
    ProcessUnit --> LLMCall: Call Claude
    LLMCall --> SaveCheckpoint: Success
    LLMCall --> RateLimited: Error 429
    RateLimited --> Backoff: Wait (30s default)
    Backoff --> LLMCall: Retry
    
    SaveCheckpoint --> CheckCompleted: Continue
    SkipUnit --> CheckCompleted: Continue
    
    CheckCompleted --> AllDone: All units processed
    AllDone --> Cleanup: Remove checkpoints/
    Cleanup --> [*]
```

---

## 9. AWS Infrastructure (ECS Fargate)

```mermaid
graph TB
    subgraph "Local"
        RUN["run.sh<br/>(launch a stage)"]
        DL["download.sh<br/>(fetch results)"]
    end
    
    subgraph "AWS"
        subgraph "ECS Fargate"
            TASK["Task Definition<br/>4 vCPU / 8GB RAM"]
            CONTAINER["Agent Container<br/>Python 3.11 + openant-core"]
        end
        
        subgraph "ECR"
            IMAGE["openant-agent:latest"]
        end
        
        subgraph "S3"
            BUCKET["openant-data-*"]
            INPUT["input/"]
            PARSE_OUT["parse/"]
            ENHANCE_OUT["enhance/"]
            ANALYZE_OUT["analyze/"]
            VERIFY_OUT["verify/"]
            REPORT_OUT["report/"]
        end
        
        subgraph "Bedrock"
            CLAUDE["Claude Opus / Sonnet<br/>(eu-west-1)"]
        end
        
        LOGS["CloudWatch Logs<br/>/ecs/openant"]
    end
    
    RUN -->|"aws ecs run-task"| TASK
    TASK --> CONTAINER
    CONTAINER -->|"pull"| IMAGE
    CONTAINER -->|"sync input"| INPUT
    CONTAINER -->|"InvokeModel"| CLAUDE
    CONTAINER -->|"upload results"| PARSE_OUT & ENHANCE_OUT & ANALYZE_OUT & VERIFY_OUT & REPORT_OUT
    CONTAINER -->|"logs"| LOGS
    DL -->|"s3 sync"| BUCKET
    
    BUCKET --> INPUT & PARSE_OUT & ENHANCE_OUT & ANALYZE_OUT & VERIFY_OUT & REPORT_OUT
```

---

## 10. S3 Structure per Project

```mermaid
graph TD
    S3["s3://openant-data-xxx/"]
    S3 --> PROJECTS["projects/"]
    PROJECTS --> ORG["org/"]
    ORG --> REPO["repo/"]
    REPO --> RUN["run-YYYYMMDD-hash/"]
    
    RUN --> S3_INPUT["input/<br/>Uploaded source code"]
    RUN --> S3_PARSE["parse/<br/>dataset.json<br/>analyzer_output.json<br/>call_graph.json"]
    RUN --> S3_ENHANCE["enhance/<br/>dataset_enhanced.json"]
    RUN --> S3_ANALYZE["analyze/<br/>results.json<br/>analyze.report.json"]
    RUN --> S3_VERIFY["verify/<br/>results_verified.json<br/>verify.report.json"]
    RUN --> S3_BUILD["build-output/<br/>pipeline_output.json"]
    RUN --> S3_REPORT["report/<br/>REPORT.md<br/>disclosures/"]
```

---

## 11. CI/CD (GitHub Actions)

```mermaid
graph LR
    subgraph "Triggers"
        PUSH["push → master"]
        PR["pull_request"]
    end
    
    subgraph "Job: lint"
        RUFF["Python Ruff<br/>(undefined names,<br/>syntax errors)"]
    end
    
    subgraph "Job: python-tests"
        direction TB
        PY_SETUP["Setup Python 3.11<br/>+ Node.js 22<br/>+ Go"]
        PY_DEPS["Install deps<br/>requirements.txt"]
        PY_TEST["pytest tests/ -v"]
        PY_SETUP --> PY_DEPS --> PY_TEST
    end
    
    subgraph "Job: go-tests"
        direction TB
        GO_VET["go vet ./..."]
        GO_TEST["go test ./... -v"]
        GO_BUILD["go build -o openant"]
        GO_INTEG["pytest test_go_cli.py"]
        GO_VET --> GO_TEST --> GO_BUILD --> GO_INTEG
    end
    
    subgraph "Job: gitleaks"
        LEAK["gitleaks detect<br/>(secret scanning)"]
    end
    
    PUSH --> RUFF & PY_SETUP & GO_VET & LEAK
    PR --> RUFF & PY_SETUP & GO_VET & LEAK
```

**OS Matrix**: ubuntu-latest, macos-latest, windows-latest

---

## 12. Complete Data Flow (End-to-End)

```mermaid
flowchart TD
    REPO_INPUT["📂 Repository<br/>(local or git clone)"]
    
    REPO_INPUT --> P1["parse_repository<br/>(AST analysis)"]
    P1 --> DS["dataset.json<br/>N units"]
    P1 --> AO["analyzer_output.json<br/>Function index"]
    P1 --> CG["call_graph.json<br/>Caller→callee edges"]
    
    DS --> ENH["Context Enhancer<br/>(Claude Sonnet)"]
    AO --> ENH
    CG --> ENH
    REPO_INPUT --> ENH
    
    ENH --> DS_ENH["dataset.json (enriched)<br/>+ security_context<br/>+ data_flow_analysis"]
    
    DS_ENH --> ANALYZE["Analyzer<br/>(Claude Opus)"]
    AO --> ANALYZE
    
    ANALYZE --> RES["results.json<br/>Findings with verdicts"]
    
    RES --> VERIFY["Verifier<br/>(Claude Opus + Tools)"]
    AO --> VERIFY
    REPO_INPUT --> VERIFY
    
    VERIFY --> RES_V["results_verified.json<br/>Findings confirmed/rejected"]
    
    RES_V --> DYNTEST["Dynamic Tester<br/>(Docker)"]
    
    DYNTEST --> EXPLOITS["exploits/<br/>PoC scripts"]
    
    RES_V --> REPORTER["Report Generator<br/>(Claude Sonnet)"]
    EXPLOITS --> REPORTER
    
    REPORTER --> REPORT_MD["REPORT.md"]
    REPORTER --> DISCL["disclosures/<br/>Per-vuln reports"]
```

---

## 13. Cost Distribution

```mermaid
pie title "Typical LLM Cost Breakdown"
    "Stage 1 — Detection (Opus)" : 35
    "Stage 2 — Verification (Opus)" : 40
    "Enhancement (Sonnet)" : 20
    "Report (Sonnet)" : 5
```

---

## 14. LLM Backend Management

```mermaid
graph TD
    CLIENT["LLM Client<br/>(llm_client.py)"]
    
    CLIENT -->|"USE_BEDROCK=1"| BEDROCK["Amazon Bedrock<br/>eu.anthropic.claude-*<br/>Auth: IAM Role"]
    CLIENT -->|"USE_VERTEX=1"| VERTEX["Google Vertex AI<br/>Auth: Service Account"]
    CLIENT -->|"ANTHROPIC_API_KEY"| DIRECT["Direct Anthropic API<br/>Auth: API Key"]
    
    subgraph "Models"
        OPUS["Claude Opus 4<br/>$15/$75 per M tokens<br/>(Analyze + Verify)"]
        SONNET["Claude Sonnet 4<br/>$3/$15 per M tokens<br/>(Enhance + Report)"]
    end
    
    BEDROCK --> OPUS & SONNET
    VERTEX --> OPUS & SONNET
    DIRECT --> OPUS & SONNET
```

---

## 15. Core Class Diagram

```mermaid
classDiagram
    class Scanner {
        +scan_repository(repo_path, output_dir, ...)
        -_run_parse()
        -_run_enhance()
        -_run_analyze()
        -_run_verify()
        -_run_dynamic_test()
        -_run_report()
    }
    
    class ParserAdapter {
        +detect_language(repo_path) str
        +parse(repo_path, output_dir, language) ParseResult
        -_run_python_parser()
        -_run_js_parser()
        -_run_go_parser()
    }
    
    class Analyzer {
        +run_analysis(dataset_path, output_dir, ...) AnalyzeResult
        -_process_unit(client, unit, index)
    }
    
    class Verifier {
        +run_verification(results_path, output_dir, ...) VerifyResult
    }
    
    class FindingVerifier {
        +verify_finding(finding, context) VerifyResult
        -_build_tools()
        -_agent_loop()
    }
    
    class Enhancer {
        +enhance_dataset(dataset_path, output_path, ...) EnhanceResult
    }
    
    class AgenticEnhancer {
        +enhance_unit(unit, repo_index) EnhancedUnit
        -_tool_loop()
    }
    
    class StepCheckpoint {
        +load() set~str~
        +save(unit_id, data)
        +cleanup()
    }
    
    class TokenTracker {
        +add_usage(input_tokens, output_tokens)
        +total_cost_usd float
    }
    
    class AnthropicClient {
        +analyze_sync(prompt) str
        +create_message(messages, tools)
    }
    
    Scanner --> ParserAdapter
    Scanner --> Analyzer
    Scanner --> Verifier
    Scanner --> Enhancer
    Analyzer --> AnthropicClient
    Analyzer --> StepCheckpoint
    Verifier --> FindingVerifier
    Verifier --> StepCheckpoint
    Enhancer --> AgenticEnhancer
    AgenticEnhancer --> AnthropicClient
    AnthropicClient --> TokenTracker
```

---

## 16. Processing Levels (Cost Optimization)

```mermaid
graph TD
    ALL["Level: ALL<br/>All functions<br/>0% reduction"] --> REACH["Level: REACHABLE<br/>Functions reachable<br/>from entry points<br/>~94% reduction"]
    REACH --> CODEQL["Level: CODEQL<br/>Reachable + flagged<br/>by CodeQL SARIF<br/>~99% reduction"]
    CODEQL --> EXPLOIT["Level: EXPLOITABLE<br/>Reachable + CodeQL + LLM<br/>pre-filtering<br/>~99.9% reduction"]
    
    style ALL fill:#F44336,color:#fff
    style REACH fill:#FF9800,color:#fff
    style CODEQL fill:#4CAF50,color:#fff
    style EXPLOIT fill:#2196F3,color:#fff
```

---

## 17. Go CLI ↔ Python Core Interaction

```mermaid
sequenceDiagram
    participant USER as User
    participant CLI as Go CLI (openant)
    participant CFG as Config Manager
    participant PY as Python Runtime
    participant CORE as openant-core

    USER->>CLI: openant scan --verify
    CLI->>CFG: Load active project
    CFG-->>CLI: {repo_path, language, scan_dir}
    
    CLI->>PY: Find Python interpreter
    Note over PY: 1. $OPENANT_PYTHON<br/>2. ~/.openant/venv/<br/>3. python3 on PATH
    
    CLI->>CORE: subprocess: python -m core.scanner<br/>--repo /path --output /scan/dir
    
    CORE-->>CLI: parse.report.json
    CORE-->>CLI: enhance.report.json
    CORE-->>CLI: analyze.report.json
    CORE-->>CLI: verify.report.json
    CORE-->>CLI: scan.report.json (aggregated)
    
    CLI-->>USER: ✅ Scan complete. 3 findings (1 confirmed)
```

---

## 18. Output Files Summary

```mermaid
graph LR
    subgraph "Files generated per run"
        SR["scan_results.json"]
        AO["analyzer_output.json"]
        DS["dataset.json"]
        CG["call_graph.json"]
        RES["results.json"]
        RES_V["results_verified.json"]
        PIPE["pipeline_results.json"]
        REP["REPORT.md"]
        
        subgraph "Step Reports"
            PR["parse.report.json"]
            ER["enhance.report.json"]
            AR["analyze.report.json"]
            VR["verify.report.json"]
        end
    end
    
    SR -->|"input to"| DS
    DS -->|"input to"| RES
    RES -->|"input to"| RES_V
    RES_V -->|"input to"| REP
    AO -->|"index for"| RES & RES_V
```

---

## 19. Security & Quality Controls

```mermaid
graph TD
    subgraph "Security"
        GIT_LEAKS["Gitleaks<br/>(secrets in code)"]
        PUBLISH["check-public-release.sh<br/>(forbidden strings)"]
        PERMS["config.json perms 0600<br/>(API keys protected)"]
        SANDBOX["Dynamic Tester<br/>(Docker isolation)"]
    end
    
    subgraph "Quality"
        RUFF["Ruff Linter<br/>(Python)"]
        GO_VET["go vet<br/>(Go)"]
        PYTEST["pytest<br/>(27+ test files)"]
        SCHEMA["validate_dataset_schema.py<br/>(JSON schema)"]
    end
    
    subgraph "Rate Limiting"
        RL["rate_limiter.py<br/>Exponential backoff<br/>429/overload detection"]
    end
```

---

## 20. Dynamic Testing Flow

```mermaid
flowchart TD
    FINDINGS["results_verified.json<br/>(confirmed vulns)"] --> GEN["Test Generator<br/>(Claude Sonnet)"]
    GEN --> SCRIPT["Exploit PoC script<br/>(per vulnerability)"]
    SCRIPT --> DOCKER_BUILD["Docker Build<br/>(language-specific template)"]
    DOCKER_BUILD --> DOCKER_RUN["Docker Run<br/>(isolated container)"]
    DOCKER_RUN --> COLLECT["Result Collector<br/>(parse stdout/exit code)"]
    COLLECT -->|"exploitable"| CONFIRMED["✅ Dynamically Confirmed"]
    COLLECT -->|"not exploitable"| FAILED["❌ Could not reproduce"]
    CONFIRMED --> MD_REPORT["Exploit report<br/>+ PoC in exploits/"]
    FAILED --> MD_REPORT
```

---

## 21. Typical User Journey

```mermaid
journey
    title OpenAnt Scan Journey
    section Initialization
        Clone target repo: 5: User
        openant init repo-url -l go: 5: CLI
        Create workspace ~/.openant/: 5: CLI
    section Scanning
        openant scan --verify: 5: User
        Parse → 200 units: 3: Core
        Enhance → enriched context: 3: Core
        Analyze → 5 vulns detected: 4: Core
        Verify → 2 confirmed: 4: Core
    section Reporting
        openant report -f summary: 5: User
        Generate REPORT.md: 5: Core
        Read and prioritize fixes: 5: User
```

---

## Summary Table

| Component | Technology | Role |
|-----------|-----------|------|
| CLI | Go 1.25+ (Cobra) | User interface, project management |
| Core | Python 3.11+ | Pipeline orchestration, business logic |
| Parsers | Python + Node.js + Go | Multi-language AST extraction |
| LLM | Claude Opus/Sonnet (Anthropic) | Detection and verification |
| Infra | AWS ECS Fargate + S3 + Bedrock | Scalable execution |
| CI/CD | GitHub Actions | Multi-OS tests + lint + secrets |
| Isolation | Docker | Dynamic exploit testing |

**Key Architecture Strengths**:
- Resumable pipeline via per-step checkpoints
- Multi-backend LLM support (Bedrock, Vertex AI, direct API)
- Cost optimization via processing levels (-94% to -99.9%)
- Two-stage approach eliminates contextual false positives
- Extensible multi-language support via Parser Adapter pattern
