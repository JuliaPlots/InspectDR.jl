#InspectDR: Base functionnality and types for Cairo layer
#-------------------------------------------------------------------------------


#==Constants
===============================================================================#


#==Main types
===============================================================================#
#2D plot canvas; basic info:
mutable struct PCanvas2D <: PlotCanvas
	ctx::CairoContext
	bb::BoundingBox #Entire canvas
	graphbb::BoundingBox #Graph portion
	ext::PExtents2D #Extents of graph portion
	xf::Transform2D #Transform used to render data
end
PCanvas2D(ctx, bb, graphbb, ext) =
	PCanvas2D(ctx, bb, graphbb, ext, Transform2D(ext, graphbb))
PCanvas2D(ctx, bb, ginfo::Graph2DInfo) =
	PCanvas2D(ctx, bb, ginfo.graphbb, ginfo.ext, ginfo.xf)


#=
#TODO: use instead of PCanvas2D???
#TODO: Add axis scale info, etc???
#Canvas for 2D Graph:
mutable struct GCanvas2D
	ctx::CairoContext
	graphbb::BoundingBox
	ext::PExtents2D #Extents of graph portion
	xf::Transform2D #Transform used to render data
end
GCanvas2D(ctx, graphbb, ext) =
	GCanvas2D(ctx, graphbb, ext, Transform2D(ext, graphbb))
=#

#Used to buffer portions of plot for better GUI response times
mutable struct CairoBufferedPlot
	surf::Cairo.CairoSurface #Main surface where plot is drawn
	data::Cairo.CairoSurface #Cache of data image layer
end


#==Basic rendering
===============================================================================#

#Apply transform to Cairo (when easier to do so):
function setxfrm(ctx::CairoContext, xf::Transform2D)
	xorig = xf.x0*xf.xs
	yorig = xf.y0*xf.ys
	Cairo.translate(ctx, xorig, yorig)
	Cairo.scale(ctx, xf.xs, xf.ys)
end


#==Rendering Glyphs
===============================================================================#

function getglyphcolor(glyph::GlyphAttributes, line::LineAttributes)
	c = glyph.color
	if nothing == c
		c = line.color
	end
	return c
end

function getglyphfill(glyph::GlyphAttributes)
	fill = glyph.fillcolor
	if COLOR_TRANSPARENT == fill #Small optimization
		fill = nothing
	end
	return fill
end

function drawglyph(ctx::CairoContext, g::GlyphPolyline, pt::Point2D, size::DReal, fill)
	#TODO: could scale GlyphPolyline only once for efficiency (instead of every time we draw).
	x = g.x*size; y = g.y*(-1*size) #Compensate for y-reversal
	Cairo.move_to(ctx, pt.x, pt.y)
	Cairo.rel_move_to(ctx, x[1], y[1]) #rel: Probably less prone to rounding errors

	dxv = diff(x); dyv = diff(y)
	for (dx, dy) in zip(dxv, dyv)
		Cairo.rel_line_to(ctx, dx, dy)
	end
	if g.closepath
		Cairo.close_path(ctx)
		renderfill(ctx, fill)
	end
	Cairo.stroke(ctx)
	return
end
function drawglyph(ctx::CairoContext, g::GlyphLineSegments, pt::Point2D, size::DReal, fill)
	dxv = size * (g.x2 - g.x1)
	dyv = -size * (g.y2 - g.y1)
	x1v = size * g.x1
	y1v = -size * g.y1
	for (x1, y1, dx, dy) in zip(x1v, y1v, dxv, dyv)
		Cairo.move_to(ctx, pt.x, pt.y)
		Cairo.rel_move_to(ctx, x1, y1) #rel: Probably less prone to rounding errors
		Cairo.rel_line_to(ctx, dx, dy)
		Cairo.stroke(ctx)
	end
	return
