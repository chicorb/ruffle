package {
	import flash.display.Sprite;
	import flash.external.ExternalInterface;

	public class Test extends Sprite {
		public function Test() {
			out("// read inside try/catch");
			try {
				out(ExternalInterface.marshallExceptions);
			} catch (e:Error) {
				out("caught: " + e);
			}

			out("// write inside try/catch");
			try {
				ExternalInterface.marshallExceptions = true;
				out("no error");
			} catch (e:Error) {
				out("caught: " + e);
			}
			ExternalInterface.marshallExceptions = false;

			out("// default value");
			out(ExternalInterface.marshallExceptions);

			out("// typeof");
			out(typeof ExternalInterface.marshallExceptions);

			out("// = true");
			ExternalInterface.marshallExceptions = true;
			out(ExternalInterface.marshallExceptions);

			out("// = false");
			ExternalInterface.marshallExceptions = false;
			out(ExternalInterface.marshallExceptions);

			out("// = 1");
			ExternalInterface.marshallExceptions = 1;
			out(ExternalInterface.marshallExceptions);

			out("// = null");
			ExternalInterface.marshallExceptions = null;
			out(ExternalInterface.marshallExceptions);

			out("// = \"yes\"");
			ExternalInterface.marshallExceptions = "yes";
			out(ExternalInterface.marshallExceptions);

			ExternalInterface.marshallExceptions = false;
			out("// done");
		}

		// Also reports through ExternalInterface when it's available, so the same SWF
		// can be checked in a browser with Flash Player (trace() is a no-op there).
		private function out(value:*):void {
			trace(value);
			if (ExternalInterface.available) {
				ExternalInterface.call("__out", String(value));
			}
		}
	}
}
