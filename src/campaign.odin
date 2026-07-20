package main

CAMPAIGN_MAX_CASES :: 16
CAMPAIGN_MAX_VARIABLES :: 64
CAMPAIGN_MAX_ENUM_VALUES :: 16
CAMPAIGN_MAX_CONDITIONS :: 256
CAMPAIGN_MAX_EFFECTS :: 256
CAMPAIGN_RECALCULATE_LIMIT :: CAMPAIGN_MAX_CASES + 1
CAMPAIGN_MAX_PLAYTHROUGHS :: 32
CAMPAIGN_MAX_CATALOG :: 16
CAMPAIGN_HISTORY_LIMIT :: 32

Campaign_Value_Kind :: enum {
	Boolean,
	Integer,
	Enumeration,
}
Campaign_Condition_Kind :: enum {
	Always,
	Never,
	All,
	Any,
	Not,
	Boolean_Equals,
	Integer_Compare,
	Enum_Equals,
	Case_Started,
	Case_Completed,
	Case_Outcome,
}
Campaign_Integer_Comparison :: enum {
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
}
Campaign_Effect_Kind :: enum {
	Set_Boolean,
	Set_Integer,
	Add_Integer,
	Set_Enum,
}
Campaign_Unavailable_Presentation :: enum {
	Hidden,
	Locked_Message,
	Requirements,
}
Campaign_Replay_Mode :: enum {
	Disabled,
	Effectless,
	Replace_Outcome,
}
Campaign_Invalid_Result_Policy :: enum {
	Preserve,
	Clear,
}

Campaign_Variable :: struct {
	id, display_name, description: string,
	kind:                          Campaign_Value_Kind,
	default_boolean:               bool,
	default_integer:               int,
	default_enum:                  string,
	enum_values:                   [CAMPAIGN_MAX_ENUM_VALUES]string,
	enum_value_count:              int,
}

// Conditions are stored as a flat pre-order tree. Group children occupy the
// contiguous range [first_child, first_child+child_count). Child nodes may in
// turn point at later ranges, keeping the persisted document non-recursive.
Campaign_Condition :: struct {
	kind:                             Campaign_Condition_Kind,
	first_child, child_count:         int,
	variable_id, case_id, enum_value: string,
	boolean_value:                    bool,
	integer_value:                    int,
	integer_comparison:               Campaign_Integer_Comparison,
	outcome:                          Outcome,
}

Campaign_Effect :: struct {
	kind:          Campaign_Effect_Kind,
	variable_id:   string,
	boolean_value: bool,
	integer_value: int,
	enum_value:    string,
}

Campaign_Outcome_Effects :: struct {
	outcome:                    Outcome,
	first_effect, effect_count: int,
}

Campaign_Case :: struct {
	id, title, story_path, level_path, case_content_version, locked_message: string,
	condition_root:                                                          int,
	required, optional:                                                      bool,
	unavailable_presentation:                                                Campaign_Unavailable_Presentation,
	replay_mode:                                                             Campaign_Replay_Mode,
	invalid_result_policy:                                                   Campaign_Invalid_Result_Policy,
	outcome_effects:                                                         [5]Campaign_Outcome_Effects,
	outcome_effect_count:                                                    int,
}

Campaign_Definition :: struct {
	version, id, title, creator, description, content_version, thumbnail: string,
	variables:                                                            [dynamic]Campaign_Variable,
	conditions:                                                           [dynamic]Campaign_Condition,
	effects:                                                              [dynamic]Campaign_Effect,
	cases:                                                                [dynamic]Campaign_Case,
}

