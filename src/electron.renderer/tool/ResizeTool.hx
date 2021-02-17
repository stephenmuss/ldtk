package tool;

typedef ResizeRect = {
	var x: Int;
	var y: Int;
	var w: Int;
	var h: Int;
}

class ResizeTool extends Tool<Int> {
	static var DEFAULT_ALPHA = 0.75;
	static var HANDLE_RADIUS = 5;

	var draggedHandle: Null<RectHandlePos>;
	var dragOrigin : Coords;
	var g : h2d.Graphics;
	var ge: GenericLevelElement;
	var _handlePosIterator : Array<RectHandlePos>;

	var invalidated = true;
	var _rect : Null<ResizeRect>;
	var rect(get,never) : ResizeRect;


	public function new(ge:GenericLevelElement) {
		super();
		this.ge = ge;
		createRootInLayers(editor.levelRender.root, Const.DP_UI);
		g = new h2d.Graphics(root);
		g.alpha = DEFAULT_ALPHA;

		_handlePosIterator = RectHandlePos.getConstructors().map( k->RectHandlePos.createByName(k) );
		render();
	}

	function render() {
		g.clear();

		// Draw handles
		var c = 0xffcc00;
		g.beginFill(c,1);
		for(p in _handlePosIterator) {
			if( isHandleActive(p) )
				g.drawCircle(getHandleX(p), getHandleY(p), HANDLE_RADIUS*0.6, 16);
		}
	}

	inline function get_rect() {
		if( _rect==null )
			_rect = switch ge {
				case GridCell(li, cx, cy):
					{ x:cx*li.def.gridSize, y:cy*li.def.gridSize, w:li.def.gridSize, h:li.def.gridSize }

				case Entity(li, ei):
					{ x:ei.left, y:ei.top, w:ei.width, h:ei.height }

				case PointField(li, ei, fi, arrayIdx):
					var pt = fi.getPointGrid(arrayIdx);
					{ x:pt.cx*li.def.gridSize, y:pt.cy*li.def.gridSize, w:li.def.gridSize, h:li.def.gridSize }
			}
		return _rect;
	}

	function isHandleActive(p:RectHandlePos) {
		switch ge {
			case GridCell(li, cx, cy):
			case Entity(li, ei):
				if( !ei.def.resizableX )
					switch p {
						case Left,Right,TopLeft,TopRight,BottomLeft,BottomRight: return false;
						case _:
					}
				if( !ei.def.resizableY )
					switch p {
						case Top,Bottom,TopLeft,TopRight,BottomLeft,BottomRight: return false;
						case _:
					}

			case PointField(li, ei, fi, arrayIdx):
		}

		return switch p {
			case Top, Bottom: rect.w > HANDLE_RADIUS*2;
			case Left, Right: rect.h > HANDLE_RADIUS*2;
			case TopLeft, TopRight, BottomLeft, BottomRight: true;
		}
	}

	function getOveredHandle(m:Coords) : Null<RectHandlePos> {
		for(p in _handlePosIterator)
			if( isHandleActive(p) && M.dist(m.levelX, m.levelY, getHandleX(p), getHandleY(p) ) <= HANDLE_RADIUS )
				return p;
		return null;
	}

	function getHandleX(pos:RectHandlePos) : Float {
		return switch pos {
			case Top, Bottom: rect.x + rect.w*0.5;
			case Left, TopLeft, BottomLeft: rect.x - HANDLE_RADIUS;
			case Right, TopRight, BottomRight: rect.x + rect.w-1 + HANDLE_RADIUS;
		}
	}

	function getHandleY(pos:RectHandlePos) : Float {
		return switch pos {
			case Left,Right: rect.y + rect.h*0.5;
			case Top, TopLeft, TopRight: rect.y - HANDLE_RADIUS;
			case Bottom, BottomLeft, BottomRight: rect.y + rect.h + HANDLE_RADIUS;
		}
	}

