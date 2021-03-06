package away3d.materials.passes; 

import away3d.utils.ArrayUtils;
import openfl.errors.ArgumentError;
import openfl.errors.Error;
import away3d.animators.data.AnimationRegisterCache;
import away3d.animators.IAnimationSet;
import away3d.cameras.Camera3D;
import away3d.core.base.IRenderable;
import away3d.core.managers.AGALProgram3DCache;
import away3d.core.managers.Stage3DProxy;
import away3d.debug.Debug;
import away3d.errors.AbstractMethodError;
import away3d.materials.MaterialBase;
import away3d.materials.lightpickers.LightPickerBase;
import away3d.textures.Anisotropy;

import openfl.display.BlendMode;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DBlendFactor;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DTriangleFace;
import openfl.display3D.Program3D;
import openfl.display3D.textures.TextureBase;
import openfl.events.Event;
import openfl.events.EventDispatcher;
import openfl.geom.Matrix3D;
import openfl.geom.Rectangle;

class MaterialPassBase extends EventDispatcher {
	public var material(get_material, set_material):MaterialBase;
	public var writeDepth(get_writeDepth, set_writeDepth):Bool;
	public var mipmap(get_mipmap, set_mipmap):Bool;
	public var smooth(get_smooth, set_smooth):Bool;
	public var repeat(get_repeat, set_repeat):Bool;
	public var anisotropy(get_anisotropy, set_anisotropy):Anisotropy;
	public var bothSides(get_bothSides, set_bothSides):Bool;
	public var depthCompareMode(get_depthCompareMode, set_depthCompareMode):Context3DCompareMode;
	public var animationSet(get_animationSet, set_animationSet):IAnimationSet;
	public var renderToTexture(get_renderToTexture, never):Bool;
	public var numUsedStreams(get_numUsedStreams, never):Int;
	public var numUsedVertexConstants(get_numUsedVertexConstants, never):Int;
	public var numUsedVaryings(get_numUsedVaryings, never):Int;
	public var numUsedFragmentConstants(get_numUsedFragmentConstants, never):Int;
	public var needFragmentAnimation(get_needFragmentAnimation, never):Bool;
	public var needUVAnimation(get_needUVAnimation, never):Bool;
	public var lightPicker(get_lightPicker, set_lightPicker):LightPickerBase;
	public var alphaPremultiplied(get_alphaPremultiplied, set_alphaPremultiplied):Bool;

	private var _material:MaterialBase;
	private var _animationSet:IAnimationSet;
	public var _program3Ds:Array<Program3D>;
	public var _program3Dids:Array<Int>;
	private var _context3Ds:Array<Context3D>;
	
	// agal props. these NEED to be set by subclasses!
	// todo: can we perhaps figure these out manually by checking read operations in the bytecode, so other sources can be safely updated?
	private var _numUsedStreams:Int;
	private var _numUsedTextures:Int;
	private var _numUsedVertexConstants:Int;
	private var _numUsedFragmentConstants:Int;
	private var _numUsedVaryings:Int;
	private var _smooth:Bool;
	private var _repeat:Bool;
	private var _mipmap:Bool;
	private var _anisotropy:Anisotropy;
	private var _depthCompareMode:Context3DCompareMode;
	private var _blendFactorSource:Context3DBlendFactor;
	private var _blendFactorDest:Context3DBlendFactor;
	private var _enableBlending:Bool;
	private var _bothSides:Bool;
	private var _lightPicker:LightPickerBase;
	private var _animatableAttributes:Array<String>;
	private var _animationTargetRegisters:Array<String>;
	private var _shadedTarget:String;
	
	// keep track of previously rendered usage for faster cleanup of old vertex buffer streams and textures
	static private var _previousUsedStreams:Array<Int> = [ 0, 0, 0, 0, 0, 0, 0, 0 ];
	static private var _previousUsedTexs:Array<Int> = [ 0, 0, 0, 0, 0, 0, 0, 0 ];
	private var _defaultCulling:Context3DTriangleFace;
	private var _renderToTexture:Bool;
	
