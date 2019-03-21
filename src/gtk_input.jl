#InspectDR: Event handlers for user input of Gtk layer
#-------------------------------------------------------------------------------

#==Types
===============================================================================#
const KeyMap = Dict{Int, Function}

mutable struct KeyBindings
	nomod::KeyMap
	shiftmod::KeyMap
	ctrlmod::KeyMap
	altmod::KeyMap
end
KeyBindings() = KeyBindings(KeyMap(), KeyMap(), KeyMap(), KeyMap())


#==Module-level definitions
===============================================================================#
const keybindings = KeyBindings()


#==Helper functions
===============================================================================#
function setstate_normal(pwidget::PlotWidget)
	gdk_window_set_cursor(pwidget.canvas, CURSOR_DEFAULT)
	pwidget.state = ISNormal()
end
ignoreuserinput(pwidget::PlotWidget) = nothing

#Handle mousepress if a CtrlElement was clicked:
function handleevent_mousepress(pwidget::PlotWidget, ::Type{CtrlElement}, x::Float64, y::Float64)
	istrip = hittest(pwidget, x, y)

	if istrip > 0
		if handleevent_mousepress(pwidget, pwidget.markers, istrip, x, y)
			return true
		end

		#TODO: test for other control points here....
	end

	return false
end

#Set focus on active strip under x,y coordinates:
function focus_strip(pwidget::PlotWidget, x::Float64, y::Float64)
	istrip = hittest(pwidget, x, y)
	if istrip > 0
		pwidget.curstrip = istrip
	end
	nothing
end


#==Default event handlers
===============================================================================#
handleevent_mousepress(::InputState, pwidget::PlotWidget, event::Gtk.GdkEventButton) =
	nothing
handleevent_mouserelease(::InputState, pwidget::PlotWidget, event::Gtk.GdkEventButton) =
	nothing
function handleevent_mousemove(::InputState, pwidget::PlotWidget, event::Gtk.GdkEventMotion)
	handleevent_plothover(pwidget, event)
	nothing
end

#Event handler for plot widget keypress
#-------------------------------------------------------------------------------
function handleevent_keypress(::InputState, pwidget::PlotWidget, event::Gtk.GdkEventKey)
#event.event_type: GDK_KEY_PRESS/GDK_KEY_RELEASE
#@show event.event_type, event.state, event.keyval, event.length, event.string, event.hardware_keycode, event.group, event.flags
	global keybindings

	#Find bound functions & execute:
	if modifiers_pressed(event.state, 0)
		fn = get(keybindings.nomod, event.keyval, ignoreuserinput)
		fn(pwidget)
	elseif modifiers_pressed(event.state, MODIFIER_SHIFT)
		fn = get(keybindings.shiftmod, event.keyval, ignoreuserinput)
		fn(pwidget)
	elseif modifiers_pressed(event.state, MODIFIER_CTRL)
		fn = get(keybindings.ctrlmod, event.keyval, ignoreuserinput)
		fn(pwidget)
	elseif modifiers_pressed(event.state, MODIFIER_ALT)
		fn = get(keybindings.altmod, event.keyval, ignoreuserinput)
		fn(pwidget)
	end
#	@show event.keyval
end

function handleevent_mousescroll(::InputState, pwidget::PlotWidget, event::Gtk.GdkEventScroll)
	if modifiers_pressed(event.state, 0)
		if GdkScrollDirection.GDK_SCROLL_UP == event.direction
			pan_up(pwidget)
		elseif GdkScrollDirection.GDK_SCROLL_DOWN == event.direction
			pan_down(pwidget)
		end
	elseif modifiers_pressed(event.state, MODIFIER_SHIFT)
		if GdkScrollDirection.GDK_SCROLL_UP == event.direction
			pan_left(pwidget)
		elseif GdkScrollDirection.GDK_SCROLL_DOWN == event.direction
			pan_right(pwidget)
		end
	elseif modifiers_pressed(event.state, MODIFIER_CTRL)
		if GdkScrollDirection.GDK_SCROLL_UP == event.direction
			zoom_in(pwidget, event.x, event.y)
		elseif GdkScrollDirection.GDK_SCROLL_DOWN == event.direction
			zoom_out(pwidget, event.x, event.y)
		end
	end
end
function handleevent_scalechanged(::InputState, pwidget::PlotWidget)
	if !scalectrl_enabled(pwidget); return; end #Should not really happen
	scalectrl_apply(pwidget)
end


#==State: Normal input state
===============================================================================#
function handleevent_mousepress(::ISNormal, pwidget::PlotWidget, event::Gtk.GdkEventButton)
#	@show event.state, event.button, event.event_type
	focus_strip(pwidget, event.x, event.y)
	focus(pwidget.widget) #In case not in focus

	if 3==event.button
		boxzoom_setstart(pwidget, event.x, event.y) #Changes state
	elseif 1==event.button
		if modifiers_pressed(event.state, MODIFIER_SHIFT)
			mousepan_setstart(pwidget, event.x, event.y) #Changes state
		elseif !modifiers_pressed(event.state, MODIFIERS_SUPPORTED) #Un-modified
			handleevent_mousepress(pwidget, CtrlElement, event.x, event.y)
		end
	end
	series = pwidget.src.data
	for s in series
		if isinside(s.legendbb, event.x, event.y)
			s.visible = !s.visible
			refresh(pwidget,refreshdata=true)
		end
	end
end


#==Key bindings
===============================================================================#
function _setdefaults(bnd::KeyBindings)
	bnd.nomod = KeyMap(
		GdkKeySyms.Escape => setstate_normal,
		GdkKeySyms.Up => pan_up,
		GdkKeySyms.Down => pan_down,
		GdkKeySyms.Left => pan_left,
		GdkKeySyms.Right => pan_right,
		GdkKeySyms_Plus => zoom_in,
		GdkKeySyms_Minus => zoom_out,

		Int('r') => addrefmarker,
		Int('d') => addΔmarker,
	)
	bnd.shiftmod = KeyMap(
		Int('D') => addΔmarkerref,
	)
	bnd.ctrlmod = KeyMap(
		Int('f') => zoom_full,
		Int('h') => zoom_hfull,
		Int('v') => zoom_vfull,
	)
	bnd.altmod = KeyMap(
	)
end

#Last line
