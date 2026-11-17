package {
import flash.display.Sprite;
import flash.events.TimerEvent;
import flash.external.ExternalInterface;
import flash.net.registerClassAlias;
import flash.utils.ByteArray;
import flash.utils.Timer;

// Members marked [Transient] (a variable and a getter/setter pair) are left out
// of AMF3 serialization. Compiled with metadata kept (asc -md), as mxmlc keeps [Transient].
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

    private function run(e:TimerEvent):void {
        registerClassAlias("test.Item", Item);
        registerClassAlias("test.Meta", Meta);
        var item:Item = new Item();
        item.zeta = 7;
        item.alpha = "A";
        item.middle = true;
        item.marked = "TRANSIENT_VAR";
        item.accessor = "ACCESSOR";
        item.markedAccessor = new Meta();
        var b:ByteArray = new ByteArray();
        b.writeObject(item);
        // Flash Player writes the sealed members in its own hash order, so only the length is printed.
        out("bytes " + b.length);
        b.position = 0;
        var o:Object = b.readObject();
        out("read Item=" + (o is Item) + " zeta=" + o.zeta + " alpha=" + o.alpha + " middle=" + o.middle +
            " marked=" + o.marked + " accessor=" + o.accessor + " markedAccessor=" + o.markedAccessor +
            " markedSetter=" + o.markedSetter);
    }
}
}

class Meta {
    public var owner:String = "META";
}

class Item {
    public var zeta:int;
    public var alpha:String;
    [Transient]
    public var marked:String;
    public var middle:Boolean;

    private var _a:String;
    public function get accessor():String { return _a; }
    public function set accessor(v:String):void { _a = v; }

    private var _t:Meta;
    [Transient]
    public function get markedAccessor():Meta { return _t; }
    public function set markedAccessor(v:Meta):void { _t = v; }

    private var _s:String = "SETTER";
    public function get markedSetter():String { return _s; }
    [Transient]
    public function set markedSetter(v:String):void { _s = v; }

    public function get readOnly():String { return "RO"; }
}
