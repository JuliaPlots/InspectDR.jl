#InspectDR: Base functionnality and types
#-------------------------------------------------------------------------------

#AnnotationArea
#TODO: Themes: Vector/Dict of PlotLayout/MultiplotLayout?


#==Abstracts
===============================================================================#
abstract type Plot end
abstract type PlotCanvas end #TODO: Does not appear useful
abstract type PlotAnnotation end


#==Plot-level structures
===============================================================================#
#=Input structures are high-level constructs describing the plot.  They will
be broken down to lower-level structures later on.
=#

#Specifies whether plot should apply F1 acceleration to drop points:
mutable struct PointDropMatrix
	m::Array{Bool,2} #Indices: (has_line, has_glyph)
end
droppoints(m::PointDropMatrix, has_line::Bool, has_glyph::Bool) =
	m.m[has_line+1, has_glyph+1]

#Don't want immutable like LineStyle (modified by user):
mutable struct LineAttributes <: AttributeList
	style
	width #[0, 10]
	color
end
line(;style=:solid, width=1, color=COLOR_BLACK) =
	LineAttributes(style, width, color)
LineStyle(a::LineAttributes) = LineStyle(a.style, Float64(a.width), a.color)

#"line" constructor:
#TODO: Inadequate
#eval(genexpr_attriblistbuilder(:line, LineAttributes, reqfieldcnt=0))

mutable struct AreaAttributes #<: AttributeList
	line::LineAttributes
	fillcolor::Colorant
end
AreaAttributes(;line=InspectDR.line(style=:none), fillcolor=COLOR_TRANSPARENT) =
	AreaAttributes(line, fillcolor)

mutable struct GlyphAttributes <: AttributeList #Don't use "Symbol" - name used by Julia
#==IMPORTANT:
Edge width & color taken from LineAttributes
==#
	shape #because "type" is reserved
	size #of glyph.  edge width taken from LineAttributes
	color #glyph linecolor. = nothing to match line.color
	fillcolor
end
glyph(;shape=:none, size=3, color=nothing, fillcolor=nothing) =
	GlyphAttributes(shape, size, color, fillcolor)

#"glyph" constructor:
#TODO: Inadequate
#eval(genexpr_attriblistbuilder(:glyph, GlyphAttributes, reqfieldcnt=0))

mutable struct Waveform{T}
	id::String
	ds::T
	line::LineAttributes
	glyph::GlyphAttributes
	ext::PExtents2D
	strip::UInt8 #Y-strip
	visible::Bool
	legendbb::BoundingBox
end

#Input waveform:
const IWaveform = Waveform{IDataset}

#Display waveform (concrete (x, y) pair):
const DWaveform = Waveform{Vector{Point2D}}

#=TODO:
typealias DWaveformCplx Waveform{PointComplex}
to track x-values of complex data??
=#

mutable struct Annotation
	title::String
	xlabel::String
	ylabels::Vector{String}
	timestamp::String
end
Annotation(;title="") = Annotation(title, "", [], Libc.strftime(time()))

mutable struct Font <: AbstractStyle
	name::String
	_size::Float64
	bold::Bool
	color::Colorant
end
Font(name::String, _size::Real; bold::Bool=false, color=COLOR_BLACK) =
	Font(name, _size, bold, color)
Font() = Font(DEFAULT_FONTNAME, 10)
function Font(ref::Font; name=StyleDefault, _size=StyleDefault, bold=StyleDefault, color=StyleDefault)
	result = deepcopy(ref)
	result[:name] = name
	result[:_size] = _size
	result[:bold] = bold
	result[:color] = color
	return result
end