Campaign_Value :: struct {
	kind:          Campaign_Value_Kind,
	boolean_value: bool,
	integer_value: int,
	enum_value:    string,
}
Campaign_Case_Result :: struct {
	present, started:              bool,
	case_id, case_content_version: string,
	outcome:                       Outcome,
	completion_sequence:           u64,
}
Campaign_Playthrough :: struct {
	campaign_id, campaign_content_version, id, name: string,
	results:                                         [CAMPAIGN_MAX_CASES]Campaign_Case_Result,
	values:                                          [CAMPAIGN_MAX_VARIABLES]Campaign_Value,
	completion_count:                                int,
	next_completion_sequence:                        u64,
	active_case:                                     int,
	derived_hash:                                    u64,
}
Campaign_Condition_Trace :: struct {
	value:   bool,
	message: string,
}
// A condition path addresses nodes by logical child ordinals from a case root.
// Authoring callers never need to retain serialization-array indices, which
// are intentionally free to change after insert/remove/compaction.
Campaign_Condition_Path :: struct {
	children: [CAMPAIGN_MAX_CONDITIONS]int,
	depth:    int,
}
Campaign_Workspace_Action_Kind :: enum {
	Set_Metadata,
	Add_Variable,
	Add_Condition,
	Add_Effect,
	Add_Case,
}
Campaign_Workspace_Metadata :: struct {
	version, id, title, creator, description, content_version, thumbnail: string,
}
Campaign_Workspace_Action :: struct {
	kind:       Campaign_Workspace_Action_Kind,
	metadata:   Campaign_Workspace_Metadata,
	variable:   Campaign_Variable,
	condition:  Campaign_Condition,
	effect:     Campaign_Effect,
	case_value: Campaign_Case,
}
Campaign_Recalculation :: struct {
	ok:                    bool,
	message:               string,
	cleared:               [CAMPAIGN_MAX_CASES]string,
	cleared_count, passes: int,
}
Campaign_Playthrough_Library :: struct {
	items:           [CAMPAIGN_MAX_PLAYTHROUGHS]Campaign_Playthrough,
	count, selected: int,
}
Campaign_Workspace_Tab :: enum {
	Overview,
	Cases,
	Variables,
	Conditions,
	Effects,
	Simulation,
	Diagnostics,
}
Campaign_Workspace_Text_Field :: enum {
	None,
	Campaign_Format,
	Campaign_ID,
	Campaign_Title,
	Campaign_Creator,
	Campaign_Description,
	Campaign_Version,
	Campaign_Thumbnail,
	Case_ID,
	Case_Title,
	Case_Content_Version,
	Story_Path,
	Level_Path,
	Locked_Message,
	Variable_ID,
	Variable_Name,
	Variable_Description,
	Enum_Value,
}
Campaign_Workspace_History :: struct {
	undo, redo:             [CAMPAIGN_HISTORY_LIMIT]Campaign_Definition,
	undo_count, redo_count: int,
	current:                Campaign_Definition,
	ready:                  bool,
}
Campaign_Workspace_State :: struct {
	open,
	renaming_playthrough,
	delete_confirm,
	exit_confirm:                                                     bool,
	tab:                                                                                                          Campaign_Workspace_Tab,
	text_field:                                                                                                   Campaign_Workspace_Text_Field,
	selected_case,
	selected_variable,
	selected_condition,
	selected_effect,
	selected_outcome,
	selected_enum_value: int,
	dirty:                                                                                                        bool,
	feedback,
	simulation_trace:                                                                                   string,
	diagnostics:                                                                                                  Validation,
	simulated:                                                                                                    Campaign_Playthrough,
	draft:                                                                                                        Campaign_Definition,
	history:                                                                                                      Campaign_Workspace_History,
	rename_buffer:                                                                                                [64]u8,
	rename_count:                                                                                                 int,
	text_buffer:                                                                                                  [256]u8,
	text_count:                                                                                                   int,
}
Story_Library_Kind :: enum {
	Collection,
	Standalone,
}
Campaign_Catalog_Entry :: struct {
	path, id, title, creator, description, thumbnail, requirements: string,
	kind:                                                           Story_Library_Kind,
	story_count:                                                    int,
	installed:                                                      bool,
}
Campaign_Browser_State :: struct {
	entries:         [CAMPAIGN_MAX_CATALOG]Campaign_Catalog_Entry,
	count, selected: int,
	scroll:          f32,
	feedback:        string,
}

campaign_document: Campaign_Definition
campaign_playthrough: Campaign_Playthrough
campaign_playthroughs: Campaign_Playthrough_Library
campaign_workspace: Campaign_Workspace_State
campaign_browser: Campaign_Browser_State
campaign_manifest_path: string
campaign_case_page: int
campaign_storage_override: string
