package {
	import flash.display.Sprite;
	import flash.external.ExternalInterface;

	// Document class of the child movie.
	public class Child extends Sprite {
		public static var constructed:int = 0;

		public function Child() {
			constructed++;
			var s:String = "Child constructed (" + constructed + "), helper says " + new Helper().hello();
			trace(s);
			if (ExternalInterface.available) {
				ExternalInterface.call("__out", s);
			}
		}
	}
}

// A class in a namespace private to this file.
class Helper {
	public function hello():String {
		return "hello";
	}
}
