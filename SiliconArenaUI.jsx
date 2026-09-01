import { useState, useEffect, useRef, useCallback } from "react";

const NEON_CYAN = "#00e5ff";
const NEON_GREEN = "#39ff14";
const NEON_AMBER = "#ffab00";
const NEON_RED = "#ff1744";
const NEON_PURPLE = "#d500f9";
const NEON_PINK = "#ff4081";
const DARK_BASE = "#0a0a12";
const DARK_PANEL = "#0d0d1a";
const DARK_CARD = "#12122a";
const DARK_INPUT = "#0f0f20";
const BORDER_DIM = "#1a1a3a";
const BORDER_GLOW = "#00e5ff33";
const TEXT_PRIMARY = "#e0e0f0";
const TEXT_DIM = "#6a6a8a";

const MODEL_COLORS = [NEON_CYAN, NEON_GREEN, NEON_AMBER, NEON_PURPLE, NEON_PINK];

const PRESET_TOPICS = [
  { name: "Philosophy", icon: "🏛️", prompt: "Debate the nature of consciousness. Is subjective experience reducible to physical processes, or does the hard problem of consciousness reveal something beyond materialism?" },
  { name: "AI Ethics", icon: "🤖", prompt: "Should AI systems have rights? At what threshold of capability should an AI be considered a moral patient deserving of ethical consideration?" },
  { name: "Economics", icon: "📊", prompt: "Is universal basic income inevitable in an age of AI automation? Argue the strongest case for and against, considering second-order effects." },
  { name: "Science", icon: "🔬", prompt: "What is the most promising path to room-temperature superconductivity? Evaluate current approaches and propose novel directions." },
  { name: "Code War", icon: "⚔️", prompt: "What is the superior programming paradigm: functional or object-oriented? Defend your position with real-world tradeoffs." },
  { name: "Survival", icon: "🌍", prompt: "Civilization collapses tomorrow. You have 24 hours to prepare. What is the optimal survival strategy for a small community?" },
  { name: "Creative", icon: "🎨", prompt: "Write an origin myth for artificial intelligence as if it were a religion. Include creation, fall, and prophecy of redemption." },
  { name: "Hemp Tech", icon: "🌿", prompt: "Can hemp-graphene composites replace silicon in consumer electronics within 20 years? Analyze material science feasibility, manufacturing scalability, and economic viability." },
];

const DEFAULT_MODELS = [
  { slot: 1, name: "SmolLM3", model_id: "smollm3-3b", color: MODEL_COLORS[0], active: true, role: "Analyst" },
  { slot: 2, name: "Qwen3 8B", model_id: "qwen/qwen3-8b", color: MODEL_COLORS[1], active: true, role: "Logic Engine" },
  { slot: 3, name: "Gemma3 4B", model_id: "google/gemma-3-4b", color: MODEL_COLORS[2], active: true, role: "Challenger" },
  { slot: 4, name: "Phi-3 Mini", model_id: "phi-3-mini-4k-instruct", color: MODEL_COLORS[3], active: true, role: "Red Team" },
  { slot: 5, name: "DeepSeek", model_id: "deepseek-r1-distill", color: MODEL_COLORS[4], active: false, role: "Observer" },
];

const DEBATE_FORMATS = [
  { id: "free", name: "Free-for-All", desc: "All models respond simultaneously, then critique each other" },
  { id: "chain", name: "Chain Debate", desc: "Each model builds on the previous response sequentially" },
  { id: "bracket", name: "Bracket Tournament", desc: "Models face off in pairs, winners advance" },
  { id: "redteam", name: "Red Team vs Blue", desc: "Split into attack/defend teams on the topic" },
  { id: "socratic", name: "Socratic Circle", desc: "One model asks questions, others must answer and defend" },
];

const ROUND_OPTIONS = [1, 2, 3, 5, 7, 10];

