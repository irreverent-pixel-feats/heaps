package h3d.impl;
import h3d.impl.Driver;

class LogDriver extends Driver {

	var d : Driver;
	var loggedShaders = new Map<Int,Bool>();
	var currentShader : hxsl.RuntimeShader;
	public var logLines : Array<String> = null;

	public function new( driver : Driver ) {
		this.d = driver;
		logEnable = true;
		driver.logEnable = true;
	}

	override function logImpl( str : String ) {
		if( logLines == null )
			d.logImpl(str);
		else
			logLines.push(str);
	}

	override function hasFeature( f : Feature ) {
		return d.hasFeature(f);
	}

	override function isDisposed() {
		return d.isDisposed();
	}

	override function dispose() {
		log('Dispose');
		d.dispose();
	}

	override function begin( frame : Int ) {
		log('Begin $frame');
		d.begin(frame);
	}

	override function clear( ?color : h3d.Vector, ?depth : Float, ?stencil : Int ) {
		log('Clear color=$color depth=$depth stencil=$stencil');
		d.clear(color, depth, stencil);
	}

	override function setCapture( bmp : hxd.BitmapData, callb : Void -> Void ) {
		log('SetCapture ${bmp.width}x${bmp.height}');
		d.setCapture(bmp, callb);
	}

	override function reset() {
		log('Reset');
		d.reset();
	}

	override function getDriverName( details : Bool ) {
		return d.getDriverName(details);
	}

	override function init( onCreate : Bool -> Void, forceSoftware = false ) {
		log('Init');
		d.init(function(b) {
			log('OnCreate $b');
			onCreate(b);
		},forceSoftware);
	}

	override function resize( width : Int, height : Int ) {
		log('Resize $width x $height');
		d.resize(width, height);
	}

	override function selectShader( shader : hxsl.RuntimeShader ) {
		log('Select shader #${shader.id}');
		currentShader = shader;
		var ret = d.selectShader(shader);
		if( !loggedShaders.get(shader.id) ) {
			function fmt( shader : hxsl.RuntimeShader.RuntimeShaderData ) {
				var str = hxsl.Printer.shaderToString(shader.data);
				str = ~/((fragment)|(vertex))Globals\[([0-9]+)\](.[xyz]+)?/g.map(str, function(r) {
					var name = null;
					var cid = Std.parseInt(r.matched(4)) << 2;
					var swiz = r.matched(5);
					if( swiz != null ) {
						var d = swiz.charCodeAt(1) - 'x'.code;
						cid += d;
						swiz = "." + [for( i in 1...swiz.length ) String.fromCharCode(swiz.charCodeAt(i) - d)].join("");
					}
					var g = shader.globals;
					while( g != null ) {
						if( g.path == "__consts__" && cid >= g.pos && cid < g.pos + (switch(g.type) { case TArray(TFloat, SConst(n)): n; default: 0; } ) && swiz == ".x" ) {
							swiz = null;
							name = "" + shader.consts[cid - g.pos];
							break;
						}
						if( g.pos == cid ) {
							name = g.path;
							break;
						}
						g = g.next;
					}
					if( name == null )
						return r.matched(0);
					if( swiz != null ) name += swiz;
					return name;
				});
				str = ~/((fragment)|(vertex))Params\[([0-9]+)\](.[xyz]+)?/g.map(str, function(r) {
					var name = null;
					var cid = Std.parseInt(r.matched(4)) << 2;
					var swiz = r.matched(5);
					if( swiz != null ) {
						var d = swiz.charCodeAt(1) - 'x'.code;
						cid += d;
						swiz = "." + [for( i in 1...swiz.length ) String.fromCharCode(swiz.charCodeAt(i) - d)].join("");
					}
					var p = shader.params;
					while( p != null ) {
						if( p.pos == cid ) {
							name = p.name;
							break;
						}
						p = p.next;
					}
					if( name == null )
						return r.matched(0);
					if( swiz != null ) name += swiz;
					return name;
				});
				str = ~/((fragment)|(vertex))Textures\[([0-9]+)\]/g.map(str, function(r) {
					var name = null;
					var cid = Std.parseInt(r.matched(4));
					var t = shader.textures2D;
					while( t != null ) {
						if( t.pos == cid )
							return t.name;
						t = t.next;
					}
					return r.matched(0);
				});
				str = ~/((fragment)|(vertex))TexturesCube\[([0-9]+)\]/g.map(str, function(r) {
					var name = null;
					var cid = Std.parseInt(r.matched(4));
					var t = shader.texturesCube;
					while( t != null ) {
						if( t.pos == cid )
							return t.name;
						t = t.next;
					}
					return r.matched(0);
				});
				return str;
			}
			var str = fmt(shader.vertex) + "\n" + fmt(shader.fragment);
			log('');
			log('HXSL=');
			log("\t" + str.split("\n").join("\n\t"));
			var str = getNativeShaderCode(shader);
			if( str != null ) {
				log('NATIVE=');
				log("\t" + str.split("\n").join("\n\t"));
			}
			log('');
			loggedShaders.set(shader.id, true);
		}
		return ret;
	}

