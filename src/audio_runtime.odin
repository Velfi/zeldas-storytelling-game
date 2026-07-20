package main

import "core:math"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

load_sound_assets :: proc(g: ^Game) -> int {
	paths := [Sound_Cue]string {
		.Evidence       = "assets/audio/cues/clue-revealed.ogg",
		.Fact           = "assets/audio/cues/fact-established.ogg",
		.Pick_Up        = "assets/kenney_ui-audio/Audio/click3.ogg",
		.Snap           = "assets/kenney_ui-audio/Audio/switch31.ogg",
		.Reject         = "assets/kenney_ui-audio/Audio/switch8.ogg",
		.Recreate       = "assets/kenney_ui-audio/Audio/switch20.ogg",
		.Shutter        = "assets/audio/cues/crank-resistance.ogg",
		.Sightline_Fail = "assets/kenney_ui-audio/Audio/switch10.ogg",
		.Tick           = "assets/kenney_ui-audio/Audio/switch7.ogg",
		.Reveal_Proven  = "assets/audio/cues/reveal-section-proven.ogg",
		.Door_Open      = "assets/audio/cues/wood-open.ogg",
		.Door_Close     = "assets/audio/cues/wood-close.ogg",
		.Switch         = "assets/kenney_ui-audio/Audio/switch13.ogg",
		.Decisive_Clue  = "assets/audio/cues/decisive-clue.ogg",
		.Candle_Out     = "assets/audio/cues/candle-extinguished.ogg",
		.Shutter_Close  = "assets/audio/cues/wood-close.ogg",
	}; loaded := 0
	for cue in Sound_Cue {path := paths[cue]; channels, sample_rate: i32; decoded: [^]i16
		frames := stb_vorbis_decode_filename(
			strings.clone_to_cstring(path, context.temp_allocator),
			&channels,
			&sample_rate,
			&decoded,
		)
		if frames <= 0 || decoded == nil || channels <= 0 {continue}
		defer chicago_vorbis_free(decoded)
		if sample_rate != 44100 do continue
		frame_count := int(frames)
		g.sounds[cue] = make([dynamic]f32, frame_count)
		for frame in 0 ..< frame_count {mixed: f32 = 0; for channel in 0 ..< int(channels) do mixed += f32(decoded[frame * int(channels) + channel]) / 32768
			g.sounds[cue][frame] = mixed / f32(channels)}
		loaded += 1}
	return loaded
}
destroy_sound_assets :: proc(g: ^Game) {for &samples in g.sounds do if samples != nil do delete(samples)}
play_sound :: proc(g: ^Game, cue: Sound_Cue) {
	if g.mute || g.audio_stream == nil do return
	if len(g.sounds[cue]) >
	   0 {samples := g.sounds[cue]; _ = sdl.PutAudioStreamData(g.audio_stream, rawptr(&samples[0]), i32(len(samples) * size_of(f32))); return}
	// A generated click remains as a defensive fallback if an asset is missing.
	frequencies := [Sound_Cue]f32 {
		.Evidence       = 880,
		.Fact           = 660,
		.Pick_Up        = 420,
		.Snap           = 760,
		.Reject         = 145,
		.Recreate       = 330,
		.Shutter        = 95,
		.Sightline_Fail = 180,
		.Tick           = 120,
		.Reveal_Proven  = 990,
		.Door_Open      = 260,
		.Door_Close     = 220,
		.Switch         = 520,
		.Decisive_Clue  = 740,
		.Candle_Out     = 80,
		.Shutter_Close  = 110,
	}; durations := [Sound_Cue]f32 {
		.Evidence       = .16,
		.Fact           = .22,
		.Pick_Up        = .08,
		.Snap           = .12,
		.Reject         = .13,
		.Recreate       = .22,
		.Shutter        = .28,
		.Sightline_Fail = .18,
		.Tick           = .24,
		.Reveal_Proven  = .25,
		.Door_Open      = .18,
		.Door_Close     = .18,
		.Switch         = .1,
		.Decisive_Clue  = .32,
		.Candle_Out     = .14,
		.Shutter_Close  = .3,
	}; frequency :=
		frequencies[cue]; sample_count := min(int(44100 * durations[cue]), 12000); samples: [12000]f32
	for i in 0 ..< sample_count {t := f32(i) / 44100; envelope := 1 - f32(i) / f32(sample_count); wave := f32(math.sin(f64(2 * math.PI * frequency * t))); if cue == .Shutter do wave = wave * .55 + f32(math.sin(f64(2 * math.PI * (frequency * .5) * t))) * .45; if cue == .Reject || cue == .Sightline_Fail do frequency *= .99994; samples[i] = wave * envelope * .16}
	_ = sdl.PutAudioStreamData(
		g.audio_stream,
		rawptr(&samples[0]),
		i32(sample_count * size_of(f32)),
	)
}

