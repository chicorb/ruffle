package {
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.Loader;
	import flash.display.LoaderInfo;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.external.ExternalInterface;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.utils.ByteArray;
	import flash.utils.getQualifiedClassName;

	// Movies loaded by a Loader must keep working while something still uses them, even after
	// the garbage collector ran many times and the Loader itself is gone:
	// - "instance": only an instance of a library symbol of the child is kept (on stage);
	// - "class": only the class linked to that symbol is kept, and instantiated later.
	public class Test extends Sprite {
		private var keptInstance:DisplayObject;
		private var keptClass:Class;
		private var loaded:int = 0;
		private var frames:int = 0;
		private var garbage:Object;

		public function Test() {
			var loader:Loader = new Loader();
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, onInstanceLoaded);
			loader.load(new URLRequest("child.swf"));

			var bytesLoader:URLLoader = new URLLoader();
			bytesLoader.dataFormat = URLLoaderDataFormat.BINARY;
			bytesLoader.addEventListener(Event.COMPLETE, onBytes);
			bytesLoader.load(new URLRequest("child.swf"));
		}

		private function out(s:String):void {
			trace(s);
			if (ExternalInterface.available) {
				ExternalInterface.call("__out", s);
			}
		}

		private function describe(what:String, o:DisplayObject):void {
			out(what + ": " + getQualifiedClassName(o) + " " + o.width + "x" + o.height +
				" children=" + DisplayObjectContainer(o).numChildren + " label=" + Object(o).label);
		}

		private function onInstanceLoaded(e:Event):void {
			var info:LoaderInfo = LoaderInfo(e.target);
			var cls:Class = Class(info.applicationDomain.getDefinition("ChildClip"));
			keptInstance = new cls();
			addChild(keptInstance);
			started();
		}

		private function onBytes(e:Event):void {
			var loader:Loader = new Loader();
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, onClassLoaded);
			loader.loadBytes(ByteArray(URLLoader(e.target).data));
		}

		private function onClassLoaded(e:Event):void {
			var info:LoaderInfo = LoaderInfo(e.target);
			keptClass = Class(info.applicationDomain.getDefinition("ChildClip"));
			started();
		}

		private function started():void {
			loaded++;
			if (loaded == 2) {
				// The two loads finish in any order.
				describe("instance, before", keptInstance);
				describe("class, before", new keptClass());
				addEventListener(Event.ENTER_FRAME, churn);
			}
		}

		private function churn(e:Event):void {
			// Garbage, so that the garbage collector runs several times.
			for (var i:int = 0; i < 20000; i++) {
				garbage = [i, {value: i}, "item " + i];
			}
			frames++;
			if (frames == 60) {
				removeEventListener(Event.ENTER_FRAME, churn);
				describe("instance, after", keptInstance);
				describe("class, after", new keptClass());
				out("done");
			}
		}
	}
}
