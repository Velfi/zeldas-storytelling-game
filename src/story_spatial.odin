package main

import "core:fmt"
import "core:strings"

Story_Spatial_Query_Kind :: enum {
	Present,
	Contained_By,
	Distance,
	Visible,
	Reachable,
	Travel_Time,
}

Story_Spatial_Query :: struct {
	kind: Story_Spatial_Query_Kind,
	a, b: Story_Spatial_Id,
}
Story_Spatial_Result :: struct {
	status:        Story_Spatial_Status,
	boolean_value: bool,
	number_value:  f32,
	explanation:   string,
}
Story_Spatial_Command :: struct {
	kind:                Story_Spatial_Command_Kind,
	target, destination: Story_Spatial_Id,
	enabled:             bool,
}

Story_Spatial_Service :: struct {
	userdata: rawptr,
	query:    proc(userdata: rawptr, query: Story_Spatial_Query) -> Story_Spatial_Result,
	begin:    proc(userdata: rawptr) -> bool,
	stage:    proc(userdata: rawptr, command: Story_Spatial_Command) -> bool,
	commit:   proc(userdata: rawptr) -> bool,
	rollback: proc(userdata: rawptr),
}

story_spatial_id_valid :: proc(id: Story_Spatial_Id) -> bool {return(
		id.space_id != "" &&
		id.target_id != "" \
	)}
story_spatial_id_text :: proc(id: Story_Spatial_Id) -> string {if !story_spatial_id_valid(id) do return ""
	return fmt.tprintf("%s:%s", id.space_id, id.target_id)}
story_spatial_id_parse :: proc(
	text: string,
	default_space: string = "",
) -> (
	Story_Spatial_Id,
	bool,
) {parts := strings.split(text, ":"); if len(parts) == 2 && parts[0] != "" && parts[1] != "" do return {parts[0], parts[1]}, true
	if default_space != "" && text != "" do return {default_space, text}, true
	return {}, false}

story_spatial_query :: proc(
	service: ^Story_Spatial_Service,
	query: Story_Spatial_Query,
) -> Story_Spatial_Result {
	if service == nil || service.query == nil do return {.Unavailable, false, 0, "spatial service is unavailable"}
	return service.query(service.userdata, query)
}

story_spatial_condition :: proc(
	service: ^Story_Spatial_Service,
	condition: ^Story_Condition,
) -> Story_Condition_Trace {
	kind := Story_Spatial_Query_Kind.Present
	#partial switch condition.kind {
	case .Spatial_Present:
		kind = .Present
	case .Spatial_Contained_By:
		kind = .Contained_By
	case .Spatial_Distance:
		kind = .Distance
	case .Spatial_Visible:
		kind = .Visible
	case .Spatial_Reachable:
		kind = .Reachable
	case .Spatial_Travel_Time:
		kind = .Travel_Time
	case:
		return {false, "not a spatial condition"}
	}
	result := story_spatial_query(service, {kind, condition.spatial_a, condition.spatial_b})
	if result.status != .Available do return {false, result.explanation}
	if kind == .Distance || kind == .Travel_Time {
		ok := result.number_value <= condition.distance
		return {
			ok,
			fmt.tprintf(
				"%s: %.2f <= %.2f",
				result.explanation,
				result.number_value,
				condition.distance,
			),
		}
	}
	return {result.boolean_value, result.explanation}
}

story_spatial_stage_effect :: proc(service: ^Story_Spatial_Service, effect: Story_Effect) -> bool {
	if service == nil || service.stage == nil do return false
	return service.stage(
		service.userdata,
		{
			effect.spatial_command,
			effect.spatial_target,
			effect.spatial_destination,
			effect.world_enabled,
		},
	)
}
