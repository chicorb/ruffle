package {
import flash.display.Sprite;
import flash.events.MouseEvent;
import flash.text.TextField;
import flash.text.TextFormat;

// TextField.mouseWheelEnabled: a field with mouseWheelEnabled = false does not scroll
// with the mouse wheel, but the MOUSE_WHEEL event is still dispatched (and bubbles), as
// Flex expects: DataGridItemRenderer and mx.controls.Text set it to false so that the list
// or the container scrolls instead.
// Note: the expected output follows the documentation. Flash Player 32 on Linux could not be
// used to produce it: it does not deliver the wheel to text fields, and its getter always
// returns false there.
public class Test extends Sprite {
    private var a:TextField;
    private var b:TextField;

    public function Test() {
        var parent:Sprite = new Sprite();
        addChild(parent);
        a = field("a", 0, false);
        b = field("b", 100, true);
        parent.addChild(a);
        parent.addChild(b);
        trace("a.mouseWheelEnabled = " + a.mouseWheelEnabled + ", b.mouseWheelEnabled = " + b.mouseWheelEnabled);
        a.mouseWheelEnabled = true;
        a.mouseWheelEnabled = false;
        trace("a.mouseWheelEnabled after true and false = " + a.mouseWheelEnabled);
        parent.addEventListener(MouseEvent.MOUSE_WHEEL, function(e:MouseEvent):void {
            trace("MOUSE_WHEEL on " + TextField(e.target).name + ": scrollV a=" + a.scrollV + " b=" + b.scrollV);
        });
        stage.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent):void {
            trace("done: scrollV a=" + a.scrollV + " b=" + b.scrollV);
        });
    }

    private static function field(name:String, x:Number, wheel:Boolean):TextField {
        var tf:TextField = new TextField();
        tf.name = name;
        tf.x = x;
        tf.width = 100;
        tf.height = 40;
        tf.multiline = true;
        tf.wordWrap = true;
        tf.border = true;
        tf.defaultTextFormat = new TextFormat("_sans", 12);
        var s:String = "";
        for (var i:int = 1; i <= 10; i++) {
            s += name + " line " + i + (i < 10 ? "\r" : "");
        }
        tf.text = s;
        tf.mouseWheelEnabled = wheel;
        return tf;
    }
}
}
