package main

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

Story_Value_Kind :: enum {
	Boolean,
	Integer,
	Enumeration,
	Entity,
}
Story_Truth :: enum {
	Undetermined,
	False,
	True,
}
Story_Belief_Stance :: enum {
	Uncertain,
	Believes,
	Disbelieves,
}
Story_Objective_Status :: enum {
	Inactive,
	Active,
	Completed,
	Failed,
}
story_objective_status_text :: proc(status: Story_Objective_Status) -> string {switch
	status {case .Inactive:
		return "inactive"; case .Active:
		return "active"; case .Completed:
		return "completed"; case .Failed:
		return "failed"}
	return "inactive"}
story_objective_status_from_text :: proc(text: string) -> (Story_Objective_Status, bool) {switch
	strings.to_lower(strings.trim_space(text)) {case "", "inactive":
		return .Inactive, true; case "active":
		return .Active, true; case "completed":
		return .Completed, true; case "failed":
		return .Failed, true; case:
		return .Inactive, false}}
Story_Invariant_Kind :: enum {
	Always,
	Never,
	Reachable,
	Eventually,
}
Story_Repeat_Policy :: enum {
	Always,
	Once,
	Cooldown,
}

Story_Spatial_Target_Kind :: enum {
	Entity,
	Marker,
	Room,
	Interaction,
	Transition,
}
Story_Spatial_Status :: enum {
	Available,
	Unavailable,
	Missing,
}
Story_Spatial_Command_Kind :: enum {
	Set_Interaction,
	Set_Visible,
	Move,
	Spawn,
	Despawn,
	Set_Access,
}

Story_Spatial_Id :: struct {
	space_id, target_id: string,
}
Story_Spatial_Binding :: struct {
	space_id:    string,
	target_kind: Story_Spatial_Target_Kind,
	target_id:   string,
}

Story_Value :: struct {
	kind:          Story_Value_Kind,
	boolean_value: bool,
	integer_value: int,
	text_value:    string,
}

Story_Entity :: struct {
	id, kind, display_name, description, appearance_model_asset_ref:                 string,
	// Runtime presentation and interaction are authored beside the stable entity
	// identity so projecting the same story under a renamed ID needs no code edit.
	default_animation:                                                               string,
	animation_phase:                                                                 f32,
	presentation_tint:                                                               [4]u8,
	presentation_facing:                                                             f32,
	visibility_condition_id, availability_condition_id, completion_condition_id:     string,
	interaction_scene_id, interaction_prompt, unavailable_prompt, completion_prompt: string,
	spatial:                                                                         Story_Spatial_Binding,
	// Volume is the amount of container capacity this entity consumes. A
	// positive capacity makes the entity a container.
	volume, container_capacity:                                                      int,
	initially_locked:                                                                bool,
	owner_id, initial_container_id:                                                  string,
	tags:                                                                            [STORY_MAX_TAGS]string,
	tag_count:                                                                       int,
	roles:                                                                           [STORY_MAX_ROLES]string,
	role_count:                                                                      int,
}

Story_Role :: struct {
	id, display_name, description: string,
	minimum, maximum:              int,
}

Story_Variable :: struct {
	id, display_name, description: string,
	kind:                          Story_Value_Kind,
	default_value:                 Story_Value,
	minimum, maximum:              int,
	enum_values:                   [STORY_MAX_ENUM_VALUES]string,
	enum_value_count:              int,
}

Story_Fact :: struct {
	id, display_name, proposition, variable_id: string,
	canonical_truth:                            Story_Truth,
	player_visible:                             bool,
}

Story_Proposition :: struct {
	id, text:        string,
	canonical_truth: Story_Truth,
}
Story_Knowledge :: struct {
	actor_id, proposition_id: string,
	stance:                   Story_Belief_Stance,
}
Story_Relationship :: struct {
	id, source_id, target_id, kind: string,
	variable_id:                    string,
}

Story_Communication :: struct {
	sequence:                                                   u64,
	sender_id, recipient_id, proposition_id, scene_id, node_id: string,
}

Story_Event :: struct {
	id, subject_id, action, object_id, location_id, fictional_time, provenance: string,
	witnesses:                                                                  [STORY_MAX_ROLES]string,
	witness_count:                                                              int,
}

Story_Objective :: struct {
	id, display_name, description:                 string,
	hidden:                                        bool,
	initial_status:                                Story_Objective_Status,
	stage_count:                                   int,
	completion_condition_id, failure_condition_id: string,
	completion_condition, failure_condition:       int,
}

Story_Ending :: struct {
	id, title, summary, condition_id: string,
	condition_root, priority:         int,
}