	// render state mementos for render-to-texture passes
	private var _oldTarget:TextureBase;
	private var _oldSurface:Int;
	private var _oldDepthStencil:Bool;
	private var _oldRect:Rectangle;
	private var _alphaPremultiplied:Bool;
	private var _needFragmentAnimation:Bool;
	private var _needUVAnimation:Bool;
	private var _UVTarget:String;
	private var _UVSource:String;
	private var _writeDepth:Bool;
	
	public var animationRegisterCache:AnimationRegisterCache;
	
	/**
	 * Creates a new MaterialPassBase object.
	 *
	 * @param renderToTexture Indicates whether this pass is a render-to-texture pass.
	 */
	public function new(renderToTexture:Bool = false)
	{
		super();
 
		_program3Ds = ArrayUtils.Prefill( new Array<Program3D>(), 8 ); 
		_program3Dids = [ -1, -1, -1, -1, -1, -1, -1, -1 ];
		_context3Ds = ArrayUtils.Prefill( new Array<Context3D>(), 8);
		_smooth = true;
		_repeat = false;
		_mipmap = true;
		_anisotropy = Anisotropy.ANISOTROPIC2X;
		_depthCompareMode = Context3DCompareMode.LESS_EQUAL;
		
		_blendFactorSource = Context3DBlendFactor.ONE;
		_blendFactorDest = Context3DBlendFactor.ZERO;

		_animatableAttributes = [ "va0" ];
		_animationTargetRegisters = [ "vt0" ];
		_shadedTarget = "ft0";
		
		_defaultCulling = Context3DTriangleFace.BACK;
		
		_writeDepth = true;

		_renderToTexture = renderToTexture;
		_numUsedStreams = 1;
		_numUsedVertexConstants = 5;
	}
	
	/**
	 * The material to which this pass belongs.
	 */ 
	public function get_material() : MaterialBase
	{
		return _material;
	}
	
	public function set_material(value:MaterialBase) : MaterialBase
	{
		_material = value;
		return _material;
	}
	
	/**
	 * Indicate whether this pass should write to the depth buffer or not. Ignored when blending is enabled.
	 */ 
	public function get_writeDepth() : Bool
	{
		return _writeDepth;
	}
	
	public function set_writeDepth(value:Bool) : Bool
	{
		_writeDepth = value;
		return _writeDepth;
	}
	
	/**
	 * Defines whether any used textures should use mipmapping.
	 */ 
	public function get_mipmap() : Bool
	{
		return _mipmap;
	}
	
	public function set_mipmap(value:Bool) : Bool
	{
		if (_mipmap == value)
			return _mipmap;
		_mipmap = value;
		invalidateShaderProgram();
		return _mipmap;
	}
	
    /**
     * Indicates the number of Anisotropic filtering samples to take for mipmapping
     */
    public function get_anisotropy():Anisotropy {
        return _anisotropy;
    }

    public function set_anisotropy(value:Anisotropy):Anisotropy {
        if (_anisotropy == value)
        	return _anisotropy;
        _anisotropy = value;
        invalidateShaderProgram();
        return _anisotropy;
    }

	/**
	 * Defines whether smoothing should be applied to any used textures.
	 */ 
	public function get_smooth() : Bool
	{
		return _smooth;
	}
	
	public function set_smooth(value:Bool) : Bool
	{
		if (_smooth == value)
			return _smooth;
		_smooth = value;
		invalidateShaderProgram();
		return _smooth;
	}
	
	/**
	 * Defines whether textures should be tiled.
	 */ 
	public function get_repeat() : Bool
	{
		return _repeat;
	}
	
	public function set_repeat(value:Bool) : Bool
	{
		if (_repeat == value)
			return _repeat;
		_repeat = value;
		invalidateShaderProgram();
		return _repeat;
	}
	
	/**
	 * Defines whether or not the material should perform backface culling.
	 */ 
	public function get_bothSides() : Bool
	{
		return _bothSides;
	}
	
	public function set_bothSides(value:Bool) : Bool
	{
		_bothSides = value;
		return _bothSides;
	}

	/**
	 * The depth compare mode used to render the renderables using this material.
	 *
	 * @see openfl.display3D.Context3DCompareMode
	 */ 
	public function get_depthCompareMode() : Context3DCompareMode
	{
		return _depthCompareMode;
	}
	
