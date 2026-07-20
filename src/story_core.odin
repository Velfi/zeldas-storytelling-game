package main

import "core:fmt"
import "core:strings"

STORY_PROJECT_VERSION :: "InteractiveStory v1"
STORY_DOMAIN_CORE :: "core"
STORY_MAX_ENUM_VALUES :: 16
STORY_MAX_TAGS :: 16
STORY_MAX_ROLES :: 16
STORY_MAX_CONDITION_CHILDREN :: 16
STORY_MAX_STORYLET_CONDITIONS :: 16
STORY_MAX_STORYLET_EFFECTS :: 16
STORY_MAX_NODE_EFFECTS :: 16
STORY_MAX_NODE_CHOICES :: 16
STORY_MAX_TRACE_ITEMS :: 64
STORY_MAX_CHANGED_IDS :: 64

Story_Value_Kind :: enum {Boolean, Integer, Enumeration, Entity}
Story_Truth :: enum {Undetermined, False, True}
Story_Belief_Stance :: enum {Uncertain, Believes, Disbelieves}
Story_Objective_Status :: enum {Inactive, Active, Completed, Failed}
story_objective_status_text :: proc(status:Story_Objective_Status)->string {switch status {case .Inactive:return "inactive";case .Active:return "active";case .Completed:return "completed";case .Failed:return "failed"};return "inactive"}
story_objective_status_from_text :: proc(text:string)->(Story_Objective_Status,bool) {switch strings.to_lower(strings.trim_space(text)) {case "","inactive":return .Inactive,true;case "active":return .Active,true;case "completed":return .Completed,true;case "failed":return .Failed,true;case:return .Inactive,false}}
Story_Invariant_Kind :: enum {Always, Never, Reachable, Eventually}
Story_Repeat_Policy :: enum {Always, Once, Cooldown}

Story_Spatial_Target_Kind :: enum {Entity, Marker, Room, Interaction, Transition}
Story_Spatial_Status :: enum {Available, Unavailable, Missing}
Story_Spatial_Command_Kind :: enum {Set_Interaction, Set_Visible, Move, Spawn, Despawn, Set_Access}

Story_Spatial_Id :: struct {space_id, target_id:string}
Story_Spatial_Binding :: struct {
	space_id:string,
	target_kind:Story_Spatial_Target_Kind,
	target_id:string,
}

Story_Value :: struct {
	kind:Story_Value_Kind,
	boolean_value:bool,
	integer_value:int,
	text_value:string,
}

Story_Entity :: struct {
	id, kind, display_name, description, appearance_model_asset_ref:string,
	spatial:Story_Spatial_Binding,
	// Volume is the amount of container capacity this entity consumes. A
	// positive capacity makes the entity a container.
	volume, container_capacity:int,
	initially_locked:bool,
	owner_id, initial_container_id:string,
	tags:[STORY_MAX_TAGS]string,
	tag_count:int,
	roles:[STORY_MAX_ROLES]string,
	role_count:int,
}

Story_Role :: struct {id, display_name, description:string, minimum, maximum:int}

Story_Variable :: struct {
	id, display_name, description:string,
	kind:Story_Value_Kind,
	default_value:Story_Value,
	minimum, maximum:int,
	enum_values:[STORY_MAX_ENUM_VALUES]string,
	enum_value_count:int,
}

Story_Fact :: struct {
	id, display_name, proposition, variable_id:string,
	canonical_truth:Story_Truth,
	player_visible:bool,
}

Story_Proposition :: struct {id, text:string, canonical_truth:Story_Truth}
Story_Knowledge :: struct {actor_id, proposition_id:string, stance:Story_Belief_Stance}
Story_Relationship :: struct {id, source_id, target_id, kind:string, variable_id:string}

Story_Communication :: struct {
	sequence:u64,
	sender_id, recipient_id, proposition_id, scene_id, node_id:string,
}

Story_Event :: struct {
	id, subject_id, action, object_id, location_id, fictional_time, provenance:string,
	witnesses:[STORY_MAX_ROLES]string,
	witness_count:int,
}

Story_Objective :: struct {
	id, display_name, description:string,
	hidden:bool,
	initial_status:Story_Objective_Status,
	stage_count:int,
	completion_condition_id, failure_condition_id:string,
	completion_condition, failure_condition:int,
}

Story_Ending :: struct {id, title, summary, condition_id:string, condition_root, priority:int}

Story_Integer_Comparison :: enum {Equal, Not_Equal, Less, Less_Equal, Greater, Greater_Equal}
Story_Condition_Kind :: enum {
	Always, Never, All, Any, Not,
	Value_Equals, Integer_Compare,
	Entity_Has_Tag, Entity_Has_Role,
	Aware, Unaware, Belief_Equals, Communicated,
	Objective_Equals, Event_Occurred,
	Scene_Completed, Storylet_Seen,
	Spatial_Present, Spatial_Contained_By, Spatial_Distance, Spatial_Visible,
	Spatial_Reachable, Spatial_Travel_Time,
}

// Conditions are a flat pre-order forest. Group nodes reference a contiguous
// child range, matching the existing Campaign representation while allowing
// every narrative surface to share one evaluator.
Story_Condition :: struct {
	id:string,
	kind:Story_Condition_Kind,
	first_child, child_count:int,
	child_ids:[STORY_MAX_CONDITION_CHILDREN]string,
	child_id_count:int,
	variable_id, entity_id, other_entity_id, proposition_id, objective_id, event_id, content_id, text_value:string,
	value:Story_Value,
	comparison:Story_Integer_Comparison,
	objective_status:Story_Objective_Status,
	belief_stance:Story_Belief_Stance,
	spatial_a, spatial_b:Story_Spatial_Id,
	distance:f32,
}

Story_Effect_Kind :: enum {
	Set_Value, Add_Integer,
	Make_Aware, Set_Belief, Communicate,
	Set_Objective, Emit_Event,
	Complete_Scene, Mark_Storylet,
	Spatial_Command,
}

Story_Effect :: struct {
	id:string,
	kind:Story_Effect_Kind,
	variable_id, actor_id, other_actor_id, proposition_id, objective_id, event_id, content_id, world_id:string,
	value:Story_Value,
	belief_stance:Story_Belief_Stance,
	objective_status:Story_Objective_Status,
	spatial_command:Story_Spatial_Command_Kind,
	spatial_target, spatial_destination:Story_Spatial_Id,
	world_enabled:bool,
}

Story_Scene :: struct {id, display_name, entry_node, bound_entity, summary, return_to:string}
Story_Localization :: struct {node_id, language, text, status, note, voice:string}
Story_Node_Kind :: enum {Line, Choice, Check, Stage, Interaction, Effect, Selector, Objective, Wait_Event, Subscene, End}
Story_Choice :: struct {id, label, target, condition_id:string}
Story_Node :: struct {
	id, scene_id, line_id, speaker_id, text, next, success, failure, cancel, subscene_id:string,
	ui, camera, actor, actor_mark, animation, summary, ending, domain_ref, event_id:string,
	ui_image_asset_ref, sound_cue_asset_ref, animation_asset_ref:string,
	duration, transition:f32,
	blocking:bool,
	choices:[STORY_MAX_NODE_CHOICES]Story_Choice,
	choice_count:int,
	kind:Story_Node_Kind,
	condition_id:string,
	effect_ids:[STORY_MAX_NODE_EFFECTS]string,
	effect_id_count:int,
	condition_root, first_effect, effect_count:int,
}

Story_Storylet :: struct {
	id, group, scene_id:string,
	condition_roots:[STORY_MAX_STORYLET_CONDITIONS]int,
	condition_ids:[STORY_MAX_STORYLET_CONDITIONS]string,
	condition_count:int,
	effect_indices:[STORY_MAX_STORYLET_EFFECTS]int,
	effect_ids:[STORY_MAX_STORYLET_EFFECTS]string,
	effect_count:int,
	dramatic_priority, specificity, cooldown, authored_order:int,
	repeat_policy:Story_Repeat_Policy,
	fallback:bool,
}

