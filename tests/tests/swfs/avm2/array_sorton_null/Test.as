package {
import flash.display.Sprite;
import flash.events.TimerEvent;
import flash.external.ExternalInterface;
import flash.utils.Timer;

// Array.sortOn with null and undefined elements: Flash Player moves them to the end
// instead of failing.
public class Test extends Sprite {
    public function Test() {
        // Wait a bit so that the output also reaches the page in the browser plugin.
        var t:Timer = new Timer(500, 1);
        t.addEventListener(TimerEvent.TIMER, run);
        t.start();
    }

    private function out(s:String):void {
        trace(s);
        if (ExternalInterface.available) {
            ExternalInterface.call("__out", s);
        }
    }

    private function names(a:Array):String {
        var r:Array = [];
        for each (var o:* in a) {
            r.push(o === null ? "<null>" : o === undefined ? "<undefined>" : String(o.n));
        }
        return r.join(",");
    }

    private function test(label:String, a:Array, options:* = 0, field:* = "v"):void {
        try {
            var r:* = a.sortOn(field, options);
            out(label + ": " + names(a) + (r is Array ? " returned " + (r === a ? "the array" : r.join(",")) : " returned " + r));
        } catch (e:Error) {
            out(label + ": error " + e.errorID);
        }
    }

    private function run(e:TimerEvent):void {
        test("null", [{n: "b", v: "b"}, null, {n: "a", v: "a"}]);
        test("null first", [null, {n: "b", v: "b"}, {n: "a", v: "a"}]);
        test("two nulls", [{n: "b", v: "b"}, null, {n: "a", v: "a"}, null]);
        test("null and undefined", [undefined, {n: "b", v: "b"}, null, {n: "a", v: "a"}]);
        test("null DESCENDING", [{n: "a", v: "a"}, null, {n: "b", v: "b"}], Array.DESCENDING);
        test("null NUMERIC", [{n: "2", v: 2}, null, {n: "1", v: 1}], Array.NUMERIC);
        test("null UNIQUESORT", [{n: "b", v: "b"}, null, {n: "a", v: "a"}], Array.UNIQUESORT);
        test("two nulls UNIQUESORT", [{n: "b", v: "b"}, null, null], Array.UNIQUESORT);
        test("null RETURNINDEXEDARRAY", [{n: "b", v: "b"}, null, {n: "a", v: "a"}], Array.RETURNINDEXEDARRAY);
        test("null two fields", [{n: "b", g: "x", v: "b"}, null, {n: "a", g: "x", v: "a"}], 0, ["g", "v"]);
    }
}
}