Story_Integer_Comparison :: enum {
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
}
Story_Condition_Kind :: enum {
	Always,
	Never,
	All,
	Any,
	Not,
	Value_Equals,
	Integer_Compare,
	Entity_Has_Tag,
	Entity_Has_Role,
	Aware,
	Unaware,
	Belief_Equals,
	Communicated,
	Objective_Equals,
	Event_Occurred,
	Scene_Completed,
	Storylet_Seen,
	Spatial_Present,
	Spatial_Contained_By,
	Spatial_Distance,
	Spatial_Visible,
	Spatial_Reachable,
	Spatial_Travel_Time,
	Capability_State,
}

// Conditions are a flat pre-order forest. Group nodes reference a contiguous
// child range, matching the existing Campaign representation while allowing
// every narrative surface to share one evaluator.
Story_Condition :: struct {
	id:                                                                                                      string,
	kind:                                                                                                    Story_Condition_Kind,
	first_child,
	child_count:                                                                                int,
	child_ids:                                                                                               [STORY_MAX_CONDITION_CHILDREN]string,
	child_id_count:                                                                                          int,
	variable_id,
	entity_id,
	other_entity_id,
	proposition_id,
	objective_id,
	event_id,
	content_id,
	text_value: string,
	value:                                                                                                   Story_Value,
	comparison:                                                                                              Story_Integer_Comparison,
	objective_status:                                                                                        Story_Objective_Status,
	belief_stance:                                                                                           Story_Belief_Stance,
	spatial_a,
	spatial_b:                                                                                    Story_Spatial_Id,
	distance:                                                                                                f32,
}

Story_Effect_Kind :: enum {
	Set_Value,
	Add_Integer,
	Make_Aware,
	Set_Belief,
	Communicate,
	Set_Objective,
	Emit_Event,
	Complete_Scene,
	Mark_Storylet,
	Spatial_Command,
}

Story_Effect :: struct {
	id:                                                                                                  string,
	kind:                                                                                                Story_Effect_Kind,
	variable_id,
	actor_id,
	other_actor_id,
	proposition_id,
	objective_id,
	event_id,
	content_id,
	world_id: string,
	value:                                                                                               Story_Value,
	belief_stance:                                                                                       Story_Belief_Stance,
	objective_status:                                                                                    Story_Objective_Status,
	spatial_command:                                                                                     Story_Spatial_Command_Kind,
	spatial_target,
	spatial_destination:                                                                 Story_Spatial_Id,
	world_enabled:                                                                                       bool,
}

Story_Scene :: struct {
	id, display_name, entry_node, bound_entity, summary, return_to: string,
}
Story_Localization :: struct {
	node_id, language, text, status, note, voice: string,
}
Story_Node_Kind :: enum {
	Line,
	Choice,
	Check,
	Stage,
	Interaction,
	Effect,
	Selector,
	Objective,
	Wait_Event,
	Subscene,
	End,
}
Story_Choice :: struct {
	id, label, target, condition_id: string,
}
Story_Node :: struct {
	id, scene_id, line_id, speaker_id, text, next, success, failure, cancel, subscene_id: string,
	ui, camera, actor, actor_mark, animation, summary, ending, domain_ref, event_id:      string,
	ui_image_asset_ref, sound_cue_asset_ref, animation_asset_ref:                         string,
	duration, transition:                                                                 f32,
	blocking:                                                                             bool,
	choices:                                                                              [STORY_MAX_NODE_CHOICES]Story_Choice,
	choice_count:                                                                         int,
	kind:                                                                                 Story_Node_Kind,
	condition_id:                                                                         string,
	effect_ids:                                                                           [STORY_MAX_NODE_EFFECTS]string,
	effect_id_count:                                                                      int,
	condition_root, first_effect, effect_count:                                           int,
}

Story_Storylet :: struct {
	id, group, scene_id:                                      string,
	condition_roots:                                          [STORY_MAX_STORYLET_CONDITIONS]int,
	condition_ids:                                            [STORY_MAX_STORYLET_CONDITIONS]string,
	condition_count:                                          int,
	effect_indices:                                           [STORY_MAX_STORYLET_EFFECTS]int,
	effect_ids:                                               [STORY_MAX_STORYLET_EFFECTS]string,
	effect_count:                                             int,
	dramatic_priority, specificity, cooldown, authored_order: int,
	repeat_policy:                                            Story_Repeat_Policy,
	fallback:                                                 bool,
}

Story_Storylet_Group :: struct {
	id:                              string,
	allow_empty, seeded_random_ties: bool,
}
Story_Invariant :: struct {
	id, description, condition_id: string,
	kind:                          Story_Invariant_Kind,
	condition_root:                int,
	required:                      bool,
}