Story_Storylet_Group :: struct {id:string, allow_empty, seeded_random_ties:bool}
Story_Invariant :: struct {id, description, condition_id:string, kind:Story_Invariant_Kind, condition_root:int, required:bool}

Story_Expansion_Distribution :: enum {Reference, Embed}
Story_Expansion_Fallback :: enum {None, Omit}
Story_Expansion_Requirement :: struct {
	id, version:string,
	optional:bool,
	distribution:Story_Expansion_Distribution,
	fallback:Story_Expansion_Fallback,
}
Story_Capability_Requirement :: struct {id, version:string, payload:rawptr}
Resolved_Story_Expansion :: struct {id, namespace, version, content_hash:string, enabled:bool}
Resolved_Story_Environment :: struct {
	expansions:[dynamic]Resolved_Story_Expansion,
	identity:u64,
}

Story_Project :: struct {
	version, id, title, creator, description, content_version, default_space_id, ui_font_asset_ref:string,
	revision:u64,
	expansion_requirements:[dynamic]Story_Expansion_Requirement,
	capabilities:[dynamic]Story_Capability_Requirement,
	resolved_environment:Resolved_Story_Environment,
	entities:[dynamic]Story_Entity,
	roles:[dynamic]Story_Role,
	variables:[dynamic]Story_Variable,
	facts:[dynamic]Story_Fact,
	propositions:[dynamic]Story_Proposition,
	initial_knowledge:[dynamic]Story_Knowledge,
	relationships:[dynamic]Story_Relationship,
	events:[dynamic]Story_Event,
	objectives:[dynamic]Story_Objective,
	conditions:[dynamic]Story_Condition,
	effects:[dynamic]Story_Effect,
	localizations:[dynamic]Story_Localization,
	scenes:[dynamic]Story_Scene,
	nodes:[dynamic]Story_Node,
	storylet_groups:[dynamic]Story_Storylet_Group,
	storylets:[dynamic]Story_Storylet,
	endings:[dynamic]Story_Ending,
	invariants:[dynamic]Story_Invariant,
}

active_story_project:Story_Project
active_compiled_story:Compiled_Story
active_story_runtime:Story_Runtime
active_spatial_registry:Story_Spatial_Registry
active_spatial_service:Story_Spatial_Service

Story_State_Value :: struct {variable_id:string, value:Story_Value}
Story_Objective_State :: struct {objective_id:string, status:Story_Objective_Status, stage:int, activated_sequence,completed_sequence:u64}
Story_Content_History :: struct {id:string, count:int, last_sequence:u64}
Story_World_State :: struct {id:string, enabled:bool}
Story_Container_State :: struct {entity_id, owner_id:string, locked:bool}
Story_Containment_State :: struct {item_id, container_id:string}

Story_State :: struct {
	project_id, content_version:string,
	schema_identity:u64,
	seed, sequence:u64,
	values:[dynamic]Story_State_Value,
	knowledge:[dynamic]Story_Knowledge,
	communications:[dynamic]Story_Communication,
	objectives:[dynamic]Story_Objective_State,
	emitted_events:[dynamic]string,
	completed_scenes:[dynamic]Story_Content_History,
	storylet_history:[dynamic]Story_Content_History,
	world:[dynamic]Story_World_State,
	containers:[dynamic]Story_Container_State,
	containment:[dynamic]Story_Containment_State,
}

Story_Trace_Item :: struct {subject, before, after, explanation:string}
Story_Trace :: struct {items:[STORY_MAX_TRACE_ITEMS]Story_Trace_Item, count:int}
Story_Condition_Trace :: struct {value:bool, explanation:string}
Story_Transaction_Result :: struct {ok:bool, message:string, trace:Story_Trace}

Story_Diagnostic_Severity :: enum {Info, Warning, Error}
Story_Diagnostic :: struct {severity:Story_Diagnostic_Severity, id, message:string}
Story_Validation :: struct {
	ok, proof_complete:bool,
	diagnostics:[dynamic]Story_Diagnostic,
	error_count, warning_count, explored_states:int,
}

story_value_boolean :: proc(value:bool)->Story_Value {return {kind=.Boolean,boolean_value=value}}
story_value_integer :: proc(value:int)->Story_Value {return {kind=.Integer,integer_value=value}}
story_value_text :: proc(kind:Story_Value_Kind,value:string)->Story_Value {return {kind=kind,text_value=value}}

story_value_equal :: proc(a,b:Story_Value)->bool {
	if a.kind!=b.kind do return false
	switch a.kind {case .Boolean:return a.boolean_value==b.boolean_value;case .Integer:return a.integer_value==b.integer_value;case .Enumeration,.Entity:return a.text_value==b.text_value}
	return false
}

story_value_string :: proc(value:Story_Value)->string {
	switch value.kind {case .Boolean:return value.boolean_value?"true":"false";case .Integer:return fmt.tprintf("%d",value.integer_value);case .Enumeration,.Entity:return value.text_value}
	return ""
}

story_entity_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.entities do if item.id==id do return i;return -1}
story_variable_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.variables do if item.id==id do return i;return -1}
story_proposition_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.propositions do if item.id==id do return i;return -1}
story_objective_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.objectives do if item.id==id do return i;return -1}
story_event_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.events do if item.id==id do return i;return -1}
story_condition_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.conditions do if item.id==id do return i;return -1}
story_effect_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.effects do if item.id==id do return i;return -1}
story_scene_index :: proc(project:^Story_Project,id:string)->int {for item,i in project.scenes do if item.id==id do return i;return -1}

story_state_value_index :: proc(state:^Story_State,id:string)->int {for item,i in state.values do if item.variable_id==id do return i;return -1}
story_state_knowledge_index :: proc(state:^Story_State,actor,proposition:string)->int {for item,i in state.knowledge do if item.actor_id==actor&&item.proposition_id==proposition do return i;return -1}
story_state_objective_index :: proc(state:^Story_State,id:string)->int {for item,i in state.objectives do if item.objective_id==id do return i;return -1}
story_tracked_objective_index :: proc(project:^Story_Project,state:^Story_State)->int {
	best:=-1;best_sequence:u64=0
	for objective,project_index in project.objectives {
		if objective.hidden do continue
		state_index:=story_state_objective_index(state,objective.id);if state_index<0||state.objectives[state_index].status!=.Active do continue
		sequence:=state.objectives[state_index].activated_sequence
		if best<0||sequence>best_sequence {best=project_index;best_sequence=sequence}
	}
	return best
}
story_state_history_index :: proc(items:[]Story_Content_History,id:string)->int {for item,i in items do if item.id==id do return i;return -1}

story_value_valid :: proc(variable:^Story_Variable,value:Story_Value)->bool {
	if variable.kind!=value.kind do return false
	switch variable.kind {
	case .Boolean:return true
	case .Integer:return value.integer_value>=variable.minimum&&value.integer_value<=variable.maximum
	case .Enumeration:
		for item in variable.enum_values[:variable.enum_value_count] do if item==value.text_value do return true
		return false
	case .Entity:return value.text_value!=""
	}
	return false
}

story_schema_identity :: proc(project:^Story_Project)->u64 {
	hash:u64=1469598103934665603
	for variable in project.variables {for ch in variable.id {hash=(hash~u64(ch))*1099511628211};hash=(hash~u64(variable.kind))*1099511628211}
	return hash
}