	public function set_depthCompareMode(value:Context3DCompareMode) : Context3DCompareMode
	{
		_depthCompareMode = value;
		return _depthCompareMode;
	}

	/**
	 * Returns the animation data set adding animations to the material.
	 */ 
	public function get_animationSet() : IAnimationSet
	{
		return _animationSet;
	}
	
	public function set_animationSet(value:IAnimationSet) : IAnimationSet
	{
		if (_animationSet == value)
			return _animationSet;
		
		_animationSet = value;
		
		invalidateShaderProgram();
		return _animationSet;
	}
	
	/**
	 * Specifies whether this pass renders to texture
	 */ 
	public function get_renderToTexture() : Bool
	{
		return _renderToTexture;
	}
	
	/**
	 * Cleans up any resources used by the current object.
	 * @param deep Indicates whether other resources should be cleaned up, that could potentially be shared across different instances.
	 */
	public function dispose():Void
	{
		if (_lightPicker!=null)
			_lightPicker.removeEventListener(Event.CHANGE, onLightsChange);
		
		// For loop conversion - 						for (var i:UInt = 0; i < 8; ++i)
		
		var i:UInt = 0;
		
		for (i in 0...8) {
			if (_program3Ds[i]!=null) {
				AGALProgram3DCache.getInstanceFromIndex(i).freeProgram3D(_program3Dids[i]);
				_program3Ds[i] = null;
			}
		}
	}
	
	/**
	 * The amount of used vertex streams in the vertex code. Used by the animation code generation to know from which index on streams are available.
	 */ 
	public function get_numUsedStreams() : UInt
	{
		return _numUsedStreams;
	}
	
	/**
	 * The amount of used vertex constants in the vertex code. Used by the animation code generation to know from which index on registers are available.
	 */ 
	public function get_numUsedVertexConstants() : UInt
	{
		return _numUsedVertexConstants;
	}
	 
	
	public function get_numUsedVaryings() : UInt
	{
		return _numUsedVaryings;
	}

	/**
	 * The amount of used fragment constants in the fragment code. Used by the animation code generation to know from which index on registers are available.
	 */ 
	public function get_numUsedFragmentConstants() : UInt
	{
		return _numUsedFragmentConstants;
	}
	 
	
	public function get_needFragmentAnimation() : Bool
	{
		return _needFragmentAnimation;
	}

	/**
	 * Indicates whether the pass requires any UV animatin code.
	 */ 
	public function get_needUVAnimation() : Bool
	{
		return _needUVAnimation;
	}
	
	/**
	 * Sets up the animation state. This needs to be called before render()
	 *
	 * @private
	 */
	public function updateAnimationState(renderable:IRenderable, stage3DProxy:Stage3DProxy, camera:Camera3D):Void
	{
		renderable.animator.setRenderState(stage3DProxy, renderable, _numUsedVertexConstants, _numUsedStreams, camera);
	}
	
	/**
	 * Renders an object to the current render target.
	 *
	 * @private
	 */
	public function render(renderable:IRenderable, stage3DProxy:Stage3DProxy, camera:Camera3D, viewProjection:Matrix3D):Void
	{
		throw new AbstractMethodError();
	}

	/**
	 * Returns the vertex AGAL code for the material.
	 */
	public function getVertexCode():String
	{
		throw new AbstractMethodError();
		return "";
	}

	/**
	 * Returns the fragment AGAL code for the material.
	 */
	public function getFragmentCode(fragmentAnimatorCode:String):String
	{
		throw new AbstractMethodError();
		return "";
	}

