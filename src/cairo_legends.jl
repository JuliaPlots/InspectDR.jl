#InspectDR: Draw legends with Cairo layer.
#-------------------------------------------------------------------------------


#==
===============================================================================#

#NOTE: linelength & textoffset are absolute values
function legend_renderitem(ctx::CairoContext, wfrm::IWaveform, x::Float64, y::Float64,
	linelength::Float64, textoffset::Float64)
	linestart = x+textoffset
	lineend = linestart+linelength
	if wfrm.visible
Cairo.save(ctx)
		setlinestyle(ctx, LineStyle(wfrm.line))
		drawline(ctx, Point2D(linestart, y), Point2D(lineend, y))
		drawglyph_safe(ctx, wfrm, Point2D(linestart+linelength/2, y))
Cairo.restore(ctx)
	end
	x = lineend+textoffset #Compute new x
	render(ctx, wfrm.id, Point2D(x, y), align=ALIGN_VCENTER|ALIGN_LEFT)
end

function legend_render(canvas::PCanvas2D, plot::Plot2D, istrip::Int)
	ctx = canvas.ctx #WANTCONST
	lyt = plot.layout.values #WANTCONST

	xleft = canvas.bb.xmax - lyt.halloc_legend
	bb = BoundingBox(xleft, canvas.bb.xmax, canvas.graphbb.ymin, canvas.graphbb.ymin)
	Cairo.save(canvas.ctx)
	drawrectangle(ctx, bb, lyt.frame_legend)
	Cairo.restore(canvas.ctx)

	Cairo.save(canvas.ctx)
	setfont(ctx, lyt.font_legend)
	(w, h) = text_dims(Cairo.text_extents(ctx, "M"))
	ypitch = h*(1+lyt.valloc_legenditemsp)

	#Compute absolute values:
	textoffset = lyt.hoffset_legendtext*w

	y = canvas.graphbb.ymin + h/2
	for d in plot.data
		if d.strip != istrip; continue; end
		if "" == d.id; continue; end
		legend_renderitem(ctx, d, xleft, y, lyt.halloc_legendlineseg, textoffset)
		d.legendbb = BoundingBox(xleft, canvas.bb.xmax,y-h/2,y+h/2)
		y += ypitch
	end
	Cairo.restore(canvas.ctx)
end


#Last line