end
function drawglyph(ctx::CairoContext, g::GlyphCircle, pt::Point2D, size::DReal, fill)
	cairo_circle(ctx, pt.x, pt.y, g.radius*size)
	renderfill(ctx, fill)
	Cairo.stroke(ctx)
end

#Correctly displays a glyph, given wfrm properties.
function drawglyph_safe(ctx::CairoContext, wfrm::IWaveform, pt::Point2D)
	_glyph = Glyph(wfrm.glyph.shape)
	if nothing == _glyph; return; end

	linecolor = getglyphcolor(wfrm.glyph, wfrm.line)
	linestyle = LineStyle(:solid, Float64(wfrm.line.width), linecolor)
	setlinestyle(ctx, linestyle)
	fill = getglyphfill(wfrm.glyph)
	gsize = Float64(wfrm.glyph.size)

	drawglyph(ctx, _glyph, pt, gsize, fill)
	return
end


#==Rendering base plot elements
===============================================================================#

#Render main plot annotation (titles, axis labels, ...)
#-------------------------------------------------------------------------------
function render(ctx::CairoContext, a::Annotation,
	bb::BoundingBox, databb::BoundingBox, graphbblist::Vector{BoundingBox}, lyt::PlotLayout)
	TIMESTAMP_OFFSET = 3 #WANTCONST

	#Title
#	xcenter = (bb.xmin+bb.xmax)/2 #Entire plot BB.
	xcenter = (databb.xmin+databb.xmax)/2 #Data-area BB only.
	pt = Point2D(xcenter, bb.ymin+lyt.voffset_title)
	render(ctx, a.title, pt, lyt.font_title, align=ALIGN_HCENTER|ALIGN_VCENTER)

	#X-axis label
	xcenter = (databb.xmin+databb.xmax)/2
	pt = Point2D(xcenter, bb.ymax-lyt.voffset_xaxislabel)
	render(ctx, a.xlabel, pt, lyt.font_axislabel, align=ALIGN_HCENTER|ALIGN_VCENTER)

	#Y-axis labels
	nstrips = min(length(a.ylabels), length(graphbblist))
	for i in 1:nstrips
		graphbb = graphbblist[i]
		ycenter = (graphbb.ymin+graphbb.ymax)/2
		pt = Point2D(bb.xmin+lyt.hoffset_yaxislabel, ycenter)
		render(ctx, a.ylabels[i], pt, lyt.font_axislabel, align=ALIGN_HCENTER|ALIGN_VCENTER, angle=-π/2)
	end

	#Time stamp
	if lyt.enable_timestamp
		pt = Point2D(bb.xmax-TIMESTAMP_OFFSET, bb.ymax-TIMESTAMP_OFFSET)
		render(ctx, a.timestamp, pt, lyt.font_time, align=ALIGN_RIGHT|ALIGN_BOTTOM)
	end
end

#Render frame around graph
#-------------------------------------------------------------------------------
function render_graphframe(canvas::PCanvas2D, aa::AreaAttributes)
	ctx = canvas.ctx #WANTCONST
Cairo.save(ctx)
	setlinestyle(ctx, LineStyle(aa.line))
	Cairo.rectangle(ctx, canvas.graphbb)
	Cairo.stroke(ctx)
Cairo.restore(ctx)
	return
end

#==Render grid
===============================================================================#
render_vlines(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, xlines::AbstractGridLines) = nothing
function render_vlines(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, xlines::GridLines)
	if xlines.displaymajor
		setlinestyle(ctx, lyt.line_gridmajor)
		for xline in xlines.major
			x = map2dev(xf, Point2D(xline, 0)).x
			drawline(ctx, Point2D(x, graphbb.ymin), Point2D(x, graphbb.ymax))
		end
	end
	if xlines.displayminor
		setlinestyle(ctx, lyt.line_gridminor)
		for xline in xlines.minor
			x = map2dev(xf, Point2D(xline, 0)).x
			drawline(ctx, Point2D(x, graphbb.ymin), Point2D(x, graphbb.ymax))
		end
	end