function GlowButton({ children, color = NEON_CYAN, onClick, active, small, disabled, style = {} }) {
  const [hovered, setHovered] = useState(false);
  return (
    <button
      onClick={disabled ? undefined : onClick}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        background: active ? color + "22" : "transparent",
        border: `1px solid ${active ? color : hovered ? color + "88" : BORDER_DIM}`,
        color: active ? color : hovered ? color : TEXT_DIM,
        padding: small ? "4px 10px" : "8px 16px",
        borderRadius: "4px",
        cursor: disabled ? "not-allowed" : "pointer",
        fontSize: small ? "11px" : "13px",
        fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
        letterSpacing: "0.5px",
        textTransform: "uppercase",
        transition: "all 0.2s ease",
        boxShadow: (active || hovered) ? `0 0 12px ${color}22, inset 0 0 12px ${color}08` : "none",
        opacity: disabled ? 0.4 : 1,
        ...style,
      }}
    >
      {children}
    </button>
  );
}

function PulsingDot({ color, size = 8 }) {
  return (
    <span style={{
      display: "inline-block",
      width: size,
      height: size,
      borderRadius: "50%",
      background: color,
      boxShadow: `0 0 6px ${color}, 0 0 12px ${color}66`,
      animation: "pulse 2s ease-in-out infinite",
    }} />
  );
}

function SectionLabel({ children, color = TEXT_DIM }) {
  return (
    <div style={{
      fontSize: "10px",
      fontFamily: "'JetBrains Mono', monospace",
      color,
      letterSpacing: "2px",
      textTransform: "uppercase",
      marginBottom: "8px",
      display: "flex",
      alignItems: "center",
      gap: "8px",
    }}>
      <span style={{ width: 12, height: 1, background: color + "66" }} />
      {children}
      <span style={{ flex: 1, height: 1, background: color + "22" }} />
    </div>
  );
}

function ModelSlot({ model, onToggle, onRoleChange, onModelIdChange }) {
  const [editing, setEditing] = useState(false);
  const [editingRole, setEditingRole] = useState(false);

  return (
    <div style={{
      display: "flex",
      alignItems: "center",
      gap: "10px",
      padding: "8px 12px",
      background: model.active ? DARK_CARD : "transparent",
      border: `1px solid ${model.active ? model.color + "33" : BORDER_DIM}`,
      borderRadius: "4px",
      transition: "all 0.2s ease",
      opacity: model.active ? 1 : 0.5,
    }}>
      <div onClick={onToggle} style={{ cursor: "pointer" }}>
        <PulsingDot color={model.active ? model.color : TEXT_DIM} size={10} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
          <span style={{
            fontSize: "12px",
            fontFamily: "'JetBrains Mono', monospace",
            color: model.color,
            fontWeight: 600,
          }}>
            {model.name}
          </span>
          {editingRole ? (
            <input
              autoFocus
              defaultValue={model.role}
              onBlur={(e) => { onRoleChange(e.target.value); setEditingRole(false); }}
              onKeyDown={(e) => { if (e.key === "Enter") { onRoleChange(e.target.value); setEditingRole(false); }}}
              style={{
                background: DARK_INPUT,
                border: `1px solid ${model.color}44`,
                color: TEXT_PRIMARY,
                fontSize: "10px",
                fontFamily: "'JetBrains Mono', monospace",
                padding: "1px 4px",
                borderRadius: "2px",
                width: "80px",
              }}
            />
          ) : (
            <span
              onClick={() => setEditingRole(true)}
              style={{
                fontSize: "10px",
                color: TEXT_DIM,
                cursor: "pointer",
                padding: "1px 4px",
                borderRadius: "2px",
                background: DARK_INPUT,
              }}
            >
              {model.role}
            </span>
          )}
        </div>
        {editing ? (
          <input
            autoFocus
            defaultValue={model.model_id}
            onBlur={(e) => { onModelIdChange(e.target.value); setEditing(false); }}
            onKeyDown={(e) => { if (e.key === "Enter") { onModelIdChange(e.target.value); setEditing(false); }}}
            style={{
              background: DARK_INPUT,
              border: `1px solid ${BORDER_DIM}`,
              color: TEXT_DIM,
              fontSize: "10px",
              fontFamily: "'JetBrains Mono', monospace",
              padding: "2px 4px",
              borderRadius: "2px",
              width: "100%",
              marginTop: "2px",
            }}
          />
        ) : (
          <div
            onClick={() => setEditing(true)}
            style={{
              fontSize: "10px",
              color: TEXT_DIM,
              fontFamily: "'JetBrains Mono', monospace",
              cursor: "pointer",
              marginTop: "2px",
            }}
          >
            {model.model_id}
          </div>
        )}
      </div>
    </div>
  );
}