story_state_new :: proc(project:^Story_Project)->Story_State {
	state:=Story_State{project_id=project.id,content_version=project.content_version,schema_identity=story_schema_identity(project),seed=1}
	for variable in project.variables do append(&state.values,Story_State_Value{variable.id,variable.default_value})
	for item in project.initial_knowledge do append(&state.knowledge,item)
	for objective in project.objectives {
		item:=Story_Objective_State{objective_id=objective.id,status=objective.initial_status}
		if item.status==.Active {state.sequence+=1;item.activated_sequence=state.sequence}
		if item.status==.Completed||item.status==.Failed {state.sequence+=1;item.completed_sequence=state.sequence}
		append(&state.objectives,item)
	}
	for entity in project.entities {
		if entity.container_capacity>0 do append(&state.containers,Story_Container_State{entity_id=entity.id,owner_id=entity.owner_id,locked=entity.initially_locked})
		if entity.initial_container_id!="" do append(&state.containment,Story_Containment_State{item_id=entity.id,container_id=entity.initial_container_id})
	}
	return state
}

story_state_clone :: proc(source:^Story_State)->Story_State {
	result:=source^
	result.values=nil;result.knowledge=nil;result.communications=nil;result.objectives=nil;result.emitted_events=nil;result.completed_scenes=nil;result.storylet_history=nil;result.world=nil;result.containers=nil;result.containment=nil
	append(&result.values,..source.values[:]);append(&result.knowledge,..source.knowledge[:]);append(&result.communications,..source.communications[:]);append(&result.objectives,..source.objectives[:]);append(&result.emitted_events,..source.emitted_events[:]);append(&result.completed_scenes,..source.completed_scenes[:]);append(&result.storylet_history,..source.storylet_history[:]);append(&result.world,..source.world[:]);append(&result.containers,..source.containers[:]);append(&result.containment,..source.containment[:])
	return result
}

story_state_destroy :: proc(state:^Story_State) {delete(state.values);delete(state.knowledge);delete(state.communications);delete(state.objectives);delete(state.emitted_events);delete(state.completed_scenes);delete(state.storylet_history);delete(state.world);delete(state.containers);delete(state.containment);state^={}}

story_entity_has_tag :: proc(project:^Story_Project,id,tag:string)->bool {i:=story_entity_index(project,id);if i<0 do return false;for item in project.entities[i].tags[:project.entities[i].tag_count] do if item==tag do return true;return false}
story_entity_has_role :: proc(project:^Story_Project,id,role:string)->bool {i:=story_entity_index(project,id);if i<0 do return false;for item in project.entities[i].roles[:project.entities[i].role_count] do if item==role do return true;return false}

story_condition_eval :: proc(project:^Story_Project,state:^Story_State,index:int,depth:int=0,spatial:^Story_Spatial_Service=nil)->Story_Condition_Trace {
	if index<0||index>=len(project.conditions) do return {false,"condition reference is out of range"}
	if depth>64 do return {false,"condition recursion limit exceeded"}
	c:=project.conditions[index]
	switch c.kind {
	case .Always:return {true,"always"}
	case .Never:return {false,"never"}
	case .All:
		for child_id in c.child_ids[:c.child_id_count] {child:=story_condition_index(project,child_id);r:=story_condition_eval(project,state,child,depth+1,spatial);if !r.value do return {false,fmt.tprintf("all failed: %s",r.explanation)}}
		return {true,"all conditions passed"}
	case .Any:
		for child_id in c.child_ids[:c.child_id_count] {child:=story_condition_index(project,child_id);r:=story_condition_eval(project,state,child,depth+1,spatial);if r.value do return {true,fmt.tprintf("any passed: %s",r.explanation)}}
		return {false,"no alternative passed"}
	case .Not:
		if c.child_id_count!=1 do return {false,"not requires one child"}
		r:=story_condition_eval(project,state,story_condition_index(project,c.child_ids[0]),depth+1,spatial);return {!r.value,fmt.tprintf("not (%s)",r.explanation)}
	case .Value_Equals:
		i:=story_state_value_index(state,c.variable_id);if i<0 do return {false,fmt.tprintf("%s is undefined",c.variable_id)}
		ok:=story_value_equal(state.values[i].value,c.value);return {ok,fmt.tprintf("%s is %s",c.variable_id,story_value_string(state.values[i].value))}
	case .Integer_Compare:
		i:=story_state_value_index(state,c.variable_id);if i<0||state.values[i].value.kind!=.Integer do return {false,fmt.tprintf("%s is not an integer",c.variable_id)}
		a,b:=state.values[i].value.integer_value,c.value.integer_value;ok:=false
		switch c.comparison {case .Equal:ok=a==b;case .Not_Equal:ok=a!=b;case .Less:ok=a<b;case .Less_Equal:ok=a<=b;case .Greater:ok=a>b;case .Greater_Equal:ok=a>=b}
		return {ok,fmt.tprintf("%s is %d",c.variable_id,a)}
	case .Entity_Has_Tag:return {story_entity_has_tag(project,c.entity_id,c.text_value),fmt.tprintf("%s has tag %s",c.entity_id,c.text_value)}
	case .Entity_Has_Role:return {story_entity_has_role(project,c.entity_id,c.text_value),fmt.tprintf("%s has role %s",c.entity_id,c.text_value)}
	case .Aware,.Unaware,.Belief_Equals:
		i:=story_state_knowledge_index(state,c.entity_id,c.proposition_id);aware:=i>=0
		if c.kind==.Aware do return {aware,fmt.tprintf("%s is %saware of %s",c.entity_id,aware?"":"not ",c.proposition_id)}
		if c.kind==.Unaware do return {!aware,fmt.tprintf("%s is %saware of %s",c.entity_id,aware?"":"not ",c.proposition_id)}
		stance:=Story_Belief_Stance.Uncertain;if aware do stance=state.knowledge[i].stance
		ok:=aware&&stance==c.belief_stance;return {ok,fmt.tprintf("%s stance for %s is %v",c.entity_id,c.proposition_id,stance)}
	case .Communicated:
		for item in state.communications do if item.sender_id==c.entity_id&&item.recipient_id==c.other_entity_id&&item.proposition_id==c.proposition_id do return {true,"communication occurred"}
		return {false,"communication has not occurred"}
	case .Objective_Equals:
		i:=story_state_objective_index(state,c.objective_id);ok:=i>=0&&state.objectives[i].status==c.objective_status;return {ok,fmt.tprintf("objective %s status checked",c.objective_id)}
	case .Event_Occurred:
		for id in state.emitted_events do if id==c.event_id do return {true,fmt.tprintf("event %s occurred",c.event_id)}
		return {false,fmt.tprintf("event %s has not occurred",c.event_id)}
	case .Scene_Completed:
		return {story_state_history_index(state.completed_scenes[:],c.content_id)>=0,fmt.tprintf("scene %s completion checked",c.content_id)}
	case .Storylet_Seen:
		return {story_state_history_index(state.storylet_history[:],c.content_id)>=0,fmt.tprintf("storylet %s history checked",c.content_id)}
	case .Spatial_Present,.Spatial_Contained_By,.Spatial_Distance,.Spatial_Visible,.Spatial_Reachable,.Spatial_Travel_Time:
		return story_spatial_condition(spatial,&c)
	}
	return {false,"unsupported condition"}
}

story_trace_add :: proc(trace:^Story_Trace,subject,before,after,explanation:string) {if trace.count>=len(trace.items) do return;trace.items[trace.count]={subject,before,after,explanation};trace.count+=1}

story_history_mark :: proc(items:^[dynamic]Story_Content_History,id:string,sequence:u64) {i:=story_state_history_index(items^[:],id);if i<0 {append(items,Story_Content_History{id=id,count=1,last_sequence=sequence});return};items[i].count+=1;items[i].last_sequence=sequence}

