extends RefCounted

## Small, bounded vector accents connect weapon intent to contact. They are
## attached to the acting weapon/target, never full-screen particle noise.
static func family(id: String, role: String) -> String:
	var named := {"CHR001":"shield", "CHR002":"blade", "CHR003":"rifle", "CHR004":"burst", "CHR005":"mortar", "CHR006":"prism", "CHR007":"seal", "CHR008":"heal", "ENM001":"claw", "ENM002":"rifle", "ENM003":"shield", "BOSS001":"siege"}
	if named.has(id): return str(named[id])
	return str({"GUARDIAN":"shield", "DEFENDER":"shield", "VANGUARD":"blade", "MELEE_RUSH":"claw", "ASSAULT":"rifle", "RANGED":"rifle", "ARTILLERY":"mortar", "AREA":"siege", "MEDIC":"heal", "HEALER":"heal", "SPECIALIST":"prism", "BUFFER":"seal"}.get(role,"seal"))

static func ellipse(c: CanvasItem, p: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var line := PackedVector2Array()
	for i in range(41):
		var a := TAU * float(i) / 40.0
		line.append(p + Vector2(cos(a), sin(a)) * radius)
	c.draw_polyline(line, color, width, true)

static func telegraph(c: CanvasItem, target: Vector2, style: String, elapsed: float, contact: float, hostile: bool, strength: float) -> void:
	if elapsed >= contact or elapsed < maxf(0.0,contact-.42): return
	var t := clampf(1.0-(contact-elapsed)/.42,0,1)
	var radius := (62.0 if style in ["mortar","siege"] else 35.0) * strength
	var color := Color("ff9464") if hostile else Color("7bdeed")
	color.a = .30 + .40 * t
	ellipse(c,target,Vector2(radius*(1.35-t*.35),radius*.30),color,2.0*strength)
	if style in ["mortar","siege"]:
		for i in range(4):
			var offset := Vector2.RIGHT.rotated(PI*.5*i)*radius
			c.draw_line(target+offset*.7,target+offset,color,2.0*strength,true)

static func action(c: CanvasItem, origin: Vector2, target: Vector2, style: String, elapsed: float, action_name: String, color: Color, strength: float) -> void:
	var ultimate := action_name == "ultimate"
	var melee := style in ["blade","claw","shield"]
	var release := (1.10 if melee else .82) if ultimate else (.40 if melee else .14)
	var age := elapsed-release
	var direction := (target-origin).normalized()
	if direction.length_squared()<.01: direction=Vector2.RIGHT
	var normal := Vector2(-direction.y,direction.x)
	var size := strength * (1.35 if ultimate else 1.0)
	if style in ["blade","claw"]:
		if age < -.06 or age > .22: return
		var t := clampf((age+.06)/.28,0,1)
		var radius := (68.0 if style=="blade" else 47.0)*size
		for slash in range(3 if style=="claw" else 1):
			var center := origin+direction*26.0*size+normal*(slash-1)*12.0*size
			var angle := direction.angle()-.95+t*1.20
			var arc := PackedVector2Array()
			for i in range(17):
				var a := angle+float(i)/16.0*.9
				arc.append(center+Vector2(cos(a),sin(a))*radius)
			var tint := color; tint.a = sin(t*PI)*.90
			c.draw_polyline(arc,tint,7.0*size,true)
			c.draw_polyline(arc,Color(1,.98,.88,tint.a),2.0*size,true)
	elif style in ["rifle","burst","mortar","siege"]:
		if age < 0 or age > .22: return
		var alpha := 1.0-age/.22
		var length := (43.0 if style in ["mortar","siege"] else 29.0)*size
		var flare := PackedVector2Array([origin-direction*5*size,origin+direction*length*.42+normal*11*size,origin+direction*length,origin+direction*length*.42-normal*11*size])
		c.draw_colored_polygon(flare,Color(color.r,color.g,color.b,alpha*.88))
		c.draw_line(origin,origin+direction*length,Color(1,.98,.90,alpha),4*size,true)
		if style=="burst":
			for i in range(3):
				var start := origin+direction*(age*620.0+i*26.0)*size
				c.draw_line(start,start+direction*21*size,Color(color.r,color.g,color.b,alpha*.7),3*size,true)
		elif style in ["mortar","siege"]:
			c.draw_arc(origin,12*size+age*80*size,0,TAU,24,Color(1,.78,.38,alpha*.6),3*size,true)
	elif style=="shield":
		if age < -.12 or age > .25: return
		var t := clampf((age+.12)/.37,0,1)
		var center := origin+direction*28*size
		var radius := 35*size*(.7+t*.6)
		c.draw_arc(center,radius,direction.angle()-1.1,direction.angle()+1.1,24,Color(color.r,color.g,color.b,sin(t*PI)*.9),8*size,true)
	else:
		if elapsed > release+.22: return
		var t := clampf(elapsed/maxf(.01,release),0,1)
		var radius := (18.0+16.0*t)*size
		var sides := 4 if style=="prism" else 6
		var ring := PackedVector2Array()
		for i in range(sides+1):
			var a := float(i)/sides*TAU+elapsed*1.5
			ring.append(origin+Vector2(cos(a),sin(a))*radius)
		c.draw_polyline(ring,Color(color.r,color.g,color.b,.3+t*.5),2.5*size,true)
		if style=="heal":
			c.draw_line(origin-normal*radius*.45,origin+normal*radius*.45,Color(.8,1,.9,.9),4*size,true)
			c.draw_line(origin-direction*radius*.45,origin+direction*radius*.45,Color(.8,1,.9,.9),4*size,true)

static func impact(c: CanvasItem, p: Vector2, style: String, t: float, color: Color, strength: float) -> void:
	var fade := 1.0-smoothstep(.15,1.0,t)
	var r := (22+48*t)*strength
	if style in ["blade","claw"]:
		for i in range(3 if style=="claw" else 2):
			var offset := Vector2((i-1)*13,0)*strength
			var dir := Vector2(.65,-.76 if i%2==0 else .76)
			c.draw_line(p+offset-dir*r,p+offset+dir*r,Color(color.r,color.g,color.b,fade),5*strength,true)
			c.draw_line(p+offset-dir*r*.7,p+offset+dir*r*.7,Color(1,.98,.90,fade),2*strength,true)
	elif style in ["mortar","siege"]:
		ellipse(c,p+Vector2(0,30*strength),Vector2(r*1.8,r*.36),Color(color.r,color.g,color.b,fade*.9),4*strength)
		for i in range(9):
			var direction := Vector2.RIGHT.rotated(float(i)/9*TAU)
			var tip := p+direction*r+Vector2(0,t*t*45*strength)
			c.draw_line(tip-direction*11*strength,tip,Color(1,.83,.56,fade),3*strength,true)
	elif style in ["rifle","burst"]:
		for i in range(5):
			var d := Vector2.RIGHT.rotated(float(i)*TAU/5+.35)
			c.draw_line(p+d*r*.15,p+d*r,Color(1,.96,.79,fade),2.5*strength,true)
	else:
		c.draw_arc(p,r,0,TAU,32,Color(color.r,color.g,color.b,fade),3*strength,true)