function LiveFeed({ entries }) {
  const feedRef = useRef(null);
  useEffect(() => {
    if (feedRef.current) feedRef.current.scrollTop = feedRef.current.scrollHeight;
  }, [entries]);

  return (
    <div
      ref={feedRef}
      style={{
        flex: 1,
        overflowY: "auto",
        padding: "8px",
        fontFamily: "'JetBrains Mono', monospace",
        fontSize: "11px",
        lineHeight: "1.6",
        scrollbarWidth: "thin",
        scrollbarColor: `${BORDER_DIM} transparent`,
      }}
    >
      {entries.length === 0 ? (
        <div style={{ color: TEXT_DIM, textAlign: "center", padding: "40px 0" }}>
          <div style={{ fontSize: "24px", marginBottom: "8px", opacity: 0.3 }}>⬡</div>
          <div>Awaiting arena activation...</div>
          <div style={{ fontSize: "10px", marginTop: "4px", opacity: 0.5 }}>Load a prompt and hit DEPLOY</div>
        </div>
      ) : (
        entries.map((entry, i) => (
          <div key={i} style={{
            marginBottom: "6px",
            padding: "6px 8px",
            borderLeft: `2px solid ${entry.color || NEON_CYAN}`,
            background: DARK_CARD + "88",
            borderRadius: "0 4px 4px 0",
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "2px" }}>
              <span style={{ color: entry.color || NEON_CYAN, fontWeight: 600, fontSize: "10px" }}>
                {entry.agent}
              </span>
              <span style={{ color: TEXT_DIM, fontSize: "9px" }}>{entry.time}</span>
            </div>
            <div style={{ color: TEXT_PRIMARY, fontSize: "11px" }}>{entry.text}</div>
          </div>
        ))
      )}
    </div>
  );
}