play_story_node_sound :: proc(g: ^Game, node_id: string) -> bool {if g == nil || g.mute || g.audio_stream == nil do return false
	path, ok := story_node_sound_path(g.story_project, &authoring_workspace.assets, node_id)
	if !ok || !os.is_file(path) do return false
	channels, sample_rate: i32
	decoded: [^]i16
	frames := stb_vorbis_decode_filename(
		strings.clone_to_cstring(path, context.temp_allocator),
		&channels,
		&sample_rate,
		&decoded,
	)
	if frames <= 0 || decoded == nil || channels <= 0 || sample_rate != 44100 do return false
	defer chicago_vorbis_free(decoded)
	samples := make([]f32, int(frames), context.temp_allocator)
	for 	frame in 0 ..< int(frames) {mixed: f32 = 0; for channel in 0 ..< int(channels) do mixed += f32(decoded[frame * int(channels) + channel]) / 32768
		samples[frame] = mixed / f32(channels)}
	return sdl.PutAudioStreamData(
		g.audio_stream,
		raw_data(samples),
		i32(len(samples) * size_of(f32)),
	)}

project_asset_audio_preview_info :: proc(
	project_root: string,
	registry: ^Project_Asset_Registry,
	id: string,
) -> (
	frames, channels, sample_rate: int,
	ready: bool,
) {if registry == nil do return; index := project_asset_index(registry, id); if index < 0 || registry.assets[index].kind != .Audio do return
	path := project_asset_record_path(project_root, registry.assets[index])
	if !os.is_file(path) do return
	if strings.to_lower(os.ext(path)) == ".ogg" {decoded_channels, decoded_rate: i32
		decoded: [^]i16
		decoded_frames := stb_vorbis_decode_filename(
			strings.clone_to_cstring(path, context.temp_allocator),
			&decoded_channels,
			&decoded_rate,
			&decoded,
		)
		if decoded != nil do chicago_vorbis_free(decoded)
		return int(decoded_frames),
			int(decoded_channels),
			int(decoded_rate),
			decoded_frames > 0 && decoded_channels > 0 && decoded_rate == 44100}
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil || len(data) < 44 || string(data[:4]) != "RIFF" do return
	channels = int(project_asset_u16_le(data, 22))
	sample_rate = int(project_asset_u32_le(data, 24))
	bits := int(project_asset_u16_le(data, 34))
	if channels <= 0 || sample_rate != 44100 || bits != 16 do return
	at := 12
	for at + 8 <= len(data) {size := int(project_asset_u32_le(data, at + 4)); if at + 8 + size > len(data) do break
		if string(data[at:at + 4]) == "data" {frames = size / (channels * 2); return frames,
				channels,
				sample_rate,
				frames > 0}
		at += 8 + size + (size & 1)}
	return}

apply_story_node_animation_asset :: proc(g: ^Game, node_id: string) -> bool {if g == nil || g.story_project == nil do return false
	path, ok := story_node_animation_path(g.story_project, &authoring_workspace.assets, node_id)
	if !ok || !os.is_file(path) do return false
	mesh, loaded := glb_load(path)
	if !loaded || !mesh.ready do return false
	node_index := project_asset_story_node_index(g.story_project, node_id)
	if node_index < 0 do return false
	actor := g.story_project.nodes[node_index].actor
	if actor == "" do actor = g.story_project.nodes[node_index].speaker_id
	payload := mystery_game_payload(g)
	if payload == nil do return false
	for character, i in payload.characters do if character.entity_id == actor && i + 1 < len(character_meshes) {character_meshes[i + 1] = mesh; return true}
	return false}