end
render_hlines(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, ylines::AbstractGridLines) = nothing
function render_hlines(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, ylines::GridLines)
	if ylines.displaymajor
		setlinestyle(ctx, lyt.line_gridmajor)
		for yline in ylines.major
			y = map2dev(xf, Point2D(0, yline)).y
			drawline(ctx, Point2D(graphbb.xmin, y), Point2D(graphbb.xmax, y))
		end
	end
	if ylines.displayminor
		setlinestyle(ctx, lyt.line_gridminor)
		for yline in ylines.minor
			y = map2dev(xf, Point2D(0, yline)).y
			drawline(ctx, Point2D(graphbb.xmin, y), Point2D(graphbb.xmax, y))
		end
	end
end

function render_grid(canvas::PCanvas2D, lyt::PlotLayout, grid::GridRect)
	ctx = canvas.ctx #WANTCONST
	Cairo.save(ctx) #-----
	render_vlines(ctx, canvas.graphbb, canvas.xf, lyt, grid.xlines)
	render_hlines(ctx, canvas.graphbb, canvas.xf, lyt, grid.ylines)
	Cairo.restore(ctx) #-----
end


#==Render ticks
===============================================================================#

#Default label:
function render_ticklabel(ctx::CairoContext, val::DReal, pt::Point2D, font::Font, align::CAlignment, fmt::TickLabelFormatting, ::AxisScale)
	tstr = ""
	if false #Old display system.
		#TODO: deprecate
		tstr = "$val"
		if length(tstr) > 7 #HACK!
			tstr = @sprintf("%0.1e", val)
		end
	else
		tstr = formatted(val, fmt.fmt, showexp=!fmt.splitexp)
	end
	render(ctx, tstr, pt, font, align=align)
end

render_ticklabel(ctx::CairoContext, val::DReal, pt::Point2D, font::Font, align::CAlignment, fmt::TickLabelFormatting, scale::LogScale{:e}) =
	render_power(ctx, "e", val, pt, font, align)
render_ticklabel(ctx::CairoContext, val::DReal, pt::Point2D, font::Font, align::CAlignment, fmt::TickLabelFormatting, scale::LogScale{2}) =
	render_power(ctx, "2", val, pt, font, align)
render_ticklabel(ctx::CairoContext, val::DReal, pt::Point2D, font::Font, align::CAlignment, fmt::TickLabelFormatting, scale::LogScale{10}) =
	render_power(ctx, "10", val, pt, font, align)

function render_axisscalelabel(ctx::CairoContext, pt::Point2D, font::Font, align::CAlignment, fmt::TickLabelFormatting, ::AxisScale)
	tstr = formatted_exp(fmt.fmt)
	render(ctx, tstr, pt, font, align=align)
end

#Render ticks: Well-defined GridLines
#-------------------------------------------------------------------------------
function render_xticks(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, xlines::GridLines, xs::AxisScale, ticklabels::Bool)
	tframe = DReal(lyt.frame_data.line.width) #WANTCONST TODO: Fix LineAttributes to have concrete type
	fmt = TickLabelFormatting(lyt.format_xtick, xlines.rnginfo)
	yframe = graphbb.ymax
	ylabel = graphbb.ymax + lyt.voffset_xticklabel
	for xtick in xlines.major
		x = map2dev(xf, Point2D(xtick, 0)).x
		if ticklabels
			render_ticklabel(ctx, xtick, Point2D(x, ylabel), lyt.font_ticklabel, ALIGN_TOP|ALIGN_HCENTER, fmt, xs)
		end
		drawline(ctx, Point2D(x, yframe), Point2D(x, yframe-lyt.length_tickmajor))
	end
	for xtick in xlines.minor
		x = map2dev(xf, Point2D(xtick, 0)).x
		drawline(ctx, Point2D(x, yframe), Point2D(x, yframe-lyt.length_tickminor))
	end
	if fmt.splitexp && ticklabels
		xlabel = graphbb.xmax + tframe
		render_axisscalelabel(ctx, Point2D(xlabel, yframe), lyt.font_ticklabel, ALIGN_BOTTOM|ALIGN_LEFT, fmt, xs)
	end