	/**
	 * The blend mode to use when drawing this renderable. The following blend modes are supported:
	 * <ul>
	 * <li>BlendMode.NORMAL: No blending, unless the material inherently needs it</li>
	 * <li>BlendMode.LAYER: Force blending. This will draw the object the same as NORMAL, but without writing depth writes.</li>
	 * <li>BlendMode.MULTIPLY</li>
	 * <li>BlendMode.ADD</li>
	 * <li>BlendMode.ALPHA</li>
	 * </ul>
	 */
	public function setBlendMode(value:BlendMode):Void
	{
		switch (value) {
			case BlendMode.NORMAL:
				_blendFactorSource = Context3DBlendFactor.ONE;
				_blendFactorDest = Context3DBlendFactor.ZERO;
				_enableBlending = false;
			case BlendMode.LAYER:
				_blendFactorSource = Context3DBlendFactor.SOURCE_ALPHA;
				_blendFactorDest = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;
				_enableBlending = true;
			case BlendMode.MULTIPLY:
				_blendFactorSource = Context3DBlendFactor.ZERO;
				_blendFactorDest = Context3DBlendFactor.SOURCE_COLOR;
				_enableBlending = true;
			case BlendMode.ADD:
				_blendFactorSource = Context3DBlendFactor.SOURCE_ALPHA;
				_blendFactorDest = Context3DBlendFactor.ONE;
				_enableBlending = true;
			case BlendMode.ALPHA:
				_blendFactorSource = Context3DBlendFactor.ZERO;
				_blendFactorDest = Context3DBlendFactor.SOURCE_ALPHA;
				_enableBlending = true;
			default:
				throw new Error("Unsupported blend mode!");  
		}
	}

	/**
	 * Sets the render state for the pass that is independent of the rendered object. This needs to be called before
	 * calling renderPass. Before activating a pass, the previously used pass needs to be deactivated.
	 * @param stage3DProxy The Stage3DProxy object which is currently used for rendering.
	 * @param camera The camera from which the scene is viewed.
	 * @private
	 */
	public function activate(stage3DProxy:Stage3DProxy, camera:Camera3D):Void
	{
		var contextIndex:Int = stage3DProxy._stage3DIndex;
		var context:Context3D = stage3DProxy._context3D;
		
		context.setDepthTest(_writeDepth && !_enableBlending, _depthCompareMode);
		if (_enableBlending)
			context.setBlendFactors(_blendFactorSource, _blendFactorDest);

		
		if ( _context3Ds[contextIndex] != context || _program3Ds[contextIndex]==null) {
			_context3Ds[contextIndex] = context;
			updateProgram(stage3DProxy);
			dispatchEvent(new Event(Event.CHANGE));
		}
		
		var prevUsed:Int = _previousUsedStreams[contextIndex];
		// For loop conversion - 			for (i = _numUsedStreams; i < prevUsed; ++i)
		for (i in _numUsedStreams...prevUsed)
			context.setVertexBufferAt(i, null);
		
		prevUsed = _previousUsedTexs[contextIndex];
		// For loop conversion - 						for (i = _numUsedTextures; i < prevUsed; ++i)			
		for (i in _numUsedTextures...prevUsed)
			context.setTextureAt(i, null);
		
		if (_animationSet!=null && !_animationSet.usesCPU)
			_animationSet.activate(stage3DProxy, this);
		
		context.setProgram(_program3Ds[contextIndex]);

		context.setCulling(_bothSides ? Context3DTriangleFace.NONE : _defaultCulling);
		
		if (_renderToTexture) {
			_oldTarget = stage3DProxy.renderTarget;
			_oldSurface = stage3DProxy.renderSurfaceSelector;
			_oldDepthStencil = stage3DProxy.enableDepthAndStencil;
			_oldRect = stage3DProxy.scissorRect;
		}
	}

	/**
	 * Clears the render state for the pass. This needs to be called before activating another pass.
	 * @param stage3DProxy The Stage3DProxy used for rendering
	 *
	 * @private
	 */
	public function deactivate(stage3DProxy:Stage3DProxy):Void
	{
		var index:UInt = stage3DProxy._stage3DIndex;
		_previousUsedStreams[index] = _numUsedStreams;
		_previousUsedTexs[index] = _numUsedTextures;
		
		if (_animationSet!=null && !_animationSet.usesCPU)
			_animationSet.deactivate(stage3DProxy, this);
		
		if (_renderToTexture) {
			// kindly restore state
			stage3DProxy.setRenderTarget(_oldTarget, _oldDepthStencil, _oldSurface);
			stage3DProxy.scissorRect = _oldRect;
		}
		
		stage3DProxy._context3D.setDepthTest(true, Context3DCompareMode.LESS_EQUAL);
	}
	