	override function isRunning():Bool {
		return draggedHandle!=null;
	}

	override function startUsing(ev:hxd.Event, m:Coords) {
		super.startUsing(ev,m);
		curMode = null;

		ev.cancel = true;
		draggedHandle = getOveredHandle(m);
		if( draggedHandle==null ) {
			// Can happen if startUsing() is manually called (like while creating an Entity)
			switch ge {
				case GridCell(li, cx, cy):
				case Entity(li, ei):
					draggedHandle = ei.def.resizableX && ei.def.resizableY ? BottomRight
						: ei.def.resizableX ? Right
						: Bottom;

				case PointField(li, ei, fi, arrayIdx):
			}
		}

		dragOrigin = m;
	}

	override function stopUsing(m:Coords) {
		super.stopUsing(m);
		draggedHandle = null;
	}

	public function onMouseDown(ev:hxd.Event, m:Coords) {
		var p = getOveredHandle(m);
		if( p!=null )
			startUsing(ev, m);
	}

	override function onMouseMove(ev:hxd.Event, m:Coords) {
		super.onMouseMove(ev, m);

		if( !isRunning() ) {
			// Overing
			var p = getOveredHandle(m);
			if( p!=null ) {
				g.alpha = 1;
				ev.cancel = true;
				editor.cursor.set( Resize(p) );
			}
			else
				g.alpha = DEFAULT_ALPHA;
		}
		else {
			// Actual resizing
			ev.cancel = true;
			var snap = settings.v.grid ? editor.curLayerDef.gridSize : 1;

			// Width
			var newWid = switch draggedHandle {
				case Top, Bottom: rect.w;

				case Left, TopLeft, BottomLeft:
					(rect.x+rect.w) - HANDLE_RADIUS - m.levelX;

				case Right, TopRight, BottomRight:
					m.levelX - rect.x - HANDLE_RADIUS;
				}
			if( newWid!=rect.w )
				newWid = M.round(newWid/snap) * snap;

			// Height
			var newHei = switch draggedHandle {
				case Left, Right: rect.h;

				case Top, TopLeft, TopRight:
					(rect.y+rect.h) - HANDLE_RADIUS - m.levelY;

				case Bottom, BottomLeft, BottomRight:
					m.levelY - rect.y - HANDLE_RADIUS;
			}
			if( newHei!=rect.h )
				newHei = M.round(newHei/snap) * snap;

			// Apply new bounds
			switch ge {
				case GridCell(li, cx, cy):

				case Entity(li, ei):
					var oldW = ei.width;
					var oldH = ei.height;

					ei.customWidth = newWid;
					if( ei.customWidth<=ei.def.width ) ei.customWidth = null;

					ei.customHeight = newHei;
					if( ei.customHeight<=ei.def.height ) ei.customHeight = null;

					switch draggedHandle {
						case Left, TopLeft, BottomLeft: if( ei.def.pivotX==0 ) ei.x -= ( ei.width - oldW );
						case Right, TopRight, BottomRight: if( ei.def.pivotX==1 ) ei.x += ( ei.width - oldW );
						case _:
					}

					switch draggedHandle {
						case Top, TopLeft, TopRight: if( ei.def.pivotY==0 ) ei.y -= ( ei.height - oldH );
						case Bottom, BottomLeft, BottomRight: if( ei.def.pivotY==1 ) ei.y += ( ei.height - oldH );
						case _:
					}

					editor.ge.emit( EntityInstanceChanged(ei) );
					editor.selectionTool.invalidateRender();
					invalidate();

				case PointField(li, ei, fi, arrayIdx):
			}
			dragOrigin = m;
		}
	}

	public inline function invalidate() {
		invalidated = true;
	}

	override function postUpdate() {
		super.postUpdate();
		if( invalidated ) {
			_rect = null;
			render();
			invalidated = false;
		}
	}
}