story_effect_apply :: proc(project:^Story_Project,state:^Story_State,effect:Story_Effect,trace:^Story_Trace,spatial:^Story_Spatial_Service=nil)->bool {
	switch effect.kind {
	case .Set_Value,.Add_Integer:
		vi:=story_variable_index(project,effect.variable_id);si:=story_state_value_index(state,effect.variable_id);if vi<0||si<0 do return false
		before:=story_value_string(state.values[si].value);next:=effect.value
		if effect.kind==.Add_Integer {if project.variables[vi].kind!=.Integer do return false;next=story_value_integer(state.values[si].value.integer_value+effect.value.integer_value)}
		if !story_value_valid(&project.variables[vi],next) do return false
		state.values[si].value=next;story_trace_add(trace,effect.variable_id,before,story_value_string(next),"typed value effect");return true
	case .Make_Aware,.Set_Belief:
		if story_entity_index(project,effect.actor_id)<0||story_proposition_index(project,effect.proposition_id)<0 do return false
		i:=story_state_knowledge_index(state,effect.actor_id,effect.proposition_id);before:="unaware"
		if i<0 {append(&state.knowledge,Story_Knowledge{effect.actor_id,effect.proposition_id,.Uncertain});i=len(state.knowledge)-1}else do before=fmt.tprintf("%v",state.knowledge[i].stance)
		if effect.kind==.Set_Belief do state.knowledge[i].stance=effect.belief_stance
		story_trace_add(trace,fmt.tprintf("%s/%s",effect.actor_id,effect.proposition_id),before,fmt.tprintf("%v",state.knowledge[i].stance),"epistemic effect");return true
	case .Communicate:
		if story_entity_index(project,effect.actor_id)<0||story_entity_index(project,effect.other_actor_id)<0||story_proposition_index(project,effect.proposition_id)<0 do return false
		state.sequence+=1;append(&state.communications,Story_Communication{sequence=state.sequence,sender_id=effect.actor_id,recipient_id=effect.other_actor_id,proposition_id=effect.proposition_id,scene_id=effect.content_id})
		i:=story_state_knowledge_index(state,effect.other_actor_id,effect.proposition_id);if i<0 {append(&state.knowledge,Story_Knowledge{effect.other_actor_id,effect.proposition_id,.Uncertain});i=len(state.knowledge)-1};state.knowledge[i].stance=effect.belief_stance
		story_trace_add(trace,effect.proposition_id,"not communicated","communicated",fmt.tprintf("%s told %s",effect.actor_id,effect.other_actor_id));return true
	case .Set_Objective:
		i:=story_state_objective_index(state,effect.objective_id);if i<0 do return false;before_status:=state.objectives[i].status;before:=fmt.tprintf("%v",before_status)
		if before_status!=effect.objective_status {
			state.sequence+=1;state.objectives[i].status=effect.objective_status
			if effect.objective_status==.Active {state.objectives[i].activated_sequence=state.sequence;state.objectives[i].completed_sequence=0}
			if effect.objective_status==.Completed||effect.objective_status==.Failed do state.objectives[i].completed_sequence=state.sequence
		}
		story_trace_add(trace,effect.objective_id,before,fmt.tprintf("%v",effect.objective_status),"objective effect");return true
	case .Emit_Event:
		if story_event_index(project,effect.event_id)<0 do return false;append(&state.emitted_events,effect.event_id);state.sequence+=1;story_trace_add(trace,effect.event_id,"pending","occurred","event emitted");return true
	case .Complete_Scene:state.sequence+=1;story_history_mark(&state.completed_scenes,effect.content_id,state.sequence);story_trace_add(trace,effect.content_id,"incomplete","completed","scene completion");return true
	case .Mark_Storylet:state.sequence+=1;story_history_mark(&state.storylet_history,effect.content_id,state.sequence);story_trace_add(trace,effect.content_id,"unseen","seen","storylet history");return true
	case .Spatial_Command:
		if !story_spatial_stage_effect(spatial,effect) do return false
		story_trace_add(trace,effect.spatial_target.target_id,"world state","staged","typed spatial command");return true
	}
	return false
}

// A transaction is all-or-nothing. Failed effects destroy the working copy and
// leave player state untouched, so UI and MCP callers share identical safety.
story_apply_transaction :: proc(project:^Story_Project,state:^Story_State,effect_indices:[]int,spatial:^Story_Spatial_Service=nil)->Story_Transaction_Result {
	working:=story_state_clone(state);result:=Story_Transaction_Result{}
	spatial_started:=false
	if spatial!=nil&&spatial.begin!=nil {spatial_started=spatial.begin(spatial.userdata);if !spatial_started {story_state_destroy(&working);result.message="spatial transaction could not begin";return result}}
	for index in effect_indices {
		if index<0||index>=len(project.effects)||!story_effect_apply(project,&working,project.effects[index],&result.trace,spatial) {if spatial_started&&spatial.rollback!=nil do spatial.rollback(spatial.userdata);story_state_destroy(&working);result.message=fmt.tprintf("effect %d failed; transaction rolled back",index);return result}
	}
	if spatial_started&&spatial.commit!=nil&&!spatial.commit(spatial.userdata) {if spatial.rollback!=nil do spatial.rollback(spatial.userdata);story_state_destroy(&working);result.message="spatial commit failed; transaction rolled back";return result}
	story_state_destroy(state);state^=working;result.ok=true;result.message=fmt.tprintf("applied %d effects",len(effect_indices));return result
}

Storylet_Candidate :: struct {index, priority, specificity, seen_count, authored_order:int, eligible, selected:bool, explanation:string}
Storylet_Selection :: struct {found:bool, storylet_index:int, candidates:[dynamic]Storylet_Candidate, explanation:string}

storylet_select :: proc(project:^Story_Project,state:^Story_State,group:string)->Storylet_Selection {
	result:=Storylet_Selection{storylet_index=-1};best:Storylet_Candidate;has_best:=false
	for item,index in project.storylets {
		if item.group!=group do continue
		candidate:=Storylet_Candidate{index=index,priority=item.dramatic_priority,specificity=item.specificity,authored_order=item.authored_order,eligible=true}
		history:=story_state_history_index(state.storylet_history[:],item.id);if history>=0 {candidate.seen_count=state.storylet_history[history].count;if item.repeat_policy==.Once {candidate.eligible=false;candidate.explanation="once-only storylet was already seen"};if item.repeat_policy==.Cooldown&&int(state.sequence-state.storylet_history[history].last_sequence)<item.cooldown {candidate.eligible=false;candidate.explanation="storylet cooldown is active"}}
		for condition_i in 0..<item.condition_count {root:=story_condition_index(project,item.condition_ids[condition_i]);check:=story_condition_eval(project,state,root);if !check.value {candidate.eligible=false;candidate.explanation=check.explanation;break}}
		append(&result.candidates,candidate);if !candidate.eligible do continue
		better:=!has_best||candidate.priority>best.priority||candidate.priority==best.priority&&candidate.specificity>best.specificity||candidate.priority==best.priority&&candidate.specificity==best.specificity&&candidate.seen_count<best.seen_count||candidate.priority==best.priority&&candidate.specificity==best.specificity&&candidate.seen_count==best.seen_count&&candidate.authored_order<best.authored_order
		if better {best=candidate;has_best=true}
	}
	if has_best {result.found=true;result.storylet_index=best.index;for &candidate in result.candidates do if candidate.index==best.index do candidate.selected=true;result.explanation=fmt.tprintf("selected %s by priority %d, specificity %d, seen %d, authored order %d",project.storylets[best.index].id,best.priority,best.specificity,best.seen_count,best.authored_order)}else do result.explanation="no eligible storylet"
	return result
}

storylet_selection_destroy :: proc(result:^Storylet_Selection) {delete(result.candidates);result^={}}