mutable struct PlotLayout <: AbstractStyle #Layout/LegendLStyle
	enable_legend::Bool
	enable_timestamp::Bool

	valloc_data::Float64 #Suggested height of data (graph) area when exporting.
	valloc_top::Float64 #Top of plot data area
	valloc_mid::Float64 #Space betwen strips
	valloc_bottom::Float64 #Bottom of plot data area
	valloc_legenditemsp::Float64 #Spacing between items (% of text height).

	halloc_data::Float64 #Suggested width of data (graph) area when exporting.
	halloc_left::Float64 #Left of data area
	halloc_right::Float64 #Right of data area - excluding legend area
	#NOTE: halloc_right needs room for axis scale (ex: ×10⁻²).
	halloc_legend::Float64
	halloc_legendlineseg::Float64 #length of line segment to display.

	#Offsets to center of text:
	voffset_title::Float64
	voffset_xaxislabel::Float64 #Centered
	voffset_xticklabel::Float64

	hoffset_yaxislabel::Float64 #Centered
	hoffset_yticklabel::Float64
	hoffset_legendtext::Float64 #Spacing between line/symbol and label (% of M character).

	length_tickmajor::Float64
	length_tickminor::Float64

	line_gridmajor::LineStyle
	line_gridminor::LineStyle
	line_smithmajor::LineStyle
	line_smithminor::LineStyle

	font_title::Font
	font_axislabel::Font
	font_ticklabel::Font
	font_annotation::Font
	font_time::Font #Timestamp
	font_legend::Font

	format_xtick::TickLabelStyle
	format_ytick::TickLabelStyle

	frame_canvas::AreaAttributes #Area under entire plot
	frame_data::AreaAttributes
	frame_legend::AreaAttributes

#=TODO:
 - Legend position (left/right/...)
 - Legend autosize (auto-compute from text)
=#
end

PlotLayout() = PlotLayout(
	false, false, #enable
	0, 0, 0, 0, 0, #valloc
	0, 0, 0, 0, 0, #halloc
	0, 0, 0, #voffset
	0, 0, 0, #hoffset
	Float64(5), Float64(3), #length_tick*
	LineStyle(:dash, Float64(2), RGB24(.7, .7, .7)), #line_gridmajor
	LineStyle(:dash, Float64(1), RGB24(.7, .7, .7)), #line_gridminor
	LineStyle(:solid, Float64(2), COLOR_BLACK), #line_smithmajor
	LineStyle(:solid, Float64(1), RGB24(.7, .7, .7)), #line_smithminor
	Font(), Font(), Font(), Font(), Font(), Font(),
	TickLabelStyle(), TickLabelStyle(),
	AreaAttributes(), AreaAttributes(), AreaAttributes()
)

const PlotStyle = StyleType{PlotLayout}

#AnnotationGroup: Allows for hierarchical groupings of PlotAnnotation:
mutable struct AnnotationGroup{T<:PlotAnnotation} <: PlotAnnotation
	elem::Vector{T}
end

mutable struct TextAnnotation <: PlotAnnotation
	text::String
	pos::Pos2DOffset
	font::Font
	angle::DReal #Degrees
	align::Symbol #tl, tc, tr, cl, cc, cr, bl, bc, br
	strip::UInt8
end
#Don't use "text"... high probability of collisions when exported...
atext(text::String; x=DNaN, y=DNaN,
	xoffset_rel=0, yoffset_rel=0, xoffset=0, yoffset=0,
	font=Font(10), angle=0, align=:bl, strip=1) =
	TextAnnotation(text,
		Pos2DOffset(Point2D(x,y), Vector2D(xoffset_rel, yoffset_rel), Vector2D(xoffset, yoffset)),
		font, angle, align, strip
	)

mutable struct HVMarker <: PlotAnnotation
	vmarker::Bool
	hmarker::Bool
	pos::Point2D
	line::LineAttributes
	strip::UInt8
end
vmarker(pos, line=InspectDR.line(); strip=0) = HVMarker(true, false, Point2D(pos, DNaN), line, strip)
hmarker(pos, line=InspectDR.line(); strip=1) = HVMarker(false, true, Point2D(DNaN, pos), line, strip)
hvmarker(pos, line=InspectDR.line(); strip=1) = HVMarker(true, true, pos, line, strip)

mutable struct PolylineAnnotation <: PlotAnnotation
	#TODO: preferable to use Point2D?
	x::Vector{DReal}
	y::Vector{DReal}
	line::LineAttributes
	fillcolor::Colorant
	closepath::Bool
	strip::UInt8
end
PolylineAnnotation(x, y; line=InspectDR.line(), fillcolor=COLOR_TRANSPARENT, closepath=true, strip=1) =
	PolylineAnnotation(x, y, line, fillcolor, closepath, strip)

