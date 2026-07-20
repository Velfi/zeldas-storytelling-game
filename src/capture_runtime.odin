package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

capture_configure_authoring :: proc(g: ^Game, argument: string) {
	if argument == "--capture-theme-knoll" {
		g.screen = .Theme_Knoll
		g.gui.focused = button_id({300, 458, 220, 42})
	}
	if argument == "--capture-theme-knoll-details" do g.screen = .Theme_Knoll_Details
	if argument == "--capture-campaign-checkbox" {
		campaign_workspace_begin()
		campaign_workspace.tab = .Variables
		g.screen = .Campaign_Action
		boolean_index := -1
		for variable, i in campaign_workspace.draft.variables {
			if variable.kind == .Boolean {
				boolean_index = i
				break
			}
		}
		if boolean_index < 0 {
			append(
				&campaign_workspace.draft.variables,
				Campaign_Variable {
					id = "capture_flag",
					display_name = "Capture flag",
					description = "Boolean component capture fixture",
					kind = .Boolean,
				},
			)
			boolean_index = len(campaign_workspace.draft.variables) - 1
		}
		campaign_workspace.selected_variable = boolean_index
		campaign_workspace.draft.variables[boolean_index].default_boolean = true
	}
	if strings.has_prefix(argument, "--capture-campaign-authoring-") {
		campaign_workspace_begin()
		g.screen = .Campaign_Action
		switch argument {
		case "--capture-campaign-authoring-overview":
			campaign_workspace.tab = .Overview
		case "--capture-campaign-authoring-cases":
			campaign_workspace.tab = .Cases
		case "--capture-campaign-authoring-variables":
			campaign_workspace.tab = .Variables
		case "--capture-campaign-authoring-conditions":
			campaign_workspace.tab = .Conditions
		case "--capture-campaign-authoring-effects":
			campaign_workspace.tab = .Effects
		case "--capture-campaign-authoring-simulation":
			campaign_workspace.tab = .Simulation
		case "--capture-campaign-authoring-diagnostics":
			campaign_workspace.tab = .Diagnostics
		}
	}
	if strings.has_prefix(argument, "--capture-story-authoring-") {
		authoring_workspace_begin(g)
		switch argument {
		case "--capture-story-authoring-project":
			authoring_workspace.tab = .Project
		case "--capture-story-authoring-story-data":
			authoring_workspace.tab = .Story_Data
		case "--capture-story-authoring-mystery":
			authoring_workspace.tab = .Mystery
		case "--capture-story-authoring-diagnostics":
			authoring_workspace.tab = .Diagnostics
		case "--capture-story-authoring-assets":
			authoring_workspace.tab = .Assets
		case "--capture-story-authoring-packages":
			authoring_workspace.tab = .Packages
		case "--capture-story-authoring-library":
			authoring_workspace.tab = .Library
		}
	}
}

capture_apply_cli_overrides :: proc(g: ^Game) -> bool {
	for value in os.args {
		if value == "--hide-roofs" do g.capture_hide_roofs = true
	}
	camera_position_text := argument_value("--camera-position=")
	camera_look_at_text := argument_value("--camera-look-at=")
	if camera_position_text != "" || camera_look_at_text != "" {
		if camera_position_text == "" || camera_look_at_text == "" {
			fmt.eprintln(
				"custom capture camera requires both --camera-position=x,y,z and --camera-look-at=x,y,z",
			)
			return false
		}
		camera_position, position_ok := parse_vec3_argument(camera_position_text)
		camera_look_at, look_at_ok := parse_vec3_argument(camera_look_at_text)
		if !position_ok || !look_at_ok {
			fmt.eprintln("capture camera values must be comma-separated x,y,z numbers")
			return false
		}
		dx := camera_look_at.x - camera_position.x
		dy := camera_look_at.y - camera_position.y
		dz := camera_look_at.z - camera_position.z
		if dx * dx + dy * dy + dz * dz < .0001 {
			fmt.eprintln("capture camera position and look-at must be different")
			return false
		}
		g.camera_pose_override = true
		g.camera_eye_override = camera_position
		g.camera_target_override = camera_look_at
		g.screen = .Investigate
	}

	walls_text := argument_value("--walls=")
	cutaway_text := argument_value("--cutaway=")
	if walls_text != "" && cutaway_text != "" {
		fmt.eprintln("use either --walls=auto|up|down or --cutaway=0..1, not both")
		return false
	}
	if walls_text != "" {
		wall_view, ok := capture_wall_view_from_text(walls_text)
		if !ok {
			fmt.eprintln("capture wall mode must be auto, up, down, or cutaway")
			return false
		}
		g.wall_view = wall_view
		switch wall_view {
		case .Walls_Up:
			g.cutaway_transition = 0
			for &amount in g.wall_cutaways do amount = 0
		case .Walls_Down:
			g.cutaway_transition = 1
			for &amount in g.wall_cutaways do amount = 1
		case .Automatic:
			maximum_cutaway: f32
			for &wall, i in house_walls {
				if i >= len(g.wall_cutaways) do break
				amount := house_wall_cutaway_target(g, &wall)
				g.wall_cutaways[i] = amount
				maximum_cutaway = max(maximum_cutaway, amount)
			}
			g.cutaway_transition = maximum_cutaway
		}
	}
	if cutaway_text != "" {
		amount, ok := strconv.parse_f32(strings.trim_space(cutaway_text))
		if !ok || amount < 0 || amount > 1 {
			fmt.eprintln("capture cutaway amount must be between 0 and 1")
			return false
		}
		g.wall_view = .Automatic
		g.cutaway_transition = amount
		g.capture_cutaway_override = true
		g.capture_cutaway_amount = amount
		for &wall_amount in g.wall_cutaways do wall_amount = amount
	}
	return true
}