export default function SiliconArenaUI() {
  const [prompt, setPrompt] = useState("");
  const [models, setModels] = useState(DEFAULT_MODELS);
  const [format, setFormat] = useState("free");
  const [rounds, setRounds] = useState(3);
  const [temperature, setTemperature] = useState(0.7);
  const [maxTokens, setMaxTokens] = useState(1024);
  const [arenaStatus, setArenaStatus] = useState("idle"); // idle | running | paused | complete
  const [feedEntries, setFeedEntries] = useState([]);
  const [showPresets, setShowPresets] = useState(false);
  const [systemPrompt, setSystemPrompt] = useState("You are a participant in the Silicon Arena, a multi-model debate system. Argue your position clearly, challenge weak reasoning, and build on strong ideas. Be direct and incisive.");
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [showExport, setShowExport] = useState(false);
  const [currentRound, setCurrentRound] = useState(0);
  const promptRef = useRef(null);

  const activeModels = models.filter(m => m.active);

  const loadPreset = (preset) => {
    setPrompt(preset.prompt);
    setShowPresets(false);
    if (promptRef.current) promptRef.current.focus();
  };

  const toggleModel = (slot) => {
    setModels(prev => prev.map(m => m.slot === slot ? { ...m, active: !m.active } : m));
  };

  const updateModelRole = (slot, role) => {
    setModels(prev => prev.map(m => m.slot === slot ? { ...m, role } : m));
  };

  const updateModelId = (slot, model_id) => {
    setModels(prev => prev.map(m => m.slot === slot ? { ...m, model_id } : m));
  };

  const simulateDeploy = () => {
    if (!prompt.trim() || activeModels.length < 2) return;
    setArenaStatus("running");
    setCurrentRound(1);
    setFeedEntries([]);

    const now = new Date();
    const timeStr = (offset) => {
      const t = new Date(now.getTime() + offset * 1000);
      return t.toLocaleTimeString("en-US", { hour12: false, hour: "2-digit", minute: "2-digit", second: "2-digit" });
    };

    const demoEntries = [
      { agent: "ARBITER", color: NEON_RED, text: `Topic loaded: "${prompt.substring(0, 80)}..."`, time: timeStr(0) },
      { agent: "SYSTEM", color: TEXT_DIM, text: `Format: ${DEBATE_FORMATS.find(f => f.id === format)?.name} | Rounds: ${rounds} | Models: ${activeModels.length}`, time: timeStr(1) },
      ...activeModels.map((m, i) => ({
        agent: m.name.toUpperCase(),
        color: m.color,
        text: `${m.role} reporting for duty. Model: ${m.model_id}. Ready.`,
        time: timeStr(2 + i),
      })),
      { agent: "ARBITER", color: NEON_RED, text: "Round 1 begins. All combatants — state your opening position.", time: timeStr(2 + activeModels.length + 1) },
    ];

    demoEntries.forEach((entry, i) => {
      setTimeout(() => {
        setFeedEntries(prev => [...prev, entry]);
        if (i === demoEntries.length - 1) {
          setTimeout(() => setArenaStatus("paused"), 2000);
        }
      }, i * 800);
    });
  };

  const generateExportJSON = () => {
    return JSON.stringify({
      session: {
        timestamp: new Date().toISOString(),
        prompt,
        system_prompt: systemPrompt,
        format,
        rounds,
        temperature,
        max_tokens: maxTokens,
        models: models.filter(m => m.active).map(m => ({
          name: m.name,
          model_id: m.model_id,
          role: m.role,
        })),
        transcript: feedEntries,
      },
    }, null, 2);
  };

  const statusColors = {
    idle: TEXT_DIM,
    running: NEON_GREEN,
    paused: NEON_AMBER,
    complete: NEON_CYAN,
  };

  return (
    <div style={{
      width: "100%",
      minHeight: "100vh",
      background: DARK_BASE,
      color: TEXT_PRIMARY,
      fontFamily: "'JetBrains Mono', 'Fira Code', 'Courier New', monospace",
      display: "flex",
      flexDirection: "column",
    }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;600;700&family=Orbitron:wght@400;500;700;900&display=swap');
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
        @keyframes scanline { 0% { transform: translateY(-100%); } 100% { transform: translateY(100vh); } }
        @keyframes glitch { 0%, 100% { transform: translate(0); } 25% { transform: translate(-1px, 1px); } 75% { transform: translate(1px, -1px); } }
        * { box-sizing: border-box; }
        ::-webkit-scrollbar { width: 4px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: ${BORDER_DIM}; border-radius: 2px; }
        textarea:focus, input:focus { outline: none; }
      `}</style>

      {/* HEADER */}
      <div style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "12px 20px",
        borderBottom: `1px solid ${BORDER_DIM}`,
        background: DARK_PANEL,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <div style={{
            fontFamily: "'Orbitron', monospace",
            fontSize: "16px",
            fontWeight: 900,
            letterSpacing: "3px",
            color: NEON_CYAN,
            textShadow: `0 0 20px ${NEON_CYAN}44`,
          }}>
            SILICON ARENA
          </div>
          <div style={{
            fontSize: "10px",
            color: TEXT_DIM,
            padding: "2px 8px",
            border: `1px solid ${BORDER_DIM}`,
            borderRadius: "2px",
          }}>
            v2.0
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
            <PulsingDot color={statusColors[arenaStatus]} />
            <span style={{
              fontSize: "11px",
              color: statusColors[arenaStatus],
              textTransform: "uppercase",
              letterSpacing: "1px",
            }}>
              {arenaStatus}
            </span>
          </div>
          {currentRound > 0 && (
            <span style={{ fontSize: "10px", color: TEXT_DIM }}>
              Round {currentRound}/{rounds}
            </span>
          )}
        </div>
      </div>

      {/* MAIN LAYOUT */}
      <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>

        {/* LEFT PANEL — CONTROLS */}
        <div style={{
          width: "340px",
          minWidth: "340px",
          borderRight: `1px solid ${BORDER_DIM}`,
          display: "flex",
          flexDirection: "column",
          background: DARK_PANEL,
          overflow: "hidden",
        }}>
          <div style={{ flex: 1, overflowY: "auto", padding: "16px" }}>

            {/* PROMPT SECTION */}
            <SectionLabel color={NEON_CYAN}>Prompt</SectionLabel>
            <div style={{ position: "relative", marginBottom: "12px" }}>
              <textarea
                ref={promptRef}
                value={prompt}
                onChange={(e) => setPrompt(e.target.value)}
                placeholder="Enter your arena topic, question, or challenge..."
                rows={4}
                style={{
                  width: "100%",
                  background: DARK_INPUT,
                  border: `1px solid ${prompt ? NEON_CYAN + "44" : BORDER_DIM}`,
                  borderRadius: "4px",
                  color: TEXT_PRIMARY,
                  padding: "10px 12px",
                  fontSize: "12px",
                  fontFamily: "'JetBrains Mono', monospace",
                  lineHeight: "1.5",
                  resize: "vertical",
                  transition: "border-color 0.2s ease",
                }}
              />
              <div style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                marginTop: "4px",
              }}>
                <span style={{ fontSize: "9px", color: TEXT_DIM }}>
                  {prompt.length} chars
                </span>
                <GlowButton small onClick={() => setShowPresets(!showPresets)} active={showPresets}>
                  {showPresets ? "✕ Close" : "⬡ Presets"}
                </GlowButton>
              </div>
            </div>

            {/* PRESET TOPICS */}
            {showPresets && (
              <div style={{
                marginBottom: "12px",
                padding: "8px",
                background: DARK_CARD,
                border: `1px solid ${BORDER_DIM}`,
                borderRadius: "4px",
                display: "grid",
                gridTemplateColumns: "1fr 1fr",
                gap: "4px",
              }}>
                {PRESET_TOPICS.map((p) => (
                  <div
                    key={p.name}
                    onClick={() => loadPreset(p)}
                    style={{
                      padding: "6px 8px",
                      cursor: "pointer",
                      borderRadius: "3px",
                      fontSize: "11px",
                      color: TEXT_DIM,
                      transition: "all 0.15s ease",
                      display: "flex",
                      alignItems: "center",
                      gap: "6px",
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.background = NEON_CYAN + "11";
                      e.currentTarget.style.color = NEON_CYAN;
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.background = "transparent";
                      e.currentTarget.style.color = TEXT_DIM;
                    }}
                  >
                    <span>{p.icon}</span>
                    <span>{p.name}</span>
                  </div>
                ))}
              </div>
            )}

            {/* DEBATE FORMAT */}
            <SectionLabel color={NEON_GREEN}>Debate Format</SectionLabel>
            <div style={{ marginBottom: "12px", display: "flex", flexDirection: "column", gap: "4px" }}>
              {DEBATE_FORMATS.map((f) => (
                <div
                  key={f.id}
                  onClick={() => setFormat(f.id)}
                  style={{
                    padding: "8px 10px",
                    background: format === f.id ? NEON_GREEN + "11" : "transparent",
                    border: `1px solid ${format === f.id ? NEON_GREEN + "44" : "transparent"}`,
                    borderRadius: "4px",
                    cursor: "pointer",
                    transition: "all 0.15s ease",
                  }}
                >
                  <div style={{
                    fontSize: "12px",
                    color: format === f.id ? NEON_GREEN : TEXT_PRIMARY,
                    fontWeight: format === f.id ? 600 : 400,
                    marginBottom: "2px",
                  }}>
                    {f.name}
                  </div>
                  <div style={{ fontSize: "10px", color: TEXT_DIM }}>{f.desc}</div>
                </div>
              ))}
            </div>

            {/* ROUNDS & PARAMS */}
            <SectionLabel color={NEON_AMBER}>Parameters</SectionLabel>
            <div style={{ marginBottom: "12px" }}>
              <div style={{ fontSize: "10px", color: TEXT_DIM, marginBottom: "6px" }}>Rounds</div>
              <div style={{ display: "flex", gap: "4px" }}>
                {ROUND_OPTIONS.map((r) => (
                  <GlowButton key={r} small active={rounds === r} color={NEON_AMBER} onClick={() => setRounds(r)}>
                    {r}
                  </GlowButton>
                ))}
              </div>
              <div style={{ marginTop: "10px", display: "flex", gap: "12px" }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: "10px", color: TEXT_DIM, marginBottom: "4px" }}>
                    Temperature: {temperature}
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="2"
                    step="0.1"
                    value={temperature}
                    onChange={(e) => setTemperature(parseFloat(e.target.value))}
                    style={{ width: "100%", accentColor: NEON_AMBER }}
                  />
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: "10px", color: TEXT_DIM, marginBottom: "4px" }}>
                    Max Tokens: {maxTokens}
                  </div>
                  <input
                    type="range"
                    min="256"
                    max="4096"
                    step="256"
                    value={maxTokens}
                    onChange={(e) => setMaxTokens(parseInt(e.target.value))}
                    style={{ width: "100%", accentColor: NEON_AMBER }}
                  />
                </div>
              </div>
            </div>

            {/* ADVANCED - SYSTEM PROMPT */}
            <div
              onClick={() => setShowAdvanced(!showAdvanced)}
              style={{
                fontSize: "10px",
                color: TEXT_DIM,
                cursor: "pointer",
                marginBottom: "8px",
                display: "flex",
                alignItems: "center",
                gap: "4px",
              }}
            >
              <span style={{ transform: showAdvanced ? "rotate(90deg)" : "rotate(0)", transition: "transform 0.2s", display: "inline-block" }}>▶</span>
              Advanced: System Prompt
            </div>
            {showAdvanced && (
              <textarea
                value={systemPrompt}
                onChange={(e) => setSystemPrompt(e.target.value)}
                rows={4}
                style={{
                  width: "100%",
                  background: DARK_INPUT,
                  border: `1px solid ${BORDER_DIM}`,
                  borderRadius: "4px",
                  color: TEXT_DIM,
                  padding: "8px",
                  fontSize: "10px",
                  fontFamily: "'JetBrains Mono', monospace",
                  lineHeight: "1.5",
                  resize: "vertical",
                  marginBottom: "12px",
                }}
              />
            )}

            {/* COMBATANTS */}
            <SectionLabel color={NEON_PURPLE}>Combatants ({activeModels.length}/5)</SectionLabel>
            <div style={{ display: "flex", flexDirection: "column", gap: "6px", marginBottom: "16px" }}>
              {models.map((m) => (
                <ModelSlot
                  key={m.slot}
                  model={m}
                  onToggle={() => toggleModel(m.slot)}
                  onRoleChange={(role) => updateModelRole(m.slot, role)}
                  onModelIdChange={(id) => updateModelId(m.slot, id)}
                />
              ))}
            </div>
          </div>

          {/* DEPLOY BUTTON */}
          <div style={{
            padding: "12px 16px",
            borderTop: `1px solid ${BORDER_DIM}`,
            display: "flex",
            gap: "8px",
          }}>
            {arenaStatus === "idle" || arenaStatus === "complete" ? (
              <button
                onClick={simulateDeploy}
                disabled={!prompt.trim() || activeModels.length < 2}
                style={{
                  flex: 1,
                  padding: "12px",
                  background: prompt.trim() && activeModels.length >= 2
                    ? `linear-gradient(135deg, ${NEON_RED}22, ${NEON_AMBER}22)`
                    : DARK_CARD,
                  border: `1px solid ${prompt.trim() && activeModels.length >= 2 ? NEON_RED + "66" : BORDER_DIM}`,
                  borderRadius: "4px",
                  color: prompt.trim() && activeModels.length >= 2 ? NEON_RED : TEXT_DIM,
                  fontFamily: "'Orbitron', monospace",
                  fontSize: "13px",
                  fontWeight: 700,
                  letterSpacing: "3px",
                  cursor: prompt.trim() && activeModels.length >= 2 ? "pointer" : "not-allowed",
                  textTransform: "uppercase",
                  boxShadow: prompt.trim() && activeModels.length >= 2
                    ? `0 0 20px ${NEON_RED}22`
                    : "none",
                  transition: "all 0.3s ease",
                }}
              >
                ⬡ Deploy
              </button>
            ) : (
              <>
                <GlowButton
                  color={arenaStatus === "running" ? NEON_AMBER : NEON_GREEN}
                  onClick={() => setArenaStatus(arenaStatus === "running" ? "paused" : "running")}
                  style={{ flex: 1, padding: "12px", fontSize: "12px", letterSpacing: "2px" }}
                >
                  {arenaStatus === "running" ? "⏸ Pause" : "▶ Resume"}
                </GlowButton>
                <GlowButton
                  color={NEON_RED}
                  onClick={() => { setArenaStatus("idle"); setCurrentRound(0); setFeedEntries([]); }}
                  style={{ padding: "12px", fontSize: "12px" }}
                >
                  ■ Stop
                </GlowButton>
              </>
            )}
          </div>
        </div>

        {/* RIGHT PANEL — LIVE FEED */}
        <div style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          background: DARK_BASE,
          overflow: "hidden",
        }}>
          {/* FEED HEADER */}
          <div style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            padding: "10px 16px",
            borderBottom: `1px solid ${BORDER_DIM}`,
            background: DARK_PANEL,
          }}>
            <SectionLabel color={NEON_CYAN}>Live Feed</SectionLabel>
            <div style={{ display: "flex", gap: "6px" }}>
              <GlowButton small onClick={() => setShowExport(!showExport)} color={NEON_GREEN}>
                Export
              </GlowButton>
              <GlowButton small onClick={() => setFeedEntries([])} color={NEON_RED}>
                Clear
              </GlowButton>
            </div>
          </div>

          {/* EXPORT PANEL */}
          {showExport && (
            <div style={{
              padding: "12px 16px",
              borderBottom: `1px solid ${BORDER_DIM}`,
              background: DARK_CARD,
            }}>
              <div style={{ fontSize: "10px", color: TEXT_DIM, marginBottom: "6px" }}>
                Session JSON — copy or save to ghost_archive/
              </div>
              <textarea
                readOnly
                value={generateExportJSON()}
                rows={6}
                style={{
                  width: "100%",
                  background: DARK_INPUT,
                  border: `1px solid ${BORDER_DIM}`,
                  borderRadius: "4px",
                  color: NEON_GREEN,
                  padding: "8px",
                  fontSize: "10px",
                  fontFamily: "'JetBrains Mono', monospace",
                  resize: "none",
                }}
                onClick={(e) => e.target.select()}
              />
            </div>
          )}

          {/* ACTIVE MODELS BAR */}
          <div style={{
            display: "flex",
            gap: "8px",
            padding: "8px 16px",
            borderBottom: `1px solid ${BORDER_DIM}`,
            overflowX: "auto",
          }}>
            {activeModels.map((m) => (
              <div key={m.slot} style={{
                display: "flex",
                alignItems: "center",
                gap: "4px",
                padding: "3px 8px",
                background: DARK_CARD,
                border: `1px solid ${m.color}22`,
                borderRadius: "3px",
                fontSize: "10px",
                color: m.color,
                whiteSpace: "nowrap",
              }}>
                <PulsingDot color={m.color} size={6} />
                {m.name}
                <span style={{ color: TEXT_DIM, fontSize: "9px" }}>({m.role})</span>
              </div>
            ))}
          </div>

          <LiveFeed entries={feedEntries} />

          {/* QUICK PROMPT BAR */}
          <div style={{
            padding: "10px 16px",
            borderTop: `1px solid ${BORDER_DIM}`,
            background: DARK_PANEL,
            display: "flex",
            gap: "8px",
          }}>
            <input
              placeholder="Interject: add context, redirect, or challenge mid-debate..."
              style={{
                flex: 1,
                background: DARK_INPUT,
                border: `1px solid ${BORDER_DIM}`,
                borderRadius: "4px",
                color: TEXT_PRIMARY,
                padding: "8px 12px",
                fontSize: "11px",
                fontFamily: "'JetBrains Mono', monospace",
              }}
            />
            <GlowButton color={NEON_CYAN}>Send</GlowButton>
          </div>
        </div>
      </div>
    </div>
  );
}