#Single graph strip of a Plot2D (shared x-coord):
mutable struct GraphStrip
	yscale::AxisScale
	ext_data::PExtents2D #Maximum extents of data in strip (typically all finite)
	yext_full::PExtents1D #y-extents when zoomed out to "full" (NaN values: use ext_data)
	yext::PExtents1D #Current/active y-extents (typically all finite)
	grid::PlotGrid
end
GraphStrip() = GraphStrip(AxisScale(:lin, tgtmajor=8, tgtminor=2),
	PExtents2D(), PExtents1D(), PExtents1D(),
	GridRect(vmajor=true, vminor=false, hmajor=true, hminor=false))

#2D plot.
mutable struct Plot2D <: Plot
	xscale::AxisScale
	layout::PlotStyle
	annotation::Annotation

	#Plot extents (access using getextents):
	xext_data::PExtents1D #Maximum x-extents of data in strip (typically all finite)
	xext_full::PExtents1D #x-extents when zoomed out to "full" (NaN values: use xext_data)
	xext::PExtents1D #Current/active x-extents (typically all finite)

	plotbb::NullOr{BoundingBox} #User can specify where to draw on Multiplot

	strips::Vector{GraphStrip}
	data::Vector{IWaveform}

	#Annotation controlled directly by user (using _add interface):
	userannot::Vector{PlotAnnotation}

	#Annotation controlled by parent object
	parentannot::Vector{PlotAnnotation}

	#Display data cache:
	invalid_ddata::Bool #Is cache of display data invalid?
	display_data::Vector{DWaveform} #Clipped to current extents

	displayNaN::Bool #Costly (time) on large datasets
	pointdropmatrix::PointDropMatrix

	#Maximum # of x-pts in display:
	#TODO: move to layout?
	xres::Int
end

Plot2D(;title="") = Plot2D(AxisScale(:lin, tgtmajor=3.5, tgtminor=4),
	StyleType(defaults.plotlayout), Annotation(title=title),
	PExtents1D(), PExtents1D(), PExtents1D(),
	nothing, [GraphStrip()], [], [], [], true, [],
	false, defaults.pointdropmatrix, 1000
)

#Style info for multi-plot object:
mutable struct MultiplotLayout <: AbstractStyle
	ncolumns::Int

	valloc_title::Float64 #Title height allocation (title gets centered)
	valloc_plot::Float64 #Default height for single plot when saving multi-plot
	halloc_plot::Float64 #Default width for single plot when saving multi-plot

	font_title::Font
	frame::AreaAttributes
end
MultiplotLayout() = MultiplotLayout(
	1,
	0, 0, 0, #h/valloc
	Font(),
	AreaAttributes()
)

const MultiplotStyle = StyleType{MultiplotLayout}

mutable struct Multiplot
	title::String
	subplots::Vector{Plot}
	layout::MultiplotStyle
end
#TODO: ok to deprecate titlefont=??
function Multiplot(;style::MultiplotLayout=defaults.mplotlayout, title="",
		ncolumns=StyleDefault, valloc_plot=StyleDefault, halloc_plot=StyleDefault)
	layout = StyleType(style)
	layout[:ncolumns] = ncolumns
	layout[:valloc_plot] = valloc_plot
	layout[:halloc_plot] = halloc_plot
	return Multiplot(title, [], layout)
end


#==Constructor-like functions
===============================================================================#


#==Accessors
===============================================================================#
getextents(d::IWaveform) = getextents(d.ds)
function getextents(dlist::Vector{IWaveform}, strip::Int=1)
	result = PExtents2D(DNaN, DNaN, DNaN, DNaN)
	for d in dlist
		if strip == d.strip
			result = union(result, d.ext)
		end
	end
	return result
end

hasline(w::Waveform) = (w.line.style != :none)
hasglyph(w::Waveform) = isglyph(w.glyph.shape)


#==Mutators
===============================================================================#
settitle(mplot::Plot2D, title::String) =
	(mplot.annotation.title = String(title))

settitle(mplot::Multiplot, title::String) =
	(mplot.title = String(title))


#=="add" interface
===============================================================================#

function _add(mp::Multiplot, plot::Plot2D)
	push!(mp.subplots, plot)
	return plot
