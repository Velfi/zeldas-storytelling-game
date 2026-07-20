package main

import "core:fmt"
import "core:strings"

when ODIN_OS == .Windows {
	foreign import tomlc17 "../third_party/tomlc17/tomlc17.lib"
} else {
	foreign import tomlc17 "../third_party/tomlc17/libtomlc17.a"
}

Toml_Type :: enum i32 {
	UNKNOWN,
	STRING,
	INT64,
	FP64,
	BOOLEAN,
	DATE,
	TIME,
	DATETIME,
	DATETIMETZ,
	ARRAY,
	TABLE,
}
Toml_String :: struct {
	ptr: cstring,
	len: i32,
}
Toml_Array :: struct {
	size: i32,
	elem: [^]Toml_Datum,
}
Toml_Table :: struct {
	size:  i32,
	key:   [^]cstring,
	len:   [^]i32,
	value: [^]Toml_Datum,
}
Toml_Timestamp :: struct {
	year, month, day, hour, minute, second: i16,
	usec:                                   i32,
	tz:                                     i16,
}
Toml_Value :: struct #raw_union {
	s:       cstring,
	str:     Toml_String,
	int64:   i64,
	fp64:    f64,
	boolean: bool,
	ts:      Toml_Timestamp,
	arr:     Toml_Array,
	tab:     Toml_Table,
}
Toml_Datum :: struct {
	type:          Toml_Type,
	flag:          u32,
	lineno, colno: i32,
	source:        cstring,
	u:             Toml_Value,
}
Toml_Result :: struct {
	ok:       bool,
	toptab:   Toml_Datum,
	errmsg:   [200]u8,
	internal: rawptr,
}

foreign tomlc17 {
	toml_parse_file_ex :: proc(fname: cstring) -> Toml_Result ---
	toml_free :: proc(result: Toml_Result) ---
	toml_get :: proc(table: Toml_Datum, key: cstring) -> Toml_Datum ---
}

toml_seek_key :: proc(table: Toml_Datum, key: string) -> Toml_Datum {ckey, err :=
		strings.clone_to_cstring(key, context.temp_allocator)
	if err != nil do return {}
	return toml_get(table, ckey)}
toml_case_string :: proc(table: Toml_Datum, key: string) -> string {datum := toml_seek_key(
		table,
		key,
	)
	if datum.type != .STRING || datum.u.str.ptr == nil do return ""
	ptr := cast([^]u8)rawptr(datum.u.str.ptr)
	bytes := ptr[:datum.u.str.len]
	return fmt.aprintf("%s", string(bytes))}
toml_case_int :: proc(table: Toml_Datum, key: string) -> int {datum := toml_seek_key(table, key)
	if datum.type == .INT64 do return int(datum.u.int64)
	return 0}
toml_case_float :: proc(table: Toml_Datum, key: string) -> f32 {datum := toml_seek_key(table, key)
	if datum.type == .FP64 do return f32(datum.u.fp64)
	if datum.type == .INT64 do return f32(datum.u.int64)
	return 0}
toml_case_bool :: proc(table: Toml_Datum, key: string) -> bool {datum := toml_seek_key(table, key)
	return datum.type == .BOOLEAN && datum.u.boolean}
toml_tables :: proc(table: Toml_Datum, key: string) -> []Toml_Datum {datum := toml_seek_key(
		table,
		key,
	)
	if datum.type != .ARRAY || datum.u.arr.elem == nil || datum.u.arr.size <= 0 do return nil
	all := datum.u.arr.elem[:datum.u.arr.size]
	for 	item, i in all {if item.type == .TABLE do continue; return all[:i]}
	return all}
toml_case_strings :: proc(table: Toml_Datum, key: string) -> []string {datum := toml_seek_key(
		table,
		key,
	)
	if datum.type != .ARRAY || datum.u.arr.elem == nil do return nil
	items := datum.u.arr.elem[:datum.u.arr.size]
	result := make([dynamic]string, 0, len(items))
	for item in items do if item.type == .STRING && item.u.str.ptr != nil {ptr := cast([^]u8)rawptr(item.u.str.ptr); bytes := ptr[:item.u.str.len]; append(&result, fmt.aprintf("%s", string(bytes)))}
	return result[:]}
toml_case_ints :: proc(table: Toml_Datum, key: string) -> []int {datum := toml_seek_key(table, key)
	if datum.type != .ARRAY || datum.u.arr.elem == nil do return nil
	items := datum.u.arr.elem[:datum.u.arr.size]
	result := make([dynamic]int, 0, len(items))
	for item in items do if item.type == .INT64 do append(&result, int(item.u.int64))
	return result[:]}
toml_parse_diagnostic :: proc(path, kind: string, result: ^Toml_Result) -> Validation {message :=
		string(result.errmsg[:])
	end := 0
	for end < len(message) && message[end] != 0 do end += 1
	return{false, fmt.tprintf("Could not parse %s %s: %s", kind, path, message[:end])}}
toml_file_valid :: proc(path: string) -> bool {cpath, err := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	)
	if err != nil do return false
	parsed := toml_parse_file_ex(cpath)
	defer toml_free(parsed)
	return parsed.ok}
toml_diagnostic :: proc(path, message: string, line: int) -> Validation {return{
		false,
		fmt.tprintf("%s:%d: %s", path, line, message),
	}}