play_project_asset_audio :: proc(g: ^Game, registry: ^Project_Asset_Registry, id: string) -> bool {
	if g == nil || registry == nil || g.mute || g.audio_stream == nil do return false
	_, _, _, ready := project_asset_audio_preview_info(
		active_authoring_project.root_path,
		registry,
		id,
	); if !ready do return false
	index := project_asset_index(
		registry,
		id,
	); if index < 0 || registry.assets[index].kind != .Audio do return false
	path := project_asset_record_path(
		active_authoring_project.root_path,
		registry.assets[index],
	); if !os.is_file(path) do return false
	// OGG is decoded through the same production path used by authored sound
	// cues. WAV PCM16 previews are converted directly from the validated RIFF
	// payload so every supported authoring audio format can be auditioned.
	if strings.to_lower(os.ext(path)) ==
	   ".ogg" {channels, sample_rate: i32; decoded: [^]i16; frames := stb_vorbis_decode_filename(strings.clone_to_cstring(path, context.temp_allocator), &channels, &sample_rate, &decoded); if frames <= 0 || decoded == nil || channels <= 0 || sample_rate != 44100 do return false; defer chicago_vorbis_free(decoded); samples := make([]f32, int(frames), context.temp_allocator); for frame in 0 ..< int(frames) {mixed: f32 = 0; for channel in 0 ..< int(channels) do mixed += f32(decoded[frame * int(channels) + channel]) / 32768; samples[frame] = mixed / f32(channels)}; return sdl.PutAudioStreamData(g.audio_stream, raw_data(samples), i32(len(samples) * size_of(f32)))}
	data, err := os.read_entire_file_from_path(
		path,
		context.temp_allocator,
	); if err != nil || len(data) < 44 || string(data[:4]) != "RIFF" do return false
	channels := int(
		project_asset_u16_le(data, 22),
	); sample_rate := int(project_asset_u32_le(data, 24)); bits := int(project_asset_u16_le(data, 34)); if channels <= 0 || sample_rate != 44100 || bits != 16 do return false
	at := 12; payload: []u8; for at + 8 <= len(data) {size := int(project_asset_u32_le(data, at + 4)); if at + 8 + size > len(data) do break; if string(data[at:at + 4]) == "data" {payload = data[at + 8:at + 8 + size]; break}; at += 8 + size + (size & 1)}; if len(payload) < channels * 2 do return false
	frames :=
		len(payload) /
		(channels *
				2); samples := make([]f32, frames, context.temp_allocator); for frame in 0 ..< frames {mixed: f32 = 0; for channel in 0 ..< channels {sample_at := (frame * channels + channel) * 2; raw := i16(u16(payload[sample_at]) | u16(payload[sample_at + 1]) << 8); mixed += f32(raw) / 32768}; samples[frame] = mixed / f32(channels)}; return sdl.PutAudioStreamData(g.audio_stream, raw_data(samples), i32(len(samples) * size_of(f32)))
}