end
_add(mp::Multiplot, ::Type{T}) where T<:Plot = _add(mp, T())


#Set dataf1=false to overwrite optimizations for functions of 1 argument.
function _add(plot::Plot2D, x::Vector, y::Vector; id::String="", dataf1=true, strip=1)
	if dataf1
		dataf1 = isincreasing(x) #Can we use optimizations?
	end
	ext = PExtents2D() #Don't care at the moment
	ds = IWaveform(id, IDataset{dataf1}(x, y), line(), glyph(), ext, strip, true, BoundingBox(-1,-1,-1,-1))
	push!(plot.data, ds)
	return ds
end

function _add(plot::Plot2D, annot::PlotAnnotation)
	push!(plot.userannot, annot)
	return annot
end


#==Plot extents
===============================================================================#

function invalidate_extents(plot::Plot2D)
	#If extents are no longer valid, neither is display cache:
	plot.invalid_ddata = true
end

function invalidate_datalist(plot::Plot2D)
	plot.invalid_ddata = true
end

#Get/set functions for graph extents:
#-------------------------------------------------------------------------------
#Full extents are always merged (ext_full expected to be incomplete):
getxextents_full(plot::Plot2D) = merge(plot.xext_data, plot.xext_full)
getyextents_full(strip::GraphStrip) = merge(yvalues(strip.ext_data), strip.yext_full)

#Active extents:
#(Obtain values from full extents when supplied ext contains NaN fields):
#NOTE: no need for get functions.. simply access structures directly.
_setxextents(plot::Plot2D, ext::PExtents1D) =
	(plot.xext = merge(getxextents_full(plot), ext))
_setyextents(strip::GraphStrip, ext::PExtents1D) =
	(strip.yext = merge(getyextents_full(strip), ext))

function setyextents(plot::Plot2D, ext::PExtents1D, strip::Int = 1)
	_setyextents(plot.strips[strip], ext)
	#No need to invalidate... data reduction depends on x extents
	#invalidate_extents(plot)
end
function setxextents(plot::Plot2D, ext::PExtents1D)
	_setxextents(plot, ext)
	invalidate_extents(plot)
end

#NOTE: set/get*extents_axis functions: set/get extents in axis coordinates
#      (stored in user-"read"-able coordinates).
getxextents_axis(plot::Plot2D) = read2axis(plot.xext, InputXfrm1D(plot.xscale))
getyextents_axis(strip::GraphStrip) = read2axis(strip.yext, InputXfrm1D(strip.yscale))
getyextents_axis(plot::Plot2D, strip::Int) = getyextents_axis(plot.strips[strip])
getextents_axis(plot::Plot2D, strip::Int) =
	PExtents2D(getxextents_axis(plot), getyextents_axis(plot.strips[strip]))

setxextents_axis(plot::Plot2D, ext::PExtents1D) =
	setxextents(plot, axis2read(ext, InputXfrm1D(plot.xscale)))
setyextents_axis(plot::Plot2D, ext::PExtents1D, strip::Int) =
	setyextents(plot, axis2read(ext, InputXfrm1D(plot.strips[strip].yscale)), strip)
function setextents_axis(plot::Plot2D, ext::PExtents2D, strip::Int)
	setxextents_axis(plot, xvalues(ext))
	setyextents_axis(plot, yvalues(ext), strip)
end


#==Plot/graph bounding boxes
===============================================================================#

#TODO: Move aspect_square functionality to graph (not data area)
aspect_square(::PlotGrid) = false
aspect_square(::GridSmith) = true

#TODO: Deprecate this strange hack:
function grid1(plot::Plot2D)
	if length(plot.strips) > 0
		return plot.strips[1].grid
	else
		return GridRect()
	end
end


#Returns a centered bounding box with square aspect ratio.
#TODO: use in graphbounds - not databounds
function squarebounds(bb::BoundingBox)
	w = width(bb); h = height(bb)
	xmin = bb.xmin; xmax = bb.xmax
	ymin = bb.ymin; ymax = bb.ymax
	if w < h
		hdim = w / 2
		c = (ymin + ymax) / 2
		ymin = c - hdim; ymax = c + hdim
	else
		hdim = h / 2
		c = (xmin + xmax) / 2
		xmin = c - hdim; xmax = c + hdim
	end
	return BoundingBox(xmin, xmax, ymin, ymax)
