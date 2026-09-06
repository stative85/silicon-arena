extends RefCounted
class_name AsyncAgentState

## One agent's cognition lifecycle. ONE OUTSTANDING COGNITION PER AGENT.
##
## THE LEAK THIS CLOSES. A fixed release tick equalizes when actions LAND. It
## does not equalize how often an agent gets to THINK. If a fast model may
## begin its next cognition the moment it COMPLETES, it accumulates more
## observations, more submissions and more chances to act while a slower model
## is still finishing -- and model speed is back in the experiment, having
## entered through cadence rather than release.
##
##   observe -> submit -> complete -> WAIT FOR RELEASE -> close -> observe again
##
## The next observation is gated on ENVELOPE CLOSE, never on completion.
##
## Arm 2 SHOULD have speed-dependent cadence: real latency changes when the
## envelope closes, and that is the effect under study. Arm 3 must not. That
## difference is the experiment, which is why the gate is a class with a test
## rather than a line in the runner.

const IDLE := "IDLE"                      ## may observe
const PENDING := "PENDING"                ## cognition outstanding
const AWAITING_RELEASE := "AWAITING_RELEASE"   ## completed, not yet released

var agent_id: String = ""
var model_id: String = ""
var state: String = IDLE

var envelope: AsyncEnvelope = null
var release_tick: int = -1

## Counters the sabotage test reads. If the gate leaks, a faster agent will
## show more observations than a slower one under EQUALIZED.
var observations: int = 0
var submissions: int = 0
var closes: int = 0


static func make(aid: String, mid: String) -> AsyncAgentState:
	var a := AsyncAgentState.new()
	a.agent_id = aid
	a.model_id = mid
	return a


func may_observe() -> bool:
	return state == IDLE


func begin(env: AsyncEnvelope) -> void:
	if state != IDLE:
		push_error("agent %s began a second cognition while %s"
			% [agent_id, state])
		return
	envelope = env
	state = PENDING
	observations += 1
	submissions += 1


## Cognition finished. This does NOT free the agent: it only records when the
## action becomes eligible for release. Freeing here is precisely the leak.
func complete(release_at_tick: int) -> void:
	if state != PENDING:
		return
	release_tick = release_at_tick
	state = AWAITING_RELEASE


func ready_to_release(now_tick: int) -> bool:
	return state == AWAITING_RELEASE and now_tick >= release_tick


## The envelope has been applied. Only now may the agent observe again.
func close() -> void:
	state = IDLE
	envelope = null
	release_tick = -1
	closes += 1