story_validation_add :: proc(result:^Story_Validation,severity:Story_Diagnostic_Severity,id,message:string) {append(&result.diagnostics,Story_Diagnostic{severity,id,message});if severity==.Error do result.error_count+=1;else if severity==.Warning do result.warning_count+=1}
story_validation_claim_id :: proc(result:^Story_Validation,ids:^[dynamic]string,id,kind:string) {
	if id=="" {story_validation_add(result,.Error,"",fmt.tprintf("%s requires an ID",kind));return}
	for existing in ids^ do if existing==id {story_validation_add(result,.Error,id,"duplicate stable ID");return}
	append(ids,id)
}

story_project_assign_legacy_ids :: proc(project:^Story_Project) {
	for &condition,i in project.conditions do if condition.id=="" do condition.id=fmt.tprintf("condition_%04d",i)
	for &effect,i in project.effects do if effect.id=="" do effect.id=fmt.tprintf("effect_%04d",i)
	for &condition in project.conditions do if condition.child_id_count==0&&condition.child_count>0&&condition.first_child>=0&&condition.first_child+condition.child_count<=len(project.conditions) {condition.child_id_count=min(condition.child_count,len(condition.child_ids));for i in 0..<condition.child_id_count do condition.child_ids[i]=project.conditions[condition.first_child+i].id}
	for &objective in project.objectives {
		if objective.completion_condition_id==""&&objective.completion_condition>=0&&objective.completion_condition<len(project.conditions) do objective.completion_condition_id=project.conditions[objective.completion_condition].id
		if objective.failure_condition_id==""&&objective.failure_condition>=0&&objective.failure_condition<len(project.conditions) do objective.failure_condition_id=project.conditions[objective.failure_condition].id
	}
	for &node in project.nodes {
		if node.condition_id==""&&node.condition_root>=0&&node.condition_root<len(project.conditions) do node.condition_id=project.conditions[node.condition_root].id
		if node.effect_id_count==0&&node.effect_count>0&&node.first_effect>=0&&node.first_effect+node.effect_count<=len(project.effects) {node.effect_id_count=min(node.effect_count,len(node.effect_ids));for i in 0..<node.effect_id_count do node.effect_ids[i]=project.effects[node.first_effect+i].id}
	}
	for &item in project.storylets {
		for i in 0..<item.condition_count do if item.condition_ids[i]==""&&item.condition_roots[i]>=0&&item.condition_roots[i]<len(project.conditions) do item.condition_ids[i]=project.conditions[item.condition_roots[i]].id
		for i in 0..<item.effect_count do if item.effect_ids[i]==""&&item.effect_indices[i]>=0&&item.effect_indices[i]<len(project.effects) do item.effect_ids[i]=project.effects[item.effect_indices[i]].id
	}
	for &ending in project.endings do if ending.condition_id==""&&ending.condition_root>=0&&ending.condition_root<len(project.conditions) do ending.condition_id=project.conditions[ending.condition_root].id
	for &invariant in project.invariants do if invariant.condition_id==""&&invariant.condition_root>=0&&invariant.condition_root<len(project.conditions) do invariant.condition_id=project.conditions[invariant.condition_root].id
}

story_condition_validate_node :: proc(project:^Story_Project,result:^Story_Validation,index,depth:int) {
	if index<0||index>=len(project.conditions) {story_validation_add(result,.Error,"condition","condition reference is out of range");return}
	if depth>64 {story_validation_add(result,.Error,"condition","condition nesting exceeds 64 levels");return}
	c:=project.conditions[index]
	if c.kind==.All||c.kind==.Any||c.kind==.Not {
		if c.child_id_count<=0 {story_validation_add(result,.Error,c.id,"condition group has no children");return}
		if c.kind==.Not&&c.child_id_count!=1 do story_validation_add(result,.Error,c.id,"not condition requires exactly one child")
		for child_id in c.child_ids[:c.child_id_count] {child:=story_condition_index(project,child_id);if child<0 {story_validation_add(result,.Error,c.id,"condition group references an unknown child");continue};story_condition_validate_node(project,result,child,depth+1)}
	}
	if (c.kind==.Value_Equals||c.kind==.Integer_Compare)&&story_variable_index(project,c.variable_id)<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"condition references an unknown variable")
	if (c.kind==.Entity_Has_Tag||c.kind==.Entity_Has_Role||c.kind==.Aware||c.kind==.Unaware||c.kind==.Belief_Equals)&&story_entity_index(project,c.entity_id)<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"condition references an unknown entity")
	if (c.kind==.Aware||c.kind==.Unaware||c.kind==.Belief_Equals||c.kind==.Communicated)&&story_proposition_index(project,c.proposition_id)<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"condition references an unknown proposition")
	if c.kind==.Communicated&&story_entity_index(project,c.other_entity_id)<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"communication condition references an unknown recipient")
	if c.kind==.Objective_Equals&&story_objective_index(project,c.objective_id)<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"condition references an unknown objective")
	if c.kind==.Event_Occurred&&story_event_index(project,c.event_id)<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"condition references an unknown event")
	if c.kind==.Scene_Completed&&story_scene_index(project,c.content_id)<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"condition references an unknown scene")
	if c.kind>=.Spatial_Present&&c.kind<=.Spatial_Travel_Time {
		if !story_spatial_id_valid(c.spatial_a) do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"spatial condition requires a qualified primary target")
		if c.kind!=.Spatial_Present&&!story_spatial_id_valid(c.spatial_b) do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"spatial condition requires a qualified secondary target")
		if (c.kind==.Spatial_Distance||c.kind==.Spatial_Travel_Time)&&c.distance<0 do story_validation_add(result,.Error,fmt.tprintf("condition_%d",index),"spatial threshold cannot be negative")
	}
}

story_node_index :: proc(project:^Story_Project,scene,id:string)->int {for node,i in project.nodes do if node.scene_id==scene&&node.id==id do return i;return -1}

story_scene_reaches :: proc(project:^Story_Project,source,target:string,visiting:^[128]string,count:^int)->bool {
	if source==target do return true
	for item in visiting[:count^] do if item==source do return false
	if count^>=len(visiting^) do return false
	visiting[count^]=source;count^+=1
	for node in project.nodes do if node.scene_id==source&&node.kind==.Subscene&&node.subscene_id!="" {if story_scene_reaches(project,node.subscene_id,target,visiting,count) {count^-=1;return true}}
	count^-=1;return false
}