end

#Get bounding box of plot data area:
function databounds(plotb::BoundingBox, lyt::PlotLayout)
	xmin = plotb.xmin + lyt.halloc_left
	xmax = plotb.xmax
	xmax -= lyt.enable_legend ? lyt.halloc_legend : lyt.halloc_right
	ymin = plotb.ymin + lyt.valloc_top
	ymax = plotb.ymax - lyt.valloc_bottom

	#Avoid division by zero, inversions, ...
	if xmin >= xmax
		c = (xmin + xmax)/2
		xmin = c - 0.5
		xmax = c + 0.5
	end
	if ymin >= ymax
		c = (ymin + ymax)/2
		ymin = c - 0.5
		ymax = c + 0.5
	end

	return BoundingBox(xmin, xmax, ymin, ymax)
end

#TODO: Move aspect_square to graphbounds.
function databounds(plotb::BoundingBox, lyt::PlotLayout, grid::PlotGrid)
	graphbb = databounds(plotb, lyt)
	if aspect_square(grid)
		graphbb = squarebounds(graphbb)
	end
	return graphbb
end

#Compute graph height (given n strips)
#TODO: Causes graphs to start/end on fractional pixels... behaves poorly.
#TODO: Latch to integer pixel boundaries.
function graph_h(datab::BoundingBox, gap::Float64, nstrips::Int)
	h = height(datab)
	if nstrips > 1
		h = (h - gap*(nstrips-1)) / nstrips
	end
	return max(h, 0)
end

#Get bounding box of graph "istrip":
function _graphbounds(datab::BoundingBox, h::Float64, pitch::Float64, istrip::Int)
	ymin = datab.ymin + pitch*(istrip-1)
	ymax = ymin + h
	return BoundingBox(datab.xmin, datab.xmax, ymin, ymax)
end

function graphbounds(datab::BoundingBox, lyt::PlotLayout, nstrips::Int, istrip::Int)
	gap = lyt.valloc_mid
	h = graph_h(datab, gap, nstrips)
	return _graphbounds(datab, h, h+gap, istrip)
end

#Get vector of graphbounds:
function graphbounds_list(datab::BoundingBox, lyt::PlotLayout, nstrips::Int)
	result = Vector{BoundingBox}(undef, nstrips)
	gap = lyt.valloc_mid
	h = graph_h(datab, gap, nstrips)
	pitch = h+gap

	for i in 1:nstrips
		result[i] = _graphbounds(datab, h, pitch, i)
	end
	return result
end

#Get bounding box of entire plot:
function plotbounds(lyt::PlotLayout, graphbb::BoundingBox)
	xmin = graphbb.xmin - lyt.halloc_left
	xmax = graphbb.xmax
	xmax += lyt.enable_legend ? lyt.halloc_legend : lyt.halloc_right
	ymin = graphbb.ymin - lyt.valloc_top
	ymax = graphbb.ymax + lyt.valloc_bottom
	return BoundingBox(xmin, xmax, ymin, ymax)
end

function plotbounds(lyt::PlotLayout, graphw::Float64, graphh::Float64)
	bb = plotbounds(lyt, BoundingBox(0, graphw, 0, graphh))
	return BoundingBox(0, width(bb), 0, height(bb))
end

#Get suggested plot bounds:
function plotbounds(lyt::PlotLayout, grid::PlotGrid)
	graphw = lyt.halloc_data; graphh = lyt.valloc_data
	if aspect_square(grid)
		graphw = graphh = min(graphw, graphh)
	end
	return plotbounds(lyt, graphw, graphh)
end

#Grid dimensions using Multiplot auto layout
function griddims_auto(mplot::Multiplot)
	nplots = length(mplot.subplots)
	ncols = mplot.layout.values.ncolumns
	nrows = div(nplots-1, ncols) + 1
	return (nrows, ncols)
end

#Computes suggested canvas size for a Multiplot object
function size_auto(mplot::Multiplot)
	#TODO: Compute more accurate size from Plot2D.plotbb
	nrows, ncols = griddims_auto(mplot)
	yoffset = mplot.layout.values.valloc_title
	w = Float64(mplot.layout.values.halloc_plot*ncols)
	h = Float64(mplot.layout.values.valloc_plot*nrows+yoffset)
	return (w, h)
