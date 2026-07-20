package main

import sdl "vendor:sdl3"

Input_Device :: enum { Keyboard_Mouse, Gamepad }
Prompt_Kind :: enum { Accept, Back, Interact, Vehicle_Action, Board, Notebook, Navigate, Move, Look, Room_Hint, Camera, Attributes, Handbrake }
keyboard_prompt_label :: proc(kind:Prompt_Kind)->string {switch kind {case .Accept:return "ENTER";case .Back:return "ESC";case .Interact:return "E";case .Vehicle_Action:return "F";case .Board:return "B";case .Notebook:return "N";case .Navigate:return "ARROWS";case .Move:return "WASD";case .Look:return "ARROWS";case .Room_Hint:return "Q";case .Camera:return "F";case .Attributes:return "C";case .Handbrake:return "SPACE"};return "?"}
gamepad_family :: proc(kind:sdl.GamepadType)->int {#partial switch kind {case .PS3,.PS4,.PS5:return 1;case .NINTENDO_SWITCH_PRO,.NINTENDO_SWITCH_JOYCON_LEFT,.NINTENDO_SWITCH_JOYCON_RIGHT,.NINTENDO_SWITCH_JOYCON_PAIR:return 2};return 0}
gamepad_prompt_label :: proc(kind:Prompt_Kind,family:int)->string {
	if kind==.Board {switch family {case 1:return "SQUARE";case 2:return "Y";case:return "X"}}
	if kind==.Notebook {switch family {case 1:return "TRIANGLE";case 2:return "X";case:return "Y"}}
	if kind==.Back {switch family {case 1:return "CIRCLE";case 2:return "A";case:return "B"}}
	if kind==.Vehicle_Action {switch family {case 1:return "TRIANGLE";case 2:return "X";case:return "Y"}}
	if kind==.Handbrake do return "RB"
	if kind==.Attributes {switch family {case 1:return "SQUARE";case 2:return "Y";case:return "X"}}
	#partial switch kind {case .Accept:return family==1?"CROSS":family==2?"B":"A";case .Interact:return family==1?"CROSS":family==2?"B":"A";case .Navigate:return "D-PAD";case .Move:return "LEFT STICK";case .Look:return "RIGHT STICK";case .Room_Hint:return "L3";case .Camera:return "R3"}
	return "?"
}
prompt_label :: proc(g:^Game,kind:Prompt_Kind)->string {return g.active_device==.Gamepad?gamepad_prompt_label(kind,gamepad_family(g.gamepad_type)):keyboard_prompt_label(kind)}