story_project_validate :: proc(project:^Story_Project)->Story_Validation {
	story_project_assign_legacy_ids(project)
	result:=Story_Validation{ok=true,proof_complete=true}
	if project.version!=STORY_PROJECT_VERSION do story_validation_add(&result,.Error,project.id,"obsolete or unsupported story format")
	if project.id==""||project.title=="" do story_validation_add(&result,.Error,project.id,"project requires an ID and title")
	story_domain_register_core()
	for capability,i in project.capabilities {
		adapter:=story_domain_find(capability.id,capability.version)
		if capability.id==STORY_DOMAIN_CORE do story_validation_add(&result,.Error,capability.id,"core is always present and must not be declared as a capability")
		if adapter==nil do story_validation_add(&result,.Error,capability.id,"unsupported capability or version")
		for prior in project.capabilities[:i] do if prior.id==capability.id do story_validation_add(&result,.Error,capability.id,"capability is declared more than once")
	}
	for requirement,i in project.expansion_requirements {
		if requirement.id==""||requirement.version=="" do story_validation_add(&result,.Error,requirement.id,"expansion requirement needs an ID and exact version")
		if requirement.optional&&requirement.fallback==.None do story_validation_add(&result,.Error,requirement.id,"optional expansion requires an explicit fallback policy")
		for prior in project.expansion_requirements[:i] do if prior.id==requirement.id do story_validation_add(&result,.Error,requirement.id,"expansion is declared more than once")
	}
	ids:[dynamic]string;defer delete(ids)
	for entity in project.entities do story_validation_claim_id(&result,&ids,entity.id,"entity")
	for role in project.roles do story_validation_claim_id(&result,&ids,role.id,"role")
	for variable,i in project.variables {story_validation_claim_id(&result,&ids,variable.id,"variable");if !story_value_valid(&project.variables[i],variable.default_value) do story_validation_add(&result,.Error,variable.id,"variable default is invalid or out of bounds")}
	for fact in project.facts do story_validation_claim_id(&result,&ids,fact.id,"fact")
	for proposition in project.propositions do story_validation_claim_id(&result,&ids,proposition.id,"proposition")
	for relationship in project.relationships do story_validation_claim_id(&result,&ids,relationship.id,"relationship")
	for event in project.events do story_validation_claim_id(&result,&ids,event.id,"event")
	for objective in project.objectives {
		story_validation_claim_id(&result,&ids,objective.id,"objective")
		if !objective.hidden&&(strings.trim_space(objective.display_name)==""||strings.trim_space(objective.description)=="") do story_validation_add(&result,.Error,objective.id,"player-visible objective requires a title and description")
	}
	if len(project.objectives)>64 do story_validation_add(&result,.Error,project.id,"story exceeds the 64-objective runtime limit")
	for condition in project.conditions do story_validation_claim_id(&result,&ids,condition.id,"condition")
	for effect in project.effects do story_validation_claim_id(&result,&ids,effect.id,"effect")
	for scene in project.scenes do story_validation_claim_id(&result,&ids,scene.id,"scene")
	for node in project.nodes do story_validation_claim_id(&result,&ids,node.id,"node")
	for group in project.storylet_groups do story_validation_claim_id(&result,&ids,group.id,"storylet group")
	for item in project.storylets do story_validation_claim_id(&result,&ids,item.id,"storylet")
	for ending in project.endings do story_validation_claim_id(&result,&ids,ending.id,"ending")
	for invariant in project.invariants do story_validation_claim_id(&result,&ids,invariant.id,"invariant")
	for entity in project.entities {
		if entity.spatial.target_id!=""&&entity.spatial.space_id=="" do story_validation_add(&result,.Error,entity.id,"spatial binding requires a space ID")
		if entity.volume<0||entity.container_capacity<0 do story_validation_add(&result,.Error,entity.id,"volume and container capacity cannot be negative")
		if entity.initially_locked&&entity.container_capacity==0 do story_validation_add(&result,.Error,entity.id,"only a container can be locked")
		if entity.owner_id!=""&&story_entity_index(project,entity.owner_id)<0 do story_validation_add(&result,.Error,entity.id,"container references an unknown owner")
		if entity.owner_id!=""&&entity.container_capacity==0 do story_validation_add(&result,.Error,entity.id,"only a container can be owned")
		if entity.initial_container_id!="" {
			container_i:=story_entity_index(project,entity.initial_container_id)
			if container_i<0||project.entities[container_i].container_capacity<=0 do story_validation_add(&result,.Error,entity.id,"contained_by references an unknown container")
			if entity.volume<=0 do story_validation_add(&result,.Error,entity.id,"a stored entity requires positive volume")
		}
		for role_i in 0..<entity.role_count {
			role:=entity.roles[role_i];found:=false
			for declared in project.roles do if declared.id==role do found=true
			if !found do story_validation_add(&result,.Error,entity.id,fmt.tprintf("entity references unknown role %s",role))
		}
	}
	// Validate authored contents with the same rules used by runtime storage.
	container_state:=story_state_new(project)
	for entity in project.entities do if entity.container_capacity>0 {
		if story_container_used_volume(project,&container_state,entity.id)>entity.container_capacity do story_validation_add(&result,.Error,entity.id,"initial contents exceed container capacity")
		if entity.initial_container_id!=""&&story_container_would_cycle(&container_state,entity.id,entity.initial_container_id) do story_validation_add(&result,.Error,entity.id,"container containment cannot form a cycle")
	}
	story_state_destroy(&container_state)
	for capability in project.capabilities {adapter:=story_domain_find(capability.id,capability.version);if adapter!=nil&&adapter.validate!=nil do adapter.validate(project,&result)}
	for role in project.roles {
		count:=0
		for entity in project.entities do for role_i in 0..<entity.role_count do if entity.roles[role_i]==role.id do count+=1
		if count<role.minimum do story_validation_add(&result,.Error,role.id,"role cardinality is below its minimum")
		if role.maximum>0&&count>role.maximum do story_validation_add(&result,.Error,role.id,"role cardinality exceeds its maximum")
	}
	for fact in project.facts {if fact.proposition!=""&&story_proposition_index(project,fact.proposition)<0 do story_validation_add(&result,.Error,fact.id,"fact references unknown proposition");if fact.variable_id!=""&&story_variable_index(project,fact.variable_id)<0 do story_validation_add(&result,.Error,fact.id,"fact references unknown variable")}
	for item in project.initial_knowledge {if story_entity_index(project,item.actor_id)<0 do story_validation_add(&result,.Error,item.actor_id,"initial knowledge references unknown actor");if story_proposition_index(project,item.proposition_id)<0 do story_validation_add(&result,.Error,item.proposition_id,"initial knowledge references unknown proposition")}
	for relationship in project.relationships {if story_entity_index(project,relationship.source_id)<0||story_entity_index(project,relationship.target_id)<0 do story_validation_add(&result,.Error,relationship.id,"relationship references unknown entity");if story_variable_index(project,relationship.variable_id)<0 do story_validation_add(&result,.Error,relationship.id,"relationship references unknown variable")}
	for event in project.events {
		if event.subject_id!=""&&story_entity_index(project,event.subject_id)<0 do story_validation_add(&result,.Error,event.id,"event references unknown subject")
		if event.object_id!=""&&story_entity_index(project,event.object_id)<0 do story_validation_add(&result,.Error,event.id,"event references unknown object")
		if event.location_id!=""&&story_entity_index(project,event.location_id)<0 do story_validation_add(&result,.Error,event.id,"event references unknown location")
		for witness_i in 0..<event.witness_count do if story_entity_index(project,event.witnesses[witness_i])<0 do story_validation_add(&result,.Error,event.id,"event references unknown witness")
	}
	for condition_index in 0..<len(project.conditions) do story_condition_validate_node(project,&result,condition_index,0)
	for effect,i in project.effects {
		if (effect.kind==.Set_Value||effect.kind==.Add_Integer)&&story_variable_index(project,effect.variable_id)<0 do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"effect references an unknown variable")
		if (effect.kind==.Make_Aware||effect.kind==.Set_Belief||effect.kind==.Communicate)&&story_entity_index(project,effect.actor_id)<0 do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"effect references an unknown actor")
		if effect.kind==.Communicate&&story_entity_index(project,effect.other_actor_id)<0 do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"communication effect references an unknown recipient")
		if (effect.kind==.Make_Aware||effect.kind==.Set_Belief||effect.kind==.Communicate)&&story_proposition_index(project,effect.proposition_id)<0 do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"effect references an unknown proposition")
		if effect.kind==.Set_Objective&&story_objective_index(project,effect.objective_id)<0 do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"effect references an unknown objective")
		if effect.kind==.Emit_Event&&story_event_index(project,effect.event_id)<0 do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"effect references an unknown event")
		if effect.kind==.Spatial_Command&&!story_spatial_id_valid(effect.spatial_target) do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"spatial command requires a qualified target")
		if effect.kind==.Spatial_Command&&effect.spatial_command==.Move&&!story_spatial_id_valid(effect.spatial_destination) do story_validation_add(&result,.Error,fmt.tprintf("effect_%d",i),"move command requires a qualified destination")
	}
	line_ids:[dynamic]string;defer delete(line_ids)
	for scene in project.scenes {if scene.entry_node!=""&&story_node_index(project,scene.id,scene.entry_node)<0 do story_validation_add(&result,.Error,scene.id,"scene entry references an unknown node")}
	for node in project.nodes {
		if story_scene_index(project,node.scene_id)<0 do story_validation_add(&result,.Error,node.id,"node references unknown scene")
		if node.line_id!="" {for line in line_ids do if line==node.line_id do story_validation_add(&result,.Error,node.id,"duplicate stable line ID");append(&line_ids,node.line_id)}
		targets:=[4]string{node.next,node.success,node.failure,node.cancel};for target in targets do if target!=""&&story_node_index(project,node.scene_id,target)<0 do story_validation_add(&result,.Error,node.id,"node edge references an unknown target")
		if node.kind==.Subscene {if story_scene_index(project,node.subscene_id)<0 do story_validation_add(&result,.Error,node.id,"subscene node references unknown scene");visiting:[128]string;count:=0;if story_scene_reaches(project,node.subscene_id,node.scene_id,&visiting,&count) do story_validation_add(&result,.Error,node.id,"recursive subscene call is not allowed")}
		if node.kind==.Choice&&node.choice_count==0&&node.success==""&&node.cancel=="" do story_validation_add(&result,.Error,node.id,"choice node has no authored choices")
		for choice_i in 0..<node.choice_count {choice:=node.choices[choice_i];if choice.id==""||choice.target=="" do story_validation_add(&result,.Error,node.id,"choice requires an ID and target");if story_node_index(project,node.scene_id,choice.target)<0 do story_validation_add(&result,.Error,node.id,"choice references an unknown target");if choice.condition_id!=""&&story_condition_index(project,choice.condition_id)<0 do story_validation_add(&result,.Error,node.id,"choice references an unknown condition");for prior in 0..<choice_i do if node.choices[prior].id==choice.id do story_validation_add(&result,.Error,node.id,"choice IDs must be unique")}
		if node.kind==.Interaction&&node.success==""&&node.next=="" do story_validation_add(&result,.Error,node.id,"interaction node requires a success result")
		if node.kind==.Wait_Event&&node.event_id=="" do story_validation_add(&result,.Error,node.id,"wait-event node requires an event ID")
		if node.condition_id!=""&&story_condition_index(project,node.condition_id)<0 do story_validation_add(&result,.Error,node.id,"node condition is unknown")
		for effect_i in 0..<node.effect_id_count do if story_effect_index(project,node.effect_ids[effect_i])<0 do story_validation_add(&result,.Error,node.id,"node effect is unknown")
	}
	for item,i in project.localizations {
		found:=false;for node in project.nodes do if node.id==item.node_id do found=true;if !found do story_validation_add(&result,.Error,item.node_id,"localization references an unknown node")
		if strings.trim_space(item.language)=="" do story_validation_add(&result,.Error,item.node_id,"localization requires a language")
		for prior in 0..<i do if project.localizations[prior].node_id==item.node_id&&project.localizations[prior].language==item.language do story_validation_add(&result,.Error,item.node_id,"localization language must be unique per node")
	}
	for group in project.storylet_groups {fallback:=false;for item in project.storylets do if item.group==group.id&&item.fallback do fallback=true;if !fallback&&!group.allow_empty do story_validation_add(&result,.Error,group.id,"storylet group requires a fallback or allow-empty policy")}
	for item in project.storylets {found:=false;for group in project.storylet_groups do if group.id==item.group do found=true;if !found do story_validation_add(&result,.Error,item.id,"storylet references unknown group");if story_scene_index(project,item.scene_id)<0 do story_validation_add(&result,.Error,item.id,"storylet references unknown scene");for condition_i in 0..<item.condition_count do if story_condition_index(project,item.condition_ids[condition_i])<0 do story_validation_add(&result,.Error,item.id,"storylet condition is unknown");for effect_i in 0..<item.effect_count do if story_effect_index(project,item.effect_ids[effect_i])<0 do story_validation_add(&result,.Error,item.id,"storylet effect is unknown")}
	for ending in project.endings do if story_condition_index(project,ending.condition_id)<0 do story_validation_add(&result,.Error,ending.id,"ending condition is unknown")
	for invariant in project.invariants do if story_condition_index(project,invariant.condition_id)<0 do story_validation_add(&result,.Error,invariant.id,"invariant condition is unknown")
	result.ok=result.error_count==0;return result
}