Story_Expansion_Distribution :: enum {
	Reference,
	Embed,
}
Story_Expansion_Fallback :: enum {
	None,
	Omit,
}
Story_Expansion_Requirement :: struct {
	id, version:  string,
	optional:     bool,
	distribution: Story_Expansion_Distribution,
	fallback:     Story_Expansion_Fallback,
}
Story_Capability_Requirement :: struct {
	id, version: string,
	payload:     rawptr,
}
Resolved_Story_Expansion :: struct {
	id, namespace, version, content_hash: string,
	enabled:                              bool,
}
Resolved_Story_Environment :: struct {
	expansions: [dynamic]Resolved_Story_Expansion,
	identity:   u64,
}

Story_Project :: struct {
	version,
	id,
	title,
	creator,
	description,
	content_version,
	default_space_id,
	ui_font_asset_ref: string,
	revision:                                                                                       u64,
	expansion_requirements:                                                                         [dynamic]Story_Expansion_Requirement,
	capabilities:                                                                                   [dynamic]Story_Capability_Requirement,
	resolved_environment:                                                                           Resolved_Story_Environment,
	entities:                                                                                       [dynamic]Story_Entity,
	roles:                                                                                          [dynamic]Story_Role,
	variables:                                                                                      [dynamic]Story_Variable,
	facts:                                                                                          [dynamic]Story_Fact,
	propositions:                                                                                   [dynamic]Story_Proposition,
	initial_knowledge:                                                                              [dynamic]Story_Knowledge,
	relationships:                                                                                  [dynamic]Story_Relationship,
	events:                                                                                         [dynamic]Story_Event,
	objectives:                                                                                     [dynamic]Story_Objective,
	conditions:                                                                                     [dynamic]Story_Condition,
	effects:                                                                                        [dynamic]Story_Effect,
	localizations:                                                                                  [dynamic]Story_Localization,
	scenes:                                                                                         [dynamic]Story_Scene,
	nodes:                                                                                          [dynamic]Story_Node,
	storylet_groups:                                                                                [dynamic]Story_Storylet_Group,
	storylets:                                                                                      [dynamic]Story_Storylet,
	endings:                                                                                        [dynamic]Story_Ending,
	invariants:                                                                                     [dynamic]Story_Invariant,
}

active_story_project: Story_Project
active_compiled_story: Compiled_Story
active_story_runtime: Story_Runtime
active_spatial_registry: Story_Spatial_Registry
active_spatial_service: Story_Spatial_Service

Story_State_Value :: struct {
	variable_id: string,
	value:       Story_Value,
}
Story_Objective_State :: struct {
	objective_id:                           string,
	status:                                 Story_Objective_Status,
	stage:                                  int,
	activated_sequence, completed_sequence: u64,
}
Story_Content_History :: struct {
	id:            string,
	count:         int,
	last_sequence: u64,
}
Story_World_State :: struct {
	id:      string,
	enabled: bool,
}
Story_Container_State :: struct {
	entity_id, owner_id: string,
	locked:              bool,
}
Story_Containment_State :: struct {
	item_id, container_id: string,
}

Story_State :: struct {
	project_id, content_version: string,
	schema_identity:             u64,
	seed, sequence:              u64,
	values:                      [dynamic]Story_State_Value,
	knowledge:                   [dynamic]Story_Knowledge,
	communications:              [dynamic]Story_Communication,
	objectives:                  [dynamic]Story_Objective_State,
	emitted_events:              [dynamic]string,
	completed_scenes:            [dynamic]Story_Content_History,
	storylet_history:            [dynamic]Story_Content_History,
	world:                       [dynamic]Story_World_State,
	containers:                  [dynamic]Story_Container_State,
	containment:                 [dynamic]Story_Containment_State,
}

Story_Trace_Item :: struct {
	subject, before, after, explanation: string,
}
Story_Trace :: struct {
	items: [STORY_MAX_TRACE_ITEMS]Story_Trace_Item,
	count: int,
}
Story_Condition_Trace :: struct {
	value:       bool,
	explanation: string,
}
Story_Transaction_Result :: struct {
	ok:      bool,
	message: string,
	trace:   Story_Trace,
}

Story_Diagnostic_Severity :: enum {
	Info,
	Warning,
	Error,
}
Story_Diagnostic :: struct {
	severity:    Story_Diagnostic_Severity,
	id, message: string,
}
Story_Validation :: struct {
	ok, proof_complete:                          bool,
	diagnostics:                                 [dynamic]Story_Diagnostic,
	error_count, warning_count, explored_states: int,
}