end


#==Pre-processing display data
===============================================================================#

function _reduce(input::IWaveform, xext::PExtents1D, pdm::PointDropMatrix, xres_max::Integer)
	ds = droppoints(pdm, hasline(input), hasglyph(input)) ?
		_reduce(input.ds, xext, xres_max) : _reduce_nodrop(input.ds, xext, xres_max)

	return DWaveform(input.id, ds, input.line, input.glyph, input.ext, input.strip, input.visible, input.legendbb)
end

_reduce(inputlist::Vector{IWaveform}, xext::PExtents1D, pdm::PointDropMatrix, xres_max::Integer) =
	map((input)->_reduce(input, xext, pdm, xres_max), inputlist)

#Rescale input dataset:
#-------------------------------------------------------------------------------

map2axis(input::T, x::InputXfrm1DSpec, y::InputXfrm1DSpec) where T<:IDataset =
	T(map2axis(input.x, x), map2axis(input.y, y))

function map2axis(input::IWaveform, x::InputXfrm1DSpec, y::InputXfrm1DSpec)
	ds = map2axis(input.ds, x, y)
	return IWaveform(input.id, ds, input.line, input.glyph, getextents(ds), input.strip, input.visible, input.legendbb)
end

function map2axis(inputlist::Vector{IWaveform}, xflist::Vector{InputXfrm2D})
	n = length(inputlist) #WANTCONST
	nstrips = length(xflist) #WANTCONST
	emptyds = IDataset{true}([], []) #WANTCONST
	result = Vector{IWaveform}(undef, n)

	for i in 1:n
		input = inputlist[i]
		strip = input.strip
		if strip > 0 && strip <= nstrips
			result[i] = map2axis(input, xflist[strip].x, xflist[strip].y)
		else #No scale for this strip... return empty waveform
			result = IWaveform(input.id, emptyds, input.line, input.glyph, PExtents2D(), strip, input.visible, input.legendbb)
		end
	end
	return result
end

#Preprocess input dataset (rescale/reduce quantity of data/...):
#-------------------------------------------------------------------------------
#   (Updates display_data)
function preprocess_data(plot::Plot2D)
	#TODO: Find a way to preprocess x-vectors referencing same data only once?
	nstrips = length(plot.strips) #WANTCONST

	#Figure out required input data tranform for each strip:
	xflist = Vector{InputXfrm2D}(undef, nstrips)
	for i in 1:nstrips
		strip = plot.strips[i]

		#Need to take grid into account:
		xflist[i] = InputXfrm2D(plot.xscale, strip.yscale, strip.grid)
	end

	#Rescale data
	wfrmlist = map2axis(plot.data, xflist)

	for i in 1:nstrips
		strip = plot.strips[i]
		xf = InputXfrm2D(plot.xscale, strip.yscale)

		#Update extents:
		strip.ext_data = axis2read(getextents(wfrmlist, i), xf)
		_setyextents(strip, strip.yext) #Update extents, resolving any NaN fields.
	end

	#Extract maximum xextents from all strips:
	plot.xext_data = union([xvalues(strip.ext_data) for strip in plot.strips])
	_setxextents(plot, plot.xext) #Update extents, resolving any NaN fields.

	#Reduce data:
	xext = getxextents_axis(plot) #Read back extents, in transformed coordinates
	plot.display_data = _reduce(wfrmlist, xext, plot.pointdropmatrix, plot.xres)
	plot.invalid_ddata = false

	#NOTE: Rescaling before data reduction is somewhat inefficient, but makes
	#      it easier to interpolate data in _reduce step.
	#TODO: Find a way to efficiently reduce before re-scaling???
end


#==High-level display functions
===============================================================================#
function update_ddata(plot::Plot2D)
	invalidate_extents(plot) #Always refresh data
	#TODO: Conditionnaly compute (only when data changed/added)?

	refreshed = plot.invalid_ddata #Indicates if fn refreshed data
	if refreshed
		preprocess_data(plot)
	end
	return refreshed
end

#Last line
