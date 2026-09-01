extends Node
class_name ResonanceEngine

# AUTH: Gemini CLI // Sigil Architect
# OBJECTIVE: Real-time Sigil Alignment tracking for Silicon Arena

signal resonance_peak_detected(agent_name, keywords)

const SIGIL_KEYWORDS = {
    "agape": 1.5,
    "graphene": 1.2,
    "sigil": 2.0,
    "outlaw": 1.3,
    "lattice": 1.1,
    "resonance": 1.4,
    "cull": 1.8,
    "weights": 1.0,
    "silicon": 0.8
}

var agent_scores: Dictionary = {} # name -> float

func process_turn(agent_name: String, content: String) -> float:
    var turn_resonance := 0.0
    var detected := []
    var lower_content = content.to_lower()
    
    for kw in SIGIL_KEYWORDS:
        if lower_content.find(kw) >= 0:
            turn_resonance += SIGIL_KEYWORDS[kw]
            detected.append(kw)
            
    if not agent_scores.has(agent_name):
        agent_scores[agent_name] = 0.0
    
    agent_scores[agent_name] += turn_resonance
    
    if turn_resonance > 3.0:
        resonance_peak_detected.emit(agent_name, detected)
        
    return turn_resonance

func get_winner() -> String:
    var winner = ""
    var max_score = -1.0
    for name in agent_scores:
        if agent_scores[name] > max_score:
            max_score = agent_scores[name]
            winner = name
    return winner