story_validation_destroy :: proc(result:^Story_Validation) {delete(result.diagnostics);result^={}}

Story_Record_Kind :: enum {Entity, Role, Variable, Fact, Proposition, Knowledge, Relationship, Event, Objective, Scene, Node, Storylet_Group, Storylet, Ending, Invariant}
Story_Command_Kind :: enum {Add_Record, Update_Record, Delete_By_Id, Add_Entity, Add_Variable, Add_Proposition, Add_Scene, Add_Storylet}
Story_Command :: struct {
	kind:Story_Command_Kind,
	record_kind:Story_Record_Kind,
	entity:Story_Entity,role:Story_Role,variable:Story_Variable,fact:Story_Fact,proposition:Story_Proposition,knowledge:Story_Knowledge,
	relationship:Story_Relationship,event:Story_Event,objective:Story_Objective,scene:Story_Scene,node:Story_Node,
	storylet_group:Story_Storylet_Group,storylet:Story_Storylet,ending:Story_Ending,invariant:Story_Invariant,
	id:string,
}
Story_Command_Batch_Result :: struct {ok,stale:bool,revision:u64,message,impact_summary:string,changed_ids:[STORY_MAX_CHANGED_IDS]string,changed_count:int,validation:Story_Validation}

story_project_clone :: proc(source:^Story_Project)->Story_Project {
	result:=source^
	result.expansion_requirements=nil;append(&result.expansion_requirements,..source.expansion_requirements[:])
	result.capabilities=nil;for capability in source.capabilities {copy:=capability;copy.payload=nil;adapter:=story_domain_find(capability.id,capability.version);if capability.payload!=nil&&adapter!=nil&&adapter.clone!=nil do copy.payload=adapter.clone(capability.payload);append(&result.capabilities,copy)}
	result.resolved_environment.expansions=nil;append(&result.resolved_environment.expansions,..source.resolved_environment.expansions[:])
	result.entities=nil;result.roles=nil;result.variables=nil;result.facts=nil;result.propositions=nil;result.initial_knowledge=nil;result.relationships=nil;result.events=nil;result.objectives=nil;result.conditions=nil;result.effects=nil;result.localizations=nil;result.scenes=nil;result.nodes=nil;result.storylet_groups=nil;result.storylets=nil;result.endings=nil;result.invariants=nil
	append(&result.entities,..source.entities[:]);append(&result.roles,..source.roles[:]);append(&result.variables,..source.variables[:]);append(&result.facts,..source.facts[:]);append(&result.propositions,..source.propositions[:]);append(&result.initial_knowledge,..source.initial_knowledge[:]);append(&result.relationships,..source.relationships[:]);append(&result.events,..source.events[:]);append(&result.objectives,..source.objectives[:]);append(&result.conditions,..source.conditions[:]);append(&result.effects,..source.effects[:]);append(&result.localizations,..source.localizations[:]);append(&result.scenes,..source.scenes[:]);append(&result.nodes,..source.nodes[:]);append(&result.storylet_groups,..source.storylet_groups[:]);append(&result.storylets,..source.storylets[:]);append(&result.endings,..source.endings[:]);append(&result.invariants,..source.invariants[:]);return result
}

story_project_destroy :: proc(project:^Story_Project) {for capability in project.capabilities {adapter:=story_domain_find(capability.id,capability.version);if capability.payload!=nil&&adapter!=nil&&adapter.destroy!=nil do adapter.destroy(capability.payload)};delete(project.expansion_requirements);delete(project.capabilities);delete(project.resolved_environment.expansions);delete(project.entities);delete(project.roles);delete(project.variables);delete(project.facts);delete(project.propositions);delete(project.initial_knowledge);delete(project.relationships);delete(project.events);delete(project.objectives);delete(project.conditions);delete(project.effects);delete(project.localizations);delete(project.scenes);delete(project.nodes);delete(project.storylet_groups);delete(project.storylets);delete(project.endings);delete(project.invariants);project^={}}