update_vehicle_drive_audio :: proc(g: ^Game, v: Vehicle_State, tune: Vehicle_Tune, throttle: f32) {
	if g == nil || g.mute || g.vehicle_audio_stream == nil do return
	target_frequency, target_gain := vehicle_engine_targets(v, tune, throttle)
	if g.vehicle_audio_frequency <= 0 do g.vehicle_audio_frequency = target_frequency
	g.vehicle_audio_frequency += (target_frequency - g.vehicle_audio_frequency) * .10
	g.vehicle_audio_gain += (target_gain - g.vehicle_audio_gain) * .14
	target_tire_gain := max(
		vehicle_tire_audio_target_blended(v, v.handbrake_slip),
		vehicle_assist_audio_gain(v.driver_assist, v.driver_assist_strength, v.driver_assist_time),
	); g.vehicle_audio_tire_gain += (target_tire_gain - g.vehicle_audio_tire_gain) * .18
	target_tire_frequency_a, target_tire_frequency_b := vehicle_tire_audio_frequencies_for_vehicle(
		v,
		v.traction_state,
		v.driver_assist,
		v.driver_assist_strength,
	); g.vehicle_audio_tire_frequency_a = vehicle_tire_frequency_step(g.vehicle_audio_tire_frequency_a, target_tire_frequency_a); g.vehicle_audio_tire_frequency_b = vehicle_tire_frequency_step(g.vehicle_audio_tire_frequency_b, target_tire_frequency_b)
	target_rough_gain :=
		vehicle_rough_feedback_blended(v, v.surface_blend) *
		.026; g.vehicle_audio_rough_gain += (target_rough_gain - g.vehicle_audio_rough_gain) * .16
	rough_frequency := vehicle_rough_audio_frequency(v)
	// One exact fixed-tick chunk keeps latency bounded and makes synthesis
	// deterministic regardless of render rate. A dedicated stream lets UI cues
	// overlap the engine instead of waiting behind it in a shared queue.
	samples: [735]f32
	for i in 0 ..< len(samples) {
		phase :=
			g.vehicle_audio_phase; fundamental := f32(math.sin(f64(phase))); second := f32(math.sin(f64(phase * 2))); fourth := f32(math.sin(f64(phase * 4)))
		pulse := fundamental * .58 + second * .28 + fourth * .14
		// Independent incommensurate phases produce a stable scrub texture. Each
		// oscillator wraps on its own full cycle, avoiding discontinuities.
		tire_a := f32(
			math.sin(f64(g.vehicle_audio_tire_phase_a)),
		); tire_b := f32(math.sin(f64(g.vehicle_audio_tire_phase_b))); tire := tire_a * .62 + tire_b * .38
		rough :=
			f32(math.sin(f64(g.vehicle_audio_rough_phase))) * .72 +
			f32(math.sin(f64(g.vehicle_audio_rough_phase * 2))) * .28
		samples[i] =
			pulse * g.vehicle_audio_gain +
			tire * g.vehicle_audio_tire_gain +
			rough * g.vehicle_audio_rough_gain
		g.vehicle_audio_phase += f32(2 * math.PI) * g.vehicle_audio_frequency / 44100
		if g.vehicle_audio_phase > f32(2 * math.PI) do g.vehicle_audio_phase -= f32(2 * math.PI)
		g.vehicle_audio_tire_phase_a +=
			f32(2 * math.PI) *
			g.vehicle_audio_tire_frequency_a /
			44100; g.vehicle_audio_tire_phase_b += f32(2 * math.PI) * g.vehicle_audio_tire_frequency_b / 44100
		if g.vehicle_audio_tire_phase_a > f32(2 * math.PI) do g.vehicle_audio_tire_phase_a -= f32(2 * math.PI)
		if g.vehicle_audio_tire_phase_b > f32(2 * math.PI) do g.vehicle_audio_tire_phase_b -= f32(2 * math.PI)
		g.vehicle_audio_rough_phase +=
			f32(2 * math.PI) *
			rough_frequency /
			44100; if g.vehicle_audio_rough_phase > f32(2 * math.PI) do g.vehicle_audio_rough_phase -= f32(2 * math.PI)
	}
	_ = sdl.PutAudioStreamData(
		g.vehicle_audio_stream,
		rawptr(&samples[0]),
		i32(len(samples) * size_of(f32)),
	)
}

play_vehicle_impact_sound :: proc(g: ^Game, impact: f32) {
	if g == nil || g.mute || g.audio_stream == nil do return
	frequency, gain, duration := vehicle_impact_audio_parameters(
		impact,
	); sample_count := min(int(duration * 44100), 7056); samples: [7056]f32
	for i in 0 ..< sample_count {
		t :=
			f32(i) /
			44100; envelope := f32(math.exp(f64(-t * (24 + impact * 18)))); body := f32(math.sin(f64(2 * math.PI * frequency * t))); knock := f32(math.sin(f64(2 * math.PI * (frequency * 2.73) * t)))
		// A deterministic high partial supplies the initial contact without noise
		// generators or assets; the low body carries perceived impact weight.
		attack := clamp(
			1 - t / .006,
			0,
			1,
		); samples[i] = (body * .72 + knock * .28 * attack) * envelope * gain
	}
	_ = sdl.PutAudioStreamData(
		g.audio_stream,
		rawptr(&samples[0]),
		i32(sample_count * size_of(f32)),
	)
}

play_check_dice_sound :: proc(g: ^Game) {
	if g == nil || g.audio_stream == nil do return
	// A short deterministic wooden rattle: six decaying impacts accelerate,
	// then leave room for the settled result cue.
	sample_rate: f32 = 44100; sample_count := int(CHECK_ROLL_DURATION * sample_rate); samples := make([]f32, sample_count, context.temp_allocator)
	impacts := [6]f32{.05, .17, .31, .48, .70, 1.02}
	for i in 0 ..< sample_count {t := f32(i) / sample_rate; value: f32 = 0; for impact, index in impacts {age := t - impact; if age < 0 || age > .09 do continue; decay := f32(math.exp(f64(-age * 55))); frequency := f32(520 + index * 73); value += f32(math.sin(f64(2 * math.PI * frequency * age))) * decay * .11}; samples[i] = value}
	_ = sdl.PutAudioStreamData(
		g.audio_stream,
		rawptr(&samples[0]),
		i32(len(samples) * size_of(f32)),
	)
}
