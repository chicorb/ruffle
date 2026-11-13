package {
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.Loader;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.external.ExternalInterface;
	import flash.net.URLRequest;
	import flash.system.ApplicationDomain;
	import flash.system.LoaderContext;
	import flash.utils.getQualifiedClassName;

	// The same movie, with lazily initialized code, loaded twice into the same domain: the classes
	// of the first copy are used for everything, including the root of the second copy.
	public class Test extends Sprite {
		private var first:Loader = new Loader();
		private var second:Loader = new Loader();

		public function Test() {
			first.contentLoaderInfo.addEventListener(Event.COMPLETE, onFirst);
			first.load(new URLRequest("child.swf"), new LoaderContext(false, ApplicationDomain.currentDomain));
		}

		private function out(s:String):void {
			trace(s);
			if (ExternalInterface.available) {
				ExternalInterface.call("__out", s);
			}
		}

		private function onFirst(e:Event):void {
			out("first loaded: " + getQualifiedClassName(first.content));
			second.contentLoaderInfo.addEventListener(Event.COMPLETE, onSecond);
			second.load(new URLRequest("child.swf"), new LoaderContext(false, ApplicationDomain.currentDomain));
		}

		private function onSecond(e:Event):void {
			out("second loaded: " + getQualifiedClassName(second.content));
			out("same root class: " + (Object(first.content).constructor == Object(second.content).constructor));
			var a:Class = Class(first.contentLoaderInfo.applicationDomain.getDefinition("ChildClip"));
			var b:Class = Class(second.contentLoaderInfo.applicationDomain.getDefinition("ChildClip"));
			out("same ChildClip: " + (a == b) + ", same as here: " + (a == ApplicationDomain.currentDomain.getDefinition("ChildClip")));
			var c:Class = Class(ApplicationDomain.currentDomain.getDefinition("Child"));
			out("Child.constructed: " + c["constructed"]);
			var clip:DisplayObject = new b();
			addChild(clip);
			out("new ChildClip: " + clip.width + "x" + clip.height + " children=" + DisplayObjectContainer(clip).numChildren + " label=" + Object(clip).label);
			out("done");
		}
	}
}