story_command_record_id :: proc(command:^Story_Command)->string {switch command.record_kind {case .Entity:return command.entity.id;case .Role:return command.role.id;case .Variable:return command.variable.id;case .Fact:return command.fact.id;case .Proposition:return command.proposition.id;case .Knowledge:return fmt.tprintf("%s/%s",command.knowledge.actor_id,command.knowledge.proposition_id);case .Relationship:return command.relationship.id;case .Event:return command.event.id;case .Objective:return command.objective.id;case .Scene:return command.scene.id;case .Node:return command.node.id;case .Storylet_Group:return command.storylet_group.id;case .Storylet:return command.storylet.id;case .Ending:return command.ending.id;case .Invariant:return command.invariant.id};return ""}
story_command_id :: proc(command:^Story_Command)->string {switch command.kind {case .Add_Entity:return command.entity.id;case .Add_Variable:return command.variable.id;case .Add_Proposition:return command.proposition.id;case .Add_Scene:return command.scene.id;case .Add_Storylet:return command.storylet.id;case .Add_Record,.Update_Record:return story_command_record_id(command);case .Delete_By_Id:return command.id};return ""}

story_apply_record :: proc(project:^Story_Project,command:^Story_Command,update:bool)->bool {
	switch command.record_kind {
	case .Entity:for &item in project.entities do if item.id==command.entity.id {if !update do return false;item=command.entity;return true};if update do return false;append(&project.entities,command.entity)
	case .Role:for &item in project.roles do if item.id==command.role.id {if !update do return false;item=command.role;return true};if update do return false;append(&project.roles,command.role)
	case .Variable:for &item in project.variables do if item.id==command.variable.id {if !update do return false;item=command.variable;return true};if update do return false;append(&project.variables,command.variable)
	case .Fact:for &item in project.facts do if item.id==command.fact.id {if !update do return false;item=command.fact;return true};if update do return false;append(&project.facts,command.fact)
	case .Proposition:for &item in project.propositions do if item.id==command.proposition.id {if !update do return false;item=command.proposition;return true};if update do return false;append(&project.propositions,command.proposition)
	case .Knowledge:for &item in project.initial_knowledge do if item.actor_id==command.knowledge.actor_id&&item.proposition_id==command.knowledge.proposition_id {if !update do return false;item=command.knowledge;return true};if update do return false;append(&project.initial_knowledge,command.knowledge)
	case .Relationship:for &item in project.relationships do if item.id==command.relationship.id {if !update do return false;item=command.relationship;return true};if update do return false;append(&project.relationships,command.relationship)
	case .Event:for &item in project.events do if item.id==command.event.id {if !update do return false;item=command.event;return true};if update do return false;append(&project.events,command.event)
	case .Objective:for &item in project.objectives do if item.id==command.objective.id {if !update do return false;item=command.objective;return true};if update do return false;append(&project.objectives,command.objective)
	case .Scene:for &item in project.scenes do if item.id==command.scene.id {if !update do return false;item=command.scene;return true};if update do return false;append(&project.scenes,command.scene)
	case .Node:for &item in project.nodes do if item.id==command.node.id {if !update do return false;item=command.node;return true};if update do return false;append(&project.nodes,command.node)
	case .Storylet_Group:for &item in project.storylet_groups do if item.id==command.storylet_group.id {if !update do return false;item=command.storylet_group;return true};if update do return false;append(&project.storylet_groups,command.storylet_group)
	case .Storylet:for &item in project.storylets do if item.id==command.storylet.id {if !update do return false;item=command.storylet;return true};if update do return false;append(&project.storylets,command.storylet)
	case .Ending:for &item in project.endings do if item.id==command.ending.id {if !update do return false;item=command.ending;return true};if update do return false;append(&project.endings,command.ending)
	case .Invariant:for &item in project.invariants do if item.id==command.invariant.id {if !update do return false;item=command.invariant;return true};if update do return false;append(&project.invariants,command.invariant)
	}
	return true
}

story_apply_command_raw :: proc(project:^Story_Project,command:^Story_Command)->bool {
	switch command.kind {
	case .Add_Record:return story_apply_record(project,command,false)
	case .Update_Record:return story_apply_record(project,command,true)
	case .Add_Entity:append(&project.entities,command.entity);return true
	case .Add_Variable:append(&project.variables,command.variable);return true
	case .Add_Proposition:append(&project.propositions,command.proposition);return true
	case .Add_Scene:append(&project.scenes,command.scene);return true
	case .Add_Storylet:append(&project.storylets,command.storylet);return true
	case .Delete_By_Id:
		for item,i in project.entities do if item.id==command.id {ordered_remove(&project.entities,i);return true}
		for item,i in project.variables do if item.id==command.id {ordered_remove(&project.variables,i);return true}
		for item,i in project.propositions do if item.id==command.id {ordered_remove(&project.propositions,i);return true}
		for item,i in project.scenes do if item.id==command.id {ordered_remove(&project.scenes,i);return true}
		for item,i in project.storylets do if item.id==command.id {ordered_remove(&project.storylets,i);return true}
		for item,i in project.roles do if item.id==command.id {ordered_remove(&project.roles,i);return true}
		for item,i in project.facts do if item.id==command.id {ordered_remove(&project.facts,i);return true}
		for item,i in project.relationships do if item.id==command.id {ordered_remove(&project.relationships,i);return true}
		for item,i in project.events do if item.id==command.id {ordered_remove(&project.events,i);return true}
		for item,i in project.objectives do if item.id==command.id {ordered_remove(&project.objectives,i);return true}
		for item,i in project.nodes do if item.id==command.id {ordered_remove(&project.nodes,i);return true}
		for item,i in project.storylet_groups do if item.id==command.id {ordered_remove(&project.storylet_groups,i);return true}
		for item,i in project.endings do if item.id==command.id {ordered_remove(&project.endings,i);return true}
		for item,i in project.invariants do if item.id==command.id {ordered_remove(&project.invariants,i);return true}
	}
	return false
}

// This is the parity boundary for UI and MCP authors. Both must provide the
// revision they inspected and both receive identical validation diagnostics.
story_command_batch :: proc(project:^Story_Project,expected_revision:u64,commands:[]Story_Command,dry_run:bool=false)->Story_Command_Batch_Result {
	result:=Story_Command_Batch_Result{revision=project.revision};if expected_revision!=project.revision {result.stale=true;result.message=fmt.tprintf("stale revision: expected %d, current %d",expected_revision,project.revision);return result}
	working:=story_project_clone(project)
	for &command in commands {if !story_apply_command_raw(&working,&command) {story_project_destroy(&working);result.message="command batch rejected without changes";return result};if result.changed_count<len(result.changed_ids) {result.changed_ids[result.changed_count]=story_command_id(&command);result.changed_count+=1}}
	working.revision+=1;result.validation=story_project_validate(&working);if !result.validation.ok {story_project_destroy(&working);result.message="command batch failed validation";return result}
	result.ok=true;result.revision=working.revision;result.message=dry_run?"dry run valid":"command batch committed";result.impact_summary=fmt.tprintf("%d record%s changed; validation has %d warning%s",result.changed_count,result.changed_count==1?"":"s",result.validation.warning_count,result.validation.warning_count==1?"":"s")
	if dry_run {story_project_destroy(&working);return result}
	story_project_destroy(project);project^=working;return result
}

story_command_result_destroy :: proc(result:^Story_Command_Batch_Result) {story_validation_destroy(&result.validation);result^={}}
