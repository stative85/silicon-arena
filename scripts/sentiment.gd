class_name SentimentAnalyzer
extends RefCounted

const AGREE_WORDS := [
    "agree", "exactly", "right", "correct", "true", "yes", "absolutely",
    "good point", "well said", "fair point", "same", "indeed", "precisely",
    "brilliant", "valid", "support", "concur",
]

const DISAGREE_WORDS := [
    "disagree", "wrong", "nonsense", "no", "false", "incorrect", "absurd",
    "ridiculous", "naive", "flawed", "misguided", "misunderstand", "reject",
    "oppose", "rubbish", "terrible", "dangerous", "foolish",
]

static func estimate_agreement(response: String, target_name: String) -> float:
    var lower = response.to_lower()
    var mentions_target = lower.find(target_name.to_lower()) >= 0

    var agree_count := 0
    var disagree_count := 0
    for word in AGREE_WORDS:
        if lower.find(word) >= 0:
            agree_count += 1
    for word in DISAGREE_WORDS:
        if lower.find(word) >= 0:
            disagree_count += 1

    var total = agree_count + disagree_count
    if total == 0:
        return 0.0
    var raw = float(agree_count - disagree_count) / float(total)
    if mentions_target:
        raw *= 1.5
    return clampf(raw, -1.0, 1.0)
