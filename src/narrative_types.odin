package main

// Small host-facing value types shared by campaign, presentation, and the
// MysteryDomain adapter. They deliberately contain no legacy case records.
Validation :: struct {ok:bool, message:string}

Outcome :: enum {
	Airtight,
	Correct_But_Unproven,
	Plausible_Incomplete,
	Wrong_Accusation,
	Unresolved,
}

Check_Result :: struct {
	target, die_a, die_b, modifier, total:int,
	success:bool,
}

Theory :: struct {
	murder, alibi, cover_up, proof:bool,
	// The investigation UI still stores the selected suspect and its three
	// supported proof pillars here while the domain-state migration is underway.
	accused:string,
	pillars:[3]string,
}

Theory_Diagnostics :: struct {complete:bool}

Workbench_Event :: struct {
	time:int,
	actor, action, prop, room:string,
	pinned_observation:int,
}

Reconstruction_Result :: struct {
	physically_possible, decisive_contradiction:bool,
	first_failed_event:int,
	message:string,
}

simulate_workbench :: proc(events:[]Workbench_Event,supported:[]bool)->Reconstruction_Result {
	result:=Reconstruction_Result{physically_possible=true,first_failed_event=-1,message="Every beat can occupy the time and place assigned to it. The chain holds."}
	previous:=-1
	for event,i in events {
		failure:=""
		if event.time<previous {result.physically_possible=false;failure="Time runs backward at the highlighted beat. Put the evening in an order the house could live through."}
		else if event.actor=="someone" {result.physically_possible=false;failure="The highlighted beat has no actor. A sequence cannot act for itself."}
		else if event.prop=="unknown object" {result.physically_possible=false;failure="An unnamed object cannot carry the highlighted action. Identify what was used."}
		else if event.room=="unknown place" {result.physically_possible=false;failure="The highlighted beat has nowhere to occur. Give it a room before trusting the account."}
		if failure!=""&&result.first_failed_event<0 {result.first_failed_event=i;result.message=failure}
		if i<len(supported)&&!supported[i]&&result.first_failed_event<0 {result.first_failed_event=i;result.message="The sequence is possible, but the highlighted beat exists only in theory. Attach evidence before trusting it."}
		if event.action=="open_shutter"||event.action=="close_shutter" do result.decisive_contradiction=true
		previous=event.time
	}
	return result
}

story_node_kind_valid :: proc(kind:string)->bool {switch kind {case "line","choice","check","stage","interaction","effect","selector","objective","wait_event","subscene","end":return true};return false}
skill_index :: proc(skill:string)->int {switch skill {case "Observation":return 2;case "Analysis","Empathy":return 1;case "Pressure":return 0};return 0}
check_target :: proc(difficulty:int)->int {return 6+clamp(difficulty,0,4)*2}
check_modifier :: proc(skill,evidence,disposition,situational:int)->int {return skill+evidence+disposition+situational}
check_success_percent :: proc(target,modifier:int)->int {successes:=0;for a in 1..=6 do for b in 1..=6 do if a+b+modifier>=target do successes+=1;return (successes*100+18)/36}
skill_check :: proc(seed:^u64,skill,difficulty,evidence,disposition,situational:int)->Check_Result {seed^~=seed^<<13;seed^~=seed^>>7;seed^~=seed^<<17;die_a:=int(seed^%6)+1;seed^~=seed^<<13;seed^~=seed^>>7;seed^~=seed^<<17;die_b:=int(seed^%6)+1;modifier:=check_modifier(skill,evidence,disposition,situational);target:=check_target(difficulty);total:=die_a+die_b+modifier;return {target=target,die_a=die_a,die_b=die_b,modifier=modifier,total=total,success=total>=target}}
clock_minutes :: proc(value:string)->int {if len(value)<4 do return -1;colon:=-1;for c,i in value do if c==':' {colon=i;break};if colon<=0||colon>=len(value)-1 do return -1;hour,minute:=0,0;for c in value[:colon] {if c<'0'||c>'9' do return -1;hour=hour*10+int(c-'0')};for c in value[colon+1:] {if c<'0'||c>'9' do return -1;minute=minute*10+int(c-'0')};if minute>=60 do return -1;return hour*60+minute}