	/**
	 * Marks the shader program as invalid, so it will be recompiled before the next render.
	 *
	 * @param updateMaterial Indicates whether the invalidation should be performed on the entire material. Should always pass "true" unless it's called from the material itself.
	 */
	public function invalidateShaderProgram(updateMaterial:Bool = true):Void
	{
		// For loop conversion - 			for (var i:UInt = 0; i < 8; ++i)
		var i:UInt = 0;
		for (i in 0...8)
			_program3Ds[i] = null;
		
		if (_material!=null && updateMaterial)
			_material.invalidatePasses(this);
	}
	
	/**
	 * Compiles the shader program.
	 * @param polyOffsetReg An optional register that contains an amount by which to inflate the model (used in single object depth map rendering).
	 */
	public function updateProgram(stage3DProxy:Stage3DProxy):Void
	{
		var animatorCode:String = "";
		var UVAnimatorCode:String = "";
		var fragmentAnimatorCode:String = "";
		var vertexCode:String = getVertexCode();
		
		if (_animationSet!=null && !_animationSet.usesCPU) {
			animatorCode = _animationSet.getAGALVertexCode(this, _animatableAttributes, _animationTargetRegisters, stage3DProxy.profile);
			if (_needFragmentAnimation)
				fragmentAnimatorCode = _animationSet.getAGALFragmentCode(this, _shadedTarget, stage3DProxy.profile);
			if (_needUVAnimation)
				UVAnimatorCode = _animationSet.getAGALUVCode(this, _UVSource, _UVTarget);
			_animationSet.doneAGALCode(this);
		} else {
			var len:UInt = _animatableAttributes.length;
			
			// simply write attributes to targets, do not animate them
			// projection will pick up on targets[0] to do the projection
			// For loop conversion - 				for (var i:UInt = 0; i < len; ++i)
			var i:UInt = 0;
			for (i in 0...len)
				animatorCode += "mov " + _animationTargetRegisters[i] + ", " + _animatableAttributes[i] + "\n";
			if (_needUVAnimation)
				UVAnimatorCode = "mov " + _UVTarget + "," + _UVSource + "\n";
		}
		
		vertexCode = animatorCode + UVAnimatorCode + vertexCode;
		var fragmentCode:String = getFragmentCode(fragmentAnimatorCode);

		if (Debug.active) {
			trace("Compiling AGAL Code:");
			trace("--------------------");
			trace(vertexCode);
			trace("--------------------");
			trace(fragmentCode);
		}
		AGALProgram3DCache.getInstance(stage3DProxy).setProgram3D(this, vertexCode, fragmentCode);
	}

	/**
	 * The light picker used by the material to provide lights to the material if it supports lighting.
	 *
	 * @see away3d.materials.lightpickers.LightPickerBase
	 * @see away3d.materials.lightpickers.StaticLightPicker
	 */ 
	public function get_lightPicker() : LightPickerBase
	{
		return _lightPicker;
	}
	
	public function set_lightPicker(value:LightPickerBase) : LightPickerBase
	{
		if (_lightPicker!=null)
			_lightPicker.removeEventListener(Event.CHANGE, onLightsChange);
		_lightPicker = value;
		if (_lightPicker!=null)
			_lightPicker.addEventListener(Event.CHANGE, onLightsChange);
		updateLights();
		return _lightPicker;
	}

	/**
	 * Called when the light picker's configuration changes.
	 */
	private function onLightsChange(event:Event):Void
	{
		updateLights();
	}

	/**
	 * Implemented by subclasses if the pass uses lights to update the shader.
	 */
	private function updateLights():Void
	{
	
	}

	/**
	 * Indicates whether visible textures (or other pixels) used by this material have
	 * already been premultiplied. Toggle this if you are seeing black halos around your
	 * blended alpha edges.
	 */ 
	public function get_alphaPremultiplied() : Bool
	{
		return _alphaPremultiplied;
	}
	
	public function set_alphaPremultiplied(value:Bool) : Bool
	{
		_alphaPremultiplied = value;
		invalidateShaderProgram(false);
		return _alphaPremultiplied;
	}
}

