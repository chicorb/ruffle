package {
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.external.ExternalInterface;

	// Listeners added with useWeakReference = true must keep working while their function is
	// alive: a method lives as long as its object. Once nothing else references the object, the
	// listener goes away with it, after the garbage collector ran.
	public class Test extends Sprite {
		private var dispatcher:EventDispatcher = new EventDispatcher();
		private var keptReceiver:Receiver;
		private var removedReceiver:Receiver;
		private var keptClosure:Function;
		private var frames:int = 0;
		private var garbage:Object;

		public function Test() {
			keptReceiver = new Receiver("kept receiver", out);
			dispatcher.addEventListener("ping", keptReceiver.onPing, false, 0, true);

			keptClosure = function(e:Event):void {
				out("kept weak closure got " + e.type);
			};
			dispatcher.addEventListener("ping", keptClosure, false, 0, true);

			dispatcher.addEventListener("ping", function(e:Event):void {
				out("strong closure got " + e.type);
			});

			removedReceiver = new Receiver("removed receiver", out);
			dispatcher.addEventListener("ping", removedReceiver.onPing, false, 0, true);
			dispatcher.removeEventListener("ping", removedReceiver.onPing);

			// Same listener again, now strong: ignored, it is already registered.
			dispatcher.addEventListener("ping", keptReceiver.onPing);

			out("before: hasEventListener " + dispatcher.hasEventListener("ping"));
			dispatcher.dispatchEvent(new Event("ping"));

			// Only referenced by its weak listener (after the first dispatch: when it is collected
			// depends on when the collector runs).
			var unreferenced:Receiver = new Receiver("unreferenced receiver", out);
			dispatcher.addEventListener("ping", unreferenced.onPing, false, 0, true);
			unreferenced = null;

			addEventListener(Event.ENTER_FRAME, churn);
		}

		private function out(s:String):void {
			trace(s);
			if (ExternalInterface.available) {
				ExternalInterface.call("__out", s);
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
				out("after: hasEventListener " + dispatcher.hasEventListener("ping"));
				dispatcher.dispatchEvent(new Event("ping"));
				dispatcher.removeEventListener("ping", keptReceiver.onPing);
				dispatcher.removeEventListener("ping", keptClosure);
				out("removed: dispatching again");
				dispatcher.dispatchEvent(new Event("ping"));
				out("done");
			}
		}
	}
}

class Receiver {
	private var name:String;
	private var out:Function;

	public function Receiver(name:String, out:Function) {
		this.name = name;
		this.out = out;
	}

	public function onPing(e:Object):void {
		out(name + " got " + e.type);
	}
}