	override function getNativeShaderCode( shader ) {
		return d.getNativeShaderCode(shader);
	}

	override function selectMaterial( pass : h3d.mat.Pass ) {
		log('Select Material Cull=${pass.culling} depth=${pass.depthTest}${pass.depthWrite ? "" : " nowrite"} blend=${pass.blendSrc},${pass.blendDst} color=${pass.colorMask}');
		d.selectMaterial(pass);
	}

	function sizeOf( t : hxsl.Ast.Type ) {
		return switch( t ) {
		case TVoid: 0;
		case TInt, TFloat: 1;
		case TVec(n, _): n;
		case TMat4: 16;
		case TMat3: 9;
		case TMat3x4: 12;
		case TArray(t, SConst(n)): sizeOf(t) * n;
		default: throw "assert " + t;
		}
	}

	override function uploadShaderBuffers( buffers : h3d.shader.Buffers, which : h3d.shader.Buffers.BufferKind ) {
		switch( which ) {
		case Globals:
			inline function logVars( s : hxsl.RuntimeShader.RuntimeShaderData, buf : h3d.shader.Buffers.ShaderBuffers ) {
				if( s.globalsSize == 0 ) return;
				log('Upload ' + (s.vertex?"vertex":"fragment") + " globals");
				var g = s.globals;
				while( g != null ) {
					log('\t@${g.pos} ' + g.path + '=' + [for( i in 0...sizeOf(g.type) ) hxd.Math.fmt(buf.globals.toData()[g.pos + i])]);
					g = g.next;
				}
			}
			logVars(currentShader.vertex, buffers.vertex);
			logVars(currentShader.fragment, buffers.fragment);
		case Params:
			inline function logVars( s : hxsl.RuntimeShader.RuntimeShaderData, buf : h3d.shader.Buffers.ShaderBuffers ) {
				if( s.paramsSize == 0 ) return;
				log('Upload ' + (s.vertex?"vertex":"fragment") + " params");
				var p = s.params;
				while( p != null ) {
					var pos = p.pos;
					#if flash
					pos += s.globalsSize * 4;
					#end
					log('\t@$pos ' + p.name + '=' + [for( i in 0...sizeOf(p.type) ) hxd.Math.fmt(buf.params.toData()[p.pos + i])]);
					p = p.next;
				}
			}
			logVars(currentShader.vertex, buffers.vertex);
			logVars(currentShader.fragment, buffers.fragment);
		case Textures:
			inline function logVars( s : hxsl.RuntimeShader.RuntimeShaderData, buf : h3d.shader.Buffers.ShaderBuffers ) {
				var t = s.textures2D;
				while( t != null ) {
					log('Set ${s.vertex ? "Vertex" : "Fragment"} Texture@${t.pos} ' + t.name+"=" + (buf.tex.length <= t.pos ? 'OUT OF BOUNDS' : '' + buf.tex[t.pos]));
					t = t.next;
				}
				t = s.texturesCube;
				while( t != null ) {
					log('Set ${s.vertex ? "Vertex" : "Fragment"} TextureCube@${t.pos} ' + t.name+"=" + (buf.tex.length <= t.pos ? 'OUT OF BOUNDS' : '' + buf.tex[t.pos + s.textures2DCount]));
					t = t.next;
				}
			}
			logVars(currentShader.vertex, buffers.vertex);
			logVars(currentShader.fragment, buffers.fragment);
		}
		d.uploadShaderBuffers(buffers, which);
	}