end
function render_yticks(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, ylines::GridLines, ys::AxisScale)
	tframe = DReal(lyt.frame_data.line.width) #WANTCONST TODO: Fix LineAttributes to have concrete type
	fmt = TickLabelFormatting(lyt.format_ytick, ylines.rnginfo)
	xframe = graphbb.xmin
	xlabel = graphbb.xmin - lyt.hoffset_yticklabel
	for ytick in ylines.major
		y = map2dev(xf, Point2D(0, ytick)).y
		render_ticklabel(ctx, ytick, Point2D(xlabel, y), lyt.font_ticklabel, ALIGN_RIGHT|ALIGN_VCENTER, fmt, ys)
		drawline(ctx, Point2D(xframe, y), Point2D(xframe+lyt.length_tickmajor, y))
	end
	for ytick in ylines.minor
		y = map2dev(xf, Point2D(0, ytick)).y
		drawline(ctx, Point2D(xframe, y), Point2D(xframe+lyt.length_tickminor, y))
	end
	if fmt.splitexp
		ylabel = graphbb.ymin - tframe
		render_axisscalelabel(ctx, Point2D(xframe, ylabel), lyt.font_ticklabel, ALIGN_BOTTOM|ALIGN_LEFT, fmt, ys)
	end
end

#Render ticks: UndefinedGridLines
#-------------------------------------------------------------------------------
function render_xticks(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, xlines::UndefinedGridLines, xs::AxisScale, ticklabels::Bool)
	fmt = TickLabelFormatting(NoRangeDisplayInfo())
	yframe = graphbb.ymax
	ylabel = graphbb.ymax + lyt.voffset_xticklabel
	for (x, xlabel) in [(graphbb.xmin, xlines.minline), (graphbb.xmax, xlines.maxline)]
		if ticklabels
			render_ticklabel(ctx, xlabel, Point2D(x, ylabel), lyt.font_ticklabel, ALIGN_TOP|ALIGN_HCENTER, fmt, LinScale())
		end
		drawline(ctx, Point2D(x, yframe), Point2D(x, yframe-lyt.length_tickmajor))
	end
end
function render_yticks(ctx::CairoContext, graphbb::BoundingBox, xf::Transform2D, lyt::PlotLayout, ylines::UndefinedGridLines, ys::AxisScale)
	fmt = TickLabelFormatting(NoRangeDisplayInfo())
	xframe = graphbb.xmin
	xlabel = graphbb.xmin - lyt.hoffset_yticklabel
	for (y, ylabel) in [(graphbb.ymax, ylines.minline), (graphbb.ymin, ylines.maxline)]
		render_ticklabel(ctx, ylabel, Point2D(xlabel, y), lyt.font_ticklabel, ALIGN_RIGHT|ALIGN_VCENTER, fmt, LinScale())
		drawline(ctx, Point2D(xframe, y), Point2D(xframe+lyt.length_tickmajor, y))
	end
end

function render_ticks(canvas::PCanvas2D, lyt::PlotLayout, grid::GridRect, xs::AxisScale, ys::AxisScale, xticklabels::Bool)
	render_xticks(canvas.ctx, canvas.graphbb, canvas.xf, lyt, grid.xlines, xs, xticklabels)
	render_yticks(canvas.ctx, canvas.graphbb, canvas.xf, lyt, grid.ylines, ys)
end


#==High-level rendering
===============================================================================#

#Render axis labels, ticks, ...
#-------------------------------------------------------------------------------
function render_axes(canvas::PCanvas2D, lyt::PlotLayout, grid::GridRect, xs::AxisScale, ys::AxisScale, xticklabels::Bool)
	render_graphframe(canvas, lyt.frame_data)
	render_ticks(canvas, lyt, grid, xs, ys, xticklabels)