	override function getShaderInputNames() : Array<String> {
		return d.getShaderInputNames();
	}

	override function selectBuffer( buffer : Buffer ) {
		log('SelectBuffer');
		d.selectBuffer(buffer);
	}

	override function selectMultiBuffers( buffers : Buffer.BufferOffset ) {
		log('SelectMultiBuffers');
		d.selectMultiBuffers(buffers);
	}

	override function draw( ibuf : IndexBuffer, startIndex : Int, ntriangles : Int ) {
		log('Draw $ntriangles');
		d.draw(ibuf, startIndex, ntriangles);
	}

	override function setRenderZone( x : Int, y : Int, width : Int, height : Int ) {
		log('SetRenderZone [$x $y $width $height]');
		d.setRenderZone(x, y, width, height);
	}

	override function setRenderTarget( tex : Null<h3d.mat.Texture> ) {
		log('SetRenderTarget $tex');
		d.setRenderTarget(tex);
	}

	override function present() {
		log('Present');
		d.present();
	}

	override function setDebug( b : Bool ) {
		log('SetDebug $b');
		d.setDebug(b);
	}

	override function allocTexture( t : h3d.mat.Texture ) : Texture {
		log('AllocTexture $t');
		return d.allocTexture(t);
	}

	override function allocIndexes( count : Int ) : IndexBuffer {
		log('AllocIndexes $count');
		return d.allocIndexes(count);
	}

	override function allocVertexes( m : ManagedBuffer ) : VertexBuffer {
		log('AllocVertexes size=${m.size} stride=${m.stride}');
		return d.allocVertexes(m);
	}

	override function disposeTexture( t : Texture ) {
		log('Dispose texture');
		d.disposeTexture(t);
	}

	override function disposeIndexes( i : IndexBuffer ) {
		log('DisposeIndexes');
		d.disposeIndexes(i);
	}

	override function disposeVertexes( v : VertexBuffer ) {
		log('DisposeIndexes');
		d.disposeVertexes(v);
	}

	override function uploadIndexBuffer( i : IndexBuffer, startIndice : Int, indiceCount : Int, buf : hxd.IndexBuffer, bufPos : Int ) {
		log('UploadIndexBuffer');
		d.uploadIndexBuffer(i, startIndice, indiceCount, buf, bufPos);
	}

	override function uploadIndexBytes( i : IndexBuffer, startIndice : Int, indiceCount : Int, buf : haxe.io.Bytes , bufPos : Int ) {
		log('UploadIndexBytes');
		d.uploadIndexBytes(i, startIndice, indiceCount, buf, bufPos);
	}

	override function uploadVertexBuffer( v : VertexBuffer, startVertex : Int, vertexCount : Int, buf : hxd.FloatBuffer, bufPos : Int ) {
		log('UploadVertexBuffer');
		d.uploadVertexBuffer(v, startVertex, vertexCount, buf, bufPos);
	}

	override function uploadVertexBytes( v : VertexBuffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
		log('UploadVertexBytes');
		d.uploadVertexBytes(v, startVertex, vertexCount, buf, bufPos);
	}

	override function uploadTextureBitmap( t : h3d.mat.Texture, bmp : hxd.BitmapData, mipLevel : Int, side : Int ) {
		log('UploadTextureBitmap $t mip=$mipLevel side=$side');
		d.uploadTextureBitmap(t, bmp, mipLevel, side);
	}

	override function uploadTexturePixels( t : h3d.mat.Texture, pixels : hxd.Pixels, mipLevel : Int, side : Int ) {
		log('UploadTexturePixels $t mip=$mipLevel side=$side');
		d.uploadTexturePixels(t, pixels, mipLevel, side);
	}

}