end

#Render NaNs on plot:
#-------------------------------------------------------------------------------
function rendernans(canvas::PCanvas2D, wfrm::IWaveform)
	NAN_LINE = LineStyle(
		:solid, Float64(4), ARGB32(1, 0, 0, 0.5)
	) #WANTCONST
	ctx = canvas.ctx #WANTCONST
	graphbb = canvas.graphbb #WANTCONST
	x = wfrm.ds.x #WANTCONST
	y = wfrm.ds.y #WANTCONST

	if length(x) != length(y)
		error("x & y - vector length mismatch.")
	end

	setlinestyle(ctx, NAN_LINE)
	hasNaNNaN = false

	for i in 1:length(x)
		pt = Point2D(x[i], y[i])
		xnan = isnan(pt.x); ynan = isnan(pt.y)

		if xnan && ynan
			hasNaNNaN = true #nothing practical to display
		elseif xnan
			pt = map2dev(canvas.xf, pt)
			Cairo.move_to(ctx, graphbb.xmin, pt.y)
			Cairo.line_to(ctx, graphbb.xmax, pt.y)
			Cairo.stroke(ctx)
		elseif ynan
			pt = map2dev(canvas.xf, pt)
			Cairo.move_to(ctx, pt.x, graphbb.ymin)
			Cairo.line_to(ctx, pt.x, graphbb.ymax)
			Cairo.stroke(ctx)
		end
	end

	#TODO: warn hasNaNNaN?
	return hasNaNNaN
end
function rendernans(canvas::PCanvas2D, wfrmlist::Vector{IWaveform}, strip::Int)
	for wfrm in wfrmlist
		if 0 == wfrm.strip || wfrm.strip == strip
			rendernans(canvas, wfrm)
		end
	end
	return
end

#Render an actual waveform
#-------------------------------------------------------------------------------
function render(canvas::PCanvas2D, wfrm::DWaveform)
	ctx = canvas.ctx #WANTCONST
	ds = wfrm.ds #WANTCONST

	if length(ds) < 1; return; end
	if !wfrm.visible; return; end

if hasline(wfrm)
	setlinestyle(ctx, LineStyle(wfrm.line))
	newsegment = true
	for i in 1:length(ds)
		pt = map2dev(canvas.xf, ds[i])
		xnan = isnan(pt.x); ynan = isnan(pt.y)

		#TODO: log NaNs?  Display NaNs?
		if xnan && ynan
			Cairo.stroke(ctx) #Close last line
			newsegment = true
		elseif xnan || ynan
			#Simply skip this point
		elseif newsegment
			Cairo.move_to(ctx, pt.x, pt.y)
			newsegment = false
		else
			Cairo.line_to(ctx, pt.x, pt.y)
		end
	end
	Cairo.stroke(ctx)
end

	_glyph = Glyph(wfrm.glyph.shape)
	if nothing == _glyph; return; end

	#TODO: do not draw when outside graph extents.

	#Draw symbols:
	linecolor = getglyphcolor(wfrm.glyph, wfrm.line)
	linestyle = LineStyle(:solid, Float64(wfrm.line.width), linecolor)
	setlinestyle(ctx, linestyle)
	fill = getglyphfill(wfrm.glyph)
	gsize = Float64(wfrm.glyph.size)
	for i in 1:length(ds)
		pt = map2dev(canvas.xf, ds[i])
		drawglyph(ctx, _glyph, pt, gsize, fill)
	end

	return
end
function render(canvas::PCanvas2D, wfrmlist::Vector{DWaveform}, strip::Int)
	for wfrm in wfrmlist
		if 0 == wfrm.strip || wfrm.strip == strip
			render(canvas, wfrm)
		end
	end
	return
end

#Last line
